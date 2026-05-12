import SwiftUI

extension FeatureSettingsView {
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

                FeatureEmbeddedFieldGroup {
                    FeatureToggleRow(
                        title: featureSettingsLocalized("Translate selected text with translation shortcut"),
                        detail: featureSettingsLocalized("If text is selected, the translation shortcut translates the selection directly instead of starting a recording."),
                        isOn: binding(
                            get: { featureSettings.translation.replaceSelectedText },
                            set: { featureSettings.translation.replaceSelectedText = $0 }
                        )
                    )

                    if featureSettings.translation.replaceSelectedText {
                        FeatureToggleRow(
                            title: featureSettingsLocalized("Replace Selected Text"),
                            detail: featureSettingsLocalized("When enabled, selected-text translation replaces the current selection directly. When disabled, Voxt opens a result window after completion instead."),
                            isOn: binding(
                                get: { !featureSettings.translation.showResultWindow },
                                set: { featureSettings.translation.showResultWindow = !$0 }
                            )
                        )
                    }
                }

                if featureSettings.translation.modelSelectionID.translationSelection != .whisperDirectTranslate {
                    FeatureSettingSection(title: featureSettingsLocalized("Prompt"), detail: featureSettingsLocalized("Prompt controls are shown only when the selected translation model supports prompt-based generation.")) {
                        FeaturePromptSection(
                            title: featureSettingsLocalized("Translation Prompt"),
                            text: promptBinding(
                                get: { featureSettings.translation.prompt },
                                set: { featureSettings.translation.prompt = $0 },
                                kind: .translation
                            ),
                            defaultText: AppPromptDefaults.text(for: .translation),
                            variables: ModelSettingsPromptVariables.translation,
                            guidance: PromptAuthoringGuidance.translation,
                            persistChanges: saveFeatureSettings
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
            subtitle: featureSettingsLocalized("Set the ASR and text model pairing used for rewrite mode, then tune the rewrite-specific prompt and follow-up shortcut."),
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
                        text: promptBinding(
                            get: { featureSettings.rewrite.prompt },
                            set: { featureSettings.rewrite.prompt = $0 },
                            kind: .rewrite
                        ),
                        defaultText: AppPromptDefaults.text(for: .rewrite),
                        variables: ModelSettingsPromptVariables.rewrite,
                        guidance: PromptAuthoringGuidance.rewrite,
                        persistChanges: saveFeatureSettings
                    )
                }

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
}
