// LaptopLidState.swift
// Reads the laptop clamshell state that gates the built-in microphone.

import Foundation
import IOKit

nonisolated enum LaptopLidState: String, Sendable {
    case open
    case closed
    /// Desktops, or the registry value could not be read.
    case unavailable

    static func current() -> LaptopLidState {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != 0 else { return .unavailable }
        defer { IOObjectRelease(rootDomain) }

        guard let property = IORegistryEntryCreateCFProperty(
            rootDomain,
            "AppleClamshellState" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue(),
            let isClosed = property as? Bool
        else {
            return .unavailable
        }
        return isClosed ? .closed : .open
    }
}

/// Decides whether a Core Audio input device can actually deliver audio right now.
///
/// Mac laptops with Apple silicon or a T2 chip disconnect the internal microphone in
/// hardware while the lid is closed. Core Audio keeps publishing the device, but it only
/// produces digital silence, so it must not take part in microphone selection.
nonisolated enum MicrophoneAvailabilityPolicy {
    static func isInternalMicrophone(
        transport: AudioDeviceTransport,
        uid: String,
        inputDataSource: UInt32?
    ) -> Bool {
        guard transport == .builtIn else { return false }
        return uid == AudioDeviceInspector.appleSiliconBuiltInMicrophoneUID
            || inputDataSource == AudioDeviceInspector.internalMicrophoneDataSource
    }

    static func isAvailable(
        transport: AudioDeviceTransport,
        uid: String,
        inputDataSource: UInt32?,
        lidState: LaptopLidState
    ) -> Bool {
        guard lidState == .closed else { return true }
        return !isInternalMicrophone(transport: transport, uid: uid, inputDataSource: inputDataSource)
    }
}
