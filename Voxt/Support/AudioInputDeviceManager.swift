import Foundation
import CoreAudio

struct AudioInputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let name: String
}

enum AudioInputDeviceManager {
    static func availableInputDevices() -> [AudioInputDevice] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )
        guard sizeStatus == noErr, dataSize > 0 else {
            VoxtLog.warning("Failed to query audio input devices. status=\(sizeStatus), dataSize=\(dataSize)")
            return []
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(0), count: deviceCount)
        let listStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard listStatus == noErr else {
            VoxtLog.warning("Failed to load audio input device list. status=\(listStatus)")
            return []
        }

        let devices: [AudioInputDevice] = deviceIDs.compactMap { (id: AudioDeviceID) -> AudioInputDevice? in
            guard hasInputStream(deviceID: id) else { return nil }
            guard let name = deviceName(deviceID: id), !name.isEmpty else { return nil }
            return AudioInputDevice(id: id, name: name)
        }
        .sorted { (lhs: AudioInputDevice, rhs: AudioInputDevice) in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        VoxtLog.info("Audio input devices discovered: \(devices.count)", verbose: true)
        return devices
    }

    static func defaultInputDeviceID() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID(0)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        guard status == noErr, deviceID != 0 else {
            VoxtLog.warning("Failed to read default input device. status=\(status), deviceID=\(deviceID)")
            return nil
        }
        return deviceID
    }

    private static func hasInputStream(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }

    private static func deviceName(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var buffer = [CChar](repeating: 0, count: 256)
        var dataSize = UInt32(buffer.count * MemoryLayout<CChar>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &buffer)
        guard status == noErr else { return nil }
        return String(cString: buffer)
    }
}
