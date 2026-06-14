import Foundation
import Combine

enum TranscriptionHistoryKind: Codable, Hashable, Sendable {
    case normal
    case translation
    case rewrite
    case transcript

    var rawValue: String {
        switch self {
        case .normal:
            return "normal"
        case .translation:
            return "translation"
        case .rewrite:
            return "rewrite"
        case .transcript:
            return "transcript"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "normal":
            self = .normal
        case "translation":
            self = .translation
        case "rewrite":
            self = .rewrite
        case "transcript":
            self = .transcript
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown TranscriptionHistoryKind value: \(rawValue)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct WhisperHistoryWordTiming: Codable, Hashable {
    let word: String
    let startSeconds: Double
    let endSeconds: Double
    let probability: Double
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
    let focusedAppBundleID: String?
    let browserURLHost: String?
    let browserURLOrigin: String?
    let matchedGroupID: UUID?
    let matchedGroupName: String?
    let matchedAppGroupName: String?
    let matchedURLGroupName: String?
    let remoteASRProvider: String?
    let remoteASRModel: String?
    let remoteASREndpoint: String?
    let remoteLLMProvider: String?
    let remoteLLMModel: String?
    let remoteLLMEndpoint: String?
    let audioRelativePath: String?
    let whisperWordTimings: [WhisperHistoryWordTiming]?
    let senseVoiceMetadata: SenseVoiceTranscriptMetadata?
    let transcriptSegments: [TranscriptSegment]?
    let transcriptAudioRelativePath: String?
    let meetingCaptureMode: MeetingCaptureMode?
    let transcriptSummary: TranscriptSummarySnapshot?
    let transcriptSummaryChatMessages: [TranscriptSummaryChatMessage]?
    let displayTitle: String?
    let transcriptionChatMessages: [TranscriptSummaryChatMessage]?
    let dictionaryHitTerms: [String]
    let dictionaryCorrectedTerms: [String]
    let dictionaryCorrectionSnapshots: [DictionaryCorrectionSnapshot]
    let dictionarySuggestedTerms: [DictionarySuggestionSnapshot]

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
        case focusedAppBundleID
        case browserURLHost
        case browserURLOrigin
        case matchedGroupID
        case matchedGroupName
        case matchedAppGroupName
        case matchedURLGroupName
        case remoteASRProvider
        case remoteASRModel
        case remoteASREndpoint
        case remoteLLMProvider
        case remoteLLMModel
        case remoteLLMEndpoint
        case audioRelativePath
        case whisperWordTimings
        case senseVoiceMetadata
        case transcriptSegments
        case transcriptAudioRelativePath
        case meetingCaptureMode
        case transcriptSummary
        case transcriptSummaryChatMessages
        case displayTitle
        case transcriptionChatMessages
        case dictionaryHitTerms
        case dictionaryCorrectedTerms
        case dictionaryCorrectionSnapshots
        case dictionarySuggestedTerms
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
        focusedAppBundleID: String?,
        browserURLHost: String? = nil,
        browserURLOrigin: String? = nil,
        matchedGroupID: UUID?,
        matchedGroupName: String?,
        matchedAppGroupName: String?,
        matchedURLGroupName: String?,
        remoteASRProvider: String?,
        remoteASRModel: String?,
        remoteASREndpoint: String?,
        remoteLLMProvider: String?,
        remoteLLMModel: String?,
        remoteLLMEndpoint: String?,
        audioRelativePath: String? = nil,
        whisperWordTimings: [WhisperHistoryWordTiming]?,
        senseVoiceMetadata: SenseVoiceTranscriptMetadata? = nil,
        transcriptSegments: [TranscriptSegment]? = nil,
        transcriptAudioRelativePath: String? = nil,
        meetingCaptureMode: MeetingCaptureMode? = nil,
        transcriptSummary: TranscriptSummarySnapshot? = nil,
        transcriptSummaryChatMessages: [TranscriptSummaryChatMessage]? = nil,
        displayTitle: String? = nil,
        transcriptionChatMessages: [TranscriptSummaryChatMessage]? = nil,
        dictionaryHitTerms: [String],
        dictionaryCorrectedTerms: [String],
        dictionaryCorrectionSnapshots: [DictionaryCorrectionSnapshot] = [],
        dictionarySuggestedTerms: [DictionarySuggestionSnapshot]
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
        self.focusedAppBundleID = focusedAppBundleID
        self.browserURLHost = browserURLHost
        self.browserURLOrigin = browserURLOrigin
        self.matchedGroupID = matchedGroupID
        self.matchedGroupName = matchedGroupName
        self.matchedAppGroupName = matchedAppGroupName
        self.matchedURLGroupName = matchedURLGroupName
        self.remoteASRProvider = remoteASRProvider
        self.remoteASRModel = remoteASRModel
        self.remoteASREndpoint = remoteASREndpoint
        self.remoteLLMProvider = remoteLLMProvider
        self.remoteLLMModel = remoteLLMModel
        self.remoteLLMEndpoint = remoteLLMEndpoint
        self.audioRelativePath = audioRelativePath ?? transcriptAudioRelativePath
        self.whisperWordTimings = whisperWordTimings
        self.senseVoiceMetadata = senseVoiceMetadata
        self.transcriptSegments = transcriptSegments
        self.transcriptAudioRelativePath = transcriptAudioRelativePath
        self.meetingCaptureMode = meetingCaptureMode
        self.transcriptSummary = transcriptSummary
        self.transcriptSummaryChatMessages = transcriptSummaryChatMessages
        self.displayTitle = displayTitle
        self.transcriptionChatMessages = transcriptionChatMessages
        self.dictionaryHitTerms = dictionaryHitTerms
        self.dictionaryCorrectedTerms = dictionaryCorrectedTerms
        self.dictionaryCorrectionSnapshots = dictionaryCorrectionSnapshots
        self.dictionarySuggestedTerms = dictionarySuggestedTerms
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
        focusedAppBundleID = try container.decodeIfPresent(String.self, forKey: .focusedAppBundleID)
        browserURLHost = try container.decodeIfPresent(String.self, forKey: .browserURLHost)
        browserURLOrigin = try container.decodeIfPresent(String.self, forKey: .browserURLOrigin)
        let decodedMatchedAppGroupName = try container.decodeIfPresent(String.self, forKey: .matchedAppGroupName)
        let decodedMatchedURLGroupName = try container.decodeIfPresent(String.self, forKey: .matchedURLGroupName)
        matchedGroupID = try container.decodeIfPresent(UUID.self, forKey: .matchedGroupID)
        matchedGroupName = try container.decodeIfPresent(String.self, forKey: .matchedGroupName)
            ?? decodedMatchedURLGroupName
            ?? decodedMatchedAppGroupName
        matchedAppGroupName = decodedMatchedAppGroupName
        matchedURLGroupName = decodedMatchedURLGroupName
        remoteASRProvider = try container.decodeIfPresent(String.self, forKey: .remoteASRProvider)
        remoteASRModel = try container.decodeIfPresent(String.self, forKey: .remoteASRModel)
        remoteASREndpoint = try container.decodeIfPresent(String.self, forKey: .remoteASREndpoint)
        remoteLLMProvider = try container.decodeIfPresent(String.self, forKey: .remoteLLMProvider)
        remoteLLMModel = try container.decodeIfPresent(String.self, forKey: .remoteLLMModel)
        remoteLLMEndpoint = try container.decodeIfPresent(String.self, forKey: .remoteLLMEndpoint)
        let decodedAudioRelativePath = try container.decodeIfPresent(String.self, forKey: .audioRelativePath)
        whisperWordTimings = try container.decodeIfPresent([WhisperHistoryWordTiming].self, forKey: .whisperWordTimings)
        senseVoiceMetadata = try container.decodeIfPresent(SenseVoiceTranscriptMetadata.self, forKey: .senseVoiceMetadata)
        transcriptSegments = try container.decodeIfPresent([TranscriptSegment].self, forKey: .transcriptSegments)
        transcriptAudioRelativePath = try container.decodeIfPresent(String.self, forKey: .transcriptAudioRelativePath)
        meetingCaptureMode = try container.decodeIfPresent(MeetingCaptureMode.self, forKey: .meetingCaptureMode)
        audioRelativePath = decodedAudioRelativePath ?? transcriptAudioRelativePath
        transcriptSummary = try container.decodeIfPresent(TranscriptSummarySnapshot.self, forKey: .transcriptSummary)
        transcriptSummaryChatMessages = try container.decodeIfPresent([TranscriptSummaryChatMessage].self, forKey: .transcriptSummaryChatMessages)
        displayTitle = try container.decodeIfPresent(String.self, forKey: .displayTitle)
        transcriptionChatMessages = try container.decodeIfPresent([TranscriptSummaryChatMessage].self, forKey: .transcriptionChatMessages)
        dictionaryHitTerms = try container.decodeIfPresent([String].self, forKey: .dictionaryHitTerms) ?? []
        dictionaryCorrectedTerms = try container.decodeIfPresent([String].self, forKey: .dictionaryCorrectedTerms) ?? []
        dictionaryCorrectionSnapshots = try container.decodeIfPresent([DictionaryCorrectionSnapshot].self, forKey: .dictionaryCorrectionSnapshots) ?? []
        dictionarySuggestedTerms = try container.decodeIfPresent([DictionarySuggestionSnapshot].self, forKey: .dictionarySuggestedTerms) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(transcriptionEngine, forKey: .transcriptionEngine)
        try container.encode(transcriptionModel, forKey: .transcriptionModel)
        try container.encode(enhancementMode, forKey: .enhancementMode)
        try container.encode(enhancementModel, forKey: .enhancementModel)
        try container.encode(kind, forKey: .kind)
        try container.encode(isTranslation, forKey: .isTranslation)
        try container.encodeIfPresent(audioDurationSeconds, forKey: .audioDurationSeconds)
        try container.encodeIfPresent(transcriptionProcessingDurationSeconds, forKey: .transcriptionProcessingDurationSeconds)
        try container.encodeIfPresent(llmDurationSeconds, forKey: .llmDurationSeconds)
        try container.encodeIfPresent(focusedAppName, forKey: .focusedAppName)
        try container.encodeIfPresent(focusedAppBundleID, forKey: .focusedAppBundleID)
        try container.encodeIfPresent(browserURLHost, forKey: .browserURLHost)
        try container.encodeIfPresent(browserURLOrigin, forKey: .browserURLOrigin)
        try container.encodeIfPresent(matchedGroupID, forKey: .matchedGroupID)
        try container.encodeIfPresent(matchedGroupName, forKey: .matchedGroupName)
        try container.encodeIfPresent(matchedAppGroupName, forKey: .matchedAppGroupName)
        try container.encodeIfPresent(matchedURLGroupName, forKey: .matchedURLGroupName)
        try container.encodeIfPresent(remoteASRProvider, forKey: .remoteASRProvider)
        try container.encodeIfPresent(remoteASRModel, forKey: .remoteASRModel)
        try container.encodeIfPresent(remoteASREndpoint, forKey: .remoteASREndpoint)
        try container.encodeIfPresent(remoteLLMProvider, forKey: .remoteLLMProvider)
        try container.encodeIfPresent(remoteLLMModel, forKey: .remoteLLMModel)
        try container.encodeIfPresent(remoteLLMEndpoint, forKey: .remoteLLMEndpoint)
        try container.encodeIfPresent(audioRelativePath, forKey: .audioRelativePath)
        try container.encodeIfPresent(whisperWordTimings, forKey: .whisperWordTimings)
        try container.encodeIfPresent(senseVoiceMetadata, forKey: .senseVoiceMetadata)
        try container.encodeIfPresent(transcriptSegments, forKey: .transcriptSegments)
        try container.encodeIfPresent(transcriptAudioRelativePath, forKey: .transcriptAudioRelativePath)
        try container.encodeIfPresent(meetingCaptureMode, forKey: .meetingCaptureMode)
        try container.encodeIfPresent(transcriptSummary, forKey: .transcriptSummary)
        try container.encodeIfPresent(transcriptSummaryChatMessages, forKey: .transcriptSummaryChatMessages)
        try container.encodeIfPresent(displayTitle, forKey: .displayTitle)
        try container.encodeIfPresent(transcriptionChatMessages, forKey: .transcriptionChatMessages)
        try container.encode(dictionaryHitTerms, forKey: .dictionaryHitTerms)
        try container.encode(dictionaryCorrectedTerms, forKey: .dictionaryCorrectedTerms)
        try container.encode(dictionaryCorrectionSnapshots, forKey: .dictionaryCorrectionSnapshots)
        try container.encode(dictionarySuggestedTerms, forKey: .dictionarySuggestedTerms)
    }
}

struct HistoryReportMetrics: Hashable {
    let totalDictationSeconds: TimeInterval
    let totalCharacters: Int
    let totalTranslationCharacters: Int
    let dailyCharacters: [Date: Int]
    let branchItems: [HistoryBranchMetricItem]
}

struct HistoryBranchMetricItem: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case app
        case url
    }

    let kind: Kind
    let title: String
    let subtitle: String?
    let bundleID: String?
    let urlHost: String?
    let urlOrigin: String?
    let characterCount: Int

    var id: String {
        switch kind {
        case .app:
            return "app:\(bundleID ?? title)"
        case .url:
            return "url:\(urlHost ?? title)"
        }
    }
}

@MainActor
final class TranscriptionHistoryStore: ObservableObject {
    @Published private(set) var entries: [TranscriptionHistoryEntry] = []

    private var allEntries: [TranscriptionHistoryEntry] = []
    private var entriesByKind: [TranscriptionHistoryKind: [TranscriptionHistoryEntry]] = [:]
    private var loadedCount = 0
    private var totalEntryCount = 0
    private var reloadGeneration = 0
    private let pageSize = 40

    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard
    private let repository: HistoryRepositoryProtocol
    private let audioArchive: HistoryAudioArchiveManaging

    init(
        repository: HistoryRepositoryProtocol? = nil,
        audioArchive: HistoryAudioArchiveManaging? = nil
    ) {
        self.repository = repository ?? HistoryRepository()
        self.audioArchive = audioArchive ?? HistoryAudioArchiveService()
        reload()
    }

    var hasMore: Bool {
        loadedCount < totalEntryCount
    }

    func historyEntries(for kind: TranscriptionHistoryKind) -> [TranscriptionHistoryEntry] {
        entriesByKind[kind] ?? []
    }

    func entry(id: UUID) -> TranscriptionHistoryEntry? {
        if let cached = allEntries.first(where: { $0.id == id }) {
            return cached
        }
        return try? repository.entry(id: id)
    }

    func updateRetentionPolicy() {
        cleanupRetainedEntriesIfNeeded()
        reload()
    }

    func reload() {
        do {
            let repositoryCount = try repository.entryCount(kind: nil, query: "")
            if repositoryCount > 0 || !legacyHistoryFileExists() {
                let firstPage = try repository.entries(kind: nil, query: "", limit: pageSize, offset: 0)
                applyLoadedEntries(firstPage, totalCount: repositoryCount, resetPagination: true)
                return
            }

            let url = try historyFileURL()
            guard fileManager.fileExists(atPath: url.path) else {
                applyReloadedEntries([], resetPagination: true)
                return
            }
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([TranscriptionHistoryEntry].self, from: data)
            applyReloadedEntries(decoded, resetPagination: true)
        } catch {
            applyReloadedEntries([], resetPagination: true)
        }
    }

    func reloadAsync() {
        reloadGeneration += 1
        let generation = reloadGeneration
        let repository = repository

        let url: URL?
        do {
            url = try historyFileURL()
        } catch {
            applyReloadedEntries([], resetPagination: true)
            return
        }

        DispatchQueue.global(qos: .utility).async { [weak self, url] in
            let loadedEntries: [TranscriptionHistoryEntry]
            let totalCount: Int
            if let repositoryCount = try? repository.entryCount(kind: nil, query: ""),
               repositoryCount > 0 || url.map({ !FileManager.default.fileExists(atPath: $0.path) }) == true {
                totalCount = repositoryCount
                loadedEntries = (try? repository.entries(kind: nil, query: "", limit: 40, offset: 0)) ?? []
            } else if let url, FileManager.default.fileExists(atPath: url.path) {
                do {
                    let data = try Data(contentsOf: url)
                    loadedEntries = try JSONDecoder().decode([TranscriptionHistoryEntry].self, from: data)
                    totalCount = loadedEntries.reduce(into: 0) { count, entry in
                        if case .transcript = entry.kind {
                            return
                        }
                        count += 1
                    }
                } catch {
                    loadedEntries = []
                    totalCount = 0
                }
            } else {
                loadedEntries = []
                totalCount = 0
            }

            DispatchQueue.main.async {
                guard let self, generation == self.reloadGeneration else { return }
                self.applyLoadedEntries(loadedEntries, totalCount: totalCount, resetPagination: false)
            }
        }
    }

    func loadNextPage() {
        guard hasMore else { return }
        let page = historyEntries(kind: nil, query: "", limit: pageSize, offset: loadedCount)
        guard !page.isEmpty else {
            totalEntryCount = loadedCount
            publishVisibleEntries()
            return
        }
        mergeLoadedEntries(page)
        loadedCount = min(loadedCount + page.count, totalEntryCount)
        refreshEntryIndexes()
        publishVisibleEntries()
    }

    func historyEntries(
        kind: TranscriptionHistoryKind?,
        query: String = "",
        limit: Int,
        offset: Int
    ) -> [TranscriptionHistoryEntry] {
        (try? repository.entries(kind: kind, query: query, limit: limit, offset: offset)) ?? []
    }

    func entryCount(kind: TranscriptionHistoryKind?, query: String = "") -> Int {
        (try? repository.entryCount(kind: kind, query: query)) ?? 0
    }

    func loadEntries(
        kind: TranscriptionHistoryKind?,
        query: String = "",
        limit: Int,
        offset: Int,
        completion: @escaping (Int, [TranscriptionHistoryEntry]) -> Void
    ) {
        let repository = repository
        DispatchQueue.global(qos: .userInitiated).async {
            let count = (try? repository.entryCount(kind: kind, query: query)) ?? 0
            let page = (try? repository.entries(kind: kind, query: query, limit: limit, offset: offset)) ?? []
            DispatchQueue.main.async {
                completion(count, page)
            }
        }
    }

    func allEntriesBatch(limit: Int, offset: Int) -> [TranscriptionHistoryEntry] {
        (try? repository.entries(kind: nil, query: "", limit: limit, offset: offset)) ?? []
    }

    func latestEntryText() -> String? {
        try? repository.latestEntryText()
    }

    func pendingDictionaryHistoryEntryCount(after checkpoint: DictionaryHistoryScanCheckpoint?) -> Int {
        (try? repository.pendingNormalEntryCount(after: checkpoint)) ?? 0
    }

    func pendingDictionaryHistoryEntries(after checkpoint: DictionaryHistoryScanCheckpoint?) -> [TranscriptionHistoryEntry] {
        (try? repository.pendingNormalEntries(after: checkpoint)) ?? []
    }

    func reportMetrics(
        dayStarts: [Date],
        branchStartDate: Date? = nil,
        completion: @escaping (HistoryReportMetrics?) -> Void
    ) {
        let repository = repository
        DispatchQueue.global(qos: .utility).async {
            let metrics = try? repository.reportMetrics(dayStarts: dayStarts, branchStartDate: branchStartDate)
            DispatchQueue.main.async {
                completion(metrics)
            }
        }
    }

    @discardableResult
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
        focusedAppBundleID: String?,
        browserURLHost: String? = nil,
        browserURLOrigin: String? = nil,
        matchedGroupID: UUID?,
        matchedGroupName: String?,
        matchedAppGroupName: String?,
        matchedURLGroupName: String?,
        remoteASRProvider: String?,
        remoteASRModel: String?,
        remoteASREndpoint: String?,
        remoteLLMProvider: String?,
        remoteLLMModel: String?,
        remoteLLMEndpoint: String?,
        audioRelativePath: String? = nil,
        whisperWordTimings: [WhisperHistoryWordTiming]?,
        senseVoiceMetadata: SenseVoiceTranscriptMetadata? = nil,
        transcriptSegments: [TranscriptSegment]? = nil,
        transcriptAudioRelativePath: String? = nil,
        meetingCaptureMode: MeetingCaptureMode? = nil,
        transcriptSummary: TranscriptSummarySnapshot? = nil,
        displayTitle: String? = nil,
        transcriptionChatMessages: [TranscriptSummaryChatMessage]? = nil,
        dictionaryHitTerms: [String],
        dictionaryCorrectedTerms: [String],
        dictionaryCorrectionSnapshots: [DictionaryCorrectionSnapshot] = [],
        dictionarySuggestedTerms: [DictionarySuggestionSnapshot]
    ) -> UUID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let entry = TranscriptionHistoryEntry(
            id: UUID(),
            text: trimmed,
            createdAt: Date(),
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
            focusedAppBundleID: focusedAppBundleID,
            browserURLHost: browserURLHost,
            browserURLOrigin: browserURLOrigin,
            matchedGroupID: matchedGroupID,
            matchedGroupName: matchedGroupName,
            matchedAppGroupName: matchedAppGroupName,
            matchedURLGroupName: matchedURLGroupName,
            remoteASRProvider: remoteASRProvider,
            remoteASRModel: remoteASRModel,
            remoteASREndpoint: remoteASREndpoint,
            remoteLLMProvider: remoteLLMProvider,
            remoteLLMModel: remoteLLMModel,
            remoteLLMEndpoint: remoteLLMEndpoint,
            audioRelativePath: audioRelativePath,
            whisperWordTimings: whisperWordTimings,
            senseVoiceMetadata: senseVoiceMetadata,
            transcriptSegments: transcriptSegments,
            transcriptAudioRelativePath: transcriptAudioRelativePath,
            meetingCaptureMode: meetingCaptureMode,
            transcriptSummary: transcriptSummary,
            displayTitle: displayTitle,
            transcriptionChatMessages: transcriptionChatMessages,
            dictionaryHitTerms: dictionaryHitTerms,
            dictionaryCorrectedTerms: dictionaryCorrectedTerms,
            dictionaryCorrectionSnapshots: dictionaryCorrectionSnapshots,
            dictionarySuggestedTerms: dictionarySuggestedTerms
        )

        totalEntryCount += 1
        cacheUpdatedEntry(entry)
        loadedCount = min(max(loadedCount + 1, min(pageSize, allEntries.count)), totalEntryCount)
        refreshEntryIndexes()
        publishVisibleEntries()
        persistEntry(entry)
        cleanupRetainedEntriesIfNeeded()
        return entry.id
    }

    @discardableResult
    func delete(id: UUID) -> Bool {
        let wasCached = allEntries.contains { $0.id == id }
        let removed: TranscriptionHistoryEntry?
        do {
            removed = try repository.delete(id: id)
        } catch {
            return false
        }

        removeCachedEntry(id: id)
        if removed != nil || wasCached {
            totalEntryCount = max(0, totalEntryCount - 1)
        }
        loadedCount = min(loadedCount, totalEntryCount)
        refreshEntryIndexes()
        publishVisibleEntries()
        removed.map(audioArchive.removeArchive(for:))
        return true
    }

    func clearAll() {
        let audioPaths = (try? repository.audioRelativePaths()) ?? []
        do {
            try repository.clearAll()
        } catch {
            return
        }

        audioPaths.forEach(audioArchive.removeArchive(relativePath:))
        allEntries = []
        loadedCount = 0
        totalEntryCount = 0
        refreshEntryIndexes()
        publishVisibleEntries()
    }

    func importAudioArchive(
        from sourceURL: URL,
        kind: TranscriptionHistoryKind,
        preferredFileName: String? = nil
    ) throws -> String {
        try audioArchive.importArchive(from: sourceURL, kind: kind, preferredFileName: preferredFileName)
    }

    func replaceAudioArchive(for entryID: UUID, with sourceURL: URL) throws -> TranscriptionHistoryEntry? {
        guard let existingEntry = entry(id: entryID) else { return nil }

        let resolvedRelativePath = try audioArchive.replaceArchive(for: existingEntry, with: sourceURL)

        let updatedEntry = existingEntry.updatingAudioRelativePath(resolvedRelativePath)
        cacheUpdatedEntry(updatedEntry)
        persistEntry(updatedEntry)
        return updatedEntry
    }

    func audioURL(for entry: TranscriptionHistoryEntry) -> URL? {
        audioArchive.audioURL(for: entry)
    }

    func exportAllAudioArchives(to destinationDirectoryURL: URL) throws -> HistoryAudioExportSummary {
        try audioArchive.exportAllArchives(to: destinationDirectoryURL) { visitBatch in
            forEachHistoryBatch(visitBatch)
        }
    }

    func currentAudioArchiveStorageStats() -> HistoryAudioStorageStats {
        let audioPaths = (try? repository.audioRelativePaths()) ?? []
        return audioArchive.storageStats(audioPaths: audioPaths)
    }

    func currentAudioArchiveStorageStats(completion: @escaping (HistoryAudioStorageStats) -> Void) {
        let repository = repository
        let rootURL = try? audioArchive.rootURL()
        DispatchQueue.global(qos: .utility).async {
            let audioPaths = (try? repository.audioRelativePaths()) ?? []
            let stats = HistoryAudioArchiveService.storageStats(rootURL: rootURL, audioPaths: audioPaths)
            DispatchQueue.main.async {
                completion(stats)
            }
        }
    }

    func applyDictionarySuggestedTerms(_ snapshotsByHistoryID: [UUID: [DictionarySuggestionSnapshot]]) {
        guard !snapshotsByHistoryID.isEmpty else { return }

        var didChange = false
        for (historyID, snapshots) in snapshotsByHistoryID {
            guard let existingEntry = entry(id: historyID) else { continue }
            let merged = mergeSnapshots(
                existing: existingEntry.dictionarySuggestedTerms,
                incoming: snapshots
            )
            guard merged != existingEntry.dictionarySuggestedTerms else { continue }
            let updatedEntry = existingEntry.updatingDictionarySuggestedTerms(merged)
            cacheUpdatedEntry(updatedEntry)
            persistEntry(updatedEntry)
            didChange = true
        }

        guard didChange else { return }
        refreshEntryIndexes()
        publishVisibleEntries()
    }

    func applyDictionaryCorrectedTerms(_ correctedTermsByHistoryID: [UUID: [String]]) {
        guard !correctedTermsByHistoryID.isEmpty else { return }

        var didChange = false
        for (historyID, correctedTerms) in correctedTermsByHistoryID {
            guard let existingEntry = entry(id: historyID) else { continue }
            let merged = mergeUniqueTerms(
                existing: existingEntry.dictionaryCorrectedTerms,
                incoming: correctedTerms
            )
            guard merged != existingEntry.dictionaryCorrectedTerms else { continue }
            let updatedEntry = existingEntry.updatingDictionaryCorrectedTerms(merged)
            cacheUpdatedEntry(updatedEntry)
            persistEntry(updatedEntry)
            didChange = true
        }

        guard didChange else { return }
        refreshEntryIndexes()
        publishVisibleEntries()
    }

    func applyDictionaryCorrectionSnapshots(_ snapshotsByHistoryID: [UUID: [DictionaryCorrectionSnapshot]]) {
        guard !snapshotsByHistoryID.isEmpty else { return }

        var didChange = false
        for (historyID, snapshots) in snapshotsByHistoryID {
            guard let existingEntry = entry(id: historyID) else { continue }
            let merged = mergeCorrectionSnapshots(
                existing: existingEntry.dictionaryCorrectionSnapshots,
                incoming: snapshots
            )
            guard merged != existingEntry.dictionaryCorrectionSnapshots else { continue }
            let updatedEntry = existingEntry.updatingDictionaryCorrectionSnapshots(merged)
            cacheUpdatedEntry(updatedEntry)
            persistEntry(updatedEntry)
            didChange = true
        }

        guard didChange else { return }
        refreshEntryIndexes()
        publishVisibleEntries()
    }

    func applyDictionaryCorrectionResult(
        historyID: UUID,
        updatedText: String,
        correctedTerms: [String],
        correctionSnapshots: [DictionaryCorrectionSnapshot]
    ) {
        guard let existingEntry = entry(id: historyID) else { return }

        let trimmedUpdatedText = updatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let mergedTerms = mergeUniqueTerms(
            existing: existingEntry.dictionaryCorrectedTerms,
            incoming: correctedTerms
        )
        let mergedSnapshots = mergeCorrectionSnapshots(
            existing: existingEntry.dictionaryCorrectionSnapshots,
            incoming: correctionSnapshots
        )

        guard !trimmedUpdatedText.isEmpty else { return }
        let didTextChange = trimmedUpdatedText != existingEntry.text
        let didTermsChange = mergedTerms != existingEntry.dictionaryCorrectedTerms
        let didSnapshotsChange = mergedSnapshots != existingEntry.dictionaryCorrectionSnapshots
        guard didTextChange || didTermsChange || didSnapshotsChange else { return }

        let updatedEntry = existingEntry.updatingDictionaryCorrectionResult(
            text: trimmedUpdatedText,
            dictionaryCorrectedTerms: mergedTerms,
            dictionaryCorrectionSnapshots: mergedSnapshots
        )
        cacheUpdatedEntry(updatedEntry)

        refreshEntryIndexes()
        publishVisibleEntries()
        persistEntry(updatedEntry)
    }

    func replaceDictionaryCorrectionResult(
        historyID: UUID,
        updatedText: String,
        correctedTerms: [String],
        correctionSnapshots: [DictionaryCorrectionSnapshot]
    ) {
        guard let existingEntry = entry(id: historyID) else { return }

        let trimmedUpdatedText = updatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let mergedTerms = mergeUniqueTerms(
            existing: existingEntry.dictionaryCorrectedTerms,
            incoming: correctedTerms
        )

        guard !trimmedUpdatedText.isEmpty else { return }
        let didTextChange = trimmedUpdatedText != existingEntry.text
        let didTermsChange = mergedTerms != existingEntry.dictionaryCorrectedTerms
        let didSnapshotsChange = correctionSnapshots != existingEntry.dictionaryCorrectionSnapshots
        guard didTextChange || didTermsChange || didSnapshotsChange else { return }

        let updatedEntry = existingEntry.updatingDictionaryCorrectionResult(
            text: trimmedUpdatedText,
            dictionaryCorrectedTerms: mergedTerms,
            dictionaryCorrectionSnapshots: correctionSnapshots
        )
        cacheUpdatedEntry(updatedEntry)

        refreshEntryIndexes()
        publishVisibleEntries()
        persistEntry(updatedEntry)
    }

    @discardableResult
    func updateTranscriptSummary(_ summary: TranscriptSummarySnapshot?, for entryID: UUID) -> TranscriptionHistoryEntry? {
        guard let existingEntry = entry(id: entryID) else { return nil }
        let updatedEntry = existingEntry.updatingTranscriptSummary(summary)
        cacheUpdatedEntry(updatedEntry)
        refreshEntryIndexes()
        publishVisibleEntries()
        persistEntry(updatedEntry)
        return updatedEntry
    }

    @discardableResult
    func updateSummaryChatMessages(_ messages: [TranscriptSummaryChatMessage], for entryID: UUID) -> TranscriptionHistoryEntry? {
        guard let existingEntry = entry(id: entryID) else { return nil }
        let updatedEntry = existingEntry.updatingSummaryChatMessages(messages)
        cacheUpdatedEntry(updatedEntry)
        refreshEntryIndexes()
        publishVisibleEntries()
        persistEntry(updatedEntry)
        return updatedEntry
    }

    @discardableResult
    func updateTranscriptSegments(_ segments: [TranscriptSegment], for entryID: UUID) -> TranscriptionHistoryEntry? {
        guard let existingEntry = entry(id: entryID) else { return nil }
        let text = TranscriptFormatter.joinedText(for: segments)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let updatedEntry = existingEntry.updatingTranscriptSegments(segments, text: text)
        cacheUpdatedEntry(updatedEntry)
        refreshEntryIndexes()
        publishVisibleEntries()
        persistEntry(updatedEntry)
        return updatedEntry
    }

    @discardableResult
    func updateTranscriptionChatMessages(_ messages: [TranscriptSummaryChatMessage], for entryID: UUID) -> TranscriptionHistoryEntry? {
        guard let existingEntry = entry(id: entryID) else { return nil }
        let updatedEntry = existingEntry.updatingTranscriptionChatMessages(messages)
        cacheUpdatedEntry(updatedEntry)
        refreshEntryIndexes()
        publishVisibleEntries()
        persistEntry(updatedEntry)
        return updatedEntry
    }

    @discardableResult
    func updateTranscriptionEntry(
        _ entryID: UUID,
        text: String,
        createdAt: Date,
        audioDurationSeconds: TimeInterval?,
        transcriptionProcessingDurationSeconds: TimeInterval?,
        llmDurationSeconds: TimeInterval?,
        whisperWordTimings: [WhisperHistoryWordTiming]?,
        senseVoiceMetadata: SenseVoiceTranscriptMetadata?,
        transcriptionChatMessages: [TranscriptSummaryChatMessage],
        dictionaryHitTerms: [String],
        dictionaryCorrectedTerms: [String],
        dictionaryCorrectionSnapshots: [DictionaryCorrectionSnapshot] = [],
        dictionarySuggestedTerms: [DictionarySuggestionSnapshot]
    ) -> TranscriptionHistoryEntry? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let existingEntry = entry(id: entryID)
        else {
            return nil
        }

        let updatedEntry = existingEntry.updatingTranscriptionEntry(
            text: trimmed,
            createdAt: createdAt,
            audioDurationSeconds: audioDurationSeconds,
            transcriptionProcessingDurationSeconds: transcriptionProcessingDurationSeconds,
            llmDurationSeconds: llmDurationSeconds,
            whisperWordTimings: whisperWordTimings,
            senseVoiceMetadata: senseVoiceMetadata,
            transcriptionChatMessages: transcriptionChatMessages,
            dictionaryHitTerms: dictionaryHitTerms,
            dictionaryCorrectedTerms: dictionaryCorrectedTerms,
            dictionaryCorrectionSnapshots: dictionaryCorrectionSnapshots,
            dictionarySuggestedTerms: dictionarySuggestedTerms
        )
        cacheUpdatedEntry(updatedEntry)
        refreshEntryIndexes()
        publishVisibleEntries()
        persistEntry(updatedEntry)
        return updatedEntry
    }

    private func persistEntry(_ entry: TranscriptionHistoryEntry) {
        do {
            try repository.upsert(entry)
        } catch {
            // Keep UI responsive even if persistence fails.
        }
    }

    private var historyCleanupEnabled: Bool {
        defaults.object(forKey: AppPreferenceKey.historyCleanupEnabled) as? Bool ?? true
    }

    private var historyRetentionPeriod: HistoryRetentionPeriod {
        let raw = defaults.string(forKey: AppPreferenceKey.historyRetentionPeriod)
        return HistoryRetentionPeriod(rawValue: raw ?? "") ?? .ninetyDays
    }

    private func applyReloadedEntries(
        _ decodedEntries: [TranscriptionHistoryEntry],
        resetPagination: Bool
    ) {
        allEntries = decodedEntries
            .filter { $0.kind != .transcript }
            .sorted { $0.createdAt > $1.createdAt }
        totalEntryCount = allEntries.count

        let targetLoadedCount: Int
        if resetPagination || loadedCount == 0 {
            targetLoadedCount = pageSize
        } else {
            targetLoadedCount = max(loadedCount, pageSize)
        }

        loadedCount = min(targetLoadedCount, allEntries.count)
        refreshEntryIndexes()
        publishVisibleEntries()
    }

    private func applyLoadedEntries(
        _ loadedEntries: [TranscriptionHistoryEntry],
        totalCount: Int,
        resetPagination: Bool
    ) {
        allEntries = uniqueSortedEntries(loadedEntries.filter { $0.kind != .transcript })
        totalEntryCount = max(0, totalCount)

        let targetLoadedCount: Int
        if resetPagination || loadedCount == 0 {
            targetLoadedCount = min(pageSize, allEntries.count)
        } else {
            targetLoadedCount = min(max(loadedCount, pageSize), allEntries.count)
        }

        loadedCount = targetLoadedCount
        refreshEntryIndexes()
        publishVisibleEntries()
        cleanupRetainedEntriesIfNeeded()
    }

    private func cleanupRetainedEntriesIfNeeded(referenceDate: Date = Date()) {
        guard historyCleanupEnabled else { return }
        guard let days = historyRetentionPeriod.days else { return }

        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: referenceDate) ?? referenceDate
        let removedEntries = (try? repository.deleteEntries(olderThan: cutoff)) ?? []
        guard !removedEntries.isEmpty else { return }
        removedEntries.forEach(audioArchive.removeArchive(for:))
        let removedIDs = Set(removedEntries.map(\.id))
        allEntries.removeAll { removedIDs.contains($0.id) }
        totalEntryCount = max(0, totalEntryCount - removedEntries.count)
        loadedCount = min(loadedCount, allEntries.count)
        refreshEntryIndexes()
        publishVisibleEntries()
    }

    private func refreshEntryIndexes() {
        entriesByKind = Dictionary(grouping: allEntries, by: \.kind)
    }

    private func publishVisibleEntries() {
        entries = Array(allEntries.prefix(loadedCount))
    }

    private func cacheUpdatedEntry(_ entry: TranscriptionHistoryEntry) {
        if let index = allEntries.firstIndex(where: { $0.id == entry.id }) {
            allEntries[index] = entry
        } else {
            allEntries.append(entry)
        }
        allEntries = uniqueSortedEntries(allEntries)
        if loadedCount == 0 {
            loadedCount = min(pageSize, allEntries.count)
        } else {
            loadedCount = min(max(loadedCount, min(pageSize, allEntries.count)), allEntries.count)
        }
    }

    private func mergeLoadedEntries(_ entries: [TranscriptionHistoryEntry]) {
        allEntries = uniqueSortedEntries(allEntries + entries.filter { $0.kind != .transcript })
    }

    private func removeCachedEntry(id: UUID) {
        allEntries.removeAll { $0.id == id }
    }

    private func uniqueSortedEntries(_ entries: [TranscriptionHistoryEntry]) -> [TranscriptionHistoryEntry] {
        var seen = Set<UUID>()
        return entries
            .sorted { $0.createdAt > $1.createdAt }
            .filter { seen.insert($0.id).inserted }
    }

    private func forEachHistoryBatch(_ body: ([TranscriptionHistoryEntry]) -> Void) {
        let batchSize = 500
        var offset = 0
        while true {
            let batch = allEntriesBatch(limit: batchSize, offset: offset)
            guard !batch.isEmpty else { break }
            body(batch)
            offset += batch.count
        }
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

    private func legacyHistoryFileExists() -> Bool {
        (try? historyFileURL()).map { fileManager.fileExists(atPath: $0.path) } ?? false
    }

    private func mergeSnapshots(
        existing: [DictionarySuggestionSnapshot],
        incoming: [DictionarySuggestionSnapshot]
    ) -> [DictionarySuggestionSnapshot] {
        guard !incoming.isEmpty else { return existing }
        var merged = existing
        var seen = Set(existing.map(\.id))
        for snapshot in incoming where seen.insert(snapshot.id).inserted {
            merged.append(snapshot)
        }
        return merged
    }

    private func mergeCorrectionSnapshots(
        existing: [DictionaryCorrectionSnapshot],
        incoming: [DictionaryCorrectionSnapshot]
    ) -> [DictionaryCorrectionSnapshot] {
        guard !incoming.isEmpty else { return existing }
        var merged = existing
        var seen = Set(existing)
        for snapshot in incoming where seen.insert(snapshot).inserted {
            merged.append(snapshot)
        }
        return merged.sorted { lhs, rhs in
            if lhs.finalLocation == rhs.finalLocation {
                return lhs.finalLength < rhs.finalLength
            }
            return lhs.finalLocation < rhs.finalLocation
        }
    }

    private func mergeUniqueTerms(existing: [String], incoming: [String]) -> [String] {
        var merged = existing
        let existingNormalized = Set(existing.map(DictionaryStore.normalizeTerm))
        var appended = Set<String>()

        for term in incoming {
            let normalized = DictionaryStore.normalizeTerm(term)
            guard !normalized.isEmpty else { continue }
            guard !existingNormalized.contains(normalized) else { continue }
            guard appended.insert(normalized).inserted else { continue }
            merged.append(term)
        }

        return merged
    }
}
