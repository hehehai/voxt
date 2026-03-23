import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AboutSettingsView: View {
    let appUpdateManager: AppUpdateManager
    let navigationRequest: SettingsNavigationRequest?
    @Environment(\.locale) private var locale

    @State private var latestLogUpdateDate: Date?
    @State private var logExportStatus: String?
    @State private var hostWindow: NSWindow?

    private var appVersionText: String {
        let bundle = Bundle.main
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        if let shortVersion, let buildVersion, !buildVersion.isEmpty {
            return "\(shortVersion) (\(buildVersion))"
        }
        if let shortVersion, !shortVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return shortVersion
        }
        if let buildVersion, !buildVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return buildVersion
        }
        return String(localized: "Version metadata missing")
    }

    private let feedbackURL = URL(string: "https://github.com/hehehai/voxt/issues/new/choose")!

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Voxt")
                        .font(.headline)
                    Text("Voice to Thought")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        HStack(spacing: 4) {
                            Text("Version")
                            Text(appVersionText)
                        }
                        Spacer(minLength: 0)
                        Button(String(localized: "Check for Updates…")) {
                            appUpdateManager.checkForUpdatesWithUserInterface()
                        }
                        .controlSize(.small)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .settingsNavigationAnchor(.aboutVoxt)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Project")
                        .font(.headline)
                    Link("github.com/hehehai/voxt", destination: URL(string: "https://github.com/hehehai/voxt")!)
                        .font(.caption)
                    Link(String(localized: "Feedback"), destination: feedbackURL)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .settingsNavigationAnchor(.aboutProject)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Author")
                        .font(.headline)
                    Link("hehehai", destination: URL(string: "https://www.hehehai.cn/")!)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .settingsNavigationAnchor(.aboutAuthor)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Thanks")
                        .font(.headline)
                    Link(
                        "github.com/Blaizzy/mlx-audio-swift",
                        destination: URL(string: "https://github.com/Blaizzy/mlx-audio-swift")!
                    )
                    .font(.caption)
                    Link(
                        "github.com/fayazara/Kaze",
                        destination: URL(string: "https://github.com/fayazara/Kaze")!
                    )
                    .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .settingsNavigationAnchor(.aboutThanks)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Logs")
                            .font(.headline)
                        Spacer()
                        Button("Export Latest Logs (2000)") {
                            exportLatestLogs()
                        }
                        .controlSize(.small)
                    }

                    let value = latestLogUpdateDate?.formatted(
                        .dateTime
                            .locale(locale)
                            .year()
                            .month(.abbreviated)
                            .day()
                            .hour()
                            .minute()
                            .second()
                    ) ?? String(localized: "No logs yet")
                    Text(localizedFormat("Last updated: %@", value))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let logExportStatus {
                        Text(logExportStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Exports the most recent 2000 log entries as a .log file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .settingsNavigationAnchor(.aboutLogs)
        }
        .background(
            WindowAccessor { window in
                hostWindow = window
            }
        )
        .onAppear {
            refreshLogUpdateDate()
        }
    }

    private func refreshLogUpdateDate() {
        latestLogUpdateDate = VoxtLog.latestLogUpdateDate()
    }

    private func exportLatestLogs() {
        logExportStatus = nil
        let payload = VoxtLog.latestLogExportPayload(limit: 2000)
        let panel = configuredSavePanel(filename: payload.filename)

        if let hostWindow {
            panel.beginSheetModal(for: hostWindow) { response in
                handleLogExportResponse(response, panel: panel, payload: payload)
            }
            return
        }

        let response = panel.runModal()
        handleLogExportResponse(response, panel: panel, payload: payload)
    }

    private func localizedFormat(_ key: String, _ argument: String) -> String {
        let format = NSLocalizedString(key, comment: "")
        return String(format: format, locale: locale, argument)
    }

    private func configuredSavePanel(filename: String) -> NSSavePanel {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [UTType(filenameExtension: "log", conformingTo: .plainText) ?? .plainText]
        return panel
    }

    private func handleLogExportResponse(
        _ response: NSApplication.ModalResponse,
        panel: NSSavePanel,
        payload: VoxtLog.ExportPayload
    ) {
        defer { refreshLogUpdateDate() }

        guard response == .OK else {
            logExportStatus = String(localized: "Export canceled")
            return
        }

        guard let destinationURL = panel.url else {
            logExportStatus = String(localized: "Export canceled")
            return
        }

        do {
            try payload.content.write(to: destinationURL, atomically: true, encoding: .utf8)
            logExportStatus = localizedFormat("Exported to %@", destinationURL.lastPathComponent)
        } catch {
            logExportStatus = localizedFormat("Export failed: %@", error.localizedDescription)
        }
    }
}
