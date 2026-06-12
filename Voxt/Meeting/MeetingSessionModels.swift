import Foundation
import Combine

struct MeetingSessionResult {
    let transcriptionEngine: TranscriptionEngine
    let transcriptionModelDescription: String
    let segments: [MeetingTranscriptSegment]
    let visibleSnapshotSegments: [MeetingTranscriptSegment]
    let audioDurationSeconds: TimeInterval
    let archivedAudioURL: URL?

    var persistedSegments: [MeetingTranscriptSegment] {
        let primarySegments = MeetingTranscriptFormatter.meaningfulSegments(for: segments)
        if !primarySegments.isEmpty {
            return primarySegments
        }
        return MeetingTranscriptFormatter.mergedSegmentsForPersistence(
            primarySegments: segments,
            fallbackSegments: visibleSnapshotSegments
        )
    }

    var combinedText: String {
        MeetingTranscriptFormatter.joinedText(for: persistedSegments)
    }
}

enum MeetingCaptureMode: String, CaseIterable, Identifiable, Sendable {
    case meeting
    case subtitles
    case recording

    var id: String { rawValue }

    var usesMicrophone: Bool {
        switch self {
        case .meeting, .recording:
            return true
        case .subtitles:
            return false
        }
    }

    var usesSystemAudio: Bool {
        switch self {
        case .meeting, .subtitles:
            return true
        case .recording:
            return false
        }
    }

    func includes(speaker: MeetingSpeaker) -> Bool {
        switch speaker {
        case .me:
            return usesMicrophone
        case .them:
            return usesSystemAudio
        }
    }

    var title: String {
        switch self {
        case .meeting:
            return AppLocalization.localizedString("Meeting")
        case .subtitles:
            return AppLocalization.localizedString("Subtitles")
        case .recording:
            return AppLocalization.localizedString("Recording")
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .meeting:
            return AppLocalization.localizedString("Record microphone and system audio.")
        case .subtitles:
            return AppLocalization.localizedString("Record system audio only.")
        case .recording:
            return AppLocalization.localizedString("Record microphone only.")
        }
    }

    var sourceDescription: String {
        switch self {
        case .meeting:
            return AppLocalization.localizedString("Built-in audio + microphone")
        case .subtitles:
            return AppLocalization.localizedString("Built-in audio only")
        case .recording:
            return AppLocalization.localizedString("Microphone only")
        }
    }

    static func stored(in defaults: UserDefaults = .standard) -> MeetingCaptureMode {
        let rawValue = defaults.string(forKey: AppPreferenceKey.meetingCaptureMode) ?? ""
        return MeetingCaptureMode(rawValue: rawValue) ?? .meeting
    }

    func persist(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: AppPreferenceKey.meetingCaptureMode)
    }
}

@MainActor
final class MeetingOverlayState: ObservableObject {
    @Published var isPresented = false
    @Published var isRecording = false
    @Published var isModelInitializing = false
    @Published var isFinalizing = false
    @Published var isPaused = false
    @Published var isCollapsed = false
    @Published var audioLevel: Float = 0
    @Published var realtimeTranslateEnabled = false
    @Published var captureMode: MeetingCaptureMode = .meeting
    @Published var isCaptureModePickerPresented = false
    @Published var isRealtimeTranslationLanguagePickerPresented = false
    @Published var isCloseConfirmationPresented = false
    @Published var realtimeTranslationDraftLanguageRaw = TranslationTargetLanguage.english.rawValue
    @Published var segments: [MeetingTranscriptSegment] = []

    let waveformState = RecentAudioWaveformState()

    func reset() {
        isPresented = false
        isRecording = false
        isModelInitializing = false
        isFinalizing = false
        isPaused = false
        isCollapsed = false
        audioLevel = 0
        waveformState.reset()
        waveformState.setActive(false)
        realtimeTranslateEnabled = false
        captureMode = .meeting
        isCaptureModePickerPresented = false
        isRealtimeTranslationLanguagePickerPresented = false
        isCloseConfirmationPresented = false
        realtimeTranslationDraftLanguageRaw = TranslationTargetLanguage.english.rawValue
        segments = []
    }
}
