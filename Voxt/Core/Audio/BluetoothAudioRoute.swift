// BluetoothAudioRoute.swift
// Detects when opening a microphone interrupts playback on the same Bluetooth headset.

import Foundation
import CoreAudio

/// Opening a Bluetooth headset's microphone switches it from its media profile to its call
/// profile. Audio already playing on that headset (for example the start cue) is cut off
/// and continues at call quality, so callers sequence playback before capture there.
nonisolated enum BluetoothAudioRoute {
    /// Bluetooth headsets publish separate input and output devices whose UIDs share the
    /// device address, e.g. `AA-BB-CC-DD-EE-FF:input` and `AA-BB-CC-DD-EE-FF:output`.
    static func deviceAddress(fromUID uid: String) -> String? {
        guard let separator = uid.lastIndex(of: ":") else { return nil }
        let address = uid[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        return address.isEmpty ? nil : address
    }

    static func sharesHeadset(
        inputID: AudioDeviceID,
        inputUID: String,
        inputTransport: AudioDeviceTransport,
        outputID: AudioDeviceID,
        outputUID: String,
        outputTransport: AudioDeviceTransport
    ) -> Bool {
        guard inputTransport.isBluetooth, outputTransport.isBluetooth else { return false }
        if inputID == outputID { return true }
        guard let inputAddress = deviceAddress(fromUID: inputUID),
              let outputAddress = deviceAddress(fromUID: outputUID)
        else {
            return false
        }
        return inputAddress == outputAddress
    }

    /// Whether capturing from `inputDeviceID` (or the default input) interrupts the current
    /// default output.
    static func openingInputInterruptsOutput(inputDeviceID: AudioDeviceID?) -> Bool {
        guard let inputID = inputDeviceID ?? AudioDeviceInspector.defaultInputDeviceID(),
              let outputID = AudioDeviceInspector.defaultOutputDeviceID()
        else {
            return false
        }
        let inputTransport = AudioDeviceInspector.transport(of: inputID)
        let outputTransport = AudioDeviceInspector.transport(of: outputID)
        guard inputTransport.isBluetooth, outputTransport.isBluetooth else { return false }
        return sharesHeadset(
            inputID: inputID,
            inputUID: AudioDeviceInspector.uid(of: inputID) ?? "",
            inputTransport: inputTransport,
            outputID: outputID,
            outputUID: AudioDeviceInspector.uid(of: outputID) ?? "",
            outputTransport: outputTransport
        )
    }
}
