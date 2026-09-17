import Foundation

nonisolated enum MeetingFileSpeakerMode: String, CaseIterable, Identifiable {
    case analyze
    case later
    case off

    static let preferenceKey = "fileSpeakerAnalysisMode"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .analyze: return AppLocalization.localizedString("Analyze speakers when safe")
        case .later: return AppLocalization.localizedString("Analyze speakers later")
        case .off: return AppLocalization.localizedString("Transcription only")
        }
    }
}
