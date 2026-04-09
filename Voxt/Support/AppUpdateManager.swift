import Foundation
import Sparkle
import AppKit
import Combine

@MainActor
final class AppUpdateManager: NSObject, ObservableObject, SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    enum CheckSource {
        case automatic
        case manual
    }

    private lazy var updaterController: SPUStandardUpdaterController? = {
        guard sparkleIsAvailable else { return nil }
        return SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }()

    private let stableFeedURLString = "https://voxt.actnow.dev/updates/stable/appcast.xml"
    private let betaFeedURLString = "https://voxt.actnow.dev/updates/beta/appcast.xml"
    private let betaFeedEnableEnvKey = "VOXT_ENABLE_BETA_UPDATES"
    private var lastCheckSource: CheckSource = .automatic
    private var isPresentingUpdateUI = false
    @Published private(set) var hasUpdate = false
    @Published private(set) var latestVersion: String?
    @Published private(set) var updateCheckIssueMessage: String?
    @Published private(set) var isPreparingInteractiveUpdateUI = false
    private var latestDownloadedUpdateURL: URL?
    var onUpdatePresentationWillBegin: (() -> Void)?
    var onUpdatePresentationDidEnd: (() -> Void)?
    private lazy var sparkleIsAvailable: Bool = {
        let bundle = Bundle.main
        let shortVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let buildVersion = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let available = !shortVersion.isEmpty && !buildVersion.isEmpty
        if !available {
            VoxtLog.warning("Sparkle disabled: bundle version metadata is missing. short=\(shortVersion), build=\(buildVersion)")
        }
        return available
    }()

    // Background/dockless apps should opt into Sparkle's gentle reminder support
    // to avoid missing scheduled update alerts.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController?.updater.automaticallyChecksForUpdates ?? false }
        set {
            guard let updaterController else { return }
            updaterController.updater.automaticallyChecksForUpdates = newValue
        }
    }

    func syncAutomaticallyChecksForUpdates(_ newValue: Bool) {
        guard automaticallyChecksForUpdates != newValue else { return }
        automaticallyChecksForUpdates = newValue
    }

    func checkForUpdatesWithUserInterface() {
        lastCheckSource = .manual
        reportIssue(nil)
        guard sparkleIsAvailable, let updaterController else {
            reportIssue(AppLocalization.localizedString("Installer service is unavailable."))
            return
        }
        guard isInstallerServiceAvailable() else {
            VoxtLog.error("Sparkle installer services unavailable. Unable to present interactive update flow.")
            reportIssue(AppLocalization.localizedString("Installer service is unavailable."))
            return
        }

        logInstallerServiceAvailability()
        setPreparingInteractiveUpdateUI(true)
        NSApp.activate(ignoringOtherApps: true)
        VoxtLog.info("Manual update check triggered via Sparkle user interface.")
        updaterController.updater.checkForUpdates()
    }

    func checkForUpdates(source: CheckSource) {
        lastCheckSource = source
        reportIssue(nil)
        guard sparkleIsAvailable, let updaterController else {
            reportIssue(AppLocalization.localizedString("Installer service is unavailable."))
            return
        }
        if source == .manual {
            if !isInstallerServiceAvailable() {
                VoxtLog.error("Sparkle installer services unavailable. Opening manual update page instead of Sparkle installer flow.")
                reportIssue(AppLocalization.localizedString("Installer service is unavailable."))
                return
            }
            logInstallerServiceAvailability()
        }
        switch source {
        case .manual:
            NSApp.activate(ignoringOtherApps: true)
            VoxtLog.info("Manual update check triggered via Sparkle background mode.")
            updaterController.updater.checkForUpdatesInBackground()
        case .automatic:
            if !isInstallerServiceAvailable() {
                VoxtLog.warning("Sparkle installer services unavailable. Skipping background update cycle.")
                reportIssue(AppLocalization.localizedString("Installer service is unavailable."))
                return
            }
            VoxtLog.info("Background update check triggered via Sparkle.")
            updaterController.updater.checkForUpdatesInBackground()
        }
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        selectedFeedURLString
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let nsError = error as NSError
        if isNoUpdateFoundError(nsError) {
            setPreparingInteractiveUpdateUI(false)
            setUpdateState(hasUpdate: false, latestVersion: nil, issue: nil, downloadedURL: nil)
            VoxtLog.info(
                """
                Sparkle update abort treated as no-update result. source=\(lastCheckSource.description), \
                domain=\(nsError.domain), code=\(nsError.code), description=\(nsError.localizedDescription)
                """
            )
            return
        }
        let failureReason = nsError.localizedFailureReason ?? "nil"
        let underlyingErrorSummary: String
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            underlyingErrorSummary = "\(underlyingError.domain):\(underlyingError.code):\(underlyingError.localizedDescription)"
        } else {
            underlyingErrorSummary = "nil"
        }
        VoxtLog.error(
            """
            Sparkle update aborted. domain=\(nsError.domain), code=\(nsError.code), \
            description=\(nsError.localizedDescription), failureReason=\(failureReason), \
            underlyingError=\(underlyingErrorSummary), updateURL=\(latestDownloadedUpdateURL?.absoluteString ?? "nil"), \
            userInfo=\(nsError.userInfo)
            """
        )
        reportIssue(nsError.localizedDescription)
        finishUpdatePresentationIfNeeded()
        handleInstallerFailureIfNeeded(nsError)
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        setUpdateState(
            hasUpdate: true,
            latestVersion: "\(item.displayVersionString) (\(item.versionString))",
            issue: nil,
            downloadedURL: item.fileURL
        )
        VoxtLog.info(
            """
            Sparkle found update. source=\(lastCheckSource.description), \
            version=\(item.displayVersionString), build=\(item.versionString), \
            minSystemVersion=\(item.minimumSystemVersion ?? "nil")
            """
        )
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        setPreparingInteractiveUpdateUI(false)
        setUpdateState(hasUpdate: false, latestVersion: nil, issue: nil, downloadedURL: nil)
        let nsError = error as NSError
        VoxtLog.info(
            """
            Sparkle did not find update. source=\(lastCheckSource.description), \
            domain=\(nsError.domain), code=\(nsError.code), description=\(nsError.localizedDescription)
            """
        )
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        latestDownloadedUpdateURL = item.fileURL
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
            if isNoUpdateFoundError(nsError) {
                setUpdateState(hasUpdate: false, latestVersion: nil, issue: nil, downloadedURL: nil)
                VoxtLog.info(
                    """
                    Sparkle finished update cycle with no-update result. source=\(lastCheckSource.description), \
                    check=\(String(describing: updateCheck)), domain=\(nsError.domain), \
                    code=\(nsError.code), description=\(nsError.localizedDescription)
                    """
                )
                return
            }
            reportIssue(nsError.localizedDescription)
            VoxtLog.warning(
                """
                Sparkle finished update cycle with error. source=\(lastCheckSource.description), \
                check=\(String(describing: updateCheck)), domain=\(nsError.domain), \
                code=\(nsError.code), description=\(nsError.localizedDescription)
                """
            )
        } else {
            reportIssue(nil)
            VoxtLog.info(
                "Sparkle finished update cycle successfully. source=\(lastCheckSource.description), check=\(String(describing: updateCheck))"
            )
        }
        finishUpdatePresentationIfNeeded()
    }

    func standardUserDriverWillShowModalAlert() {
        beginUpdatePresentationIfNeeded(reason: "modal alert")
        VoxtLog.info("Sparkle will show modal alert.")
    }

    func standardUserDriverDidShowModalAlert() {
        VoxtLog.info("Sparkle did show modal alert.")
    }

    func standardUserDriverWillFinishUpdateSession() {
        VoxtLog.info("Sparkle will finish update session.")
        finishUpdatePresentationIfNeeded()
    }

    private var selectedFeedURLString: String {
        let baseFeedURLString: String
        // Prefer stable feed by default. Beta feed should be explicitly opted in
        // because local/dev beta channels may contain test-only appcast entries.
        if let channel = ProcessInfo.processInfo.environment["VOXT_UPDATE_CHANNEL"]?.lowercased() {
            switch channel {
            case "beta":
                if canUseBetaFeed {
                    baseFeedURLString = betaFeedURLString
                    break
                }

                VoxtLog.info("VOXT_UPDATE_CHANNEL=beta ignored; using stable appcast unless beta is explicitly enabled.")
                baseFeedURLString = stableFeedURLString
                break
            case "stable":
                baseFeedURLString = stableFeedURLString
                break
            default:
                baseFeedURLString = stableFeedURLString
            }
        } else {
            baseFeedURLString = stableFeedURLString
        }
        return Self.localizedFeedURLString(
            baseURLString: baseFeedURLString,
            interfaceLanguage: AppLocalization.language
        )
    }

    private var canUseBetaFeed: Bool {
        let explicitEnable = ProcessInfo.processInfo.environment[betaFeedEnableEnvKey]
            .map { $0.lowercased() } ?? ""
        return ["1", "true", "yes", "on"].contains(explicitEnable)
    }

    private func handleInstallerFailureIfNeeded(_ error: NSError) {
        let message = error.localizedDescription.lowercased()
        let indicatesInstallerFailure =
            (error.domain == SUSparkleErrorDomain && [4003, 4005, 4008, 4012].contains(error.code)) ||
            message.contains("authorization") ||
            message.contains("installer") ||
            message.contains("gain authorization required to update target")
        guard indicatesInstallerFailure else { return }

        let fallbackURLString = latestDownloadedUpdateURL?.absoluteString
            ?? selectedFeedURLString.replacingOccurrences(of: "/appcast.xml", with: "/")

        guard let url = URL(string: fallbackURLString) else { return }
        VoxtLog.warning(
            """
            Sparkle installer failed to launch or authorize. \
            Opening fallback update URL: \(fallbackURLString)
            """
        )
        NSWorkspace.shared.open(url)
    }

    private func logInstallerServiceAvailability() {
        guard isInstallerServiceAvailable() else {
            return
        }
        let frameworkXPCServicesURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices", isDirectory: true)
        let frameworkEntries = (try? FileManager.default.contentsOfDirectory(atPath: frameworkXPCServicesURL.path)) ?? []
        let installerEntries = frameworkEntries.filter { $0.localizedCaseInsensitiveContains("Installer") }
        VoxtLog.info("Sparkle installer check: found installer services \(installerEntries)")
    }

    private func isInstallerServiceAvailable() -> Bool {
        let appXPCServicesURL = Bundle.main.bundleURL.appendingPathComponent("Contents/XPCServices", isDirectory: true)
        let frameworkXPCServicesURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices", isDirectory: true)
        let fm = FileManager.default
        let appEntries = (try? fm.contentsOfDirectory(atPath: appXPCServicesURL.path)) ?? []
        let frameworkEntries = (try? fm.contentsOfDirectory(atPath: frameworkXPCServicesURL.path)) ?? []

        let combinedEntries = appEntries + frameworkEntries
        let installerEntries = combinedEntries.filter { $0.localizedCaseInsensitiveContains("Installer") }
        guard !installerEntries.isEmpty else {
            VoxtLog.error(
                """
                Sparkle installer services not found.
                appXPCServices=\(appXPCServicesURL.path) entries=\(appEntries)
                frameworkXPCServices=\(frameworkXPCServicesURL.path) entries=\(frameworkEntries)
                """
            )
            return false
        }
        return true
    }

    private func reportIssue(_ message: String?) {
        setUpdateState(
            hasUpdate: hasUpdate,
            latestVersion: latestVersion,
            issue: message,
            downloadedURL: latestDownloadedUpdateURL
        )
    }

    private func setUpdateState(
        hasUpdate: Bool,
        latestVersion: String?,
        issue: String?,
        downloadedURL: URL?
    ) {
        self.hasUpdate = hasUpdate
        self.latestVersion = latestVersion
        self.updateCheckIssueMessage = issue
        self.latestDownloadedUpdateURL = downloadedURL
        NotificationCenter.default.post(name: .voxtUpdateAvailabilityDidChange, object: nil)
    }

    private func setPreparingInteractiveUpdateUI(_ isPreparing: Bool) {
        guard isPreparingInteractiveUpdateUI != isPreparing else { return }
        isPreparingInteractiveUpdateUI = isPreparing
        NotificationCenter.default.post(name: .voxtUpdateAvailabilityDidChange, object: nil)
    }

    private func isNoUpdateFoundError(_ error: NSError) -> Bool {
        error.domain == SUSparkleErrorDomain && error.code == 1001
    }

    private func beginUpdatePresentationIfNeeded(reason: String) {
        setPreparingInteractiveUpdateUI(false)
        guard !isPresentingUpdateUI else { return }
        isPresentingUpdateUI = true
        VoxtLog.info("Sparkle update UI became active. reason=\(reason), source=\(lastCheckSource.description)")
        onUpdatePresentationWillBegin?()
    }

    private func finishUpdatePresentationIfNeeded() {
        setPreparingInteractiveUpdateUI(false)
        guard isPresentingUpdateUI else { return }
        isPresentingUpdateUI = false
        VoxtLog.info("Sparkle update UI finished. source=\(lastCheckSource.description)")
        onUpdatePresentationDidEnd?()
    }

    static func localizedFeedURLString(baseURLString: String, interfaceLanguage: AppInterfaceLanguage) -> String {
        guard var components = URLComponents(string: baseURLString) else {
            return baseURLString
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "lang" }
        queryItems.append(
            URLQueryItem(name: "lang", value: interfaceLanguage.localeIdentifier)
        )
        components.queryItems = queryItems
        return components.url?.absoluteString ?? baseURLString
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

extension Notification.Name {
    static let voxtUpdateAvailabilityDidChange = Notification.Name("voxt.update.availability.didChange")
}
