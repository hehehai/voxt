import XCTest
@testable import Voxt

@MainActor
final class VoxtRemindersSyncCoordinatorTests: XCTestCase {
    func testDisabledSyncDoesNotCreateReminders() async throws {
        let directory = try TemporaryDirectory()
        let noteStore = VoxtNoteStore(fileURL: directory.url.appendingPathComponent("notes.json"))
        let exportStore = VoxtNoteRemindersExportStore(fileURL: directory.url.appendingPathComponent("exports.json"))
        let backend = FakeVoxtRemindersSyncBackend()
        let settings = RemindersNoteSyncSettings(
            enabled: false,
            selectedListIdentifier: "list-1",
            selectedListTitle: "Voxt"
        )

        let coordinator = VoxtRemindersSyncCoordinator(
            noteStore: noteStore,
            settingsProvider: { settings },
            exportStore: exportStore,
            notificationCenter: NotificationCenter(),
            backendFactory: { backend }
        )

        _ = coordinator
        _ = noteStore.append(
            sessionID: UUID(),
            text: "disabled",
            title: "Disabled",
            titleGenerationState: .generated
        )

        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(backend.reminders.isEmpty)
        XCTAssertTrue(exportStore.recordsByNoteID.isEmpty)
    }

    func testCreateUpdateAndDeleteReminder() async throws {
        let directory = try TemporaryDirectory()
        let noteStore = VoxtNoteStore(fileURL: directory.url.appendingPathComponent("notes.json"))
        let exportStore = VoxtNoteRemindersExportStore(fileURL: directory.url.appendingPathComponent("exports.json"))
        let backend = FakeVoxtRemindersSyncBackend()
        let settings = RemindersNoteSyncSettings(
            enabled: true,
            selectedListIdentifier: "list-1",
            selectedListTitle: "Voxt"
        )

        let coordinator = VoxtRemindersSyncCoordinator(
            noteStore: noteStore,
            settingsProvider: { settings },
            exportStore: exportStore,
            notificationCenter: NotificationCenter(),
            backendFactory: { backend }
        )

        _ = coordinator
        let item = try XCTUnwrap(
            noteStore.append(
                sessionID: UUID(),
                text: "Ship reminders integration.",
                title: "Reminders sync",
                titleGenerationState: .generated
            )
        )

        try await Task.sleep(for: .milliseconds(500))

        let initialRecord = try XCTUnwrap(exportStore.recordsByNoteID[item.id])
        var reminder = try XCTUnwrap(backend.reminder(with: initialRecord.reminderCalendarItemIdentifier))
        XCTAssertEqual(reminder.title, "Reminders sync")
        XCTAssertEqual(reminder.notes, "Ship reminders integration.")
        XCTAssertFalse(reminder.isCompleted)

        _ = noteStore.updateTitle("Updated title", state: .generated, for: item.id)
        try await Task.sleep(for: .milliseconds(500))
        _ = noteStore.updateCompletion(true, for: item.id)
        try await Task.sleep(for: .milliseconds(500))

        reminder = try XCTUnwrap(backend.reminder(with: initialRecord.reminderCalendarItemIdentifier))
        XCTAssertEqual(reminder.title, "Updated title")
        XCTAssertTrue(reminder.isCompleted)

        noteStore.delete(id: item.id)
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertNil(try backend.reminder(with: initialRecord.reminderCalendarItemIdentifier))
        XCTAssertTrue(backend.deletedIdentifiers.contains(initialRecord.reminderCalendarItemIdentifier))
        XCTAssertTrue(exportStore.recordsByNoteID.isEmpty)
    }

    func testStaleReminderMappingCreatesReplacementReminder() async throws {
        let directory = try TemporaryDirectory()
        let noteStore = VoxtNoteStore(fileURL: directory.url.appendingPathComponent("notes.json"))
        let exportStore = VoxtNoteRemindersExportStore(fileURL: directory.url.appendingPathComponent("exports.json"))
        let backend = FakeVoxtRemindersSyncBackend()
        let settings = RemindersNoteSyncSettings(
            enabled: true,
            selectedListIdentifier: "list-1",
            selectedListTitle: "Voxt"
        )

        let coordinator = VoxtRemindersSyncCoordinator(
            noteStore: noteStore,
            settingsProvider: { settings },
            exportStore: exportStore,
            notificationCenter: NotificationCenter(),
            backendFactory: { backend }
        )

        _ = coordinator
        let item = try XCTUnwrap(
            noteStore.append(
                sessionID: UUID(),
                text: "Original note body.",
                title: "Original title",
                titleGenerationState: .generated
            )
        )

        try await Task.sleep(for: .milliseconds(500))

        let originalRecord = try XCTUnwrap(exportStore.recordsByNoteID[item.id])
        backend.dropReminder(identifier: originalRecord.reminderCalendarItemIdentifier)

        _ = noteStore.updateTitle("Recovered title", state: .generated, for: item.id)
        try await Task.sleep(for: .milliseconds(500))

        let replacementRecord = try XCTUnwrap(exportStore.recordsByNoteID[item.id])
        XCTAssertNotEqual(
            replacementRecord.reminderCalendarItemIdentifier,
            originalRecord.reminderCalendarItemIdentifier
        )
        let reminder = try XCTUnwrap(backend.reminder(with: replacementRecord.reminderCalendarItemIdentifier))
        XCTAssertEqual(reminder.title, "Recovered title")
    }

    func testUnauthorizedOrMissingListSkipsSyncAndKeepsLocalNote() async throws {
        let directory = try TemporaryDirectory()
        let noteStore = VoxtNoteStore(fileURL: directory.url.appendingPathComponent("notes.json"))
        let exportStore = VoxtNoteRemindersExportStore(fileURL: directory.url.appendingPathComponent("exports.json"))
        let backend = FakeVoxtRemindersSyncBackend()
        let notificationCenter = NotificationCenter()
        var settings = RemindersNoteSyncSettings(
            enabled: true,
            selectedListIdentifier: "list-1",
            selectedListTitle: "Voxt"
        )

        let coordinator = VoxtRemindersSyncCoordinator(
            noteStore: noteStore,
            settingsProvider: { settings },
            exportStore: exportStore,
            notificationCenter: notificationCenter,
            backendFactory: { backend }
        )

        _ = coordinator
        backend.authorizationStateValue = .denied
        let item = try XCTUnwrap(
            noteStore.append(
                sessionID: UUID(),
                text: "Permission blocked note.",
                title: "Blocked",
                titleGenerationState: .generated
            )
        )

        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(backend.reminders.isEmpty)
        XCTAssertTrue(exportStore.recordsByNoteID.isEmpty)
        XCTAssertNotNil(noteStore.items.first(where: { $0.id == item.id }))

        backend.authorizationStateValue = .authorized
        settings.selectedListIdentifier = "missing-list"
        notificationCenter.post(name: .voxtFeatureSettingsDidChange, object: nil)
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertTrue(backend.reminders.isEmpty)
        XCTAssertTrue(exportStore.recordsByNoteID.isEmpty)
        XCTAssertNotNil(noteStore.items.first(where: { $0.id == item.id }))
    }
}

private final class FakeVoxtRemindersSyncBackend: VoxtRemindersSyncBackend {
    private let lock = NSLock()

    var authorizationStateValue: RemindersAuthorizationState = .authorized
    var writableListDescriptors: [RemindersListDescriptor] = [
        RemindersListDescriptor(identifier: "list-1", title: "Voxt", sourceTitle: "iCloud")
    ]

    private var remindersByIdentifier: [String: RemindersReminderRecord] = [:]
    private var nextIdentifier = 1
    private(set) var deletedIdentifiers: [String] = []

    var reminders: [String: RemindersReminderRecord] {
        lock.withLock { remindersByIdentifier }
    }

    func authorizationState() -> RemindersAuthorizationState {
        authorizationStateValue
    }

    func writableLists() throws -> [RemindersListDescriptor] {
        writableListDescriptors
    }

    func reminder(with identifier: String) throws -> RemindersReminderRecord? {
        lock.withLock { remindersByIdentifier[identifier] }
    }

    func saveReminder(_ payload: RemindersReminderPayload, existingIdentifier: String?) throws -> String {
        lock.withLock {
            let identifier: String
            if let existingIdentifier, remindersByIdentifier[existingIdentifier] != nil {
                identifier = existingIdentifier
            } else {
                identifier = "rem-\(nextIdentifier)"
                nextIdentifier += 1
            }

            remindersByIdentifier[identifier] = RemindersReminderRecord(
                calendarItemIdentifier: identifier,
                listIdentifier: payload.listIdentifier,
                title: payload.title,
                notes: payload.notes,
                isCompleted: payload.isCompleted
            )
            return identifier
        }
    }

    func deleteReminder(with identifier: String) throws {
        lock.withLock {
            remindersByIdentifier.removeValue(forKey: identifier)
            deletedIdentifiers.append(identifier)
        }
    }

    func dropReminder(identifier: String) {
        lock.withLock {
            remindersByIdentifier.removeValue(forKey: identifier)
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
