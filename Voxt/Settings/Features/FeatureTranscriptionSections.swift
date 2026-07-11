// FeatureTranscriptionSections.swift
// Provides Feature Transcription Sections for feature settings.

import SwiftUI

extension FeatureSettingsView {
    var transcriptionContent: some View {
        featurePage(
            title: featureSettingsLocalized("Transcription"),
            subtitle: featureSettingsLocalized("Choose a speech model, then add text enhancement if needed."),
            iconKind: .transcription,
            pills: transcriptionPills,
            showsHeroHeader: false
        ) {
            FeatureSettingsCard(title: "") {
                FeatureSettingSection(title: "", detail: "") {
                    FeatureSelectorRow(
                        title: featureSettingsLocalized("Speech Model"),
                        value: asrSelectionSummary(featureSettings.transcription.asrSelectionID),
                        action: { selectorSheet = .transcriptionASR }
                    )
                }

                FeatureToggleRow(
                    title: featureSettingsLocalized("Text Enhancement"),
                    detail: "",
                    isOn: transcriptionLLMEnabledBinding
                )

                if featureSettings.transcription.llmEnabled {
                    FeatureSettingSection(title: "", detail: "") {
                        FeatureSelectorRow(
                            title: featureSettingsLocalized("Enhancement Model"),
                            value: llmSelectionSummary(featureSettings.transcription.llmSelectionID),
                            action: { selectorSheet = .transcriptionLLM }
                        )
                        FeaturePromptSection(
                            title: featureSettingsLocalized("Enhancement Prompt"),
                            text: promptBinding(
                                get: { featureSettings.transcription.prompt },
                                set: { featureSettings.transcription.prompt = $0 },
                                kind: .enhancement
                            ),
                            defaultText: AppPromptDefaults.text(for: .enhancement),
                            variables: ModelSettingsPromptVariables.enhancement,
                            guidance: "",
                            persistChanges: { prompt in
                                FeatureSettingsStore.saveTranscriptionPrompt(prompt)
                            }
                        )
                    }
                }

            }
        }
    }

    var noteContent: some View {
        featurePage(
            title: featureSettingsLocalized("Notes"),
            subtitle: featureSettingsLocalized("Capture key points during recording. Notes stay separate and get short AI titles."),
            iconKind: .note,
            pills: notePills,
            showsHeroHeader: false
        ) {
            FeatureSettingsCard(title: "") {
                if !noteStore.isAvailable || noteStore.lastRecoveryArchiveURL != nil {
                    VoxtNoteStorageRecoveryView(store: noteStore)
                }

                FeatureSettingSection(title: "", detail: "") {
                    FeatureSelectorRow(
                        title: featureSettingsLocalized("Title Model"),
                        value: llmSelectionSummary(featureSettings.transcription.notes.titleModelSelectionID),
                        action: { selectorSheet = .transcriptionNoteTitle }
                    )
                }

                FeatureToggleRow(
                    title: featureSettingsLocalized("Sound"),
                    detail: "",
                    isOn: binding(
                        get: { featureSettings.transcription.notes.soundEnabled },
                        set: { featureSettings.transcription.notes.soundEnabled = $0 }
                    )
                )

                if featureSettings.transcription.notes.soundEnabled {
                    FeatureNoteSoundPresetRow(
                        title: featureSettingsLocalized("Sound Preset"),
                        detail: "",
                        picker: {
                            SettingsMenuPicker(
                                selection: binding(
                                    get: { featureSettings.transcription.notes.soundPreset },
                                    set: { featureSettings.transcription.notes.soundPreset = $0 }
                                ),
                                options: InteractionSoundPreset.allCases.map { preset in
                                    SettingsMenuOption(value: preset, title: preset.title)
                                },
                                selectedTitle: featureSettings.transcription.notes.soundPreset.title,
                                width: 220
                            )
                        },
                        onTrySound: {
                            interactionSoundPlayer.playPreview(preset: featureSettings.transcription.notes.soundPreset)
                        }
                    )
                }

                FeatureSettingSection(
                    title: featureSettingsLocalized("Floating Panel"),
                    detail: featureSettingsLocalized("Reveal your notes by resting the pointer in a screen corner.")
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        VoxtNotePanelCornerPicker(
                            selection: binding(
                                get: { featureSettings.transcription.notes.panel.corner },
                                set: { featureSettings.transcription.notes.panel.corner = $0 }
                            )
                        )

                        VoxtNotePanelDelayRow(
                            title: featureSettingsLocalized("Reveal Delay"),
                            value: binding(
                                get: { featureSettings.transcription.notes.panel.revealDelay },
                                set: { featureSettings.transcription.notes.panel.revealDelay = $0 }
                            ),
                            range: 0.2...2.0
                        )

                        VoxtNotePanelDelayRow(
                            title: featureSettingsLocalized("Hide Delay"),
                            value: binding(
                                get: { featureSettings.transcription.notes.panel.hideDelay },
                                set: { featureSettings.transcription.notes.panel.hideDelay = $0 }
                            ),
                            range: 0.1...2.0
                        )

                        Toggle(
                            featureSettingsLocalized("Translucent Panel"),
                            isOn: binding(
                                get: { featureSettings.transcription.notes.panel.isTranslucent },
                                set: { featureSettings.transcription.notes.panel.isTranslucent = $0 }
                            )
                        )
                        .toggleStyle(.switch)

                        Text(featureSettingsLocalized("macOS Hot Corners may activate at the same time."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                FeatureSettingSection(
                    title: "",
                    detail: ""
                ) {
                    noteObsidianSyncSection
                }

                FeatureSettingSection(
                    title: "",
                    detail: ""
                ) {
                    noteRemindersSyncSection
                }
            }
        }
    }
}

private struct VoxtNoteStorageRecoveryView: View {
    @ObservedObject var store: VoxtNoteStore
    @State private var confirmsArchiveAndRebuild = false

    var body: some View {
        FeatureSettingSection(
            title: featureSettingsLocalized("Note Storage"),
            detail: featureSettingsLocalized("Voxt keeps note data in its own local application storage.")
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if store.isAvailable {
                    Label(
                        featureSettingsLocalized("Note storage is ready."),
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)

                    if let archiveURL = store.lastRecoveryArchiveURL {
                        Text(
                            String(
                                format: featureSettingsLocalized("The previous database was archived at %@"),
                                archiveURL.path
                            )
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    }
                } else {
                    Label(
                        featureSettingsLocalized("Note storage is unavailable."),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)

                    if let message = store.availability.errorMessage, !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    HStack(spacing: 10) {
                        Button(featureSettingsLocalized("Retry")) {
                            store.retryOpeningStorage()
                        }

                        Button(
                            featureSettingsLocalized("Archive and Rebuild"),
                            role: .destructive
                        ) {
                            confirmsArchiveAndRebuild = true
                        }
                    }
                }
            }
        }
        .confirmationDialog(
            featureSettingsLocalized("Archive the current note database and create a new one?"),
            isPresented: $confirmsArchiveAndRebuild,
            titleVisibility: .visible
        ) {
            Button(featureSettingsLocalized("Archive and Rebuild"), role: .destructive) {
                store.archiveAndRebuildStorage()
            }
            Button(featureSettingsLocalized("Cancel"), role: .cancel) {}
        } message: {
            Text(featureSettingsLocalized("The existing database will be preserved in a recovery folder. Notes in it will not appear in the new database."))
        }
    }
}

private struct VoxtNotePanelCornerPicker: View {
    @Binding var selection: VoxtNotePanelCorner

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(spacing: 9) {
                HStack {
                    cornerButton(.topLeft)
                    Spacer()
                    cornerButton(.topRight)
                }
                Spacer()
                Image(systemName: "display")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.tertiary)
                Spacer()
                HStack {
                    cornerButton(.bottomLeft)
                    Spacer()
                    cornerButton(.bottomRight)
                }
            }
            .padding(10)
            .frame(width: 230, height: 132)
            .background(
                Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.7)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(featureSettingsLocalized("Hiding Corner"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(selection.title)
                    .font(.headline)
                Text(featureSettingsLocalized("The same corner works on every connected display."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func cornerButton(_ corner: VoxtNotePanelCorner) -> some View {
        Button { selection = corner } label: {
            Circle()
                .fill(selection == corner ? Color.accentColor : Color.primary.opacity(0.12))
                .frame(width: 17, height: 17)
                .overlay {
                    Circle()
                        .stroke(
                            selection == corner ? Color.accentColor.opacity(0.25) : .clear,
                            lineWidth: 5
                        )
                }
        }
        .buttonStyle(.plain)
        .help(corner.title)
        .accessibilityLabel(corner.title)
        .accessibilityAddTraits(selection == corner ? .isSelected : [])
    }
}

private struct VoxtNotePanelDelayRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(value, format: .number.precision(.fractionLength(1)))
                    .monospacedDigit()
                Text(featureSettingsLocalized("sec"))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: 0.1)
        }
    }
}
