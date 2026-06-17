import Foundation
import AVFoundation
import Combine
@preconcurrency import MLX
import MLXAudioCore
import MLXAudioSTT
import MLXAudioVAD
import AudioToolbox

struct MLXIntermediateCorrectionDecision: Equatable {
    let elapsedSeconds: Double
    let contextSampleCount: Int
}

struct MLXCorrectionCadence: Equatable {
    let correctionIntervalSeconds: Double
    let firstCorrectionMinimumSeconds: Double
    let intermediateContextWindowSeconds: Double
    let quickPassContextWindowSeconds: Double
}

struct MLXSequentialTranscriptMergeResult: Equatable {
    let text: String
    let overlapCount: Int
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

private struct SenseVoiceInferenceResult {
    let output: STTOutput
    let metadata: SenseVoiceTranscriptMetadata?
}

private struct MLXCorrectionPassResult {
    let text: String?
    let error: Error?

    static func success(_ text: String?) -> MLXCorrectionPassResult {
        MLXCorrectionPassResult(text: text, error: nil)
    }

    static func failure(_ error: Error) -> MLXCorrectionPassResult {
        MLXCorrectionPassResult(text: nil, error: error)
    }
}

private enum MLXCaptureStartError: LocalizedError {
    case engineStartTimedOut(Double)

    var errorDescription: String? {
        switch self {
        case .engineStartTimedOut(let seconds):
            return "Audio engine failed to start within \(String(format: "%.0f", seconds))s."
        }
    }
}

/// Lets the non-`Sendable` `AVAudioEngine` be handed to a detached task so the blocking
/// `start()` call can run off the main actor. Start/stop are serialized by `MLXTranscriber`,
/// which never touches the engine concurrently, so this is safe.
private struct MLXAudioEngineBox: @unchecked Sendable {
    // `nonisolated(unsafe)` lets the detached start/stop run off the main actor under
    // `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Safe because MLXTranscriber never touches
    // the engine concurrently with the single in-flight start.
    nonisolated(unsafe) let engine: AVAudioEngine
}

private enum MLXStructuredTranscriptionError: LocalizedError {
    case senseVoiceLongFormVADUnavailable(String)
    case senseVoiceLongFormNoSpeechSegments(Double)

    var errorDescription: String? {
        switch self {
        case .senseVoiceLongFormVADUnavailable:
            return String(localized: "SenseVoice long audio processing is unavailable because the VAD model could not be prepared.")
        case .senseVoiceLongFormNoSpeechSegments:
            return String(localized: "SenseVoice could not detect any speech segments in this long audio clip.")
        }
    }

    var diagnosticDescription: String {
        switch self {
        case .senseVoiceLongFormVADUnavailable(let detail):
            return "SenseVoice long-form VAD unavailable. detail=\(detail)"
        case .senseVoiceLongFormNoSpeechSegments(let durationSeconds):
            return "SenseVoice long-form VAD produced no speech segments. durationSec=\(String(format: "%.2f", durationSeconds))"
        }
    }
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
    static func shouldUseSenseVoiceVAD(
        sampleCount: Int,
        sampleRate: Int,
        directPassMaximumDurationSeconds: Double
    ) -> Bool {
        let safeSampleRate = max(sampleRate, 1)
        let durationSeconds = Double(sampleCount) / Double(safeSampleRate)
        return durationSeconds > directPassMaximumDurationSeconds
    }

    static func splitSenseVoiceRange(
        start: Int,
        end: Int,
        maxChunkSamples: Int,
        overlapSamples: Int
    ) -> [Range<Int>] {
        guard maxChunkSamples > 0, end - start > maxChunkSamples else {
            return start < end ? [start..<end] : []
        }

        var ranges: [Range<Int>] = []
        var cursor = start
        while cursor < end {
            let upperBound = min(cursor + maxChunkSamples, end)
            ranges.append(cursor..<upperBound)
            guard upperBound < end else { break }
            cursor = max(start, upperBound - overlapSamples)
        }
        return ranges
    }

    static func correctionCadence(
        for repo: String,
        sessionAllowsRealtimeTextDisplay: Bool
    ) -> MLXCorrectionCadence {
        if MLXModelFamily.family(for: repo) == .senseVoice {
            if sessionAllowsRealtimeTextDisplay {
                return MLXCorrectionCadence(
                    correctionIntervalSeconds: 4.0,
                    firstCorrectionMinimumSeconds: 2.2,
                    intermediateContextWindowSeconds: 14.0,
                    quickPassContextWindowSeconds: 24.0
                )
            }
            return MLXCorrectionCadence(
                correctionIntervalSeconds: 2.6,
                firstCorrectionMinimumSeconds: 1.8,
                intermediateContextWindowSeconds: 18.0,
                quickPassContextWindowSeconds: 18.0
            )
        }

        if sessionAllowsRealtimeTextDisplay {
            return MLXCorrectionCadence(
                correctionIntervalSeconds: 6.0,
                firstCorrectionMinimumSeconds: 3.5,
                intermediateContextWindowSeconds: 18.0,
                quickPassContextWindowSeconds: 30.0
            )
        }
        return MLXCorrectionCadence(
            correctionIntervalSeconds: 3.2,
            firstCorrectionMinimumSeconds: 2.2,
            intermediateContextWindowSeconds: 24.0,
            quickPassContextWindowSeconds: 18.0
        )
    }

    static func mergeSequentialTranscript(base: String, next: String) -> String {
        sequentialTranscriptMergeResult(base: base, next: next).text
    }

    static func sequentialTranscriptMergeResult(base: String, next: String) -> MLXSequentialTranscriptMergeResult {
        let left = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let right = next.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !left.isEmpty else {
            return MLXSequentialTranscriptMergeResult(text: right, overlapCount: 0)
        }
        guard !right.isEmpty else {
            return MLXSequentialTranscriptMergeResult(text: left, overlapCount: 0)
        }
        if left.hasSuffix(right) {
            return MLXSequentialTranscriptMergeResult(text: left, overlapCount: right.count)
        }
        if right.hasPrefix(left) {
            return MLXSequentialTranscriptMergeResult(text: right, overlapCount: left.count)
        }

        let leftLast = left.unicodeScalars.last
        let rightFirst = right.unicodeScalars.first
        let minimumOverlapCount: Int
        if let leftLast, let rightFirst,
           CharacterSet.alphanumerics.contains(leftLast),
           CharacterSet.alphanumerics.contains(rightFirst) {
            minimumOverlapCount = 3
        } else {
            minimumOverlapCount = 2
        }

        let overlapCount = suffixPrefixOverlapCount(left, right)
        if overlapCount >= minimumOverlapCount {
            let rightChars = Array(right)
            return MLXSequentialTranscriptMergeResult(
                text: left + String(rightChars.dropFirst(overlapCount)),
                overlapCount: overlapCount
            )
        }

        let shouldInsertSpace: Bool
        if let leftLast, let rightFirst {
            shouldInsertSpace =
                CharacterSet.alphanumerics.contains(leftLast) &&
                CharacterSet.alphanumerics.contains(rightFirst)
        } else {
            shouldInsertSpace = true
        }
        return MLXSequentialTranscriptMergeResult(
            text: shouldInsertSpace ? "\(left) \(right)" : left + right,
            overlapCount: 0
        )
    }

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

    static func shouldRunQuickStopPass(
        plan: MLXFinalizationPlan,
        sessionAllowsRealtimeTextDisplay: Bool,
        liveMode: MLXLiveMode
    ) -> Bool {
        guard sessionAllowsRealtimeTextDisplay else { return false }
        guard liveMode != .nativeQwenLive else { return false }
        return plan.shouldRunQuickPass
    }

    static func resolvedNativeLiveVisiblePreview(
        previousPreview: String,
        previousConfirmedText: String,
        confirmedText: String,
        provisionalText: String
    ) -> String? {
        let normalizedConfirmed = confirmedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasProvisionalContent = !provisionalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let combined = (confirmedText + provisionalText).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !combined.isEmpty else { return nil }
        guard combined != previousPreview else { return nil }

        if normalizedConfirmed == previousConfirmedText,
           !hasProvisionalContent,
           !previousPreview.isEmpty,
           previousPreview.hasPrefix(normalizedConfirmed),
           previousPreview.count > combined.count {
            return nil
        }

        return combined
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

    static func removingKnownASRContextLeakage(from text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .filter { !isKnownASRContextLeakageLine($0) }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isKnownASRContextLeakageLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lowercased = trimmed.lowercased()
        return (
            trimmed.contains("说话者的主要语言") && trimmed.contains("其他常用语言")
        ) || (
            trimmed.contains("请将识别偏向于") && trimmed.contains("不要翻译")
        ) || (
            trimmed.contains("当音频中确实出现这些词") && trimmed.contains("词典词汇")
        ) || (
            lowercased.contains("the speaker's primary language is")
                && lowercased.contains("other commonly used languages")
        ) || (
            lowercased.contains("bias recognition toward correct spelling")
                && lowercased.contains("do not translate")
        ) || (
            lowercased.contains("prefer these dictionary terms")
                && lowercased.contains("match the audio")
        ) || (
            trimmed.contains("話者の主要言語") && trimmed.contains("その他のよく使う言語")
        ) || (
            trimmed.contains("認識を寄せてください") && trimmed.contains("翻訳はしないでください")
        ) || (
            trimmed.contains("音声内で実際に一致する場合") && trimmed.contains("辞書語")
        )
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

        func samples(from startIndex: Int) -> (samples: [Float], nextIndex: Int) {
            lock.lock()
            defer { lock.unlock() }

            let clampedStart = max(0, min(startIndex, samples.count))
            guard clampedStart < samples.count else { return ([], samples.count) }
            return (Array(samples[clampedStart...]), samples.count)
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

    /// Upper bound for the off-main `AVAudioEngine.start()`. A wedged coreaudiod can block
    /// `kAUStartIO` for ~10s; failing fast surfaces an overlay error instead of stalling.
    private static let captureStartTimeoutSeconds: Double = 6

    private let correctionPollInterval: Duration = .milliseconds(600)
    private let quickPassMinimumDurationSeconds: Double = 14.0
    private let qwenLiveFeedPollInterval: Duration = .milliseconds(100)
    private let qwenLiveEndedTimeoutSeconds: Double = 0.35
    private let senseVoiceVADRepo = "mlx-community/silero-vad"
    private let senseVoiceDirectPassMaximumDurationSeconds: Double = 30.0
    private let senseVoiceChunkMaximumDurationSeconds: Double = 24.0
    private let senseVoiceChunkOverlapSeconds: Double = 0.35
    private let senseVoiceVADThreshold: Float = 0.5
    private let senseVoiceVADMinSpeechDurationMs = 220
    private let senseVoiceVADMinSilenceDurationMs = 420
    private let senseVoiceVADSpeechPadMs = 180

    private var sessionRevision = 0
    private var correctionLoopTask: Task<Void, Never>?
    private var finalizationTask: Task<Void, Never>?
    private var preloadTask: Task<Void, Never>?
    private var captureWatchdogTask: Task<Void, Never>?
    private var liveSessionSetupTask: Task<Void, Never>?
    private var activeCorrectionPassID: UUID?
    private var activeCorrectionPassTask: Task<MLXCorrectionPassResult, Never>?
    private var activeCorrectionPassKind: MLXCorrectionPassKind?
    private var activeLiveMode = MLXModelManager.liveMode(for: MLXModelManager.defaultModelRepo)
    private var qwenStreamingSession: StreamingInferenceSession?
    private var qwenStreamingEventTask: Task<Void, Never>?
    private var qwenStreamingFeedTask: Task<Void, Never>?
    private var qwenLiveModelPinned = false
    private var qwenFeedCursor = 0
    private var latestNativeLiveConfirmedText = ""
    private var latestNativeLivePreviewText = ""
    private var latestNativeLiveEndedText = ""
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
    @Published private(set) var latestSenseVoiceMetadata: SenseVoiceTranscriptMetadata?
    private var senseVoiceVADModel: SileroVAD?
    private var pendingRuntimeFailureMessage: String?

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

    func consumePendingRuntimeFailureMessage() -> String? {
        let message = pendingRuntimeFailureMessage
        pendingRuntimeFailureMessage = nil
        return message
    }

    func startRecording() {
        Task { [weak self] in
            _ = await self?.startRecordingSession()
        }
    }

    /// Starts capture and returns a user-facing failure message, or `nil` on success.
    ///
    /// The blocking `AVAudioEngine.start()` runs off the main actor with a timeout
    /// (`startAudioCaptureGraphWithTimeout()`), so a wedged CoreAudio device can no longer
    /// freeze the hotkey/UI thread — it surfaces an overlay error instead.
    @discardableResult
    func startRecordingSession() async -> String? {
        guard !isRecording else { return nil }

        cancelActiveTasks()
        removeCompletedAudioArchiveIfNeeded()
        resetTransientState()
        sessionRevision += 1
        let revision = sessionRevision
        activeSessionBehavior = modelManager.currentTranscriptionBehavior
        activeLiveMode = resolvedSessionLiveMode()
        activeCaptureUsesPreferredInputDevice = preferredInputDeviceID != nil
        isModelInitializing = modelManager.state != .ready
        VoxtLog.info(
            "MLX transcription session started. repo=\(modelManager.currentModelRepo), correctionMode=\(activeSessionBehavior.correctionMode), realtimeDisplay=\(sessionAllowsRealtimeTextDisplay), liveMode=\(String(describing: activeLiveMode)), modelState=\(String(describing: modelManager.state))",
            verbose: true
        )

        do {
            try await startAudioCaptureGraphWithTimeout()
            isRecording = true
            scheduleCaptureStartupWatchdog(revision: revision)
            startModelPreloadIfNeeded(revision: revision)

            if activeLiveMode == .nativeQwenLive {
                startNativeQwenLiveSession(revision: revision)
            } else if activeSessionBehavior.runsIntermediateCorrections {
                correctionLoopTask = Task { [weak self] in
                    await self?.runIntermediateCorrectionLoop(revision: revision)
                }
            } else {
                VoxtLog.info(
                    "MLX transcription intermediate corrections disabled for repo=\(modelManager.currentModelRepo); finalization-only mode enabled.",
                    verbose: true
                )
            }
            return nil
        } catch {
            VoxtLog.error("MLXTranscriber start recording failed: \(error)")
            stopAudioEngine()
            audioEngine.inputNode.removeTap(onBus: 0)
            return String(localized: "Failed to start the microphone. Please try again.")
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        stopAudioEngine()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false

        correctionLoopTask?.cancel()
        correctionLoopTask = nil
        liveSessionSetupTask?.cancel()
        liveSessionSetupTask = nil
        qwenStreamingFeedTask?.cancel()
        qwenStreamingFeedTask = nil
        drainPendingSamplesIntoQwenLiveSession()
        qwenStreamingSession?.stop()

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
            releaseNativeLiveSession(cancelSession: false)
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
        guard isRecording,
              activeSessionBehavior.runsIntermediateCorrections,
              activeLiveMode != .nativeQwenLive
        else { return }
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
        pendingRuntimeFailureMessage = nil

        let snapshot = sampleStore.snapshot()
        guard !snapshot.isEmpty else {
            releaseNativeLiveSession(cancelSession: false)
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
        if activeLiveMode == .nativeQwenLive {
            await waitForNativeLiveEndedPreviewIfNeeded(revision: revision)
        }
        let shouldRunQuickPass = MLXTranscriptionPlanning.shouldRunQuickStopPass(
            plan: plan,
            sessionAllowsRealtimeTextDisplay: sessionAllowsRealtimeTextDisplay,
            liveMode: activeLiveMode
        )
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

        let quickResult: MLXCorrectionPassResult
        if let quickSource {
            quickResult = await runManagedCorrectionPass(
                stage: .postStopQuick,
                revision: revision,
                explicitSamples: quickSource,
                sampleRate: sampleRate
            )
        } else {
            quickResult = .success(nil)
        }

        let finalResult = await runManagedCorrectionPass(
            stage: .postStopFinal,
            revision: revision,
            explicitSamples: snapshot,
            sampleRate: sampleRate
        )

        guard revision == sessionRevision else { return }
        stageCompletedAudioArchive(samples: snapshot, sampleRate: sampleRate)
        let fallbackText: String
        if !latestNativeLiveEndedText.isEmpty {
            fallbackText = latestNativeLiveEndedText
        } else if !latestNativeLivePreviewText.isEmpty {
            fallbackText = latestNativeLivePreviewText
        } else {
            fallbackText = transcribedText
        }
        let resolved = normalizeText(finalResult.text ?? quickResult.text ?? fallbackText)
        if resolved.isEmpty, let error = finalResult.error ?? quickResult.error {
            let failureMessage = runtimeFailureMessage(for: error)
            pendingRuntimeFailureMessage = failureMessage
            VoxtLog.error(
                "MLX finalization produced no transcript because inference failed. repo=\(modelManager.currentModelRepo), error=\(failureMessage)"
            )
        }
        transcribedText = resolved
        publishPartial(resolved)
        onTranscriptionFinished?(resolved)
        VoxtLog.info(
            "MLX finalization completed. repo=\(modelManager.currentModelRepo), audioSec=\(String(format: "%.2f", plan.durationSeconds)), textChars=\(resolved.count)",
            verbose: true
        )
        sampleStore.clear()
        releaseNativeLiveSession(cancelSession: false)
    }

    private func runManagedCorrectionPass(
        stage: MLXCorrectionPassKind,
        revision: Int,
        explicitSamples: [Float]?,
        sampleRate: Double
    ) async -> MLXCorrectionPassResult {
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
            return .success(nil)
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
        if stage == .intermediate {
            guard isRecording, revision == sessionRevision else { return .success(nil) }
        }

        let passID = UUID()
        let passTask = Task<MLXCorrectionPassResult, Never> { [weak self] in
            guard let self else { return .success(nil) }
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
    ) async -> MLXCorrectionPassResult {
        guard revision == sessionRevision else { return .success(nil) }
        let rawSamples = explicitSamples ?? sampleStore.snapshot()
        guard !rawSamples.isEmpty else { return .success(nil) }
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
            let (streamedText, finalOutput, senseVoiceMetadata) = try await runStreamingInference(
                model: model,
                audioSamples: audioSamples,
                inferenceConfiguration: inferenceConfiguration
            )
            try Task.checkCancellation()
            let inferenceElapsedMs = Int(Date().timeIntervalSince(inferenceStartedAt) * 1000)

            let rawCandidate = normalizeText(finalOutput?.text ?? streamedText)
            let candidate = normalizeText(MLXTranscriptionPlanning.removingKnownASRContextLeakage(from: rawCandidate))
            if candidate != rawCandidate {
                VoxtLog.warning(
                    "MLX ASR context leakage removed. repo=\(repo), stage=\(stageLabel(for: stage)), rawChars=\(rawCandidate.count), outputChars=\(candidate.count)"
                )
            }
            guard !candidate.isEmpty else { return .success(nil) }
            latestSenseVoiceMetadata = senseVoiceMetadata
            applyCandidate(candidate, stage: stage)
            let elapsedMs = Int(Date().timeIntervalSince(passStartedAt) * 1000)
            VoxtLog.info(
                "MLX correction pass completed. repo=\(repo), stage=\(stageLabel(for: stage)), audioSec=\(String(format: "%.2f", audioSeconds)), elapsedMs=\(elapsedMs), inferenceMs=\(inferenceElapsedMs), textChars=\(candidate.count)",
                verbose: true
            )
            return .success(candidate)
        } catch is CancellationError {
            let elapsedMs = Int(Date().timeIntervalSince(passStartedAt) * 1000)
            VoxtLog.info(
                "MLX correction pass cancelled. repo=\(repo), stage=\(stageLabel(for: stage)), audioSec=\(String(format: "%.2f", audioSeconds)), elapsedMs=\(elapsedMs)",
                verbose: true
            )
            return .success(nil)
        } catch {
            await MainActor.run {
                self.isModelInitializing = false
            }
            let elapsedMs = Int(Date().timeIntervalSince(passStartedAt) * 1000)
            VoxtLog.error(
                "MLXTranscriber \(stageLabel(for: stage)) pass failed. repo=\(repo), audioSec=\(String(format: "%.2f", audioSeconds)), elapsedMs=\(elapsedMs), error=\(error.localizedDescription)"
            )
            return .failure(error)
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
        latestSenseVoiceMetadata = nil
        pendingRuntimeFailureMessage = nil
        qwenFeedCursor = 0
        latestNativeLiveConfirmedText = ""
        latestNativeLivePreviewText = ""
        latestNativeLiveEndedText = ""
    }

    private var currentCorrectionIntervalSeconds: Double {
        currentCorrectionCadence.correctionIntervalSeconds
    }

    private var currentFirstCorrectionMinimumSeconds: Double {
        currentCorrectionCadence.firstCorrectionMinimumSeconds
    }

    private var currentIntermediateContextWindowSeconds: Double {
        currentCorrectionCadence.intermediateContextWindowSeconds
    }

    private var currentQuickPassContextWindowSeconds: Double {
        currentCorrectionCadence.quickPassContextWindowSeconds
    }

    private var currentCorrectionCadence: MLXCorrectionCadence {
        MLXTranscriptionPlanning.correctionCadence(
            for: modelManager.currentModelRepo,
            sessionAllowsRealtimeTextDisplay: sessionAllowsRealtimeTextDisplay
        )
    }

    private func stopAudioEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }

    /// Configures the engine, input device, tap and `prepare()` — everything except the
    /// blocking `start()`. Returns the data needed to log once the engine is running.
    private func configureAudioCaptureGraph(usePreferredInputDevice: Bool? = nil) -> (format: AVAudioFormat, usedPreferredDevice: Bool) {
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
        return (recordingFormat, shouldUsePreferredInputDevice)
    }

    private func logCaptureStarted(format: AVAudioFormat, usedPreferredDevice: Bool) {
        VoxtLog.info(
            "MLX audio capture started. sampleRate=\(Int(format.sampleRate)), channels=\(format.channelCount), format=\(format.commonFormat.rawValue), interleaved=\(format.isInterleaved), routing=\(usedPreferredDevice ? "preferred" : "system-default"), deviceID=\(usedPreferredDevice ? (preferredInputDeviceID.map(String.init(describing:)) ?? "default") : "system-default")",
            verbose: true
        )
    }

    /// Synchronous start. Used only by mid-session recovery/device-switch paths, which are
    /// already off the hotkey thread. The hotkey start path uses the async timeout variant.
    private func startAudioCaptureGraph(usePreferredInputDevice: Bool? = nil) throws {
        let context = configureAudioCaptureGraph(usePreferredInputDevice: usePreferredInputDevice)
        try audioEngine.start()
        logCaptureStarted(format: context.format, usedPreferredDevice: context.usedPreferredDevice)
    }

    /// Same as `startAudioCaptureGraph`, but runs the blocking `AVAudioEngine.start()` off the
    /// main actor and gives up after `captureStartTimeoutSeconds`, so a wedged coreaudiod can
    /// never freeze the hotkey/UI thread.
    private func startAudioCaptureGraphWithTimeout(usePreferredInputDevice: Bool? = nil) async throws {
        let context = configureAudioCaptureGraph(usePreferredInputDevice: usePreferredInputDevice)
        try await startConfiguredEngineWithTimeout(timeoutSeconds: Self.captureStartTimeoutSeconds)
        logCaptureStarted(format: context.format, usedPreferredDevice: context.usedPreferredDevice)
    }

    /// Runs the already-configured engine's blocking `start()` on a detached task, racing it
    /// against a timeout. On timeout the engine is stopped so the start call unwinds promptly.
    private func startConfiguredEngineWithTimeout(timeoutSeconds: Double) async throws {
        let engineBox = MLXAudioEngineBox(engine: audioEngine)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                // Detached so the blocking start can never run on the main actor.
                try await Task.detached(priority: .userInitiated) {
                    try engineBox.engine.start()
                }.value
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeoutSeconds))
                engineBox.engine.stop()
                throw MLXCaptureStartError.engineStartTimedOut(timeoutSeconds)
            }
            defer { group.cancelAll() }
            _ = try await group.next()
        }
    }

    private func cancelActiveTasks() {
        correctionLoopTask?.cancel()
        correctionLoopTask = nil
        finalizationTask?.cancel()
        finalizationTask = nil
        liveSessionSetupTask?.cancel()
        liveSessionSetupTask = nil
        activeCorrectionPassTask?.cancel()
        activeCorrectionPassTask = nil
        activeCorrectionPassID = nil
        activeCorrectionPassKind = nil
        isFinalizingTranscription = false
        preloadTask?.cancel()
        preloadTask = nil
        captureWatchdogTask?.cancel()
        captureWatchdogTask = nil
        releaseNativeLiveSession(cancelSession: true)
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

    private func resolvedSessionLiveMode() -> MLXLiveMode {
        guard sessionAllowsRealtimeTextDisplay else { return .batchPreview }
        return MLXModelManager.liveMode(for: modelManager.currentModelRepo)
    }

    private func startNativeQwenLiveSession(revision: Int) {
        liveSessionSetupTask?.cancel()
        liveSessionSetupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let startedAt = Date()
            var shouldReleaseModel = false
            defer {
                if shouldReleaseModel {
                    self.modelManager.endActiveUse()
                }
            }

            do {
                self.modelManager.beginActiveUse()
                shouldReleaseModel = true
                let loadedModel = try await self.modelManager.loadModel()
                guard !Task.isCancelled,
                      revision == self.sessionRevision,
                      self.isRecording,
                      self.activeLiveMode == .nativeQwenLive
                else { return }
                guard let qwenModel = loadedModel as? Qwen3ASRModel else {
                    VoxtLog.warning(
                        "MLX native live requested for non-Qwen model. repo=\(self.modelManager.currentModelRepo)"
                    )
                    return
                }

                self.installNativeQwenLiveSession(qwenModel, revision: revision)
                self.isModelInitializing = false
                shouldReleaseModel = false
                let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                VoxtLog.info(
                    "MLX native Qwen live session ready. repo=\(self.modelManager.currentModelRepo), elapsedMs=\(elapsedMs)",
                    verbose: true
                )
            } catch {
                guard !Task.isCancelled else { return }
                let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                self.isModelInitializing = false
                VoxtLog.warning(
                    "MLX native Qwen live session setup failed. repo=\(self.modelManager.currentModelRepo), elapsedMs=\(elapsedMs), error=\(error.localizedDescription)"
                )
            }
        }
    }

    private func installNativeQwenLiveSession(_ model: Qwen3ASRModel, revision: Int) {
        releaseNativeLiveSession(cancelSession: true)
        let session = StreamingInferenceSession(
            model: model,
            config: StreamingConfig(
                language: resolvedNativeQwenLiveLanguage(),
                temperature: 0.0,
                maxTokensPerPass: 1024
            )
        )
        qwenStreamingSession = session
        qwenLiveModelPinned = true
        qwenFeedCursor = 0
        latestNativeLiveConfirmedText = ""
        latestNativeLivePreviewText = ""
        latestNativeLiveEndedText = ""
        let feedPollInterval = qwenLiveFeedPollInterval

        qwenStreamingEventTask = Task { [weak self, session] in
            for await event in session.events {
                self?.handleNativeQwenLiveEvent(event, revision: revision)
            }
        }

        qwenStreamingFeedTask = Task { [weak self, session] in
            while true {
                let chunk = self?.drainPendingSamplesForQwenLiveFeed(revision: revision) ?? []
                if !chunk.isEmpty {
                    session.feedAudio(samples: chunk)
                }

                let shouldContinue = self?.shouldContinueQwenLiveFeed(revision: revision) ?? false
                if !shouldContinue {
                    return
                }

                do {
                    try await Task.sleep(for: feedPollInterval)
                } catch {
                    return
                }
            }
        }
    }

    private func releaseNativeLiveSession(cancelSession: Bool) {
        qwenStreamingFeedTask?.cancel()
        qwenStreamingFeedTask = nil
        qwenStreamingEventTask?.cancel()
        qwenStreamingEventTask = nil
        if cancelSession {
            qwenStreamingSession?.cancel()
        }
        qwenStreamingSession = nil
        if qwenLiveModelPinned {
            qwenLiveModelPinned = false
            modelManager.endActiveUse()
        }
    }

    private func resolvedNativeQwenLiveLanguage() -> String {
        let hintPayload = resolvedHintPayload()
        if let language = hintPayload.language?.trimmingCharacters(in: .whitespacesAndNewlines),
           !language.isEmpty {
            return language
        }

        let selectedCodes = UserMainLanguageOption.storedSelection(
            from: UserDefaults.standard.string(forKey: AppPreferenceKey.userMainLanguageCodes)
        )
        let mainLanguage = ASRHintResolver.selectedLanguageOptions(selectedCodes).first
            ?? UserMainLanguageOption.fallbackOption()
        return mainLanguage.promptName
    }

    private func drainPendingSamplesForQwenLiveFeed(revision: Int) -> [Float] {
        guard revision == sessionRevision, isRecording, activeLiveMode == .nativeQwenLive else { return [] }
        let pending = sampleStore.samples(from: qwenFeedCursor)
        qwenFeedCursor = pending.nextIndex
        guard !pending.samples.isEmpty else { return [] }

        do {
            return try prepareInputSamples(pending.samples, sampleRate: inputSampleRate)
        } catch {
            VoxtLog.warning("MLX native Qwen live sample prepare failed: \(error.localizedDescription)")
            return []
        }
    }

    private func shouldContinueQwenLiveFeed(revision: Int) -> Bool {
        revision == sessionRevision && isRecording && activeLiveMode == .nativeQwenLive && qwenStreamingSession != nil
    }

    private func drainPendingSamplesIntoQwenLiveSession() {
        guard let session = qwenStreamingSession else { return }
        let pending = sampleStore.samples(from: qwenFeedCursor)
        qwenFeedCursor = pending.nextIndex
        guard !pending.samples.isEmpty else { return }

        do {
            let prepared = try prepareInputSamples(pending.samples, sampleRate: inputSampleRate)
            if !prepared.isEmpty {
                session.feedAudio(samples: prepared)
            }
        } catch {
            VoxtLog.warning("MLX native Qwen live stop-drain prepare failed: \(error.localizedDescription)")
        }
    }

    private func handleNativeQwenLiveEvent(_ event: TranscriptionEvent, revision: Int) {
        guard revision == sessionRevision else { return }

        switch event {
        case .displayUpdate(let confirmedText, let provisionalText):
            guard let combined = MLXTranscriptionPlanning.resolvedNativeLiveVisiblePreview(
                previousPreview: latestNativeLivePreviewText,
                previousConfirmedText: latestNativeLiveConfirmedText,
                confirmedText: confirmedText,
                provisionalText: provisionalText
            ) else { return }
            latestNativeLiveConfirmedText = normalizeText(confirmedText)
            internalTranscribedText = combined
            transcribedText = combined
            latestNativeLivePreviewText = combined
            publishPartial(combined)
        case .ended(let fullText):
            let normalized = normalizeText(fullText)
            latestNativeLiveConfirmedText = normalized
            latestNativeLiveEndedText = normalized
            if !normalized.isEmpty {
                internalTranscribedText = normalized
                transcribedText = normalized
                latestNativeLivePreviewText = normalized
                publishPartial(normalized)
            }
        case .confirmed, .provisional, .stats:
            break
        }
    }

    private func waitForNativeLiveEndedPreviewIfNeeded(revision: Int) async {
        guard activeLiveMode == .nativeQwenLive else { return }
        guard latestNativeLiveEndedText.isEmpty else { return }

        let startedAt = Date()
        while revision == sessionRevision,
              latestNativeLiveEndedText.isEmpty,
              Date().timeIntervalSince(startedAt) < qwenLiveEndedTimeoutSeconds
        {
            do {
                try await Task.sleep(for: .milliseconds(25))
            } catch {
                return
            }
        }
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
        DictionaryEntryCollection.asrPromptTermsText(from: dictionaryEntryProvider?() ?? [])
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
    ) async throws -> (streamedText: String, finalOutput: STTOutput?, senseVoiceMetadata: SenseVoiceTranscriptMetadata?) {
        try Task.checkCancellation()
        let audioArray = MLXArray(audioSamples)
        var streamedText = ""
        var finalOutput: STTOutput?
        var senseVoiceMetadata: SenseVoiceTranscriptMetadata?

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
            let result = try await runSenseVoiceInference(
                model: senseVoiceModel,
                audioSamples: audioSamples,
                languageHint: inferenceConfiguration.languageHint,
                useITN: inferenceConfiguration.senseVoiceUseITN,
                verbose: generationParameters.verbose
            )
            let output = result.output
            senseVoiceMetadata = result.metadata
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

        return (streamedText, finalOutput, senseVoiceMetadata)
    }

    private func runSenseVoiceInference(
        model: SenseVoiceModel,
        audioSamples: [Float],
        languageHint: String?,
        useITN: Bool,
        verbose: Bool
    ) async throws -> SenseVoiceInferenceResult {
        let durationSeconds = Double(audioSamples.count) / Double(targetSampleRate)
        let resolvedLanguage = normalizedSenseVoiceLanguageHint(languageHint)

        guard MLXTranscriptionPlanning.shouldUseSenseVoiceVAD(
            sampleCount: audioSamples.count,
            sampleRate: targetSampleRate,
            directPassMaximumDurationSeconds: senseVoiceDirectPassMaximumDurationSeconds
        ) else {
            let output = model.generate(
                audio: MLXArray(audioSamples),
                language: resolvedLanguage,
                useITN: useITN,
                verbose: verbose
            )
            return SenseVoiceInferenceResult(
                output: output,
                metadata: SenseVoiceTranscriptMetadata.fromOutput(
                    output,
                    startSeconds: 0,
                    endSeconds: durationSeconds,
                    usedVADSegmentation: false
                )
            )
        }

        let ranges: [Range<Int>]
        do {
            ranges = try await resolvedSenseVoiceSegmentRanges(for: audioSamples)
        } catch {
            let structuredError = MLXStructuredTranscriptionError.senseVoiceLongFormVADUnavailable(
                error.localizedDescription
            )
            VoxtLog.error(structuredError.diagnosticDescription)
            throw structuredError
        }

        guard !ranges.isEmpty else {
            let structuredError = MLXStructuredTranscriptionError.senseVoiceLongFormNoSpeechSegments(
                durationSeconds
            )
            VoxtLog.error(structuredError.diagnosticDescription)
            throw structuredError
        }

        var mergedText = ""
        var metadataSegments: [SenseVoiceSegmentMetadata] = []

        for range in ranges {
            try Task.checkCancellation()
            let chunkSamples = Array(audioSamples[range])
            guard !chunkSamples.isEmpty else { continue }
            let output = model.generate(
                audio: MLXArray(chunkSamples),
                language: resolvedLanguage,
                useITN: useITN,
                verbose: verbose
            )
            let chunkText = normalizeText(output.text)
            mergedText = MLXTranscriptionPlanning.mergeSequentialTranscript(base: mergedText, next: chunkText)
            if let metadata = SenseVoiceTranscriptMetadata.fromOutput(
                output,
                startSeconds: Double(range.lowerBound) / Double(targetSampleRate),
                endSeconds: Double(range.upperBound) / Double(targetSampleRate),
                usedVADSegmentation: true
            ) {
                metadataSegments = SenseVoiceTranscriptMetadata.mergeSequentialSegments(
                    base: metadataSegments,
                    next: metadata.segments
                )
            }
        }

        let metadata = SenseVoiceTranscriptMetadata.aggregated(
            segments: metadataSegments,
            usedVADSegmentation: true
        )
        let output = STTOutput(
            text: mergedText,
            segments: metadataSegments.map { segment in
                [
                    "text": segment.text,
                    "language": segment.language as Any,
                    "emotion": segment.emotion as Any,
                    "event": segment.event as Any,
                    "startSeconds": segment.startSeconds,
                    "endSeconds": segment.endSeconds,
                ]
            },
            language: metadata?.language
        )
        return SenseVoiceInferenceResult(output: output, metadata: metadata)
    }

    private func resolvedSenseVoiceSegmentRanges(for audioSamples: [Float]) async throws -> [Range<Int>] {
        let vad = try await loadSenseVoiceVADModel()
        let timestamps = try vad.getSpeechTimestamps(
            MLXArray(audioSamples),
            sampleRate: targetSampleRate,
            threshold: senseVoiceVADThreshold,
            minSpeechDurationMs: senseVoiceVADMinSpeechDurationMs,
            minSilenceDurationMs: senseVoiceVADMinSilenceDurationMs,
            speechPadMs: senseVoiceVADSpeechPadMs
        )
        let maxChunkSamples = Int(senseVoiceChunkMaximumDurationSeconds * Double(targetSampleRate))
        let overlapSamples = Int(senseVoiceChunkOverlapSeconds * Double(targetSampleRate))
        var ranges: [Range<Int>] = []

        for timestamp in timestamps {
            let start = max(0, min(timestamp.start, audioSamples.count))
            let end = max(start, min(timestamp.end, audioSamples.count))
            guard end > start else { continue }
            ranges.append(
                contentsOf: MLXTranscriptionPlanning.splitSenseVoiceRange(
                    start: start,
                    end: end,
                    maxChunkSamples: maxChunkSamples,
                    overlapSamples: overlapSamples
                )
            )
        }
        return ranges
    }

    private func loadSenseVoiceVADModel() async throws -> SileroVAD {
        if let senseVoiceVADModel {
            return senseVoiceVADModel
        }
        let modelDirectory = try await modelManager.ensureModelDirectory(repo: senseVoiceVADRepo)
        let model = try SileroVAD.fromModelDirectory(modelDirectory)
        senseVoiceVADModel = model
        return model
    }

    private func normalizedSenseVoiceLanguageHint(_ languageHint: String?) -> String {
        let normalized = languageHint?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "auto"
        switch normalized {
        case "zh", "en", "yue", "ja", "ko", "nospeech":
            return normalized
        default:
            return "auto"
        }
    }

    private func runtimeFailureMessage(for error: Error) -> String {
        if let structuredError = error as? MLXStructuredTranscriptionError,
           let description = structuredError.errorDescription {
            return description
        }
        return error.localizedDescription
    }

    func transcribeBufferedChunk(samples: [Float], sampleRate: Double) async throws -> String? {
        guard !samples.isEmpty else { return nil }

        latestSenseVoiceMetadata = nil
        modelManager.beginActiveUse()
        defer { modelManager.endActiveUse() }
        defer { isModelInitializing = false }
        let model = try await modelManager.loadModel()
        let audioSamples = try prepareInputSamples(samples, sampleRate: sampleRate)
        let inferenceConfiguration = resolvedInferenceConfiguration(for: .postStopFinal)
        let (streamedText, finalOutput, senseVoiceMetadata) = try await runStreamingInference(
            model: model,
            audioSamples: audioSamples,
            inferenceConfiguration: inferenceConfiguration
        )
        latestSenseVoiceMetadata = senseVoiceMetadata
        let rawCandidate = normalizeText(finalOutput?.text ?? streamedText)
        let candidate = normalizeText(MLXTranscriptionPlanning.removingKnownASRContextLeakage(from: rawCandidate))
        if candidate != rawCandidate {
            VoxtLog.warning(
                "MLX ASR context leakage removed. repo=\(modelManager.currentModelRepo), stage=structured, rawChars=\(rawCandidate.count), outputChars=\(candidate.count)"
            )
        }
        guard !candidate.isEmpty else {
            latestSenseVoiceMetadata = nil
            return nil
        }
        return candidate
    }

    func transcribeAudioFile(_ fileURL: URL) async throws -> String {
        let loaded = try DebugAudioClipIO.loadMonoSamples(from: fileURL)
        return try await transcribeBufferedChunk(
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
                        Self.traceQuoted(normalizeText(candidate.text ?? "")),
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
                        Self.traceQuoted(normalizeText(candidate.text ?? "")),
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
        let resolvedFinal = normalizeText(finalText.text ?? transcribedText)
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
