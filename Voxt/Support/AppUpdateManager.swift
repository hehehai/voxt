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
    private var lastCheckSource: CheckSource = .automatic

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
        lastCheckSource = source
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

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let nsError = error as NSError
        VoxtLog.error(
            """
            Sparkle update aborted. domain=\(nsError.domain), code=\(nsError.code), \
            description=\(nsError.localizedDescription), userInfo=\(nsError.userInfo)
            """
        )
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        VoxtLog.info(
            """
            Sparkle found update. source=\(lastCheckSource.description), \
            version=\(item.displayVersionString), build=\(item.versionString), \
            minSystemVersion=\(item.minimumSystemVersion ?? "nil")
            """
        )
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        let nsError = error as NSError
        VoxtLog.info(
            """
            Sparkle did not find update. source=\(lastCheckSource.description), \
            domain=\(nsError.domain), code=\(nsError.code), description=\(nsError.localizedDescription)
            """
        )
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        VoxtLog.info(
            """
            Sparkle finished downloading update. version=\(item.displayVersionString), \
            build=\(item.versionString), fileURL=\(item.fileURL?.absoluteString ?? "nil")
            """
        )
    }

    func updater(_ updater: SPUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error) {
        let nsError = error as NSError
        VoxtLog.error(
            """
            Sparkle failed to download update. version=\(item.displayVersionString), \
            build=\(item.versionString), domain=\(nsError.domain), \
            code=\(nsError.code), description=\(nsError.localizedDescription)
            """
        )
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        if let error {
            let nsError = error as NSError
            VoxtLog.warning(
                """
                Sparkle finished update cycle with error. source=\(lastCheckSource.description), \
                check=\(String(describing: updateCheck)), domain=\(nsError.domain), \
                code=\(nsError.code), description=\(nsError.localizedDescription)
                """
            )
        } else {
            VoxtLog.info(
                "Sparkle finished update cycle successfully. source=\(lastCheckSource.description), check=\(String(describing: updateCheck))"
            )
        }
    }

    func standardUserDriverWillShowModalAlert() {
        VoxtLog.info("Sparkle will show modal alert.")
    }

    func standardUserDriverDidShowModalAlert() {
        VoxtLog.info("Sparkle did show modal alert.")
    }

    private var selectedFeedURLString: String {
        // Prefer stable feed by default. Beta feed should be explicitly opted in
        // because local/dev beta channels may contain test-only appcast entries.
        if let channel = ProcessInfo.processInfo.environment["VOXT_UPDATE_CHANNEL"]?.lowercased() {
            switch channel {
            case "beta":
                return betaFeedURLString
            case "stable":
                return stableFeedURLString
            default:
                break
            }
        }
        return stableFeedURLString
    }
}

private extension AppUpdateManager.CheckSource {
    var description: String {
        switch self {
        case .automatic:
            return "automatic"
        case .manual:
            return "manual"
        }
    }
}
