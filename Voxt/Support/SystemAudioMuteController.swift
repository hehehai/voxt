import Foundation
import CoreAudio

@MainActor
final class SystemAudioMuteController {
    private enum MuteStrategy {
        case bundleIDBased(String)
        case processObjectBased(AudioObjectID)
        case unavailable
    }

    private struct ProcessTapSession {
        let tapID: AudioObjectID
        let aggregateDeviceID: AudioObjectID
        let ioProcID: AudioDeviceIOProcID
    }

    private var processTapSession: ProcessTapSession?

    @discardableResult
    func muteSystemAudioIfNeeded() -> Bool {
        if processTapSession != nil {
            return true
        }
        guard SystemAudioCapturePermission.authorizationStatus() == .authorized else {
            return false
        }

        return activateProcessTapMuteIfPossible()
    }

    func restoreSystemAudioIfNeeded() {
        if let session = processTapSession {
            AudioDeviceStop(session.aggregateDeviceID, session.ioProcID)
            AudioDeviceDestroyIOProcID(session.aggregateDeviceID, session.ioProcID)
            AudioHardwareDestroyAggregateDevice(session.aggregateDeviceID)
            AudioHardwareDestroyProcessTap(session.tapID)
            processTapSession = nil
        }
    }

    private func activateProcessTapMuteIfPossible() -> Bool {
        guard let outputDeviceID = defaultOutputDeviceID(),
              let outputUID = deviceUID(for: outputDeviceID)
        else {
            VoxtLog.warning("System audio mute unavailable: failed to resolve default output device.")
            return false
        }

        switch resolvedMuteStrategy() {
        case .bundleIDBased(let bundleID):
            VoxtLog.info("System audio mute strategy=bundleIDBased", verbose: true)
            return activateBundleIDProcessTapMute(bundleID: bundleID, outputUID: outputUID)
        case .processObjectBased(let processObjectID):
            VoxtLog.info("System audio mute strategy=processObjectBased", verbose: true)
            return activateProcessObjectTapMute(processObjectID: processObjectID, outputUID: outputUID)
        case .unavailable:
            VoxtLog.warning("System audio mute unavailable: failed to resolve mute strategy.")
            return false
        }
    }

    private func resolvedMuteStrategy() -> MuteStrategy {
        if #available(macOS 26.0, *) {
            if let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty {
                return .bundleIDBased(bundleID)
            }
        }

        if let processObjectID = currentProcessObjectID() {
            return .processObjectBased(processObjectID)
        }

        return .unavailable
    }

    private func activateBundleIDProcessTapMute(bundleID: String, outputUID: String) -> Bool {
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        tapDescription.uuid = UUID()
        tapDescription.name = "Voxt System Audio Mute"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .muted

        if #available(macOS 26.0, *) {
            tapDescription.isProcessRestoreEnabled = true
            tapDescription.bundleIDs = [bundleID]
        }

        return startProcessTapSession(tapDescription: tapDescription, outputUID: outputUID)
    }

    private func activateProcessObjectTapMute(processObjectID: AudioObjectID, outputUID: String) -> Bool {
        let tapDescription = CATapDescription(
            stereoGlobalTapButExcludeProcesses: [processObjectID]
        )
        tapDescription.uuid = UUID()
        tapDescription.name = "Voxt System Audio Mute"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = CATapMuteBehavior.muted

        return startProcessTapSession(tapDescription: tapDescription, outputUID: outputUID)
    }

    private func startProcessTapSession(tapDescription: CATapDescription, outputUID: String) -> Bool {

        var tapID = AudioObjectID(kAudioObjectUnknown)
        let tapCreateStatus = AudioHardwareCreateProcessTap(tapDescription, &tapID)
        guard tapCreateStatus == noErr, tapID != AudioObjectID(kAudioObjectUnknown) else {
            VoxtLog.warning("System audio mute tap creation failed. status=\(tapCreateStatus)")
            return false
        }

        let aggregateUID = "voxt-process-tap-\(tapDescription.uuid.uuidString)"
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "VoxtProcessTap",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [
                    kAudioSubDeviceUIDKey: outputUID
                ]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString
                ]
            ]
        ]

        var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
        let aggregateStatus = AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregateDeviceID)
        guard aggregateStatus == noErr, aggregateDeviceID != AudioObjectID(kAudioObjectUnknown) else {
            AudioHardwareDestroyProcessTap(tapID)
            VoxtLog.warning("System audio mute aggregate device creation failed. status=\(aggregateStatus)")
            return false
        }

        var ioProcID: AudioDeviceIOProcID?
        let ioProcStatus = AudioDeviceCreateIOProcIDWithBlock(
            &ioProcID,
            aggregateDeviceID,
            DispatchQueue.global(qos: .userInitiated)
        ) { _, _, _, _, _ in
            // The tap remains active while this no-op IOProc is running.
        }

        guard ioProcStatus == noErr, let ioProcID else {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            AudioHardwareDestroyProcessTap(tapID)
            VoxtLog.warning("System audio mute IOProc creation failed. status=\(ioProcStatus)")
            return false
        }

        let startStatus = AudioDeviceStart(aggregateDeviceID, ioProcID)
        guard startStatus == noErr else {
            AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            AudioHardwareDestroyProcessTap(tapID)
            VoxtLog.warning("System audio mute start failed. status=\(startStatus)")
            return false
        }

        processTapSession = ProcessTapSession(
            tapID: tapID,
            aggregateDeviceID: aggregateDeviceID,
            ioProcID: ioProcID
        )
        return true
    }

    private func currentProcessObjectID() -> AudioObjectID? {
        var pid = getpid()
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var processObjectID = AudioObjectID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafePointer(to: &pid) { pidPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<pid_t>.size),
                pidPointer,
                &dataSize,
                &processObjectID
            )
        }
        guard status == noErr, processObjectID != AudioObjectID(kAudioObjectUnknown) else {
            VoxtLog.warning("System audio mute process object lookup failed. status=\(status)")
            return nil
        }
        return processObjectID
    }

    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
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
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    private func deviceUID(for deviceID: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let valuePointer = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<CFString?>.size,
            alignment: MemoryLayout<CFString?>.alignment
        )
        defer { valuePointer.deallocate() }

        valuePointer.initializeMemory(as: CFString?.self, repeating: nil, count: 1)
        defer { valuePointer.assumingMemoryBound(to: CFString?.self).deinitialize(count: 1) }

        var dataSize = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, valuePointer)
        guard status == noErr else { return nil }
        guard let value = valuePointer.assumingMemoryBound(to: CFString?.self).pointee else { return nil }
        return value as String
    }
}
