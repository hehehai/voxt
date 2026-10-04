// SpeechTranscriber.swift
// Provides Speech Transcriber for transcription engines.

import Foundation
import Speech
import AVFoundation
import Combine
import CoreAudio

@MainActor
class SpeechTranscriber: ObservableObject, TranscriberProtocol {
    /// Speech framework requests accept appended audio from any thread.
    nonisolated private final class RecognitionAudioInput: @unchecked Sendable {
        let request: SFSpeechAudioBufferRecognitionRequest

        init(request: SFSpeechAudioBufferRecognitionRequest) {
            self.request = request
        }
    }

    nonisolated private final class AudioSampleStore: @unchecked Sendable {
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
    private var captureSession: MicrophoneCaptureSession?
    private let sampleStore = AudioSampleStore()
    private var preferredInputDeviceID: AudioDeviceID?
    /// Capture always delivers mono audio at this rate.
    private let inputSampleRate: Double = 16000
    private var completedAudioArchiveURL: URL?

    private var finalizeTimeoutTask: Task<Void, Never>?
    private var hasDeliveredFinalResult = false
    var sessionReportsPartialResultsOverride: Bool?

    var onTranscriptionFinished: ((String) -> Void)?
    private(set) var lastStartFailureMessage: String?

    init() {
        refreshSpeechRecognizer(localeIdentifier: nil)
    }

    func setPreferredInputDevice(_ deviceID: AudioDeviceID?) {
        preferredInputDeviceID = deviceID
    }

    func requestPermissions() async -> Bool {
        guard await RecordingPermissionRequest.speechRecognitionAccess() else { return false }
        return await RecordingPermissionRequest.microphoneAccess()
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
        Task { [weak self] in
            _ = await self?.startRecordingSession()
        }
    }

    /// Starts recognition and microphone capture. Returns whether recording started;
    /// `lastStartFailureMessage` explains a failure.
    @discardableResult
    func startRecordingSession() async -> Bool {
        guard !isRecording else { return true }
        lastStartFailureMessage = nil
        removeCompletedAudioArchiveIfNeeded()

        let settings = resolvedDictationSettings()
        refreshSpeechRecognizer(localeIdentifier: settings.localeIdentifier)

        guard let recognizer = speechRecognizer else {
            let message = AppLocalization.localizedString("Direct Dictation is unavailable for the current language.")
            lastStartFailureMessage = message
            VoxtLog.asrWarning("Speech transcriber start blocked: recognizer is unavailable for current locale.")
            return false
        }
        if settings.prefersOnDeviceRecognition && !recognizer.supportsOnDeviceRecognition {
            let message = AppLocalization.localizedString("Direct Dictation on-device recognition is unavailable for the selected language.")
            lastStartFailureMessage = message
            VoxtLog.asrWarning(
                "Speech transcriber start blocked: on-device recognition is unavailable. locale=\(recognizer.locale.identifier)"
            )
            return false
        }
        guard recognizer.isAvailable else {
            let message = AppLocalization.localizedString("Direct Dictation is temporarily unavailable. Try again in a moment.")
            lastStartFailureMessage = message
            VoxtLog.asrWarning("Speech transcriber start blocked: recognizer is not currently available.")
            return false
        }

        cleanupSessionState()
        sampleStore.clear()
        transcribedText = ""
        audioLevel = 0
        hasDeliveredFinalResult = false

        do {
            try await startSpeechRecognition(recognizer: recognizer, settings: settings)
            isRecording = true
            lastStartFailureMessage = nil
            return true
        } catch {
            lastStartFailureMessage = AppLocalization.localizedString("Direct Dictation failed to start recording.")
            if MicrophoneCaptureError.isAbort(error) {
                VoxtLog.asr("Speech transcriber start cancelled before the microphone was running.")
            } else {
                VoxtLog.asrError("Speech transcriber start recording failed: \(error.localizedDescription)")
            }
            stopAudioCapture()
            cleanupSessionState()
            return false
        }
    }

    func stopRecording() {
        guard isRecording else {
            // Abort a microphone start that is still in progress.
            stopAudioCapture()
            return
        }

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

    func shutdownForApplicationTermination() {
        stopAudioCapture()
        cleanupSessionState()
        removeCompletedAudioArchiveIfNeeded()
        audioLevel = 0
        isEnhancing = false
        isFinalizingTranscription = false
        onTranscriptionFinished = nil
    }

    /// Moves capture to the current preferred device. The recognition request keeps running
    /// because the delivered audio format does not change with the device.
    func restartCaptureForPreferredInputDevice() throws {
        guard isRecording else { return }
        captureSession?.switchDevice(to: preferredInputDeviceID)
    }

    private func cleanupSessionState() {
        finalizeTimeoutTask?.cancel()
        finalizeTimeoutTask = nil
        isRecording = false
        clearRecognitionPipeline(cancelTask: true)
        sampleStore.clear()
    }

    /// Stops capture after handing out already captured audio, then ends the request.
    private func stopAudioCapture() {
        captureSession?.stop()
        captureSession = nil
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
    ) async throws {
        clearRecognitionPipeline(cancelTask: true)
        captureSession?.stop()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = settings.reportsPartialResults
        request.taskHint = .dictation
        request.contextualStrings = settings.contextualPhrases
        request.requiresOnDeviceRecognition = settings.prefersOnDeviceRecognition
        if #available(macOS 13.0, *) {
            request.addsPunctuation = settings.addsPunctuation
        }
        recognitionRequest = request

        let capture = MicrophoneCaptureSession(context: "dictation")
        captureSession = capture
        let audioInput = RecognitionAudioInput(request: request)
        let sampleStore = self.sampleStore
        let deliverLevel: @MainActor @Sendable (Float) -> Void = { [weak self] level in
            self?.audioLevel = level
        }

        _ = try await capture.start(
            MicrophoneCaptureRequest(deviceID: preferredInputDeviceID, outputSampleRate: inputSampleRate),
            onBuffer: { buffer in
                audioInput.request.append(buffer)
                guard let samples = AudioLevelMeter.monoSamples(from: buffer), !samples.isEmpty else { return }
                sampleStore.append(samples)

                var sumOfSquares: Float = 0
                for sample in samples {
                    sumOfSquares += sample * sample
                }
                let normalized = min(sqrt(sumOfSquares / Float(samples.count)) * 20, 1.0)
                Task { @MainActor in
                    deliverLevel(normalized)
                }
            },
            onEvent: { _ in }
        )
        guard captureSession === capture else { throw CancellationError() }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    let allowsPartial = self.sessionReportsPartialResultsOverride ?? true
                    if allowsPartial || result.isFinal {
                        self.transcribedText = text
                    }
                    if result.isFinal {
                        self.finishRecognition(with: text)
                    }
                }
            }

            if let error {
                let nsError = error as NSError
                if nsError.domain != "kAFAssistantErrorDomain" || (nsError.code != 216 && nsError.code != 1110) {
                    VoxtLog.asrError("Speech recognition error: \(error)")
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

    private func resolvedDictationSettings() -> ResolvedDictationSettings {
        let defaults = UserDefaults.standard
        let settings = ASRHintSettingsStore.resolvedSettings(
            for: .dictation,
            rawValue: defaults.string(forKey: AppPreferenceKey.asrHintSettings)
        )
        let userLanguageCodes = UserMainLanguageOption.storedSelection(
            from: defaults.string(forKey: AppPreferenceKey.userMainLanguageCodes)
        )
        let resolved = ASRHintResolver.resolveDictationSettings(
            settings: settings,
            userLanguageCodes: userLanguageCodes
        )
        if let override = sessionReportsPartialResultsOverride {
            return ResolvedDictationSettings(
                localeIdentifier: resolved.localeIdentifier,
                contextualPhrases: resolved.contextualPhrases,
                prefersOnDeviceRecognition: resolved.prefersOnDeviceRecognition,
                addsPunctuation: resolved.addsPunctuation,
                reportsPartialResults: override
            )
        }
        return resolved
    }

    private func refreshSpeechRecognizer(localeIdentifier: String?) {
        let locale = localeIdentifier.map(Locale.init(identifier:)) ?? Locale.current
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        if speechRecognizer == nil {
            lastStartFailureMessage = AppLocalization.localizedString("Direct Dictation is unavailable for the current language.")
            VoxtLog.asrWarning("Speech recognizer initialization failed for locale=\(locale.identifier).")
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
            VoxtLog.asrWarning("Speech completed audio archive export failed: \(error.localizedDescription)")
        }
    }

    private func removeCompletedAudioArchiveIfNeeded() {
        guard let completedAudioArchiveURL else { return }
        try? FileManager.default.removeItem(at: completedAudioArchiveURL)
        self.completedAudioArchiveURL = nil
    }
}
