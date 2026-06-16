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

                FeatureToggleRow(
                    title: featureSettingsLocalized("Notes"),
                    detail: "",
                    isOn: binding(
                        get: { featureSettings.transcription.notes.enabled },
                        set: { featureSettings.transcription.notes.enabled = $0 }
                    )
                )
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
                FeatureNoteShortcutRow(
                    title: featureSettingsLocalized("Trigger Key"),
                    detail: featureSettingsLocalized("Use this key while a live transcription session is recording to save the current transcript tail as a note and insert a note marker into the OverLazy preview."),
                    shortcut: binding(
                        get: { featureSettings.transcription.notes.triggerShortcut },
                        set: { featureSettings.transcription.notes.triggerShortcut = $0 }
                    )
                )

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
