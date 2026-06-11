import SwiftUI

extension FeatureSettingsView {
    var meetingContent: some View {
        featurePage(
            title: featureSettingsLocalized("Meeting"),
            subtitle: featureSettingsLocalized("Capture microphone and system audio into a speaker-labelled transcript."),
            systemImageName: "person.2.wave.2",
            pills: meetingPills,
            showsHeroHeader: false
        ) {
            FeatureSettingsCard(title: "") {
                HStack(spacing: 8) {
                    Text(featureSettingsLocalized("Meeting Mode"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary.opacity(0.92))

                    Text(featureSettingsLocalized("Beta"))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.accentColor.opacity(0.14))
                        )
                        .foregroundStyle(Color.accentColor)

                    Spacer(minLength: 0)
                }

                FeatureSettingSection(title: "", detail: "") {
                    FeatureSelectorRow(
                        title: featureSettingsLocalized("Speech Model"),
                        value: asrSelectionSummary(featureSettings.meeting.asrSelectionID),
                        action: { selectorSheet = .meetingASR }
                    )

                    FeatureSelectorRow(
                        title: featureSettingsLocalized("Summary Model"),
                        value: llmSelectionSummary(featureSettings.meeting.summaryModelSelectionID),
                        action: { selectorSheet = .meetingSummary }
                    )
                }

                FeatureToggleRow(
                    title: featureSettingsLocalized("Hide Floating Window from Screen Sharing"),
                    detail: "",
                    isOn: binding(
                        get: { featureSettings.meeting.hideOverlayFromScreenSharing },
                        set: { featureSettings.meeting.hideOverlayFromScreenSharing = $0 }
                    )
                )

                FeatureToggleRow(
                    title: featureSettingsLocalized("Realtime Translation"),
                    detail: "",
                    isOn: binding(
                        get: { featureSettings.meeting.realtimeTranslateEnabled },
                        set: { featureSettings.meeting.realtimeTranslateEnabled = $0 }
                    )
                )

                if featureSettings.meeting.realtimeTranslateEnabled {
                    FeatureInlinePickerRow(
                        title: featureSettingsLocalized("Translation Target"),
                        detail: ""
                    ) {
                        SettingsMenuPicker(
                            selection: meetingRealtimeTranslationTargetLanguage,
                            options: TranslationTargetLanguage.allCases.map {
                                SettingsMenuOption(value: $0, title: $0.title)
                            },
                            selectedTitle: meetingRealtimeTranslationTargetLanguage.wrappedValue.title,
                            width: 220
                        )
                    }
                }

                FeatureToggleRow(
                    title: featureSettingsLocalized("Auto-generate Summary"),
                    detail: "",
                    isOn: binding(
                        get: { featureSettings.meeting.summaryAutoGenerate },
                        set: { featureSettings.meeting.summaryAutoGenerate = $0 }
                    )
                )
            }
        }
    }

    var meetingPills: [FeatureSummaryPill] {
        [
            FeatureSummaryPill(
                title: featureSettingsLocalized("Audio Model"),
                value: shortSummary(asrSelectionSummary(featureSettings.meeting.asrSelectionID), maxLength: 52)
            ),
            FeatureSummaryPill(
                title: featureSettingsLocalized("Summary Model"),
                value: shortSummary(llmSelectionSummary(featureSettings.meeting.summaryModelSelectionID), maxLength: 52)
            ),
            FeatureSummaryPill(
                title: featureSettingsLocalized("Translate"),
                value: featureSettings.meeting.realtimeTranslateEnabled
                    ? meetingRealtimeTranslationTargetLanguage.wrappedValue.title
                    : featureSettingsLocalized("Off")
            )
        ]
    }

    var meetingRealtimeTranslationTargetLanguage: Binding<TranslationTargetLanguage> {
        Binding(
            get: {
                let rawValue = featureSettings.meeting.realtimeTargetLanguageRawValue
                guard let language = TranslationTargetLanguage(rawValue: rawValue),
                      !rawValue.isEmpty
                else {
                    return .english
                }
                return language
            },
            set: { language in
                featureSettings.meeting.realtimeTargetLanguageRawValue = language.rawValue
                saveFeatureSettings()
            }
        )
    }
}
