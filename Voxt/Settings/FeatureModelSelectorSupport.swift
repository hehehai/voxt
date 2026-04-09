import SwiftUI

private func localized(_ key: String) -> String {
    AppLocalization.localizedString(key)
}

enum FeatureModelSelectorSheet: String, Identifiable {
    case transcriptionASR
    case transcriptionLLM
    case translationASR
    case translationModel
    case rewriteASR
    case rewriteLLM
    case meetingASR
    case meetingSummary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transcriptionASR: return localized("Choose Transcription ASR")
        case .transcriptionLLM: return localized("Choose Transcription LLM")
        case .translationASR: return localized("Choose Translation ASR")
        case .translationModel: return localized("Choose Translation Model")
        case .rewriteASR: return localized("Choose Rewrite ASR")
        case .rewriteLLM: return localized("Choose Rewrite LLM")
        case .meetingASR: return localized("Choose Meeting ASR")
        case .meetingSummary: return localized("Choose Meeting Summary Model")
        }
    }
}

struct FeatureModelSelectorEntry: Identifiable {
    let selectionID: FeatureModelSelectionID
    let title: String
    let engine: String
    let sizeText: String
    let ratingText: String
    let filterTags: [String]
    let displayTags: [String]
    let statusText: String
    let usageLocations: [String]
    let isSelectable: Bool
    let disabledReason: String?

    var id: String { selectionID.rawValue }
}
