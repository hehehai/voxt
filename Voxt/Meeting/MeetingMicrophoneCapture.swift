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
    private var hasLoggedFirstCallback = false

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
        hasLoggedFirstCallback = false

        let inputNode = audioEngine.inputNode
        applyPreferredInputDeviceIfNeeded(inputNode: inputNode)
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw CaptureError.inputUnavailable
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let copiedBuffer = Self.copyPCMBuffer(buffer) else { return }
            let level = Self.normalizedRMS(from: copiedBuffer)
            if self?.hasLoggedFirstCallback == false {
                self?.hasLoggedFirstCallback = true
                VoxtLog.info(
                    "Meeting microphone callback received. sampleRate=\(Int(copiedBuffer.format.sampleRate)), channels=\(copiedBuffer.format.channelCount), frames=\(copiedBuffer.frameLength)",
                    verbose: true
                )
            }
            onBuffer(copiedBuffer, level)
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
        hasLoggedFirstCallback = false
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

    private static func copyPCMBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            return nil
        }
        copy.frameLength = buffer.frameLength

        let sourceBuffers = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destinationBuffers = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard sourceBuffers.count == destinationBuffers.count else { return nil }

        for index in 0..<sourceBuffers.count {
            let source = sourceBuffers[index]
            let destination = destinationBuffers[index]
            let copySize = min(Int(source.mDataByteSize), Int(destination.mDataByteSize))
            guard copySize > 0,
                  let sourceData = source.mData,
                  let destinationData = destination.mData
            else {
                continue
            }
            memcpy(destinationData, sourceData, copySize)
            destinationBuffers[index].mDataByteSize = UInt32(copySize)
        }
        return copy
    }
}
