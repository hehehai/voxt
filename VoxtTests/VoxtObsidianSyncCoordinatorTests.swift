import XCTest
@testable import Voxt

@MainActor
final class VoxtObsidianSyncCoordinatorTests: XCTestCase {
    func testDisabledSyncDoesNotWriteVaultFiles() async throws {
        let directory = try TemporaryDirectory()
        let vaultURL = directory.url.appendingPathComponent("vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)

        let noteStore = VoxtNoteStore(fileURL: directory.url.appendingPathComponent("notes.json"))
        let exportStore = VoxtNoteObsidianExportStore(fileURL: directory.url.appendingPathComponent("exports.json"))
        let settings = ObsidianNoteSyncSettings(
            enabled: false,
            vaultPath: vaultURL.path,
            relativeFolder: "Voxt",
            groupingMode: .file
        )

        let coordinator = VoxtObsidianSyncCoordinator(
            noteStore: noteStore,
            settingsProvider: { settings },
            exportStore: exportStore
        )

        _ = coordinator
        _ = noteStore.append(
            sessionID: UUID(),
            text: "Ship the disabled sync test.",
            title: "Disabled sync",
            titleGenerationState: .generated
        )

        try await Task.sleep(for: .milliseconds(700))
        XCTAssertFalse(FileManager.default.fileExists(atPath: vaultURL.appendingPathComponent("Voxt").path))
    }

    func testSessionAndSingleFileGroupingWriteReadableFiles() async throws {
        let directory = try TemporaryDirectory()
        let vaultURL = directory.url.appendingPathComponent("vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)

        let noteStore = VoxtNoteStore(fileURL: directory.url.appendingPathComponent("notes.json"))
        let exportStore = VoxtNoteObsidianExportStore(fileURL: directory.url.appendingPathComponent("exports.json"))
        var settings = ObsidianNoteSyncSettings(
            enabled: true,
            vaultPath: vaultURL.path,
            relativeFolder: "Voxt",
            groupingMode: .session
        )

        let coordinator = VoxtObsidianSyncCoordinator(
            noteStore: noteStore,
            settingsProvider: { settings },
            exportStore: exportStore
        )

        _ = coordinator
        let firstSessionID = UUID()
        let firstItem = try XCTUnwrap(
            noteStore.append(
                sessionID: firstSessionID,
                text: "Session grouped note",
                title: "Session note",
                titleGenerationState: .generated
            )
        )

        try await Task.sleep(for: .milliseconds(700))

        let firstRecord = try XCTUnwrap(exportStore.recordsByNoteID[firstItem.id])
        XCTAssertEqual(firstRecord.groupingMode, .session)
        XCTAssertTrue(firstRecord.relativeFilePath.contains("Voxt/Sessions/"))
        XCTAssertTrue(firstRecord.relativeFilePath.contains("Session note"))
        XCTAssertFalse(firstRecord.relativeFilePath.contains(firstSessionID.uuidString))

        let sessionFileURL = vaultURL.appendingPathComponent(firstRecord.relativeFilePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionFileURL.path))

        let sessionContent = try String(contentsOf: sessionFileURL, encoding: .utf8)
        XCTAssertTrue(sessionContent.contains("# Session note"))
        XCTAssertFalse(sessionContent.contains("Note ID:"))
        XCTAssertFalse(sessionContent.contains("VOXT_NOTE_START"))

        settings.groupingMode = .file
        let secondItem = try XCTUnwrap(
            noteStore.append(
                sessionID: UUID(),
                text: "Single file note",
                title: "Single/file note",
                titleGenerationState: .generated
            )
        )

        try await Task.sleep(for: .milliseconds(700))

        let record = try XCTUnwrap(exportStore.recordsByNoteID[secondItem.id])
        XCTAssertEqual(record.groupingMode, .file)
        XCTAssertTrue(record.relativeFilePath.contains("Voxt/Notes/"))
        XCTAssertTrue(record.relativeFilePath.contains("Single file note"))
        XCTAssertFalse(record.relativeFilePath.contains(secondItem.id.uuidString))

        let singleFileURL = vaultURL.appendingPathComponent(record.relativeFilePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: singleFileURL.path))

        let singleFileContent = try String(contentsOf: singleFileURL, encoding: .utf8)
        XCTAssertTrue(singleFileContent.contains("# Single/file note"))
        XCTAssertTrue(singleFileContent.contains("note-id:"))
        XCTAssertFalse(singleFileContent.contains("VOXT_NOTE_START"))
    }

    func testSingleFileStatusAndTitleUpdatesPreserveEditedBody() async throws {
        let directory = try TemporaryDirectory()
        let vaultURL = directory.url.appendingPathComponent("vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)

        let noteStore = VoxtNoteStore(fileURL: directory.url.appendingPathComponent("notes.json"))
        let exportStore = VoxtNoteObsidianExportStore(fileURL: directory.url.appendingPathComponent("exports.json"))
        let settings = ObsidianNoteSyncSettings(
            enabled: true,
            vaultPath: vaultURL.path,
            relativeFolder: "Voxt",
            groupingMode: .file
        )

        let coordinator = VoxtObsidianSyncCoordinator(
            noteStore: noteStore,
            settingsProvider: { settings },
            exportStore: exportStore
        )

        _ = coordinator
        let item = try XCTUnwrap(
            noteStore.append(
                sessionID: UUID(),
                text: "Original body from Voxt.",
                title: "Initial title",
                titleGenerationState: .generated
            )
        )

        try await Task.sleep(for: .milliseconds(700))

        let record = try XCTUnwrap(exportStore.recordsByNoteID[item.id])
        let fileURL = vaultURL.appendingPathComponent(record.relativeFilePath)
        var content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(content.contains("Original body from Voxt."))

        let editedBody = "Edited in Obsidian.\n\nSecond paragraph."
        content = content.replacingOccurrences(of: "Original body from Voxt.", with: editedBody)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        _ = noteStore.updateTitle("Updated title", state: .generated, for: item.id)
        try await Task.sleep(for: .milliseconds(700))
        _ = noteStore.updateCompletion(true, for: item.id)
        try await Task.sleep(for: .milliseconds(700))

        let updatedContent = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(updatedContent.contains("# Updated title"))
        XCTAssertTrue(updatedContent.contains("status: \"completed\""))
        XCTAssertTrue(updatedContent.contains(editedBody))
        XCTAssertFalse(updatedContent.contains("Original body from Voxt."))
    }

    func testCompletedSingleFileUsesTimeAndStatusSuffixInFileName() async throws {
        let directory = try TemporaryDirectory()
        let vaultURL = directory.url.appendingPathComponent("vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)

        let noteStore = VoxtNoteStore(fileURL: directory.url.appendingPathComponent("notes.json"))
        let exportStore = VoxtNoteObsidianExportStore(fileURL: directory.url.appendingPathComponent("exports.json"))

        let item = try XCTUnwrap(
            noteStore.append(
                sessionID: UUID(),
                text: "连接 wax API 接口。",
                title: "完成 wax API 接口连接",
                titleGenerationState: .generated
            )
        )
        _ = noteStore.updateCompletion(true, for: item.id)

        let settings = ObsidianNoteSyncSettings(
            enabled: true,
            vaultPath: vaultURL.path,
            relativeFolder: "Voxt",
            groupingMode: .file
        )

        let coordinator = VoxtObsidianSyncCoordinator(
            noteStore: noteStore,
            settingsProvider: { settings },
            exportStore: exportStore
        )

        _ = coordinator
        try await Task.sleep(for: .milliseconds(700))

        let record = try XCTUnwrap(exportStore.recordsByNoteID[item.id])
        let fileName = URL(fileURLWithPath: record.relativeFilePath).lastPathComponent
        XCTAssertTrue(fileName.contains("wax API 接口连接 [完成].md"))
        XCTAssertFalse(fileName.contains("完成 wax"))
        XCTAssertFalse(fileName.contains(Self.dayFolderFormatter.string(from: item.createdAt)))
    }

    func testSessionMigrationReusesExistingReadableFileInsteadOfAddingSuffix() async throws {
        let directory = try TemporaryDirectory()
        let vaultURL = directory.url.appendingPathComponent("vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)

        let noteStore = VoxtNoteStore(fileURL: directory.url.appendingPathComponent("notes.json"))
        let exportStore = VoxtNoteObsidianExportStore(fileURL: directory.url.appendingPathComponent("exports.json"))
        let item = try XCTUnwrap(
            noteStore.append(
                sessionID: UUID(),
                text: "优化建议正文。",
                title: "笔记应用优化建议",
                titleGenerationState: .generated
            )
        )
        _ = noteStore.updateCompletion(true, for: item.id)

        let dayFolder = Self.dayFolderFormatter.string(from: item.createdAt)
        let readablePath = "Voxt/Sessions/\(dayFolder)/\(Self.timeFormatter.string(from: item.createdAt)) - 笔记应用优化建议 [完成].md"
        let readableURL = vaultURL.appendingPathComponent(readablePath)
        try FileManager.default.createDirectory(at: readableURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.renderExistingSessionFile(sessionID: item.sessionID).write(to: readableURL, atomically: true, encoding: .utf8)

        exportStore.upsert(
            VoxtNoteObsidianExportRecord(
                noteID: item.id,
                groupingMode: .session,
                relativeFilePath: "Voxt/Sessions/\(dayFolder)/\(item.sessionID.uuidString).md"
            )
        )

        let settings = ObsidianNoteSyncSettings(
            enabled: true,
            vaultPath: vaultURL.path,
            relativeFolder: "Voxt",
            groupingMode: .session
        )

        let coordinator = VoxtObsidianSyncCoordinator(
            noteStore: noteStore,
            settingsProvider: { settings },
            exportStore: exportStore
        )

        _ = coordinator
        try await Task.sleep(for: .milliseconds(700))

        let record = try XCTUnwrap(exportStore.recordsByNoteID[item.id])
        XCTAssertEqual(record.relativeFilePath, readablePath)
        XCTAssertFalse(record.relativeFilePath.contains("(2)"))
    }

    func testSessionMigrationDropsStaleNumericSuffixWhenBasePathIsFree() async throws {
        let directory = try TemporaryDirectory()
        let vaultURL = directory.url.appendingPathComponent("vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)

        let noteStore = VoxtNoteStore(fileURL: directory.url.appendingPathComponent("notes.json"))
        let exportStore = VoxtNoteObsidianExportStore(fileURL: directory.url.appendingPathComponent("exports.json"))
        let item = try XCTUnwrap(
            noteStore.append(
                sessionID: UUID(),
                text: "优化建议正文。",
                title: "笔记应用优化建议",
                titleGenerationState: .generated
            )
        )
        _ = noteStore.updateCompletion(true, for: item.id)

        let dayFolder = Self.dayFolderFormatter.string(from: item.createdAt)
        let basePath = "Voxt/Sessions/\(dayFolder)/\(Self.timeFormatter.string(from: item.createdAt)) - 笔记应用优化建议 [完成].md"
        let suffixedPath = basePath.replacingOccurrences(of: ".md", with: " (2).md")
        let suffixedURL = vaultURL.appendingPathComponent(suffixedPath)
        try FileManager.default.createDirectory(at: suffixedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.renderExistingSessionFile(sessionID: item.sessionID).write(to: suffixedURL, atomically: true, encoding: .utf8)

        exportStore.upsert(
            VoxtNoteObsidianExportRecord(
                noteID: item.id,
                groupingMode: .session,
                relativeFilePath: suffixedPath
            )
        )

        let settings = ObsidianNoteSyncSettings(
            enabled: true,
            vaultPath: vaultURL.path,
            relativeFolder: "Voxt",
            groupingMode: .session
        )

        let coordinator = VoxtObsidianSyncCoordinator(
            noteStore: noteStore,
            settingsProvider: { settings },
            exportStore: exportStore
        )

        _ = coordinator
        try await Task.sleep(for: .milliseconds(700))

        let record = try XCTUnwrap(exportStore.recordsByNoteID[item.id])
        XCTAssertEqual(record.relativeFilePath, basePath)
        XCTAssertFalse(record.relativeFilePath.contains("(2)"))
    }

    func testSingleFileMigrationDropsStaleNumericSuffixWhenBasePathIsFree() async throws {
        let directory = try TemporaryDirectory()
        let vaultURL = directory.url.appendingPathComponent("vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)

        let noteStore = VoxtNoteStore(fileURL: directory.url.appendingPathComponent("notes.json"))
        let exportStore = VoxtNoteObsidianExportStore(fileURL: directory.url.appendingPathComponent("exports.json"))
        let item = try XCTUnwrap(
            noteStore.append(
                sessionID: UUID(),
                text: "wax API 接口的单文件正文。",
                title: "完成 wax API 接口连接",
                titleGenerationState: .generated
            )
        )
        _ = noteStore.updateCompletion(true, for: item.id)

        let dayFolder = Self.dayFolderFormatter.string(from: item.createdAt)
        let basePath = "Voxt/Notes/\(dayFolder)/\(Self.timeFormatter.string(from: item.createdAt)) - wax API 接口连接 [完成].md"
        let suffixedPath = basePath.replacingOccurrences(of: ".md", with: " (2).md")
        let suffixedURL = vaultURL.appendingPathComponent(suffixedPath)
        try FileManager.default.createDirectory(at: suffixedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.renderExistingSingleNoteFile(noteID: item.id, sessionID: item.sessionID).write(to: suffixedURL, atomically: true, encoding: .utf8)

        exportStore.upsert(
            VoxtNoteObsidianExportRecord(
                noteID: item.id,
                groupingMode: .file,
                relativeFilePath: suffixedPath
            )
        )

        let settings = ObsidianNoteSyncSettings(
            enabled: true,
            vaultPath: vaultURL.path,
            relativeFolder: "Voxt",
            groupingMode: .file
        )

        let coordinator = VoxtObsidianSyncCoordinator(
            noteStore: noteStore,
            settingsProvider: { settings },
            exportStore: exportStore
        )

        _ = coordinator
        try await Task.sleep(for: .milliseconds(700))

        let record = try XCTUnwrap(exportStore.recordsByNoteID[item.id])
        XCTAssertEqual(record.relativeFilePath, basePath)
        XCTAssertFalse(record.relativeFilePath.contains("(2)"))
    }

    func testDailyGroupingDeleteRemovesManagedFile() async throws {
        let directory = try TemporaryDirectory()
        let vaultURL = directory.url.appendingPathComponent("vault", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)

        let noteStore = VoxtNoteStore(fileURL: directory.url.appendingPathComponent("notes.json"))
        let exportStore = VoxtNoteObsidianExportStore(fileURL: directory.url.appendingPathComponent("exports.json"))
        let settings = ObsidianNoteSyncSettings(
            enabled: true,
            vaultPath: vaultURL.path,
            relativeFolder: "Voxt",
            groupingMode: .daily
        )

        let coordinator = VoxtObsidianSyncCoordinator(
            noteStore: noteStore,
            settingsProvider: { settings },
            exportStore: exportStore
        )

        _ = coordinator
        let item = try XCTUnwrap(
            noteStore.append(
                sessionID: UUID(),
                text: "Review the final markdown output.",
                title: "Initial title",
                titleGenerationState: .generated
            )
        )

        try await Task.sleep(for: .milliseconds(700))

        let dayFolder = Self.dayFolderFormatter.string(from: item.createdAt)
        let dailyFileURL = vaultURL.appendingPathComponent("Voxt/Daily/\(dayFolder) Notes.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dailyFileURL.path))

        noteStore.delete(id: item.id)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dailyFileURL.path))
    }

    private static let dayFolderFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static func renderExistingSessionFile(sessionID: UUID) -> String {
        """
        ---
        type: "voxt-note-collection"
        source: "voxt"
        grouping: "session"
        session-id: "\(sessionID.uuidString)"
        ---

        # Existing session file
        """
    }

    private static func renderExistingSingleNoteFile(noteID: UUID, sessionID: UUID) -> String {
        """
        ---
        type: "voxt-note"
        source: "voxt"
        created: "2026-04-28T00:00:00Z"
        updated: "2026-04-28T00:00:00Z"
        status: "completed"
        title: "wax API 接口连接"
        note-id: "\(noteID.uuidString)"
        session-id: "\(sessionID.uuidString)"
        ---

        # Existing note file

        已有正文
        """
    }
}
