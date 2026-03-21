import Foundation
import AVFoundation
import CoreAudio

final class MeetingMicrophoneCapture: @unchecked Sendable {
    enum CaptureError: LocalizedError {
        case inputUnavailable
        case engineStartFailed(Error)

        var errorDescription: String? {
            switch self {
            case .inputUnavailable:
                return "Microphone input is unavailable."
            case .engineStartFailed(let error):
                return "Microphone capture failed to start: \(error.localizedDescription)"
            }
        }
    }

    private var audioEngine: AVAudioEngine?
    private var hasTapInstalled = false
    private var preferredInputDeviceID: AudioDeviceID?

    deinit {
        stop()
    }

    func setPreferredInputDevice(_ deviceID: AudioDeviceID?) {
        preferredInputDeviceID = deviceID
    }

    func start(onBuffer: @escaping (AVAudioPCMBuffer, Float) -> Void) throws {
        stop()
        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine

        let inputNode = audioEngine.inputNode
        applyPreferredInputDeviceIfNeeded(inputNode: inputNode)
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw CaptureError.inputUnavailable
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            onBuffer(buffer, Self.normalizedRMS(from: buffer))
        }
        hasTapInstalled = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw CaptureError.engineStartFailed(error)
        }

        VoxtLog.info(
            "Meeting microphone capture started. sampleRate=\(Int(format.sampleRate)), channels=\(format.channelCount), deviceID=\(preferredInputDeviceID.map(String.init(describing:)) ?? "default")",
            verbose: true
        )
    }

    func stop() {
        guard let audioEngine = self.audioEngine else { return }
        if hasTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasTapInstalled = false
        }
        audioEngine.pause()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.reset()
        self.audioEngine = nil
        VoxtLog.info("Meeting microphone capture stopped.", verbose: true)
    }

    private func applyPreferredInputDeviceIfNeeded(inputNode: AVAudioInputNode) {
        guard let preferredInputDeviceID,
              preferredInputDeviceID != AudioDeviceID(kAudioObjectUnknown),
              AudioInputDeviceManager.isAvailableInputDevice(preferredInputDeviceID),
              let audioUnit = inputNode.audioUnit
        else {
            return
        }

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
            VoxtLog.warning("Meeting microphone capture could not switch input device. status=\(status), deviceID=\(preferredInputDeviceID)")
        }
    }

    private static func normalizedRMS(from buffer: AVAudioPCMBuffer) -> Float {
        AudioLevelMeter.normalizedLevel(from: buffer)
    }
}
