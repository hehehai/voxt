import Foundation
import AVFoundation
import Combine
@preconcurrency import MLX
import MLXAudioCore
import MLXAudioSTT
import AudioToolbox

struct MLXIntermediateCorrectionDecision: Equatable {
    let elapsedSeconds: Double
    let contextSampleCount: Int
}

struct MLXFinalizationPlan: Equatable {
    let durationSeconds: Double
    let quickPassSampleCount: Int?

    var shouldRunQuickPass: Bool {
        quickPassSampleCount != nil
    }
}

enum MLXTranscriptionPlanning {
    static func intermediateCorrectionDecision(
        sampleCount: Int,
        sampleRate: Double,
        nextCorrectionAtSeconds: Double,
        behavior: MLXModelManager.TranscriptionBehavior,
        firstCorrectionMinimumSeconds: Double,
        contextWindowSeconds: Double
    ) -> MLXIntermediateCorrectionDecision? {
        guard behavior.runsIntermediateCorrections else { return nil }
        guard sampleCount > 0 else { return nil }

        let safeSampleRate = max(sampleRate, 1)
        let elapsedSeconds = Double(sampleCount) / safeSampleRate
        guard elapsedSeconds >= firstCorrectionMinimumSeconds else { return nil }
        guard elapsedSeconds >= nextCorrectionAtSeconds else { return nil }

        return MLXIntermediateCorrectionDecision(
            elapsedSeconds: elapsedSeconds,
            contextSampleCount: Int(contextWindowSeconds * safeSampleRate)
        )
    }

    static func finalizationPlan(
        sampleCount: Int,
        sampleRate: Double,
        behavior: MLXModelManager.TranscriptionBehavior,
        quickPassMinimumDurationSeconds: Double,
        quickPassContextWindowSeconds: Double
    ) -> MLXFinalizationPlan {
        let safeSampleRate = max(sampleRate, 1)
        let durationSeconds = Double(sampleCount) / safeSampleRate
        let quickPassSampleCount: Int?

        if behavior.allowsQuickStopPass, durationSeconds >= quickPassMinimumDurationSeconds {
            quickPassSampleCount = Int(quickPassContextWindowSeconds * safeSampleRate)
        } else {
            quickPassSampleCount = nil
        }

        return MLXFinalizationPlan(
            durationSeconds: durationSeconds,
            quickPassSampleCount: quickPassSampleCount
        )
    }

    static func automaticBiases(
        for family: MLXModelFamily,
        multilingualContext: String?
    ) -> (qwenContextBias: String?, granitePromptBias: String?) {
        guard let multilingualContext, !multilingualContext.isEmpty else {
            return (nil, nil)
        }

        switch family {
        case .qwen3ASR, .graniteSpeech:
            // Local streaming MLX models may echo prompt/context guidance back into the
            // partial transcript UI, so multilingual guidance stays in the language hint only.
            return (nil, nil)
        case .senseVoice, .cohereTranscribe, .generic:
            return (nil, nil)
        }
    }
}

@MainActor
class MLXTranscriber: ObservableObject, TranscriberProtocol {
    private enum CorrectionStage {
        case intermediate
        case postStopQuick
        case postStopFinal
    }

    private struct ResolvedInferenceConfiguration {
        let generationParameters: STTGenerateParameters
        let languageHint: String?
        let qwenContextBias: String
        let granitePromptBias: String?
        let senseVoiceUseITN: Bool
    }

    private final class AudioSampleStore {
        private let lock = NSLock()
        private var samples: [Float] = []
        private var callbackCount: Int = 0

        func noteCallback() {
            lock.lock()
            defer { lock.unlock() }
            callbackCount += 1
        }

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

        func count() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return samples.count
        }

        func callbacksReceived() -> Int {
            lock.lock()
            defer { lock.unlock() }
            return callbackCount
        }

        func clear() {
            lock.lock()
            defer { lock.unlock() }
            samples.removeAll(keepingCapacity: false)
            callbackCount = 0
        }

        func tail(sampleCount: Int) -> [Float] {
            lock.lock()
            defer { lock.unlock() }
            guard sampleCount > 0, sampleCount < samples.count else { return samples }
            return Array(samples.suffix(sampleCount))
        }
    }

    @Published var isRecording = false
    @Published var isModelInitializing = false
    @Published var audioLevel: Float = 0.0
    @Published var transcribedText = ""
    @Published var isEnhancing = false
    @Published var isFinalizingTranscription = false

    var onTranscriptionFinished: ((String) -> Void)?
    var onPartialTranscription: ((String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private let sampleStore = AudioSampleStore()
    private var inputSampleRate: Double = 16000
    private let modelManager: MLXModelManager
    private var preferredInputDeviceID: AudioDeviceID?
    private let targetSampleRate = 16000

    private let correctionIntervalSeconds: Double = 6.0
    private let firstCorrectionMinimumSeconds: Double = 3.5
    private let correctionPollInterval: Duration = .milliseconds(600)
    private let intermediateContextWindowSeconds: Double = 18.0
    private let quickPassContextWindowSeconds: Double = 30.0
    private let quickPassMinimumDurationSeconds: Double = 14.0

    private var sessionRevision = 0
    private var correctionLoopTask: Task<Void, Never>?
    private var finalizationTask: Task<Void, Never>?
    private var preloadTask: Task<Void, Never>?
    private var captureWatchdogTask: Task<Void, Never>?
    private var inferenceBusy = false
    private var didRetryCaptureStartup = false
    private var activeCaptureUsesPreferredInputDevice = false
    private var loggedSampleExtractionFailure = false
    private var activeSessionBehavior = MLXModelManager.transcriptionBehavior(
        for: MLXModelManager.defaultModelRepo
    )

    private var stableCommittedText = ""
    private var lastCandidateText = ""
    private var nextCorrectionAtSeconds: Double = 6.0

    init(modelManager: MLXModelManager) {
        self.modelManager = modelManager
    }

    func setPreferredInputDevice(_ deviceID: AudioDeviceID?) {
        preferredInputDeviceID = deviceID
    }

    func requestPermissions() async -> Bool {
        let micStatus = await AVCaptureDevice.requestAccess(for: .audio)
        return micStatus
    }

    func startRecording() {
        guard !isRecording else { return }

        cancelActiveTasks()
        resetTransientState()
        sessionRevision += 1
        let revision = sessionRevision
        activeSessionBehavior = modelManager.currentTranscriptionBehavior
        activeCaptureUsesPreferredInputDevice = preferredInputDeviceID != nil
        isModelInitializing = modelManager.state != .ready
        VoxtLog.info(
            "MLX transcription session started. repo=\(modelManager.currentModelRepo), correctionMode=\(activeSessionBehavior.correctionMode), modelState=\(String(describing: modelManager.state))",
            verbose: true
        )

        do {
            try startAudioCaptureGraph()
            isRecording = true
            scheduleCaptureStartupWatchdog(revision: revision)
            startModelPreloadIfNeeded(revision: revision)

            if activeSessionBehavior.runsIntermediateCorrections {
                correctionLoopTask = Task { [weak self] in
                    await self?.runIntermediateCorrectionLoop(revision: revision)
                }
            } else {
                VoxtLog.info(
                    "MLX transcription intermediate corrections disabled for repo=\(modelManager.currentModelRepo); finalization-only mode enabled.",
                    verbose: true
                )
            }
        } catch {
            VoxtLog.error("MLXTranscriber start recording failed: \(error)")
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        stopAudioEngine()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false

        correctionLoopTask?.cancel()
        correctionLoopTask = nil

        let revision = sessionRevision
        let sampleRate = inputSampleRate
        let callbackCount = sampleStore.callbacksReceived()
        let sampleCount = sampleStore.count()
        VoxtLog.info(
            "MLX recording stop captured. callbacks=\(callbackCount), samples=\(sampleCount), sampleRate=\(Int(sampleRate))",
            verbose: true
        )

        guard sampleCount > 0 else {
            isFinalizingTranscription = false
            if callbackCount > 0 {
                VoxtLog.warning(
                    "MLX recording stopped with audio callbacks but no extracted samples. sampleRate=\(Int(sampleRate))"
                )
            }
            onTranscriptionFinished?("")
            return
        }

        isFinalizingTranscription = true
        finalizationTask?.cancel()
        finalizationTask = Task { [weak self] in
            await self?.runFinalizationPipeline(revision: revision, sampleRate: sampleRate)
        }
    }

    /// Triggers an intermediate transcription pass while recording.
    /// Used to improve responsiveness during short pauses in speech.
    func forceIntermediateTranscription() {
        guard isRecording, activeSessionBehavior.runsIntermediateCorrections else { return }
        let revision = sessionRevision
        let sampleRate = inputSampleRate
        Task { [weak self] in
            _ = await self?.runCorrectionPass(
                stage: .intermediate,
                revision: revision,
                explicitSamples: nil,
                sampleRate: sampleRate
            )
        }
    }

    func restartCaptureForPreferredInputDevice() throws {
        guard isRecording else { return }
        activeCaptureUsesPreferredInputDevice = preferredInputDeviceID != nil
        try startAudioCaptureGraph(usePreferredInputDevice: activeCaptureUsesPreferredInputDevice)
    }

    private func runIntermediateCorrectionLoop(revision: Int) async {
        while !Task.isCancelled, revision == sessionRevision, isRecording {
            do {
                try await Task.sleep(for: correctionPollInterval)
            } catch {
                return
            }

            guard revision == sessionRevision, isRecording else { return }
            let sampleCount = sampleStore.count()
            guard let decision = MLXTranscriptionPlanning.intermediateCorrectionDecision(
                sampleCount: sampleCount,
                sampleRate: inputSampleRate,
                nextCorrectionAtSeconds: nextCorrectionAtSeconds,
                behavior: activeSessionBehavior,
                firstCorrectionMinimumSeconds: firstCorrectionMinimumSeconds,
                contextWindowSeconds: intermediateContextWindowSeconds
            ) else { continue }
            let intermediateSamples = sampleStore.tail(sampleCount: decision.contextSampleCount)

            _ = await runCorrectionPass(
                stage: .intermediate,
                revision: revision,
                explicitSamples: intermediateSamples,
                sampleRate: inputSampleRate
            )

            nextCorrectionAtSeconds = decision.elapsedSeconds + correctionIntervalSeconds
        }
    }

    private func runFinalizationPipeline(revision: Int, sampleRate: Double) async {
        defer {
            if revision == sessionRevision {
                isFinalizingTranscription = false
            }
        }

        let snapshot = sampleStore.snapshot()
        guard !snapshot.isEmpty else {
            onTranscriptionFinished?("")
            sampleStore.clear()
            return
        }

        let plan = MLXTranscriptionPlanning.finalizationPlan(
            sampleCount: snapshot.count,
            sampleRate: sampleRate,
            behavior: activeSessionBehavior,
            quickPassMinimumDurationSeconds: quickPassMinimumDurationSeconds,
            quickPassContextWindowSeconds: quickPassContextWindowSeconds
        )
        VoxtLog.info(
            "MLX finalization started. repo=\(modelManager.currentModelRepo), audioSec=\(String(format: "%.2f", plan.durationSeconds)), quickPass=\(plan.shouldRunQuickPass)",
            verbose: true
        )
        let quickSource: [Float]?
        if let quickPassSampleCount = plan.quickPassSampleCount {
            quickSource = latestWindow(from: snapshot, maxCount: quickPassSampleCount)
        } else {
            quickSource = nil
        }

        let quickText: String?
        if let quickSource {
            quickText = await runCorrectionPass(
                stage: .postStopQuick,
                revision: revision,
                explicitSamples: quickSource,
                sampleRate: sampleRate
            )
        } else {
            quickText = nil
        }

        let finalText = await runCorrectionPass(
            stage: .postStopFinal,
            revision: revision,
            explicitSamples: snapshot,
            sampleRate: sampleRate
        )

        guard revision == sessionRevision else { return }
        let resolved = normalizeText(finalText ?? quickText ?? transcribedText)
        transcribedText = resolved
        publishPartial(resolved)
        onTranscriptionFinished?(resolved)
        VoxtLog.info(
            "MLX finalization completed. repo=\(modelManager.currentModelRepo), audioSec=\(String(format: "%.2f", plan.durationSeconds)), textChars=\(resolved.count)",
            verbose: true
        )
        sampleStore.clear()
    }

    private func runCorrectionPass(
        stage: CorrectionStage,
        revision: Int,
        explicitSamples: [Float]?,
        sampleRate: Double
    ) async -> String? {
        if stage == .intermediate, inferenceBusy {
            VoxtLog.info("MLX intermediate correction skipped because inference is still busy.", verbose: true)
            return nil
        }

        while inferenceBusy {
            try? await Task.sleep(for: .milliseconds(80))
        }
        inferenceBusy = true
        defer { inferenceBusy = false }

        guard revision == sessionRevision else { return nil }
        let rawSamples = explicitSamples ?? sampleStore.snapshot()
        guard !rawSamples.isEmpty else { return nil }
        let audioSeconds = Double(rawSamples.count) / safeSampleRate(sampleRate)
        let repo = modelManager.currentModelRepo
        let passStartedAt = Date()

        do {
            modelManager.beginActiveUse()
            defer { modelManager.endActiveUse() }
            let model = try await modelManager.loadModel()
            await MainActor.run {
                self.isModelInitializing = false
            }
            let audioSamples = try prepareInputSamples(rawSamples, sampleRate: sampleRate)
            let inferenceConfiguration = resolvedInferenceConfiguration(for: stage)
            let inferenceStartedAt = Date()
            let (streamedText, finalOutput) = try await runStreamingInference(
                model: model,
                audioSamples: audioSamples,
                inferenceConfiguration: inferenceConfiguration
            )
            let inferenceElapsedMs = Int(Date().timeIntervalSince(inferenceStartedAt) * 1000)

            let candidate = normalizeText(finalOutput?.text ?? streamedText)
            guard !candidate.isEmpty else { return nil }
            applyCandidate(candidate, stage: stage)
            let elapsedMs = Int(Date().timeIntervalSince(passStartedAt) * 1000)
            VoxtLog.info(
                "MLX correction pass completed. repo=\(repo), stage=\(stageLabel(for: stage)), audioSec=\(String(format: "%.2f", audioSeconds)), elapsedMs=\(elapsedMs), inferenceMs=\(inferenceElapsedMs), textChars=\(candidate.count)",
                verbose: true
            )
            return candidate
        } catch {
            await MainActor.run {
                self.isModelInitializing = false
            }
            let elapsedMs = Int(Date().timeIntervalSince(passStartedAt) * 1000)
            VoxtLog.error(
                "MLXTranscriber \(stageLabel(for: stage)) pass failed. repo=\(repo), audioSec=\(String(format: "%.2f", audioSeconds)), elapsedMs=\(elapsedMs), error=\(error.localizedDescription)"
            )
            return nil
        }
    }

    private func resetTransientState() {
        sampleStore.clear()
        transcribedText = ""
        audioLevel = 0
        isModelInitializing = false
        isFinalizingTranscription = false
        didRetryCaptureStartup = false
        activeCaptureUsesPreferredInputDevice = preferredInputDeviceID != nil
        stableCommittedText = ""
        lastCandidateText = ""
        nextCorrectionAtSeconds = correctionIntervalSeconds
        loggedSampleExtractionFailure = false
    }

    private func stopAudioEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }

    private func startAudioCaptureGraph(usePreferredInputDevice: Bool? = nil) throws {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.reset()

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        let shouldUsePreferredInputDevice = usePreferredInputDevice ?? activeCaptureUsesPreferredInputDevice
        activeCaptureUsesPreferredInputDevice = shouldUsePreferredInputDevice
        if shouldUsePreferredInputDevice {
            applyPreferredInputDeviceIfNeeded(inputNode: inputNode)
        }
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputSampleRate = recordingFormat.sampleRate
        let sampleStore = self.sampleStore

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            sampleStore.noteCallback()

            guard let samples = AudioLevelMeter.monoSamples(from: buffer), !samples.isEmpty else {
                if !self.loggedSampleExtractionFailure {
                    self.loggedSampleExtractionFailure = true
                    VoxtLog.warning(
                        """
                        MLX audio sample extraction failed. sampleRate=\(Int(buffer.format.sampleRate)), channels=\(buffer.format.channelCount), format=\(buffer.format.commonFormat.rawValue), interleaved=\(buffer.format.isInterleaved)
                        """
                    )
                }
                return
            }

            sampleStore.append(samples)
            let normalized = AudioLevelMeter.normalizedLevel(fromSamples: samples)
            Task { @MainActor [weak self] in
                self?.audioLevel = normalized
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        VoxtLog.info(
            "MLX audio capture started. sampleRate=\(Int(recordingFormat.sampleRate)), channels=\(recordingFormat.channelCount), format=\(recordingFormat.commonFormat.rawValue), interleaved=\(recordingFormat.isInterleaved), routing=\(shouldUsePreferredInputDevice ? "preferred" : "system-default"), deviceID=\(shouldUsePreferredInputDevice ? (preferredInputDeviceID.map(String.init(describing:)) ?? "default") : "system-default")",
            verbose: true
        )
    }

    private func cancelActiveTasks() {
        correctionLoopTask?.cancel()
        correctionLoopTask = nil
        finalizationTask?.cancel()
        finalizationTask = nil
        isFinalizingTranscription = false
        preloadTask?.cancel()
        preloadTask = nil
        captureWatchdogTask?.cancel()
        captureWatchdogTask = nil
    }

    private func safeSampleRate(_ value: Double) -> Double {
        max(value, 1)
    }

    private func latestWindow(from samples: [Float], maxCount: Int) -> [Float] {
        guard maxCount > 0, samples.count > maxCount else { return samples }
        return Array(samples.suffix(maxCount))
    }

    private func publishPartial(_ text: String) {
        onPartialTranscription?(text)
    }

    private func startModelPreloadIfNeeded(revision: Int) {
        guard activeSessionBehavior.preloadsOnRecordingStart else {
            isModelInitializing = false
            return
        }
        guard modelManager.state != .ready else {
            isModelInitializing = false
            return
        }

        preloadTask?.cancel()
        preloadTask = Task { [weak self] in
            guard let self else { return }
            let startedAt = Date()
            do {
                self.modelManager.beginActiveUse()
                defer { self.modelManager.endActiveUse() }
                _ = try await self.modelManager.loadModel()
                guard !Task.isCancelled, revision == self.sessionRevision else { return }
                await MainActor.run {
                    self.isModelInitializing = false
                }
                let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                VoxtLog.info(
                    "MLX transcription preload completed. repo=\(self.modelManager.currentModelRepo), elapsedMs=\(elapsedMs)",
                    verbose: true
                )
            } catch {
                guard !Task.isCancelled else { return }
                let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                VoxtLog.warning(
                    "MLX transcription preload failed. repo=\(self.modelManager.currentModelRepo), elapsedMs=\(elapsedMs), error=\(error.localizedDescription)"
                )
            }
        }
    }

    private func scheduleCaptureStartupWatchdog(revision: Int) {
        captureWatchdogTask?.cancel()
        captureWatchdogTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(1.2))
            } catch {
                return
            }
            await self?.recoverAudioCaptureIfNeeded(revision: revision)
        }
    }

    private func recoverAudioCaptureIfNeeded(revision: Int) async {
        guard revision == sessionRevision, isRecording else { return }
        guard sampleStore.callbacksReceived() == 0 else { return }
        guard !didRetryCaptureStartup else { return }

        didRetryCaptureStartup = true
        let shouldFallbackToSystemDefault = preferredInputDeviceID != nil && activeCaptureUsesPreferredInputDevice
        if shouldFallbackToSystemDefault {
            VoxtLog.warning(
                "MLX audio capture produced no initial callbacks. Retrying once with system default input instead of the preferred device."
            )
        } else {
            VoxtLog.warning("MLX audio capture produced no initial callbacks. Restarting input graph once.")
        }

        do {
            try startAudioCaptureGraph(usePreferredInputDevice: shouldFallbackToSystemDefault ? false : activeCaptureUsesPreferredInputDevice)
            scheduleCaptureStartupWatchdog(revision: revision)
        } catch {
            VoxtLog.error("MLX audio capture recovery failed: \(error)")
        }
    }

    private func applyCandidate(_ candidate: String, stage: CorrectionStage) {
        switch stage {
        case .postStopFinal:
            transcribedText = candidate
            stableCommittedText = candidate
            lastCandidateText = candidate
            publishPartial(candidate)
        case .intermediate, .postStopQuick:
            if lastCandidateText.isEmpty {
                lastCandidateText = candidate
                transcribedText = candidate
                publishPartial(candidate)
                return
            }

            let stablePrefix = longestCommonPrefix(lastCandidateText, candidate)
            if stablePrefix.count > stableCommittedText.count {
                stableCommittedText = stablePrefix
            }

            lastCandidateText = candidate
            let merged = mergeStablePrefix(stableCommittedText, candidate: candidate)
            transcribedText = merged
            publishPartial(merged)
        }
    }

    private func mergeStablePrefix(_ stable: String, candidate: String) -> String {
        guard !stable.isEmpty else { return candidate }
        guard !candidate.isEmpty else { return stable }
        if candidate.hasPrefix(stable) {
            return candidate
        }

        let stableChars = Array(stable)
        let candidateChars = Array(candidate)
        let maxOverlap = min(stableChars.count, candidateChars.count)

        for overlap in stride(from: maxOverlap, through: 1, by: -1) {
            let stableSuffix = String(stableChars.suffix(overlap))
            let candidatePrefix = String(candidateChars.prefix(overlap))
            if stableSuffix == candidatePrefix {
                return stable + String(candidateChars.dropFirst(overlap))
            }
        }

        return stable + " " + candidate
    }

    private func longestCommonPrefix(_ lhs: String, _ rhs: String) -> String {
        var leftIndex = lhs.startIndex
        var rightIndex = rhs.startIndex

        while leftIndex < lhs.endIndex, rightIndex < rhs.endIndex, lhs[leftIndex] == rhs[rightIndex] {
            leftIndex = lhs.index(after: leftIndex)
            rightIndex = rhs.index(after: rightIndex)
        }

        return String(lhs[..<leftIndex])
    }

    private func normalizeText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolvedInferenceConfiguration(for stage: CorrectionStage) -> ResolvedInferenceConfiguration {
        let hintPayload = resolvedHintPayload()
        let tuningSettings = resolvedLocalTuningSettings()
        let userLanguageCodes = UserMainLanguageOption.storedSelection(
            from: UserDefaults.standard.string(forKey: AppPreferenceKey.userMainLanguageCodes)
        )
        let family = MLXModelFamily.family(for: modelManager.currentModelRepo)
        let automaticBiases = MLXTranscriptionPlanning.automaticBiases(
            for: family,
            multilingualContext: hintPayload.multilingualContext
        )
        let chunkDuration: Float
        let minChunkDuration: Float
        switch tuningSettings.preset {
        case .balanced:
            chunkDuration = 1200
            minChunkDuration = 1
        case .accuracyFirst:
            chunkDuration = 90
            minChunkDuration = 2.5
        }

        let languageHint = family == .graniteSpeech ? nil : hintPayload.language
        let maxTokens: Int
        switch stage {
        case .intermediate:
            maxTokens = 1024
        case .postStopQuick:
            maxTokens = 2048
        case .postStopFinal:
            maxTokens = 8192
        }

        return ResolvedInferenceConfiguration(
            generationParameters: STTGenerateParameters(
                maxTokens: maxTokens,
                temperature: 0.0,
                topP: 0.95,
                topK: 0,
                verbose: false,
                language: languageHint,
                chunkDuration: chunkDuration,
                minChunkDuration: minChunkDuration
            ),
            languageHint: languageHint,
            qwenContextBias: mergedBiasText(
                resolvedBiasTemplate(tuningSettings.qwenContextBias, userLanguageCodes: userLanguageCodes),
                autoBias: automaticBiases.qwenContextBias
            ),
            granitePromptBias: mergedOptionalBiasText(
                resolvedBiasTemplate(tuningSettings.granitePromptBias, userLanguageCodes: userLanguageCodes),
                autoBias: automaticBiases.granitePromptBias
            ),
            senseVoiceUseITN: tuningSettings.senseVoiceUseITN
        )
    }

    private func resolvedHintPayload() -> ResolvedASRHintPayload {
        let defaults = UserDefaults.standard
        let settings = ASRHintSettingsStore.resolvedSettings(
            for: .mlxAudio,
            rawValue: defaults.string(forKey: AppPreferenceKey.asrHintSettings)
        )
        let userLanguageCodes = UserMainLanguageOption.storedSelection(
            from: defaults.string(forKey: AppPreferenceKey.userMainLanguageCodes)
        )
        return ASRHintResolver.resolve(
            target: .mlxAudio,
            settings: settings,
            userLanguageCodes: userLanguageCodes,
            mlxModelRepo: modelManager.currentModelRepo
        )
    }

    private func resolvedLocalTuningSettings() -> MLXLocalTuningSettings {
        MLXLocalTuningSettingsStore.resolvedSettings(
            for: modelManager.currentModelRepo,
            rawValue: UserDefaults.standard.string(forKey: AppPreferenceKey.mlxLocalASRTuningSettings)
        )
    }

    private func stageLabel(for stage: CorrectionStage) -> String {
        switch stage {
        case .intermediate: return "intermediate"
        case .postStopQuick: return "post-stop quick"
        case .postStopFinal: return "post-stop final"
        }
    }

    private func mergedBiasText(_ userBias: String, autoBias: String?) -> String {
        let trimmedUserBias = userBias.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAutoBias = autoBias?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch (trimmedUserBias.isEmpty, trimmedAutoBias.isEmpty) {
        case (true, true):
            return ""
        case (false, true):
            return trimmedUserBias
        case (true, false):
            return trimmedAutoBias
        case (false, false):
            return "\(trimmedAutoBias)\n\(trimmedUserBias)"
        }
    }

    private func mergedOptionalBiasText(_ userBias: String, autoBias: String?) -> String? {
        let merged = mergedBiasText(userBias, autoBias: autoBias)
        return merged.isEmpty ? nil : merged
    }

    private func resolvedBiasTemplate(_ template: String, userLanguageCodes: [String]) -> String {
        ASRHintResolver.resolveTemplateVariables(
            in: template,
            userLanguageCodes: userLanguageCodes
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func prepareInputSamples(_ samples: [Float], sampleRate: Double) throws -> [Float] {
        if abs(sampleRate - Double(targetSampleRate)) > 1.0 {
            return try resampleAudio(samples, from: Int(sampleRate), to: targetSampleRate)
        }

        return samples
    }

    private func runStreamingInference(
        model: any STTGenerationModel,
        audioSamples: [Float],
        inferenceConfiguration: ResolvedInferenceConfiguration
    ) async throws -> (streamedText: String, finalOutput: STTOutput?) {
        let audioArray = MLXArray(audioSamples)
        var streamedText = ""
        var finalOutput: STTOutput?

        let stream: AsyncThrowingStream<STTGeneration, Error>
        let generationParameters = inferenceConfiguration.generationParameters
        if let qwenModel = model as? Qwen3ASRModel {
            stream = qwenModel.generateStream(
                audio: audioArray,
                maxTokens: generationParameters.maxTokens,
                temperature: generationParameters.temperature,
                context: inferenceConfiguration.qwenContextBias,
                language: inferenceConfiguration.languageHint,
                chunkDuration: generationParameters.chunkDuration,
                minChunkDuration: generationParameters.minChunkDuration
            )
        } else if let graniteModel = model as? GraniteSpeechModel {
            stream = graniteModel.generateStream(
                audio: audioArray,
                maxTokens: generationParameters.maxTokens,
                temperature: generationParameters.temperature,
                prompt: inferenceConfiguration.granitePromptBias,
                language: nil
            )
        } else if let senseVoiceModel = model as? SenseVoiceModel {
            let output = senseVoiceModel.generate(
                audio: audioArray,
                language: inferenceConfiguration.languageHint ?? "auto",
                useITN: inferenceConfiguration.senseVoiceUseITN,
                verbose: generationParameters.verbose
            )
            stream = AsyncThrowingStream { continuation in
                continuation.yield(.result(output))
                continuation.finish()
            }
        } else {
            stream = model.generateStream(audio: audioArray, generationParameters: generationParameters)
        }

        for try await event in stream {
            switch event {
            case .token(let token):
                streamedText += token
                await Task.yield()
            case .info:
                break
            case .result(let output):
                finalOutput = output
            }
        }

        return (streamedText, finalOutput)
    }

    func transcribeMeetingChunk(samples: [Float], sampleRate: Double) async -> String? {
        guard !samples.isEmpty else { return nil }

        do {
            modelManager.beginActiveUse()
            defer { modelManager.endActiveUse() }
            let model = try await modelManager.loadModel()
            isModelInitializing = false
            let audioSamples = try prepareInputSamples(samples, sampleRate: sampleRate)
            let inferenceConfiguration = resolvedInferenceConfiguration(for: .postStopFinal)
            let (streamedText, finalOutput) = try await runStreamingInference(
                model: model,
                audioSamples: audioSamples,
                inferenceConfiguration: inferenceConfiguration
            )
            let candidate = normalizeText(finalOutput?.text ?? streamedText)
            return candidate.isEmpty ? nil : candidate
        } catch {
            isModelInitializing = false
            VoxtLog.error("MLX meeting transcription failed: \(error)")
            return nil
        }
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
            VoxtLog.warning("Unable to switch input device. status=\(status)")
        }
    }
}
