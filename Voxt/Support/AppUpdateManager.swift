import Foundation
import Sparkle

@MainActor
final class AppUpdateManager: NSObject {
    enum CheckSource {
        case automatic
        case manual
    }

    private let updaterController: SPUStandardUpdaterController

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

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
