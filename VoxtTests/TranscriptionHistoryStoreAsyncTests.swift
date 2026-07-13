// TranscriptionHistoryStoreAsyncTests.swift

import Foundation
import XCTest
@testable import Voxt

@MainActor
final class TranscriptionHistoryStoreAsyncTests: XCTestCase {
    func testClearAllInvalidatesInFlightReloadSnapshot() async throws {
        let repository = try makeFixture(entries: [makeEntry(index: 0)])
        let store = TranscriptionHistoryStore(repository: repository)

        repository.blockNextEntriesRequest()
        store.reloadAsync()
        XCTAssertTrue(repository.waitUntilRequestIsBlocked())

        store.clearAll()
        repository.releaseBlockedRequest()
        await drainMainQueue()

        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertFalse(store.hasMore)
    }

    func testMutationInvalidatesInFlightNextPage() async throws {
        let entries = (0..<80).map(makeEntry(index:))
        let target = entries[50]
        let repository = try makeFixture(entries: entries)
        let store = TranscriptionHistoryStore(repository: repository)
        XCTAssertEqual(store.entries.count, 40)

        repository.blockNextEntriesRequest()
        store.loadNextPage()
        XCTAssertTrue(repository.waitUntilRequestIsBlocked())

        XCTAssertTrue(store.delete(id: target.id))
        repository.releaseBlockedRequest()
        await drainMainQueue()

        XCTAssertNil(store.entry(id: target.id))
        XCTAssertEqual(store.entries.count, 40)
        XCTAssertTrue(store.hasMore)
    }

    private func makeFixture(entries: [TranscriptionHistoryEntry]) throws -> BlockingHistoryRepository {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxt-history-async-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let database = VoxtDatabase(databaseURL: directoryURL.appendingPathComponent("history.sqlite"))
        let baseRepository = HistoryRepository(database: database, legacyJSONURL: nil, migrateLegacyJSON: false)
        try baseRepository.replaceAll(entries)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        return BlockingHistoryRepository(base: baseRepository)
    }

    private func makeEntry(index: Int) -> TranscriptionHistoryEntry {
        TranscriptionHistoryEntry(
            id: UUID(),
            text: "entry-\(index)",
            createdAt: Date().addingTimeInterval(TimeInterval(-index)),
            transcriptionEngine: "engine",
            transcriptionModel: "model",
            enhancementMode: "off",
            enhancementModel: "none",
            kind: .normal,
            isTranslation: false,
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

    private func drainMainQueue() async {
        for _ in 0..<20 {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class BlockingHistoryRepository: HistoryRepositoryProtocol, @unchecked Sendable {
    private let base: HistoryRepositoryProtocol
    private let lock = NSLock()
    private let requestStarted = DispatchSemaphore(value: 0)
    private let requestRelease = DispatchSemaphore(value: 0)
    private var shouldBlockNextEntriesRequest = false

    init(base: HistoryRepositoryProtocol) {
        self.base = base
    }

    func blockNextEntriesRequest() {
        lock.withLock {
            shouldBlockNextEntriesRequest = true
        }
    }

    func waitUntilRequestIsBlocked() -> Bool {
        requestStarted.wait(timeout: .now() + 2) == .success
    }

    func releaseBlockedRequest() {
        requestRelease.signal()
    }

    func entries(
        kind: TranscriptionHistoryKind?,
        query: String,
        limit: Int?,
        offset: Int
    ) throws -> [TranscriptionHistoryEntry] {
        let snapshot = try base.entries(kind: kind, query: query, limit: limit, offset: offset)
        let shouldBlock = lock.withLock {
            let value = shouldBlockNextEntriesRequest
            shouldBlockNextEntriesRequest = false
            return value
        }
        if shouldBlock {
            requestStarted.signal()
            _ = requestRelease.wait(timeout: .now() + 2)
        }
        return snapshot
    }

    func entry(id: UUID) throws -> TranscriptionHistoryEntry? {
        try base.entry(id: id)
    }

    func latestEntryText() throws -> String? {
        try base.latestEntryText()
    }

    func audioRelativePaths() throws -> [String] {
        try base.audioRelativePaths()
    }

    func entryCount(kind: TranscriptionHistoryKind?, query: String) throws -> Int {
        try base.entryCount(kind: kind, query: query)
    }

    func pendingNormalEntryCount(after checkpoint: DictionaryHistoryScanCheckpoint?) throws -> Int {
        try base.pendingNormalEntryCount(after: checkpoint)
    }

    func pendingNormalEntries(after checkpoint: DictionaryHistoryScanCheckpoint?) throws -> [TranscriptionHistoryEntry] {
        try base.pendingNormalEntries(after: checkpoint)
    }

    func reportMetrics(dayStarts: [Date], branchStartDate: Date?) throws -> HistoryReportMetrics {
        try base.reportMetrics(dayStarts: dayStarts, branchStartDate: branchStartDate)
    }

    func upsert(_ entry: TranscriptionHistoryEntry) throws {
        try base.upsert(entry)
    }

    func delete(id: UUID) throws -> TranscriptionHistoryEntry? {
        try base.delete(id: id)
    }

    func clearAll() throws {
        try base.clearAll()
    }

    func deleteEntries(olderThan cutoff: Date) throws -> [TranscriptionHistoryEntry] {
        try base.deleteEntries(olderThan: cutoff)
    }
}
