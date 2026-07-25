// FeatureAvailabilitySections.swift
// Provides the Feature master-toggle grid for Custom → Feature.

import SwiftUI

extension FeatureSettingsView {
    var featuresContent: some View {
        featurePage(
            title: AppLocalization.localizedString("Feature"),
            subtitle: AppLocalization.localizedString("Choose which features are available in Voxt."),
            iconKind: .features,
            pills: [],
            showsHeroHeader: false
        ) {
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                alignment: .leading,
                spacing: 12
            ) {
                ForEach(FeatureAvailabilityCardKind.allCases) { kind in
                    FeatureAvailabilityCard(
                        kind: kind,
                        isEnabled: binding(for: kind)
                    )
                }
            }
        }
    }

    private func binding(for kind: FeatureAvailabilityCardKind) -> Binding<Bool>? {
        switch kind {
        case .transcription:
            return nil
        case .translation:
            return binding(
                get: { featureSettings.availability.translationEnabled },
                set: { featureSettings.availability.translationEnabled = $0 }
            )
        case .rewrite:
            return binding(
                get: { featureSettings.availability.rewriteEnabled },
                set: { featureSettings.availability.rewriteEnabled = $0 }
            )
        case .note:
            return binding(
                get: { featureSettings.availability.notesEnabled },
                set: { enabled in
                    featureSettings.availability.notesEnabled = enabled
                    featureSettings.transcription.notes.enabled = enabled
                }
            )
        case .appEnhancement:
            return binding(
                get: { featureSettings.availability.appEnhancementEnabled },
                set: { enabled in
                    featureSettings.availability.appEnhancementEnabled = enabled
                    featureSettings.rewrite.appEnhancementEnabled = enabled
                }
            )
        case .meeting:
            return binding(
                get: { featureSettings.availability.meetingEnabled },
                set: { featureSettings.availability.meetingEnabled = $0 }
            )
        }
    }
}

enum FeatureAvailabilityCardKind: String, CaseIterable, Identifiable {
    case transcription
    case translation
    case rewrite
    case note
    case appEnhancement
    case meeting

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .transcription: return "Transcription"
        case .translation: return "Translation"
        case .rewrite: return "Rewrite"
        case .note: return "Notes"
        case .appEnhancement: return "App Enhancement"
        case .meeting: return "Meeting"
        }
    }

    var title: String {
        AppLocalization.localizedString(titleKey)
    }

    var iconKind: SettingsSidebarIconKind {
        switch self {
        case .transcription: return .transcription
        case .translation: return .translation
        case .rewrite: return .rewrite
        case .note: return .note
        case .appEnhancement: return .appEnhancement
        case .meeting: return .meeting
        }
    }

    var showsToggle: Bool {
        self != .transcription
    }
}

struct FeatureAvailabilityCard: View {
    let kind: FeatureAvailabilityCardKind
    let isEnabled: Binding<Bool>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SettingsSidebarIconView(kind: kind.iconKind)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18, height: 18)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    )

                Text(kind.title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)

                if kind.showsToggle, let isEnabled {
                    Toggle("", isOn: isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous)
                .fill(SettingsUIStyle.controlFillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsUIStyle.compactCornerRadius, style: .continuous)
                .stroke(SettingsUIStyle.subtleBorderColor, lineWidth: 1)
        )
    }
}
