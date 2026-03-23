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
        MeetingTranscriptFormatter.mergedSegmentsForPersistence(
            primarySegments: segments,
            fallbackSegments: visibleSnapshotSegments
        )
    }

    var combinedText: String {
        MeetingTranscriptFormatter.joinedText(for: persistedSegments)
    }
}

@MainActor
final class MeetingOverlayState: ObservableObject {
    @Published var isPresented = false
    @Published var isRecording = false
    @Published var isModelInitializing = false
    @Published var isPaused = false
    @Published var isCollapsed = false
    @Published var audioLevel: Float = 0
    @Published var realtimeTranslateEnabled = false
    @Published var isRealtimeTranslationLanguagePickerPresented = false
    @Published var isCloseConfirmationPresented = false
    @Published var realtimeTranslationDraftLanguageRaw = TranslationTargetLanguage.english.rawValue
    @Published var segments: [MeetingTranscriptSegment] = []

    let waveformState = RecentAudioWaveformState()

    func reset() {
        isPresented = false
        isRecording = false
        isModelInitializing = false
        isPaused = false
        isCollapsed = false
        audioLevel = 0
        waveformState.reset()
        waveformState.setActive(false)
        realtimeTranslateEnabled = false
        isRealtimeTranslationLanguagePickerPresented = false
        isCloseConfirmationPresented = false
        realtimeTranslationDraftLanguageRaw = TranslationTargetLanguage.english.rawValue
        segments = []
    }
}
