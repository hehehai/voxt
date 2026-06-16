// VoxtNoteStoreTests.swift
// Provides Voxt Note Store Tests for Voxt test coverage.

import XCTest
@testable import Voxt

@MainActor
final class VoxtNoteStoreTests: XCTestCase {
    func testAppendUpdateDeleteAndReloadPersistedNotes() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appendingPathComponent("voxt-notes.json")

        let sessionID = UUID()
        let store = VoxtNoteStore(fileURL: fileURL)
        let item = try XCTUnwrap(
            store.append(
                sessionID: sessionID,
                text: "Schedule design review for Friday afternoon.",
                title: "Schedule design review",
                titleGenerationState: .pending
            )
        )

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.titleGenerationState, .pending)

        _ = store.updateTitle("Friday design review", state: .generated, for: item.id)
        XCTAssertEqual(store.items.first?.title, "Friday design review")
        XCTAssertEqual(store.items.first?.titleGenerationState, .generated)

        try await Task.sleep(for: .milliseconds(450))

        let reloadedStore = VoxtNoteStore(fileURL: fileURL)
        XCTAssertEqual(reloadedStore.items.count, 1)
        XCTAssertEqual(reloadedStore.items.first?.title, "Friday design review")
        XCTAssertEqual(reloadedStore.items.first?.sessionID, sessionID)
        XCTAssertFalse(reloadedStore.items.first?.isCompleted ?? true)

        _ = reloadedStore.updateCompletion(true, for: item.id)
        XCTAssertTrue(reloadedStore.items.first?.isCompleted ?? false)
        XCTAssertTrue(reloadedStore.incompleteItems.isEmpty)

        reloadedStore.delete(id: item.id)
        XCTAssertTrue(reloadedStore.items.isEmpty)
    }

    func testFallbackTitlePrefersSentencePrefix() {
        XCTAssertEqual(
            VoxtNoteTitleSupport.fallbackTitle(from: "Call Alice about the roadmap. Also share the draft."),
            "Call Alice about the roadmap"
        )
    }
}
