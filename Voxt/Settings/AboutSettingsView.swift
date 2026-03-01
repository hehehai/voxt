import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AboutSettingsView: View {
    @Environment(\.locale) private var locale

    @State private var latestLogUpdateDate: Date?
    @State private var logExportStatus: String?

    private var appVersionText: String? {
        let bundle = Bundle.main
        let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        if let shortVersion, let buildVersion, !buildVersion.isEmpty {
            return "\(shortVersion) (\(buildVersion))"
        }
        if let shortVersion {
            return shortVersion
        }
        if let buildVersion {
            return buildVersion
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Voxt")
                        .font(.headline)
                    Text("On-device push-to-talk transcription powered by MLX Audio.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let version = appVersionText {
                        HStack(spacing: 4) {
                            Text("Version")
                            Text(version)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("License")
                        .font(.headline)
                    Text("MIT License")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Project")
                        .font(.headline)
                    Link("github.com/hehehai/voxt", destination: URL(string: "https://github.com/hehehai/voxt")!)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

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
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
        }
        .onAppear {
            refreshLogUpdateDate()
        }
    }

    private func refreshLogUpdateDate() {
        latestLogUpdateDate = VoxtLog.latestLogUpdateDate()
    }

    private func exportLatestLogs() {
        do {
            let generatedURL = try VoxtLog.exportLatestLogs(limit: 2000)
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.allowedContentTypes = [.plainText]
            panel.nameFieldStringValue = generatedURL.lastPathComponent
            panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

            let response = panel.runModal()
            guard response == .OK, let destinationURL = panel.url else {
                logExportStatus = nil
                refreshLogUpdateDate()
                return
            }

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: generatedURL, to: destinationURL)
            logExportStatus = localizedFormat("Exported to %@", destinationURL.lastPathComponent)
            refreshLogUpdateDate()
        } catch {
            logExportStatus = localizedFormat("Export failed: %@", error.localizedDescription)
            refreshLogUpdateDate()
        }
    }

    private func localizedFormat(_ key: String, _ argument: String) -> String {
        let format = NSLocalizedString(key, comment: "")
        return String(format: format, locale: locale, argument)
    }
}
