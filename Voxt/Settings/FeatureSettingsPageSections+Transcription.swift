import SwiftUI

extension FeatureSettingsView {
    var transcriptionContent: some View {
        featurePage(
            title: featureSettingsLocalized("Transcription"),
            subtitle: featureSettingsLocalized("Choose the speech model for standard transcription, then optionally add LLM cleanup and app-aware enhancement."),
            icon: "waveform.and.mic",
            pills: transcriptionPills
        ) {
            FeatureSettingsCard(title: featureSettingsLocalized("Model Pipeline")) {
                FeatureSettingSection(title: featureSettingsLocalized("Speech Recognition"), detail: featureSettingsLocalized("This model handles the first-pass transcript.")) {
                    FeatureSelectorRow(
                        title: featureSettingsLocalized("ASR Model"),
                        value: asrSelectionSummary(featureSettings.transcription.asrSelectionID),
                        action: { selectorSheet = .transcriptionASR }
                    )
                }

                FeatureToggleRow(
                    title: featureSettingsLocalized("Enable LLM Enhancement"),
                    detail: featureSettingsLocalized("Use a second language model pass to clean punctuation, structure, and readability."),
                    isOn: transcriptionLLMEnabledBinding
                )

                FeatureToggleRow(
                    title: featureSettingsLocalized("Enable App Enhancement"),
                    detail: featureSettingsLocalized("Use different enhancement prompts for different apps or browser pages."),
                    isOn: binding(
                        get: { featureSettings.rewrite.appEnhancementEnabled },
                        set: { featureSettings.rewrite.appEnhancementEnabled = $0 }
                    )
                )

                FeatureToggleRow(
                    title: featureSettingsLocalized("Enable Notes"),
                    detail: featureSettingsLocalized("Add segmented notes during transcription. Once enabled, Notes appears in the Feature menu and supports a dedicated trigger key."),
                    isOn: binding(
                        get: { featureSettings.transcription.notes.enabled },
                        set: { featureSettings.transcription.notes.enabled = $0 }
                    )
                )

                if featureSettings.transcription.llmEnabled {
                    FeatureSettingSection(title: featureSettingsLocalized("Text Enhancement"), detail: featureSettingsLocalized("Only configured and installed models can be selected here.")) {
                        FeatureSelectorRow(
                            title: featureSettingsLocalized("LLM Model"),
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
                            guidance: PromptAuthoringGuidance.enhancement,
                            persistChanges: saveFeatureSettings
                        )
                    }
                }
            }
        }
    }

    var noteContent: some View {
        featurePage(
            title: featureSettingsLocalized("Notes"),
            subtitle: featureSettingsLocalized("Cut a live transcription into separate notes without stopping the recording session. Notes stay in their own floating window and each one gets a short AI title."),
            icon: "note.text",
            pills: notePills
        ) {
            FeatureSettingsCard(title: featureSettingsLocalized("Notes Workflow")) {
                FeatureNoteShortcutRow(
                    title: featureSettingsLocalized("Note Trigger"),
                    detail: featureSettingsLocalized("Use this key while a live transcription session is recording to save the current transcript tail as a note and insert a note marker into the OverLazy preview."),
                    shortcut: binding(
                        get: { featureSettings.transcription.notes.triggerShortcut },
                        set: { featureSettings.transcription.notes.triggerShortcut = $0 }
                    )
                )

                FeatureSettingSection(title: featureSettingsLocalized("Title Generation"), detail: featureSettingsLocalized("This model generates the short floating-card title for each saved note.")) {
                    FeatureSelectorRow(
                        title: featureSettingsLocalized("Note Title Model"),
                        value: llmSelectionSummary(featureSettings.transcription.notes.titleModelSelectionID),
                        action: { selectorSheet = .transcriptionNoteTitle }
                    )
                }

                FeatureToggleRow(
                    title: featureSettingsLocalized("Note Audio"),
                    detail: featureSettingsLocalized("Play a short reminder sound each time the note trigger is pressed during a live transcription session."),
                    isOn: binding(
                        get: { featureSettings.transcription.notes.soundEnabled },
                        set: { featureSettings.transcription.notes.soundEnabled = $0 }
                    )
                )

                if featureSettings.transcription.notes.soundEnabled {
                    FeatureNoteSoundPresetRow(
                        title: featureSettingsLocalized("Note Sound Preset"),
                        detail: featureSettingsLocalized("Choose the reminder sound used when a note is captured, and preview it here."),
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
                    title: featureSettingsLocalized("Obsidian Sync"),
                    detail: ""
                ) {
                    noteObsidianSyncSection
                }

                FeatureSettingSection(
                    title: featureSettingsLocalized("Reminders Sync"),
                    detail: ""
                ) {
                    noteRemindersSyncSection
                }
            }
        }
    }
}
