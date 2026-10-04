// AudioDeviceInspector.swift
// Reads Core Audio device properties used for capture routing and diagnostics.

import Foundation
import CoreAudio

nonisolated enum AudioDeviceTransport: Equatable, Sendable {
    case builtIn
    case bluetooth
    case bluetoothLE
    case usb
    case virtual
    case aggregate
    case continuityCapture
    case displayPort
    case hdmi
    case airPlay
    case thunderbolt
    case pci
    case other(UInt32)
    case unknown

    init(rawValue: UInt32?) {
        guard let rawValue else {
            self = .unknown
            return
        }
        switch rawValue {
        case kAudioDeviceTransportTypeBuiltIn:
            self = .builtIn
        case kAudioDeviceTransportTypeBluetooth:
            self = .bluetooth
        case kAudioDeviceTransportTypeBluetoothLE:
            self = .bluetoothLE
        case kAudioDeviceTransportTypeUSB:
            self = .usb
        case kAudioDeviceTransportTypeVirtual:
            self = .virtual
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate:
            self = .aggregate
        case kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless:
            self = .continuityCapture
        case kAudioDeviceTransportTypeDisplayPort:
            self = .displayPort
        case kAudioDeviceTransportTypeHDMI:
            self = .hdmi
        case kAudioDeviceTransportTypeAirPlay:
            self = .airPlay
        case kAudioDeviceTransportTypeThunderbolt:
            self = .thunderbolt
        case kAudioDeviceTransportTypePCI:
            self = .pci
        default:
            self = .other(rawValue)
        }
    }

    var isBluetooth: Bool {
        self == .bluetooth || self == .bluetoothLE
    }

    var label: String {
        switch self {
        case .builtIn: return "builtIn"
        case .bluetooth: return "bluetooth"
        case .bluetoothLE: return "bluetoothLE"
        case .usb: return "usb"
        case .virtual: return "virtual"
        case .aggregate: return "aggregate"
        case .continuityCapture: return "continuity"
        case .displayPort: return "displayPort"
        case .hdmi: return "hdmi"
        case .airPlay: return "airPlay"
        case .thunderbolt: return "thunderbolt"
        case .pci: return "pci"
        case .other(let rawValue): return AudioDeviceInspector.fourCharacterCode(rawValue)
        case .unknown: return "unknown"
        }
    }
}

/// Point-in-time description of one Core Audio device. Values are read once and are only
/// meant for routing decisions made immediately and for diagnostics.
nonisolated struct AudioDeviceSnapshot: Equatable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transport: AudioDeviceTransport
    let inputChannels: Int
    let outputChannels: Int
    let nominalSampleRate: Double?
    let inputDataSource: UInt32?
    let isAlive: Bool

    var isInputOnly: Bool {
        inputChannels > 0 && outputChannels == 0
    }

    var diagnosticDescription: String {
        let rate = nominalSampleRate.map { String(Int($0.rounded())) } ?? "unknown"
        return "\(name){uid=\(uid),id=\(id),transport=\(transport.label),in=\(inputChannels),out=\(outputChannels),rate=\(rate),alive=\(isAlive)}"
    }
}

nonisolated enum AudioDeviceInspector {
    /// `kIOAudioInputPortSubTypeInternalMicrophone`, reported as the data source of a
    /// laptop's built-in microphone.
    static let internalMicrophoneDataSource: UInt32 = 0x696D_6963 // 'imic'
    static let appleSiliconBuiltInMicrophoneUID = "BuiltInMicrophoneDevice"

    static func defaultInputDeviceID() -> AudioDeviceID? {
        defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    static func defaultOutputDeviceID() -> AudioDeviceID? {
        defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    static func snapshot(of deviceID: AudioDeviceID) -> AudioDeviceSnapshot {
        AudioDeviceSnapshot(
            id: deviceID,
            uid: uid(of: deviceID) ?? "unknown",
            name: name(of: deviceID) ?? "unknown",
            transport: transport(of: deviceID),
            inputChannels: channelCount(of: deviceID, scope: kAudioObjectPropertyScopeInput),
            outputChannels: channelCount(of: deviceID, scope: kAudioObjectPropertyScopeOutput),
            nominalSampleRate: nominalSampleRate(of: deviceID),
            inputDataSource: uint32Property(
                deviceID,
                selector: kAudioDevicePropertyDataSource,
                scope: kAudioObjectPropertyScopeInput
            ),
            isAlive: isAlive(deviceID)
        )
    }

    static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        var deviceIDs = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &deviceIDs) == noErr else {
            return []
        }
        return deviceIDs
    }

    /// Every input and output device as seen by Core Audio, including devices Voxt hides
    /// from microphone selection.
    static func describeAllDevices() -> String {
        let descriptions = allDeviceIDs().map { snapshot(of: $0).diagnosticDescription }
        return descriptions.isEmpty ? "[]" : "[" + descriptions.joined(separator: ", ") + "]"
    }

    static func describeDefaultDevices() -> String {
        let input = defaultInputDeviceID().map { snapshot(of: $0).diagnosticDescription } ?? "none"
        let output = defaultOutputDeviceID().map { snapshot(of: $0).diagnosticDescription } ?? "none"
        return "defaultInput=\(input), defaultOutput=\(output)"
    }

    static func transport(of deviceID: AudioDeviceID) -> AudioDeviceTransport {
        AudioDeviceTransport(rawValue: uint32Property(deviceID, selector: kAudioDevicePropertyTransportType))
    }

    static func isUsableInputDevice(_ deviceID: AudioDeviceID) -> Bool {
        guard deviceID != AudioDeviceID(kAudioObjectUnknown) else { return false }
        return isAlive(deviceID) && channelCount(of: deviceID, scope: kAudioObjectPropertyScopeInput) > 0
    }

    static func isAlive(_ deviceID: AudioDeviceID) -> Bool {
        // Devices that do not publish the property are treated as alive, matching HAL defaults.
        (uint32Property(deviceID, selector: kAudioDevicePropertyDeviceIsAlive) ?? 1) != 0
    }

    static func name(of deviceID: AudioDeviceID) -> String? {
        stringProperty(deviceID, selector: kAudioObjectPropertyName)
    }

    static func uid(of deviceID: AudioDeviceID) -> String? {
        stringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID)
    }

    static func nominalSampleRate(of deviceID: AudioDeviceID) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value = Float64(0)
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr,
              value.isFinite,
              value > 0
        else {
            return nil
        }
        return value
    }

    static func bufferFrameSize(of deviceID: AudioDeviceID) -> UInt32? {
        uint32Property(deviceID, selector: kAudioDevicePropertyBufferFrameSize)
    }

    static func channelCount(of deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioBufferList>.size)
        else {
            return 0
        }

        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, storage) == noErr else {
            return 0
        }

        let bufferList = UnsafeMutableAudioBufferListPointer(
            storage.assumingMemoryBound(to: AudioBufferList.self)
        )
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func fourCharacterCode(_ value: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xFF) }
        guard bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) else { return String(value) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func defaultDeviceID(selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        guard let value = uint32Property(AudioObjectID(kAudioObjectSystemObject), selector: selector),
              value != kAudioObjectUnknown
        else {
            return nil
        }
        return AudioDeviceID(value)
    }

    private static func uint32Property(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(objectID, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return value
    }

    private static func stringProperty(
        _ objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        let string = value.takeRetainedValue() as String
        return string.isEmpty ? nil : string
    }
}
