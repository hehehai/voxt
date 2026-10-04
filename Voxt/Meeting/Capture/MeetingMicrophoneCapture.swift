// MeetingMicrophoneCapture.swift
// Provides Meeting Microphone Capture for meeting capture.

import Foundation
import AVFoundation
import CoreAudio

/// Meeting and onboarding microphone input on top of `MicrophoneCaptureSession`.
///
/// `start` returns immediately; the device starts on the capture queue. Buffers arrive on
/// the capture delivery queue as mono Float32 at `outputSampleRate`. A start that fails
/// (not one that was stopped) is reported once through `onFailure` on the main actor.
final class MeetingMicrophoneCapture: @unchecked Sendable {
    /// Keeps the meeting archive at the quality previously captured from typical microphones.
    static let outputSampleRate: Double = 48000

    /// The handlers are created on the main actor but run on the capture delivery queue,
    /// as they always did with the previous audio-engine tap.
    nonisolated private final class Handlers: @unchecked Sendable {
        let onBuffer: (AVAudioPCMBuffer, Float) -> Void

        init(onBuffer: @escaping (AVAudioPCMBuffer, Float) -> Void) {
            self.onBuffer = onBuffer
        }
    }

    private var captureSession: MicrophoneCaptureSession?
    private var startTask: Task<Void, Never>?
    private var preferredInputDeviceID: AudioDeviceID?

    deinit {
        startTask?.cancel()
        captureSession?.stop()
    }

    func setPreferredInputDevice(_ deviceID: AudioDeviceID?) {
        preferredInputDeviceID = deviceID
    }

    func start(
        onBuffer: @escaping (AVAudioPCMBuffer, Float) -> Void,
        onFailure: (@MainActor (Error) -> Void)? = nil
    ) {
        stop()
        let capture = MicrophoneCaptureSession(context: "meeting")
        captureSession = capture
        let handlers = Handlers(onBuffer: onBuffer)
        let request = MicrophoneCaptureRequest(
            deviceID: preferredInputDeviceID,
            outputSampleRate: Self.outputSampleRate
        )

        startTask = Task { @MainActor [weak self] in
            do {
                _ = try await capture.start(
                    request,
                    onBuffer: { buffer in
                        handlers.onBuffer(buffer, AudioLevelMeter.normalizedLevel(from: buffer))
                    },
                    onEvent: { _ in }
                )
            } catch {
                guard !MicrophoneCaptureError.isAbort(error),
                      let self,
                      self.captureSession === capture
                else { return }
                VoxtLog.meetingWarning("Meeting microphone capture failed to start: \(error.localizedDescription)")
                self.stop()
                onFailure?(error)
            }
        }
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        captureSession?.stop()
        captureSession = nil
    }
}
