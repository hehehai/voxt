import Foundation
import Combine

enum TranscriptionHistoryKind: String, Codable {
    case normal
    case translation
    case rewrite
    case assistant
}

struct AssistantHistoryStep: Codable, Hashable, Identifiable {
    struct WaitCondition: Codable, Hashable {
        let condition: String
        let value: String?
        let timeout: Double?
    }

    let id: UUID
    let title: String
    let action: String?
    let targetApp: String?
    let targetLabel: String?
    let targetRole: String?
    let relativeX: Double?
    let relativeY: Double?
    let resolvedTargetLabel: String?
    let resolvedTargetRole: String?
    let resolvedRelativeX: Double?
    let resolvedRelativeY: Double?
    let success: Bool?
    let durationMs: Int?
    let error: String?
    let diagnosisCategory: String?
    let diagnosisReason: String?
    let params: [String: String]?
    let note: String?
    let waitAfter: WaitCondition?
    let recordedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        action: String? = nil,
        targetApp: String? = nil,
        targetLabel: String? = nil,
        targetRole: String? = nil,
        relativeX: Double? = nil,
        relativeY: Double? = nil,
        resolvedTargetLabel: String? = nil,
        resolvedTargetRole: String? = nil,
        resolvedRelativeX: Double? = nil,
        resolvedRelativeY: Double? = nil,
        success: Bool? = nil,
        durationMs: Int? = nil,
        error: String? = nil,
        diagnosisCategory: String? = nil,
        diagnosisReason: String? = nil,
        params: [String: String]? = nil,
        note: String? = nil,
        waitAfter: WaitCondition? = nil,
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.action = action
        self.targetApp = targetApp
        self.targetLabel = targetLabel
        self.targetRole = targetRole
        self.relativeX = relativeX
        self.relativeY = relativeY
        self.resolvedTargetLabel = resolvedTargetLabel
        self.resolvedTargetRole = resolvedTargetRole
        self.resolvedRelativeX = resolvedRelativeX
        self.resolvedRelativeY = resolvedRelativeY
        self.success = success
        self.durationMs = durationMs
        self.error = error
        self.diagnosisCategory = diagnosisCategory
        self.diagnosisReason = diagnosisReason
        self.params = params
        self.note = note
        self.waitAfter = waitAfter
        self.recordedAt = recordedAt
    }
}

struct TranscriptionHistoryEntry: Identifiable, Codable, Hashable {
    let id: UUID
    let text: String
    let createdAt: Date
    let transcriptionEngine: String
    let transcriptionModel: String
    let enhancementMode: String
    let enhancementModel: String
    let kind: TranscriptionHistoryKind
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
    let assistantSummary: String?
    let assistantActions: [String]?
    let assistantStructuredSteps: [AssistantHistoryStep]?
    let assistantSnapshotPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case createdAt
        case transcriptionEngine
        case transcriptionModel
        case enhancementMode
        case enhancementModel
        case kind
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
        case assistantSummary
        case assistantActions
        case assistantStructuredSteps
        case assistantSnapshotPath
    }

    init(
        id: UUID,
        text: String,
        createdAt: Date,
        transcriptionEngine: String,
        transcriptionModel: String,
        enhancementMode: String,
        enhancementModel: String,
        kind: TranscriptionHistoryKind,
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
        remoteLLMEndpoint: String?,
        assistantSummary: String?,
        assistantActions: [String]?,
        assistantStructuredSteps: [AssistantHistoryStep]?,
        assistantSnapshotPath: String?
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.transcriptionEngine = transcriptionEngine
        self.transcriptionModel = transcriptionModel
        self.enhancementMode = enhancementMode
        self.enhancementModel = enhancementModel
        self.kind = kind
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
        self.assistantSummary = assistantSummary
        self.assistantActions = assistantActions
        self.assistantStructuredSteps = assistantStructuredSteps
        self.assistantSnapshotPath = assistantSnapshotPath
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
        let decodedIsTranslation = try container.decodeIfPresent(Bool.self, forKey: .isTranslation) ?? false
        isTranslation = decodedIsTranslation
        kind = try container.decodeIfPresent(TranscriptionHistoryKind.self, forKey: .kind)
            ?? (decodedIsTranslation ? .translation : .normal)
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
        assistantSummary = try container.decodeIfPresent(String.self, forKey: .assistantSummary)
        assistantActions = try container.decodeIfPresent([String].self, forKey: .assistantActions)
        assistantStructuredSteps = try container.decodeIfPresent([AssistantHistoryStep].self, forKey: .assistantStructuredSteps)
        assistantSnapshotPath = try container.decodeIfPresent(String.self, forKey: .assistantSnapshotPath)
    }
}

@MainActor
final class TranscriptionHistoryStore: ObservableObject {
    @Published private(set) var entries: [TranscriptionHistoryEntry] = []

    var allEntries: [TranscriptionHistoryEntry] = []
    private var loadedCount = 0
    private let pageSize = 40
    private let maxStoredEntries = 1000

    let fileManager = FileManager.default
    let defaults = UserDefaults.standard

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
            persistEntries()
        }
    }

    func reload() {
        do {
            let url = try historyFileLocation()
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
                persistEntries()
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
        kind: TranscriptionHistoryKind,
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
        remoteLLMEndpoint: String?,
        assistantSummary: String?,
        assistantActions: [String]?,
        assistantStructuredSteps: [AssistantHistoryStep]?,
        assistantSnapshotPath: String?
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let entry = TranscriptionHistoryEntry.make(
            text: trimmed,
            transcriptionEngine: transcriptionEngine,
            transcriptionModel: transcriptionModel,
            enhancementMode: enhancementMode,
            enhancementModel: enhancementModel,
            kind: kind,
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
            remoteLLMEndpoint: remoteLLMEndpoint,
            assistantSummary: assistantSummary,
            assistantActions: assistantActions,
            assistantStructuredSteps: assistantStructuredSteps,
            assistantSnapshotPath: assistantSnapshotPath
        )

        allEntries.insert(entry, at: 0)
        if allEntries.count > maxStoredEntries {
            allEntries = Array(allEntries.prefix(maxStoredEntries))
        }
        _ = applyRetentionPolicyIfNeeded()

        loadedCount = min(max(loadedCount + 1, pageSize), allEntries.count)
        entries = Array(allEntries.prefix(loadedCount))
        persistEntries()
    }

    func delete(id: UUID) {
        allEntries.removeAll { $0.id == id }
        loadedCount = min(loadedCount, allEntries.count)
        entries = Array(allEntries.prefix(loadedCount))
        persistEntries()
    }

    func clearAll() {
        allEntries = []
        entries = []
        loadedCount = 0
        persistEntries()
    }

    private var historyEnabled: Bool {
        defaults.bool(forKey: AppPreferenceKey.historyEnabled)
    }

    private var historyRetentionPeriod: HistoryRetentionPeriod {
        currentHistoryRetentionPeriod()
    }

    private func applyRetentionPolicyIfNeeded(referenceDate: Date = Date()) -> Bool {
        guard historyEnabled else { return false }
        guard let days = historyRetentionPeriod.days else { return false }

        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: referenceDate) ?? referenceDate
        let originalCount = allEntries.count
        allEntries.removeAll { $0.createdAt < cutoff }
        return allEntries.count != originalCount
    }

}
