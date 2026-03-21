import Foundation
import AVFoundation
import Combine
import AudioToolbox
import WhisperKit

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

    private actor RealtimeStartGate {
        enum Outcome {
            case success
            case failure(Error)
        }

        private var outcome: Outcome?
        private var continuation: CheckedContinuation<Outcome, Never>?

        func wait() async -> Outcome {
            if let outcome {
                return outcome
            }
            return await withCheckedContinuation { continuation in
                if let outcome {
                    continuation.resume(returning: outcome)
                    return
                }
                self.continuation = continuation
            }
        }

        func succeed() {
            resolve(.success)
        }

        func fail(_ error: Error) {
            resolve(.failure(error))
        }

        private func resolve(_ outcome: Outcome) {
            guard self.outcome == nil else {
                return
            }
            self.outcome = outcome
            let continuation = self.continuation
            self.continuation = nil
            continuation?.resume(returning: outcome)
        }
    }

    static let offlinePartialPollInterval: Duration = .seconds(6)
    static let offlineFirstPartialMinimumSeconds: Double = 5.0

    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var transcribedText = ""
    @Published var isEnhancing = false

    var onTranscriptionFinished: ((String) -> Void)?
    var onPartialTranscription: ((String) -> Void)?
    private(set) var lastStartFailureMessage: String?
    private(set) var latestWordTimings: [WhisperHistoryWordTiming] = []

    private let audioEngine = AVAudioEngine()
    private let sampleStore = AudioSampleStore()
    private let modelManager: WhisperKitModelManager
    private var preferredInputDeviceID: AudioDeviceID?
    private var inputSampleRate: Double = 16000
    private var preparedWhisper: WhisperKit?
    private var preparedOutputMode: AppDelegate.SessionOutputMode = .transcription
    private var preparedUseBuiltInTranslationTask = false
    private var sessionRevision = 0
    private var partialLoopTask: Task<Void, Never>?
    private var finalizationTask: Task<Void, Never>?
    private var captureWatchdogTask: Task<Void, Never>?
    private var realtimeTranscriptionTask: Task<Void, Never>?
    private var audioStreamTranscriber: AudioStreamTranscriber?
    private var activeUseHeld = false
    private var isInferenceRunning = false
    private var didRetryCaptureStartup = false

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

    func prepareSession(
        outputMode: AppDelegate.SessionOutputMode,
        useBuiltInTranslationTask: Bool = false
    ) async -> String? {
        cancelActiveTasks()
        cleanupPreparedWhisperIfNeeded()
        resetTransientState()
        preparedOutputMode = outputMode
        preparedUseBuiltInTranslationTask = useBuiltInTranslationTask
        lastStartFailureMessage = nil

        do {
            modelManager.beginActiveUse()
            activeUseHeld = true
            preparedWhisper = try await modelManager.loadWhisper()
            return nil
        } catch {
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

        if whisperRealtimeEnabled {
            return await startRealtimeRecordingSession(revision: sessionRevision)
        }

        do {
            try startAudioCaptureGraph()
            isRecording = true
            let revision = sessionRevision
            scheduleCaptureStartupWatchdog(revision: revision)
            partialLoopTask = Task { [weak self] in
                await self?.runPartialLoop(revision: revision)
            }
            return nil
        } catch {
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
        isRecording = false
        audioLevel = 0

        partialLoopTask?.cancel()
        partialLoopTask = nil
        captureWatchdogTask?.cancel()
        captureWatchdogTask = nil

        finalizationTask?.cancel()
        if whisperRealtimeEnabled {
            let streamTranscriber = audioStreamTranscriber
            audioStreamTranscriber = nil
            finalizationTask = Task { [weak self] in
                await streamTranscriber?.stopStreamTranscription()
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
        guard isRecording, !whisperRealtimeEnabled else { return }
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

    private func startRealtimeRecordingSession(revision: Int) async -> String? {
        guard let whisper = preparedWhisper else {
            return String(localized: "Whisper is not ready yet. Open Settings > Model and try again.")
        }

        do {
            let startGate = RealtimeStartGate()
            let streamTranscriber = try makeAudioStreamTranscriber(
                whisper: whisper,
                revision: revision,
                startGate: startGate
            )
            audioStreamTranscriber = streamTranscriber
            realtimeTranscriptionTask = Task { [weak self] in
                do {
                    try await streamTranscriber.startStreamTranscription()
                } catch {
                    await startGate.fail(error)
                    await self?.handleRealtimeTranscriptionError(error, revision: revision)
                }
                self?.handleRealtimeTranscriptionTaskExit(revision: revision)
            }

            let outcome = await startGate.wait()
            switch outcome {
            case .success:
                return nil
            case .failure(let error):
                let message = String(localized: "Whisper failed to start recording.")
                lastStartFailureMessage = message
                VoxtLog.error("Whisper realtime start failed: \(error)")
                cleanupPreparedWhisperIfNeeded()
                return message
            }
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
        await runInference(
            revision: revision,
            samples: samples,
            sampleRate: sampleRate,
            includeWordTimings: whisperTimestampsEnabled,
            publishFinalResult: true
        )
    }

    private func runInference(
        revision: Int,
        samples: [Float],
        sampleRate: Double,
        includeWordTimings: Bool,
        publishFinalResult: Bool
    ) async {
        guard !samples.isEmpty else {
            if publishFinalResult {
                cleanupPreparedWhisperIfNeeded()
                onTranscriptionFinished?("")
            }
            return
        }

        while isInferenceRunning {
            do {
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                return
            }
        }

        guard revision == sessionRevision else { return }
        guard let whisper = preparedWhisper else {
            if publishFinalResult {
                cleanupPreparedWhisperIfNeeded()
                onTranscriptionFinished?("")
            }
            return
        }

        isInferenceRunning = true
        defer {
            isInferenceRunning = false
            if publishFinalResult {
                cleanupPreparedWhisperIfNeeded()
            }
        }

        do {
            let preparedSamples = prepareInputSamples(samples, sampleRate: sampleRate)
            let decodeOptions = buildDecodingOptions(
                whisper: whisper,
                includeWordTimings: includeWordTimings
            )
            let results = try await whisper.transcribe(audioArray: preparedSamples, decodeOptions: decodeOptions)
            guard revision == sessionRevision else { return }

            let text = normalizeText(results.map(\.text).joined(separator: " "))
            if publishFinalResult {
                latestWordTimings = includeWordTimings ? buildWordTimings(from: results) : []
                transcribedText = text
                onPartialTranscription?(text)
                onTranscriptionFinished?(text)
            } else {
                transcribedText = text
                onPartialTranscription?(text)
            }
        } catch {
            VoxtLog.error("Whisper inference failed: \(error)")
            if publishFinalResult {
                latestWordTimings = []
                onTranscriptionFinished?(transcribedText.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    private func buildDecodingOptions(
        whisper: WhisperKit,
        includeWordTimings: Bool
    ) -> DecodingOptions {
        let hintPayload = resolvedHintPayload()
        let resolvedTask = resolvedDecodingTask()
        let detectLanguage = hintPayload.language == nil
        let promptTokens: [Int]?
        if let prompt = hintPayload.prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty,
           let tokenizer = whisper.tokenizer {
            promptTokens = tokenizer.encode(text: " " + prompt)
                .filter { token in token < tokenizer.specialTokens.specialTokenBegin }
        } else {
            promptTokens = nil
        }

        VoxtLog.info(
            "Whisper decode options. task=\(resolvedTask.description), language=\(hintPayload.language ?? "auto"), detectLanguage=\(detectLanguage), promptChars=\(hintPayload.prompt?.count ?? 0), promptTokens=\(promptTokens?.count ?? 0), realtime=\(whisperRealtimeEnabled)",
            verbose: true
        )

        return DecodingOptions(
            verbose: false,
            task: resolvedTask,
            language: hintPayload.language,
            temperature: whisperTemperature,
            temperatureFallbackCount: 0,
            usePrefillPrompt: true,
            detectLanguage: detectLanguage,
            skipSpecialTokens: true,
            withoutTimestamps: !includeWordTimings,
            wordTimestamps: includeWordTimings,
            promptTokens: promptTokens,
            chunkingStrategy: whisperVADEnabled ? .vad : nil
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
            userLanguageCodes: userLanguageCodes
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
        latestWordTimings = []
        audioStreamTranscriber = nil
        preparedWhisper?.audioProcessor.stopRecording()
        preparedWhisper?.audioProcessor.purgeAudioSamples(keepingLast: 0)
    }

    private func cancelActiveTasks() {
        partialLoopTask?.cancel()
        partialLoopTask = nil
        finalizationTask?.cancel()
        finalizationTask = nil
        captureWatchdogTask?.cancel()
        captureWatchdogTask = nil
        realtimeTranscriptionTask?.cancel()
        realtimeTranscriptionTask = nil
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
        audioStreamTranscriber = nil
        if activeUseHeld {
            modelManager.endActiveUse()
            activeUseHeld = false
        }
        preparedWhisper = nil
        preparedUseBuiltInTranslationTask = false
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

    private func makeAudioStreamTranscriber(
        whisper: WhisperKit,
        revision: Int,
        startGate: RealtimeStartGate
    ) throws -> AudioStreamTranscriber {
        guard let tokenizer = whisper.tokenizer else {
            throw NSError(domain: "Voxt.WhisperKitTranscriber", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Whisper tokenizer is unavailable."
            ])
        }

        let decodeOptions = buildDecodingOptions(whisper: whisper, includeWordTimings: false)
        inputSampleRate = targetSampleRate
        return AudioStreamTranscriber(
            audioEncoder: whisper.audioEncoder,
            featureExtractor: whisper.featureExtractor,
            segmentSeeker: whisper.segmentSeeker,
            textDecoder: whisper.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: whisper.audioProcessor,
            decodingOptions: decodeOptions,
            useVAD: whisperVADEnabled,
            stateChangeCallback: { [weak self] oldState, newState in
                Task { @MainActor [weak self] in
                    self?.handleRealtimeStateChange(
                        oldState: oldState,
                        newState: newState,
                        revision: revision,
                        startGate: startGate
                    )
                }
            }
        )
    }

    private func handleRealtimeStateChange(
        oldState: AudioStreamTranscriber.State,
        newState: AudioStreamTranscriber.State,
        revision: Int,
        startGate: RealtimeStartGate
    ) {
        guard revision == sessionRevision else { return }

        if newState.isRecording && !oldState.isRecording {
            isRecording = true
            Task {
                await startGate.succeed()
            }
            VoxtLog.info(
                "Whisper audio capture started. sampleRate=\(Int(targetSampleRate)), deviceID=\(preferredInputDeviceID.map(String.init(describing:)) ?? "default"), mode=realtime",
                verbose: true
            )
        }

        audioLevel = max(newState.bufferEnergy.max() ?? 0, 0)
        let mergedText = mergedRealtimeText(from: newState)
        if !mergedText.isEmpty {
            transcribedText = mergedText
            onPartialTranscription?(mergedText)
        }
    }

    private func handleRealtimeTranscriptionError(_ error: Error, revision: Int) async {
        guard revision == sessionRevision else { return }
        VoxtLog.error("Whisper realtime transcription failed: \(error)")
        guard isRecording else { return }
        stopRecording()
    }

    private func handleRealtimeTranscriptionTaskExit(revision: Int) {
        guard revision == sessionRevision else { return }
        realtimeTranscriptionTask = nil
    }

    private func mergedRealtimeText(from state: AudioStreamTranscriber.State) -> String {
        let confirmed = state.confirmedSegments.map(\.text).joined()
        let unconfirmedSegments = state.unconfirmedSegments.map(\.text).joined()
        let fallback = state.currentText.isEmpty ? state.unconfirmedText.last ?? "" : state.currentText
        let merged = normalizeText(confirmed + (unconfirmedSegments.isEmpty ? fallback : unconfirmedSegments))
        return merged == "Waiting for speech..." ? "" : merged
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
        UserDefaults.standard.object(forKey: AppPreferenceKey.whisperRealtimeEnabled) as? Bool ?? true
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
