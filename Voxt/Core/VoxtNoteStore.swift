// VoxtNoteStore.swift
// Provides Voxt Note Store for core app behavior.

import Foundation
import Combine

enum NoteTitleGenerationState: String, Codable, Equatable, Sendable {
    case pending
    case generated
    case fallback
}

struct VoxtNoteItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let sessionID: UUID
    let createdAt: Date
    let text: String
    let title: String
    let titleGenerationState: NoteTitleGenerationState
    let isCompleted: Bool

    func updatingTitle(_ title: String, state: NoteTitleGenerationState) -> VoxtNoteItem {
        VoxtNoteItem(
            id: id,
            sessionID: sessionID,
            createdAt: createdAt,
            text: text,
            title: title,
            titleGenerationState: state,
            isCompleted: isCompleted
        )
    }

    func updatingCompletion(_ isCompleted: Bool) -> VoxtNoteItem {
        VoxtNoteItem(
            id: id,
            sessionID: sessionID,
            createdAt: createdAt,
            text: text,
            title: title,
            titleGenerationState: titleGenerationState,
            isCompleted: isCompleted
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case sessionID
        case createdAt
        case text
        case title
        case titleGenerationState
        case isCompleted
    }

    init(
        id: UUID,
        sessionID: UUID,
        createdAt: Date,
        text: String,
        title: String,
        titleGenerationState: NoteTitleGenerationState,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.text = text
        self.title = title
        self.titleGenerationState = titleGenerationState
        self.isCompleted = isCompleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sessionID = try container.decode(UUID.self, forKey: .sessionID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        text = try container.decode(String.self, forKey: .text)
        title = try container.decode(String.self, forKey: .title)
        titleGenerationState = try container.decode(NoteTitleGenerationState.self, forKey: .titleGenerationState)
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
    }
}

enum VoxtNoteTitleSupport {
    static func fallbackTitle(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Note" }

        let collapsedWhitespace = trimmed
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsedWhitespace.isEmpty else { return "Note" }

        let stopCharacters = CharacterSet(charactersIn: "\n。！？!?;；:.")
        if let boundary = collapsedWhitespace.unicodeScalars.firstIndex(where: { stopCharacters.contains($0) }) {
            let candidate = String(collapsedWhitespace.unicodeScalars[..<boundary])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty {
                return limitedTitle(candidate)
            }
        }

        return limitedTitle(collapsedWhitespace)
    }

    static func normalizedGeneratedTitle(_ title: String) -> String {
        let firstLine = title
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? ""
        let trimmed = firstLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’"))
        guard !trimmed.isEmpty else { return "" }
        return limitedTitle(trimmed)
    }

    private static func limitedTitle(_ value: String) -> String {
        let limit = containsCJK(value) ? 20 : 48
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.count > limit else { return candidate }
        let endIndex = candidate.index(candidate.startIndex, offsetBy: limit)
        return String(candidate[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
    }
}

@MainActor
final class VoxtNoteStore: ObservableObject {
    @Published private(set) var items: [VoxtNoteItem] = []

    private let fileManager: FileManager
    private let persistenceCoordinator = AsyncJSONPersistenceCoordinator(
        label: "com.voxt.note-store.persistence"
    )
    private let fileURLOverride: URL?
    private let maxStoredItems = 1000

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        self.fileURLOverride = fileURL
        reload()
    }

    var latestItem: VoxtNoteItem? {
        items.first
    }

    var incompleteItems: [VoxtNoteItem] {
        items.filter { !$0.isCompleted }
    }

    var latestIncompleteItem: VoxtNoteItem? {
        incompleteItems.first
    }

    func reload() {
        do {
            let fileURL = try noteFileURL()
            guard fileManager.fileExists(atPath: fileURL.path) else {
                items = []
                return
            }
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([VoxtNoteItem].self, from: data)
            items = decoded.sorted { $0.createdAt > $1.createdAt }
        } catch {
            items = []
        }
    }

    @discardableResult
    func append(
        sessionID: UUID,
        text: String,
        title: String,
        titleGenerationState: NoteTitleGenerationState
    ) -> VoxtNoteItem? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty, !trimmedTitle.isEmpty else { return nil }

        let item = VoxtNoteItem(
            id: UUID(),
            sessionID: sessionID,
            createdAt: Date(),
            text: trimmedText,
            title: trimmedTitle,
            titleGenerationState: titleGenerationState,
            isCompleted: false
        )
        items.insert(item, at: 0)
        if items.count > maxStoredItems {
            items = Array(items.prefix(maxStoredItems))
        }
        persist()
        return item
    }

    @discardableResult
    func updateTitle(
        _ title: String,
        state: NoteTitleGenerationState,
        for noteID: UUID
    ) -> VoxtNoteItem? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty,
              let index = items.firstIndex(where: { $0.id == noteID })
        else {
            return nil
        }

        let updated = items[index].updatingTitle(trimmedTitle, state: state)
        items[index] = updated
        persist()
        return updated
    }

    func delete(id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    @discardableResult
    func updateCompletion(_ isCompleted: Bool, for noteID: UUID) -> VoxtNoteItem? {
        guard let index = items.firstIndex(where: { $0.id == noteID }) else {
            return nil
        }

        let updated = items[index].updatingCompletion(isCompleted)
        items[index] = updated
        persist()
        return updated
    }

    func clearAll() {
        items = []
        persist()
    }

    private func persist() {
        do {
            let fileURL = try noteFileURL()
            persistenceCoordinator.scheduleWrite(items, to: fileURL)
        } catch {
            return
        }
    }

    private func noteFileURL() throws -> URL {
        if let fileURLOverride {
            return fileURLOverride
        }

        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("Voxt", isDirectory: true)
            .appendingPathComponent("voxt-notes.json")
    }
}
