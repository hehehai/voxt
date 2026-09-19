// RemoteASRTranscriber.swift
// Provides Remote ASRTranscriber for remote ASR adapters.

import Foundation
import AVFoundation
import AudioToolbox
import Combine

@MainActor
class RemoteASRTranscriber: NSObject, ObservableObject, TranscriberProtocol {
    final class AudioSampleStore {
        private let lock = NSLock()
        var samples: [Float] = []

        func append(_ newSamples: [Float]) {
            lock.lock()
            defer { lock.unlock() }
            samples.append(contentsOf: newSamples)
        }

        func snapshot() -> [Float] {
            lock.lock()
            defer { lock.unlock() }
            return samples
        }

        func clear() {
            lock.lock()
            defer { lock.unlock() }
            samples.removeAll(keepingCapacity: false)
        }
    }

    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var transcribedText = ""
    @Published var isEnhancing = false
    @Published var isRequesting = false
    @Published var isFinalizingTranscription = false
    var sessionAllowsRealtimeTextDisplay = true

    var onTranscriptionFinished: ((String) -> Void)?
    var onStartFailure: ((String) -> Void)?
    var onRuntimeFailure: ((String) -> Void)?
    var dictionaryEntryProvider: (() -> [DictionaryEntry])?
    var doubaoDictionaryEntryProvider: (() -> [DictionaryEntry])?
    var voiceActivityUseCase: ASRVoiceActivityUseCase = .transcription

    private var recorder: AVAudioRecorder?
    let audioEngine = AVAudioEngine()
    var doubaoStreamingContext: DoubaoStreamingContext?
    var aliyunStreamingContext: AliyunFunStreamingContext?
    var aliyunQwenStreamingContext: AliyunQwenStreamingContext?
    var stepFunStreamingContext: StepFunStreamingContext?
    var geminiLiveStreamingContext: GeminiLiveStreamingContext?
    private var meterTimer: Timer?
    private var openAIPreviewTask: Task<Void, Never>?
    private var openAIPreviewInFlight = false
    private var openAIPreviewLastText = ""
    private var recordingFileURL: URL?
    private var completedAudioArchiveURL: URL?
    let sampleStore = AudioSampleStore()
    var streamingInputSampleRate: Double = HistoryAudioArchiveSupport.targetSampleRate
    private var transcribeTask: Task<Void, Never>?
    var stopRequested = false
    var activeProvider: RemoteASRProvider?
    var activeConfiguration: RemoteProviderConfiguration?
    var preferredInputDeviceID: AudioDeviceID?
    private let streamingFinalWaitTimeout: TimeInterval = 20
    private var lastPresentedRuntimeErrorMessage = ""
    private var pendingIntermediateTranscription: String?
    private var intermediateTranscriptionPublishTask: Task<Void, Never>?
    var recordingGenerationID = UUID()
    var doubaoCaptureStartupWatchdogTask: Task<Void, Never>?
    var didRetryDoubaoCaptureStartup = false
    var doubaoCaptureUsesPreferredInputDevice = false
    let doubaoCaptureStartupWatchdogDelay: Duration = .seconds(1.2)
    let aliyunRealtimeStopDrainDelay: Duration = .milliseconds(180)
    let realtimePendingAudioByteLimit = 1_024_000

    func setPreferredInputDevice(_ deviceID: AudioDeviceID?) {
        preferredInputDeviceID = deviceID
    }

    func activeRealtimeDebugSummary() -> String? {
        if let context = doubaoStreamingContext {
            return "doubao{\(context.debugSummary())}"
        }
        if aliyunStreamingContext != nil {
            return "aliyun-fun{active=true}"
        }
        if aliyunQwenStreamingContext != nil {
            return "aliyun-qwen{active=true}"
        }
        if stepFunStreamingContext != nil {
            return "stepfun{active=true}"
        }
        if geminiLiveStreamingContext != nil {
            return "gemini-live{active=true}"
        }
        return nil
    }

    func requestPermissions() async -> Bool {
        await RecordingPermissionRequest.microphoneAccess()
    }

    func consumeCompletedAudioArchiveURL() -> URL? {
        let url = completedAudioArchiveURL
        completedAudioArchiveURL = nil
        return url
    }

    func discardCompletedAudioArchive() {
        removeCompletedAudioArchiveIfNeeded()
    }

    func startRecording() {
        guard !isRecording else { return }
        recordingGenerationID = UUID()
        removeCompletedAudioArchiveIfNeeded()
        cleanupActiveUploadTask()
        cleanupDoubaoStreamingState()
        cleanupAliyunStreamingState()
        cleanupStepFunStreamingState()
        cleanupGeminiLiveStreamingState()
        sampleStore.clear()
        streamingInputSampleRate = HistoryAudioArchiveSupport.targetSampleRate
        transcribedText = ""
        resetIntermediateTranscriptionPublishing()
        audioLevel = 0
        isRequesting = false
        stopRequested = false
        lastPresentedRuntimeErrorMessage = ""
        let provider = selectedProvider
        let configuration = selectedProviderConfiguration(for: provider)
        if let message = endpointSecurityValidationMessage(for: configuration) {
            notifyStartFailure(
                NSError(
                    domain: "Voxt.RemoteASR",
                    code: -20,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            )
            return
        }
        let hintPayload = resolvedHintPayload(for: provider, configuration: configuration)
        activeProvider = provider
        activeConfiguration = configuration
        let configuredModel = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedModel = configuredModel.isEmpty
            ? provider.suggestedModel
            : configuredModel
        let resolvedEndpoint = configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let routeSummary: String
        if provider == .aliyunBailianASR {
            if let kind = RemoteASREndpointSupport.aliyunQwenRealtimeSessionKind(for: resolvedModel) {
                routeSummary = switch kind {
                case .qwenASR:
                    "aliyun-qwen-realtime"
                case .omniASR:
                    "aliyun-omni-realtime"
                }
            } else if RemoteASREndpointSupport.isAliyunFunRealtimeModel(resolvedModel) {
                routeSummary = "aliyun-fun-realtime"
            } else if RemoteASREndpointSupport.isAliyunFileTranscriptionModel(resolvedModel) {
                routeSummary = "aliyun-file"
            } else {
                routeSummary = "aliyun-unknown"
            }
        } else if provider == .stepFunASR,
                  RemoteASRRealtimeSupport.isStepFunRealtimeModel(resolvedModel) {
            routeSummary = "stepfun-realtime"
        } else if provider == .googleGeminiASR {
            routeSummary = "gemini-live"
        } else {
            routeSummary = provider.rawValue
        }
        VoxtLog.model(
            "Remote ASR recording requested. provider=\(provider.rawValue), model=\(resolvedModel), endpoint=\(resolvedEndpoint.isEmpty ? "<default>" : resolvedEndpoint), route=\(routeSummary), realtimeDisplay=\(sessionAllowsRealtimeTextDisplay), pseudoRealtime=\(configuration.openAIChunkPseudoRealtimeEnabled), language=\(hintPayload.language ?? "auto"), languageHints=\(hintPayload.languageHints.count), promptChars=\(hintPayload.prompt?.count ?? 0)"
        )

        if provider == .doubaoASR {
            do {
                try startDoubaoStreaming(configuration: configuration, hintPayload: hintPayload)
            } catch {
                VoxtLog.asrError("Doubao streaming setup failed: \(error.localizedDescription)")
                cleanupRecorderState()
                cleanupDoubaoStreamingState()
                activeProvider = nil
                activeConfiguration = nil
                notifyStartFailure(error)
            }
            return
        }

        if provider == .aliyunBailianASR {
            do {
                if let kind = RemoteASREndpointSupport.aliyunQwenRealtimeSessionKind(for: configuration.model) {
                    try startAliyunQwenRealtimeStreaming(
                        configuration: configuration,
                        hintPayload: hintPayload,
                        kind: kind
                    )
                } else {
                    try startAliyunFunStreaming(configuration: configuration, hintPayload: hintPayload)
                }
            } catch {
                VoxtLog.asrError("Aliyun realtime streaming setup failed: \(error.localizedDescription)")
                cleanupRecorderState()
                cleanupAliyunStreamingState()
                activeProvider = nil
                activeConfiguration = nil
                notifyStartFailure(error)
            }
            return
        }

        if provider == .stepFunASR,
           RemoteASRRealtimeSupport.isStepFunRealtimeModel(resolvedModel) {
            do {
                try startStepFunStreaming(configuration: configuration, hintPayload: hintPayload)
            } catch {
                VoxtLog.asrError("StepFun realtime streaming setup failed: \(error.localizedDescription)")
                cleanupRecorderState()
                cleanupStepFunStreamingState()
                activeProvider = nil
                activeConfiguration = nil
                notifyStartFailure(error)
            }
            return
        }

        if provider == .googleGeminiASR {
            do {
                try startGeminiLiveStreaming(configuration: configuration, hintPayload: hintPayload)
            } catch {
                VoxtLog.asrError("Gemini live streaming setup failed: \(error.localizedDescription)")
                cleanupRecorderState()
                cleanupGeminiLiveStreamingState()
                activeProvider = nil
                activeConfiguration = nil
                notifyStartFailure(error)
            }
            return
        }

        do {
            try startFileRecordingMode()
            if provider == .openAIWhisper,
               configuration.openAIChunkPseudoRealtimeEnabled,
               sessionAllowsRealtimeTextDisplay {
                startOpenAIPreviewLoop(configuration: configuration)
            }
        } catch {
            VoxtLog.asrError("Remote ASR recorder setup failed: \(error.localizedDescription)")
            cleanupRecorderState()
            activeProvider = nil
            activeConfiguration = nil
            notifyStartFailure(error)
        }
    }

    func stopRecording() {
        let hasPendingRealtimeSession =
            doubaoStreamingContext != nil ||
            aliyunStreamingContext != nil ||
            aliyunQwenStreamingContext != nil ||
            stepFunStreamingContext != nil ||
            geminiLiveStreamingContext != nil
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

        if activeProvider == .stepFunASR, let context = stepFunStreamingContext {
            isRequesting = true
            stopStepFunStreaming(context)
            scheduleStreamingCompletion(generationID: generationID) {
                await self.resolveStreamingResult(
                    warningMessage: "StepFun realtime final result wait failed"
                ) {
                    try await context.responseState.waitForFinalResult(timeoutSeconds: self.streamingFinalWaitTimeout)
                } fallback: {
                    await context.responseState.currentText()
                }
            }
            return
        }

        if activeProvider == .googleGeminiASR, let context = geminiLiveStreamingContext {
            isRequesting = true
            stopGeminiLiveStreaming(context)
            scheduleStreamingCompletion(generationID: generationID) {
                await self.resolveStreamingResult(
                    warningMessage: "Gemini live final result wait failed"
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

        guard let provider = activeProvider,
              let configuration = activeConfiguration
        else {
            notifyRuntimeFailure(
                NSError(
                    domain: "Voxt.RemoteASR",
                    code: -102,
                    userInfo: [NSLocalizedDescriptionKey: "Remote ASR session configuration is unavailable."]
                )
            )
            finish(with: transcribedText, generationID: generationID)
            return
        }

        isRequesting = true
        transcribeTask = Task { [weak self] in
            guard let self else { return }
            let uploadPreparation = await self.prepareUploadAudioForRemoteASR(
                originalFileURL: fileURL,
                provider: provider,
                configuration: configuration
            )
            defer {
                uploadPreparation.cleanupTemporaryUploadFileIfNeeded()
            }
            guard uploadPreparation.shouldRequestRemoteASR else {
                await MainActor.run {
                    guard self.isCurrentGeneration(generationID) else { return }
                    VoxtLog.asr(
                        "Remote ASR request skipped because upload VAD observed no speech. provider=\((self.activeProvider ?? self.selectedProvider).rawValue), originalSec=\(Self.telemetrySeconds(uploadPreparation.originalDurationSeconds))",
                        verbose: true
                    )
                    self.completedAudioArchiveURL = fileURL
                    self.transcribedText = ""
                    self.finish(with: "", generationID: generationID)
                }
                return
            }
            do {
                let result = try await self.transcribeRecordedAudio(
                    fileURL: uploadPreparation.uploadFileURL,
                    provider: provider,
                    configuration: configuration
                )
                await MainActor.run {
                    guard self.isCurrentGeneration(generationID) else { return }
                    self.transcribedText = result
                    self.completedAudioArchiveURL = fileURL
                    self.finish(with: result, generationID: generationID)
                }
            } catch {
                await MainActor.run {
                    guard self.isCurrentGeneration(generationID) else { return }
                    VoxtLog.asrError("Remote ASR transcription failed: \(error.localizedDescription)")
                    self.notifyRuntimeFailure(error)
                    self.completedAudioArchiveURL = fileURL
                    self.finish(with: self.transcribedText, generationID: generationID)
                }
            }
        }
    }

    private func prepareUploadAudioForRemoteASR(
        originalFileURL: URL,
        provider: RemoteASRProvider,
        configuration: RemoteProviderConfiguration
    ) async -> RemoteASRAudioUploadPreparation {
        let localVADMode = LocalVADMode.stored()
        let startedAt = ProcessInfo.processInfo.systemUptime
        do {
            let preparation = try await RemoteASRAudioUploadPreprocessor.prepareUploadAudio(
                originalFileURL: originalFileURL,
                provider: provider,
                configuration: configuration,
                localVADMode: localVADMode,
                useCase: voiceActivityUseCase
            )
            let elapsed = max(0, ProcessInfo.processInfo.systemUptime - startedAt)
            VoxtLog.asr(
                """
                Remote ASR upload audio prepared. provider=\(provider.rawValue), model=\(configuration.model), policy=\(preparation.policy.telemetryName), originalSec=\(Self.telemetrySeconds(preparation.originalDurationSeconds)), uploadSec=\(Self.telemetrySeconds(preparation.uploadDurationSeconds)), segments=\(preparation.speechSegmentCount), observedSpeech=\(preparation.observedSpeech.map(String.init(describing:)) ?? "nil"), elapsedMs=\(String(format: "%.1f", elapsed * 1000))
                """,
                verbose: true
            )
            return preparation
        } catch {
            VoxtLog.asrWarning(
                "Remote ASR upload VAD preprocessing failed; using original audio. provider=\(provider.rawValue), model=\(configuration.model), error=\(error.localizedDescription)"
            )
            return .original(
                fileURL: originalFileURL,
                policy: .disabled(reason: "preprocessor-error")
            )
        }
    }

    func restartCaptureForPreferredInputDevice() throws {
        if let context = doubaoStreamingContext {
            VoxtLog.asrWarning(
                "Doubao audio capture restart requested. preferredDeviceID=\(preferredInputDeviceID.map(String.init(describing:)) ?? "default"), state=\(context.debugSummary())"
            )
        stopDoubaoAudioCapture()
        didRetryDoubaoCaptureStartup = false
        try startDoubaoAudioCapture(usePreferredInputDevice: preferredInputDeviceID != nil)
        context.audioCaptureStartCount += 1
        context.lastAudioCaptureStartReason = "preferred-input-change"
        scheduleDoubaoCaptureStartupWatchdog(context)
        VoxtLog.asrWarning(
            "Doubao audio capture restart completed. preferredDeviceID=\(preferredInputDeviceID.map(String.init(describing:)) ?? "default"), state=\(context.debugSummary())"
        )
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

        if let context = stepFunStreamingContext {
            guard context.didStartAudioStream else { return }
            stopStepFunAudioCapture()
            try startStepFunAudioCapture(context: context)
            return
        }

        if let context = geminiLiveStreamingContext {
            guard context.didStartAudioStream else { return }
            stopGeminiLiveAudioCapture()
            try startGeminiLiveAudioCapture(context: context)
            return
        }

        throw NSError(
            domain: "Voxt.RemoteASR",
            code: -101,
            userInfo: [NSLocalizedDescriptionKey: "Remote ASR file recording cannot switch microphones during an active session."]
        )
    }

    private func scheduleStreamingCompletion(
        generationID: UUID,
        result: @escaping @Sendable () async -> String
    ) {
        transcribeTask = Task { [weak self] in
            guard let self else { return }
            let finalText = await result()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self.isCurrentGeneration(generationID) else { return }
                self.stageCompletedStreamingAudioArchive()
                self.transcribedText = finalText
                self.finish(with: finalText, generationID: generationID)
            }
        }
    }

    func resolveStreamingResult(
        warningMessage: String,
        waitForFinal: @escaping @Sendable () async throws -> String,
        fallback: @escaping @Sendable () async -> String
    ) async -> String {
        do {
            let text = try await waitForFinal()
            return Task.isCancelled ? "" : text
        } catch is CancellationError {
            // Cancellation is not a provider failure and must not recover partial output.
            return ""
        } catch {
            guard !Task.isCancelled else { return "" }
            let fallbackText = await fallback()
            guard !Task.isCancelled else { return "" }
            if fallbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VoxtLog.asrWarning("\(warningMessage): \(error.localizedDescription)")
                notifyRuntimeFailure(error)
            } else {
                VoxtLog.asr("\(warningMessage): recovered with partial text fallback.", verbose: true)
            }
            return fallbackText
        }
    }

    private func transcribeRecordedAudio(
        fileURL: URL,
        provider: RemoteASRProvider,
        configuration: RemoteProviderConfiguration
    ) async throws -> String {
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
        if let message = endpointSecurityValidationMessage(for: configuration) {
            throw NSError(
                domain: "Voxt.RemoteASR",
                code: -20,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }

        switch provider {
        case .openAIWhisper:
            return try await transcribeOpenAI(fileURL: fileURL, configuration: configuration, hintPayload: hintPayload)
        case .glmASR:
            return try await transcribeGLM(fileURL: fileURL, configuration: configuration, hintPayload: hintPayload)
        case .doubaoASR:
            return try await transcribeDoubao(fileURL: fileURL, configuration: configuration, hintPayload: hintPayload)
        case .aliyunBailianASR:
            return try await transcribeAliyunBailian(fileURL: fileURL, configuration: configuration)
        case .stepFunASR:
            return try await transcribeStepFun(fileURL: fileURL, configuration: configuration, hintPayload: hintPayload)
        case .xiaomiMiMoASR:
            return try await transcribeXiaomiMiMo(fileURL: fileURL, configuration: configuration, hintPayload: hintPayload)
        case .googleGeminiASR:
            throw NSError(
                domain: "Voxt.RemoteASR",
                code: -64,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Gemini live transcribe supports voice input only. File transcription and meeting mode are not available for this provider.")]
            )
        }
    }

    private func endpointSecurityValidationMessage(
        for configuration: RemoteProviderConfiguration
    ) -> String? {
        RemoteEndpointSecurityPolicy.validationMessage(
            endpoint: configuration.endpoint,
            hasCredentials: RemoteEndpointSecurityPolicy.hasExplicitCredentials(configuration),
            allowsWebSocket: true
        )
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
        let stored = RemoteModelConfigurationStore.loadConfiguration(
            providerID: provider.rawValue,
            from: raw
        ).map { [provider.rawValue: $0] } ?? [:]
        return RemoteModelConfigurationStore.resolvedASRConfiguration(provider: provider, stored: stored)
    }

    func transcribeDebugAudioFile(
        _ fileURL: URL,
        provider: RemoteASRProvider,
        configuration: RemoteProviderConfiguration
    ) async throws -> String {
        guard configuration.isConfigured else {
            throw NSError(
                domain: "Voxt.RemoteASR",
                code: -111,
                userInfo: [NSLocalizedDescriptionKey: "Remote ASR is not configured yet."]
            )
        }
        let hintPayload = resolvedHintPayload(for: provider, configuration: configuration)
        do {
            return try await transcribeAudioFile(
                fileURL: fileURL,
                provider: provider,
                configuration: configuration,
                hintPayload: hintPayload
            )
        } catch {
            let message = userVisibleRemoteErrorMessage(for: error)
            throw NSError(
                domain: "Voxt.RemoteASR",
                code: (error as NSError).code,
                userInfo: [
                    NSLocalizedDescriptionKey: message,
                    NSUnderlyingErrorKey: error,
                ]
            )
        }
    }

    func resolvedHintPayload(
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
            mlxModelRepo: configuration.model,
            dictionaryTerms: resolvedDictionaryTermsTemplateValue()
        )
    }

    private func resolvedDictionaryTermsTemplateValue() -> String {
        DictionaryEntryCollection.asrPromptTermsText(from: dictionaryEntryProvider?() ?? [])
    }

    func doubaoRequestPayload(
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
            dictionaryEnabled: true
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

    func inputCaptureTapFormat(
        inputNode: AVAudioInputNode,
        activeInputDeviceID: AudioDeviceID?,
        logContext: String
    ) -> AVAudioFormat {
        let nodeOutputFormat = inputNode.outputFormat(forBus: 0)
        let hardwareSampleRate = AudioInputDeviceManager.nominalSampleRate(for: activeInputDeviceID)
        let tapFormat = AudioInputDeviceManager.captureTapFormat(
            nodeOutputFormat: nodeOutputFormat,
            hardwareSampleRate: hardwareSampleRate
        )

        if abs(tapFormat.sampleRate - nodeOutputFormat.sampleRate) > 1 {
            VoxtLog.warning(
                "\(logContext) adjusted input tap format. deviceID=\(activeInputDeviceID.map(String.init(describing:)) ?? "default"), hardwareSampleRate=\(hardwareSampleRate.map { String(Int($0.rounded())) } ?? "unknown"), nodeSampleRate=\(Int(nodeOutputFormat.sampleRate.rounded())), tapSampleRate=\(Int(tapFormat.sampleRate.rounded()))"
            )
        }

        return tapFormat
    }

    @discardableResult
    func applyPreferredInputDeviceIfNeeded(inputNode: AVAudioInputNode) -> Bool {
        guard let preferredInputDeviceID,
              preferredInputDeviceID != AudioDeviceID(kAudioObjectUnknown),
              AudioInputDeviceManager.isAvailableInputDevice(preferredInputDeviceID)
        else {
            return false
        }
        guard let audioUnit = inputNode.audioUnit else { return false }
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
            VoxtLog.asrWarning("Remote ASR failed to switch preferred input device. status=\(status)")
            return false
        }
        return true
    }

    func audioLevelFromPCM16(_ data: Data) -> Float {
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

    nonisolated static func makeDoubaoPCM16MonoData(from buffer: AVAudioPCMBuffer) -> Data? {
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

    nonisolated static func makePCM16MonoData(from samples: [Float], inputSampleRate: Double) -> Data? {
        guard !samples.isEmpty, inputSampleRate > 0 else { return nil }
        let targetRate = 16000.0
        let ratio = targetRate / inputSampleRate
        let outputCount = max(Int(Double(samples.count) * ratio), 1)
        var data = Data(count: outputCount * MemoryLayout<Int16>.size)
        data.withUnsafeMutableBytes { rawBuffer in
            let out = rawBuffer.bindMemory(to: Int16.self)
            for index in 0..<outputCount {
                let sourcePosition = Double(index) / ratio
                let sourceIndex = min(Int(sourcePosition.rounded(.down)), samples.count - 1)
                let clamped = max(-1.0, min(1.0, samples[sourceIndex]))
                out[index] = Int16(clamped * Float(Int16.max))
            }
        }
        return data
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
        resetIntermediateTranscriptionPublishing()
        recorder?.stop()
        recorder = nil
        recordingFileURL = nil
        sampleStore.clear()
        streamingInputSampleRate = HistoryAudioArchiveSupport.targetSampleRate
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
        sampleStore.clear()
        streamingInputSampleRate = HistoryAudioArchiveSupport.targetSampleRate
        isRecording = false
        stopOpenAIPreviewLoop()
        stopMeteringTimer()
        return fileURL
    }

    func cleanupDoubaoStreamingState() {
        doubaoCaptureStartupWatchdogTask?.cancel()
        doubaoCaptureStartupWatchdogTask = nil
        didRetryDoubaoCaptureStartup = false
        doubaoCaptureUsesPreferredInputDevice = false
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

    private func cleanupStepFunStreamingState() {
        if let context = stepFunStreamingContext {
            context.isClosed = true
            context.ws.cancel(with: .normalClosure, reason: nil)
            context.session.invalidateAndCancel()
        }
        stepFunStreamingContext = nil
        stopStepFunAudioCapture()
    }

    private func cleanupGeminiLiveStreamingState() {
        if let context = geminiLiveStreamingContext {
            context.isClosed = true
            context.ws.cancel(with: .normalClosure, reason: nil)
            context.session.invalidateAndCancel()
        }
        geminiLiveStreamingContext = nil
        stopGeminiLiveAudioCapture()
    }

    private func cleanupActiveUploadTask() {
        transcribeTask?.cancel()
        transcribeTask = nil
        stopOpenAIPreviewLoop()
        isRequesting = false
    }

    func discardPendingSessionOutput() {
        recordingGenerationID = UUID()
        removeCompletedAudioArchiveIfNeeded()
        cleanupActiveUploadTask()
        cleanupRecorderState()
        cleanupDoubaoStreamingState()
        cleanupAliyunStreamingState()
        cleanupStepFunStreamingState()
        cleanupGeminiLiveStreamingState()
        activeProvider = nil
        activeConfiguration = nil
        stopRequested = false
        lastPresentedRuntimeErrorMessage = ""
    }

    func shutdownForApplicationTermination() async {
        let tasks = [
            transcribeTask,
            openAIPreviewTask,
            intermediateTranscriptionPublishTask,
            doubaoCaptureStartupWatchdogTask
        ].compactMap { $0 }
        onTranscriptionFinished = nil
        onStartFailure = nil
        onRuntimeFailure = nil
        discardPendingSessionOutput()
        for task in tasks {
            await task.value
        }
        isEnhancing = false
        isRequesting = false
        isFinalizingTranscription = false
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

    private func removeCompletedAudioArchiveIfNeeded() {
        guard let completedAudioArchiveURL else { return }
        try? FileManager.default.removeItem(at: completedAudioArchiveURL)
        self.completedAudioArchiveURL = nil
    }

    private func stageCompletedStreamingAudioArchive() {
        removeCompletedAudioArchiveIfNeeded()
        let samples = sampleStore.snapshot()
        let realtimeSummary = activeRealtimeDebugSummary() ?? "none"
        guard !samples.isEmpty else {
            VoxtLog.asrWarning(
                "Remote streaming audio archive export skipped because no local samples were captured. realtime=\(realtimeSummary)"
            )
            return
        }
        let tempURL = HistoryAudioArchiveSupport.temporaryArchiveURL(prefix: "voxt-remote-stream-history")
        do {
            if try HistoryAudioArchiveSupport.exportWAV(
                samples: samples,
                sampleRate: streamingInputSampleRate,
                to: tempURL
            ) {
                completedAudioArchiveURL = tempURL
                VoxtLog.asr(
                    "Remote streaming audio archive staged. samples=\(samples.count), sampleRate=\(Int(streamingInputSampleRate)), file=\(tempURL.lastPathComponent), realtime=\(realtimeSummary)",
                    verbose: true
                )
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            VoxtLog.asrWarning("Remote streaming completed audio archive export failed: \(error.localizedDescription)")
        }
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
            let visibleText = RecordingSessionSupport.textAfterSuppressingPromptEcho(
                normalized,
                prompt: hintPayload.prompt
            )
            guard !visibleText.isEmpty else {
                VoxtLog.asrWarning("OpenAI preview transcription suppressed because it matched ASR prompt guidance.")
                return
            }
            if normalized != openAIPreviewLastText {
                openAIPreviewLastText = visibleText
                publishIntermediateTranscription(visibleText)
            }
        } catch {
            // Preview failures are expected while recorder header is still mutating.
        }
    }

    func publishIntermediateTranscription(_ text: String) {
        guard sessionAllowsRealtimeTextDisplay else { return }
        let visibleText = RecordingSessionSupport.textAfterSuppressingPromptEcho(text)
        guard !visibleText.isEmpty else {
            VoxtLog.asrWarning("Remote ASR intermediate transcription suppressed because it matched prompt guidance.")
            return
        }
        pendingIntermediateTranscription = visibleText
        guard intermediateTranscriptionPublishTask == nil else { return }
        intermediateTranscriptionPublishTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled, let self else { return }
            let pending = self.pendingIntermediateTranscription
            self.pendingIntermediateTranscription = nil
            self.intermediateTranscriptionPublishTask = nil
            if let pending {
                self.transcribedText = pending
            }
        }
    }

    private func resetIntermediateTranscriptionPublishing() {
        intermediateTranscriptionPublishTask?.cancel()
        intermediateTranscriptionPublishTask = nil
        pendingIntermediateTranscription = nil
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

    private nonisolated static func telemetrySeconds(_ value: TimeInterval?) -> String {
        guard let value, value.isFinite else { return "nil" }
        return String(format: "%.3f", value)
    }

    func finish(with text: String, generationID: UUID) {
        guard !Task.isCancelled, isCurrentGeneration(generationID) else { return }
        cleanupActiveUploadTask()
        cleanupRecorderState()
        cleanupDoubaoStreamingState()
        cleanupAliyunStreamingState()
        cleanupStepFunStreamingState()
        cleanupGeminiLiveStreamingState()
        activeProvider = nil
        activeConfiguration = nil
        lastPresentedRuntimeErrorMessage = ""
        onTranscriptionFinished?(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func isCurrentGeneration(_ generationID: UUID) -> Bool {
        recordingGenerationID == generationID
    }

    private func notifyStartFailure(_ error: Error) {
        let message = userVisibleRemoteErrorMessage(for: error)
        guard !message.isEmpty else { return }
        onStartFailure?(message)
    }

    func notifyRuntimeFailure(_ error: Error, generationID: UUID? = nil) {
        if let generationID, !isCurrentGeneration(generationID) { return }
        let message = userVisibleRemoteErrorMessage(for: error)
        guard !message.isEmpty, message != lastPresentedRuntimeErrorMessage else { return }
        lastPresentedRuntimeErrorMessage = message
        onRuntimeFailure?(message)
    }

    private func userVisibleRemoteErrorMessage(for error: Error) -> String {
        if let conflictMessage = VoxtNetworkSession.directModeConflictMessage(for: error) {
            return conflictMessage
        }
        if let proxyUnavailableMessage = VoxtNetworkSession.activeProxyUnavailableMessage(for: error) {
            return proxyUnavailableMessage
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
