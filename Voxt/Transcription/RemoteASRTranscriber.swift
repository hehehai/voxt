import Foundation
import AVFoundation
import AudioToolbox
import Combine
import zlib

@MainActor
class RemoteASRTranscriber: NSObject, ObservableObject, TranscriberProtocol {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var transcribedText = ""
    @Published var isEnhancing = false
    @Published var isRequesting = false
    @Published var isFinalizingTranscription = false

    var onTranscriptionFinished: ((String) -> Void)?
    var onStartFailure: ((String) -> Void)?
    var onRuntimeFailure: ((String) -> Void)?
    var doubaoDictionaryEntryProvider: (() -> [DictionaryEntry])?

    private var recorder: AVAudioRecorder?
    private let audioEngine = AVAudioEngine()
    private var doubaoStreamingContext: DoubaoStreamingContext?
    private var aliyunStreamingContext: AliyunFunStreamingContext?
    private var aliyunQwenStreamingContext: AliyunQwenStreamingContext?
    private var meterTimer: Timer?
    private var openAIPreviewTask: Task<Void, Never>?
    private var openAIPreviewInFlight = false
    private var openAIPreviewLastText = ""
    private var recordingFileURL: URL?
    private var transcribeTask: Task<Void, Never>?
    private var stopRequested = false
    private var activeProvider: RemoteASRProvider?
    private var preferredInputDeviceID: AudioDeviceID?
    private let streamingFinalWaitTimeout: TimeInterval = 20
    private var lastPresentedRuntimeErrorMessage = ""
    private var recordingGenerationID = UUID()

    func setPreferredInputDevice(_ deviceID: AudioDeviceID?) {
        preferredInputDeviceID = deviceID
    }

    func requestPermissions() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func startRecording() {
        guard !isRecording else { return }
        recordingGenerationID = UUID()
        cleanupActiveUploadTask()
        cleanupDoubaoStreamingState()
        cleanupAliyunStreamingState()
        transcribedText = ""
        audioLevel = 0
        isRequesting = false
        stopRequested = false
        lastPresentedRuntimeErrorMessage = ""
        let provider = selectedProvider
        let configuration = selectedProviderConfiguration(for: provider)
        let hintPayload = resolvedHintPayload(for: provider, configuration: configuration)
        activeProvider = provider

        if provider == .doubaoASR {
            do {
                try startDoubaoStreaming(configuration: configuration, hintPayload: hintPayload)
            } catch {
                VoxtLog.error("Doubao streaming setup failed: \(error.localizedDescription)")
                cleanupRecorderState()
                cleanupDoubaoStreamingState()
                activeProvider = nil
                notifyStartFailure(error)
            }
            return
        }

        if provider == .aliyunBailianASR {
            do {
                if isAliyunQwenRealtimeModel(configuration.model) {
                    try startAliyunQwenRealtimeStreaming(configuration: configuration, hintPayload: hintPayload)
                } else {
                    try startAliyunFunStreaming(configuration: configuration, hintPayload: hintPayload)
                }
            } catch {
                VoxtLog.error("Aliyun realtime streaming setup failed: \(error.localizedDescription)")
                cleanupRecorderState()
                cleanupAliyunStreamingState()
                activeProvider = nil
                notifyStartFailure(error)
            }
            return
        }

        do {
            try startFileRecordingMode()
            if provider == .openAIWhisper, configuration.openAIChunkPseudoRealtimeEnabled {
                startOpenAIPreviewLoop(configuration: configuration)
            }
        } catch {
            VoxtLog.error("Remote ASR recorder setup failed: \(error.localizedDescription)")
            cleanupRecorderState()
            activeProvider = nil
            notifyStartFailure(error)
        }
    }

    func stopRecording() {
        let hasPendingRealtimeSession =
            doubaoStreamingContext != nil ||
            aliyunStreamingContext != nil ||
            aliyunQwenStreamingContext != nil
        guard isRecording || hasPendingRealtimeSession || recorder != nil else { return }
        stopRequested = true
        let generationID = recordingGenerationID

        if activeProvider == .doubaoASR, let context = doubaoStreamingContext {
            isRequesting = true
            stopDoubaoStreaming(context)
            scheduleStreamingCompletion(generationID: generationID) {
                let finalText = await self.resolveStreamingResult(
                    warningMessage: "Doubao final result wait failed"
                ) {
                    try await context.responseState.waitForFinalResult(timeoutSeconds: self.streamingFinalWaitTimeout)
                } fallback: {
                    await context.responseState.currentText()
                }
                let currentText = await context.responseState.currentText()
                return finalText.isEmpty ? currentText : finalText
            }
            return
        }

        if activeProvider == .aliyunBailianASR, let context = aliyunStreamingContext {
            isRequesting = true
            stopAliyunFunStreaming(context)
            scheduleStreamingCompletion(generationID: generationID) {
                await self.resolveStreamingResult(
                    warningMessage: "Aliyun fun final result wait failed"
                ) {
                    try await context.responseState.waitForFinalResult(timeoutSeconds: self.streamingFinalWaitTimeout)
                } fallback: {
                    await context.responseState.currentText()
                }
            }
            return
        }

        if activeProvider == .aliyunBailianASR, let context = aliyunQwenStreamingContext {
            isRequesting = true
            stopAliyunQwenStreaming(context)
            scheduleStreamingCompletion(generationID: generationID) {
                await self.resolveStreamingResult(
                    warningMessage: "Aliyun qwen realtime final result wait failed"
                ) {
                    try await context.responseState.waitForFinalResult(timeoutSeconds: self.streamingFinalWaitTimeout)
                } fallback: {
                    await context.responseState.currentText()
                }
            }
            return
        }

        guard let fileURL = stopFileRecordingCapture() else {
            finish(with: transcribedText, generationID: generationID)
            return
        }

        isRequesting = true
        transcribeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.transcribeRecordedAudio(fileURL: fileURL)
                await MainActor.run {
                    guard self.isCurrentGeneration(generationID) else { return }
                    self.transcribedText = result
                    self.finish(with: result, generationID: generationID)
                }
            } catch {
                await MainActor.run {
                    guard self.isCurrentGeneration(generationID) else { return }
                    VoxtLog.error("Remote ASR transcription failed: \(error.localizedDescription)")
                    self.notifyRuntimeFailure(error)
                    self.finish(with: self.transcribedText, generationID: generationID)
                }
            }
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    func restartCaptureForPreferredInputDevice() throws {
        if let context = doubaoStreamingContext {
            stopDoubaoAudioCapture()
            try startDoubaoAudioCapture()
            _ = context
            return
        }

        if let context = aliyunStreamingContext {
            stopAliyunAudioCapture()
            try startAliyunAudioCapture(context: context)
            return
        }

        if let context = aliyunQwenStreamingContext {
            stopAliyunAudioCapture()
            try startAliyunQwenAudioCapture(context: context)
            return
        }

        throw NSError(
            domain: "Voxt.RemoteASR",
            code: -101,
            userInfo: [NSLocalizedDescriptionKey: "Remote ASR file recording cannot switch microphones during an active session."]
        )
    }

    private func stopDoubaoStreaming(_ context: DoubaoStreamingContext) {
        isRecording = false
        stopDoubaoAudioCapture()
        flushBufferedDoubaoAudioIfNeeded(context: context, includeTrailingPartial: true)
        VoxtLog.info("Doubao streaming stop requested. sentAudioPackets=\(context.audioPacketCount)", verbose: true)

        let finalSequence = DoubaoASRConfiguration.finalStreamingSequence(
            nextAudioSequence: context.nextAudioSequence
        )
        VoxtLog.info(
            "Doubao streaming final packet. lastSequence=\(context.lastAudioSequence), nextSequence=\(context.nextAudioSequence), finalSequence=\(finalSequence)",
            verbose: true
        )
        guard !context.isClosed else {
            VoxtLog.info("Doubao streaming socket already closed before final packet, skip final send.", verbose: true)
            return
        }

        let finalPacket = buildDoubaoPacket(
            messageType: DoubaoProtocol.messageTypeAudioOnlyClientRequest,
            messageFlags: DoubaoProtocol.flagNegativeAudioPacket,
            serialization: DoubaoProtocol.serializationNone,
            compression: DoubaoProtocol.compressionNone,
            sequence: finalSequence,
            payload: Data()
        )
        sendDoubaoPacket(finalPacket, through: context.ws) { error, isBenign in
            Task { [responseState = context.responseState] in
                if isBenign {
                    await responseState.markSocketClosed()
                } else {
                    await responseState.markCompletedWithError(error)
                }
            }
        }
    }

    private func stopAliyunFunStreaming(_ context: AliyunFunStreamingContext) {
        isRecording = false
        stopAliyunAudioCapture()
        guard !context.isClosed else { return }

        sendAliyunFunControl(action: "finish-task", through: context.ws, taskID: context.taskID) { error in
            Task { [responseState = context.responseState] in
                if let error {
                    await responseState.markCompletedWithError(error)
                } else {
                    await responseState.markFinishRequested()
                }
            }
        }
    }

    private func stopAliyunQwenStreaming(_ context: AliyunQwenStreamingContext) {
        isRecording = false
        stopAliyunAudioCapture()
        guard !context.isClosed else { return }

        sendAliyunQwenEvent(
            type: "session.finish",
            through: context.ws
        ) { error in
            Task { [responseState = context.responseState] in
                if let error {
                    await responseState.markCompletedWithError(error)
                } else {
                    await responseState.markFinishRequested()
                }
            }
        }
    }

    private func scheduleStreamingCompletion(
        generationID: UUID,
        result: @escaping @Sendable () async -> String
    ) {
        transcribeTask = Task { [weak self] in
            guard let self else { return }
            let finalText = await result()
            await MainActor.run {
                guard self.isCurrentGeneration(generationID) else { return }
                self.transcribedText = finalText
                self.finish(with: finalText, generationID: generationID)
            }
        }
    }

    private func resolveStreamingResult(
        warningMessage: String,
        waitForFinal: @escaping @Sendable () async throws -> String,
        fallback: @escaping @Sendable () async -> String
    ) async -> String {
        do {
            return try await waitForFinal()
        } catch {
            VoxtLog.warning("\(warningMessage): \(error.localizedDescription)")
            notifyRuntimeFailure(error)
            return await fallback()
        }
    }

    private func transcribeRecordedAudio(fileURL: URL) async throws -> String {
        let provider = activeProvider ?? selectedProvider
        let configuration = selectedProviderConfiguration(for: provider)
        let hintPayload = resolvedHintPayload(for: provider, configuration: configuration)
        return try await transcribeAudioFile(
            fileURL: fileURL,
            provider: provider,
            configuration: configuration,
            hintPayload: hintPayload
        )
    }

    private func transcribeAudioFile(
        fileURL: URL,
        provider: RemoteASRProvider,
        configuration: RemoteProviderConfiguration,
        hintPayload: ResolvedASRHintPayload
    ) async throws -> String {
        switch provider {
        case .openAIWhisper:
            return try await transcribeOpenAI(fileURL: fileURL, configuration: configuration, hintPayload: hintPayload)
        case .glmASR:
            return try await transcribeGLM(fileURL: fileURL, configuration: configuration, hintPayload: hintPayload)
        case .doubaoASR:
            return try await transcribeDoubao(fileURL: fileURL, configuration: configuration, hintPayload: hintPayload)
        case .aliyunBailianASR:
            return try await transcribeAliyunBailian(fileURL: fileURL, configuration: configuration)
        }
    }

    private func startFileRecordingMode() throws {
        let fileURL = makeTemporaryRecordingURL()
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            throw NSError(domain: "Voxt.RemoteASR", code: -100, userInfo: [NSLocalizedDescriptionKey: "Recorder start failed"])
        }
        self.recorder = recorder
        self.recordingFileURL = fileURL
        self.isRecording = true
        startMeteringTimer()
    }

    private var selectedProvider: RemoteASRProvider {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.remoteASRSelectedProvider) ?? ""
        return RemoteASRProvider(rawValue: raw) ?? .openAIWhisper
    }

    private func selectedProviderConfiguration(for provider: RemoteASRProvider) -> RemoteProviderConfiguration {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.remoteASRProviderConfigurations) ?? ""
        let all = RemoteModelConfigurationStore.loadConfigurations(from: raw)
        return RemoteModelConfigurationStore.resolvedASRConfiguration(provider: provider, stored: all)
    }

    func currentMeetingConfiguration() -> (provider: RemoteASRProvider, configuration: RemoteProviderConfiguration) {
        let provider = selectedProvider
        let configuration = selectedProviderConfiguration(for: provider)
        return (
            provider,
            RemoteASRMeetingConfiguration.resolvedMeetingConfiguration(
                provider: provider,
                configuration: configuration
            )
        )
    }

    func transcribeMeetingAudioFile(_ fileURL: URL) async throws -> String {
        let currentMeeting = currentMeetingConfiguration()
        let provider = currentMeeting.provider
        let configuration = currentMeeting.configuration
        guard configuration.isConfigured else {
            throw NSError(
                domain: "Voxt.RemoteASR",
                code: -101,
                userInfo: [NSLocalizedDescriptionKey: "Remote ASR is not configured yet."]
            )
        }
        guard RemoteASRMeetingConfiguration.hasValidMeetingModel(
            provider: provider,
            configuration: configuration
        ) else {
            throw NSError(
                domain: "Voxt.RemoteASR",
                code: -102,
                userInfo: [NSLocalizedDescriptionKey: RemoteASRMeetingConfiguration.startBlockedMessage(for: provider, configuration: configuration)]
            )
        }
        let hintPayload = resolvedHintPayload(for: provider, configuration: configuration)
        return try await transcribeAudioFile(
            fileURL: fileURL,
            provider: provider,
            configuration: configuration,
            hintPayload: hintPayload
        )
    }

    private func resolvedHintPayload(
        for provider: RemoteASRProvider,
        configuration: RemoteProviderConfiguration
    ) -> ResolvedASRHintPayload {
        let settingsRaw = UserDefaults.standard.string(forKey: AppPreferenceKey.asrHintSettings)
        let settings = ASRHintSettingsStore.resolvedSettings(
            for: ASRHintTarget.from(engine: .remote, remoteProvider: provider),
            rawValue: settingsRaw
        )
        let userLanguageCodes = UserMainLanguageOption.storedSelection(
            from: UserDefaults.standard.string(forKey: AppPreferenceKey.userMainLanguageCodes)
        )
        return ASRHintResolver.resolve(
            target: ASRHintTarget.from(engine: .remote, remoteProvider: provider),
            settings: settings,
            userLanguageCodes: userLanguageCodes,
            mlxModelRepo: configuration.model
        )
    }

    private func doubaoRequestPayload(
        configuration: RemoteProviderConfiguration,
        hintPayload: ResolvedASRHintPayload,
        requestID: String,
        userID: String,
        audioFormat: String,
        enableNonstream: Bool = false
    ) -> [String: Any] {
        let dictionaryPayload = DoubaoDictionaryRequestPayloadBuilder.build(
            configuration: configuration,
            entries: doubaoDictionaryEntryProvider?() ?? [],
            dictionaryEnabled: UserDefaults.standard.object(forKey: AppPreferenceKey.dictionaryRecognitionEnabled) as? Bool ?? true
        )
        return DoubaoASRConfiguration.fullRequestPayload(
            requestID: requestID,
            userID: userID,
            language: hintPayload.language,
            chineseOutputVariant: hintPayload.chineseOutputVariant,
            audioFormat: audioFormat,
            enableNonstream: enableNonstream,
            dictionaryPayload: dictionaryPayload
        )
    }

    private func transcribeOpenAI(
        fileURL: URL,
        configuration: RemoteProviderConfiguration,
        hintPayload: ResolvedASRHintPayload
    ) async throws -> String {
        let endpoint = URL(string: normalizedEndpoint(configuration.endpoint, defaultValue: "https://api.openai.com/v1/audio/transcriptions"))!
        let token = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw NSError(domain: "Voxt.RemoteASR", code: -1, userInfo: [NSLocalizedDescriptionKey: "OpenAI API key is empty."])
        }
        return try await transcribeOpenAIJSON(
            endpoint: endpoint,
            authorizationValue: "Bearer \(token)",
            fileURL: fileURL,
            model: configuration.model,
            hintPayload: hintPayload
        )
    }

    private func transcribeOpenAIJSON(
        endpoint: URL,
        authorizationValue: String,
        fileURL: URL,
        model: String,
        hintPayload: ResolvedASRHintPayload
    ) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        let effectiveModel = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "whisper-1" : model
        var extraFields: [String: String] = [
            "response_format": "json",
            "stream": "false"
        ]
        if let language = hintPayload.language?.trimmingCharacters(in: .whitespacesAndNewlines), !language.isEmpty {
            extraFields["language"] = language
        }
        if let prompt = hintPayload.prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
            extraFields["prompt"] = prompt
        }
        let body = try makeMultipartBody(
            fileURL: fileURL,
            boundary: boundary,
            model: effectiveModel,
            extraFields: extraFields
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain", forHTTPHeaderField: "Accept")
        request.setValue(authorizationValue, forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let (data, response) = try await VoxtNetworkSession.active.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Voxt.RemoteASR", code: -10, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response."])
        }
        guard (200...299).contains(http.statusCode) else {
            let payload = String(data: data.prefix(500), encoding: .utf8) ?? ""
            throw NSError(
                domain: "Voxt.RemoteASR",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(payload)"]
            )
        }

        if let object = try? JSONSerialization.jsonObject(with: data),
           let text = extractText(in: object),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let plainText = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !plainText.isEmpty, !isLikelyJSONObjectString(plainText) {
            return plainText
        }

        throw NSError(
            domain: "Voxt.RemoteASR",
            code: -11,
            userInfo: [NSLocalizedDescriptionKey: "OpenAI transcription response did not contain text."]
        )
    }

    private func transcribeGLM(
        fileURL: URL,
        configuration: RemoteProviderConfiguration,
        hintPayload: ResolvedASRHintPayload
    ) async throws -> String {
        let endpoint = URL(string: normalizedEndpoint(configuration.endpoint, defaultValue: "https://open.bigmodel.cn/api/paas/v4/audio/transcriptions"))!
        let token = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw NSError(domain: "Voxt.RemoteASR", code: -2, userInfo: [NSLocalizedDescriptionKey: "GLM API key is empty."])
        }
        var extraFields = ["stream": "true"]
        if let prompt = hintPayload.prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
            extraFields["prompt"] = prompt
        }
        return try await transcribeViaMultipartStream(
            endpoint: endpoint,
            authorizationValue: "Bearer \(token)",
            fileURL: fileURL,
            model: configuration.model,
            extraFields: extraFields
        )
    }

    private func transcribeDoubao(
        fileURL: URL,
        configuration: RemoteProviderConfiguration,
        hintPayload: ResolvedASRHintPayload
    ) async throws -> String {
        let accessToken = configuration.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let appID = configuration.appID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resourceID = resolvedDoubaoResourceID(from: configuration)
        let endpoint = resolvedDoubaoEndpoint(from: configuration)

        guard !accessToken.isEmpty else {
            throw NSError(domain: "Voxt.RemoteASR", code: -3, userInfo: [NSLocalizedDescriptionKey: "Doubao Access Token is empty."])
        }
        guard !appID.isEmpty else {
            throw NSError(domain: "Voxt.RemoteASR", code: -4, userInfo: [NSLocalizedDescriptionKey: "Doubao App ID is empty."])
        }
        if DoubaoASRConfiguration.isMeetingFlashModel(resourceID) {
            return try await transcribeDoubaoMeetingFlash(
                fileURL: fileURL,
                appID: appID,
                accessToken: accessToken,
                resourceID: resourceID,
                endpoint: DoubaoASRConfiguration.resolvedMeetingFlashEndpoint(configuration.endpoint),
                hintPayload: hintPayload,
                configuration: configuration
            )
        }
        return try await transcribeDoubaoWebSocket(
            fileURL: fileURL,
            appID: appID,
            accessToken: accessToken,
            resourceID: resourceID,
            endpoint: endpoint,
            hintPayload: hintPayload,
            configuration: configuration
        )
    }

    private func transcribeDoubaoMeetingFlash(
        fileURL: URL,
        appID: String,
        accessToken: String,
        resourceID: String,
        endpoint: String,
        hintPayload: ResolvedASRHintPayload,
        configuration: RemoteProviderConfiguration
    ) async throws -> String {
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "Voxt.RemoteASR", code: -34, userInfo: [NSLocalizedDescriptionKey: "Invalid Doubao meeting endpoint URL."])
        }

        let audioData = try Data(contentsOf: fileURL)
        var body = doubaoRequestPayload(
            configuration: configuration,
            hintPayload: hintPayload,
            requestID: UUID().uuidString.lowercased(),
            userID: "voxt-meeting",
            audioFormat: DoubaoASRConfiguration.requestAudioFormat
        )
        body["audio"] = ["data": audioData.base64EncodedString()]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "X-Api-Request-Id")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await VoxtNetworkSession.active.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Voxt.RemoteASR", code: -35, userInfo: [NSLocalizedDescriptionKey: "Invalid Doubao meeting HTTP response."])
        }
        guard (200...299).contains(http.statusCode) else {
            let payload = String(data: data.prefix(500), encoding: .utf8) ?? ""
            throw NSError(
                domain: "Voxt.RemoteASR",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Doubao meeting ASR request failed (HTTP \(http.statusCode)): \(payload)"]
            )
        }

        let object = try JSONSerialization.jsonObject(with: data)
        if let text = extractDoubaoText(in: object), !text.isEmpty {
            return text
        }
        if let text = extractText(in: object), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private func transcribeAliyunBailian(fileURL: URL, configuration: RemoteProviderConfiguration) async throws -> String {
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? RemoteASRProvider.aliyunBailianASR.suggestedModel
            : configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAliyunFunRealtimeModel(model)
                || isAliyunQwenRealtimeModel(model)
                || isAliyunFileTranscriptionModel(model)
                || AliyunMeetingASRConfiguration.routing(for: model) == .compatibleShortAudio
        else {
            throw NSError(
                domain: "Voxt.RemoteASR",
                code: -33,
                userInfo: [NSLocalizedDescriptionKey: "Aliyun ASR in Voxt supports Qwen/Fun/Paraformer transcription models only."]
            )
        }

        let token = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw NSError(domain: "Voxt.RemoteASR", code: -30, userInfo: [NSLocalizedDescriptionKey: "Aliyun Bailian API key is empty."])
        }
        if let validationError = AliyunMeetingASRConfiguration.validationError(model: model, endpoint: configuration.endpoint) {
            throw NSError(domain: "Voxt.RemoteASR", code: -36, userInfo: [NSLocalizedDescriptionKey: validationError])
        }
        if isAliyunFileTranscriptionModel(model) {
            return try await AliyunMeetingASRClient.transcribe(
                fileURL: fileURL,
                apiKey: token,
                model: model,
                endpoint: configuration.endpoint
            )
        }
        let endpoint = URL(string: AliyunMeetingASRConfiguration.resolvedCompatibleEndpoint(configuration.endpoint, model: model))!
        let fileData = try Data(contentsOf: fileURL)
        let dataURI = "data:\(audioMIMEType(for: fileURL));base64,\(fileData.base64EncodedString())"

        let payload: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_audio",
                            "input_audio": [
                                "data": dataURI,
                                "format": "wav"
                            ]
                        ]
                    ]
                ]
            ],
            "stream": false
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await VoxtNetworkSession.active.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Voxt.RemoteASR", code: -31, userInfo: [NSLocalizedDescriptionKey: "Invalid Aliyun Bailian HTTP response."])
        }
        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw NSError(
                domain: "Voxt.RemoteASR",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Aliyun Bailian ASR request failed (HTTP \(http.statusCode)): \(message)"]
            )
        }

        let object = try JSONSerialization.jsonObject(with: data)
        if let text = AliyunMeetingASRClient.extractText(from: object), !text.isEmpty {
            return text
        }
        throw NSError(domain: "Voxt.RemoteASR", code: -32, userInfo: [NSLocalizedDescriptionKey: "Aliyun Bailian ASR returned no text content."])
    }

    private func startAliyunFunStreaming(
        configuration: RemoteProviderConfiguration,
        hintPayload: ResolvedASRHintPayload
    ) throws {
        let token = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw NSError(domain: "Voxt.RemoteASR", code: -40, userInfo: [NSLocalizedDescriptionKey: "Aliyun Bailian API key is empty."])
        }

        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? RemoteASRProvider.aliyunBailianASR.suggestedModel
            : configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = resolvedAliyunFunRealtimeEndpoint(configuration.endpoint)
        guard let wsURL = URL(string: endpoint) else {
            throw NSError(domain: "Voxt.RemoteASR", code: -41, userInfo: [NSLocalizedDescriptionKey: "Invalid Aliyun realtime WebSocket endpoint URL."])
        }

        var request = URLRequest(url: wsURL)
        request.timeoutInterval = 45
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let managedSocket = VoxtNetworkSession.makeWebSocketTask(with: request)
        let ws = managedSocket.task
        ws.resume()

        let taskID = AliyunMeetingASRConfiguration.makeRealtimeTaskID()
        let responseState = AliyunFunResponseState { [weak self] error in
            Task { @MainActor [weak self] in
                self?.notifyRuntimeFailure(error)
            }
        }
        let context = AliyunFunStreamingContext(
            session: managedSocket.session,
            ws: ws,
            taskID: taskID,
            responseState: responseState,
            generationID: recordingGenerationID
        )
        aliyunStreamingContext = context
        receiveAliyunFunMessages(context)

        var parameters: [String: Any] = [
            "sample_rate": 16000,
            "format": "pcm"
        ]
        if !hintPayload.languageHints.isEmpty {
            parameters["language_hints"] = hintPayload.languageHints
        }

        sendAliyunFunControl(
            action: "run-task",
            through: ws,
            taskID: taskID,
            model: model,
            parameters: parameters
        ) { error in
            Task { [responseState] in
                if let error {
                    await responseState.markCompletedWithError(error)
                } else {
                    await responseState.markRunRequested()
                }
            }
        }
    }

    private func receiveAliyunFunMessages(_ context: AliyunFunStreamingContext) {
        context.ws.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard self.isCurrentGeneration(context.generationID),
                          self.aliyunStreamingContext === context
                    else { return }
                    do {
                        if case .string(let text) = message {
                            try await self.handleAliyunFunMessage(text, context: context)
                        } else if case .data(let data) = message,
                                  let text = String(data: data, encoding: .utf8) {
                            try await self.handleAliyunFunMessage(text, context: context)
                        }
                    } catch {
                        await context.responseState.markCompletedWithError(error)
                    }
                    if !context.isClosed {
                        self.receiveAliyunFunMessages(context)
                    }
                }
            case .failure(let error):
                Task {
                    guard await MainActor.run(body: { [weak self] in
                        guard let self else { return false }
                        return self.isCurrentGeneration(context.generationID) && self.aliyunStreamingContext === context
                    }) else { return }
                    await context.responseState.markCompletedWithError(error)
                }
            }
        }
    }

    private func handleAliyunFunMessage(_ text: String, context: AliyunFunStreamingContext) async throws {
        guard let data = text.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        let event = AliyunMeetingASRConfiguration.realtimeSocketEvent(from: object)
        let payload = object["payload"] as? [String: Any] ?? [:]

        if event == "task-failed" || event == "error" {
            let errorText = AliyunMeetingASRConfiguration.realtimeSocketErrorMessage(from: object)
                ?? "Aliyun fun ASR task failed."
            throw NSError(domain: "Voxt.RemoteASR", code: -42, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        if event == "task-started", !context.didStartAudioStream {
            guard !stopRequested else {
                VoxtLog.info("Aliyun fun task-started ignored because stop was already requested.", verbose: true)
                return
            }
            do {
                try startAliyunAudioCapture(context: context)
                context.didStartAudioStream = true
            } catch {
                throw error
            }
            return
        }

        if event == "result-generated" {
            let sentence = (payload["output"] as? [String: Any]).flatMap { output -> [String: Any]? in
                output["sentence"] as? [String: Any]
            } ?? [:]
            let partialText = (sentence["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let isSentenceEnd = sentence["sentence_end"] as? Bool ?? false
            if !partialText.isEmpty {
                let merged = await context.responseState.updateWithSentence(partialText, isSentenceEnd: isSentenceEnd)
                transcribedText = merged
            }
            return
        }

        if event == "task-finished" {
            context.isClosed = true
            await context.responseState.markTaskFinished()
            return
        }
    }

    private func startAliyunAudioCapture(context: AliyunFunStreamingContext) throws {
        let inputNode = audioEngine.inputNode
        applyPreferredInputDeviceIfNeeded(inputNode: inputNode)
        let inputFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let pcmData = Self.makeDoubaoPCM16MonoData(from: buffer) else { return }
            Task { @MainActor in
                guard self.isRecording,
                      let ctx = self.aliyunStreamingContext,
                      !ctx.isClosed
                else { return }
                self.audioLevel = self.audioLevelFromPCM16(pcmData)
                ctx.ws.send(.data(pcmData)) { error in
                    if let error {
                        Task { [responseState = ctx.responseState] in
                            await responseState.markCompletedWithError(error)
                        }
                    }
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    private func stopAliyunAudioCapture() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioLevel = 0
    }

    private func sendAliyunFunControl(
        action: String,
        through ws: URLSessionWebSocketTask,
        taskID: String,
        model: String? = nil,
        parameters: [String: Any]? = nil,
        onError: @escaping (Error?) -> Void
    ) {
        let payload = AliyunMeetingASRConfiguration.funRealtimeControlPayload(
            action: action,
            taskID: taskID,
            model: model,
            parameters: parameters
        )
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            guard let text = String(data: data, encoding: .utf8) else {
                onError(NSError(domain: "Voxt.RemoteASR", code: -43, userInfo: [NSLocalizedDescriptionKey: "Failed to encode Aliyun fun control message."]))
                return
            }
            ws.send(.string(text)) { error in
                onError(error)
            }
        } catch {
            onError(error)
        }
    }

    private func startAliyunQwenRealtimeStreaming(
        configuration: RemoteProviderConfiguration,
        hintPayload: ResolvedASRHintPayload
    ) throws {
        let token = configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw NSError(domain: "Voxt.RemoteASR", code: -44, userInfo: [NSLocalizedDescriptionKey: "Aliyun Bailian API key is empty."])
        }

        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "qwen3-asr-flash-realtime"
            : configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let endpoint = resolvedAliyunQwenRealtimeEndpoint(configuration.endpoint, model: model)
        guard let wsURL = URL(string: endpoint) else {
            throw NSError(domain: "Voxt.RemoteASR", code: -45, userInfo: [NSLocalizedDescriptionKey: "Invalid Aliyun Qwen realtime WebSocket endpoint URL."])
        }

        var request = URLRequest(url: wsURL)
        request.timeoutInterval = 45
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let managedSocket = VoxtNetworkSession.makeWebSocketTask(with: request)
        let ws = managedSocket.task
        ws.resume()

        let responseState = AliyunQwenResponseState { [weak self] error in
            Task { @MainActor [weak self] in
                self?.notifyRuntimeFailure(error)
            }
        }
        let context = AliyunQwenStreamingContext(
            session: managedSocket.session,
            ws: ws,
            responseState: responseState,
            generationID: recordingGenerationID
        )
        aliyunQwenStreamingContext = context
        receiveAliyunQwenMessages(context)
        sendAliyunQwenSessionUpdate(through: ws, hintPayload: hintPayload) { error in
            Task { [responseState] in
                if let error {
                    await responseState.markCompletedWithError(error)
                }
            }
        }
    }

    private func receiveAliyunQwenMessages(_ context: AliyunQwenStreamingContext) {
        context.ws.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard self.isCurrentGeneration(context.generationID),
                          self.aliyunQwenStreamingContext === context
                    else { return }
                    do {
                        if case .string(let text) = message {
                            try await self.handleAliyunQwenMessage(text, context: context)
                        } else if case .data(let data) = message,
                                  let text = String(data: data, encoding: .utf8) {
                            try await self.handleAliyunQwenMessage(text, context: context)
                        }
                    } catch {
                        await context.responseState.markCompletedWithError(error)
                    }
                    if !context.isClosed {
                        self.receiveAliyunQwenMessages(context)
                    }
                }
            case .failure(let error):
                Task {
                    guard await MainActor.run(body: { [weak self] in
                        guard let self else { return false }
                        return self.isCurrentGeneration(context.generationID) && self.aliyunQwenStreamingContext === context
                    }) else { return }
                    await context.responseState.markCompletedWithError(error)
                }
            }
        }
    }

    private func handleAliyunQwenMessage(_ text: String, context: AliyunQwenStreamingContext) async throws {
        guard let data = text.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        let type = (object["type"] as? String ?? "").lowercased()
        if type == "error" {
            let detail = (object["message"] as? String) ?? "Aliyun Qwen realtime ASR task failed."
            throw NSError(domain: "Voxt.RemoteASR", code: -46, userInfo: [NSLocalizedDescriptionKey: detail])
        }

        if type == "session.updated", !context.didStartAudioStream {
            guard !stopRequested else {
                VoxtLog.info("Aliyun qwen session.updated ignored because stop was already requested.", verbose: true)
                return
            }
            try startAliyunQwenAudioCapture(context: context)
            context.didStartAudioStream = true
            return
        }

        if type == "conversation.item.input_audio_transcription.text" {
            let partial = (object["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !partial.isEmpty {
                let merged = await context.responseState.setPartial(partial)
                transcribedText = merged
            }
            return
        }

        if type == "conversation.item.input_audio_transcription.completed" {
            let final = (object["transcript"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !final.isEmpty {
                let merged = await context.responseState.commit(final)
                transcribedText = merged
            }
            return
        }

        if type == "session.finished" {
            context.isClosed = true
            await context.responseState.markSessionFinished()
            return
        }
    }

    private func startAliyunQwenAudioCapture(context: AliyunQwenStreamingContext) throws {
        let inputNode = audioEngine.inputNode
        applyPreferredInputDeviceIfNeeded(inputNode: inputNode)
        let inputFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let pcmData = Self.makeDoubaoPCM16MonoData(from: buffer) else { return }
            Task { @MainActor in
                guard self.isRecording,
                      let ctx = self.aliyunQwenStreamingContext,
                      !ctx.isClosed
                else { return }
                self.audioLevel = self.audioLevelFromPCM16(pcmData)
                self.sendAliyunQwenAudioAppend(pcmData, through: ctx.ws) { error in
                    if let error {
                        Task { [responseState = ctx.responseState] in
                            await responseState.markCompletedWithError(error)
                        }
                    }
                }
            }
        }
        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    private func sendAliyunQwenSessionUpdate(
        through ws: URLSessionWebSocketTask,
        hintPayload: ResolvedASRHintPayload,
        onError: @escaping (Error?) -> Void
    ) {
        var transcriptionPayload: [String: Any] = [:]
        if let language = hintPayload.language?.trimmingCharacters(in: .whitespacesAndNewlines), !language.isEmpty {
            transcriptionPayload["language"] = language
        }
        let payload: [String: Any] = [
            "event_id": UUID().uuidString.lowercased(),
            "type": "session.update",
            "session": [
                "modalities": ["text"],
                "input_audio_format": "pcm",
                "sample_rate": 16000,
                "input_audio_transcription": transcriptionPayload,
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.0,
                    "silence_duration_ms": 400
                ]
            ]
        ]
        sendAliyunQwenEvent(payload: payload, through: ws, onError: onError)
    }

    private func sendAliyunQwenAudioAppend(
        _ audio: Data,
        through ws: URLSessionWebSocketTask,
        onError: @escaping (Error?) -> Void
    ) {
        let payload: [String: Any] = [
            "event_id": UUID().uuidString.lowercased(),
            "type": "input_audio_buffer.append",
            "audio": audio.base64EncodedString()
        ]
        sendAliyunQwenEvent(payload: payload, through: ws, onError: onError)
    }

    private func sendAliyunQwenEvent(
        type: String,
        through ws: URLSessionWebSocketTask,
        onError: @escaping (Error?) -> Void
    ) {
        let payload: [String: Any] = [
            "event_id": UUID().uuidString.lowercased(),
            "type": type
        ]
        sendAliyunQwenEvent(payload: payload, through: ws, onError: onError)
    }

    private func sendAliyunQwenEvent(
        payload: [String: Any],
        through ws: URLSessionWebSocketTask,
        onError: @escaping (Error?) -> Void
    ) {
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            guard let text = String(data: data, encoding: .utf8) else {
                onError(NSError(domain: "Voxt.RemoteASR", code: -47, userInfo: [NSLocalizedDescriptionKey: "Failed to encode Aliyun Qwen realtime event."]))
                return
            }
            ws.send(.string(text)) { error in
                onError(error)
            }
        } catch {
            onError(error)
        }
    }


    private func transcribeDoubaoWebSocket(
        fileURL: URL,
        appID: String,
        accessToken: String,
        resourceID: String,
        endpoint: String,
        hintPayload: ResolvedASRHintPayload,
        configuration: RemoteProviderConfiguration
    ) async throws -> String {
        guard let wsURL = URL(string: endpoint) else {
            throw NSError(domain: "Voxt.RemoteASR", code: -5, userInfo: [NSLocalizedDescriptionKey: "Invalid Doubao endpoint URL."])
        }

        var request = URLRequest(url: wsURL)
        request.timeoutInterval = 45
        request.setValue(appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        let requestID = UUID().uuidString.lowercased()
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Connect-Id")
        VoxtLog.info(
            "Doubao websocket connect. endpoint=\(endpoint), resource=\(resourceID)"
        )

        let managedSocket = VoxtNetworkSession.makeWebSocketTask(with: request)
        let ws = managedSocket.task
        ws.resume()
        defer {
            ws.cancel(with: .goingAway, reason: nil)
            managedSocket.session.invalidateAndCancel()
        }

        let reqID = UUID().uuidString.lowercased()
        try await sendDoubaoFullRequest(
            ws: ws,
            reqID: reqID,
            sequence: 1,
            hintPayload: hintPayload,
            audioFormat: DoubaoASRConfiguration.requestAudioFormat,
            configuration: configuration
        )

        let responseState = DoubaoResponseState { [weak self] error in
            Task { @MainActor [weak self] in
                self?.notifyRuntimeFailure(error)
            }
        }
        let receiveTask = Task {
            do {
                while !Task.isCancelled {
                    let message = try await ws.receive()
                    guard case .data(let payloadData) = message else { continue }
                    if let parsed = try self.parseDoubaoServerPacket(payloadData) {
                        if let text = parsed.text, !text.isEmpty {
                            _ = await responseState.replace(text: text, isFinal: parsed.isFinal)
                        } else if parsed.isFinal {
                            await responseState.markFinal()
                        }
                    }
                }
            } catch {
                if let detail = await self.fetchDoubaoHandshakeFailureDetail(
                    error: error,
                    endpoint: endpoint,
                    resourceID: resourceID,
                    appID: appID,
                    accessToken: accessToken
                ) {
                    VoxtLog.warning("Doubao websocket receive failed. detail=\(detail)")
                    let detailedError = NSError(
                        domain: "Voxt.RemoteASR",
                        code: (error as NSError).code,
                        userInfo: [NSLocalizedDescriptionKey: detail]
                    )
                    await responseState.markCompletedWithError(detailedError)
                } else {
                    await responseState.markCompletedWithError(error)
                }
            }
        }

        let fileData = try Data(contentsOf: fileURL)
        let chunkSize = 3200
        var offset = 0
        var sequence: Int32 = 2
        while offset < fileData.count {
            let end = min(offset + chunkSize, fileData.count)
            let chunk = fileData[offset..<end]
            let isLast = end >= fileData.count
            try await sendDoubaoAudioPacket(
                ws: ws,
                payload: Data(chunk),
                isLast: isLast,
                sequence: sequence
            )
            if !isLast {
                sequence += 1
            }
            offset = end
            try? await Task.sleep(for: .milliseconds(24))
        }

        let finalText = try await responseState.waitForFinalResult(timeoutSeconds: 20)
        receiveTask.cancel()
        return finalText
    }

    private func startDoubaoStreaming(
        configuration: RemoteProviderConfiguration,
        hintPayload: ResolvedASRHintPayload
    ) throws {
        let accessToken = configuration.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let appID = configuration.appID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resourceID = resolvedDoubaoResourceID(from: configuration)

        guard !accessToken.isEmpty else {
            throw NSError(domain: "Voxt.RemoteASR", code: -3, userInfo: [NSLocalizedDescriptionKey: "Doubao Access Token is empty."])
        }
        guard !appID.isEmpty else {
            throw NSError(domain: "Voxt.RemoteASR", code: -4, userInfo: [NSLocalizedDescriptionKey: "Doubao App ID is empty."])
        }

        let endpoint = resolvedDoubaoStreamingEndpoint(from: configuration)
        guard let wsURL = URL(string: endpoint) else {
            throw NSError(domain: "Voxt.RemoteASR", code: -5, userInfo: [NSLocalizedDescriptionKey: "Invalid Doubao endpoint URL."])
        }

        var request = URLRequest(url: wsURL)
        request.timeoutInterval = 45
        request.setValue(appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        let requestID = UUID().uuidString.lowercased()
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Connect-Id")
        VoxtLog.info(
            "Doubao stream connect. endpoint=\(endpoint), resource=\(resourceID)"
        )

        let managedSocket = VoxtNetworkSession.makeWebSocketTask(with: request)
        let ws = managedSocket.task
        ws.resume()
        let context = DoubaoStreamingContext(
            session: managedSocket.session,
            ws: ws,
            responseState: DoubaoResponseState { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.notifyRuntimeFailure(error)
                }
            },
            generationID: recordingGenerationID
        )
        doubaoStreamingContext = context
        receiveDoubaoMessages(context, endpoint: endpoint, resourceID: resourceID, appID: appID, accessToken: accessToken)

        let reqID = UUID().uuidString.lowercased()
        let streamingHintPayload = ResolvedASRHintPayload(
            language: nil,
            languageHints: hintPayload.languageHints,
            chineseOutputVariant: hintPayload.chineseOutputVariant,
            prompt: hintPayload.prompt
        )
        sendDoubaoFullRequest(
            ws: ws,
            reqID: reqID,
            sequence: 1,
            hintPayload: streamingHintPayload,
            audioFormat: DoubaoASRConfiguration.streamingAudioFormat,
            configuration: configuration,
            enableNonstream: true
        ) { error, isBenign in
            Task { [responseState = context.responseState] in
                if isBenign {
                    context.isClosed = true
                    await responseState.markSocketClosed()
                } else {
                    await responseState.markCompletedWithError(error)
                }
            }
        }
        try ensureDoubaoAudioCaptureStarted(context, reason: "request-sent")
    }

    private func sendDoubaoPacket(
        _ packet: Data,
        through ws: URLSessionWebSocketTask,
        onError: @escaping (Error, Bool) -> Void
    ) {
        ws.send(.data(packet)) { error in
            if let error {
                Task { @MainActor in
                    let nsError = error as NSError
                    let isBenign = self.isBenignDoubaoSocketError(nsError)
                    onError(error, isBenign)
                }
            }
        }
    }

    private func startDoubaoAudioCapture() throws {
        let inputNode = audioEngine.inputNode
        applyPreferredInputDeviceIfNeeded(inputNode: inputNode)
        let inputFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            guard let pcmData = Self.makeDoubaoPCM16MonoData(from: buffer) else { return }
            Task { @MainActor in
                guard self.isRecording,
                      let context = self.doubaoStreamingContext,
                      !context.isClosed
                else { return }
                self.audioLevel = self.audioLevelFromPCM16(pcmData)
                self.queueDoubaoAudioData(pcmData, context: context)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    private func stopDoubaoAudioCapture() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioLevel = 0
    }

    private func ensureDoubaoAudioCaptureStarted(
        _ context: DoubaoStreamingContext,
        reason: String
    ) throws {
        guard !context.didStartAudioStream else { return }
        guard !stopRequested else {
            VoxtLog.info("Doubao audio capture start skipped because stop was already requested. reason=\(reason)", verbose: true)
            return
        }
        try startDoubaoAudioCapture()
        context.didStartAudioStream = true
        VoxtLog.info("Doubao audio capture started. reason=\(reason)", verbose: true)
    }

    private func applyPreferredInputDeviceIfNeeded(inputNode: AVAudioInputNode) {
        guard let preferredInputDeviceID else { return }
        guard let audioUnit = inputNode.audioUnit else { return }
        var deviceID = preferredInputDeviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if status != noErr {
            VoxtLog.warning("Remote ASR failed to switch preferred input device. status=\(status)")
        }
    }

    private func receiveDoubaoMessages(
        _ context: DoubaoStreamingContext,
        endpoint: String,
        resourceID: String,
        appID: String,
        accessToken: String
    ) {
        context.ws.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    guard self.isCurrentGeneration(context.generationID),
                          self.doubaoStreamingContext === context
                    else { return }
                    do {
                        if case .data(let payloadData) = message,
                           let parsed = try self.parseDoubaoServerPacket(payloadData) {
                            if !context.didStartAudioStream {
                                do {
                                    try self.ensureDoubaoAudioCaptureStarted(context, reason: "server-packet")
                                } catch {
                                    await context.responseState.markCompletedWithError(error)
                                    self.cleanupDoubaoStreamingState()
                                    self.activeProvider = nil
                                    return
                                }
                            }
                            if let text = parsed.text, !text.isEmpty {
                                let merged = await context.responseState.replace(text: text, isFinal: parsed.isFinal)
                                await MainActor.run {
                                    self.transcribedText = merged
                                }
                            } else if parsed.isFinal {
                                await context.responseState.markFinal()
                            }
                        }
                    } catch {
                        let nsError = error as NSError
                        if self.isBenignDoubaoSocketError(nsError) {
                            context.isClosed = true
                            await context.responseState.markSocketClosed()
                        } else {
                            context.isClosed = true
                            VoxtLog.warning("Doubao stream receive parse failed. detail=\(error.localizedDescription)")
                            await context.responseState.markCompletedWithError(error)
                        }
                    }
                    if !context.isClosed {
                        self.receiveDoubaoMessages(
                            context,
                            endpoint: endpoint,
                            resourceID: resourceID,
                            appID: appID,
                            accessToken: accessToken
                        )
                    }
                }
            case .failure(let error):
                Task { @MainActor in
                    guard self.isCurrentGeneration(context.generationID),
                          self.doubaoStreamingContext === context
                    else { return }
                    let nsError = error as NSError
                    if self.isBenignDoubaoSocketError(nsError) {
                        context.isClosed = true
                        await context.responseState.markSocketClosed()
                        return
                    }

                    if let detail = await self.fetchDoubaoHandshakeFailureDetail(
                        error: error,
                        endpoint: endpoint,
                        resourceID: resourceID,
                        appID: appID,
                        accessToken: accessToken
                    ) {
                        context.isClosed = true
                        await MainActor.run {
                            VoxtLog.warning("Doubao stream receive failed. detail=\(detail)")
                        }
                        let detailedError = NSError(
                            domain: "Voxt.RemoteASR",
                            code: nsError.code,
                            userInfo: [NSLocalizedDescriptionKey: detail]
                        )
                        await context.responseState.markCompletedWithError(detailedError)
                    } else {
                        context.isClosed = true
                        await context.responseState.markCompletedWithError(error)
                    }
                }
            }
        }
    }

    private func fetchDoubaoHandshakeFailureDetail(
        error: Error,
        endpoint: String,
        resourceID: String,
        appID: String,
        accessToken: String
    ) async -> String? {
        let nsError = error as NSError
        if nsError.domain != NSURLErrorDomain || nsError.code != NSURLErrorBadServerResponse {
            return nil
        }

        guard var components = URLComponents(string: endpoint) else {
            return nil
        }
        if components.scheme == "wss" {
            components.scheme = "https"
        } else if components.scheme == "ws" {
            components.scheme = "http"
        }
        guard let probeURL = components.url else {
            return nil
        }

        var request = URLRequest(url: probeURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("websocket", forHTTPHeaderField: "Upgrade")
        request.setValue("Upgrade", forHTTPHeaderField: "Connection")
        request.setValue(appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        let requestID = UUID().uuidString.lowercased()
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue(requestID, forHTTPHeaderField: "X-Api-Connect-Id")

        do {
            let (data, response) = try await VoxtNetworkSession.active.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }
            logHTTPResponse(context: "Doubao handshake probe", response: http, data: data)
            let payload = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if payload.isEmpty {
                return "Doubao handshake failed (HTTP \(http.statusCode))."
            }
            return "Doubao handshake failed (HTTP \(http.statusCode)): \(payload)"
        } catch {
            return nil
        }
    }

    private func logHTTPResponse(context: String, response: HTTPURLResponse, data: Data) {
        let headers = response.allHeaderFields
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        let preview = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        VoxtLog.info("[\(context)] status=\(response.statusCode), headers={\(headers)}, body=\(preview)", verbose: true)
    }

    private func isBenignDoubaoSocketError(_ error: NSError) -> Bool {
        if error.domain == NSPOSIXErrorDomain {
            return error.code == 57
        }

        if error.domain == NSURLErrorDomain {
            return [
                NSURLErrorCancelled,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorNotConnectedToInternet
            ].contains(error.code)
        }

        return false
    }

    private func sendDoubaoFullRequest(
        ws: URLSessionWebSocketTask,
        reqID: String,
        sequence: Int32,
        hintPayload: ResolvedASRHintPayload,
        audioFormat: String,
        configuration: RemoteProviderConfiguration
    ) async throws {
        let packet = try buildDoubaoFullRequestPacket(
            reqID: reqID,
            sequence: sequence,
            hintPayload: hintPayload,
            audioFormat: audioFormat,
            configuration: configuration
        )
        try await ws.send(.data(packet))
    }

    private func sendDoubaoFullRequest(
        ws: URLSessionWebSocketTask,
        reqID: String,
        sequence: Int32,
        hintPayload: ResolvedASRHintPayload,
        audioFormat: String,
        configuration: RemoteProviderConfiguration,
        enableNonstream: Bool = false,
        onError: @escaping (Error, Bool) -> Void
    ) {
        do {
            let packet = try buildDoubaoFullRequestPacket(
                reqID: reqID,
                sequence: sequence,
                hintPayload: hintPayload,
                audioFormat: audioFormat,
                configuration: configuration,
                enableNonstream: enableNonstream
            )
            sendDoubaoPacket(packet, through: ws, onError: onError)
        } catch {
            onError(error, false)
        }
    }

    private func buildDoubaoFullRequestPacket(
        reqID: String,
        sequence: Int32,
        hintPayload: ResolvedASRHintPayload,
        audioFormat: String,
        configuration: RemoteProviderConfiguration,
        enableNonstream: Bool = false
    ) throws -> Data {
        let payloadObject = doubaoRequestPayload(
            configuration: configuration,
            hintPayload: hintPayload,
            requestID: reqID,
            userID: "voxt",
            audioFormat: audioFormat,
            enableNonstream: enableNonstream
        )
        let rawPayload = try JSONSerialization.data(withJSONObject: payloadObject)
        let (payloadCompression, payload) = encodeDoubaoPacketPayload(rawPayload, preferGzip: true)
        return buildDoubaoPacket(
            messageType: DoubaoProtocol.messageTypeFullClientRequest,
            messageFlags: DoubaoProtocol.flagPositiveSequence,
            serialization: DoubaoProtocol.serializationJSON,
            compression: payloadCompression,
            sequence: sequence,
            payload: payload
        )
    }

    private func queueDoubaoAudioData(_ pcmData: Data, context: DoubaoStreamingContext) {
        context.pendingPCMData.append(pcmData)
        flushBufferedDoubaoAudioIfNeeded(context: context, includeTrailingPartial: false)
    }

    private func flushBufferedDoubaoAudioIfNeeded(
        context: DoubaoStreamingContext,
        includeTrailingPartial: Bool
    ) {
        while let payload = DoubaoASRConfiguration.popRecommendedStreamingChunk(
            from: &context.pendingPCMData,
            includeTrailingPartial: includeTrailingPartial
        ) {
            sendBufferedDoubaoAudioPacket(payload, context: context)
        }
    }

    private func sendBufferedDoubaoAudioPacket(_ pcmData: Data, context: DoubaoStreamingContext) {
        guard !pcmData.isEmpty, !context.isClosed else { return }
        context.audioPacketCount += 1
        let sequence = context.nextAudioSequence
        context.nextAudioSequence += 1
        context.lastAudioSequence = sequence
        let (audioCompression, audioPayload) = encodeDoubaoPacketPayload(pcmData, preferGzip: true)
        let packet = buildDoubaoPacket(
            messageType: DoubaoProtocol.messageTypeAudioOnlyClientRequest,
            messageFlags: DoubaoProtocol.flagPositiveSequence,
            serialization: DoubaoProtocol.serializationNone,
            compression: audioCompression,
            sequence: sequence,
            payload: audioPayload
        )
        sendDoubaoPacket(packet, through: context.ws) { error, isBenign in
            Task { [responseState = context.responseState] in
                if isBenign {
                    context.isClosed = true
                    await responseState.markSocketClosed()
                } else {
                    await responseState.markCompletedWithError(error)
                }
            }
        }
    }

    private func sendDoubaoAudioPacket(
        ws: URLSessionWebSocketTask,
        payload: Data,
        isLast: Bool,
        sequence: Int32
    ) async throws {
        let (audioCompression, compressedPayload) = encodeDoubaoPacketPayload(payload, preferGzip: true)
        let packet = buildDoubaoPacket(
            messageType: DoubaoProtocol.messageTypeAudioOnlyClientRequest,
            messageFlags: isLast ? DoubaoProtocol.flagNegativeAudioPacket : DoubaoProtocol.flagPositiveSequence,
            serialization: DoubaoProtocol.serializationNone,
            compression: audioCompression,
            sequence: isLast ? -sequence : sequence,
            payload: compressedPayload
        )
        try await ws.send(.data(packet))
    }

    private func encodeDoubaoPacketPayload(
        _ payload: Data,
        preferGzip: Bool
    ) -> (compression: UInt8, payload: Data) {
        guard preferGzip, !payload.isEmpty else {
            return (DoubaoProtocol.compressionNone, payload)
        }

        do {
            return (DoubaoProtocol.compressionGzip, try gzipCompressDoubaoPayload(payload))
        } catch {
            VoxtLog.warning("Doubao gzip compression failed. fallback to plain payload. error=\(error.localizedDescription)")
            return (DoubaoProtocol.compressionNone, payload)
        }
    }

    private func gzipCompressDoubaoPayload(_ data: Data) throws -> Data {
        if data.isEmpty {
            return Data()
        }

        return try data.withUnsafeBytes { rawBuffer in
            guard let input = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return data
            }

            var stream = z_stream()
            stream.zalloc = nil
            stream.zfree = nil
            stream.opaque = nil
            stream.next_in = UnsafeMutablePointer<Bytef>(OpaquePointer(input))
            stream.avail_in = uInt(data.count)

            let initStatus = deflateInit2_(
                &stream,
                Z_DEFAULT_COMPRESSION,
                Z_DEFLATED,
                MAX_WBITS + 16,
                MAX_MEM_LEVEL,
                Z_DEFAULT_STRATEGY,
                ZLIB_VERSION,
                Int32(MemoryLayout<z_stream>.size)
            )
            guard initStatus == Z_OK else {
                throw NSError(domain: "Voxt.RemoteASR", code: -12, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize Doubao GZIP compression."])
            }
            defer { deflateEnd(&stream) }

            var output = Data()
            var status: Int32 = Z_OK
            while status == Z_OK {
                var out = [UInt8](repeating: 0, count: 16_384)
                let statusCode = out.withUnsafeMutableBytes { outBuffer in
                    stream.next_out = UnsafeMutablePointer<Bytef>(outBuffer.bindMemory(to: UInt8.self).baseAddress)
                    stream.avail_out = uInt(outBuffer.count)
                    return deflate(&stream, Z_FINISH)
                }
                let used = out.count - Int(stream.avail_out)
                if used > 0 {
                    output.append(contentsOf: out[0..<used])
                }
            status = statusCode
            if status != Z_OK && status != Z_STREAM_END {
                throw NSError(
                    domain: "Voxt.RemoteASR",
                    code: -13,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to compress Doubao payload."]
                )
            }
        }
            return output
        }
    }

    private func audioLevelFromPCM16(_ data: Data) -> Float {
        guard data.count >= 2 else { return 0 }
        var sum: Float = 0
        var count: Float = 0
        data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for sample in samples {
                let normalized = Float(sample) / Float(Int16.max)
                sum += normalized * normalized
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        let rms = sqrt(sum / count)
        return min(max(rms * 2.4, 0), 1)
    }

    private nonisolated static func makeDoubaoPCM16MonoData(from buffer: AVAudioPCMBuffer) -> Data? {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return nil }

        let inputRate = max(buffer.format.sampleRate, 1)
        let targetRate = 16000.0
        let step = max(inputRate / targetRate, 1)
        let outputCount = max(Int(Double(frameCount) / step), 1)
        var output = Data(count: outputCount * MemoryLayout<Int16>.size)

        switch buffer.format.commonFormat {
        case .pcmFormatInt16:
            guard let channelData = buffer.int16ChannelData?[0] else { return nil }
            output.withUnsafeMutableBytes { rawBuffer in
                let out = rawBuffer.bindMemory(to: Int16.self)
                for index in 0..<outputCount {
                    let sourceIndex = min(Int(Double(index) * step), frameCount - 1)
                    out[index] = channelData[sourceIndex]
                }
            }
        case .pcmFormatFloat32:
            guard let channelData = buffer.floatChannelData?[0] else { return nil }
            output.withUnsafeMutableBytes { rawBuffer in
                let out = rawBuffer.bindMemory(to: Int16.self)
                for index in 0..<outputCount {
                    let sourceIndex = min(Int(Double(index) * step), frameCount - 1)
                    let clamped = max(-1.0, min(1.0, channelData[sourceIndex]))
                    out[index] = Int16(clamped * Float(Int16.max))
                }
            }
        default:
            return nil
        }

        return output
    }

    private func buildDoubaoPacket(
        messageType: UInt8,
        messageFlags: UInt8,
        serialization: UInt8,
        compression: UInt8,
        sequence: Int32,
        payload: Data
    ) -> Data {
        var data = Data()
        data.append((DoubaoProtocol.version << 4) | DoubaoProtocol.headerSize)
        data.append((messageType << 4) | messageFlags)
        data.append((serialization << 4) | compression)
        data.append(0x00)
        if (messageFlags & DoubaoProtocol.flagPositiveSequence) != 0 || (messageFlags & DoubaoProtocol.flagLastAudioPacket) != 0 {
            data.append(sequence.bigEndianData)
        }
        data.append(UInt32(payload.count).bigEndianData)
        data.append(payload)
        return data
    }

    private func parseDoubaoServerPacket(_ data: Data) throws -> (text: String?, isFinal: Bool)? {
        guard data.count >= 8 else { return nil }

        let byte0 = data[0]
        let byte1 = data[1]
        let byte2 = data[2]
        let headerSizeWords = Int(byte0 & 0x0F)
        let headerSizeBytes = max(4, headerSizeWords * 4)
        guard data.count >= headerSizeBytes else { return nil }

        let messageType = (byte1 >> 4) & 0x0F
        let messageFlags = byte1 & 0x0F
        let compression = byte2 & 0x0F
        guard messageType == DoubaoProtocol.messageTypeFullServerResponse ||
                messageType == DoubaoProtocol.messageTypeServerAck ||
                messageType == DoubaoProtocol.messageTypeServerErrorResponse else {
            return nil
        }

        let hasSequence = (messageFlags & 0x1) != 0 || (messageFlags & 0x2) != 0
        let hasEvent = (messageFlags & DoubaoProtocol.flagEvent) != 0
        var cursor = headerSizeBytes

        var headerSequence: Int32?
        if hasSequence {
            guard data.count >= cursor + 4 else { return nil }
            headerSequence = Int32(bigEndianData: data.subdata(in: cursor..<(cursor + 4)))
            cursor += 4
        }
        if hasEvent {
            guard data.count >= cursor + 4 else { return nil }
            cursor += 4
        }

        let rawPayload: Data
        switch messageType {
        case DoubaoProtocol.messageTypeFullServerResponse:
            guard data.count >= cursor + 4 else { return nil }
            let payloadSize = Int(UInt32(bigEndianData: data.subdata(in: cursor..<(cursor + 4))))
            cursor += 4
            guard payloadSize >= 0, data.count >= cursor + payloadSize else { return nil }
            rawPayload = data.subdata(in: cursor..<(cursor + payloadSize))
        case DoubaoProtocol.messageTypeServerErrorResponse:
            guard data.count >= cursor + 8 else { return nil }
            cursor += 4 // server error code
            let payloadSize = Int(UInt32(bigEndianData: data.subdata(in: cursor..<(cursor + 4))))
            cursor += 4
            guard payloadSize >= 0, data.count >= cursor + payloadSize else { return nil }
            rawPayload = data.subdata(in: cursor..<(cursor + payloadSize))
        case DoubaoProtocol.messageTypeServerAck:
            rawPayload = data.count > cursor ? data.subdata(in: cursor..<data.count) : Data()
        default:
            return nil
        }
        let payload: Data
        switch compression {
        case DoubaoProtocol.compressionNone:
            payload = rawPayload
        case DoubaoProtocol.compressionGzip:
            payload = (try? decodeDoubaoGzipPayload(rawPayload)) ?? rawPayload
        default:
            if looksLikeGzip(rawPayload) {
                payload = (try? decodeDoubaoGzipPayload(rawPayload)) ?? rawPayload
            } else {
                throw NSError(
                    domain: "Voxt.RemoteASR",
                    code: -6,
                    userInfo: [NSLocalizedDescriptionKey: "Doubao response compression is unsupported in current client."]
                )
            }
        }

        if messageType == DoubaoProtocol.messageTypeServerErrorResponse {
            let errorText = String(data: payload, encoding: .utf8) ?? "Unknown Doubao server error."
            throw NSError(domain: "Voxt.RemoteASR", code: -7, userInfo: [NSLocalizedDescriptionKey: errorText])
        }

        guard !payload.isEmpty else {
            let sequenceFromHeaderOnly = headerSequence
            let isFinal = (messageFlags & DoubaoProtocol.flagLastAudioPacket) != 0
                || (sequenceFromHeaderOnly ?? 1) < 0
            return (nil, isFinal)
        }

        guard let object = try? JSONSerialization.jsonObject(with: payload) else {
            let raw = String(data: payload, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let visibleText = raw.flatMap { RemoteASRTextSanitizer.isLikelyIdentifierText($0) ? nil : $0 }
            return (visibleText, false)
        }

        let sequenceFromJSON = extractSequence(in: object)
        let isFinal = (messageFlags & DoubaoProtocol.flagLastAudioPacket) != 0
            || isLastPackage(in: object) == true
            || (sequenceFromJSON ?? headerSequence ?? 1) < 0
        let fragment = extractDoubaoText(in: object)
        return (fragment, isFinal)
    }

    private func decodeDoubaoGzipPayload(_ data: Data) throws -> Data {
        if data.isEmpty { return Data() }

        return try data.withUnsafeBytes { rawBuffer in
            guard let input = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return data
            }

            var stream = z_stream()
            stream.zalloc = nil
            stream.zfree = nil
            stream.opaque = nil
            stream.next_in = UnsafeMutablePointer<Bytef>(OpaquePointer(input))
            stream.avail_in = uInt(data.count)

            let initStatus = inflateInit2_(&stream, 16 + MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
            guard initStatus == Z_OK else {
                throw NSError(domain: "Voxt.RemoteASR", code: -8, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize Doubao GZIP decompression."])
            }
            defer { inflateEnd(&stream) }

            var output = Data()
            var decompressStatus: Int32 = Z_OK
            let chunkSize = 16_384
            while decompressStatus == Z_OK {
                var out = [UInt8](repeating: 0, count: chunkSize)
                let outCount = out.count
                let status = out.withUnsafeMutableBytes { outBuffer in
                    stream.next_out = UnsafeMutablePointer<Bytef>(outBuffer.bindMemory(to: UInt8.self).baseAddress)
                    stream.avail_out = uInt(outCount)
                    return inflate(&stream, Z_SYNC_FLUSH)
                }
                let used = outCount - Int(stream.avail_out)
                if used > 0 {
                    output.append(contentsOf: out[0..<used])
                }
                decompressStatus = status
                guard status == Z_OK || status == Z_STREAM_END else {
                    throw NSError(domain: "Voxt.RemoteASR", code: -9, userInfo: [NSLocalizedDescriptionKey: "Failed to decode Doubao GZIP response payload."])
                }
            }
            return output
        }
    }

    private func isLastPackage(in object: Any) -> Bool? {
        if let dict = object as? [String: Any] {
            if let value = dict["is_last_package"] {
                return value as? Bool ?? (value as? NSNumber)?.boolValue
            }
            for nested in dict.values {
                if let result = isLastPackage(in: nested) {
                    return result
                }
            }
            return nil
        }
        if let array = object as? [Any] {
            for item in array {
                if let result = isLastPackage(in: item) {
                    return result
                }
            }
        }
        return nil
    }

    private func looksLikeGzip(_ data: Data) -> Bool {
        guard data.count >= 2 else { return false }
        return data[0] == 0x1F && data[1] == 0x8B
    }

    private func extractSequence(in object: Any) -> Int32? {
        if let value = object as? Int { return Int32(value) }
        if let value = object as? Int32 { return value }
        if let value = object as? Int64 { return Int32(value) }
        if let dict = object as? [String: Any] {
            if let seq = dict["sequence"] {
                return extractSequence(in: seq)
            }
            for nested in dict.values {
                if let seq = extractSequence(in: nested) {
                    return seq
                }
            }
        }
        if let array = object as? [Any] {
            for item in array {
                if let seq = extractSequence(in: item) {
                    return seq
                }
            }
        }
        return nil
    }

    private func transcribeViaMultipartStream(
        endpoint: URL,
        authorizationValue: String,
        fileURL: URL,
        model: String,
        extraFields: [String: String]
    ) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        let effectiveModel = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "whisper-1" : model
        let body = try makeMultipartBody(
            fileURL: fileURL,
            boundary: boundary,
            model: effectiveModel,
            extraFields: extraFields
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream, application/json, text/plain", forHTTPHeaderField: "Accept")
        request.setValue(authorizationValue, forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let (bytes, response) = try await VoxtNetworkSession.active.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "Voxt.RemoteASR", code: -10, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response."])
        }

        if !(200...299).contains(http.statusCode) {
            let payload = try await collectText(from: bytes)
            throw NSError(
                domain: "Voxt.RemoteASR",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(payload)"]
            )
        }

        var aggregate = ""
        for try await rawLine in bytes.lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            let line: String
            if trimmed.hasPrefix("data:") {
                line = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                line = trimmed
            }

            if line == "[DONE]" {
                break
            }

            if let fragment = extractTextFragment(fromLine: line), !fragment.isEmpty {
                aggregate = mergeStreamFragment(current: aggregate, incoming: fragment)
                await MainActor.run {
                    self.transcribedText = aggregate
                }
            }
        }

        if aggregate.isEmpty {
            return transcribedText
        }
        return aggregate
    }

    private func extractTextFragment(fromLine line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let data = line.data(using: .utf8) else {
            return trimmed
        }

        if let object = try? JSONSerialization.jsonObject(with: data) {
            if let value = extractText(in: object), !value.isEmpty {
                return normalizedTextFragment(value)
            }
            return nil
        }

        if let loose = extractLooseTextField(from: trimmed), !loose.isEmpty {
            return normalizedTextFragment(loose)
        }

        // If this looks like a JSON/object payload but is non-standard (e.g. single quotes),
        // avoid rendering raw object text in UI.
        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
            (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            return nil
        }

        return normalizedTextFragment(trimmed)
    }

    private func extractLooseTextField(from line: String) -> String? {
        let patterns = [
            #"(?:["']?text["']?\s*:\s*["'])([^"']+)(?:["'])"#,
            #"(?:["']?transcript["']?\s*:\s*["'])([^"']+)(?:["'])"#,
            #"(?:["']?result_text["']?\s*:\s*["'])([^"']+)(?:["'])"#,
            #"(?:["']?text["']?\s*:\s*)([^,}\]]+)"#,
            #"(?:["']?transcript["']?\s*:\s*)([^,}\]]+)"#,
            #"(?:["']?result_text["']?\s*:\s*)([^,}\]]+)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, options: [], range: range),
                  match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: line) else {
                continue
            }
            var value = String(line[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                (value.hasPrefix("'") && value.hasSuffix("'")) {
                value.removeFirst()
                value.removeLast()
                value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func normalizedTextFragment(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if isLikelyJSONObjectString(trimmed) {
            if let data = trimmed.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data),
               let nested = extractText(in: object),
               !nested.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !isLikelyJSONObjectString(nested) {
                return nested.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let loose = extractLooseTextField(from: trimmed),
               !isLikelyJSONObjectString(loose) {
                return loose.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        }

        return trimmed
    }

    private func isLikelyJSONObjectString(_ value: String) -> Bool {
        (value.hasPrefix("{") && value.hasSuffix("}")) ||
        (value.hasPrefix("[") && value.hasSuffix("]"))
    }

    private func extractDoubaoText(in object: Any) -> String? {
        if let dict = object as? [String: Any],
           let result = dict["result"] as? [String: Any],
           let text = result["text"] as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !RemoteASRTextSanitizer.isLikelyIdentifierText(trimmed) {
                return trimmed
            }
        }

        var candidates: [String] = []

        func appendCandidate(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !RemoteASRTextSanitizer.isLikelyIdentifierText(trimmed) else { return }
            candidates.append(trimmed)
        }

        func walk(_ node: Any) {
            if let dict = node as? [String: Any] {
                let directTextKeys = ["text", "transcript", "utterance", "utterance_text", "result_text"]
                for key in directTextKeys {
                    if let value = dict[key] as? String {
                        appendCandidate(value)
                    }
                }

                let containerKeys = ["result", "results", "utterances", "payload_msg", "payload", "data", "nbest", "alternatives"]
                for key in containerKeys {
                    if let value = dict[key] {
                        walk(value)
                    }
                }

                for (_, value) in dict {
                    if value is [String: Any] || value is [Any] {
                        walk(value)
                    }
                }
                return
            }

            if let array = node as? [Any] {
                for item in array {
                    walk(item)
                }
            }
        }

        walk(object)
        return candidates.max(by: { $0.count < $1.count })
    }

    private func extractText(in object: Any) -> String? {
        if let text = object as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if isLikelyJSONObjectString(trimmed) {
                if let data = trimmed.data(using: .utf8),
                   let nestedObject = try? JSONSerialization.jsonObject(with: data),
                   let nestedText = extractText(in: nestedObject),
                   !nestedText.isEmpty {
                    return nestedText
                }
                if let loose = extractLooseTextField(from: trimmed), !loose.isEmpty {
                    return loose
                }
                return nil
            }
            return trimmed
        }
        if let dict = object as? [String: Any] {
            let preferredKeys = ["delta", "text", "transcript", "result_text", "content", "utterance", "data"]
            for key in preferredKeys {
                if let value = dict[key], let text = extractText(in: value), !text.isEmpty {
                    return text
                }
            }
            for value in dict.values {
                if (value is [String: Any] || value is [Any]),
                   let text = extractText(in: value),
                   !text.isEmpty {
                    return text
                }
            }
        }
        if let array = object as? [Any] {
            for item in array {
                if let text = extractText(in: item), !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }

    private func mergeStreamFragment(current: String, incoming: String) -> String {
        let fragment = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fragment.isEmpty else { return current }
        if current.isEmpty { return fragment }
        if fragment == current { return current }
        if fragment.hasPrefix(current) { return fragment }
        if current.hasPrefix(fragment) { return current }
        if fragment.contains(current) { return fragment }
        if current.contains(fragment) { return current }

        let maxOverlap = min(current.count, fragment.count)
        if maxOverlap > 0 {
            for length in stride(from: maxOverlap, through: 1, by: -1) {
                let currentSuffix = String(current.suffix(length))
                let incomingPrefix = String(fragment.prefix(length))
                if currentSuffix == incomingPrefix {
                    return current + fragment.dropFirst(length)
                }
            }
        }
        return current + fragment
    }

    private func makeMultipartBody(
        fileURL: URL,
        boundary: String,
        model: String,
        extraFields: [String: String]
    ) throws -> Data {
        var body = Data()

        func appendField(name: String, value: String) {
            guard !value.isEmpty else { return }
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField(name: "model", value: model)
        for (name, value) in extraFields where !value.isEmpty {
            appendField(name: name, value: value)
        }

        let filename = fileURL.lastPathComponent
        let mimeType = "audio/wav"
        let fileData = try Data(contentsOf: fileURL)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    private func audioMIMEType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "mp3":
            return "audio/mpeg"
        case "m4a":
            return "audio/mp4"
        case "ogg":
            return "audio/ogg"
        default:
            return "audio/wav"
        }
    }

    private func resolvedAliyunFunRealtimeEndpoint(_ endpoint: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "wss://dashscope.aliyuncs.com/api-ws/v1/inference"
        }
        if var components = URLComponents(string: trimmed) {
            let normalizedPath = components.path.lowercased()
            if normalizedPath.hasSuffix("/api-ws/v1/inference") {
                return trimmed
            }
            if normalizedPath.hasSuffix("/api-ws/v1/realtime") {
                components.path = components.path.replacingOccurrences(of: "/api-ws/v1/realtime", with: "/api-ws/v1/inference")
                components.queryItems = nil
                return components.string ?? trimmed
            }
            if normalizedPath.hasSuffix("/models") {
                return replacingPathSuffix(in: trimmed, oldSuffix: "/models", newSuffix: "/api-ws/v1/inference")
            }
            if normalizedPath.hasSuffix("/chat/completions") {
                return replacingPathSuffix(in: trimmed, oldSuffix: "/chat/completions", newSuffix: "/api-ws/v1/inference")
            }
            if normalizedPath.hasSuffix("/v1") {
                return appendingPath(trimmed, suffix: "/inference")
            }
        }
        return trimmed
    }

    private func isAliyunFunRealtimeModel(_ model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("fun-asr") || normalized.hasPrefix("paraformer-realtime")
    }

    private func isAliyunQwenRealtimeModel(_ model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("qwen3-asr-flash-realtime")
    }

    private func isAliyunFileTranscriptionModel(_ model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("qwen3-asr-flash-filetrans")
            || normalized == "fun-asr"
            || normalized == "paraformer-v2"
    }

    private func resolvedAliyunQwenRealtimeEndpoint(_ endpoint: String, model: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? model

        guard !trimmed.isEmpty else {
            return "wss://dashscope.aliyuncs.com/api-ws/v1/realtime?model=\(encodedModel)"
        }
        guard var components = URLComponents(string: trimmed) else {
            return trimmed
        }
        let normalizedPath = components.path.lowercased()
        if normalizedPath.hasSuffix("/api-ws/v1/realtime") {
            var items = components.queryItems ?? []
            if !items.contains(where: { $0.name == "model" }) {
                items.append(URLQueryItem(name: "model", value: model))
                components.queryItems = items
            }
            return components.string ?? trimmed
        }
        if normalizedPath.hasSuffix("/api-ws/v1/inference") {
            components.path = components.path.replacingOccurrences(of: "/api-ws/v1/inference", with: "/api-ws/v1/realtime")
            var items = components.queryItems ?? []
            if !items.contains(where: { $0.name == "model" }) {
                items.append(URLQueryItem(name: "model", value: model))
            }
            components.queryItems = items
            return components.string ?? trimmed
        }
        if normalizedPath.hasSuffix("/chat/completions") {
            let base = replacingPathSuffix(in: trimmed, oldSuffix: "/chat/completions", newSuffix: "/api-ws/v1/realtime")
            return base.contains("?") ? base : "\(base)?model=\(encodedModel)"
        }
        return trimmed
    }

    private func appendingPath(_ value: String, suffix: String) -> String {
        value.hasSuffix("/") ? value + suffix.dropFirst() : value + suffix
    }

    private func replacingPathSuffix(in value: String, oldSuffix: String, newSuffix: String) -> String {
        guard value.lowercased().hasSuffix(oldSuffix) else { return value }
        return String(value.dropLast(oldSuffix.count)) + newSuffix
    }

    private func collectText(from bytes: URLSession.AsyncBytes) async throws -> String {
        var chunks: [String] = []
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                chunks.append(trimmed)
            }
            if chunks.count >= 6 { break }
        }
        return chunks.joined(separator: " | ")
    }

    private func normalizedEndpoint(_ value: String, defaultValue: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultValue : trimmed
    }

    private func resolvedDoubaoResourceID(from configuration: RemoteProviderConfiguration) -> String {
        DoubaoASRConfiguration.resolvedResourceID(configuration.model)
    }

    private func resolvedDoubaoEndpoint(from configuration: RemoteProviderConfiguration) -> String {
        DoubaoASRConfiguration.resolvedEndpoint(configuration.endpoint, model: configuration.model)
    }

    private func resolvedDoubaoStreamingEndpoint(from configuration: RemoteProviderConfiguration) -> String {
        DoubaoASRConfiguration.resolvedStreamingEndpoint(configuration.endpoint, model: configuration.model)
    }

    private func startMeteringTimer() {
        stopMeteringTimer()
        meterTimer = Timer.scheduledTimer(
            timeInterval: 0.05,
            target: self,
            selector: #selector(updateAudioMeter),
            userInfo: nil,
            repeats: true
        )
    }

    private func stopMeteringTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
        audioLevel = 0
    }

    @objc private func updateAudioMeter() {
        guard let recorder else { return }
        recorder.updateMeters()
        let avgPower = recorder.averagePower(forChannel: 0)
        let linear = pow(10, avgPower / 20)
        audioLevel = min(max(linear, 0), 1)
    }

    private func makeTemporaryRecordingURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("voxt-remote-asr-\(UUID().uuidString)")
            .appendingPathExtension("wav")
    }

    private func cleanupRecorderState() {
        recorder?.stop()
        recorder = nil
        recordingFileURL = nil
        isRecording = false
        stopRequested = false
        stopOpenAIPreviewLoop()
        stopMeteringTimer()
    }

    private func stopFileRecordingCapture() -> URL? {
        let fileURL = recordingFileURL
        recorder?.stop()
        recorder = nil
        recordingFileURL = nil
        isRecording = false
        stopOpenAIPreviewLoop()
        stopMeteringTimer()
        return fileURL
    }

    private func cleanupDoubaoStreamingState() {
        if let context = doubaoStreamingContext {
            context.isClosed = true
            context.ws.cancel(with: .normalClosure, reason: nil)
            context.session.invalidateAndCancel()
        }
        doubaoStreamingContext = nil
        stopDoubaoAudioCapture()
    }

    private func cleanupAliyunStreamingState() {
        if let context = aliyunStreamingContext {
            context.isClosed = true
            context.ws.cancel(with: .normalClosure, reason: nil)
            context.session.invalidateAndCancel()
        }
        aliyunStreamingContext = nil
        if let context = aliyunQwenStreamingContext {
            context.isClosed = true
            context.ws.cancel(with: .normalClosure, reason: nil)
            context.session.invalidateAndCancel()
        }
        aliyunQwenStreamingContext = nil
        stopAliyunAudioCapture()
    }

    private func cleanupActiveUploadTask() {
        transcribeTask?.cancel()
        transcribeTask = nil
        stopOpenAIPreviewLoop()
        isRequesting = false
    }

    func discardPendingSessionOutput() {
        recordingGenerationID = UUID()
        cleanupActiveUploadTask()
        cleanupRecorderState()
        cleanupDoubaoStreamingState()
        cleanupAliyunStreamingState()
        activeProvider = nil
        stopRequested = false
        lastPresentedRuntimeErrorMessage = ""
    }

    private func startOpenAIPreviewLoop(configuration: RemoteProviderConfiguration) {
        stopOpenAIPreviewLoop()
        openAIPreviewLastText = ""
        openAIPreviewTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1.4))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self.runOpenAIPreviewPass(configuration: configuration)
            }
        }
    }

    private func stopOpenAIPreviewLoop() {
        openAIPreviewTask?.cancel()
        openAIPreviewTask = nil
        openAIPreviewInFlight = false
    }

    private func runOpenAIPreviewPass(configuration: RemoteProviderConfiguration) async {
        guard isRecording else { return }
        guard selectedProvider == .openAIWhisper else { return }
        guard !openAIPreviewInFlight else { return }
        guard let sourceURL = recordingFileURL else { return }

        openAIPreviewInFlight = true
        defer { openAIPreviewInFlight = false }

        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxt-openai-preview-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        do {
            if FileManager.default.fileExists(atPath: snapshotURL.path) {
                try FileManager.default.removeItem(at: snapshotURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: snapshotURL)
            defer { try? FileManager.default.removeItem(at: snapshotURL) }

            let attrs = try FileManager.default.attributesOfItem(atPath: snapshotURL.path)
            if let size = attrs[.size] as? Int64, size < 6_000 {
                return
            }

            normalizeWAVHeaderForSnapshot(at: snapshotURL)

            let hintPayload = resolvedHintPayload(for: .openAIWhisper, configuration: configuration)
            let preview = try await transcribeOpenAI(
                fileURL: snapshotURL,
                configuration: configuration,
                hintPayload: hintPayload
            )
            let normalized = preview.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return }
            if normalized != openAIPreviewLastText {
                openAIPreviewLastText = normalized
                transcribedText = normalized
            }
        } catch {
            // Preview failures are expected while recorder header is still mutating.
        }
    }

    private func normalizeWAVHeaderForSnapshot(at fileURL: URL) {
        guard var data = try? Data(contentsOf: fileURL), data.count >= 44 else { return }
        guard String(data: data[0..<4], encoding: .ascii) == "RIFF",
              String(data: data[8..<12], encoding: .ascii) == "WAVE" else {
            return
        }

        let fileSize = UInt32(data.count)
        let riffChunkSize = fileSize > 8 ? fileSize - 8 : 0
        let dataChunkSize = fileSize > 44 ? fileSize - 44 : 0

        writeLittleEndianUInt32(riffChunkSize, into: &data, at: 4)
        writeLittleEndianUInt32(dataChunkSize, into: &data, at: 40)
        try? data.write(to: fileURL, options: .atomic)
    }

    private func writeLittleEndianUInt32(_ value: UInt32, into data: inout Data, at offset: Int) {
        guard data.count >= offset + 4 else { return }
        let bytes = value.littleEndian
        withUnsafeBytes(of: bytes) { raw in
            data.replaceSubrange(offset..<(offset + 4), with: raw)
        }
    }

    private func finish(with text: String, generationID: UUID) {
        guard isCurrentGeneration(generationID) else { return }
        cleanupActiveUploadTask()
        cleanupRecorderState()
        cleanupDoubaoStreamingState()
        cleanupAliyunStreamingState()
        activeProvider = nil
        lastPresentedRuntimeErrorMessage = ""
        onTranscriptionFinished?(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func isCurrentGeneration(_ generationID: UUID) -> Bool {
        recordingGenerationID == generationID
    }

    private func notifyStartFailure(_ error: Error) {
        let message = userVisibleRemoteErrorMessage(for: error)
        guard !message.isEmpty else { return }
        onStartFailure?(message)
    }

    private func notifyRuntimeFailure(_ error: Error) {
        let message = userVisibleRemoteErrorMessage(for: error)
        guard !message.isEmpty, message != lastPresentedRuntimeErrorMessage else { return }
        lastPresentedRuntimeErrorMessage = message
        onRuntimeFailure?(message)
    }

    private func userVisibleRemoteErrorMessage(for error: Error) -> String {
        if let conflictMessage = VoxtNetworkSession.directModeConflictMessage(for: error) {
            return conflictMessage
        }
        let nsError = error as NSError
        let description = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDescription = description.lowercased()
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return AppLocalization.localizedString("Network appears to be offline. Check your connection and try again.")
            case NSURLErrorTimedOut:
                return AppLocalization.localizedString("Remote ASR timed out. Please try again.")
            case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost, NSURLErrorCannotFindHost:
                return AppLocalization.localizedString("Couldn't reach the remote ASR service. Check your network and proxy settings.")
            default:
                break
            }
        }
        switch nsError.code {
        case 401:
            return AppLocalization.localizedString("Remote ASR authentication failed. Check the provider credentials and try again.")
        case 402:
            return AppLocalization.localizedString("Remote ASR billing or quota is unavailable. Check the provider account balance and limits.")
        case 403:
            return AppLocalization.localizedString("Remote ASR access was denied. Check the provider permissions, region, or endpoint.")
        case 408, 504:
            return AppLocalization.localizedString("Remote ASR timed out. Please try again.")
        case 409, 429:
            return AppLocalization.localizedString("Remote ASR is busy or has reached its quota. Please wait a moment and try again.")
        case 500 ... 599:
            return AppLocalization.localizedString("Remote ASR is temporarily unavailable. Please try again later.")
        default:
            break
        }
        if normalizedDescription.contains("exceededconcurrentquota")
            || normalizedDescription.contains("quota")
            || normalizedDescription.contains("rate limit")
            || normalizedDescription.contains("too many requests")
            || normalizedDescription.contains("concurrent") {
            return AppLocalization.localizedString("Remote ASR is busy or has reached its quota. Please wait a moment and try again.")
        }
        if normalizedDescription.contains("billing")
            || normalizedDescription.contains("insufficient")
            || normalizedDescription.contains("balance")
            || normalizedDescription.contains("arrears")
            || normalizedDescription.contains("欠费")
            || normalizedDescription.contains("余额")
            || normalizedDescription.contains("费用") {
            return AppLocalization.localizedString("Remote ASR billing or quota is unavailable. Check the provider account balance and limits.")
        }
        if normalizedDescription.contains("unauthorized")
            || normalizedDescription.contains("forbidden")
            || normalizedDescription.contains("access token")
            || normalizedDescription.contains("api key")
            || normalizedDescription.contains("鉴权")
            || normalizedDescription.contains("权限") {
            return AppLocalization.localizedString("Remote ASR authentication failed. Check the provider credentials and try again.")
        }
        if normalizedDescription.contains("network")
            || normalizedDescription.contains("socket is not connected")
            || normalizedDescription.contains("proxy")
            || normalizedDescription.contains("vpn") {
            return AppLocalization.localizedString("Couldn't reach the remote ASR service. Check your network and proxy settings.")
        }
        return description.isEmpty
            ? AppLocalization.localizedString("Remote ASR request failed.")
            : description
    }
}

@MainActor
private final class AliyunQwenStreamingContext {
    let session: URLSession
    let ws: URLSessionWebSocketTask
    let responseState: AliyunQwenResponseState
    let generationID: UUID
    var isClosed = false
    var didStartAudioStream = false

    init(
        session: URLSession,
        ws: URLSessionWebSocketTask,
        responseState: AliyunQwenResponseState,
        generationID: UUID
    ) {
        self.session = session
        self.ws = ws
        self.responseState = responseState
        self.generationID = generationID
    }
}

private actor AliyunQwenResponseState {
    private var committed: [String] = []
    private var partial = ""
    private var finishRequested = false
    private var sessionFinished = false
    private var completionError: Error?
    private let onError: @Sendable (Error) -> Void

    init(onError: @escaping @Sendable (Error) -> Void = { _ in }) {
        self.onError = onError
    }

    func markFinishRequested() {
        finishRequested = true
    }

    func markSessionFinished() {
        sessionFinished = true
    }

    func markCompletedWithError(_ error: Error) {
        if completionError == nil {
            completionError = error
            onError(error)
        }
    }

    func setPartial(_ value: String) -> String {
        partial = value
        return mergedText()
    }

    func commit(_ value: String) -> String {
        if committed.last != value {
            committed.append(value)
        }
        partial = ""
        return mergedText()
    }

    func waitForFinalResult(timeoutSeconds: TimeInterval) async throws -> String {
        let deadline = Date().addingTimeInterval(max(timeoutSeconds, 0))
        while !sessionFinished, completionError == nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(120))
        }
        if let completionError {
            throw completionError
        }
        if finishRequested, !partial.isEmpty {
            if committed.last != partial {
                committed.append(partial)
            }
            partial = ""
        }
        return mergedText()
    }

    func currentText() -> String {
        mergedText()
    }

    private func mergedText() -> String {
        var values = committed
        if !partial.isEmpty {
            values.append(partial)
        }
        return values.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
private final class AliyunFunStreamingContext {
    let session: URLSession
    let ws: URLSessionWebSocketTask
    let taskID: String
    let responseState: AliyunFunResponseState
    let generationID: UUID
    var isClosed = false
    var didStartAudioStream = false

    init(
        session: URLSession,
        ws: URLSessionWebSocketTask,
        taskID: String,
        responseState: AliyunFunResponseState,
        generationID: UUID
    ) {
        self.session = session
        self.ws = ws
        self.taskID = taskID
        self.responseState = responseState
        self.generationID = generationID
    }
}

private actor AliyunFunResponseState {
    private var committedSegments: [String] = []
    private var livePartial = ""
    private var finishRequested = false
    private var taskFinished = false
    private var completionError: Error?
    private let onError: @Sendable (Error) -> Void

    init(onError: @escaping @Sendable (Error) -> Void = { _ in }) {
        self.onError = onError
    }

    func markRunRequested() {}

    func markFinishRequested() {
        finishRequested = true
    }

    func markTaskFinished() {
        taskFinished = true
    }

    func markCompletedWithError(_ error: Error) {
        if completionError == nil {
            completionError = error
            onError(error)
        }
    }

    func updateWithSentence(_ text: String, isSentenceEnd: Bool) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return joinedText()
        }
        if isSentenceEnd {
            if committedSegments.last != trimmed {
                committedSegments.append(trimmed)
            }
            livePartial = ""
        } else {
            livePartial = trimmed
        }
        return joinedText()
    }

    func waitForFinalResult(timeoutSeconds: TimeInterval) async throws -> String {
        let deadline = Date().addingTimeInterval(max(timeoutSeconds, 0))
        while !taskFinished, completionError == nil, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(120))
        }
        if let completionError {
            throw completionError
        }
        if finishRequested, !livePartial.isEmpty {
            if committedSegments.last != livePartial {
                committedSegments.append(livePartial)
            }
            livePartial = ""
        }
        return joinedText()
    }

    func currentText() -> String {
        joinedText()
    }

    private func joinedText() -> String {
        var segments = committedSegments
        if !livePartial.isEmpty {
            segments.append(livePartial)
        }
        return segments.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension UInt32 {
    var bigEndianData: Data {
        withUnsafeBytes(of: self.bigEndian) { Data($0) }
    }

    init(bigEndianData data: Data) {
        precondition(data.count == 4)
        self = data.reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
    }
}

private extension Int32 {
    var bigEndianData: Data {
        withUnsafeBytes(of: self.bigEndian) { Data($0) }
    }

    init(bigEndianData data: Data) {
        precondition(data.count == 4)
        let value = data.reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
        self = Int32(bitPattern: value)
    }
}
