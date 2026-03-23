import Foundation
import AVFoundation
import Combine
@preconcurrency import MLX
import MLXAudioCore
import MLXAudioSTT
import AudioToolbox

@MainActor
class MLXTranscriber: ObservableObject, TranscriberProtocol {
    private enum CorrectionStage {
        case intermediate
        case postStopQuick
        case postStopFinal
    }

    private final class AudioSampleStore {
        private let lock = NSLock()
        private var samples: [Float] = []

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

        func clear() {
            lock.lock()
            defer { lock.unlock() }
            samples.removeAll(keepingCapacity: false)
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
    private var inferenceBusy = false

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
        isModelInitializing = modelManager.state != .ready

        do {
            let inputNode = audioEngine.inputNode
            applyPreferredInputDeviceIfNeeded(inputNode: inputNode)
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputSampleRate = recordingFormat.sampleRate
            let sampleStore = self.sampleStore

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                guard let self, let channelData = buffer.floatChannelData?[0] else { return }

                let frameLength = Int(buffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData, count: frameLength))
                sampleStore.append(samples)

                if frameLength > 0 {
                    var rms: Float = 0
                    for i in 0..<frameLength {
                        rms += channelData[i] * channelData[i]
                    }
                    rms = sqrt(rms / Float(frameLength))
                    let normalized = min(rms * 20, 1.0)
                    Task { @MainActor [weak self] in
                        self?.audioLevel = normalized
                    }
                }
            }

            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            let revision = sessionRevision
            correctionLoopTask = Task { [weak self] in
                await self?.runIntermediateCorrectionLoop(revision: revision)
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

        guard sampleStore.count() > 0 else {
            onTranscriptionFinished?("")
            return
        }

        finalizationTask?.cancel()
        finalizationTask = Task { [weak self] in
            await self?.runFinalizationPipeline(revision: revision, sampleRate: sampleRate)
        }
    }

    /// Triggers an intermediate transcription pass while recording.
    /// Used to improve responsiveness during short pauses in speech.
    func forceIntermediateTranscription() {
        guard isRecording else { return }
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

    private func runIntermediateCorrectionLoop(revision: Int) async {
        while !Task.isCancelled, revision == sessionRevision, isRecording {
            do {
                try await Task.sleep(for: correctionPollInterval)
            } catch {
                return
            }

            guard revision == sessionRevision, isRecording else { return }
            let sampleCount = sampleStore.count()
            guard sampleCount > 0 else { continue }

            let elapsed = Double(sampleCount) / safeSampleRate(inputSampleRate)
            guard elapsed >= firstCorrectionMinimumSeconds else { continue }
            guard elapsed >= nextCorrectionAtSeconds else { continue }
            let contextCount = Int(intermediateContextWindowSeconds * safeSampleRate(inputSampleRate))
            let intermediateSamples = sampleStore.tail(sampleCount: contextCount)

            _ = await runCorrectionPass(
                stage: .intermediate,
                revision: revision,
                explicitSamples: intermediateSamples,
                sampleRate: inputSampleRate
            )

            nextCorrectionAtSeconds = elapsed + correctionIntervalSeconds
        }
    }

    private func runFinalizationPipeline(revision: Int, sampleRate: Double) async {
        let snapshot = sampleStore.snapshot()
        guard !snapshot.isEmpty else {
            onTranscriptionFinished?("")
            sampleStore.clear()
            return
        }

        let duration = Double(snapshot.count) / safeSampleRate(sampleRate)
        let quickSource: [Float]?
        if duration >= quickPassMinimumDurationSeconds {
            let quickContextCount = Int(quickPassContextWindowSeconds * safeSampleRate(sampleRate))
            quickSource = latestWindow(from: snapshot, maxCount: quickContextCount)
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
        sampleStore.clear()
    }

    private func runCorrectionPass(
        stage: CorrectionStage,
        revision: Int,
        explicitSamples: [Float]?,
        sampleRate: Double
    ) async -> String? {
        if stage == .intermediate, inferenceBusy {
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

        do {
            modelManager.beginActiveUse()
            defer { modelManager.endActiveUse() }
            let model = try await modelManager.loadModel()
            await MainActor.run {
                self.isModelInitializing = false
            }
            let audioSamples = try prepareInputSamples(rawSamples, sampleRate: sampleRate)
            let parameters = generationParameters(for: stage)
            let (streamedText, finalOutput) = try await runStreamingInference(
                model: model,
                audioSamples: audioSamples,
                generationParameters: parameters
            )

            let candidate = normalizeText(finalOutput?.text ?? streamedText)
            guard !candidate.isEmpty else { return nil }
            applyCandidate(candidate, stage: stage)
            return candidate
        } catch {
            await MainActor.run {
                self.isModelInitializing = false
            }
            VoxtLog.error("MLXTranscriber \(stageLabel(for: stage)) pass failed: \(error)")
            return nil
        }
    }

    private func resetTransientState() {
        sampleStore.clear()
        transcribedText = ""
        audioLevel = 0
        isModelInitializing = false
        stableCommittedText = ""
        lastCandidateText = ""
        nextCorrectionAtSeconds = correctionIntervalSeconds
    }

    private func stopAudioEngine() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }

    private func cancelActiveTasks() {
        correctionLoopTask?.cancel()
        correctionLoopTask = nil
        finalizationTask?.cancel()
        finalizationTask = nil
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

    private func generationParameters(for stage: CorrectionStage) -> STTGenerateParameters? {
        let hintPayload = resolvedHintPayload()
        let languageHint = hintPayload.language
        switch stage {
        case .intermediate:
            return STTGenerateParameters(
                maxTokens: 1024,
                temperature: 0.0,
                topP: 0.95,
                topK: 0,
                language: languageHint ?? "English"
            )
        case .postStopQuick:
            return STTGenerateParameters(
                maxTokens: 2048,
                temperature: 0.0,
                topP: 0.95,
                topK: 0,
                language: languageHint ?? "English"
            )
        case .postStopFinal:
            guard let languageHint else { return nil }
            return STTGenerateParameters(language: languageHint)
        }
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

    private func stageLabel(for stage: CorrectionStage) -> String {
        switch stage {
        case .intermediate: return "intermediate"
        case .postStopQuick: return "post-stop quick"
        case .postStopFinal: return "post-stop final"
        }
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
        generationParameters: STTGenerateParameters?
    ) async throws -> (streamedText: String, finalOutput: STTOutput?) {
        let audioArray = MLXArray(audioSamples)
        var streamedText = ""
        var finalOutput: STTOutput?

        let stream: AsyncThrowingStream<STTGeneration, Error>
        if let generationParameters {
            stream = model.generateStream(audio: audioArray, generationParameters: generationParameters)
        } else {
            stream = model.generateStream(audio: audioArray)
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
            let parameters = generationParameters(for: .postStopFinal)
            let (streamedText, finalOutput) = try await runStreamingInference(
                model: model,
                audioSamples: audioSamples,
                generationParameters: parameters
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
