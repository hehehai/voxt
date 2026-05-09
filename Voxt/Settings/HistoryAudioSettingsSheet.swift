import SwiftUI

private func localizedHistoryAudioSettings(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

struct HistoryAudioSettingsSheet: View {
    @Binding var historyCleanupEnabled: Bool
    @Binding var historyRetentionPeriodRaw: String
    @Binding var historyAudioStorageEnabled: Bool
    @Binding var historyAudioStorageDisplayPath: String
    @Binding var historyAudioStorageSelectionError: String?
    @Binding var historyAudioExportResultMessage: String?
    @Binding var isPresented: Bool

    let historyRetentionPeriod: HistoryRetentionPeriod
    let historyAudioStorageStatsSummary: String
    let onOpenHistoryAudioStorageInFinder: () -> Void
    let onChooseHistoryAudioStorageDirectory: () -> Void
    let onExportAllHistoryAudio: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localizedHistoryAudioSettings("History Settings"))
                .font(.title3.weight(.semibold))

            GeneralSettingsCard(titleText: localizedHistoryAudioSettings("Cleanup")) {
                Toggle(localizedHistoryAudioSettings("History Cleanup"), isOn: $historyCleanupEnabled)

                if historyCleanupEnabled {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(localizedHistoryAudioSettings("Retention"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        SettingsMenuPicker(
                            selection: $historyRetentionPeriodRaw,
                            options: HistoryRetentionPeriod.allCases.map { option in
                                SettingsMenuOption(value: option.rawValue, title: option.title)
                            },
                            selectedTitle: historyRetentionPeriod.title,
                            width: 160
                        )
                    }
                } else {
                    Text(localizedHistoryAudioSettings("When disabled, Voxt keeps history entries until you delete them manually."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GeneralSettingsCard(titleText: localizedHistoryAudioSettings("Audio Storage")) {
                Toggle(localizedHistoryAudioSettings("Save history audio"), isOn: $historyAudioStorageEnabled)

                if historyAudioStorageEnabled {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(localizedHistoryAudioSettings("Storage Path"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(action: onOpenHistoryAudioStorageInFinder) {
                            HStack(spacing: 6) {
                                Image(systemName: "folder")
                                    .font(.caption)
                                Text(
                                    historyAudioStorageDisplayPath.isEmpty
                                    ? HistoryAudioStorageDirectoryManager.defaultRootURL.path
                                    : historyAudioStorageDisplayPath
                                )
                                .underline()
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .multilineTextAlignment(.trailing)
                                Image(systemName: "arrow.up.forward.square")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(SettingsInlineSelectorButtonStyle())
                        .help(localizedHistoryAudioSettings("Open folder"))

                        Button(localizedHistoryAudioSettings("Choose")) {
                            onChooseHistoryAudioStorageDirectory()
                        }
                        .buttonStyle(SettingsPillButtonStyle())
                    }

                    Text(localizedHistoryAudioSettings("New history audio is stored here. Switching the path will not move existing audio files."))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let historyAudioStorageSelectionError, !historyAudioStorageSelectionError.isEmpty {
                        Text(historyAudioStorageSelectionError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } else {
                    Text(localizedHistoryAudioSettings("When disabled, history items will not keep audio files."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if historyAudioStorageEnabled {
                GeneralSettingsCard(titleText: localizedHistoryAudioSettings("Export")) {
                    HStack(spacing: 10) {
                        Button(localizedHistoryAudioSettings("Export Audio")) {
                            onExportAllHistoryAudio()
                        }
                        .buttonStyle(SettingsPillButtonStyle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(historyAudioStorageStatsSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(localizedHistoryAudioSettings("Copies every saved history audio file into a folder you choose."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let historyAudioExportResultMessage, !historyAudioExportResultMessage.isEmpty {
                        Text(historyAudioExportResultMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            SettingsDialogActionRow {
                Button(localizedHistoryAudioSettings("Done")) {
                    isPresented = false
                }
                .buttonStyle(SettingsPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }
}
