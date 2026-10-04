import Foundation
import AVFoundation
import CoreAudio

extension RemoteASRTranscriber {
    /// Starts the microphone for the active realtime provider or file recording and returns
    /// immediately; the device starts on the capture queue, never on the main thread.
    /// Samples are kept for the history archive and file upload. When `deliver` is set, each
    /// chunk is passed to it on the main actor as 16 kHz mono PCM16 while this recording
    /// generation is current.
    func startMicrophoneCapture(
        context: String,
        deliver: (@MainActor @Sendable (Data) -> Void)? = nil
    ) {
        didRetryMicrophoneWithSystemDefault = false
        startMicrophoneCapture(context: context, deviceID: preferredInputDeviceID, deliver: deliver)
    }

    private func startMicrophoneCapture(
        context: String,
        deviceID: AudioDeviceID?,
        deliver: (@MainActor @Sendable (Data) -> Void)?
    ) {
        stopStreamingAudioCapture()
        let capture = MicrophoneCaptureSession(context: "remote-\(context)")
        microphoneCaptureSession = capture
        streamingInputSampleRate = HistoryAudioArchiveSupport.targetSampleRate
        isRecording = true

        let generationID = recordingGenerationID
        let sampleStore = self.sampleStore
        let handleChunk: @MainActor @Sendable (Data) -> Void = { [weak self] pcmData in
            guard let self, self.isCurrentGeneration(generationID), self.isRecording else { return }
            self.audioLevel = self.audioLevelFromPCM16(pcmData)
            deliver?(pcmData)
        }
        let request = MicrophoneCaptureRequest(
            deviceID: deviceID,
            outputSampleRate: HistoryAudioArchiveSupport.targetSampleRate
        )

        microphoneCaptureStartTask = Task { @MainActor [weak self] in
            do {
                _ = try await capture.start(
                    request,
                    onBuffer: { buffer in
                        guard let samples = AudioLevelMeter.monoSamples(from: buffer), !samples.isEmpty else { return }
                        sampleStore.append(samples)
                        guard let pcmData = RemoteASRTranscriber.makePCM16MonoData(
                            from: samples,
                            inputSampleRate: buffer.format.sampleRate
                        ) else { return }
                        Task { @MainActor in
                            handleChunk(pcmData)
                        }
                    },
                    onEvent: { _ in }
                )
            } catch {
                guard !MicrophoneCaptureError.isAbort(error),
                      let self,
                      self.microphoneCaptureSession === capture
                else { return }
                self.handleMicrophoneCaptureStartFailure(
                    error,
                    context: context,
                    deviceID: deviceID,
                    deliver: deliver
                )
            }
        }
    }

    /// Stops the microphone after already captured audio has been handed out.
    func stopStreamingAudioCapture() {
        microphoneCaptureStartTask?.cancel()
        microphoneCaptureStartTask = nil
        microphoneCaptureSession?.stop()
        microphoneCaptureSession = nil
        audioLevel = 0
    }

    /// A preferred microphone that cannot start is retried once with the system default
    /// input; any other failure is reported to the session.
    private func handleMicrophoneCaptureStartFailure(
        _ error: Error,
        context: String,
        deviceID: AudioDeviceID?,
        deliver: (@MainActor @Sendable (Data) -> Void)?
    ) {
        let generationID = recordingGenerationID
        guard deviceID != nil, !didRetryMicrophoneWithSystemDefault else {
            VoxtLog.asrError("Remote ASR microphone failed to start. context=\(context), error=\(error.localizedDescription)")
            stopStreamingAudioCapture()
            notifyRuntimeFailure(error, generationID: generationID)
            return
        }
        didRetryMicrophoneWithSystemDefault = true
        VoxtLog.asrWarning(
            "Remote ASR microphone retrying with the system default input. context=\(context), error=\(error.localizedDescription)"
        )
        startMicrophoneCapture(context: context, deviceID: nil, deliver: deliver)
    }

    func audioLevelFromPCM16(_ data: Data) -> Float {
        guard data.count >= 2 else { return 0 }
        var sum: Float = 0
        var count: Float = 0
        data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for sample in samples {
                let normalized = Float(sample) / Float(Int16.max)
                sum += normalized * normalized
                count += 1
            }
        }
        guard count > 0 else { return 0 }
        let rms = sqrt(sum / count)
        return min(max(rms * 2.4, 0), 1)
    }

    nonisolated static func makePCM16MonoData(from samples: [Float], inputSampleRate: Double) -> Data? {
        guard !samples.isEmpty, inputSampleRate > 0 else { return nil }
        let targetRate = 16000.0
        let ratio = targetRate / inputSampleRate
        let outputCount = max(Int(Double(samples.count) * ratio), 1)
        var data = Data(count: outputCount * MemoryLayout<Int16>.size)
        data.withUnsafeMutableBytes { rawBuffer in
            let out = rawBuffer.bindMemory(to: Int16.self)
            for index in 0..<outputCount {
                let sourcePosition = Double(index) / ratio
                let sourceIndex = min(Int(sourcePosition.rounded(.down)), samples.count - 1)
                let clamped = max(-1.0, min(1.0, samples[sourceIndex]))
                out[index] = Int16(clamped * Float(Int16.max))
            }
        }
        return data
    }
}
