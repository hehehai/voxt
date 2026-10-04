// RemoteASRTranscriber.swift
// Provides Remote ASRTranscriber for remote ASR adapters.

import Foundation
import AVFoundation
import CoreAudio
import Combine

@MainActor
class RemoteASRTranscriber: NSObject, ObservableObject, TranscriberProtocol {
    /// Written from the microphone delivery queue; every access takes `lock`.
    nonisolated final class AudioSampleStore: @unchecked Sendable {
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

    /// One capture per recording, shared by realtime providers and file recording.
    var microphoneCaptureSession: MicrophoneCaptureSession?
    var microphoneCaptureStartTask: Task<Void, Never>?
    var didRetryMicrophoneWithSystemDefault = false
    private var isFileRecordingActive = false
    var doubaoStreamingContext: DoubaoStreamingContext?
    var aliyunStreamingContext: AliyunFunStreamingContext?
    var aliyunQwenStreamingContext: AliyunQwenStreamingContext?
    var stepFunStreamingContext: StepFunStreamingContext?
    var geminiLiveStreamingContext: GeminiLiveStreamingContext?
    private let openAIPreview = RemoteASRPreviewController()
    private var completedAudioArchiveURL: URL?
    let sampleStore = AudioSampleStore()
    var streamingInputSampleRate: Double = HistoryAudioArchiveSupport.targetSampleRate
    private let transcriptionTasks = TrackedTaskStore()
    var stopRequested = false
    var activeProvider: RemoteASRProvider?
    var activeConfiguration: RemoteProviderConfiguration?
    var preferredInputDeviceID: AudioDeviceID?
    private let streamingFinalWaitTimeout: TimeInterval = 20
    private var lastPresentedRuntimeErrorMessage = ""
    private var pendingIntermediateTranscription: String?
    private var intermediateTranscriptionPublishTask: Task<Void, Never>?
    var recordingGenerationID = UUID()
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

        startFileRecordingMode()
        if provider == .openAIWhisper,
           configuration.openAIChunkPseudoRealtimeEnabled,
           sessionAllowsRealtimeTextDisplay {
            startOpenAIPreviewLoop(configuration: configuration)
        }
    }

    func stopRecording() {
        let hasPendingRealtimeSession =
            doubaoStreamingContext != nil ||
            aliyunStreamingContext != nil ||
            aliyunQwenStreamingContext != nil ||
            stepFunStreamingContext != nil ||
            geminiLiveStreamingContext != nil
        guard isRecording || hasPendingRealtimeSession || isFileRecordingActive else { return }
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
        transcriptionTasks.start { [weak self] in
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

    /// Moves the running capture (realtime or file recording) to the current preferred
    /// device. The delivered audio format does not change, so provider streams continue.
    func restartCaptureForPreferredInputDevice() throws {
        guard let microphoneCaptureSession else { return }
        VoxtLog.asr(
            "Remote ASR microphone switch requested. preferredDeviceID=\(preferredInputDeviceID.map(String.init(describing:)) ?? "default"), realtime=\(activeRealtimeDebugSummary() ?? "none")"
        )
        microphoneCaptureSession.switchDevice(to: preferredInputDeviceID)
    }

    private func scheduleStreamingCompletion(
        generationID: UUID,
        result: @escaping @Sendable () async -> String
    ) {
        transcriptionTasks.start { [weak self] in
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

    /// Records the selected microphone for upload; the WAV file is written when recording
    /// stops. (`AVAudioRecorder` always records the system default input.)
    private func startFileRecordingMode() {
        isFileRecordingActive = true
        startMicrophoneCapture(context: "file")
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
            let message = RemoteASRErrorPresentation.message(for: error)
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

    private func cleanupRecorderState() {
        resetIntermediateTranscriptionPublishing()
        if isFileRecordingActive {
            stopStreamingAudioCapture()
            isFileRecordingActive = false
        }
        sampleStore.clear()
        streamingInputSampleRate = HistoryAudioArchiveSupport.targetSampleRate
        isRecording = false
        stopRequested = false
        stopOpenAIPreviewLoop()
    }

    /// Stops file recording and writes the captured audio as the upload file.
    private func stopFileRecordingCapture() -> URL? {
        guard isFileRecordingActive else { return nil }
        isFileRecordingActive = false
        stopStreamingAudioCapture()
        stopOpenAIPreviewLoop()
        let samples = sampleStore.snapshot()
        let sampleRate = streamingInputSampleRate
        sampleStore.clear()
        streamingInputSampleRate = HistoryAudioArchiveSupport.targetSampleRate
        isRecording = false

        let fileURL = HistoryAudioArchiveSupport.temporaryArchiveURL(prefix: "voxt-remote-asr")
        do {
            guard try HistoryAudioArchiveSupport.exportWAV(samples: samples, sampleRate: sampleRate, to: fileURL) else {
                VoxtLog.asrWarning("Remote ASR file recording captured no audio.")
                return nil
            }
            return fileURL
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            VoxtLog.asrError("Remote ASR file recording could not be written: \(error.localizedDescription)")
            return nil
        }
    }

    func cleanupDoubaoStreamingState() {
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
        transcriptionTasks.cancelAll()
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
            intermediateTranscriptionPublishTask,
            microphoneCaptureStartTask
        ].compactMap { $0 }
        let captureSession = microphoneCaptureSession
        onTranscriptionFinished = nil
        onStartFailure = nil
        onRuntimeFailure = nil
        discardPendingSessionOutput()
        await captureSession?.stopAndWait()
        await transcriptionTasks.waitForAll()
        await openAIPreview.waitForIdle()
        for task in tasks {
            await task.value
        }
        isEnhancing = false
        isRequesting = false
        isFinalizingTranscription = false
    }

    private func startOpenAIPreviewLoop(configuration: RemoteProviderConfiguration) {
        let generationID = recordingGenerationID
        openAIPreview.start(
            shouldRun: { [weak self] in
                guard let self else { return false }
                return self.isRecording && self.isCurrentGeneration(generationID)
            },
            transcribe: { [weak self] in
                await self?.runOpenAIPreviewPass(configuration: configuration)
            },
            publish: { [weak self] in self?.publishIntermediateTranscription($0) }
        )
    }

    private func stopOpenAIPreviewLoop() {
        openAIPreview.cancel()
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

    private func runOpenAIPreviewPass(configuration: RemoteProviderConfiguration) async -> String? {
        guard isRecording, isFileRecordingActive, selectedProvider == .openAIWhisper else { return nil }

        // Skip previews shorter than ~0.2 s of audio.
        let samples = sampleStore.snapshot()
        guard samples.count >= Int(streamingInputSampleRate * 0.2) else { return nil }
        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxt-openai-preview-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        defer { try? FileManager.default.removeItem(at: snapshotURL) }

        do {
            guard try HistoryAudioArchiveSupport.exportWAV(
                samples: samples,
                sampleRate: streamingInputSampleRate,
                to: snapshotURL
            ) else { return nil }

            let hintPayload = resolvedHintPayload(for: .openAIWhisper, configuration: configuration)
            let preview = try await transcribeOpenAI(
                fileURL: snapshotURL,
                configuration: configuration,
                hintPayload: hintPayload
            )
            let normalized = preview.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return nil }
            let visibleText = RecordingSessionSupport.textAfterSuppressingPromptEcho(
                normalized,
                prompt: hintPayload.prompt
            )
            guard !visibleText.isEmpty else {
                VoxtLog.asrWarning("OpenAI preview transcription suppressed because it matched ASR prompt guidance.")
                return nil
            }
            return visibleText
        } catch {
            // Preview failures are transient; the final pass transcribes the full recording.
            return nil
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
        let message = RemoteASRErrorPresentation.message(for: error)
        guard !message.isEmpty else { return }
        onStartFailure?(message)
    }

    func notifyRuntimeFailure(_ error: Error, generationID: UUID? = nil) {
        if let generationID, !isCurrentGeneration(generationID) { return }
        let message = RemoteASRErrorPresentation.message(for: error)
        guard !message.isEmpty, message != lastPresentedRuntimeErrorMessage else { return }
        lastPresentedRuntimeErrorMessage = message
        onRuntimeFailure?(message)
    }

}
