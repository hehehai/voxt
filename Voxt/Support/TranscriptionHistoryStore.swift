import Foundation
import Combine

struct TranscriptionHistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    let createdAt: Date
    let transcriptionEngine: String
    let transcriptionModel: String
    let enhancementMode: String
    let enhancementModel: String
    let isTranslation: Bool
    let audioDurationSeconds: TimeInterval?
    let transcriptionProcessingDurationSeconds: TimeInterval?
    let llmDurationSeconds: TimeInterval?
    let focusedAppName: String?
    let matchedAppGroupName: String?
    let matchedURLGroupName: String?
    let remoteASRProvider: String?
    let remoteASRModel: String?
    let remoteASREndpoint: String?
    let remoteLLMProvider: String?
    let remoteLLMModel: String?
    let remoteLLMEndpoint: String?

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case createdAt
        case transcriptionEngine
        case transcriptionModel
        case enhancementMode
        case enhancementModel
        case isTranslation
        case audioDurationSeconds
        case transcriptionProcessingDurationSeconds
        case llmDurationSeconds
        case focusedAppName
        case matchedAppGroupName
        case matchedURLGroupName
        case remoteASRProvider
        case remoteASRModel
        case remoteASREndpoint
        case remoteLLMProvider
        case remoteLLMModel
        case remoteLLMEndpoint
    }

    init(
        id: UUID,
        text: String,
        createdAt: Date,
        transcriptionEngine: String,
        transcriptionModel: String,
        enhancementMode: String,
        enhancementModel: String,
        isTranslation: Bool,
        audioDurationSeconds: TimeInterval?,
        transcriptionProcessingDurationSeconds: TimeInterval?,
        llmDurationSeconds: TimeInterval?,
        focusedAppName: String?,
        matchedAppGroupName: String?,
        matchedURLGroupName: String?,
        remoteASRProvider: String?,
        remoteASRModel: String?,
        remoteASREndpoint: String?,
        remoteLLMProvider: String?,
        remoteLLMModel: String?,
        remoteLLMEndpoint: String?
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.transcriptionEngine = transcriptionEngine
        self.transcriptionModel = transcriptionModel
        self.enhancementMode = enhancementMode
        self.enhancementModel = enhancementModel
        self.isTranslation = isTranslation
        self.audioDurationSeconds = audioDurationSeconds
        self.transcriptionProcessingDurationSeconds = transcriptionProcessingDurationSeconds
        self.llmDurationSeconds = llmDurationSeconds
        self.focusedAppName = focusedAppName
        self.matchedAppGroupName = matchedAppGroupName
        self.matchedURLGroupName = matchedURLGroupName
        self.remoteASRProvider = remoteASRProvider
        self.remoteASRModel = remoteASRModel
        self.remoteASREndpoint = remoteASREndpoint
        self.remoteLLMProvider = remoteLLMProvider
        self.remoteLLMModel = remoteLLMModel
        self.remoteLLMEndpoint = remoteLLMEndpoint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        transcriptionEngine = try container.decode(String.self, forKey: .transcriptionEngine)
        transcriptionModel = try container.decode(String.self, forKey: .transcriptionModel)
        enhancementMode = try container.decode(String.self, forKey: .enhancementMode)
        enhancementModel = try container.decode(String.self, forKey: .enhancementModel)
        isTranslation = try container.decodeIfPresent(Bool.self, forKey: .isTranslation) ?? false
        audioDurationSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .audioDurationSeconds)
        transcriptionProcessingDurationSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .transcriptionProcessingDurationSeconds)
        llmDurationSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .llmDurationSeconds)
        focusedAppName = try container.decodeIfPresent(String.self, forKey: .focusedAppName)
        matchedAppGroupName = try container.decodeIfPresent(String.self, forKey: .matchedAppGroupName)
        matchedURLGroupName = try container.decodeIfPresent(String.self, forKey: .matchedURLGroupName)
        remoteASRProvider = try container.decodeIfPresent(String.self, forKey: .remoteASRProvider)
        remoteASRModel = try container.decodeIfPresent(String.self, forKey: .remoteASRModel)
        remoteASREndpoint = try container.decodeIfPresent(String.self, forKey: .remoteASREndpoint)
        remoteLLMProvider = try container.decodeIfPresent(String.self, forKey: .remoteLLMProvider)
        remoteLLMModel = try container.decodeIfPresent(String.self, forKey: .remoteLLMModel)
        remoteLLMEndpoint = try container.decodeIfPresent(String.self, forKey: .remoteLLMEndpoint)
    }
}

@MainActor
final class TranscriptionHistoryStore: ObservableObject {
    @Published private(set) var entries: [TranscriptionHistoryEntry] = []

    private var allEntries: [TranscriptionHistoryEntry] = []
    private var loadedCount = 0
    private let pageSize = 40
    private let maxStoredEntries = 1000

    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard

    init() {
        reload()
    }

    var hasMore: Bool {
        loadedCount < allEntries.count
    }

    var allHistoryEntries: [TranscriptionHistoryEntry] {
        allEntries
    }

    func updateRetentionPolicy() {
        if applyRetentionPolicyIfNeeded() {
            loadedCount = min(loadedCount, allEntries.count)
            entries = Array(allEntries.prefix(loadedCount))
            persist()
        }
    }

    func reload() {
        do {
            let url = try historyFileURL()
            guard fileManager.fileExists(atPath: url.path) else {
                allEntries = []
                entries = []
                loadedCount = 0
                return
            }
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([TranscriptionHistoryEntry].self, from: data)
            allEntries = decoded.sorted { $0.createdAt > $1.createdAt }
            let didPrune = applyRetentionPolicyIfNeeded()
            loadedCount = min(pageSize, allEntries.count)
            entries = Array(allEntries.prefix(loadedCount))
            if didPrune {
                persist()
            }
        } catch {
            allEntries = []
            entries = []
            loadedCount = 0
        }
    }

    func loadNextPage() {
        guard hasMore else { return }
        loadedCount = min(loadedCount + pageSize, allEntries.count)
        entries = Array(allEntries.prefix(loadedCount))
    }

    func append(
        text: String,
        transcriptionEngine: String,
        transcriptionModel: String,
        enhancementMode: String,
        enhancementModel: String,
        isTranslation: Bool,
        audioDurationSeconds: TimeInterval?,
        transcriptionProcessingDurationSeconds: TimeInterval?,
        llmDurationSeconds: TimeInterval?,
        focusedAppName: String?,
        matchedAppGroupName: String?,
        matchedURLGroupName: String?,
        remoteASRProvider: String?,
        remoteASRModel: String?,
        remoteASREndpoint: String?,
        remoteLLMProvider: String?,
        remoteLLMModel: String?,
        remoteLLMEndpoint: String?
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let entry = TranscriptionHistoryEntry(
            id: UUID(),
            text: trimmed,
            createdAt: Date(),
            transcriptionEngine: transcriptionEngine,
            transcriptionModel: transcriptionModel,
            enhancementMode: enhancementMode,
            enhancementModel: enhancementModel,
            isTranslation: isTranslation,
            audioDurationSeconds: audioDurationSeconds,
            transcriptionProcessingDurationSeconds: transcriptionProcessingDurationSeconds,
            llmDurationSeconds: llmDurationSeconds,
            focusedAppName: focusedAppName,
            matchedAppGroupName: matchedAppGroupName,
            matchedURLGroupName: matchedURLGroupName,
            remoteASRProvider: remoteASRProvider,
            remoteASRModel: remoteASRModel,
            remoteASREndpoint: remoteASREndpoint,
            remoteLLMProvider: remoteLLMProvider,
            remoteLLMModel: remoteLLMModel,
            remoteLLMEndpoint: remoteLLMEndpoint
        )

        allEntries.insert(entry, at: 0)
        if allEntries.count > maxStoredEntries {
            allEntries = Array(allEntries.prefix(maxStoredEntries))
        }
        _ = applyRetentionPolicyIfNeeded()

        loadedCount = min(max(loadedCount + 1, pageSize), allEntries.count)
        entries = Array(allEntries.prefix(loadedCount))
        persist()
    }

    func delete(id: UUID) {
        allEntries.removeAll { $0.id == id }
        loadedCount = min(loadedCount, allEntries.count)
        entries = Array(allEntries.prefix(loadedCount))
        persist()
    }

    func clearAll() {
        allEntries = []
        entries = []
        loadedCount = 0
        persist()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(allEntries)
            let url = try historyFileURL()
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Keep UI responsive even if persistence fails.
        }
    }

    private var historyEnabled: Bool {
        defaults.bool(forKey: AppPreferenceKey.historyEnabled)
    }

    private var historyRetentionPeriod: HistoryRetentionPeriod {
        let raw = defaults.string(forKey: AppPreferenceKey.historyRetentionPeriod)
        return HistoryRetentionPeriod(rawValue: raw ?? "") ?? .thirtyDays
    }

    private func applyRetentionPolicyIfNeeded(referenceDate: Date = Date()) -> Bool {
        guard historyEnabled else { return false }
        guard let days = historyRetentionPeriod.days else { return false }

        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: referenceDate) ?? referenceDate
        let originalCount = allEntries.count
        allEntries.removeAll { $0.createdAt < cutoff }
        return allEntries.count != originalCount
    }

    private func historyFileURL() throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("Voxt", isDirectory: true)
            .appendingPathComponent("transcription-history.json")
    }
}
