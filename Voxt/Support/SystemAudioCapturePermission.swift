import Foundation
import AppKit
import SystemSettingsKit

enum SystemAudioCaptureAuthorizationStatus: String {
    case unknown
    case denied
    case authorized
}

enum SystemAudioCapturePermission {
    static func authorizationStatus() -> SystemAudioCaptureAuthorizationStatus {
        guard let preflight = preflightSPI else { return .unknown }
        let result = preflight("kTCCServiceAudioCapture" as CFString, nil)
        switch result {
        case 0:
            return .authorized
        case 1:
            return .denied
        default:
            return .unknown
        }
    }

    static func requestAccess(completion: ((Bool) -> Void)? = nil) {
        guard let request = requestSPI else {
            completion?(false)
            return
        }

        request("kTCCServiceAudioCapture" as CFString, nil) { granted in
            DispatchQueue.main.async {
                completion?(granted)
            }
        }
    }

    static func openSystemSettings() {
        _ = SystemSettings.open(.privacy(anchor: .privacyAudioCapture))
    }

    private typealias PreflightFuncType = @convention(c) (CFString, CFDictionary?) -> Int
    private typealias RequestFuncType = @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void

    private static let apiHandle: UnsafeMutableRawPointer? = {
        let tccPath = "/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC"
        return dlopen(tccPath, RTLD_NOW)
    }()

    private static let preflightSPI: PreflightFuncType? = {
        guard let apiHandle, let funcSym = dlsym(apiHandle, "TCCAccessPreflight") else {
            return nil
        }
        return unsafeBitCast(funcSym, to: PreflightFuncType.self)
    }()

    private static let requestSPI: RequestFuncType? = {
        guard let apiHandle, let funcSym = dlsym(apiHandle, "TCCAccessRequest") else {
            return nil
        }
        return unsafeBitCast(funcSym, to: RequestFuncType.self)
    }()
}
