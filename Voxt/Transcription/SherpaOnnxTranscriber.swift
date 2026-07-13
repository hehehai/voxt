// SherpaOnnxTranscriber.swift
// Provides offline sherpa-onnx ASR transcription.

import AVFoundation
import AudioToolbox
import Combine
import Foundation

fileprivate struct SherpaOnnxRecognitionConfiguration: Sendable {
    let numThreads: Int32
    let language: String?
    let hotwords: [String]
    let funASRMaxNewTokens: Int32
    let funASRTopP: Float
    let funASRUseITN: Bool
}

@MainActor
final class SherpaOnnxTranscriber: ObservableObject, TranscriberProtocol {
    @Published var isRecording = false
    @Published var audioLevel: Float = 0.0
    @Published var transcribedText = ""
    @Published var isEnhancing = false
    @Published var isFinalizingTranscription = false

    var onTranscriptionFinished: ((String) -> Void)?
    var onStartFailure: ((String) -> Void)?
    var dictionaryEntryProvider: (() -> [DictionaryEntry])?

    private let audioEngine = AVAudioEngine()
    private let modelManager: SherpaOnnxModelManager
    private var preferredInputDeviceID: AudioDeviceID?
    private var activeAudioFile: AVAudioFile?
    private var activeAudioURL: URL?
    private var completedAudioArchiveURL: URL?
    private var pendingRuntimeFailureMessage: String?
    private var activeCaptureUsesPreferredInputDevice = false
    private let targetSampleRate = 16000

    init(modelManager: SherpaOnnxModelManager) {
        self.modelManager = modelManager
    }

    func setPreferredInputDevice(_ deviceID: AudioDeviceID?) {
        preferredInputDeviceID = deviceID
    }

    func requestPermissions() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func startRecording() {
        do {
            try startAudioCapture()
        } catch {
            let message = AppLocalization.localizedString("Sherpa ONNX failed to start recording.")
            pendingRuntimeFailureMessage = "\(message) \(error.localizedDescription)"
            onStartFailure?(pendingRuntimeFailureMessage ?? message)
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        activeAudioFile = nil
        isRecording = false
        audioLevel = 0

        guard let audioURL = activeAudioURL else {
            finishTranscription("")
            return
        }
        activeAudioURL = nil
        completedAudioArchiveURL = audioURL
        runOfflineRecognition(fileURL: audioURL)
    }

    func restartCaptureForPreferredInputDevice() throws {
        guard isRecording else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        activeAudioFile = nil
        try startAudioCapture()
    }

    func consumeCompletedAudioArchiveURL() -> URL? {
        let url = completedAudioArchiveURL
        completedAudioArchiveURL = nil
        return url
    }

    func discardCompletedAudioArchive() {
        if let completedAudioArchiveURL {
            try? FileManager.default.removeItem(at: completedAudioArchiveURL)
        }
        completedAudioArchiveURL = nil
    }

    func consumePendingRuntimeFailureMessage() -> String? {
        let message = pendingRuntimeFailureMessage
        pendingRuntimeFailureMessage = nil
        return message
    }

    func transcribeBufferedChunk(samples: [Float], sampleRate: Double) async throws -> String? {
        guard !samples.isEmpty else { return nil }
        let modelID = modelManager.selectedModelID
        guard let modelDirectory = modelManager.modelDirectoryURL(id: modelID) else {
            throw NSError(
                domain: "SherpaOnnxTranscriber",
                code: 2004,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Sherpa ONNX model is not installed.")]
            )
        }

        let recognitionConfiguration = resolvedRecognitionConfiguration(for: modelID)
        let resampledSamples = await Task.detached(priority: .userInitiated) {
            Self.resampleMonoSamples(
                samples,
                sourceSampleRate: sampleRate,
                targetSampleRate: Double(self.targetSampleRate)
            )
        }.value
        let text = try await Self.recognize(
            samples: resampledSamples,
            sampleRate: Int32(targetSampleRate),
            modelID: modelID,
            modelDirectory: modelDirectory,
            recognitionConfiguration: recognitionConfiguration
        )
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    func transcribeAudioFile(_ fileURL: URL) async throws -> String {
        let loaded = try await Task.detached(priority: .userInitiated) {
            try DebugAudioClipIO.loadMonoSamples(from: fileURL)
        }.value
        return try await transcribeBufferedChunk(
            samples: loaded.samples,
            sampleRate: loaded.sampleRate
        ) ?? ""
    }

    private func startAudioCapture() throws {
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        activeCaptureUsesPreferredInputDevice = preferredInputDeviceID != nil
        applyPreferredInputDeviceIfNeeded(inputNode: inputNode)

        let format = inputNode.outputFormat(forBus: 0)
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxt-sherpa-\(UUID().uuidString).caf")
        let audioFile = try AVAudioFile(forWriting: audioURL, settings: format.settings)
        activeAudioURL = audioURL
        activeAudioFile = audioFile

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            do {
                try self.activeAudioFile?.write(from: buffer)
            } catch {
                Task { @MainActor [weak self] in
                    self?.pendingRuntimeFailureMessage = error.localizedDescription
                }
            }

            guard let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }
            let channelCount = max(1, Int(buffer.format.channelCount))
            var rms: Float = 0
            for index in 0..<frameLength {
                var sample: Float = 0
                for channel in 0..<channelCount {
                    sample += channelData[channel][index]
                }
                sample /= Float(channelCount)
                rms += sample * sample
            }
            rms = sqrt(rms / Float(frameLength))
            let normalized = min(rms * 20, 1.0)

            Task { @MainActor [weak self] in
                self?.audioLevel = normalized
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
        isFinalizingTranscription = false
        VoxtLog.asr(
            "Sherpa ONNX audio capture started. sampleRate=\(Int(format.sampleRate)), channels=\(format.channelCount), routing=\(activeCaptureUsesPreferredInputDevice ? "preferred" : "system-default")"
        )
    }

    private func runOfflineRecognition(fileURL: URL) {
        isFinalizingTranscription = true

        Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await self.transcribeAudioFile(fileURL)
                await MainActor.run {
                    self.finishTranscription(text)
                }
            } catch {
                await MainActor.run {
                    self.finishWithRuntimeFailure(error.localizedDescription)
                }
            }
        }
    }

    private func finishWithRuntimeFailure(_ message: String) {
        pendingRuntimeFailureMessage = message
        finishTranscription(transcribedText)
    }

    private func finishTranscription(_ text: String) {
        transcribedText = text
        isFinalizingTranscription = false
        onTranscriptionFinished?(text)
    }

    private func resolvedRecognitionConfiguration(for modelID: SherpaOnnxModelID) -> SherpaOnnxRecognitionConfiguration {
        let option = SherpaOnnxModelCatalog.option(for: modelID)
        let defaults = UserDefaults.standard
        let userLanguageCodes = UserMainLanguageOption.storedSelection(
            from: defaults.string(forKey: AppPreferenceKey.userMainLanguageCodes)
        )
        let hintSettings = ASRHintSettingsStore.resolvedSettings(
            for: .sherpaOnnx,
            rawValue: defaults.string(forKey: AppPreferenceKey.asrHintSettings)
        )
        let tuningSettings = SherpaOnnxLocalTuningSettingsStore.resolvedSettings(
            for: modelID,
            kind: option.kind,
            rawValue: defaults.string(forKey: AppPreferenceKey.sherpaOnnxLocalASRTuningSettings)
        )
        let dictionaryTerms = DictionaryEntryCollection.asrPromptTermsText(from: dictionaryEntryProvider?() ?? [])
        let hintPayload = ASRHintResolver.resolve(
            target: .sherpaOnnx,
            settings: hintSettings,
            userLanguageCodes: userLanguageCodes,
            dictionaryTerms: dictionaryTerms
        )
        let contextBias = ASRHintResolver.resolveTemplateVariables(
            in: tuningSettings.contextBias,
            userLanguageCodes: userLanguageCodes,
            dictionaryTerms: dictionaryTerms
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        let hotwords: [String]
        switch option.kind {
        case .fireRedASRCTC:
            hotwords = []
        case .funASRNano:
            hotwords = Self.mergedHotwords(
                hintPayload.contextualPhrases + contextBias.components(separatedBy: .newlines)
            )
        }

        return SherpaOnnxRecognitionConfiguration(
            numThreads: Int32(tuningSettings.numThreads),
            language: hintPayload.language,
            hotwords: hotwords,
            funASRMaxNewTokens: Int32(tuningSettings.funASRMaxNewTokens),
            funASRTopP: Float(tuningSettings.funASRTopP),
            funASRUseITN: tuningSettings.funASRUseITN
        )
    }

    private nonisolated static func mergedHotwords(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }
        return result
    }

    private nonisolated static func resampleMonoSamples(
        _ samples: [Float],
        sourceSampleRate: Double,
        targetSampleRate: Double
    ) -> [Float] {
        guard !samples.isEmpty else { return [] }
        guard sourceSampleRate > 0, targetSampleRate > 0 else { return samples }
        guard abs(sourceSampleRate - targetSampleRate) > 0.5 else { return samples }

        let ratio = sourceSampleRate / targetSampleRate
        let outputCount = max(1, Int(Double(samples.count) / ratio))
        var output = [Float]()
        output.reserveCapacity(outputCount)

        for outputIndex in 0..<outputCount {
            let sourcePosition = Double(outputIndex) * ratio
            let lowerIndex = min(Int(sourcePosition), samples.count - 1)
            let upperIndex = min(lowerIndex + 1, samples.count - 1)
            let fraction = Float(sourcePosition - Double(lowerIndex))
            let lower = samples[lowerIndex]
            let upper = samples[upperIndex]
            output.append(lower + (upper - lower) * fraction)
        }

        return output
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
            VoxtLog.asrWarning("Unable to switch sherpa-onnx input device. status=\(status)")
        }
    }

    private static func recognize(
        samples: [Float],
        sampleRate: Int32,
        modelID: SherpaOnnxModelID,
        modelDirectory: URL,
        recognitionConfiguration: SherpaOnnxRecognitionConfiguration
    ) async throws -> String {
        #if SHERPA_ONNX_AVAILABLE
        return try await Task.detached(priority: .userInitiated) {
            let option = SherpaOnnxModelCatalog.option(for: modelID)
            return try recognizeWithSherpa(
                samples: samples,
                sampleRate: sampleRate,
                option: option,
                modelDirectory: modelDirectory,
                recognitionConfiguration: recognitionConfiguration
            )
        }.value
        #else
        throw NSError(
            domain: "SherpaOnnxTranscriber",
            code: 2001,
            userInfo: [
                NSLocalizedDescriptionKey: "Sherpa ONNX runtime is not bundled in this build."
            ]
        )
        #endif
    }
}

#if SHERPA_ONNX_AVAILABLE
nonisolated private func withCStringPointer<R>(_ value: String, _ body: (UnsafePointer<CChar>) throws -> R) rethrows -> R {
    try value.withCString(body)
}

nonisolated private func recognizeWithSherpa(
    samples: [Float],
    sampleRate: Int32,
    option: SherpaOnnxModelOption,
    modelDirectory: URL,
    recognitionConfiguration: SherpaOnnxRecognitionConfiguration
) throws -> String {
    var config = SherpaOnnxOfflineRecognizerConfig()
    config.feat_config.sample_rate = sampleRate
    config.feat_config.feature_dim = 80
    config.model_config.num_threads = recognitionConfiguration.numThreads
    config.model_config.debug = 0

    let recognizer: OpaquePointer?
    recognizer = withCStringPointer("cpu") { provider in
        config.model_config.provider = provider
        switch option.kind {
        case .fireRedASRCTC:
            return withCStringPointer(modelDirectory.appendingPathComponent("model.int8.onnx").path) { modelPath in
                withCStringPointer(modelDirectory.appendingPathComponent("tokens.txt").path) { tokensPath in
                    config.model_config.fire_red_asr_ctc.model = modelPath
                    config.model_config.tokens = tokensPath
                    return SherpaOnnxCreateOfflineRecognizer(&config)
                }
            }
        case .funASRNano:
            let hotwordsText = recognitionConfiguration.hotwords.joined(separator: "\n")
            let language = recognitionConfiguration.language ?? ""
            let systemPrompt = AppPromptResourceStore.requiredText(for: .funASRNanoSystem)
            let userPrompt = AppPromptResourceStore.requiredText(for: .funASRNanoUser)
            return withCStringPointer(modelDirectory.appendingPathComponent("encoder_adaptor.int8.onnx").path) { adaptorPath in
                withCStringPointer(modelDirectory.appendingPathComponent("llm.int8.onnx").path) { llmPath in
                    withCStringPointer(modelDirectory.appendingPathComponent("embedding.int8.onnx").path) { embeddingPath in
                        withCStringPointer(modelDirectory.appendingPathComponent("Qwen3-0.6B").path) { tokenizerPath in
                            withCStringPointer(systemPrompt) { systemPromptPointer in
                                withCStringPointer(userPrompt) { userPromptPointer in
                                    withCStringPointer(language) { languagePointer in
                                        withCStringPointer(hotwordsText) { hotwordsPointer in
                                            config.model_config.funasr_nano.encoder_adaptor = adaptorPath
                                            config.model_config.funasr_nano.llm = llmPath
                                            config.model_config.funasr_nano.embedding = embeddingPath
                                            config.model_config.funasr_nano.tokenizer = tokenizerPath
                                            config.model_config.funasr_nano.system_prompt = systemPromptPointer
                                            config.model_config.funasr_nano.user_prompt = userPromptPointer
                                            if !language.isEmpty {
                                                config.model_config.funasr_nano.language = languagePointer
                                            }
                                            if !hotwordsText.isEmpty {
                                                config.model_config.funasr_nano.hotwords = hotwordsPointer
                                            }
                                            config.model_config.funasr_nano.max_new_tokens = recognitionConfiguration.funASRMaxNewTokens
                                            config.model_config.funasr_nano.temperature = 0.000001
                                            config.model_config.funasr_nano.top_p = recognitionConfiguration.funASRTopP
                                            config.model_config.funasr_nano.seed = 42
                                            config.model_config.funasr_nano.itn = recognitionConfiguration.funASRUseITN ? 1 : 0
                                            return SherpaOnnxCreateOfflineRecognizer(&config)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    guard let recognizer else {
        throw NSError(
            domain: "SherpaOnnxTranscriber",
            code: 2002,
            userInfo: [NSLocalizedDescriptionKey: "Failed to create sherpa-onnx recognizer."]
        )
    }
    defer { SherpaOnnxDestroyOfflineRecognizer(recognizer) }

    let chunks = sherpaRecognitionChunks(samples: samples, sampleRate: sampleRate, option: option)
    if chunks.count > 1 {
        let durationMilliseconds = Int((Double(samples.count) / Double(sampleRate)) * 1000)
        let chunkMilliseconds = Int((Double(chunks.first?.count ?? 0) / Double(sampleRate)) * 1000)
        VoxtLog.asr(
            "Sherpa ONNX FunASR chunking enabled. durationMs=\(durationMilliseconds), chunks=\(chunks.count), chunkMs=\(chunkMilliseconds)"
        )
    }

    var texts: [String] = []
    texts.reserveCapacity(chunks.count)
    for chunk in chunks {
        let text = try decodeSherpaChunk(samples: chunk, sampleRate: sampleRate, recognizer: recognizer)
        if !text.isEmpty {
            texts.append(text)
        }
    }
    return mergeSherpaRecognitionTexts(texts)
}

nonisolated private func decodeSherpaChunk(
    samples: [Float],
    sampleRate: Int32,
    recognizer: OpaquePointer
) throws -> String {
    guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else {
        throw NSError(
            domain: "SherpaOnnxTranscriber",
            code: 2003,
            userInfo: [NSLocalizedDescriptionKey: "Failed to create sherpa-onnx stream."]
        )
    }
    defer { SherpaOnnxDestroyOfflineStream(stream) }

    samples.withUnsafeBufferPointer { buffer in
        SherpaOnnxAcceptWaveformOffline(stream, sampleRate, buffer.baseAddress, Int32(buffer.count))
    }
    SherpaOnnxDecodeOfflineStream(recognizer, stream)
    guard let result = SherpaOnnxGetOfflineStreamResult(stream) else {
        return ""
    }
    defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }
    return String(cString: result.pointee.text)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

nonisolated private func sherpaRecognitionChunks(
    samples: [Float],
    sampleRate: Int32,
    option: SherpaOnnxModelOption
) -> [[Float]] {
    guard option.kind == .funASRNano, sampleRate > 0 else { return [samples] }
    let maxSamples = max(1, Int(Double(sampleRate) * 7.0))
    guard samples.count > maxSamples else { return [samples] }

    var chunks: [[Float]] = []
    chunks.reserveCapacity(Int(ceil(Double(samples.count) / Double(maxSamples))))
    var start = 0
    while start < samples.count {
        let end = min(start + maxSamples, samples.count)
        chunks.append(Array(samples[start..<end]))
        start = end
    }
    return chunks
}

nonisolated private func mergeSherpaRecognitionTexts(_ texts: [String]) -> String {
    var result = ""
    for text in texts {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        guard let previous = result.last, let next = trimmed.first else {
            result = trimmed
            continue
        }
        if shouldJoinSherpaTextWithoutSpace(previous: previous, next: next) {
            result += trimmed
        } else {
            result += " " + trimmed
        }
    }
    return result
}

nonisolated private func shouldJoinSherpaTextWithoutSpace(previous: Character, next: Character) -> Bool {
    if isSherpaWhitespace(previous) || isSherpaWhitespace(next) {
        return true
    }
    if isSherpaCJKOrPunctuation(previous) || isSherpaCJKOrPunctuation(next) {
        return true
    }
    return false
}

nonisolated private func isSherpaWhitespace(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
}

nonisolated private func isSherpaCJKOrPunctuation(_ character: Character) -> Bool {
    character.unicodeScalars.contains { scalar in
        switch scalar.value {
        case 0x3000...0x303F, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0xFF00...0xFFEF:
            return true
        default:
            return CharacterSet.punctuationCharacters.contains(scalar)
        }
    }
}
#endif
