import SwiftUI

private func featureSettingsLocalized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

extension FeatureSettingsView {
    var transcriptionContent: some View {
        featurePage(
            title: featureSettingsLocalized("Transcription"),
            subtitle: featureSettingsLocalized("Choose the speech model used for standard transcription, and optionally layer an LLM cleanup pass on top."),
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
                    title: featureSettingsLocalized("Enable Meeting"),
                    detail: featureSettingsLocalized("Turn on the dedicated meeting workflow, shortcut, overlay, and meeting-specific model settings."),
                    isOn: binding(
                        get: { featureSettings.meeting.enabled },
                        set: { featureSettings.meeting.enabled = $0 }
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
                            text: binding(
                                get: { featureSettings.transcription.prompt },
                                set: { featureSettings.transcription.prompt = $0 }
                            ),
                            defaultText: AppPreferenceKey.defaultEnhancementPrompt,
                            variables: ModelSettingsPromptVariables.enhancement
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
            }
        }
    }

    var translationContent: some View {
        featurePage(
            title: featureSettingsLocalized("Translation"),
            subtitle: featureSettingsLocalized("Configure the speech path, translation engine, target language, and prompt behavior for translation mode."),
            icon: "globe",
            pills: translationPills
        ) {
            FeatureSettingsCard(title: featureSettingsLocalized("Translation Flow")) {
                FeatureSettingSection(title: featureSettingsLocalized("Speech Recognition"), detail: featureSettingsLocalized("Choose the ASR model that feeds the translation pipeline.")) {
                    FeatureSelectorRow(
                        title: featureSettingsLocalized("ASR Model"),
                        value: asrSelectionSummary(featureSettings.translation.asrSelectionID),
                        action: { selectorSheet = .translationASR }
                    )
                }

                FeatureSettingSection(title: featureSettingsLocalized("Translation Model"), detail: featureSettingsLocalized("Select an LLM or use Whisper direct translation when the ASR path supports it.")) {
                    FeatureSelectorRow(
                        title: featureSettingsLocalized("Translation Model"),
                        value: translationSelectionSummary(featureSettings.translation.modelSelectionID),
                        action: { selectorSheet = .translationModel }
                    )
                }

                FeatureInlinePickerRow(title: featureSettingsLocalized("Target Language"), detail: featureSettingsLocalized("Move the shared translation language setting here so the behavior stays feature-local.")) {
                    SettingsMenuPicker(
                        selection: binding(
                            get: { featureSettings.translation.targetLanguage },
                            set: { featureSettings.translation.targetLanguageRawValue = $0.rawValue }
                        ),
                        options: TranslationTargetLanguage.allCases.map {
                            SettingsMenuOption(value: $0, title: $0.title)
                        },
                        selectedTitle: featureSettings.translation.targetLanguage.title,
                        width: 220
                    )
                }

                FeatureToggleRow(
                    title: featureSettingsLocalized("Replace Selected Text"),
                    detail: featureSettingsLocalized("Run translation directly against the current selected text when the translation shortcut is triggered."),
                    isOn: binding(
                        get: { featureSettings.translation.replaceSelectedText },
                        set: { featureSettings.translation.replaceSelectedText = $0 }
                    )
                )

                if featureSettings.translation.modelSelectionID.translationSelection != .whisperDirectTranslate {
                    FeatureSettingSection(title: featureSettingsLocalized("Prompt"), detail: featureSettingsLocalized("Prompt controls are shown only when the selected translation model supports prompt-based generation.")) {
                        FeaturePromptSection(
                            title: featureSettingsLocalized("Translation Prompt"),
                            text: binding(
                                get: { featureSettings.translation.prompt },
                                set: { featureSettings.translation.prompt = $0 }
                            ),
                            defaultText: AppPreferenceKey.defaultTranslationPrompt,
                            variables: ModelSettingsPromptVariables.translation
                        )
                    }
                } else {
                    FeatureHintBanner(
                        title: featureSettingsLocalized("Whisper Direct Translation"),
                        detail: featureSettingsLocalized("Prompt editing is hidden here because Whisper direct translation does not consume a text prompt.")
                    )
                }
            }
        }
    }

    var rewriteContent: some View {
        featurePage(
            title: featureSettingsLocalized("Rewrite"),
            subtitle: featureSettingsLocalized("Set the ASR and text model pairing used for rewrite mode, then decide whether app-aware enhancement is enabled."),
            icon: "text.badge.star",
            pills: rewritePills
        ) {
            FeatureSettingsCard(title: featureSettingsLocalized("Rewrite Flow")) {
                FeatureSettingSection(title: featureSettingsLocalized("Speech Recognition"), detail: featureSettingsLocalized("Choose the speech model that feeds rewrite mode.")) {
                    FeatureSelectorRow(
                        title: featureSettingsLocalized("ASR Model"),
                        value: asrSelectionSummary(featureSettings.rewrite.asrSelectionID),
                        action: { selectorSheet = .rewriteASR }
                    )
                }

                FeatureSettingSection(title: featureSettingsLocalized("Rewrite Model"), detail: featureSettingsLocalized("Pick the text model used to rewrite, rephrase, or clean captured content.")) {
                    FeatureSelectorRow(
                        title: featureSettingsLocalized("LLM Model"),
                        value: llmSelectionSummary(featureSettings.rewrite.llmSelectionID),
                        action: { selectorSheet = .rewriteLLM }
                    )
                }

                FeatureSettingSection(title: featureSettingsLocalized("Prompt"), detail: featureSettingsLocalized("Prompt templates stay local to rewrite mode and no longer live in the shared model page.")) {
                    FeaturePromptSection(
                        title: featureSettingsLocalized("Rewrite Prompt"),
                        text: binding(
                            get: { featureSettings.rewrite.prompt },
                            set: { featureSettings.rewrite.prompt = $0 }
                        ),
                        defaultText: AppPreferenceKey.defaultRewritePrompt,
                        variables: ModelSettingsPromptVariables.rewrite
                    )
                }

                FeatureToggleRow(
                    title: featureSettingsLocalized("Enable App Enhancement"),
                    detail: featureSettingsLocalized("When enabled, the dedicated App Enhancement submenu becomes available in Feature mode."),
                    isOn: binding(
                        get: { featureSettings.rewrite.appEnhancementEnabled },
                        set: { featureSettings.rewrite.appEnhancementEnabled = $0 }
                    )
                )

                FeatureContinueShortcutRow(
                    title: featureSettingsLocalized("Continue Shortcut"),
                    detail: featureSettingsLocalized("Use this key in rewrite continue mode to start the next follow-up recording from the OverLazy answer view."),
                    shortcut: binding(
                        get: { featureSettings.rewrite.continueShortcut },
                        set: { featureSettings.rewrite.continueShortcut = $0 }
                    )
                )
            }
        }
    }

    var meetingContent: some View {
        featurePage(
            title: featureSettingsLocalized("Meeting"),
            subtitle: featureSettingsLocalized("Meeting mode now owns its own ASR, summary model, prompt, and realtime translation settings."),
            icon: "person.2.crop.square.stack",
            pills: meetingPills
        ) {
            FeatureSettingsCard(title: featureSettingsLocalized("Meeting Workflow")) {
                FeatureSettingSection(title: featureSettingsLocalized("Speech Recognition"), detail: featureSettingsLocalized("Choose the ASR pipeline used only for meeting mode.")) {
                    FeatureSelectorRow(
                        title: featureSettingsLocalized("ASR Model"),
                        value: asrSelectionSummary(featureSettings.meeting.asrSelectionID),
                        action: { selectorSheet = .meetingASR }
                    )
                }

                FeatureSettingSection(title: featureSettingsLocalized("Summary Model"), detail: featureSettingsLocalized("This model is used for meeting summaries and is independent from transcription or rewrite models.")) {
                    FeatureSelectorRow(
                        title: featureSettingsLocalized("Summary Model"),
                        value: llmSelectionSummary(featureSettings.meeting.summaryModelSelectionID),
                        action: { selectorSheet = .meetingSummary }
                    )
                }

                FeatureToggleRow(
                    title: featureSettingsLocalized("Auto-generate Summary"),
                    detail: featureSettingsLocalized("Generate the meeting summary automatically when the session completes."),
                    isOn: binding(
                        get: { featureSettings.meeting.summaryAutoGenerate },
                        set: { featureSettings.meeting.summaryAutoGenerate = $0 }
                    )
                )

                FeatureToggleRow(
                    title: featureSettingsLocalized("Realtime Translation"),
                    detail: featureSettingsLocalized("Keep a live translated view during meetings using the meeting-specific translation target."),
                    isOn: binding(
                        get: { featureSettings.meeting.realtimeTranslateEnabled },
                        set: { featureSettings.meeting.realtimeTranslateEnabled = $0 }
                    )
                )

                FeatureInlinePickerRow(title: featureSettingsLocalized("Realtime Target"), detail: featureSettingsLocalized("Only used when realtime translation is enabled.")) {
                    SettingsMenuPicker(
                        selection: binding(
                            get: { featureSettings.meeting.realtimeTargetLanguage ?? .english },
                            set: { featureSettings.meeting.realtimeTargetLanguageRawValue = $0.rawValue }
                        ),
                        options: TranslationTargetLanguage.allCases.map {
                            SettingsMenuOption(value: $0, title: $0.title)
                        },
                        selectedTitle: (featureSettings.meeting.realtimeTargetLanguage ?? .english).title,
                        width: 220
                    )
                }

                FeatureToggleRow(
                    title: featureSettingsLocalized("Show Overlay In Screen Sharing"),
                    detail: featureSettingsLocalized("Keep the meeting overlay visible when sharing the screen. Turn this off when the overlay should stay private."),
                    isOn: binding(
                        get: { featureSettings.meeting.showOverlayInScreenShare },
                        set: { featureSettings.meeting.showOverlayInScreenShare = $0 }
                    )
                )

                FeatureSettingSection(title: featureSettingsLocalized("Summary Prompt"), detail: featureSettingsLocalized("Use prompt variables to shape the meeting summary format and focus.")) {
                    FeaturePromptSection(
                        title: featureSettingsLocalized("Summary Prompt"),
                        text: binding(
                            get: { featureSettings.meeting.summaryPrompt },
                            set: { featureSettings.meeting.summaryPrompt = $0 }
                        ),
                        defaultText: AppPreferenceKey.defaultMeetingSummaryPrompt,
                        variables: MeetingSummarySupport.promptTemplateVariables.map {
                            PromptTemplateVariableDescriptor(token: $0, tipKey: "Template tip \($0)")
                        }
                    )
                }
            }
        }
    }

    var transcriptionPills: [FeatureSummaryPill] {
        var pills = [
            FeatureSummaryPill(title: featureSettingsLocalized("ASR"), value: shortSummary(asrSelectionSummary(featureSettings.transcription.asrSelectionID)))
        ]
        pills.append(
            FeatureSummaryPill(
                title: featureSettingsLocalized("LLM"),
                value: featureSettings.transcription.llmEnabled
                    ? shortSummary(llmSelectionSummary(featureSettings.transcription.llmSelectionID))
                    : featureSettingsLocalized("Off")
            )
        )
        return pills
    }

    var notePills: [FeatureSummaryPill] {
        [
            FeatureSummaryPill(
                title: featureSettingsLocalized("Trigger"),
                value: shortSummary(
                    HotkeyPreference.displayString(
                        for: featureSettings.transcription.notes.triggerShortcut.hotkey,
                        distinguishModifierSides: false
                    )
                )
            ),
            FeatureSummaryPill(
                title: featureSettingsLocalized("Model"),
                value: shortSummary(llmSelectionSummary(featureSettings.transcription.notes.titleModelSelectionID))
            )
        ]
    }

    var translationPills: [FeatureSummaryPill] {
        [
            FeatureSummaryPill(title: featureSettingsLocalized("ASR"), value: shortSummary(asrSelectionSummary(featureSettings.translation.asrSelectionID))),
            FeatureSummaryPill(title: featureSettingsLocalized("Model"), value: shortSummary(translationSelectionSummary(featureSettings.translation.modelSelectionID))),
            FeatureSummaryPill(title: featureSettingsLocalized("Target"), value: featureSettings.translation.targetLanguage.title)
        ]
    }

    var rewritePills: [FeatureSummaryPill] {
        [
            FeatureSummaryPill(title: featureSettingsLocalized("ASR"), value: shortSummary(asrSelectionSummary(featureSettings.rewrite.asrSelectionID))),
            FeatureSummaryPill(title: featureSettingsLocalized("LLM"), value: shortSummary(llmSelectionSummary(featureSettings.rewrite.llmSelectionID))),
            FeatureSummaryPill(title: featureSettingsLocalized("App"), value: featureSettings.rewrite.appEnhancementEnabled ? featureSettingsLocalized("Enabled") : featureSettingsLocalized("Disabled"))
        ]
    }

    var meetingPills: [FeatureSummaryPill] {
        [
            FeatureSummaryPill(title: featureSettingsLocalized("ASR"), value: shortSummary(asrSelectionSummary(featureSettings.meeting.asrSelectionID))),
            FeatureSummaryPill(title: featureSettingsLocalized("Summary"), value: shortSummary(llmSelectionSummary(featureSettings.meeting.summaryModelSelectionID)))
        ]
    }

    func shortSummary(_ text: String) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count > 28 else { return value }
        return String(value.prefix(25)) + "..."
    }

    @ViewBuilder
    func featurePage<Content: View>(
        title: String,
        subtitle: String,
        icon: String,
        pills: [FeatureSummaryPill],
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FeatureHeroCard(
                    title: title,
                    subtitle: subtitle,
                    icon: icon,
                    pills: pills
                )

                content()
            }
            .padding(.top, 2)
            .padding(.bottom, 12)
        }
        .background(SettingsUIStyle.groupedFillColor.opacity(0.001))
    }

    var transcriptionLLMEnabledBinding: Binding<Bool> {
        binding(
            get: { featureSettings.transcription.llmEnabled },
            set: { featureSettings.transcription.llmEnabled = $0 }
        )
    }

    @ViewBuilder
    var noteObsidianSyncSection: some View {
        FeatureEmbeddedFieldGroup {
            FeatureToggleRow(
                title: featureSettingsLocalized("Enable Obsidian Sync"),
                detail: featureSettingsLocalized("Export Voxt notes into an Obsidian vault by writing Markdown files directly into the selected folder."),
                isOn: binding(
                    get: { featureSettings.transcription.notes.obsidianSync.enabled },
                    set: { featureSettings.transcription.notes.obsidianSync.enabled = $0 }
                ),
                isEmbedded: true
            )

            if featureSettings.transcription.notes.obsidianSync.enabled {
                FeatureDirectorySelectionRow(
                    title: featureSettingsLocalized("Vault Folder"),
                    detail: featureSettingsLocalized("Choose the Obsidian vault root folder that should receive exported Voxt notes."),
                    path: featureSettings.transcription.notes.obsidianSync.vaultPath.isEmpty
                        ? featureSettingsLocalized("Not configured")
                        : featureSettings.transcription.notes.obsidianSync.vaultPath,
                    buttonTitle: featureSettingsLocalized("Choose"),
                    action: chooseObsidianVaultDirectory,
                    isEmbedded: true
                )

                FeatureInlineTextFieldRow(
                    title: featureSettingsLocalized("Target Folder"),
                    detail: featureSettingsLocalized("Choose where inside the vault Voxt should write exported notes."),
                    text: binding(
                        get: { featureSettings.transcription.notes.obsidianSync.relativeFolder },
                        set: { featureSettings.transcription.notes.obsidianSync.relativeFolder = $0 }
                    ),
                    placeholder: "Voxt",
                    width: 230,
                    isEmbedded: true
                )

                FeatureInlinePickerRow(
                    title: featureSettingsLocalized("Grouping Mode"),
                    detail: featureSettingsLocalized("Choose how exported notes are organized inside Obsidian."),
                    isEmbedded: true
                ) {
                    SettingsMenuPicker(
                        selection: binding(
                            get: { featureSettings.transcription.notes.obsidianSync.groupingMode },
                            set: { featureSettings.transcription.notes.obsidianSync.groupingMode = $0 }
                        ),
                        options: ObsidianNoteGroupingMode.allCases.map {
                            SettingsMenuOption(value: $0, title: $0.title)
                        },
                        selectedTitle: featureSettings.transcription.notes.obsidianSync.groupingMode.title,
                        width: 220
                    )
                }
            }
        }
    }
}

private extension ObsidianNoteGroupingMode {
    var title: String {
        switch self {
        case .session:
            return featureSettingsLocalized("Session")
        case .daily:
            return featureSettingsLocalized("Daily")
        case .file:
            return featureSettingsLocalized("Single Note File")
        }
    }
}
