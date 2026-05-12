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

struct MLXRealtimeReplayEvent: Equatable {
    let elapsedSeconds: Double
    let text: String
    let isFinal: Bool
    let source: String
}

struct MLXRealtimeReplayDiagnostics: Equatable {
    let events: [MLXRealtimeReplayEvent]
    let trace: [String]
}

struct MLXFinalizationPlan: Equatable {
    let durationSeconds: Double
    let quickPassSampleCount: Int?

    var shouldRunQuickPass: Bool {
        quickPassSampleCount != nil
    }
}

enum MLXCorrectionPassKind: Equatable {
    case intermediate
    case postStopQuick
    case postStopFinal
}

enum MLXCorrectionPassSchedulingDecision: Equatable {
    case startImmediately
    case waitForInFlightPass
    case skipRequestedPass
    case interruptInFlightPass
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

    static func correctionPassSchedulingDecision(
        requestedPass: MLXCorrectionPassKind,
        inFlightPass: MLXCorrectionPassKind?
    ) -> MLXCorrectionPassSchedulingDecision {
        guard let inFlightPass else { return .startImmediately }
        if requestedPass == .intermediate {
            return .skipRequestedPass
        }
        if inFlightPass == .intermediate {
            return .interruptInFlightPass
        }
        return .waitForInFlightPass
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

    static func mergedHiddenPostStopPreview(base: String, candidate: String) -> String {
        let stableBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let stableCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !stableBase.isEmpty else { return stableCandidate }
        guard !stableCandidate.isEmpty else { return stableBase }
        if stableBase == stableCandidate {
            return stableCandidate
        }
        let maxTrustedCandidateCount = stableBase.count + max(48, stableBase.count / 3)
        if stableCandidate.count > maxTrustedCandidateCount,
           !stableCandidate.contains(stableBase) {
            return stableBase
        }
        if stableBase.contains(stableCandidate) {
            return stableBase
        }
        if stableCandidate.contains(stableBase) {
            return stableCandidate
        }
        if endsWithSentenceBoundary(stableBase),
           let stitched = stitchedSentenceContinuation(
               base: stableBase,
               candidate: stableCandidate,
               minimumOverlap: 10,
               maximumCandidatePrefixNoise: 4
           ) {
            return stitched
        }

        let sharedPrefix = longestCommonPrefix(stableBase, stableCandidate).count
        let suffixPrefixOverlap = suffixPrefixOverlapCount(stableBase, stableCandidate)
        if suffixPrefixOverlap == 0 && sharedPrefix < 8 {
            if !hasSharedWindow(stableBase, stableCandidate, minLength: 12),
               endsWithSentenceBoundary(stableBase) {
                let combined = stableBase + stableCandidate
                let maxSafeCombinedCount = stableBase.count + stableCandidate.count + 4
                if combined.count <= maxSafeCombinedCount {
                    return combined
                }
            }
            return stableBase.count >= stableCandidate.count ? stableBase : stableCandidate
        }

        let merged = mergeStablePrefix(stableBase, candidate: stableCandidate)
        let growthBudget = max(16, min(stableBase.count, stableCandidate.count) / 4)
        let maxSafeCount = max(stableBase.count, stableCandidate.count) + growthBudget
        if merged.count > maxSafeCount {
            return stableBase.count >= stableCandidate.count ? stableBase : stableCandidate
        }

        return merged
    }

    private static func mergeStablePrefix(_ stable: String, candidate: String) -> String {
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

    private static func longestCommonPrefix(_ lhs: String, _ rhs: String) -> String {
        var leftIndex = lhs.startIndex
        var rightIndex = rhs.startIndex

        while leftIndex < lhs.endIndex, rightIndex < rhs.endIndex, lhs[leftIndex] == rhs[rightIndex] {
            leftIndex = lhs.index(after: leftIndex)
            rightIndex = rhs.index(after: rightIndex)
        }

        return String(lhs[..<leftIndex])
    }

    private static func suffixPrefixOverlapCount(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        let maxOverlap = min(left.count, right.count)

        for overlap in stride(from: maxOverlap, through: 1, by: -1) {
            if Array(left.suffix(overlap)) == Array(right.prefix(overlap)) {
                return overlap
            }
        }

        return 0
    }

    private static func hasSharedWindow(_ lhs: String, _ rhs: String, minLength: Int) -> Bool {
        guard min(lhs.count, rhs.count) >= minLength else { return false }
        let shorter = lhs.count <= rhs.count ? lhs : rhs
        let longer = lhs.count <= rhs.count ? rhs : lhs
        let chars = Array(shorter)
        let upperBound = chars.count - minLength
        guard upperBound >= 0 else { return false }

        for start in 0...upperBound {
            let window = String(chars[start..<(start + minLength)])
            if longer.contains(window) {
                return true
            }
        }
        return false
    }

    private static func stitchedSentenceContinuation(
        base: String,
        candidate: String,
        minimumOverlap: Int,
        maximumCandidatePrefixNoise: Int
    ) -> String? {
        let baseChars = Array(base)
        let candidateChars = Array(candidate)
        guard baseChars.count >= minimumOverlap, candidateChars.count >= minimumOverlap else {
            return nil
        }

        let maxNoise = min(maximumCandidatePrefixNoise, max(candidateChars.count - minimumOverlap, 0))
        for prefixNoise in 0...maxNoise {
            let remaining = candidateChars.count - prefixNoise
            guard remaining >= minimumOverlap else { continue }
            let maxOverlap = min(baseChars.count, remaining)
            for overlap in stride(from: maxOverlap, through: minimumOverlap, by: -1) {
                let baseSuffix = Array(baseChars.suffix(overlap))
                let candidateSlice = Array(candidateChars[prefixNoise..<(prefixNoise + overlap)])
                if baseSuffix == candidateSlice {
                    let continuationStart = prefixNoise + overlap
                    let continuation = continuationStart < candidateChars.count
                        ? String(candidateChars[continuationStart...])
                        : ""
                    return base + continuation
                }
            }
        }

        return nil
    }

    private static func endsWithSentenceBoundary(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else {
            return false
        }
        return "。！？!?；;：:）)]」』\"”".contains(last)
    }
}

@MainActor
class MLXTranscriber: ObservableObject, TranscriberProtocol {
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
    var dictionaryEntryProvider: (() -> [DictionaryEntry])?

    private let audioEngine = AVAudioEngine()
    private let sampleStore = AudioSampleStore()
    private var inputSampleRate: Double = 16000
    private var completedAudioArchiveURL: URL?
    private let modelManager: MLXModelManager
    private var preferredInputDeviceID: AudioDeviceID?
    private let targetSampleRate = 16000

    private let liveCorrectionIntervalSeconds: Double = 6.0
    private let hiddenCorrectionIntervalSeconds: Double = 3.2
    private let liveFirstCorrectionMinimumSeconds: Double = 3.5
    private let hiddenFirstCorrectionMinimumSeconds: Double = 2.2
    private let correctionPollInterval: Duration = .milliseconds(600)
    private let liveIntermediateContextWindowSeconds: Double = 18.0
    private let hiddenIntermediateContextWindowSeconds: Double = 24.0
    private let liveQuickPassContextWindowSeconds: Double = 30.0
    private let hiddenQuickPassContextWindowSeconds: Double = 18.0
    private let quickPassMinimumDurationSeconds: Double = 14.0

    private var sessionRevision = 0
    private var correctionLoopTask: Task<Void, Never>?
    private var finalizationTask: Task<Void, Never>?
    private var preloadTask: Task<Void, Never>?
    private var captureWatchdogTask: Task<Void, Never>?
    private var activeCorrectionPassID: UUID?
    private var activeCorrectionPassTask: Task<String?, Never>?
    private var activeCorrectionPassKind: MLXCorrectionPassKind?
    var sessionAllowsRealtimeTextDisplay = true
    private var didRetryCaptureStartup = false
    private var activeCaptureUsesPreferredInputDevice = false
    private var loggedSampleExtractionFailure = false
    private var activeSessionBehavior = MLXModelManager.transcriptionBehavior(
        for: MLXModelManager.defaultModelRepo
    )

    private var stableCommittedText = ""
    private var lastCandidateText = ""
    private var internalTranscribedText = ""
    private var nextCorrectionAtSeconds: Double = 6.0
    private(set) var lastCaptureMetrics: TranscriptionCaptureMetrics?

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

        cancelActiveTasks()
        removeCompletedAudioArchiveIfNeeded()
        resetTransientState()
        sessionRevision += 1
        let revision = sessionRevision
        activeSessionBehavior = modelManager.currentTranscriptionBehavior
        activeCaptureUsesPreferredInputDevice = preferredInputDeviceID != nil
        isModelInitializing = modelManager.state != .ready
        VoxtLog.info(
            "MLX transcription session started. repo=\(modelManager.currentModelRepo), correctionMode=\(activeSessionBehavior.correctionMode), realtimeDisplay=\(sessionAllowsRealtimeTextDisplay), modelState=\(String(describing: modelManager.state))",
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
        lastCaptureMetrics = TranscriptionCaptureMetrics(
            callbackCount: callbackCount,
            sampleCount: sampleCount,
            sampleRate: sampleRate
        )
        let capturedAudioSec = String(format: "%.2f", lastCaptureMetrics?.capturedAudioSeconds ?? 0)
        VoxtLog.info(
            "MLX recording stop captured. callbacks=\(callbackCount), samples=\(sampleCount), sampleRate=\(Int(sampleRate)), capturedAudioSec=\(capturedAudioSec)",
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
            _ = await self?.runManagedCorrectionPass(
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
                firstCorrectionMinimumSeconds: currentFirstCorrectionMinimumSeconds,
                contextWindowSeconds: currentIntermediateContextWindowSeconds
            ) else { continue }
            let intermediateSamples = sampleStore.tail(sampleCount: decision.contextSampleCount)

            _ = await runManagedCorrectionPass(
                stage: .intermediate,
                revision: revision,
                explicitSamples: intermediateSamples,
                sampleRate: inputSampleRate
            )

            nextCorrectionAtSeconds = decision.elapsedSeconds + currentCorrectionIntervalSeconds
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
            quickPassContextWindowSeconds: currentQuickPassContextWindowSeconds
        )
        let shouldRunQuickPass = sessionAllowsRealtimeTextDisplay && plan.shouldRunQuickPass
        VoxtLog.info(
            "MLX finalization started. repo=\(modelManager.currentModelRepo), audioSec=\(String(format: "%.2f", plan.durationSeconds)), quickPass=\(shouldRunQuickPass)",
            verbose: true
        )
        let quickSource: [Float]?
        if shouldRunQuickPass, let quickPassSampleCount = plan.quickPassSampleCount {
            quickSource = latestWindow(from: snapshot, maxCount: quickPassSampleCount)
        } else {
            quickSource = nil
        }

        let quickText: String?
        if let quickSource {
            quickText = await runManagedCorrectionPass(
                stage: .postStopQuick,
                revision: revision,
                explicitSamples: quickSource,
                sampleRate: sampleRate
            )
        } else {
            quickText = nil
        }

        let finalText = await runManagedCorrectionPass(
            stage: .postStopFinal,
            revision: revision,
            explicitSamples: snapshot,
            sampleRate: sampleRate
        )

        guard revision == sessionRevision else { return }
        stageCompletedAudioArchive(samples: snapshot, sampleRate: sampleRate)
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

    private func runManagedCorrectionPass(
        stage: MLXCorrectionPassKind,
        revision: Int,
        explicitSamples: [Float]?,
        sampleRate: Double
    ) async -> String? {
        switch MLXTranscriptionPlanning.correctionPassSchedulingDecision(
            requestedPass: stage,
            inFlightPass: activeCorrectionPassKind
        ) {
        case .startImmediately:
            break
        case .waitForInFlightPass:
            break
        case .skipRequestedPass:
            VoxtLog.info("MLX intermediate correction skipped because inference is still busy.", verbose: true)
            return nil
        case .interruptInFlightPass:
            if let activeCorrectionPassKind {
                VoxtLog.info(
                    "MLX correction pass preempted. inFlight=\(stageLabel(for: activeCorrectionPassKind)), requested=\(stageLabel(for: stage))",
                    verbose: true
                )
            }
            activeCorrectionPassTask?.cancel()
        }

        while let activeTask = activeCorrectionPassTask {
            let activePassID = activeCorrectionPassID
            _ = await activeTask.result
            if activeCorrectionPassID == activePassID {
                clearActiveCorrectionPassIfNeeded(passID: activePassID)
            }
        }

        let passID = UUID()
        let passTask = Task<String?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.executeCorrectionPass(
                stage: stage,
                revision: revision,
                explicitSamples: explicitSamples,
                sampleRate: sampleRate
            )
        }
        activeCorrectionPassID = passID
        activeCorrectionPassKind = stage
        activeCorrectionPassTask = passTask

        let result = await passTask.value
        clearActiveCorrectionPassIfNeeded(passID: passID)
        return result
    }

    private func clearActiveCorrectionPassIfNeeded(passID: UUID?) {
        guard activeCorrectionPassID == passID else { return }
        activeCorrectionPassID = nil
        activeCorrectionPassTask = nil
        activeCorrectionPassKind = nil
    }

    private func executeCorrectionPass(
        stage: MLXCorrectionPassKind,
        revision: Int,
        explicitSamples: [Float]?,
        sampleRate: Double
    ) async -> String? {
        guard revision == sessionRevision else { return nil }
        let rawSamples = explicitSamples ?? sampleStore.snapshot()
        guard !rawSamples.isEmpty else { return nil }
        let audioSeconds = Double(rawSamples.count) / safeSampleRate(sampleRate)
        let repo = modelManager.currentModelRepo
        let passStartedAt = Date()

        do {
            try Task.checkCancellation()
            modelManager.beginActiveUse()
            defer { modelManager.endActiveUse() }
            let model = try await modelManager.loadModel()
            try Task.checkCancellation()
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
            try Task.checkCancellation()
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
        } catch is CancellationError {
            let elapsedMs = Int(Date().timeIntervalSince(passStartedAt) * 1000)
            VoxtLog.info(
                "MLX correction pass cancelled. repo=\(repo), stage=\(stageLabel(for: stage)), audioSec=\(String(format: "%.2f", audioSeconds)), elapsedMs=\(elapsedMs)",
                verbose: true
            )
            return nil
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
        internalTranscribedText = ""
        audioLevel = 0
        isModelInitializing = false
        isFinalizingTranscription = false
        didRetryCaptureStartup = false
        activeCaptureUsesPreferredInputDevice = preferredInputDeviceID != nil
        stableCommittedText = ""
        lastCandidateText = ""
        nextCorrectionAtSeconds = currentCorrectionIntervalSeconds
        loggedSampleExtractionFailure = false
        lastCaptureMetrics = nil
    }

    private var currentCorrectionIntervalSeconds: Double {
        sessionAllowsRealtimeTextDisplay ? liveCorrectionIntervalSeconds : hiddenCorrectionIntervalSeconds
    }

    private var currentFirstCorrectionMinimumSeconds: Double {
        sessionAllowsRealtimeTextDisplay ? liveFirstCorrectionMinimumSeconds : hiddenFirstCorrectionMinimumSeconds
    }

    private var currentIntermediateContextWindowSeconds: Double {
        sessionAllowsRealtimeTextDisplay ? liveIntermediateContextWindowSeconds : hiddenIntermediateContextWindowSeconds
    }

    private var currentQuickPassContextWindowSeconds: Double {
        sessionAllowsRealtimeTextDisplay ? liveQuickPassContextWindowSeconds : hiddenQuickPassContextWindowSeconds
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
        activeCorrectionPassTask?.cancel()
        activeCorrectionPassTask = nil
        activeCorrectionPassID = nil
        activeCorrectionPassKind = nil
        isFinalizingTranscription = false
        preloadTask?.cancel()
        preloadTask = nil
        captureWatchdogTask?.cancel()
        captureWatchdogTask = nil
    }

    private func stageCompletedAudioArchive(samples: [Float], sampleRate: Double) {
        removeCompletedAudioArchiveIfNeeded()
        guard !samples.isEmpty else { return }
        let tempURL = HistoryAudioArchiveSupport.temporaryArchiveURL(prefix: "voxt-mlx-history")
        do {
            if try HistoryAudioArchiveSupport.exportWAV(samples: samples, sampleRate: sampleRate, to: tempURL) {
                completedAudioArchiveURL = tempURL
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            VoxtLog.warning("MLX completed audio archive export failed: \(error.localizedDescription)")
        }
    }

    private func removeCompletedAudioArchiveIfNeeded() {
        guard let completedAudioArchiveURL else { return }
        try? FileManager.default.removeItem(at: completedAudioArchiveURL)
        self.completedAudioArchiveURL = nil
    }

    private func safeSampleRate(_ value: Double) -> Double {
        max(value, 1)
    }

    private func latestWindow(from samples: [Float], maxCount: Int) -> [Float] {
        guard maxCount > 0, samples.count > maxCount else { return samples }
        return Array(samples.suffix(maxCount))
    }

    private func publishPartial(_ text: String) {
        guard sessionAllowsRealtimeTextDisplay else { return }
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

    private func applyCandidate(_ candidate: String, stage: MLXCorrectionPassKind) {
        if !sessionAllowsRealtimeTextDisplay {
            switch stage {
            case .postStopFinal:
                internalTranscribedText = candidate
                transcribedText = candidate
                stableCommittedText = candidate
                lastCandidateText = candidate
                return
            case .postStopQuick:
                let trustedHiddenBaseline = resolvedTrustedHiddenPreviewBaseline(
                    base: internalTranscribedText,
                    candidate: candidate
                )
                let merged = MLXTranscriptionPlanning.mergedHiddenPostStopPreview(
                    base: trustedHiddenBaseline,
                    candidate: candidate
                )
                internalTranscribedText = merged
                transcribedText = merged
                lastCandidateText = merged
                stableCommittedText = merged
                return
            case .intermediate:
                // Keep hidden intermediate candidates off the UI, but preserve the most
                // recent full-context hypothesis as a baseline for stop-time quick-pass
                // merging. This lets final-only mode use a true tail-window quick pass
                // without losing earlier transcript context.
                let merged = MLXTranscriptionPlanning.mergedHiddenPostStopPreview(
                    base: internalTranscribedText,
                    candidate: candidate
                )
                internalTranscribedText = merged
                lastCandidateText = merged
                return
            }
        }

        internalTranscribedText = candidate
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

    private func resolvedTrustedHiddenPreviewBaseline(base: String, candidate: String) -> String {
        let stableBase = normalizeText(base)
        let stableCandidate = normalizeText(candidate)
        guard !stableBase.isEmpty, !stableCandidate.isEmpty else { return stableBase }

        let maxTrustedBaseCount = stableCandidate.count + max(48, stableCandidate.count / 2)
        if stableBase.count > maxTrustedBaseCount,
           !stableBase.contains(stableCandidate) {
            return ""
        }

        return stableBase
    }

    private func resolvedInferenceConfiguration(for stage: MLXCorrectionPassKind) -> ResolvedInferenceConfiguration {
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
            maxTokens = sessionAllowsRealtimeTextDisplay ? 1024 : 512
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
                resolvedBiasTemplate(
                    tuningSettings.qwenContextBias,
                    userLanguageCodes: userLanguageCodes,
                    dictionaryTerms: resolvedDictionaryTermsTemplateValue()
                ),
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

    private func stageLabel(for stage: MLXCorrectionPassKind) -> String {
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

    private func resolvedBiasTemplate(
        _ template: String,
        userLanguageCodes: [String],
        dictionaryTerms: String
    ) -> String {
        ASRHintResolver.resolveTemplateVariables(
            in: template,
            userLanguageCodes: userLanguageCodes,
            dictionaryTerms: dictionaryTerms
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func resolvedDictionaryTermsTemplateValue() -> String {
        let entries = dictionaryEntryProvider?() ?? []
        var seen = Set<String>()
        let terms = entries.compactMap { entry -> String? in
            guard entry.groupID == nil else { return nil }
            guard entry.replacementTerms.isEmpty else { return nil }
            let trimmed = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let normalized = DictionaryStore.normalizeTerm(trimmed)
            guard seen.insert(normalized).inserted else { return nil }
            return trimmed
        }
        return terms.joined(separator: "\n")
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
        try Task.checkCancellation()
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
            try Task.checkCancellation()
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

    func transcribeBufferedChunk(samples: [Float], sampleRate: Double) async -> String? {
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
            VoxtLog.error("MLX structured transcription failed: \(error)")
            return nil
        }
    }

    func transcribeAudioFile(_ fileURL: URL) async throws -> String {
        let loaded = try DebugAudioClipIO.loadMonoSamples(from: fileURL)
        return await transcribeBufferedChunk(
            samples: loaded.samples,
            sampleRate: loaded.sampleRate
        ) ?? ""
    }

    func debugReplayAudioFileWithTrace(
        _ fileURL: URL,
        stepSeconds: Double = 4.0,
        allowsRealtimeTextDisplay: Bool
    ) async throws -> MLXRealtimeReplayDiagnostics {
        let loaded = try DebugAudioClipIO.loadMonoSamples(from: fileURL)
        let safeSampleRate = safeSampleRate(loaded.sampleRate)
        let stepSampleCount = max(Int(stepSeconds * safeSampleRate), 1)
        let revision = sessionRevision + 1

        resetTransientState()
        sessionRevision = revision
        activeSessionBehavior = modelManager.currentTranscriptionBehavior
        sessionAllowsRealtimeTextDisplay = allowsRealtimeTextDisplay

        var events: [MLXRealtimeReplayEvent] = []
        var trace: [String] = []
        var endSample = stepSampleCount

        while endSample <= loaded.samples.count {
            let prefix = Array(loaded.samples.prefix(endSample))
            if let decision = MLXTranscriptionPlanning.intermediateCorrectionDecision(
                sampleCount: prefix.count,
                sampleRate: loaded.sampleRate,
                nextCorrectionAtSeconds: nextCorrectionAtSeconds,
                behavior: activeSessionBehavior,
                firstCorrectionMinimumSeconds: currentFirstCorrectionMinimumSeconds,
                contextWindowSeconds: currentIntermediateContextWindowSeconds
            ) {
                let intermediateSamples = latestWindow(from: prefix, maxCount: decision.contextSampleCount)
                let publishedBefore = transcribedText
                let candidate = await runManagedCorrectionPass(
                    stage: .intermediate,
                    revision: revision,
                    explicitSamples: intermediateSamples,
                    sampleRate: loaded.sampleRate
                )
                nextCorrectionAtSeconds = decision.elapsedSeconds + currentCorrectionIntervalSeconds
                let publishedAfter = normalizeText(transcribedText)
                trace.append(
                    String(
                        format: "[%.1fs] intermediate candidate=%@ published=%@",
                        Double(endSample) / safeSampleRate,
                        Self.traceQuoted(normalizeText(candidate ?? "")),
                        Self.traceQuoted(publishedAfter)
                    )
                )
                if !publishedAfter.isEmpty, publishedAfter != normalizeText(publishedBefore) {
                    events.append(
                        MLXRealtimeReplayEvent(
                            elapsedSeconds: Double(endSample) / safeSampleRate,
                            text: publishedAfter,
                            isFinal: false,
                            source: "intermediate"
                        )
                    )
                }
            }
            endSample += stepSampleCount
        }

        let snapshot = loaded.samples
        let plan = MLXTranscriptionPlanning.finalizationPlan(
            sampleCount: snapshot.count,
            sampleRate: loaded.sampleRate,
            behavior: activeSessionBehavior,
            quickPassMinimumDurationSeconds: quickPassMinimumDurationSeconds,
            quickPassContextWindowSeconds: currentQuickPassContextWindowSeconds
        )
        let shouldRunQuickPass = allowsRealtimeTextDisplay && plan.shouldRunQuickPass
        if shouldRunQuickPass, let quickPassSampleCount = plan.quickPassSampleCount {
            let quickSource = latestWindow(from: snapshot, maxCount: quickPassSampleCount)
            let publishedBefore = transcribedText
            let candidate = await runManagedCorrectionPass(
                stage: .postStopQuick,
                revision: revision,
                explicitSamples: quickSource,
                sampleRate: loaded.sampleRate
            )
            let publishedAfter = normalizeText(transcribedText)
            trace.append(
                String(
                    format: "[%.1fs] post-stop-quick candidate=%@ published=%@",
                    plan.durationSeconds,
                    Self.traceQuoted(normalizeText(candidate ?? "")),
                    Self.traceQuoted(publishedAfter)
                )
            )
            if !publishedAfter.isEmpty, publishedAfter != normalizeText(publishedBefore) {
                events.append(
                    MLXRealtimeReplayEvent(
                        elapsedSeconds: plan.durationSeconds,
                        text: publishedAfter,
                        isFinal: false,
                        source: "post-stop-quick"
                    )
                )
            }
        }

        let finalText = await runManagedCorrectionPass(
            stage: .postStopFinal,
            revision: revision,
            explicitSamples: snapshot,
            sampleRate: loaded.sampleRate
        )
        let resolvedFinal = normalizeText(finalText ?? transcribedText)
        trace.append(
            String(
                format: "[%.1fs] final text=%@",
                plan.durationSeconds,
                Self.traceQuoted(resolvedFinal)
            )
        )
        if !resolvedFinal.isEmpty {
            events.append(
                MLXRealtimeReplayEvent(
                    elapsedSeconds: plan.durationSeconds,
                    text: resolvedFinal,
                    isFinal: true,
                    source: "final"
                )
            )
        }
        return MLXRealtimeReplayDiagnostics(events: events, trace: trace)
    }

    func debugReplayRealtimeAudioFileWithTrace(
        _ fileURL: URL,
        stepSeconds: Double = 4.0
    ) async throws -> MLXRealtimeReplayDiagnostics {
        try await debugReplayAudioFileWithTrace(
            fileURL,
            stepSeconds: stepSeconds,
            allowsRealtimeTextDisplay: true
        )
    }

    func debugReplayFinalOnlyAudioFileWithTrace(
        _ fileURL: URL,
        stepSeconds: Double = 4.0
    ) async throws -> MLXRealtimeReplayDiagnostics {
        try await debugReplayAudioFileWithTrace(
            fileURL,
            stepSeconds: stepSeconds,
            allowsRealtimeTextDisplay: false
        )
    }

    var currentWorkingTranscriptText: String {
        let internalText = internalTranscribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !internalText.isEmpty {
            return internalText
        }
        return transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func traceQuoted(_ value: String) -> String {
        value.isEmpty ? "\"\"" : "\"\(value)\""
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
