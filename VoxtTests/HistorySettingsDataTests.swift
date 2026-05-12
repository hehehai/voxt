import XCTest
@testable import Voxt

final class HistorySettingsDataTests: XCTestCase {
    func testFilteredEntriesUsesSelectedHistoryTab() {
        let entries = [
            makeHistoryEntry(kind: .normal, text: "a"),
            makeHistoryEntry(kind: .translation, text: "b"),
            makeHistoryEntry(kind: .rewrite, text: "c"),
            makeHistoryEntry(kind: .transcript, text: "d")
        ]

        XCTAssertEqual(
            HistorySettingsData.filteredEntries(for: .transcription, allEntries: entries).map(\.text),
            ["a"]
        )
        XCTAssertEqual(
            HistorySettingsData.filteredEntries(for: .translation, allEntries: entries).map(\.text),
            ["b"]
        )
        XCTAssertEqual(
            HistorySettingsData.filteredEntries(for: .rewrite, allEntries: entries).map(\.text),
            ["c"]
        )
        XCTAssertEqual(
            HistorySettingsData.filteredEntries(for: .note, allEntries: entries).map(\.text),
            []
        )
    }

    func testEmptyStatePrefersHistoryAndNoteSpecificMessages() {
        let note = makeNote(title: "todo")
        let entry = makeHistoryEntry(kind: .normal, text: "Voxt")

        XCTAssertEqual(
            HistorySettingsData.emptyState(
                selectedFilter: .note,
                allEntries: [],
                filteredEntries: [],
                notes: []
            ),
            .noNotes
        )
        XCTAssertEqual(
            HistorySettingsData.emptyState(
                selectedFilter: .transcription,
                allEntries: [],
                filteredEntries: [],
                notes: [note]
            ),
            .noHistory
        )
        XCTAssertEqual(
            HistorySettingsData.emptyState(
                selectedFilter: .rewrite,
                allEntries: [entry],
                filteredEntries: [],
                notes: [note]
            ),
            .noEntriesInCategory
        )
        XCTAssertEqual(
            HistorySettingsData.emptyState(
                selectedFilter: .note,
                allEntries: [entry],
                filteredEntries: [entry],
                notes: [note]
            ),
            .none
        )
    }

    func testPaginationHelpersRespectLimits() {
        let values = Array(0..<5)

        XCTAssertEqual(HistorySettingsData.visibleEntries(from: values, visibleLimit: 3), [0, 1, 2])
        XCTAssertTrue(HistorySettingsData.hasMoreItems(in: values, visibleLimit: 3))
        XCTAssertEqual(HistorySettingsData.nextVisibleLimit(currentLimit: 3, pageSize: 2, totalCount: 5), 5)
        XCTAssertEqual(HistorySettingsData.normalizedVisibleLimit(currentLimit: 1, pageSize: 4, totalCount: 2), 4)
    }
}

private extension HistorySettingsDataTests {
    func makeHistoryEntry(kind: TranscriptionHistoryKind, text: String) -> TranscriptionHistoryEntry {
        TranscriptionHistoryEntry(
            id: UUID(),
            text: text,
            createdAt: Date(timeIntervalSince1970: 1),
            transcriptionEngine: "engine",
            transcriptionModel: "model",
            enhancementMode: "mode",
            enhancementModel: "enhanced",
            kind: kind,
            isTranslation: kind == .translation,
            audioDurationSeconds: nil,
            transcriptionProcessingDurationSeconds: nil,
            llmDurationSeconds: nil,
            focusedAppName: nil,
            focusedAppBundleID: nil,
            matchedGroupID: nil,
            matchedGroupName: nil,
            matchedAppGroupName: nil,
            matchedURLGroupName: nil,
            remoteASRProvider: nil,
            remoteASRModel: nil,
            remoteASREndpoint: nil,
            remoteLLMProvider: nil,
            remoteLLMModel: nil,
            remoteLLMEndpoint: nil,
            audioRelativePath: nil,
            whisperWordTimings: nil,
            dictionaryHitTerms: [],
            dictionaryCorrectedTerms: [],
            dictionarySuggestedTerms: []
        )
    }

    func makeNote(title: String) -> VoxtNoteItem {
        VoxtNoteItem(
            id: UUID(),
            sessionID: UUID(),
            createdAt: Date(timeIntervalSince1970: 1),
            text: title,
            title: title,
            titleGenerationState: .generated
        )
    }
}
