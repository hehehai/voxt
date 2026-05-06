import Foundation
import Speech
import AVFoundation
import Combine
import AudioToolbox

@MainActor
class SpeechTranscriber: ObservableObject, TranscriberProtocol {
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
    @Published var isFinalizingTranscription = false

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let sampleStore = AudioSampleStore()
    private var preferredInputDeviceID: AudioDeviceID?
    private var inputSampleRate: Double = 16000
    private var completedAudioArchiveURL: URL?

    private var finalizeTimeoutTask: Task<Void, Never>?
    private var hasDeliveredFinalResult = false

    var onTranscriptionFinished: ((String) -> Void)?
    private(set) var lastStartFailureMessage: String?

    init() {
        refreshSpeechRecognizer(localeIdentifier: nil)
    }

    func setPreferredInputDevice(_ deviceID: AudioDeviceID?) {
        preferredInputDeviceID = deviceID
    }

    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { return false }

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
        lastStartFailureMessage = nil
        removeCompletedAudioArchiveIfNeeded()

        let settings = resolvedDictationSettings()
        refreshSpeechRecognizer(localeIdentifier: settings.localeIdentifier)

        guard let recognizer = speechRecognizer else {
            let message = String(localized: "Direct Dictation is unavailable for the current language.")
            lastStartFailureMessage = message
            VoxtLog.warning("Speech transcriber start blocked: recognizer is unavailable for current locale.")
            return
        }
        if settings.prefersOnDeviceRecognition && !recognizer.supportsOnDeviceRecognition {
            let message = String(localized: "Direct Dictation on-device recognition is unavailable for the selected language.")
            lastStartFailureMessage = message
            VoxtLog.warning(
                "Speech transcriber start blocked: on-device recognition is unavailable. locale=\(recognizer.locale.identifier)"
            )
            return
        }
        guard recognizer.isAvailable else {
            let message = String(localized: "Direct Dictation is temporarily unavailable. Try again in a moment.")
            lastStartFailureMessage = message
            VoxtLog.warning("Speech transcriber start blocked: recognizer is not currently available.")
            return
        }

        cleanupSessionState()
        sampleStore.clear()
        transcribedText = ""
        audioLevel = 0
        hasDeliveredFinalResult = false

        do {
            try startSpeechRecognition(recognizer: recognizer, settings: settings)
            isRecording = true
            lastStartFailureMessage = nil
        } catch {
            lastStartFailureMessage = String(localized: "Direct Dictation failed to start recording.")
            VoxtLog.error("Speech transcriber start recording failed: \(error)")
            cleanupSessionState()
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        stopAudioCapture()
        isRecording = false

        finalizeTimeoutTask?.cancel()
        finalizeTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            await MainActor.run {
                self?.forceFinalizeIfNeeded()
            }
        }
    }

    func restartCaptureForPreferredInputDevice() throws {
        guard isRecording else { return }
        let settings = resolvedDictationSettings()
        refreshSpeechRecognizer(localeIdentifier: settings.localeIdentifier)
        guard let recognizer = speechRecognizer else {
            throw NSError(
                domain: "Voxt.SpeechTranscriber",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Speech recognizer is unavailable."]
            )
        }
        if settings.prefersOnDeviceRecognition && !recognizer.supportsOnDeviceRecognition {
            throw NSError(
                domain: "Voxt.SpeechTranscriber",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "On-device recognition is unavailable for the selected language."]
            )
        }
        stopAudioCapture()
        try startSpeechRecognition(recognizer: recognizer, settings: settings)
    }

    private func cleanupSessionState() {
        finalizeTimeoutTask?.cancel()
        finalizeTimeoutTask = nil
        isRecording = false
        clearRecognitionPipeline(cancelTask: true)
        sampleStore.clear()
    }

    private func stopAudioCapture() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
    }

    private func forceFinalizeIfNeeded() {
        guard !hasDeliveredFinalResult else { return }
        finishRecognition(with: transcribedText)
    }

    private func finishRecognition(with text: String) {
        guard !hasDeliveredFinalResult else { return }
        hasDeliveredFinalResult = true

        finalizeTimeoutTask?.cancel()
        finalizeTimeoutTask = nil
        clearRecognitionPipeline(cancelTask: true)
        stageCompletedAudioArchive()

        onTranscriptionFinished?(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func startSpeechRecognition(
        recognizer: SFSpeechRecognizer,
        settings: ResolvedDictationSettings
    ) throws {
        clearRecognitionPipeline(cancelTask: true)

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = settings.reportsPartialResults
        request.taskHint = .dictation
        request.contextualStrings = settings.contextualPhrases
        request.requiresOnDeviceRecognition = settings.prefersOnDeviceRecognition
        if #available(macOS 13.0, *) {
            request.addsPunctuation = settings.addsPunctuation
        }
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        applyPreferredInputDeviceIfNeeded(inputNode: inputNode)
        inputSampleRate = inputNode.outputFormat(forBus: 0).sampleRate
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let self else { return }
            self.recognitionRequest?.append(buffer)

            if let samples = AudioLevelMeter.monoSamples(from: buffer), !samples.isEmpty {
                self.sampleStore.append(samples)
            }

            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)
            if frameLength == 0 { return }

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

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.transcribedText = text
                    if result.isFinal {
                        self.finishRecognition(with: text)
                    }
                }
            }

            if let error {
                let nsError = error as NSError
                if nsError.domain != "kAFAssistantErrorDomain" || (nsError.code != 216 && nsError.code != 1110) {
                    VoxtLog.error("Speech recognition error: \(error)")
                }

                Task { @MainActor in
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                        self.finishRecognition(with: "")
                        return
                    }

                    self.finishRecognition(with: self.transcribedText)
                }
            }
        }
    }

    private func clearRecognitionPipeline(cancelTask: Bool) {
        if cancelTask {
            recognitionTask?.cancel()
        }
        recognitionTask = nil
        recognitionRequest = nil
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

    private func resolvedDictationSettings() -> ResolvedDictationSettings {
        let defaults = UserDefaults.standard
        let settings = ASRHintSettingsStore.resolvedSettings(
            for: .dictation,
            rawValue: defaults.string(forKey: AppPreferenceKey.asrHintSettings)
        )
        let userLanguageCodes = UserMainLanguageOption.storedSelection(
            from: defaults.string(forKey: AppPreferenceKey.userMainLanguageCodes)
        )
        return ASRHintResolver.resolveDictationSettings(
            settings: settings,
            userLanguageCodes: userLanguageCodes
        )
    }

    private func refreshSpeechRecognizer(localeIdentifier: String?) {
        let locale = localeIdentifier.map(Locale.init(identifier:)) ?? Locale.current
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        if speechRecognizer == nil {
            lastStartFailureMessage = String(localized: "Direct Dictation is unavailable for the current language.")
            VoxtLog.warning("Speech recognizer initialization failed for locale=\(locale.identifier).")
        }
    }

    private func stageCompletedAudioArchive() {
        removeCompletedAudioArchiveIfNeeded()
        let samples = sampleStore.snapshot()
        guard !samples.isEmpty else { return }
        let tempURL = HistoryAudioArchiveSupport.temporaryArchiveURL(prefix: "voxt-speech-history")
        do {
            if try HistoryAudioArchiveSupport.exportWAV(samples: samples, sampleRate: inputSampleRate, to: tempURL) {
                completedAudioArchiveURL = tempURL
            }
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            VoxtLog.warning("Speech completed audio archive export failed: \(error.localizedDescription)")
        }
    }

    private func removeCompletedAudioArchiveIfNeeded() {
        guard let completedAudioArchiveURL else { return }
        try? FileManager.default.removeItem(at: completedAudioArchiveURL)
        self.completedAudioArchiveURL = nil
    }
}
