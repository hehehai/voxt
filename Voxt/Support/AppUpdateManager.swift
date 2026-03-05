import Foundation
import Sparkle

@MainActor
final class AppUpdateManager: NSObject, SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    enum CheckSource {
        case automatic
        case manual
    }

    private lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }()

    private let stableFeedURLString = "https://voxt.actnow.dev/updates/stable/appcast.xml"
    private let betaFeedURLString = "https://voxt.actnow.dev/updates/beta/appcast.xml"

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

    func feedURLString(for updater: SPUUpdater) -> String? {
        selectedFeedURLString
    }

    private var selectedFeedURLString: String {
        let bundleID = Bundle.main.bundleIdentifier?.lowercased() ?? ""
        let isBetaBuild = bundleID.contains(".dev") || bundleID.contains(".beta")
        return isBetaBuild ? betaFeedURLString : stableFeedURLString
    }
}
