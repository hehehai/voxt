import SwiftUI

extension FeatureSettingsView {
    var translationContent: some View {
        featurePage(
            title: featureSettingsLocalized("Translation"),
            subtitle: featureSettingsLocalized("Configure the speech path, translation engine, target language, and prompt behavior for translation mode."),
            iconKind: .translation,
            pills: translationPills,
            showsHeroHeader: false
        ) {
            FeatureSettingsCard(title: "") {
                FeatureSettingSection(title: "", detail: "") {
                    FeatureSelectorRow(
                        title: featureSettingsLocalized("Speech Model"),
                        value: asrSelectionSummary(featureSettings.translation.asrSelectionID),
                        action: { selectorSheet = .translationASR }
                    )
                }

                FeatureSettingSection(title: "", detail: "") {
                    FeatureSelectorRow(
                        title: featureSettingsLocalized("Translation Model"),
                        value: translationSelectionSummary(featureSettings.translation.modelSelectionID),
                        action: { selectorSheet = .translationModel }
                    )
                }

                FeatureInlinePickerRow(title: featureSettingsLocalized("Target Language"), detail: "") {
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
                        title: featureSettingsLocalized("Show Translation Result for Selected Text"),
                        detail: "",
                        isOn: binding(
                            get: { featureSettings.translation.showResultWindow },
                            set: { featureSettings.translation.showResultWindow = $0 }
                        )
                    )
                }

                if featureSettings.translation.modelSelectionID.translationSelection != .whisperDirectTranslate {
                    FeatureSettingSection(title: "", detail: "") {
                        FeaturePromptSection(
                            title: featureSettingsLocalized("Translation Prompt"),
                            text: promptBinding(
                                get: { featureSettings.translation.prompt },
                                set: { featureSettings.translation.prompt = $0 },
                                kind: .translation
                            ),
                            defaultText: AppPromptDefaults.text(for: .translation),
                            variables: ModelSettingsPromptVariables.translation,
                            guidance: "",
                            persistChanges: { prompt in
                                FeatureSettingsStore.saveTranslationPrompt(prompt)
                            }
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
            iconKind: .rewrite,
            pills: rewritePills,
            showsHeroHeader: false
        ) {
            FeatureSettingsCard(title: "") {
                FeatureSettingSection(title: "", detail: "") {
                    FeatureSelectorRow(
                        title: featureSettingsLocalized("Speech Model"),
                        value: asrSelectionSummary(featureSettings.rewrite.asrSelectionID),
                        action: { selectorSheet = .rewriteASR }
                    )
                }

                FeatureSettingSection(title: "", detail: "") {
                    FeatureSelectorRow(
                        title: featureSettingsLocalized("Enhancement Model"),
                        value: llmSelectionSummary(featureSettings.rewrite.llmSelectionID),
                        action: { selectorSheet = .rewriteLLM }
                    )
                }

                FeatureSettingSection(title: "", detail: "") {
                    FeaturePromptSection(
                        title: featureSettingsLocalized("Rewrite Prompt"),
                        text: promptBinding(
                            get: { featureSettings.rewrite.prompt },
                            set: { featureSettings.rewrite.prompt = $0 },
                            kind: .rewrite
                        ),
                        defaultText: AppPromptDefaults.text(for: .rewrite),
                        variables: ModelSettingsPromptVariables.rewrite,
                        guidance: "",
                        persistChanges: { prompt in
                            FeatureSettingsStore.saveRewritePrompt(prompt)
                        }
                    )
                }

                FeatureContinueShortcutRow(
                    title: featureSettingsLocalized("Continue Shortcut"),
                    detail: "",
                    shortcut: binding(
                        get: { featureSettings.rewrite.continueShortcut },
                        set: { featureSettings.rewrite.continueShortcut = $0 }
                    )
                )

                FeatureDisclosureSection(
                    title: featureSettingsLocalized("Context Enhancement"),
                    badgeText: featureSettingsLocalized("Experimental"),
                    detail: featureSettingsLocalized("Current focused app information"),
                    onExpand: requestScrollToBottom
                ) {
                    FeatureToggleRow(
                        title: featureSettingsLocalized("Content Text"),
                        detail: "",
                        isOn: binding(
                            get: { featureSettings.rewrite.appContext.textEnabled },
                            set: { featureSettings.rewrite.appContext.textEnabled = $0 }
                        ),
                        isEmbedded: true
                    )

                    FeatureToggleRow(
                        title: featureSettingsLocalized("Screenshot"),
                        badgeText: rewriteScreenshotContextBadgeText,
                        detail: "",
                        isOn: binding(
                            get: { featureSettings.rewrite.appContext.screenshotEnabled },
                            set: { featureSettings.rewrite.appContext.screenshotEnabled = $0 }
                        ),
                        isEmbedded: true
                    )
                }
            }
        }
    }
}
