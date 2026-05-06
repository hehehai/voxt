import Foundation
import Combine

enum TranscriptionHistoryKind: String, Codable {
    case normal
    case translation
    case rewrite
    case meeting
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
    let meetingSegments: [MeetingTranscriptSegment]?
    let meetingAudioRelativePath: String?
    let meetingSummary: MeetingSummarySnapshot?
    let meetingSummaryChatMessages: [MeetingSummaryChatMessage]?
    let displayTitle: String?
    let transcriptionChatMessages: [MeetingSummaryChatMessage]?
    let dictionaryHitTerms: [String]
    let dictionaryCorrectedTerms: [String]
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
        case meetingSegments
        case meetingAudioRelativePath
        case meetingSummary
        case meetingSummaryChatMessages
        case displayTitle
        case transcriptionChatMessages
        case dictionaryHitTerms
        case dictionaryCorrectedTerms
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
        meetingSegments: [MeetingTranscriptSegment]? = nil,
        meetingAudioRelativePath: String? = nil,
        meetingSummary: MeetingSummarySnapshot? = nil,
        meetingSummaryChatMessages: [MeetingSummaryChatMessage]? = nil,
        displayTitle: String? = nil,
        transcriptionChatMessages: [MeetingSummaryChatMessage]? = nil,
        dictionaryHitTerms: [String],
        dictionaryCorrectedTerms: [String],
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
        self.audioRelativePath = audioRelativePath ?? meetingAudioRelativePath
        self.whisperWordTimings = whisperWordTimings
        self.meetingSegments = meetingSegments
        self.meetingAudioRelativePath = meetingAudioRelativePath
        self.meetingSummary = meetingSummary
        self.meetingSummaryChatMessages = meetingSummaryChatMessages
        self.displayTitle = displayTitle
        self.transcriptionChatMessages = transcriptionChatMessages
        self.dictionaryHitTerms = dictionaryHitTerms
        self.dictionaryCorrectedTerms = dictionaryCorrectedTerms
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
        meetingSegments = try container.decodeIfPresent([MeetingTranscriptSegment].self, forKey: .meetingSegments)
        meetingAudioRelativePath = try container.decodeIfPresent(String.self, forKey: .meetingAudioRelativePath)
        audioRelativePath = decodedAudioRelativePath ?? meetingAudioRelativePath
        meetingSummary = try container.decodeIfPresent(MeetingSummarySnapshot.self, forKey: .meetingSummary)
        meetingSummaryChatMessages = try container.decodeIfPresent([MeetingSummaryChatMessage].self, forKey: .meetingSummaryChatMessages)
        displayTitle = try container.decodeIfPresent(String.self, forKey: .displayTitle)
        transcriptionChatMessages = try container.decodeIfPresent([MeetingSummaryChatMessage].self, forKey: .transcriptionChatMessages)
        dictionaryHitTerms = try container.decodeIfPresent([String].self, forKey: .dictionaryHitTerms) ?? []
        dictionaryCorrectedTerms = try container.decodeIfPresent([String].self, forKey: .dictionaryCorrectedTerms) ?? []
        dictionarySuggestedTerms = try container.decodeIfPresent([DictionarySuggestionSnapshot].self, forKey: .dictionarySuggestedTerms) ?? []
    }
}

@MainActor
final class TranscriptionHistoryStore: ObservableObject {
    @Published private(set) var entries: [TranscriptionHistoryEntry] = []

    private var allEntries: [TranscriptionHistoryEntry] = []
    private var loadedCount = 0
    private var reloadGeneration = 0
    private let pageSize = 40
    private let maxStoredEntries = 1000

    private let fileManager = FileManager.default
    private let defaults = UserDefaults.standard
    private let persistenceCoordinator = AsyncJSONPersistenceCoordinator(
        label: "com.voxt.transcription-history.persistence"
    )

    init() {
        reload()
    }

    var hasMore: Bool {
        loadedCount < allEntries.count
    }

    var allHistoryEntries: [TranscriptionHistoryEntry] {
        allEntries
    }

    func entry(id: UUID) -> TranscriptionHistoryEntry? {
        allEntries.first(where: { $0.id == id })
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

        let url: URL?
        do {
            url = try historyFileURL()
        } catch {
            applyReloadedEntries([], resetPagination: true)
            return
        }

        DispatchQueue.global(qos: .utility).async { [weak self, url] in
            let decodedEntries: [TranscriptionHistoryEntry]
            if let url, FileManager.default.fileExists(atPath: url.path) {
                do {
                    let data = try Data(contentsOf: url)
                    decodedEntries = try JSONDecoder().decode([TranscriptionHistoryEntry].self, from: data)
                } catch {
                    decodedEntries = []
                }
            } else {
                decodedEntries = []
            }

            DispatchQueue.main.async {
                guard let self, generation == self.reloadGeneration else { return }
                self.applyReloadedEntries(decodedEntries, resetPagination: false)
            }
        }
    }

    func loadNextPage() {
        guard hasMore else { return }
        loadedCount = min(loadedCount + pageSize, allEntries.count)
        entries = Array(allEntries.prefix(loadedCount))
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
        meetingSegments: [MeetingTranscriptSegment]? = nil,
        meetingAudioRelativePath: String? = nil,
        meetingSummary: MeetingSummarySnapshot? = nil,
        displayTitle: String? = nil,
        transcriptionChatMessages: [MeetingSummaryChatMessage]? = nil,
        dictionaryHitTerms: [String],
        dictionaryCorrectedTerms: [String],
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
            meetingSegments: meetingSegments,
            meetingAudioRelativePath: meetingAudioRelativePath,
            meetingSummary: meetingSummary,
            displayTitle: displayTitle,
            transcriptionChatMessages: transcriptionChatMessages,
            dictionaryHitTerms: dictionaryHitTerms,
            dictionaryCorrectedTerms: dictionaryCorrectedTerms,
            dictionarySuggestedTerms: dictionarySuggestedTerms
        )

        allEntries.insert(entry, at: 0)
        if allEntries.count > maxStoredEntries {
            allEntries = Array(allEntries.prefix(maxStoredEntries))
        }
        _ = applyRetentionPolicyIfNeeded()

        loadedCount = min(max(loadedCount + 1, pageSize), allEntries.count)
        entries = Array(allEntries.prefix(loadedCount))
        persist()
        return entry.id
    }

    func delete(id: UUID) {
        let removed = allEntries.filter { $0.id == id }
        allEntries.removeAll { $0.id == id }
        loadedCount = min(loadedCount, allEntries.count)
        entries = Array(allEntries.prefix(loadedCount))
        removed.forEach(removeAudioIfNeeded(for:))
        persist()
    }

    func clearAll() {
        allEntries.forEach(removeAudioIfNeeded(for:))
        allEntries = []
        entries = []
        loadedCount = 0
        persist()
    }

    func importAudioArchive(
        from sourceURL: URL,
        kind: TranscriptionHistoryKind,
        preferredFileName: String? = nil
    ) throws -> String {
        let resolvedFileName = sanitizedAudioFileName(
            preferredFileName?.trimmingCharacters(in: .whitespacesAndNewlines),
            fallbackKind: kind
        )
        let relativePath = "\(audioFolderName(for: kind))/\(resolvedFileName)"
        let destinationURL = try historyAssetsDirectoryURL().appendingPathComponent(relativePath)
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
        return relativePath
    }

    func replaceAudioArchive(for entryID: UUID, with sourceURL: URL) throws -> TranscriptionHistoryEntry? {
        guard let index = allEntries.firstIndex(where: { $0.id == entryID }) else { return nil }

        let existingEntry = allEntries[index]
        let relativePath = existingEntry.audioRelativePath ?? existingEntry.meetingAudioRelativePath
        let resolvedRelativePath = relativePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? relativePath!
            : "\(audioFolderName(for: existingEntry.kind))/\(sanitizedAudioFileName(nil, fallbackKind: existingEntry.kind))"
        let destinationURL = try historyAssetsDirectoryURL().appendingPathComponent(resolvedRelativePath)
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: sourceURL, to: destinationURL)

        allEntries[index] = existingEntry.updatingAudioRelativePath(resolvedRelativePath)
        entries = Array(allEntries.prefix(loadedCount))
        persist()
        return allEntries[index]
    }

    func audioURL(for entry: TranscriptionHistoryEntry) -> URL? {
        let relativePath = entry.audioRelativePath ?? entry.meetingAudioRelativePath
        guard let relativePath, !relativePath.isEmpty else {
            return nil
        }
        do {
            return try historyAssetsDirectoryURL().appendingPathComponent(relativePath)
        } catch {
            return nil
        }
    }

    func exportAllAudioArchives(to destinationDirectoryURL: URL) throws -> HistoryAudioExportSummary {
        try fileManager.createDirectory(at: destinationDirectoryURL, withIntermediateDirectories: true)

        var exportedCount = 0
        var skippedCount = 0
        var failedCount = 0

        for entry in allEntries {
            guard let sourceURL = audioURL(for: entry) else {
                skippedCount += 1
                continue
            }
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                skippedCount += 1
                continue
            }

            do {
                let folderURL = destinationDirectoryURL.appendingPathComponent(audioFolderName(for: entry.kind), isDirectory: true)
                try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
                let destinationURL = folderURL.appendingPathComponent(exportFileName(for: entry))
                if fileManager.fileExists(atPath: destinationURL.path) {
                    try fileManager.removeItem(at: destinationURL)
                }
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                exportedCount += 1
            } catch {
                failedCount += 1
            }
        }

        return HistoryAudioExportSummary(
            exportedCount: exportedCount,
            skippedCount: skippedCount,
            failedCount: failedCount
        )
    }

    func currentAudioArchiveStorageStats() -> HistoryAudioStorageStats {
        var storedFileCount = 0
        var totalBytes: Int64 = 0

        for entry in allEntries {
            guard let sourceURL = audioURL(for: entry),
                  fileManager.fileExists(atPath: sourceURL.path)
            else {
                continue
            }

            storedFileCount += 1
            let fileSize = (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            totalBytes += Int64(fileSize)
        }

        return HistoryAudioStorageStats(
            storedFileCount: storedFileCount,
            totalBytes: totalBytes
        )
    }

    func applyDictionarySuggestedTerms(_ snapshotsByHistoryID: [UUID: [DictionarySuggestionSnapshot]]) {
        guard !snapshotsByHistoryID.isEmpty else { return }

        var didChange = false
        for (historyID, snapshots) in snapshotsByHistoryID {
            guard let index = allEntries.firstIndex(where: { $0.id == historyID }) else { continue }
            let merged = mergeSnapshots(
                existing: allEntries[index].dictionarySuggestedTerms,
                incoming: snapshots
            )
            guard merged != allEntries[index].dictionarySuggestedTerms else { continue }
            allEntries[index] = allEntries[index].updatingDictionarySuggestedTerms(merged)
            didChange = true
        }

        guard didChange else { return }
        entries = Array(allEntries.prefix(loadedCount))
        persist()
    }

    @discardableResult
    func updateMeetingSummary(_ summary: MeetingSummarySnapshot?, for entryID: UUID) -> TranscriptionHistoryEntry? {
        guard let index = allEntries.firstIndex(where: { $0.id == entryID }) else { return nil }
        allEntries[index] = allEntries[index].updatingMeetingSummary(summary)
        entries = Array(allEntries.prefix(loadedCount))
        persist()
        return allEntries[index]
    }

    @discardableResult
    func updateMeetingSummaryChatMessages(_ messages: [MeetingSummaryChatMessage], for entryID: UUID) -> TranscriptionHistoryEntry? {
        guard let index = allEntries.firstIndex(where: { $0.id == entryID }) else { return nil }
        allEntries[index] = allEntries[index].updatingMeetingSummaryChatMessages(messages)
        entries = Array(allEntries.prefix(loadedCount))
        persist()
        return allEntries[index]
    }

    @discardableResult
    func updateTranscriptionChatMessages(_ messages: [MeetingSummaryChatMessage], for entryID: UUID) -> TranscriptionHistoryEntry? {
        guard let index = allEntries.firstIndex(where: { $0.id == entryID }) else { return nil }
        allEntries[index] = allEntries[index].updatingTranscriptionChatMessages(messages)
        entries = Array(allEntries.prefix(loadedCount))
        persist()
        return allEntries[index]
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
        transcriptionChatMessages: [MeetingSummaryChatMessage],
        dictionaryHitTerms: [String],
        dictionaryCorrectedTerms: [String],
        dictionarySuggestedTerms: [DictionarySuggestionSnapshot]
    ) -> TranscriptionHistoryEntry? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = allEntries.firstIndex(where: { $0.id == entryID })
        else {
            return nil
        }

        allEntries[index] = allEntries[index].updatingTranscriptionEntry(
            text: trimmed,
            createdAt: createdAt,
            audioDurationSeconds: audioDurationSeconds,
            transcriptionProcessingDurationSeconds: transcriptionProcessingDurationSeconds,
            llmDurationSeconds: llmDurationSeconds,
            whisperWordTimings: whisperWordTimings,
            transcriptionChatMessages: transcriptionChatMessages,
            dictionaryHitTerms: dictionaryHitTerms,
            dictionaryCorrectedTerms: dictionaryCorrectedTerms,
            dictionarySuggestedTerms: dictionarySuggestedTerms
        )
        allEntries.sort { $0.createdAt > $1.createdAt }
        entries = Array(allEntries.prefix(loadedCount))
        persist()
        return allEntries.first(where: { $0.id == entryID })
    }

    private func persist() {
        do {
            let url = try historyFileURL()
            persistenceCoordinator.scheduleWrite(allEntries, to: url)
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
        allEntries = decodedEntries.sorted { $0.createdAt > $1.createdAt }
        let didPrune = applyRetentionPolicyIfNeeded()

        let targetLoadedCount: Int
        if resetPagination || loadedCount == 0 {
            targetLoadedCount = pageSize
        } else {
            targetLoadedCount = max(loadedCount, pageSize)
        }

        loadedCount = min(targetLoadedCount, allEntries.count)
        entries = Array(allEntries.prefix(loadedCount))

        if didPrune {
            persist()
        }
    }

    private func applyRetentionPolicyIfNeeded(referenceDate: Date = Date()) -> Bool {
        guard historyCleanupEnabled else { return false }
        guard let days = historyRetentionPeriod.days else { return false }

        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: referenceDate) ?? referenceDate
        let originalCount = allEntries.count
        let removedEntries = allEntries.filter { $0.createdAt < cutoff }
        allEntries.removeAll { $0.createdAt < cutoff }
        removedEntries.forEach(removeAudioIfNeeded(for:))
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

    private func historyAssetsDirectoryURL() throws -> URL {
        try HistoryAudioStorageDirectoryManager.ensureRootDirectoryExists()
    }

    private func removeAudioIfNeeded(for entry: TranscriptionHistoryEntry) {
        let relativePath = entry.audioRelativePath ?? entry.meetingAudioRelativePath
        guard let relativePath, !relativePath.isEmpty else { return }
        do {
            let url = try historyAssetsDirectoryURL().appendingPathComponent(relativePath)
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        } catch {
            return
        }
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

    private func audioFolderName(for kind: TranscriptionHistoryKind) -> String {
        switch kind {
        case .normal:
            return "transcription"
        case .translation:
            return "translation"
        case .rewrite:
            return "rewrite"
        case .meeting:
            return "meeting"
        }
    }

    private func sanitizedAudioFileName(_ preferredFileName: String?, fallbackKind: TranscriptionHistoryKind) -> String {
        let trimmedPreferred = preferredFileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let baseName = trimmedPreferred.isEmpty ? "\(audioFolderName(for: fallbackKind))-\(UUID().uuidString)" : trimmedPreferred
        let filtered = baseName.map { character -> Character in
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                return character
            }
            return "-"
        }
        let normalized = String(filtered).trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        let resolved = normalized.isEmpty ? "\(audioFolderName(for: fallbackKind))-\(UUID().uuidString)" : normalized
        return resolved.hasSuffix(".wav") ? resolved : "\(resolved).wav"
    }

    private func exportFileName(for entry: TranscriptionHistoryEntry) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(formatter.string(from: entry.createdAt))-\(audioFolderName(for: entry.kind))-\(entry.id.uuidString).wav"
    }
}

struct HistoryAudioExportSummary: Equatable {
    let exportedCount: Int
    let skippedCount: Int
    let failedCount: Int
}

struct HistoryAudioStorageStats: Equatable {
    let storedFileCount: Int
    let totalBytes: Int64
}

private extension TranscriptionHistoryEntry {
    func updatingDictionarySuggestedTerms(_ dictionarySuggestedTerms: [DictionarySuggestionSnapshot]) -> TranscriptionHistoryEntry {
        TranscriptionHistoryEntry(
            id: id,
            text: text,
            createdAt: createdAt,
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
            meetingSegments: meetingSegments,
            meetingAudioRelativePath: meetingAudioRelativePath,
            meetingSummary: meetingSummary,
            meetingSummaryChatMessages: meetingSummaryChatMessages,
            displayTitle: displayTitle,
            transcriptionChatMessages: transcriptionChatMessages,
            dictionaryHitTerms: dictionaryHitTerms,
            dictionaryCorrectedTerms: dictionaryCorrectedTerms,
            dictionarySuggestedTerms: dictionarySuggestedTerms
        )
    }

    func updatingMeetingSummary(_ meetingSummary: MeetingSummarySnapshot?) -> TranscriptionHistoryEntry {
        TranscriptionHistoryEntry(
            id: id,
            text: text,
            createdAt: createdAt,
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
            meetingSegments: meetingSegments,
            meetingAudioRelativePath: meetingAudioRelativePath,
            meetingSummary: meetingSummary,
            meetingSummaryChatMessages: meetingSummaryChatMessages,
            displayTitle: displayTitle,
            transcriptionChatMessages: transcriptionChatMessages,
            dictionaryHitTerms: dictionaryHitTerms,
            dictionaryCorrectedTerms: dictionaryCorrectedTerms,
            dictionarySuggestedTerms: dictionarySuggestedTerms
        )
    }

    func updatingMeetingSummaryChatMessages(_ meetingSummaryChatMessages: [MeetingSummaryChatMessage]) -> TranscriptionHistoryEntry {
        TranscriptionHistoryEntry(
            id: id,
            text: text,
            createdAt: createdAt,
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
            meetingSegments: meetingSegments,
            meetingAudioRelativePath: meetingAudioRelativePath,
            meetingSummary: meetingSummary,
            meetingSummaryChatMessages: meetingSummaryChatMessages,
            displayTitle: displayTitle,
            transcriptionChatMessages: transcriptionChatMessages,
            dictionaryHitTerms: dictionaryHitTerms,
            dictionaryCorrectedTerms: dictionaryCorrectedTerms,
            dictionarySuggestedTerms: dictionarySuggestedTerms
        )
    }

    func updatingTranscriptionChatMessages(_ transcriptionChatMessages: [MeetingSummaryChatMessage]) -> TranscriptionHistoryEntry {
        TranscriptionHistoryEntry(
            id: id,
            text: text,
            createdAt: createdAt,
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
            meetingSegments: meetingSegments,
            meetingAudioRelativePath: meetingAudioRelativePath,
            meetingSummary: meetingSummary,
            meetingSummaryChatMessages: meetingSummaryChatMessages,
            displayTitle: displayTitle,
            transcriptionChatMessages: transcriptionChatMessages,
            dictionaryHitTerms: dictionaryHitTerms,
            dictionaryCorrectedTerms: dictionaryCorrectedTerms,
            dictionarySuggestedTerms: dictionarySuggestedTerms
        )
    }

    func updatingTranscriptionEntry(
        text: String,
        createdAt: Date,
        audioDurationSeconds: TimeInterval?,
        transcriptionProcessingDurationSeconds: TimeInterval?,
        llmDurationSeconds: TimeInterval?,
        whisperWordTimings: [WhisperHistoryWordTiming]?,
        transcriptionChatMessages: [MeetingSummaryChatMessage],
        dictionaryHitTerms: [String],
        dictionaryCorrectedTerms: [String],
        dictionarySuggestedTerms: [DictionarySuggestionSnapshot]
    ) -> TranscriptionHistoryEntry {
        TranscriptionHistoryEntry(
            id: id,
            text: text,
            createdAt: createdAt,
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
            meetingSegments: meetingSegments,
            meetingAudioRelativePath: meetingAudioRelativePath,
            meetingSummary: meetingSummary,
            meetingSummaryChatMessages: meetingSummaryChatMessages,
            displayTitle: displayTitle,
            transcriptionChatMessages: transcriptionChatMessages,
            dictionaryHitTerms: dictionaryHitTerms,
            dictionaryCorrectedTerms: dictionaryCorrectedTerms,
            dictionarySuggestedTerms: dictionarySuggestedTerms
        )
    }

    func updatingAudioRelativePath(_ audioRelativePath: String?) -> TranscriptionHistoryEntry {
        TranscriptionHistoryEntry(
            id: id,
            text: text,
            createdAt: createdAt,
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
            meetingSegments: meetingSegments,
            meetingAudioRelativePath: meetingAudioRelativePath,
            meetingSummary: meetingSummary,
            meetingSummaryChatMessages: meetingSummaryChatMessages,
            displayTitle: displayTitle,
            transcriptionChatMessages: transcriptionChatMessages,
            dictionaryHitTerms: dictionaryHitTerms,
            dictionaryCorrectedTerms: dictionaryCorrectedTerms,
            dictionarySuggestedTerms: dictionarySuggestedTerms
        )
    }
}
