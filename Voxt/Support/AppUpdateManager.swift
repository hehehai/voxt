import Foundation
import Sparkle

@MainActor
final class AppUpdateManager: NSObject, SPUStandardUserDriverDelegate {
    enum CheckSource {
        case automatic
        case manual
    }

    private lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
    }()

    // Background/dockless apps should opt into Sparkle's gentle reminder support
    // to avoid missing scheduled update alerts.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    var hasUpdate: Bool {
        false
    }

    var latestVersion: String? {
        nil
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates(source: CheckSource) {
        switch source {
        case .manual:
            VoxtLog.info("Manual update check triggered via Sparkle.")
            updaterController.checkForUpdates(nil)
        case .automatic:
            VoxtLog.info("Background update check triggered via Sparkle.")
            updaterController.updater.checkForUpdatesInBackground()
        }
    }
}
