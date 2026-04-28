import Foundation
import Combine
@preconcurrency import EventKit

struct RemindersReminderPayload: Hashable, Sendable {
    let listIdentifier: String
    let title: String
    let notes: String
    let isCompleted: Bool
}

struct RemindersReminderRecord: Hashable, Sendable {
    let calendarItemIdentifier: String
    let listIdentifier: String
    let title: String
    let notes: String
    let isCompleted: Bool
}

protocol VoxtRemindersSyncBackend {
    func authorizationState() -> RemindersAuthorizationState
    func writableLists() throws -> [RemindersListDescriptor]
    func reminder(with identifier: String) throws -> RemindersReminderRecord?
    func saveReminder(_ payload: RemindersReminderPayload, existingIdentifier: String?) throws -> String
    func deleteReminder(with identifier: String) throws
}

final class EventKitVoxtRemindersSyncBackend: VoxtRemindersSyncBackend {
    private let eventStore: EKEventStore

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func authorizationState() -> RemindersAuthorizationState {
        RemindersPermissionManager.authorizationState()
    }

    func writableLists() throws -> [RemindersListDescriptor] {
        RemindersPermissionManager.writableLists(eventStore: eventStore)
    }

    func reminder(with identifier: String) throws -> RemindersReminderRecord? {
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder,
              let calendar = reminder.calendar else {
            return nil
        }
        return RemindersReminderRecord(
            calendarItemIdentifier: reminder.calendarItemIdentifier,
            listIdentifier: calendar.calendarIdentifier,
            title: reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            notes: reminder.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            isCompleted: reminder.isCompleted
        )
    }

    func saveReminder(_ payload: RemindersReminderPayload, existingIdentifier: String?) throws -> String {
        guard let calendar = eventStore.calendars(for: .reminder).first(where: {
            $0.calendarIdentifier == payload.listIdentifier && $0.allowsContentModifications
        }) else {
            throw RemindersSyncError.listUnavailable(payload.listIdentifier)
        }

        let reminder: EKReminder
        if let existingIdentifier,
           let existingReminder = eventStore.calendarItem(withIdentifier: existingIdentifier) as? EKReminder {
            reminder = existingReminder
        } else {
            reminder = EKReminder(eventStore: eventStore)
        }

        reminder.calendar = calendar
        reminder.title = payload.title
        reminder.notes = payload.notes
        reminder.isCompleted = payload.isCompleted

        try eventStore.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    func deleteReminder(with identifier: String) throws {
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            return
        }
        try eventStore.remove(reminder, commit: true)
    }
}

final class VoxtRemindersSyncCoordinator {
    private let noteStore: VoxtNoteStore
    private let settingsProvider: () -> RemindersNoteSyncSettings
    private let exportStore: VoxtNoteRemindersExportStore
    private let backendFactory: () -> any VoxtRemindersSyncBackend
    private let notificationCenter: NotificationCenter
    private let queue = DispatchQueue(label: "com.voxt.reminders-sync", qos: .utility)
    private var itemsCancellable: AnyCancellable?
    private var settingsObserver: NSObjectProtocol?
    private var latestNotesSnapshot: [VoxtNoteItem]

    @MainActor
    init(
        noteStore: VoxtNoteStore,
        settingsProvider: @escaping () -> RemindersNoteSyncSettings,
        exportStore: VoxtNoteRemindersExportStore? = nil,
        notificationCenter: NotificationCenter = .default,
        backendFactory: @escaping () -> any VoxtRemindersSyncBackend = { EventKitVoxtRemindersSyncBackend() }
    ) {
        self.noteStore = noteStore
        self.settingsProvider = settingsProvider
        self.exportStore = exportStore ?? VoxtNoteRemindersExportStore()
        self.backendFactory = backendFactory
        self.notificationCenter = notificationCenter
        self.latestNotesSnapshot = noteStore.items

        itemsCancellable = noteStore.$items
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                self?.latestNotesSnapshot = items
                self?.scheduleSync(notes: items, settings: settingsProvider(), reason: "notes-updated")
            }

        settingsObserver = notificationCenter.addObserver(
            forName: .voxtFeatureSettingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.scheduleSync(
                notes: self.latestNotesSnapshot,
                settings: self.settingsProvider(),
                reason: "settings-updated"
            )
        }

        scheduleSync(
            notes: noteStore.items,
            settings: settingsProvider(),
            reason: "startup"
        )
    }

    deinit {
        if let settingsObserver {
            notificationCenter.removeObserver(settingsObserver)
        }
    }

    private func scheduleSync(
        notes: [VoxtNoteItem],
        settings: RemindersNoteSyncSettings,
        reason: String
    ) {
        queue.async { [backendFactory, exportStore] in
            Self.reconcile(
                notes: notes,
                settings: settings,
                exportStore: exportStore,
                backend: backendFactory(),
                reason: reason
            )
        }
    }

    private static func reconcile(
        notes: [VoxtNoteItem],
        settings: RemindersNoteSyncSettings,
        exportStore: VoxtNoteRemindersExportStore,
        backend: any VoxtRemindersSyncBackend,
        reason: String
    ) {
        guard settings.enabled else { return }
        guard backend.authorizationState() == .authorized else {
            VoxtLog.warning("Reminders sync skipped because permission is unavailable. reason=\(reason)")
            return
        }

        let selectedListIdentifier = settings.selectedListIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedListIdentifier.isEmpty else {
            VoxtLog.warning("Reminders sync skipped because no target list is configured. reason=\(reason)")
            return
        }

        let writableLists: [RemindersListDescriptor]
        do {
            writableLists = try backend.writableLists()
        } catch {
            VoxtLog.warning("Reminders sync failed to load writable lists. reason=\(reason), error=\(error.localizedDescription)")
            return
        }

        guard writableLists.contains(where: { $0.identifier == selectedListIdentifier }) else {
            VoxtLog.warning("Reminders sync skipped because the target list is unavailable. reason=\(reason), listID=\(selectedListIdentifier)")
            return
        }

        let previousRecordsByNoteID = exportStore.recordsByNoteID
        let currentNoteIDs = Set(notes.map(\.id))
        var nextRecordsByNoteID = previousRecordsByNoteID.filter { currentNoteIDs.contains($0.key) }

        for note in notes.sorted(by: noteSortOrder) {
            let payload = makePayload(for: note, listIdentifier: selectedListIdentifier)
            let existingRecord = previousRecordsByNoteID[note.id]
            let existingIdentifier: String?

            if let existingRecord,
               let reminder = try? backend.reminder(with: existingRecord.reminderCalendarItemIdentifier) {
                existingIdentifier = reminder.calendarItemIdentifier
            } else {
                existingIdentifier = nil
            }

            do {
                let savedIdentifier = try backend.saveReminder(payload, existingIdentifier: existingIdentifier)
                nextRecordsByNoteID[note.id] = VoxtNoteRemindersExportRecord(
                    noteID: note.id,
                    reminderCalendarItemIdentifier: savedIdentifier,
                    selectedListIdentifierAtCreation: selectedListIdentifier
                )
            } catch {
                VoxtLog.warning("Reminders sync write failed. reason=\(reason), noteID=\(note.id.uuidString), error=\(error.localizedDescription)")
                if existingRecord == nil {
                    nextRecordsByNoteID.removeValue(forKey: note.id)
                }
            }
        }

        let removedRecords = previousRecordsByNoteID.values.filter { !currentNoteIDs.contains($0.noteID) }
        for record in removedRecords {
            do {
                try backend.deleteReminder(with: record.reminderCalendarItemIdentifier)
            } catch {
                VoxtLog.warning("Reminders sync delete failed. reason=\(reason), noteID=\(record.noteID.uuidString), error=\(error.localizedDescription)")
            }
            nextRecordsByNoteID.removeValue(forKey: record.noteID)
        }

        exportStore.replaceAll(Array(nextRecordsByNoteID.values))
    }

    private static func makePayload(
        for note: VoxtNoteItem,
        listIdentifier: String
    ) -> RemindersReminderPayload {
        RemindersReminderPayload(
            listIdentifier: listIdentifier,
            title: note.title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: note.text.trimmingCharacters(in: .whitespacesAndNewlines),
            isCompleted: note.isCompleted
        )
    }

    private static func noteSortOrder(lhs: VoxtNoteItem, rhs: VoxtNoteItem) -> Bool {
        if lhs.createdAt == rhs.createdAt {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.createdAt < rhs.createdAt
    }
}

private enum RemindersSyncError: LocalizedError {
    case listUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .listUnavailable(let identifier):
            return "List unavailable: \(identifier)"
        }
    }
}
