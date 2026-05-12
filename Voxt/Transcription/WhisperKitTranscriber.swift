import Foundation
import AVFoundation
import Combine
import AudioToolbox
import WhisperKit

public struct WhisperRealtimeEagerState {
    private static let stableHoldbackCharacterCount = 4
    private static let minimumNewUtteranceCharacterCount = 4

    public private(set) var stableCommittedText = ""
    public private(set) var currentCommittedText = ""
    public private(set) var liveCandidateText = ""
    public private(set) var lastRawCandidateText = ""
    public private(set) var publishedText = ""
    public private(set) var continuesFromCommittedPrefix = false

    public init() {}

    public mutating func reset() {
        stableCommittedText = ""
        currentCommittedText = ""
        liveCandidateText = ""
        lastRawCandidateText = ""
        publishedText = ""
        continuesFromCommittedPrefix = false
    }

    public mutating func apply(_ result: TranscriptionResult) -> String? {
        apply(hypothesisText: result.text)
    }

    mutating func apply(
        hypothesisText text: String
    ) -> String? {
        let normalized = Self.normalize(text)
        guard !normalized.isEmpty else { return nil }
        let candidate = resolvedCurrentUtteranceText(from: normalized)
        guard !candidate.isEmpty else {
            continuesFromCommittedPrefix = true
            return nil
        }

        if continuesFromCommittedPrefix,
           liveCandidateText.isEmpty,
           lastRawCandidateText.isEmpty,
           !stableCommittedText.isEmpty,
           candidate.count < Self.minimumNewUtteranceCharacterCount {
            return nil
        }

        let displayCandidate = resolvedDisplayCandidate(
            previousCandidate: lastRawCandidateText,
            currentCandidate: candidate
        )

        if !lastRawCandidateText.isEmpty {
            let agreedCount = Self.longestCommonPrefixCount(
                Array(lastRawCandidateText),
                Array(displayCandidate)
            )
            let commitCount = max(currentCommittedText.count, max(0, agreedCount - Self.stableHoldbackCharacterCount))
            if commitCount > currentCommittedText.count {
                currentCommittedText = String(displayCandidate.prefix(commitCount))
            }
        } else {
            currentCommittedText = ""
        }

        lastRawCandidateText = displayCandidate
        liveCandidateText = displayCandidate
        continuesFromCommittedPrefix = false
        return publish(stableCommittedText + displayCandidate)
    }

    public mutating func applyFinal(_ text: String) -> String? {
        let normalized = Self.normalize(text)
        reset()
        return publish(normalized, force: true)
    }

    public mutating func sealCurrentPublishedTextForNextUtterance() {
        let committed = publishedText
        stableCommittedText = committed
        currentCommittedText = ""
        liveCandidateText = ""
        lastRawCandidateText = ""
        continuesFromCommittedPrefix = true
    }

    var mutablePublishedCharacterCount: Int {
        max(0, liveCandidateText.count - currentCommittedText.count)
    }

    private mutating func publish(_ text: String, force: Bool = false) -> String? {
        let normalized = Self.normalize(text)
        guard force || normalized != publishedText else { return nil }
        publishedText = normalized
        return normalized
    }

    private func resolvedCurrentUtteranceText(from fullText: String) -> String {
        guard !stableCommittedText.isEmpty else { return fullText }
        if fullText.hasPrefix(stableCommittedText) {
            return String(fullText.dropFirst(stableCommittedText.count))
        }

        if stableCommittedText.contains(fullText) {
            return ""
        }

        let overlapCount = Self.longestSuffixPrefixOverlapCount(
            sourceCharacters: Array(stableCommittedText),
            candidateCharacters: Array(fullText)
        )
        if overlapCount >= 2 {
            return String(fullText.dropFirst(overlapCount))
        }

        return fullText
    }

    private func resolvedDisplayCandidate(
        previousCandidate: String,
        currentCandidate: String
    ) -> String {
        guard !previousCandidate.isEmpty else { return currentCandidate }
        if currentCandidate.hasPrefix(previousCandidate) {
            return currentCandidate
        }
        if previousCandidate.hasPrefix(currentCandidate) {
            return previousCandidate
        }

        let overlapCount = Self.longestSuffixPrefixOverlapCount(
            sourceCharacters: Array(previousCandidate),
            candidateCharacters: Array(currentCandidate)
        )
        guard overlapCount >= 2 else { return currentCandidate }
        return previousCandidate + String(currentCandidate.dropFirst(overlapCount))
    }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func longestCommonPrefixCount(_ lhs: [Character], _ rhs: [Character]) -> Int {
        let upperBound = min(lhs.count, rhs.count)
        var count = 0
        while count < upperBound, lhs[count] == rhs[count] {
            count += 1
        }
        return count
    }

    private static func longestSuffixPrefixOverlapCount(
        sourceCharacters: [Character],
        candidateCharacters: [Character]
    ) -> Int {
        let upperBound = min(sourceCharacters.count, candidateCharacters.count)
        guard upperBound > 0 else { return 0 }
        for overlap in stride(from: upperBound, through: 1, by: -1) {
            if Array(sourceCharacters.suffix(overlap)) == Array(candidateCharacters.prefix(overlap)) {
                return overlap
            }
        }
        return 0
    }

}

struct WhisperRealtimeReplayEvent: Equatable {
    let elapsedSeconds: Double
    let text: String
    let isFinal: Bool
    let source: String
    let rawText: String
}

struct WhisperOfflineTranscriptionDiagnostics: Equatable {
    let rawSegments: [String]
    let rawJoinedText: String
    let normalizedText: String
}

struct WhisperRealtimeReplayDiagnostics: Equatable {
    let events: [WhisperRealtimeReplayEvent]
    let trace: [String]
}

@MainActor
final class WhisperKitTranscriber: ObservableObject, TranscriberProtocol {
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
    }

    private enum WhisperInferenceProfile: String {
        case offline
        case realtimeDraft
        case realtimeEager
        case realtimeFinal

        var usesLiveDecodingBias: Bool {
            switch self {
            case .offline:
                return false
            case .realtimeDraft, .realtimeEager, .realtimeFinal:
                return true
            }
        }
    }

    enum WhisperInferencePassKind: Equatable {
        case offlineIntermediate
        case realtimeDraft
        case realtimeEager
        case realtimeSilenceReconcile
        case stopFinalRealtime
        case stopFinalOffline

        var isStopFinal: Bool {
            switch self {
            case .stopFinalRealtime, .stopFinalOffline:
                return true
            case .offlineIntermediate, .realtimeDraft, .realtimeEager, .realtimeSilenceReconcile:
                return false
            }
        }
    }

    enum WhisperInferenceSchedulingDecision: Equatable {
        case startImmediately
        case waitForInFlightPass
        case skipRequestedPass
        case interruptInFlightPass
    }

    private struct WhisperPreparedTranscription {
        let preparedSamples: [Float]
        let results: [TranscriptionResult]
        let text: String
    }

    static let offlinePartialPollInterval: Duration = .seconds(6)
    static let offlineFirstPartialMinimumSeconds: Double = 5.0
    static let realtimeEagerPollInterval: Duration = .milliseconds(250)
    static let realtimeEagerFirstPassMinimumSeconds: Double = 0.35
    static let realtimeEagerSteadyStateMinimumSeconds: Double = 0.65
    static let realtimeEagerMinimumNewAudioSeconds: Double = 0.18
    static let realtimeDraftBootstrapSeconds: Double = 2.8
    static let realtimeDraftBootstrapCharacterCount = 18
    static let realtimeDraftWindowSeconds: Double = 1.6
    static let realtimeDraftFallbackStallSeconds: Double = 0.55
    static let realtimeSilenceWindowSeconds: Double = 0.45
    static let realtimeSilenceRMSHoldThreshold: Float = 0.0035
    static let realtimeSilencePeakHoldThreshold: Float = 0.018
    static let realtimeSegmentOverlapSeconds: Double = 0.8
    nonisolated static let realtimeLongFormFinalProfileThresholdSeconds: Double = 30

    nonisolated static func inferenceSchedulingDecision(
        requestedPass: WhisperInferencePassKind,
        inFlightPass: WhisperInferencePassKind?
    ) -> WhisperInferenceSchedulingDecision {
        guard let inFlightPass else { return .startImmediately }
        if !requestedPass.isStopFinal {
            return .skipRequestedPass
        }
        if !inFlightPass.isStopFinal {
            return .interruptInFlightPass
        }
        return .waitForInFlightPass
    }

    @Published var isRecording = false
    @Published var isModelInitializing = false
    @Published var audioLevel: Float = 0.0
    @Published var transcribedText = ""
    @Published var isEnhancing = false
    @Published var isFinalizingTranscription = false
    var sessionAllowsRealtimeTextDisplay = true

    var onTranscriptionFinished: ((String) -> Void)?
    var onPartialTranscription: ((String) -> Void)?
    var dictionaryEntryProvider: (() -> [DictionaryEntry])?
    private(set) var lastStartFailureMessage: String?
    private(set) var latestWordTimings: [WhisperHistoryWordTiming] = []

    private let audioEngine = AVAudioEngine()
    private let sampleStore = AudioSampleStore()
    private let modelManager: WhisperKitModelManager
    private var preferredInputDeviceID: AudioDeviceID?
    private var inputSampleRate: Double = 16000
    private var completedAudioArchiveURL: URL?
    private var preparedWhisper: WhisperKit?
    private var preparedOutputMode: SessionOutputMode = .transcription
    private var preparedUseBuiltInTranslationTask = false
    private var sessionRevision = 0
    private var partialLoopTask: Task<Void, Never>?
    private var finalizationTask: Task<Void, Never>?
    private var captureWatchdogTask: Task<Void, Never>?
    private var realtimeEagerTask: Task<Void, Never>?
    private var realtimeLevelTask: Task<Void, Never>?
    private var activeUseHeld = false
    private var isInferenceRunning = false
    private var activeInferencePassID: UUID?
    private var activeInferencePassTask: Task<WhisperPreparedTranscription, Error>?
    private var activeInferencePassKind: WhisperInferencePassKind?
    private var didRetryCaptureStartup = false
    private var realtimeEagerLastSampleCount = 0
    private var realtimeEagerLastPublishedSampleCount = 0
    private var realtimeEagerState = WhisperRealtimeEagerState()
    private var realtimeTraceEntries: [String] = []
    private var realtimeCommittedSampleCount = 0
    private var realtimeWasRecentlySpeaking = false
    private var realtimeDidFlushCurrentSilence = false

    private let captureStartupWatchdogDelay: Duration = .seconds(1.2)
    private let targetSampleRate = Double(WhisperKit.sampleRate)

    init(modelManager: WhisperKitModelManager) {
        self.modelManager = modelManager
    }

    func setPreferredInputDevice(_ deviceID: AudioDeviceID?) {
        preferredInputDeviceID = deviceID
    }

    func requestPermissions() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func consumeCompletedAudioArchiveURL() -> URL? {
        let url = completedAudioArchiveURL
        completedAudioArchiveURL = nil
        return url
    }

    func discardCompletedAudioArchive() {
        removeCompletedAudioArchiveIfNeeded()
    }

    func prepareSession(
        outputMode: SessionOutputMode,
        useBuiltInTranslationTask: Bool = false
    ) async -> String? {
        cancelActiveTasks()
        cleanupPreparedWhisperIfNeeded()
        removeCompletedAudioArchiveIfNeeded()
        resetTransientState()
        preparedOutputMode = outputMode
        preparedUseBuiltInTranslationTask = useBuiltInTranslationTask
        lastStartFailureMessage = nil
        isModelInitializing = !modelManager.isCurrentModelLoaded

        do {
            modelManager.beginActiveUse()
            activeUseHeld = true
            preparedWhisper = try await modelManager.loadWhisper()
            return nil
        } catch {
            isModelInitializing = false
            cleanupPreparedWhisperIfNeeded()
            let message = String(localized: "Whisper failed to load the selected model.")
            lastStartFailureMessage = message
            VoxtLog.error("Whisper transcriber prepare failed: \(error)")
            return message
        }
    }

    func startRecording() {
        Task { [weak self] in
            _ = await self?.startRecordingSession()
        }
    }

    @discardableResult
    func startRecordingSession() async -> String? {
        guard !isRecording else { return nil }
        guard preparedWhisper != nil else {
            isModelInitializing = false
            let message = String(localized: "Whisper is not ready yet. Open Settings > Model and try again.")
            lastStartFailureMessage = message
            VoxtLog.warning("Whisper start blocked: model is not prepared.")
            return message
        }

        cancelActiveTasks()
        resetTransientState()
        sessionRevision += 1
        lastStartFailureMessage = nil
        didRetryCaptureStartup = false

        if effectiveWhisperRealtimeEnabled {
            return await startRealtimeRecordingSession(revision: sessionRevision)
        }

        do {
            try startAudioCaptureGraph()
            isRecording = true
            isModelInitializing = false
            let revision = sessionRevision
            scheduleCaptureStartupWatchdog(revision: revision)
            partialLoopTask = Task { [weak self] in
                await self?.runPartialLoop(revision: revision)
            }
            return nil
        } catch {
            isModelInitializing = false
            let message = String(localized: "Whisper failed to start recording.")
            lastStartFailureMessage = message
            VoxtLog.error("Whisper transcriber start failed: \(error)")
            stopAudioEngine()
            audioEngine.inputNode.removeTap(onBus: 0)
            cleanupPreparedWhisperIfNeeded()
            return message
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        let revision = sessionRevision
        let stopSampleCount = effectiveWhisperRealtimeEnabled ? snapshotPreparedAudioSamples().count : sampleStore.count()
        let stopBufferedSeconds = Double(stopSampleCount) / max(effectiveWhisperRealtimeEnabled ? targetSampleRate : inputSampleRate, 1)
        VoxtLog.info(
            """
            Whisper stop requested. revision=\(revision), realtime=\(effectiveWhisperRealtimeEnabled), sampleCount=\(stopSampleCount), bufferedSec=\(String(format: "%.2f", stopBufferedSeconds)), partialChars=\(transcribedText.count)
            """,
            verbose: true
        )
        isRecording = false
        isModelInitializing = false
        audioLevel = 0

        partialLoopTask?.cancel()
        partialLoopTask = nil
        captureWatchdogTask?.cancel()
        captureWatchdogTask = nil
        realtimeEagerTask?.cancel()
        realtimeEagerTask = nil

        isFinalizingTranscription = true
        finalizationTask?.cancel()
        if effectiveWhisperRealtimeEnabled {
            preparedWhisper?.audioProcessor.stopRecording()
            finalizationTask = Task { [weak self] in
                guard let self else { return }
                await self.runFinalTranscription(
                    revision: revision,
                    samples: self.snapshotPreparedAudioSamples(),
                    sampleRate: self.targetSampleRate
                )
            }
            return
        }

        stopAudioEngine()
        audioEngine.inputNode.removeTap(onBus: 0)

        let sampleRate = inputSampleRate
        let samples = sampleStore.snapshot()
        finalizationTask = Task { [weak self] in
            await self?.runFinalTranscription(revision: revision, samples: samples, sampleRate: sampleRate)
        }
    }

    func forceIntermediateTranscription() {
        guard isRecording, !effectiveWhisperRealtimeEnabled else { return }
        let revision = sessionRevision
        let samples = sampleStore.snapshot()
        guard !samples.isEmpty else { return }
        Task { [weak self] in
            await self?.runInference(
                revision: revision,
                samples: samples,
                sampleRate: self?.inputSampleRate ?? self?.targetSampleRate ?? Double(WhisperKit.sampleRate),
                includeWordTimings: false,
                publishFinalResult: false
            )
        }
    }

    func transcribeAudioFile(
        _ fileURL: URL,
        outputMode: SessionOutputMode = .transcription,
        useBuiltInTranslationTask: Bool = false
    ) async throws -> String {
        let diagnostics = try await debugTranscribeAudioFileWithDiagnostics(
            fileURL,
            outputMode: outputMode,
            useBuiltInTranslationTask: useBuiltInTranslationTask
        )
        return diagnostics.normalizedText
    }

    func debugTranscribeAudioFileWithDiagnostics(
        _ fileURL: URL,
        outputMode: SessionOutputMode = .transcription,
        useBuiltInTranslationTask: Bool = false,
        forcedLanguage: String? = nil
    ) async throws -> WhisperOfflineTranscriptionDiagnostics {
        let loaded = try DebugAudioClipIO.loadMonoSamples(from: fileURL)
        preparedOutputMode = outputMode
        preparedUseBuiltInTranslationTask = useBuiltInTranslationTask
        let whisper = try await modelManager.loadWhisper()
        let preparedSamples = prepareInputSamples(loaded.samples, sampleRate: loaded.sampleRate)
        let results = try await whisper.transcribe(
            audioArray: preparedSamples,
            decodeOptions: buildDecodingOptions(
                whisper: whisper,
                includeWordTimings: false,
                audioDurationSeconds: Double(preparedSamples.count) / targetSampleRate,
                forcedLanguage: forcedLanguage
            )
        )
        let rawSegments = results.map(\.text)
        let rawJoinedText = rawSegments.joined(separator: " ")
        return WhisperOfflineTranscriptionDiagnostics(
            rawSegments: rawSegments,
            rawJoinedText: rawJoinedText,
            normalizedText: normalizeText(rawJoinedText)
        )
    }

    func debugReplayRealtimeAudioFile(
        _ fileURL: URL,
        outputMode: SessionOutputMode = .transcription,
        useBuiltInTranslationTask: Bool = false,
        stepSeconds: Double = 0.25
    ) async throws -> [WhisperRealtimeReplayEvent] {
        try await debugReplayRealtimeAudioFileWithTrace(
            fileURL,
            outputMode: outputMode,
            useBuiltInTranslationTask: useBuiltInTranslationTask,
            stepSeconds: stepSeconds
        ).events
    }

    func debugReplayRealtimeAudioFileWithTrace(
        _ fileURL: URL,
        outputMode: SessionOutputMode = .transcription,
        useBuiltInTranslationTask: Bool = false,
        stepSeconds: Double = 0.25
    ) async throws -> WhisperRealtimeReplayDiagnostics {
        let loaded = try DebugAudioClipIO.loadMonoSamples(from: fileURL)
        preparedOutputMode = outputMode
        preparedUseBuiltInTranslationTask = useBuiltInTranslationTask
        let whisper = try await modelManager.loadWhisper()
        let preparedSamples = prepareInputSamples(loaded.samples, sampleRate: loaded.sampleRate)
        let stepSampleCount = max(Int(stepSeconds * targetSampleRate), 1)
        var eagerState = WhisperRealtimeEagerState()
        var events: [WhisperRealtimeReplayEvent] = []
        var trace: [String] = []
        var lastPublishedEndSample = 0
        var committedSampleCount = 0
        var wasRecentlySpeaking = false
        var didFlushCurrentSilence = false

        var endSample = stepSampleCount
        while endSample <= preparedSamples.count {
            let windowSamples = Array(preparedSamples.prefix(endSample))
            let overlapSampleCount = max(Int(Self.realtimeSegmentOverlapSeconds * targetSampleRate), 0)
            let activeSegmentStartSample = max(0, min(committedSampleCount, windowSamples.count) - overlapSampleCount)
            let activeSegmentSamples = Array(windowSamples.suffix(windowSamples.count - activeSegmentStartSample))
            let minimumSeconds = eagerState.mutablePublishedCharacterCount == 0
                ? Self.realtimeEagerFirstPassMinimumSeconds
                : Self.realtimeEagerSteadyStateMinimumSeconds
            if Double(activeSegmentSamples.count) / targetSampleRate >= minimumSeconds {
                let bufferedSeconds = Double(activeSegmentSamples.count) / targetSampleRate
                let publishedStallSeconds = Double(max(endSample - lastPublishedEndSample, 0)) / targetSampleRate
                let published: (text: String, source: String, rawText: String)?
                let usesBootstrapDraft = Self.shouldUseRealtimeDraftBootstrap(
                    bufferedSeconds: bufferedSeconds,
                    publishedCharacterCount: eagerState.mutablePublishedCharacterCount
                )
                let hasRecentSpeech = Self.hasRecentSpeechActivity(
                    samples: windowSamples,
                    targetSampleRate: targetSampleRate
                )
                if hasRecentSpeech {
                    wasRecentlySpeaking = true
                    didFlushCurrentSilence = false
                }
                let shouldFlushSilenceBoundary = !hasRecentSpeech &&
                    wasRecentlySpeaking &&
                    !didFlushCurrentSilence &&
                    !eagerState.publishedText.isEmpty &&
                    publishedStallSeconds >= Self.realtimeDraftFallbackStallSeconds
                if shouldFlushSilenceBoundary {
                    let result = try await whisper.transcribe(
                        audioArray: activeSegmentSamples,
                        decodeOptions: buildDecodingOptions(
                            whisper: whisper,
                            includeWordTimings: false,
                            profile: .realtimeFinal,
                            audioDurationSeconds: Double(activeSegmentSamples.count) / targetSampleRate
                        )
                    ).first
                    let silencePublished = result.flatMap { result in
                        eagerState.apply(hypothesisText: result.text).map {
                            (
                                text: $0,
                                source: "silence-flush",
                                rawText: result.text
                            )
                        }
                    }
                    trace.append(
                        String(
                            format: "[%.1fs] silence-flush raw=%@ published=%@",
                            Double(endSample) / targetSampleRate,
                            Self.traceQuoted(normalizeText(result?.text ?? "")),
                            Self.traceQuoted(normalizeText(silencePublished?.text ?? eagerState.publishedText))
                        )
                    )
                    if let silencePublished {
                        let normalized = normalizeText(silencePublished.text)
                        if !normalized.isEmpty, events.last?.text != normalized {
                            lastPublishedEndSample = endSample
                            events.append(
                                WhisperRealtimeReplayEvent(
                                    elapsedSeconds: Double(endSample) / targetSampleRate,
                                    text: normalized,
                                    isFinal: false,
                                    source: silencePublished.source,
                                    rawText: normalizeText(silencePublished.rawText)
                                )
                            )
                        }
                    }
                    eagerState.sealCurrentPublishedTextForNextUtterance()
                    committedSampleCount = endSample
                    lastPublishedEndSample = endSample
                    didFlushCurrentSilence = true
                    wasRecentlySpeaking = false
                    endSample = min(endSample + stepSampleCount, preparedSamples.count)
                    continue
                }
                let shouldHoldForSilence = !hasRecentSpeech &&
                    !eagerState.publishedText.isEmpty &&
                    publishedStallSeconds >= Self.realtimeDraftFallbackStallSeconds
                if shouldHoldForSilence {
                    trace.append(
                        String(
                            format: "[%.1fs] hold/silence published=%@",
                            Double(endSample) / targetSampleRate,
                            Self.traceQuoted(eagerState.publishedText)
                        )
                    )
                    endSample = min(endSample + stepSampleCount, preparedSamples.count)
                    continue
                }
                if usesBootstrapDraft {
                    let draftWindowSampleCount = max(Int(Self.realtimeDraftWindowSeconds * targetSampleRate), 1)
                    let draftWindow = Array(activeSegmentSamples.suffix(min(activeSegmentSamples.count, draftWindowSampleCount)))
                    let result = try await whisper.transcribe(
                        audioArray: draftWindow,
                        decodeOptions: buildDecodingOptions(
                            whisper: whisper,
                            includeWordTimings: false,
                            profile: .realtimeDraft,
                            audioDurationSeconds: Double(draftWindow.count) / targetSampleRate
                        )
                    ).first
                    published = result.flatMap { result in
                        eagerState.apply(hypothesisText: result.text).map {
                            (
                                text: $0,
                                source: usesBootstrapDraft ? "draft-bootstrap" : "draft-fallback",
                                rawText: result.text
                            )
                        }
                    }
                    trace.append(
                        String(
                            format: "[%.1fs] %@ raw=%@ published=%@",
                            Double(endSample) / targetSampleRate,
                            "draft-bootstrap",
                            Self.traceQuoted(normalizeText(result?.text ?? "")),
                            Self.traceQuoted(normalizeText(published?.text ?? eagerState.publishedText))
                        )
                    )
                } else {
                    let result = try await whisper.transcribe(
                        audioArray: activeSegmentSamples,
                        decodeOptions: buildDecodingOptions(
                            whisper: whisper,
                            includeWordTimings: false,
                            profile: .realtimeEager,
                            audioDurationSeconds: Double(activeSegmentSamples.count) / targetSampleRate
                        )
                    ).first
                    published = result.flatMap { result in
                        eagerState.apply(result).map {
                            (
                                text: $0,
                                source: "eager",
                                rawText: result.text
                            )
                        }
                    }
                    trace.append(
                        String(
                            format: "[%.1fs] eager raw=%@ published=%@",
                            Double(endSample) / targetSampleRate,
                            Self.traceQuoted(normalizeText(result?.text ?? "")),
                            Self.traceQuoted(normalizeText(published?.text ?? eagerState.publishedText))
                        )
                    )
                }

                if let published {
                    let normalized = normalizeText(published.text)
                    if !normalized.isEmpty, events.last?.text != normalized {
                        lastPublishedEndSample = endSample
                        events.append(
                            WhisperRealtimeReplayEvent(
                                elapsedSeconds: Double(endSample) / targetSampleRate,
                                text: normalized,
                                isFinal: false,
                                source: published.source,
                                rawText: normalizeText(published.rawText)
                            )
                        )
                    }
                }
            }

            if endSample == preparedSamples.count {
                break
            }
            endSample = min(endSample + stepSampleCount, preparedSamples.count)
        }

        let bufferedSeconds = Double(preparedSamples.count) / targetSampleRate
        let useOfflineFinalProfile = Self.shouldUseOfflineFinalProfileForStop(
            realtimeEnabled: true,
            bufferedSeconds: bufferedSeconds
        )
        let finalResults = try await whisper.transcribe(
            audioArray: preparedSamples,
            decodeOptions: buildDecodingOptions(
                whisper: whisper,
                includeWordTimings: false,
                profile: useOfflineFinalProfile ? .offline : .realtimeFinal,
                audioDurationSeconds: Double(preparedSamples.count) / targetSampleRate
            )
        )
        let finalText = normalizeText(finalResults.map(\.text).joined(separator: " "))
        if !finalText.isEmpty {
            events.append(
                WhisperRealtimeReplayEvent(
                    elapsedSeconds: Double(preparedSamples.count) / targetSampleRate,
                    text: finalText,
                    isFinal: true,
                    source: "final",
                    rawText: finalText
                )
            )
            trace.append(
                String(
                    format: "[%.1fs] final/%@ raw=%@",
                    Double(preparedSamples.count) / targetSampleRate,
                    useOfflineFinalProfile ? "offline" : "realtime",
                    Self.traceQuoted(finalText)
                )
            )
        }

        return WhisperRealtimeReplayDiagnostics(events: events, trace: trace)
    }

    func restartCaptureForPreferredInputDevice() throws {
        guard isRecording else { return }
        guard !effectiveWhisperRealtimeEnabled else {
            throw NSError(
                domain: "Voxt.WhisperKitTranscriber",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Whisper realtime capture cannot be hot-swapped safely."]
            )
        }
        try startAudioCaptureGraph()
        scheduleCaptureStartupWatchdog(revision: sessionRevision)
    }

    private func startRealtimeRecordingSession(revision: Int) async -> String? {
        guard let whisper = preparedWhisper else {
            return String(localized: "Whisper is not ready yet. Open Settings > Model and try again.")
        }

        do {
            inputSampleRate = targetSampleRate
            try whisper.audioProcessor.startRecordingLive(inputDeviceID: preferredInputDeviceID) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleRealtimeAudioBuffer(revision: revision)
                }
            }
            isRecording = true
            isModelInitializing = false
            startRealtimeLevelUpdates(revision: revision)
            startRealtimeEagerLoop(revision: revision)
            VoxtLog.info(
                "Whisper audio capture started. sampleRate=\(Int(targetSampleRate)), deviceID=\(preferredInputDeviceID.map(String.init(describing:)) ?? "default"), mode=realtime-eager",
                verbose: true
            )
            return nil
        } catch {
            let message = String(localized: "Whisper failed to start recording.")
            lastStartFailureMessage = message
            VoxtLog.error("Whisper realtime setup failed: \(error)")
            cleanupPreparedWhisperIfNeeded()
            return message
        }
    }

    private func runPartialLoop(revision: Int) async {
        while !Task.isCancelled, revision == sessionRevision, isRecording {
            do {
                try await Task.sleep(for: Self.offlinePartialPollInterval)
            } catch {
                return
            }

            guard revision == sessionRevision, isRecording else { return }
            let elapsed = Double(sampleStore.count()) / max(inputSampleRate, 1)
            guard elapsed >= Self.offlineFirstPartialMinimumSeconds else { continue }

            let samples = sampleStore.snapshot()
            guard !samples.isEmpty else { continue }

            await runInference(
                revision: revision,
                samples: samples,
                sampleRate: inputSampleRate,
                includeWordTimings: false,
                publishFinalResult: false
            )
        }
    }

    private func runFinalTranscription(revision: Int, samples: [Float], sampleRate: Double) async {
        let bufferedSeconds = Double(samples.count) / max(sampleRate, 1)
        let useOfflineFinalProfile = Self.shouldUseOfflineFinalProfileForStop(
            realtimeEnabled: effectiveWhisperRealtimeEnabled,
            bufferedSeconds: bufferedSeconds
        )
        let finalProfile: WhisperInferenceProfile = useOfflineFinalProfile ? .offline : .realtimeFinal
        if effectiveWhisperRealtimeEnabled, useOfflineFinalProfile {
            VoxtLog.info(
                "Whisper realtime finalization promoted to offline long-form profile. bufferedSec=\(String(format: "%.2f", bufferedSeconds))",
                verbose: true
            )
        }
        defer {
            if revision == sessionRevision {
                isFinalizingTranscription = false
            }
        }

        await runInference(
            revision: revision,
            samples: samples,
            sampleRate: sampleRate,
            includeWordTimings: whisperTimestampsEnabled,
            publishFinalResult: true,
            profile: finalProfile,
            passKind: useOfflineFinalProfile ? .stopFinalOffline : .stopFinalRealtime
        )
    }

    nonisolated static func shouldUseOfflineFinalProfileForStop(
        realtimeEnabled: Bool,
        bufferedSeconds: Double
    ) -> Bool {
        guard realtimeEnabled else { return true }
        return bufferedSeconds >= Self.realtimeLongFormFinalProfileThresholdSeconds
    }

    nonisolated static func reconcileRealtimeFinalText(
        finalText: String,
        latestPublishedText: String
    ) -> String {
        let normalizedFinal = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLive = latestPublishedText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedLive.isEmpty else { return normalizedFinal }
        guard !normalizedFinal.isEmpty else { return normalizedLive }
        guard normalizedLive != normalizedFinal else { return normalizedFinal }

        if normalizedLive.hasPrefix(normalizedFinal) {
            let finalCount = normalizedFinal.count
            let liveCount = normalizedLive.count
            let delta = liveCount - finalCount
            let minimumExtraCharacters = max(8, Int(Double(liveCount) * 0.12))
            if delta >= minimumExtraCharacters {
                return normalizedLive
            }
        }

        return normalizedFinal
    }

    private func runInference(
        revision: Int,
        samples: [Float],
        sampleRate: Double,
        includeWordTimings: Bool,
        publishFinalResult: Bool,
        profile: WhisperInferenceProfile = .offline,
        passKind: WhisperInferencePassKind? = nil
    ) async {
        guard !samples.isEmpty else {
            if publishFinalResult {
                VoxtLog.warning("Whisper finalization produced an empty audio snapshot; finishing with empty transcription.")
                cleanupPreparedWhisperIfNeeded()
                onTranscriptionFinished?("")
            }
            return
        }

        guard revision == sessionRevision else { return }
        guard let whisper = preparedWhisper else {
            if publishFinalResult {
                VoxtLog.warning("Whisper finalization aborted because preparedWhisper was already released.")
                cleanupPreparedWhisperIfNeeded()
                onTranscriptionFinished?("")
            }
            return
        }
        defer {
            if publishFinalResult {
                cleanupPreparedWhisperIfNeeded()
            }
        }

        do {
            let inferenceStartedAt = Date()
            let resolvedPassKind = passKind ?? inferredPassKind(
                profile: profile,
                publishFinalResult: publishFinalResult
            )
            let transcription = try await runManagedTranscriptionPass(
                passKind: resolvedPassKind,
                whisper: whisper,
                samples: samples,
                sampleRate: sampleRate,
                includeWordTimings: includeWordTimings,
                profile: profile,
                revision: revision
            )
            let preparedSamples = transcription.preparedSamples
            let results = transcription.results
            let text = transcription.text
            if publishFinalResult {
                let latestPublishedText = transcribedText
                let resolvedFinalText = Self.reconcileRealtimeFinalText(
                    finalText: text,
                    latestPublishedText: latestPublishedText
                )
                let elapsedMs = max(Int(Date().timeIntervalSince(inferenceStartedAt) * 1000), 0)
                stageCompletedAudioArchive(samples: preparedSamples, sampleRate: targetSampleRate)
                latestWordTimings = includeWordTimings ? buildWordTimings(from: results) : []
                VoxtLog.info(
                    """
                    Whisper final transcription ready. revision=\(revision), chars=\(resolvedFinalText.count), preparedSampleCount=\(preparedSamples.count), segmentCount=\(results.count), elapsedMs=\(elapsedMs)
                    """
                )
                if resolvedFinalText != text {
                    VoxtLog.info(
                        """
                        Whisper final transcription preserved longer live hypothesis tail. revision=\(revision), finalChars=\(text.count), liveChars=\(latestPublishedText.trimmingCharacters(in: .whitespacesAndNewlines).count), resolvedChars=\(resolvedFinalText.count)
                        """,
                        verbose: true
                    )
                }
                publishWhisperFinalText(resolvedFinalText)
                onTranscriptionFinished?(resolvedFinalText)
            } else {
                if sessionAllowsRealtimeTextDisplay {
                    transcribedText = text
                    onPartialTranscription?(text)
                }
            }
        } catch {
            VoxtLog.error("Whisper inference failed: \(error)")
            if publishFinalResult {
                let preparedSamples = prepareInputSamples(samples, sampleRate: sampleRate)
                stageCompletedAudioArchive(samples: preparedSamples, sampleRate: targetSampleRate)
                latestWordTimings = []
                VoxtLog.warning(
                    """
                    Whisper final inference failed; falling back to latest partial text. revision=\(revision), fallbackChars=\(transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).count), preparedSampleCount=\(preparedSamples.count)
                    """
                )
                onTranscriptionFinished?(transcribedText.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    private func buildDecodingOptions(
        whisper: WhisperKit,
        includeWordTimings: Bool,
        profile: WhisperInferenceProfile = .offline,
        audioDurationSeconds: Double? = nil,
        forcedLanguage: String? = nil
    ) -> DecodingOptions {
        let hintPayload = resolvedHintPayload()
        let tuningSettings = resolvedLocalTuningSettings()
        let resolvedTask = resolvedDecodingTask()
        let resolvedLanguage = forcedLanguage ?? resolvedWhisperLanguage(for: profile, hintPayload: hintPayload)
        let detectLanguage = resolvedLanguage == nil
        let temperature: Float
        let temperatureIncrementOnFallback: Float
        let temperatureFallbackCount: Int
        let noSpeechThreshold: Float
        let chunkingStrategy: ChunkingStrategy?

        switch profile {
        case .offline:
            temperature = whisperTemperature
            temperatureIncrementOnFallback = Float(tuningSettings.temperatureIncrementOnFallback)
            temperatureFallbackCount = tuningSettings.temperatureFallbackCount
            if let audioDurationSeconds, audioDurationSeconds <= 12 {
                noSpeechThreshold = Float(min(tuningSettings.noSpeechThreshold, 0.25))
            } else {
                noSpeechThreshold = Float(tuningSettings.noSpeechThreshold)
            }
            // Local Whisper long-form stability regresses with VAD chunking on multilingual
            // fixtures. Prefer a single-pass decode for offline/final work and leave chunked
            // behavior to the realtime draft/eager path.
            chunkingStrategy = nil
        case .realtimeDraft:
            temperature = 0
            temperatureIncrementOnFallback = 0
            temperatureFallbackCount = 1
            noSpeechThreshold = Float(min(tuningSettings.noSpeechThreshold, 0.2))
            chunkingStrategy = nil
        case .realtimeEager:
            temperature = 0
            temperatureIncrementOnFallback = Float(min(tuningSettings.temperatureIncrementOnFallback, 0.1))
            temperatureFallbackCount = min(max(tuningSettings.temperatureFallbackCount, 1), 2)
            noSpeechThreshold = Float(min(tuningSettings.noSpeechThreshold, 0.25))
            chunkingStrategy = nil
        case .realtimeFinal:
            temperature = 0
            temperatureIncrementOnFallback = Float(min(tuningSettings.temperatureIncrementOnFallback, 0.15))
            temperatureFallbackCount = max(tuningSettings.temperatureFallbackCount, 2)
            noSpeechThreshold = Float(min(tuningSettings.noSpeechThreshold, 0.3))
            chunkingStrategy = nil
        }

        let promptTokens: [Int]?
        if let prompt = hintPayload.prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty,
           let tokenizer = whisper.tokenizer {
            promptTokens = tokenizer.encode(text: " " + prompt)
                .filter { token in token < tokenizer.specialTokens.specialTokenBegin }
        } else {
            promptTokens = nil
        }

        if profile == .offline {
            VoxtLog.info(
                "Whisper decode options. profile=\(profile.rawValue), task=\(resolvedTask.description), language=\(resolvedLanguage ?? "auto"), detectLanguage=\(detectLanguage), promptChars=\(hintPayload.prompt?.count ?? 0), promptTokens=\(promptTokens?.count ?? 0), realtime=\(effectiveWhisperRealtimeEnabled)",
                verbose: true
            )
        }

        return DecodingOptions(
            verbose: false,
            task: resolvedTask,
            language: resolvedLanguage,
            temperature: temperature,
            temperatureIncrementOnFallback: temperatureIncrementOnFallback,
            temperatureFallbackCount: temperatureFallbackCount,
            usePrefillPrompt: true,
            detectLanguage: detectLanguage,
            skipSpecialTokens: true,
            withoutTimestamps: !includeWordTimings,
            wordTimestamps: includeWordTimings,
            promptTokens: promptTokens,
            compressionRatioThreshold: Float(tuningSettings.compressionRatioThreshold),
            logProbThreshold: Float(tuningSettings.logProbThreshold),
            noSpeechThreshold: noSpeechThreshold,
            chunkingStrategy: chunkingStrategy
        )
    }

    private func resolvedDecodingTask() -> DecodingTask {
        if preparedOutputMode == .translation, preparedUseBuiltInTranslationTask {
            return .translate
        }
        return .transcribe
    }

    private func resolvedHintPayload() -> ResolvedASRHintPayload {
        let defaults = UserDefaults.standard
        let settings = ASRHintSettingsStore.resolvedSettings(
            for: .whisperKit,
            rawValue: defaults.string(forKey: AppPreferenceKey.asrHintSettings)
        )
        let userLanguageCodes = UserMainLanguageOption.storedSelection(
            from: defaults.string(forKey: AppPreferenceKey.userMainLanguageCodes)
        )
        return ASRHintResolver.resolve(
            target: .whisperKit,
            settings: settings,
            userLanguageCodes: userLanguageCodes,
            dictionaryTerms: resolvedDictionaryTermsTemplateValue()
        )
    }

    private func resolvedDictionaryTermsTemplateValue() -> String {
        let entries = dictionaryEntryProvider?() ?? []
        guard !entries.isEmpty else { return "" }

        let sortedEntries = entries.sorted {
            if $0.matchCount != $1.matchCount {
                return $0.matchCount > $1.matchCount
            }
            switch ($0.lastMatchedAt, $1.lastMatchedAt) {
            case let (lhs?, rhs?) where lhs != rhs:
                return lhs > rhs
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                break
            }
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending
        }

        var seen = Set<String>()
        var terms: [String] = []
        var totalCharacters = 0

        for entry in sortedEntries {
            let trimmed = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard seen.insert(entry.normalizedTerm).inserted else { continue }

            let projectedCharacters = totalCharacters + trimmed.count + (terms.isEmpty ? 0 : 1)
            if !terms.isEmpty && projectedCharacters > 260 {
                break
            }

            terms.append(trimmed)
            totalCharacters = projectedCharacters

            if terms.count >= 20 || totalCharacters >= 260 {
                break
            }
        }

        return terms.joined(separator: "\n")
    }

    private func resolvedLocalTuningSettings() -> WhisperLocalTuningSettings {
        WhisperLocalTuningSettingsStore.resolvedSettings(
            from: UserDefaults.standard.string(forKey: AppPreferenceKey.whisperLocalASRTuningSettings)
        )
    }

    private func buildWordTimings(from results: [TranscriptionResult]) -> [WhisperHistoryWordTiming] {
        results
            .flatMap(\.allWords)
            .map {
                WhisperHistoryWordTiming(
                    word: $0.word,
                    startSeconds: Double($0.start),
                    endSeconds: Double($0.end),
                    probability: Double($0.probability)
                )
            }
    }

    private func prepareInputSamples(_ samples: [Float], sampleRate: Double) -> [Float] {
        guard abs(sampleRate - targetSampleRate) > 1 else {
            return samples
        }
        return Self.resample(samples: samples, from: sampleRate, to: targetSampleRate)
    }

    private func resetTransientState() {
        sampleStore.clear()
        transcribedText = ""
        audioLevel = 0
        isModelInitializing = false
        isFinalizingTranscription = false
        latestWordTimings = []
        realtimeEagerLastSampleCount = 0
        realtimeEagerLastPublishedSampleCount = 0
        realtimeEagerState.reset()
        realtimeTraceEntries.removeAll(keepingCapacity: false)
        realtimeCommittedSampleCount = 0
        realtimeWasRecentlySpeaking = false
        realtimeDidFlushCurrentSilence = false
        preparedWhisper?.audioProcessor.stopRecording()
        preparedWhisper?.audioProcessor.purgeAudioSamples(keepingLast: 0)
    }

    private func stageCompletedAudioArchive(samples: [Float], sampleRate: Double) {
        removeCompletedAudioArchiveIfNeeded()
        guard !samples.isEmpty else { return }
        let tempURL = HistoryAudioArchiveSupport.temporaryArchiveURL(prefix: "voxt-whisper-history")
        do {
            if try HistoryAudioArchiveSupport.exportWAV(samples: samples, sampleRate: sampleRate, to: tempURL) {
                completedAudioArchiveURL = tempURL
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            VoxtLog.warning("Whisper completed audio archive export failed: \(error.localizedDescription)")
        }
    }

    private func removeCompletedAudioArchiveIfNeeded() {
        guard let completedAudioArchiveURL else { return }
        try? FileManager.default.removeItem(at: completedAudioArchiveURL)
        self.completedAudioArchiveURL = nil
    }

    private func cancelActiveTasks() {
        partialLoopTask?.cancel()
        partialLoopTask = nil
        finalizationTask?.cancel()
        finalizationTask = nil
        isFinalizingTranscription = false
        activeInferencePassTask?.cancel()
        activeInferencePassTask = nil
        activeInferencePassID = nil
        activeInferencePassKind = nil
        captureWatchdogTask?.cancel()
        captureWatchdogTask = nil
        realtimeEagerTask?.cancel()
        realtimeEagerTask = nil
        realtimeLevelTask?.cancel()
        realtimeLevelTask = nil
        realtimeEagerLastSampleCount = 0
        realtimeEagerLastPublishedSampleCount = 0
        realtimeTraceEntries.removeAll(keepingCapacity: false)
        realtimeCommittedSampleCount = 0
        realtimeWasRecentlySpeaking = false
        realtimeDidFlushCurrentSilence = false
    }

    private func stopAudioEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.reset()
    }

    private func cleanupPreparedWhisperIfNeeded() {
        preparedWhisper?.audioProcessor.stopRecording()
        preparedWhisper?.audioProcessor.purgeAudioSamples(keepingLast: 0)
        realtimeEagerTask?.cancel()
        realtimeEagerTask = nil
        realtimeLevelTask?.cancel()
        realtimeLevelTask = nil
        activeInferencePassTask?.cancel()
        activeInferencePassTask = nil
        activeInferencePassID = nil
        activeInferencePassKind = nil
        realtimeEagerLastSampleCount = 0
        realtimeEagerLastPublishedSampleCount = 0
        realtimeEagerState.reset()
        realtimeTraceEntries.removeAll(keepingCapacity: false)
        realtimeCommittedSampleCount = 0
        realtimeWasRecentlySpeaking = false
        realtimeDidFlushCurrentSilence = false
        if activeUseHeld {
            modelManager.endActiveUse()
            activeUseHeld = false
        }
        preparedWhisper = nil
        preparedUseBuiltInTranslationTask = false
        isModelInitializing = false
        isFinalizingTranscription = false
    }

    private func startAudioCaptureGraph() throws {
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        audioEngine.reset()

        applyPreferredInputDeviceIfNeeded(inputNode: inputNode)
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputSampleRate = recordingFormat.sampleRate
        let sampleStore = self.sampleStore

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            sampleStore.noteCallback()
            guard let channelData = buffer.floatChannelData?[0] else { return }

            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }
            let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
            sampleStore.append(samples)

            var rms: Float = 0
            for index in 0..<frameLength {
                rms += channelData[index] * channelData[index]
            }
            rms = sqrt(rms / Float(frameLength))
            let normalized = min(rms * 20, 1.0)
            Task { @MainActor [weak self] in
                self?.audioLevel = normalized
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        VoxtLog.info(
            "Whisper audio capture started. sampleRate=\(Int(recordingFormat.sampleRate)), deviceID=\(preferredInputDeviceID.map(String.init(describing:)) ?? "default"), mode=offline",
            verbose: true
        )
    }

    private func scheduleCaptureStartupWatchdog(revision: Int) {
        captureWatchdogTask?.cancel()
        captureWatchdogTask = Task { [weak self] in
            do {
                try await Task.sleep(for: self?.captureStartupWatchdogDelay ?? .seconds(1.2))
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
        VoxtLog.warning("Whisper audio capture produced no initial callbacks. Restarting input graph once.")

        do {
            try startAudioCaptureGraph()
            scheduleCaptureStartupWatchdog(revision: revision)
        } catch {
            VoxtLog.error("Whisper audio capture recovery failed: \(error)")
        }
    }

    private func handleRealtimeAudioBuffer(revision: Int) {
        guard revision == sessionRevision, isRecording, effectiveWhisperRealtimeEnabled else { return }
        audioLevel = resolvedRealtimeAudioLevel(from: preparedWhisper?.audioProcessor.relativeEnergy ?? [])
    }

    private func startRealtimeEagerLoop(revision: Int) {
        realtimeEagerTask?.cancel()
        realtimeEagerLastSampleCount = 0
        realtimeEagerLastPublishedSampleCount = 0
        realtimeEagerTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.realtimeEagerPollInterval)
                } catch {
                    return
                }
                await self?.runRealtimeEagerPassIfNeeded(revision: revision)
            }
        }
    }

    private func runRealtimeEagerPassIfNeeded(revision: Int) async {
        guard revision == sessionRevision, isRecording, effectiveWhisperRealtimeEnabled else { return }
        let samples = snapshotPreparedAudioSamples()
        let sampleCount = samples.count
        guard sampleCount > 0 else { return }

        let activeSegmentSamples = resolvedRealtimeInferenceSamples(from: samples)
        let activeSegmentSampleCount = activeSegmentSamples.count
        guard activeSegmentSampleCount > 0 else { return }

        let bufferedSeconds = Double(activeSegmentSampleCount) / targetSampleRate
        let minimumSeconds = realtimeEagerState.mutablePublishedCharacterCount == 0
            ? Self.realtimeEagerFirstPassMinimumSeconds
            : Self.realtimeEagerSteadyStateMinimumSeconds
        guard bufferedSeconds >= minimumSeconds else { return }
        let hasRecentSpeech = Self.hasRecentSpeechActivity(
            samples: samples,
            targetSampleRate: targetSampleRate
        )
        let publishedStallSeconds = Double(max(sampleCount - realtimeEagerLastPublishedSampleCount, 0)) / targetSampleRate
        if hasRecentSpeech {
            realtimeWasRecentlySpeaking = true
            realtimeDidFlushCurrentSilence = false
        }
        let shouldFlushSilenceBoundary = !hasRecentSpeech &&
            realtimeWasRecentlySpeaking &&
            !realtimeDidFlushCurrentSilence &&
            !realtimeEagerState.publishedText.isEmpty &&
            publishedStallSeconds >= Self.realtimeDraftFallbackStallSeconds
        if shouldFlushSilenceBoundary {
            await reconcileRealtimeSilenceBoundary(
                revision: revision,
                samples: activeSegmentSamples,
                sampleCount: sampleCount
            )
            realtimeDidFlushCurrentSilence = true
            realtimeWasRecentlySpeaking = false
            return
        }
        let shouldHoldForSilence = !hasRecentSpeech &&
            !realtimeEagerState.publishedText.isEmpty &&
            publishedStallSeconds >= Self.realtimeDraftFallbackStallSeconds
        if shouldHoldForSilence {
            recordRealtimeTrace(
                "hold",
                sampleCount: sampleCount,
                rawText: "",
                publishedText: realtimeEagerState.publishedText,
                note: "silence-hold"
            )
            return
        }

        if realtimeEagerLastSampleCount > 0 {
            let newAudioSeconds = Double(max(sampleCount - realtimeEagerLastSampleCount, 0)) / targetSampleRate
            guard newAudioSeconds >= Self.realtimeEagerMinimumNewAudioSeconds else { return }
        }
        realtimeEagerLastSampleCount = sampleCount

        let usesBootstrapDraft = shouldUseRealtimeDraftBootstrap(bufferedSeconds: bufferedSeconds)
        if usesBootstrapDraft,
           let draftCandidate = await makeRealtimeDraftCandidate(revision: revision, samples: activeSegmentSamples),
           publishRealtimeDraftCandidate(
                draftCandidate,
                sampleCount: sampleCount,
                source: "draft-bootstrap"
           ) {
            return
        }

        guard let candidate = await makeRealtimeEagerCandidate(revision: revision, samples: activeSegmentSamples) else { return }
        _ = publishRealtimeEagerCandidate(candidate, sampleCount: sampleCount)
    }

    private func reconcileRealtimeSilenceBoundary(
        revision: Int,
        samples: [Float],
        sampleCount: Int
    ) async {
        if let candidate = await makeRealtimeSilenceReconcileCandidate(
            revision: revision,
            samples: samples
        ) {
            _ = publishRealtimeDraftCandidate(
                candidate,
                sampleCount: sampleCount,
                source: "silence-flush"
            )
        } else {
            recordRealtimeTrace(
                "silence-flush",
                sampleCount: sampleCount,
                rawText: "",
                publishedText: realtimeEagerState.publishedText,
                note: "reconcile-miss"
            )
        }
        realtimeEagerState.sealCurrentPublishedTextForNextUtterance()
        realtimeCommittedSampleCount = sampleCount
        realtimeEagerLastPublishedSampleCount = sampleCount
    }

    private func makeRealtimeDraftCandidate(revision: Int, samples: [Float]) async -> TranscriptionResult? {
        guard let whisper = preparedWhisper else { return nil }
        let windowSampleCount = max(Int(Self.realtimeDraftWindowSeconds * targetSampleRate), 1)
        let draftSamples = Array(samples.suffix(min(samples.count, windowSampleCount)))
        do {
            let transcription = try await runManagedTranscriptionPass(
                passKind: .realtimeDraft,
                whisper: whisper,
                samples: draftSamples,
                sampleRate: targetSampleRate,
                includeWordTimings: false,
                profile: .realtimeDraft,
                revision: revision
            )
            return transcription.results.first
        } catch is CancellationError {
            return nil
        } catch {
            VoxtLog.warning("Whisper realtime draft pass failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func makeRealtimeEagerCandidate(revision: Int, samples: [Float]) async -> TranscriptionResult? {
        guard let whisper = preparedWhisper else { return nil }
        do {
            let transcription = try await runManagedTranscriptionPass(
                passKind: .realtimeEager,
                whisper: whisper,
                samples: samples,
                sampleRate: targetSampleRate,
                includeWordTimings: false,
                profile: .realtimeEager,
                revision: revision
            )
            return transcription.results.first
        } catch is CancellationError {
            return nil
        } catch {
            VoxtLog.warning("Whisper realtime eager pass failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func makeRealtimeSilenceReconcileCandidate(revision: Int, samples: [Float]) async -> TranscriptionResult? {
        guard let whisper = preparedWhisper else { return nil }
        do {
            let transcription = try await runManagedTranscriptionPass(
                passKind: .realtimeSilenceReconcile,
                whisper: whisper,
                samples: samples,
                sampleRate: targetSampleRate,
                includeWordTimings: false,
                profile: .realtimeFinal,
                revision: revision
            )
            return transcription.results.first
        } catch is CancellationError {
            return nil
        } catch {
            VoxtLog.warning("Whisper realtime silence reconcile failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func startRealtimeLevelUpdates(revision: Int) {
        realtimeLevelTask?.cancel()
        realtimeLevelTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    return
                }
                self?.publishRealtimeAudioLevelIfNeeded(revision: revision)
            }
        }
    }

    private func publishRealtimeAudioLevelIfNeeded(revision: Int) {
        guard revision == sessionRevision, isRecording, effectiveWhisperRealtimeEnabled else { return }
        let energy = preparedWhisper?.audioProcessor.relativeEnergy ?? []
        audioLevel = resolvedRealtimeAudioLevel(from: energy)
    }

    private func resolvedRealtimeAudioLevel(from energy: [Float]) -> Float {
        guard !energy.isEmpty else { return 0 }
        let recentEnergy = Array(energy.suffix(4))
        guard !recentEnergy.isEmpty else { return 0 }
        let peak = recentEnergy.max() ?? 0
        let average = recentEnergy.reduce(0, +) / Float(recentEnergy.count)
        return min(max((peak * 0.7) + (average * 0.3), 0), 1)
    }

    @discardableResult
    private func publishRealtimeDraftCandidate(
        _ result: TranscriptionResult,
        sampleCount: Int,
        source: String
    ) -> Bool {
        guard let published = realtimeEagerState.apply(hypothesisText: result.text) else { return false }
        let normalized = normalizeText(published)
        guard !normalized.isEmpty else { return false }
        guard sessionAllowsRealtimeTextDisplay else { return false }
        transcribedText = normalized
        onPartialTranscription?(normalized)
        realtimeEagerLastPublishedSampleCount = sampleCount
        recordRealtimeTrace(
            source,
            sampleCount: sampleCount,
            rawText: result.text,
            publishedText: normalized
        )
        return true
    }

    @discardableResult
    private func publishRealtimeEagerCandidate(_ result: TranscriptionResult, sampleCount: Int) -> Bool {
        guard let published = realtimeEagerState.apply(result) else { return false }
        let normalized = normalizeText(published)
        guard !normalized.isEmpty else { return false }
        guard sessionAllowsRealtimeTextDisplay else { return false }
        transcribedText = normalized
        onPartialTranscription?(normalized)
        realtimeEagerLastPublishedSampleCount = sampleCount
        recordRealtimeTrace(
            "eager",
            sampleCount: sampleCount,
            rawText: result.text,
            publishedText: normalized
        )
        return true
    }

    private func shouldUseRealtimeDraftBootstrap(bufferedSeconds: Double) -> Bool {
        Self.shouldUseRealtimeDraftBootstrap(
            bufferedSeconds: bufferedSeconds,
            publishedCharacterCount: realtimeEagerState.mutablePublishedCharacterCount
        )
    }

    private static func shouldUseRealtimeDraftBootstrap(
        bufferedSeconds: Double,
        publishedCharacterCount: Int
    ) -> Bool {
        bufferedSeconds <= Self.realtimeDraftBootstrapSeconds &&
            publishedCharacterCount < Self.realtimeDraftBootstrapCharacterCount
    }

    private func publishWhisperFinalText(_ text: String) {
        if effectiveWhisperRealtimeEnabled {
            let normalized = normalizeText(text)
            if let published = realtimeEagerState.applyFinal(normalized) {
                transcribedText = published
                onPartialTranscription?(published)
                recordRealtimeTrace(
                    "final",
                    sampleCount: snapshotPreparedAudioSamples().count,
                    rawText: normalized,
                    publishedText: published
                )
            }
            return
        }

        transcribedText = text
        onPartialTranscription?(text)
    }

    func consumeRealtimeTraceEntries() -> [String] {
        let entries = realtimeTraceEntries
        realtimeTraceEntries.removeAll(keepingCapacity: false)
        return entries
    }

    func debugCaptureStopSummary() -> String {
        let sampleCount = effectiveWhisperRealtimeEnabled ? snapshotPreparedAudioSamples().count : sampleStore.count()
        let sampleRate = effectiveWhisperRealtimeEnabled ? targetSampleRate : inputSampleRate
        let bufferedSeconds = Double(sampleCount) / max(sampleRate, 1)
        return """
        realtime=\(effectiveWhisperRealtimeEnabled), sampleCount=\(sampleCount), bufferedSec=\(String(format: "%.2f", bufferedSeconds)), callbacks=\(sampleStore.callbacksReceived()), partialChars=\(transcribedText.count), finalizing=\(isFinalizingTranscription)
        """
    }

    private func recordRealtimeTrace(
        _ source: String,
        sampleCount: Int,
        rawText: String,
        publishedText: String,
        note: String? = nil
    ) {
        let seconds = Double(sampleCount) / targetSampleRate
        let trace = String(
            format: "[%.2fs] %@ raw=%@ published=%@%@",
            seconds,
            source,
            Self.traceQuoted(normalizeText(rawText)),
            Self.traceQuoted(normalizeText(publishedText)),
            note.map { " note=\($0)" } ?? ""
        )
        realtimeTraceEntries.append(trace)
        if realtimeTraceEntries.count > 200 {
            realtimeTraceEntries.removeFirst(realtimeTraceEntries.count - 200)
        }
    }

    private static func traceQuoted(_ text: String) -> String {
        "\"\(text.replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private static func hasRecentSpeechActivity(
        samples: [Float],
        targetSampleRate: Double
    ) -> Bool {
        guard !samples.isEmpty else { return false }
        let windowSampleCount = max(Int(Self.realtimeSilenceWindowSeconds * targetSampleRate), 1)
        let recentSamples = samples.suffix(min(samples.count, windowSampleCount))
        guard !recentSamples.isEmpty else { return false }

        var sumSquares: Float = 0
        var peak: Float = 0
        for sample in recentSamples {
            let magnitude = abs(sample)
            sumSquares += magnitude * magnitude
            peak = max(peak, magnitude)
        }

        let rms = sqrt(sumSquares / Float(recentSamples.count))
        return rms >= Self.realtimeSilenceRMSHoldThreshold || peak >= Self.realtimeSilencePeakHoldThreshold
    }

    private func resolvedRealtimeInferenceSamples(from samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let overlapSampleCount = max(Int(Self.realtimeSegmentOverlapSeconds * targetSampleRate), 0)
        let startSample = max(0, min(realtimeCommittedSampleCount, samples.count) - overlapSampleCount)
        guard startSample > 0 else { return samples }
        return Array(samples[startSample...])
    }

    private func inferredPassKind(
        profile: WhisperInferenceProfile,
        publishFinalResult: Bool
    ) -> WhisperInferencePassKind {
        if publishFinalResult {
            return profile == .offline ? .stopFinalOffline : .stopFinalRealtime
        }
        switch profile {
        case .offline:
            return .offlineIntermediate
        case .realtimeDraft:
            return .realtimeDraft
        case .realtimeEager:
            return .realtimeEager
        case .realtimeFinal:
            return .realtimeSilenceReconcile
        }
    }

    private func runManagedTranscriptionPass(
        passKind: WhisperInferencePassKind,
        whisper: WhisperKit,
        samples: [Float],
        sampleRate: Double,
        includeWordTimings: Bool,
        profile: WhisperInferenceProfile,
        revision: Int
    ) async throws -> WhisperPreparedTranscription {
        switch Self.inferenceSchedulingDecision(
            requestedPass: passKind,
            inFlightPass: activeInferencePassKind
        ) {
        case .startImmediately:
            break
        case .waitForInFlightPass:
            break
        case .skipRequestedPass:
            throw CancellationError()
        case .interruptInFlightPass:
            if let activeInferencePassKind {
                VoxtLog.info(
                    "Whisper inference pass preempted. inFlight=\(String(describing: activeInferencePassKind)), requested=\(String(describing: passKind))",
                    verbose: true
                )
            }
            activeInferencePassTask?.cancel()
        }

        while let activeTask = activeInferencePassTask {
            let activePassID = activeInferencePassID
            do {
                _ = try await activeTask.value
            } catch {
                // The launching caller handles the prior pass outcome; this waiter only
                // needs the inference slot to clear before starting the next pass.
            }
            if activeInferencePassID == activePassID {
                clearActiveInferencePassIfNeeded(passID: activePassID)
            }
        }

        let passID = UUID()
        let passTask = Task<WhisperPreparedTranscription, Error> { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.transcribePreparedSamples(
                whisper: whisper,
                samples: samples,
                sampleRate: sampleRate,
                includeWordTimings: includeWordTimings,
                profile: profile,
                revision: revision
            )
        }
        activeInferencePassID = passID
        activeInferencePassKind = passKind
        activeInferencePassTask = passTask

        do {
            let result = try await passTask.value
            clearActiveInferencePassIfNeeded(passID: passID)
            return result
        } catch {
            clearActiveInferencePassIfNeeded(passID: passID)
            throw error
        }
    }

    private func clearActiveInferencePassIfNeeded(passID: UUID?) {
        guard activeInferencePassID == passID else { return }
        activeInferencePassID = nil
        activeInferencePassTask = nil
        activeInferencePassKind = nil
    }

    private func transcribePreparedSamples(
        whisper: WhisperKit,
        samples: [Float],
        sampleRate: Double,
        includeWordTimings: Bool,
        profile: WhisperInferenceProfile,
        revision: Int
    ) async throws -> WhisperPreparedTranscription {
        while isInferenceRunning {
            do {
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                throw CancellationError()
            }
        }

        guard revision == sessionRevision else {
            throw CancellationError()
        }

        isInferenceRunning = true
        defer { isInferenceRunning = false }

        try Task.checkCancellation()
        let preparedSamples = prepareInputSamples(samples, sampleRate: sampleRate)
        let audioDurationSeconds = Double(preparedSamples.count) / targetSampleRate
        let decodeOptions = buildDecodingOptions(
            whisper: whisper,
            includeWordTimings: includeWordTimings,
            profile: profile,
            audioDurationSeconds: audioDurationSeconds
        )
        var results = try await whisper.transcribe(audioArray: preparedSamples, decodeOptions: decodeOptions)
        try Task.checkCancellation()
        var rawJoinedText = results.map(\.text).joined(separator: " ")
        let initialText = normalizeText(rawJoinedText)
        if let fallbackLanguage = fallbackWhisperLanguageIfNeeded(
            profile: profile,
            audioDurationSeconds: audioDurationSeconds,
            normalizedText: initialText
        ) {
            try Task.checkCancellation()
            let fallbackResults = try await whisper.transcribe(
                audioArray: preparedSamples,
                decodeOptions: buildDecodingOptions(
                    whisper: whisper,
                    includeWordTimings: includeWordTimings,
                    profile: profile,
                    audioDurationSeconds: audioDurationSeconds,
                    forcedLanguage: fallbackLanguage
                )
            )
            try Task.checkCancellation()
            let fallbackRawJoinedText = fallbackResults.map(\.text).joined(separator: " ")
            let fallbackText = normalizeText(fallbackRawJoinedText)
            if shouldPreferWhisperFallbackResult(
                primaryText: initialText,
                fallbackText: fallbackText
            ) {
                VoxtLog.info(
                    """
                    Whisper explicit-language fallback selected. profile=\(profile.rawValue), language=\(fallbackLanguage), primaryChars=\(initialText.count), fallbackChars=\(fallbackText.count), audioDurationSec=\(String(format: "%.1f", audioDurationSeconds))
                    """,
                    verbose: true
                )
                results = fallbackResults
                rawJoinedText = fallbackRawJoinedText
            }
        }
        guard revision == sessionRevision else {
            throw CancellationError()
        }
        let text = normalizeText(rawJoinedText)
        return WhisperPreparedTranscription(
            preparedSamples: preparedSamples,
            results: results,
            text: text
        )
    }

    private func snapshotPreparedAudioSamples() -> [Float] {
        guard let preparedWhisper else { return [] }
        return Array(preparedWhisper.audioProcessor.audioSamples)
    }

    private func normalizeText(_ text: String) -> String {
        WhisperTextPostProcessor.normalize(
            text,
            preferredMainLanguage: preferredMainLanguage,
            outputMode: preparedOutputMode,
            usesBuiltInTranslationTask: preparedUseBuiltInTranslationTask
        )
    }

    private func fallbackWhisperLanguageIfNeeded(
        profile: WhisperInferenceProfile,
        audioDurationSeconds: Double,
        normalizedText: String
    ) -> String? {
        guard profile == .offline else { return nil }
        let preferredLanguage = preferredMainLanguage.baseLanguageCode
        guard !preferredLanguage.isEmpty else { return nil }

        if audioDurationSeconds >= Self.realtimeLongFormFinalProfileThresholdSeconds {
            return normalizedText.count < 20 ? preferredLanguage : nil
        }

        return normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? preferredLanguage
            : nil
    }

    private func shouldPreferWhisperFallbackResult(
        primaryText: String,
        fallbackText: String
    ) -> Bool {
        let primaryCount = primaryText.trimmingCharacters(in: .whitespacesAndNewlines).count
        let fallbackCount = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines).count
        guard fallbackCount > 0 else { return false }
        guard primaryCount > 0 else { return true }
        return fallbackCount >= max(primaryCount + 8, Int(Double(primaryCount) * 1.5))
    }

    private var whisperTemperature: Float {
        Float(UserDefaults.standard.double(forKey: AppPreferenceKey.whisperTemperature))
    }

    private var whisperVADEnabled: Bool {
        UserDefaults.standard.object(forKey: AppPreferenceKey.whisperVADEnabled) as? Bool ?? true
    }

    private var whisperTimestampsEnabled: Bool {
        UserDefaults.standard.object(forKey: AppPreferenceKey.whisperTimestampsEnabled) as? Bool ?? false
    }

    private var whisperRealtimeEnabled: Bool {
        UserDefaults.standard.object(forKey: AppPreferenceKey.whisperRealtimeEnabled) as? Bool ?? false
    }

    private var effectiveWhisperRealtimeEnabled: Bool {
        sessionAllowsRealtimeTextDisplay && whisperRealtimeEnabled
    }

    private var preferredMainLanguage: UserMainLanguageOption {
        let selectedCodes = UserMainLanguageOption.storedSelection(
            from: UserDefaults.standard.string(forKey: AppPreferenceKey.userMainLanguageCodes)
        )
        if let firstCode = selectedCodes.first,
           let option = UserMainLanguageOption.option(for: firstCode) {
            return option
        }
        return UserMainLanguageOption.fallbackOption()
    }

    private func resolvedWhisperLanguage(
        for profile: WhisperInferenceProfile,
        hintPayload: ResolvedASRHintPayload
    ) -> String? {
        // Local Whisper performs better across mixed and unexpected language samples
        // when we keep language as auto-detect and rely on prompt/context bias instead
        // of force-pinning the decoder to the user's primary language.
        _ = profile
        return hintPayload.language
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

    private static func resample(samples: [Float], from inputRate: Double, to outputRate: Double) -> [Float] {
        guard !samples.isEmpty, inputRate > 0, outputRate > 0 else { return samples }
        if abs(inputRate - outputRate) <= 1 {
            return samples
        }

        let ratio = outputRate / inputRate
        let outputCount = max(Int(Double(samples.count) * ratio), 1)
        var output = [Float](repeating: 0, count: outputCount)

        for index in 0..<outputCount {
            let position = Double(index) / ratio
            let lowerIndex = Int(position)
            let upperIndex = min(lowerIndex + 1, samples.count - 1)
            let fraction = Float(position - Double(lowerIndex))
            let lower = samples[min(lowerIndex, samples.count - 1)]
            let upper = samples[upperIndex]
            output[index] = lower + (upper - lower) * fraction
        }

        return output
    }
}
