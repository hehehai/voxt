import AppKit
import Carbon

enum LaunchPresentationPolicy {
    @MainActor
    static func shouldPresentMainWindowOnLaunch() -> Bool {
        !LaunchSourceDetector.isLaunchedAsLoginItem
    }
}

enum LaunchSourceDetector {
    @MainActor
    static var isLaunchedAsLoginItem: Bool {
        guard let appleEvent = NSAppleEventManager.shared().currentAppleEvent else {
            return false
        }

        return appleEvent.paramDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem)) != nil
    }
}
