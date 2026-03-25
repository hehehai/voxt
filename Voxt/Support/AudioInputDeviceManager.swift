import Foundation
import CoreAudio

struct AudioInputDevice: Identifiable, Hashable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String

    var identifier: String { uid }
}

enum AudioInputDeviceManager {
    static func availableInputDevices() -> [AudioInputDevice] {
        let devices = snapshotAvailableInputDevices()
        VoxtLog.info("Audio input devices discovered: \(devices.count)", verbose: true)
        return devices
    }

    nonisolated static func snapshotAvailableInputDevices() -> [AudioInputDevice] {
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
        guard sizeStatus == noErr, dataSize > 0 else { return [] }

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
        guard listStatus == noErr else { return [] }

        let devices: [AudioInputDevice] = deviceIDs.compactMap { (id: AudioDeviceID) -> AudioInputDevice? in
            guard hasInputStream(deviceID: id) else { return nil }
            guard let uid = deviceUID(deviceID: id), !uid.isEmpty else { return nil }
            guard let name = deviceName(deviceID: id), !name.isEmpty else { return nil }
            return AudioInputDevice(id: id, uid: uid, name: name)
        }
        .sorted { (lhs: AudioInputDevice, rhs: AudioInputDevice) in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
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

    static func defaultInputDeviceUID(from devices: [AudioInputDevice]? = nil) -> String? {
        guard let defaultID = defaultInputDeviceID() else { return nil }
        if let devices, let device = devices.first(where: { $0.id == defaultID }) {
            return device.uid
        }
        return deviceUID(deviceID: defaultID)
    }

    static func resolvedInputDeviceID(
        from devices: [AudioInputDevice],
        preferredID: AudioDeviceID?
    ) -> AudioDeviceID? {
        resolvedInputDeviceID(
            from: devices,
            preferredID: preferredID,
            defaultDeviceID: defaultInputDeviceID()
        )
    }

    static func resolvedInputDeviceID(
        from devices: [AudioInputDevice],
        preferredID: AudioDeviceID?,
        defaultDeviceID: AudioDeviceID?
    ) -> AudioDeviceID? {
        if let preferredID,
           devices.contains(where: { $0.id == preferredID }) {
            return preferredID
        }

        if let defaultDeviceID,
           devices.contains(where: { $0.id == defaultDeviceID }) {
            return defaultDeviceID
        }

        return devices.first?.id
    }

    static func isAvailableInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        snapshotAvailableInputDevices().contains(where: { $0.id == deviceID })
    }

    static func makeDevicesObserver(onChange: @escaping @Sendable () -> Void) -> AudioInputDeviceObserver? {
        AudioInputDeviceObserver(onChange: onChange)
    }

    nonisolated static func selectorDescription(_ selector: AudioObjectPropertySelector) -> String {
        switch selector {
        case kAudioHardwarePropertyDevices:
            return "devices"
        case kAudioHardwarePropertyDefaultInputDevice:
            return "defaultInputDevice"
        default:
            return String(selector)
        }
    }

    nonisolated private static func hasInputStream(deviceID: AudioDeviceID) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }

    nonisolated private static func deviceName(deviceID: AudioDeviceID) -> String? {
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

    nonisolated private static func deviceUID(deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var unmanagedUID: CFString?
        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &unmanagedUID
        )
        guard status == noErr, let unmanagedUID else { return nil }
        return unmanagedUID as String
    }
}

final class AudioInputDeviceObserver {
    private let queue = DispatchQueue(label: "com.voxt.audio-input-devices")
    private let onChange: @Sendable () -> Void
    private let block: AudioObjectPropertyListenerBlock
    private var devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    private var isRegistered = false

    init?(onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        self.block = { numberAddresses, addresses in
            let selectorValues = UnsafeBufferPointer(start: addresses, count: Int(numberAddresses)).map {
                AudioInputDeviceManager.selectorDescription($0.mSelector)
            }
            let selectors = selectorValues.isEmpty ? "unknown" : selectorValues.joined(separator: ",")
            VoxtLog.info("Audio input device observer fired. selectors=\(selectors)")
            onChange()
        }

        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        let devicesStatus = AudioObjectAddPropertyListenerBlock(
            systemObjectID,
            &devicesAddress,
            queue,
            block
        )
        let defaultInputStatus = AudioObjectAddPropertyListenerBlock(
            systemObjectID,
            &defaultInputAddress,
            queue,
            block
        )

        guard devicesStatus == noErr, defaultInputStatus == noErr else {
            if devicesStatus == noErr {
                AudioObjectRemovePropertyListenerBlock(systemObjectID, &devicesAddress, queue, block)
            }
            if defaultInputStatus == noErr {
                AudioObjectRemovePropertyListenerBlock(systemObjectID, &defaultInputAddress, queue, block)
            }
            VoxtLog.warning(
                "Failed to register audio device observer. devicesStatus=\(devicesStatus), defaultInputStatus=\(defaultInputStatus)"
            )
            return nil
        }

        isRegistered = true
        VoxtLog.info("Audio input device observer registered.")
    }

    deinit {
        guard isRegistered else { return }
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        AudioObjectRemovePropertyListenerBlock(systemObjectID, &devicesAddress, queue, block)
        AudioObjectRemovePropertyListenerBlock(systemObjectID, &defaultInputAddress, queue, block)
        VoxtLog.info("Audio input device observer removed.", verbose: true)
    }
}
