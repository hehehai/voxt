import Foundation
import Combine

enum DictionarySuggestionSourceContext: String, Codable {
    case history
    case correction
    case repeatObservation
}

enum DictionaryHistoryScanPromptLanguageSupport {
    static let noneValue = "None"

    static func otherLanguagesPromptValue(from codes: [String]) -> String {
        let options = Array(codes.dropFirst())
            .compactMap(UserMainLanguageOption.option(for:))
        guard !options.isEmpty else { return noneValue }
        return options.map(\.promptName).joined(separator: ", ")
    }
}

enum DictionarySuggestionStatus: String, Codable {
    case pending
    case dismissed
    case added
}

struct DictionarySuggestionSnapshot: Identifiable, Codable, Hashable {
    let term: String
    let normalizedTerm: String
    let groupID: UUID?
    let groupNameSnapshot: String?

    var id: String {
        "\(normalizedTerm)|\(groupID?.uuidString ?? "global")"
    }
}

struct DictionarySuggestion: Identifiable, Codable, Hashable {
    let id: UUID
    var term: String
    var normalizedTerm: String
    var sourceContext: DictionarySuggestionSourceContext
    var status: DictionarySuggestionStatus
    var firstSeenAt: Date
    var lastSeenAt: Date
    var seenCount: Int
    var lastHistoryEntryID: UUID?
    var groupID: UUID?
    var groupNameSnapshot: String?
    var evidenceSamples: [String]

    init(
        id: UUID = UUID(),
        term: String,
        normalizedTerm: String,
        sourceContext: DictionarySuggestionSourceContext,
        status: DictionarySuggestionStatus = .pending,
        firstSeenAt: Date = Date(),
        lastSeenAt: Date = Date(),
        seenCount: Int = 1,
        lastHistoryEntryID: UUID? = nil,
        groupID: UUID? = nil,
        groupNameSnapshot: String? = nil,
        evidenceSamples: [String] = []
    ) {
        self.id = id
        self.term = term
        self.normalizedTerm = normalizedTerm
        self.sourceContext = sourceContext
        self.status = status
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.seenCount = seenCount
        self.lastHistoryEntryID = lastHistoryEntryID
        self.groupID = groupID
        self.groupNameSnapshot = groupNameSnapshot
        self.evidenceSamples = evidenceSamples
    }
}

struct DictionarySuggestionDraft: Identifiable, Hashable {
    let term: String
    let normalizedTerm: String
    let sourceContext: DictionarySuggestionSourceContext
    let groupID: UUID?
    let groupNameSnapshot: String?
    let evidenceSample: String

    var id: String {
        "\(normalizedTerm)|\(groupID?.uuidString ?? "global")"
    }

    var snapshot: DictionarySuggestionSnapshot {
        DictionarySuggestionSnapshot(
            term: term,
            normalizedTerm: normalizedTerm,
            groupID: groupID,
            groupNameSnapshot: groupNameSnapshot
        )
    }
}

struct DictionaryHistoryScanCheckpoint: Codable, Equatable {
    let lastProcessedAt: Date
    let lastHistoryEntryID: UUID
}

struct DictionaryHistoryScanProgress: Equatable {
    var isRunning = false
    var isCancellationRequested = false
    var processedCount = 0
    var totalCount = 0
    var newSuggestionCount = 0
    var duplicateCount = 0
    var lastProcessedCount = 0
    var lastNewSuggestionCount = 0
    var lastDuplicateCount = 0
    var lastRunAt: Date?
    var errorMessage: String?
}

struct DictionaryHistoryScanCandidate: Hashable {
    let term: String
    let historyEntryIDs: [UUID]
    let groupID: UUID?
    let groupNameSnapshot: String?
    let evidenceSample: String
}

struct DictionaryHistoryScanApplyResult {
    let newSuggestionCount: Int
    let duplicateCount: Int
    let snapshotsByHistoryID: [UUID: [DictionarySuggestionSnapshot]]
}

struct DictionarySuggestionBulkAddResult: Equatable {
    let addedCount: Int
    let skippedCount: Int
}

struct DictionarySuggestionFilterSettings: Codable, Equatable, Hashable {
    var prompt: String
    var batchSize: Int
    var maxCandidatesPerBatch: Int

    static let defaultBatchSize = 12
    static let defaultMaxCandidatesPerBatch = 12
    static let minimumBatchSize = 1
    static let maximumBatchSize = 50
    static let minimumMaxCandidates = 1
    static let maximumMaxCandidates = 50

    static let defaultPrompt = """
    You are building a personal dictionary for a speech-to-text app. Be conservative. Only output high-confidence terms that are genuinely worth storing in a custom dictionary.

    ### Keep Only These Kinds of Terms
    1. Person names
    2. Place names, venue names, region names, or landmarks that are specific and uncommon
    3. Company, brand, product, app, project, team, or feature names
    4. Acronyms or abbreviations with clear domain meaning
    5. Distinctive industry terminology or stable user-specific spellings

    ### Hard Exclusions
    1. Common everyday words in the user's primary spoken language or any other frequently used language
    2. Generic nouns, verbs, adjectives, adverbs, fillers, or discourse words
    3. ASR mistakes, malformed fragments, partial words, repeated fragments, or words that are obviously mis-transcribed in context
    4. Long phrases, clauses, commands, sentence fragments, or anything that looks like a chunk of the transcript instead of a dictionary term
    5. Common words from a secondary language that appear inside mixed-language speech unless they are clearly a proper noun, acronym, or technical term
    6. Terms already listed in `dictionaryHitTerms` or `dictionaryCorrectedTerms`, unless the history clearly shows a new exact spelling that should replace the previous form
    7. Pure numbers, dates, times, IDs, email addresses, URLs, file paths, or punctuation-heavy strings
    8. High-frequency function words or general-purpose vocabulary in any declared user language, even if they appear repeatedly
    9. Generic travel, logistics, office, and UI vocabulary such as 航班, 车次, 地铁, 高铁, 酒店, 会议, 邮件, 文件, token, prompt, model, button, setting, unless the transcript clearly indicates a specific proper noun, product name, or stable domain phrase that is uncommon for general users
    10. Generic reference phrases such as 我们的规则, 这个问题, 那个功能, our rule, this issue, that feature

    ### Length Rules
    - Prefer single words or very short noun phrases
    - English or Latin-script terms should usually be 1 to 4 words, and must not exceed 6 words
    - English or Latin-script terms should not exceed 32 letters total unless they are a well-known acronym or product name
    - Chinese, Japanese, or Korean terms should usually be short and must not exceed 6 characters unless they are a clearly established proper noun

    ### Decision Rules
    - Prioritize terms that appear at least 2 times
    - Single-occurrence terms are allowed only when they are unmistakably a person name, place name, organization name, product name, acronym, or domain term
    - Analyze using the user's main language and the surrounding transcript context
    - Treat the primary spoken language and the other frequently used languages as ordinary daily vocabulary for this user
    - Repetition alone is not enough. A repeated common word must still be excluded
    - In mixed-language speech, do not extract a term just because it is from a secondary language; keep it only when it is clearly a proper noun, acronym, brand, product name, or technical term
    - If a word would be familiar to most ordinary speakers of that language, exclude it
    - If a candidate is a broad category label instead of a unique named entity or distinctive term, exclude it
    - Well-known cities, countries, and everyday location names should usually be excluded unless the transcript shows they are genuinely user-specific dictionary targets
    - If you are unsure whether a term is common, generic, or an ASR error, exclude it
    - Preserve the exact casing and spelling for accepted names and acronyms

    ### Three Filtering Principles
    1. Common vocabulary never belongs in the dictionary, even if it appears often
    2. Context-only items do not belong in the dictionary, such as route endpoints, transport numbers, UI labels, or one-off workflow words that are only needed for the current sentence
    3. Keep only stable correction targets: names, brands, acronyms, product names, technical terms, or durable user-specific terminology

    ### Cross-Language Guidance
    - Apply the same exclusion standard to every language listed for the user, including Chinese, English, Japanese, Korean, Thai, and any other declared language
    - Do not rely on a fixed Chinese-only or English-only stopword list; generalize the same "exclude high-frequency common vocabulary" rule to all declared languages
    - A secondary-language word inside mixed-language speech is usually not dictionary-worthy if it is still a common word in that language

    ### Quick Examples
    - Exclude: 航班, 车次, 地铁, 酒店, 会议, 邮件, 文件
    - Exclude: flight, train, station, schedule, email, file, token, prompt, model, button, setting, company
    - Exclude when they are only route endpoints or transport identifiers in a travel query: origin city, destination city, train number, flight number such as K130, MU5735, G1234
    - Keep: OpenAI, Claude, Bangkok Bank, TensorRT, Kubernetes, 清迈大学
    - Keep only when clearly specific and uncommon in context: product names, acronyms, person names, place names, brand names, technical terms, stable internal project names

    ### Output Rules
    - User's primary spoken language: {{USER_MAIN_LANGUAGE}}
    - Other frequently used languages: {{USER_OTHER_LANGUAGES}}
    - Input: {{HISTORY_RECORDS}}
    - Output must be a JSON array
    - Each array item must be an object with exactly one field: {"term": "accepted term"}
    - Return [] if there are no worthy terms
    - Do not return prose, markdown, code fences, explanations, or any extra fields

    Example:
    [
      { "term": "OpenAI" },
      { "term": "MCP" }
    ]
    """

    static let defaultValue = DictionarySuggestionFilterSettings(
        prompt: defaultPrompt,
        batchSize: defaultBatchSize,
        maxCandidatesPerBatch: defaultMaxCandidatesPerBatch
    )

    func sanitized() -> DictionarySuggestionFilterSettings {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return DictionarySuggestionFilterSettings(
            prompt: trimmedPrompt.isEmpty ? Self.defaultPrompt : trimmedPrompt,
            batchSize: min(max(batchSize, Self.minimumBatchSize), Self.maximumBatchSize),
            maxCandidatesPerBatch: min(
                max(maxCandidatesPerBatch, Self.minimumMaxCandidates),
                Self.maximumMaxCandidates
            )
        )
    }
}

enum DictionaryHistoryScanCandidateValidator {
    static func shouldAccept(term: String) -> Bool {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        return isStructurallyReasonable(trimmed) && !isClearlyGenericVocabulary(trimmed)
    }

    static func shouldAccept(term: String, evidenceSample: String) -> Bool {
        guard shouldAccept(term: term) else { return false }
        let sample = evidenceSample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sample.isEmpty else { return true }
        return !isContextSpecificArtifact(term: term, in: sample)
    }

    private static let sentencePunctuation: Set<Character> = [
        ".", ",", ":", ";", "!", "?", "，", "。", "：", "；", "！", "？", "、"
    ]

    private static let genericEnglishTerms: Set<String> = [
        "button",
        "company",
        "email",
        "file",
        "flight",
        "message",
        "model",
        "neither",
        "office",
        "prompt",
        "schedule",
        "setting",
        "station",
        "token",
        "train"
    ]

    private static let genericEnglishReferenceStarters: Set<String> = [
        "my", "our", "your", "their", "this", "that", "these", "those"
    ]

    private static let genericEnglishReferenceEndings: Set<String> = [
        "company",
        "content",
        "data",
        "feature",
        "file",
        "function",
        "issue",
        "message",
        "model",
        "problem",
        "prompt",
        "result",
        "rule",
        "setting",
        "term",
        "text"
    ]

    private static let genericCJKTerms: Set<String> = [
        "会议",
        "公司",
        "地铁",
        "文件",
        "机场",
        "航班",
        "订单",
        "提示词",
        "模型",
        "火车",
        "邮件",
        "设置",
        "车次",
        "酒店",
        "高铁"
    ]

    private static let genericChineseReferencePrefixes: [String] = [
        "这个",
        "那个",
        "这些",
        "那些",
        "这种",
        "那种",
        "我们",
        "你们",
        "他们",
        "她们",
        "它们",
        "我的",
        "你的",
        "他的",
        "她的",
        "它的",
        "我们的",
        "你们的",
        "他们的",
        "她们的",
        "它们的"
    ]

    private static let genericChineseReferenceSuffixes: [String] = [
        "规则",
        "问题",
        "功能",
        "内容",
        "结果",
        "消息",
        "词汇",
        "词语",
        "文本",
        "数据",
        "文件",
        "设置",
        "模型",
        "提示词",
        "方案",
        "接口",
        "公司",
        "事情",
        "情况"
    ]

    private static let travelKeywords: [String] = [
        "flight",
        "flights",
        "train",
        "trains",
        "station",
        "route",
        "航班",
        "车次",
        "列车",
        "火车",
        "高铁",
        "机票",
        "动车"
    ]

    private static func isStructurallyReasonable(_ term: String) -> Bool {
        guard !term.isEmpty else { return false }
        guard term.count <= 48 else { return false }
        guard !term.contains(where: \.isNewline) else { return false }
        guard !term.contains(where: { sentencePunctuation.contains($0) }) else { return false }
        guard term.range(of: #"^\d+$"#, options: .regularExpression) == nil else { return false }

        let latinWordCount = latinWords(in: term).count
        if containsLatinLetters(in: term) {
            guard latinWordCount <= 6 else { return false }
            guard latinLetterCount(in: term) <= 32 else { return false }
        }

        let cjkCount = cjkCharacterCount(in: term)
        if cjkCount > 0, !containsLatinLetters(in: term) {
            guard cjkCount <= 6 else { return false }
        }

        return true
    }

    private static func isClearlyGenericVocabulary(_ term: String) -> Bool {
        let lowercased = term.lowercased()
        if genericEnglishTerms.contains(lowercased) {
            return true
        }
        if genericCJKTerms.contains(term) {
            return true
        }
        if isGenericReferencePhrase(term, lowercased: lowercased) {
            return true
        }
        return false
    }

    private static func isGenericReferencePhrase(_ term: String, lowercased: String) -> Bool {
        if isGenericChineseReferencePhrase(term) {
            return true
        }
        if isGenericEnglishReferencePhrase(lowercased) {
            return true
        }
        return false
    }

    private static func isGenericChineseReferencePhrase(_ term: String) -> Bool {
        guard term.count >= 3, term.count <= 8 else { return false }
        guard let prefix = genericChineseReferencePrefixes.first(where: term.hasPrefix) else {
            return false
        }
        let remainder = String(term.dropFirst(prefix.count))
        guard !remainder.isEmpty else { return false }
        return genericChineseReferenceSuffixes.contains(where: remainder.hasSuffix)
    }

    private static func isGenericEnglishReferencePhrase(_ lowercased: String) -> Bool {
        let words = lowercased.split(whereSeparator: \.isWhitespace)
        guard words.count >= 2, words.count <= 4 else { return false }
        guard let first = words.first, genericEnglishReferenceStarters.contains(String(first)) else {
            return false
        }
        guard let last = words.last else { return false }
        return genericEnglishReferenceEndings.contains(String(last))
    }

    private static func isContextSpecificArtifact(term: String, in sample: String) -> Bool {
        looksLikeTravelRouteEndpoint(term: term, in: sample)
            || looksLikeTransportIdentifier(term: term, in: sample)
    }

    private static func looksLikeTravelRouteEndpoint(term: String, in sample: String) -> Bool {
        let normalizedSample = sample.lowercased()
        guard travelKeywords.contains(where: normalizedSample.contains) else { return false }

        if sample.contains("\(term)到") || sample.contains("到\(term)") {
            return true
        }

        if normalizedSample.contains("from \(term.lowercased())")
            || normalizedSample.contains("to \(term.lowercased())")
            || normalizedSample.contains("\(term.lowercased()) to ")
        {
            return true
        }

        return false
    }

    private static func looksLikeTransportIdentifier(term: String, in sample: String) -> Bool {
        let normalizedSample = sample.lowercased()
        guard travelKeywords.contains(where: normalizedSample.contains) else { return false }
        return term.range(of: #"^[A-Za-z]{1,3}\d{2,4}$"#, options: .regularExpression) != nil
    }

    private static func latinWords(in text: String) -> [Substring] {
        text.split(whereSeparator: \.isWhitespace).filter { token in
            token.contains(where: isLatinLetter)
        }
    }

    private static func containsLatinLetters(in text: String) -> Bool {
        text.contains(where: isLatinLetter)
    }

    private static func latinLetterCount(in text: String) -> Int {
        text.reduce(into: 0) { count, character in
            if isLatinLetter(character) {
                count += 1
            }
        }
    }

    private static func cjkCharacterCount(in text: String) -> Int {
        text.unicodeScalars.reduce(into: 0) { count, scalar in
            if isCJKScalar(scalar) {
                count += 1
            }
        }
    }

    private static func isLatinLetter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
        }
    }

    private static func isCJKScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF,
             0x4E00...0x9FFF,
             0x3040...0x309F,
             0x30A0...0x30FF,
             0x31F0...0x31FF,
             0xAC00...0xD7AF:
            return true
        default:
            return false
        }
    }
}

@MainActor
final class DictionarySuggestionStore: ObservableObject {
    @Published private(set) var suggestions: [DictionarySuggestion] = []
    @Published private(set) var historyScanProgress = DictionaryHistoryScanProgress()
    @Published private(set) var filterSettings = DictionarySuggestionFilterSettings.defaultValue

    private let defaults = UserDefaults.standard
    private let fileManager = FileManager.default
    private let evidenceLimit = 3

    init() {
        reload()
    }

    var pendingSuggestions: [DictionarySuggestion] {
        suggestions
            .filter { $0.status == .pending }
            .sorted {
                if $0.lastSeenAt == $1.lastSeenAt {
                    return $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending
                }
                return $0.lastSeenAt > $1.lastSeenAt
            }
    }

    func reload() {
        filterSettings = loadFilterSettings()
        do {
            let url = try suggestionsFileURL()
            guard fileManager.fileExists(atPath: url.path) else {
                suggestions = []
                return
            }
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([DictionarySuggestion].self, from: data)
            let deduplicated = deduplicatedSuggestions(decoded)
            suggestions = deduplicated
            if decoded != deduplicated {
                persist()
            }
        } catch {
            suggestions = []
        }
    }

    func saveFilterSettings(_ settings: DictionarySuggestionFilterSettings) {
        let sanitized = settings.sanitized()
        filterSettings = sanitized
        guard let data = try? JSONEncoder().encode(sanitized) else { return }
        defaults.set(data, forKey: AppPreferenceKey.dictionarySuggestionFilterSettings)
    }

    func resetFilterSettingsToDefault() {
        saveFilterSettings(.defaultValue)
    }

    func status(for snapshot: DictionarySuggestionSnapshot) -> DictionarySuggestionStatus? {
        suggestions.first {
            $0.normalizedTerm == snapshot.normalizedTerm && $0.groupID == snapshot.groupID
        }?.status
    }

    func dismiss(id: UUID) {
        guard let index = suggestions.firstIndex(where: { $0.id == id }) else { return }
        suggestions[index].status = .dismissed
        suggestions[index].lastSeenAt = Date()
        persist()
    }

    func clearAll() {
        suggestions = []
        persist()
    }

    var historyScanCheckpoint: DictionaryHistoryScanCheckpoint? {
        guard let data = defaults.data(forKey: AppPreferenceKey.dictionarySuggestionHistoryScanCheckpoint),
              let checkpoint = try? JSONDecoder().decode(DictionaryHistoryScanCheckpoint.self, from: data)
        else {
            return nil
        }
        return checkpoint
    }

    func pendingHistoryEntries(in historyStore: TranscriptionHistoryStore) -> [TranscriptionHistoryEntry] {
        let sorted = historyStore.allHistoryEntries.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.id.uuidString < $1.id.uuidString
            }
            return $0.createdAt < $1.createdAt
        }

        let pendingEntries: [TranscriptionHistoryEntry]
        if let checkpoint = historyScanCheckpoint {
            pendingEntries = sorted.filter {
                if $0.createdAt > checkpoint.lastProcessedAt {
                    return true
                }
                if $0.createdAt < checkpoint.lastProcessedAt {
                    return false
                }
                return $0.id.uuidString > checkpoint.lastHistoryEntryID.uuidString
            }
        } else {
            pendingEntries = sorted
        }

        return pendingEntries.filter { $0.kind == .normal }
    }

    func beginHistoryScan(totalCount: Int) {
        historyScanProgress = DictionaryHistoryScanProgress(
            isRunning: true,
            isCancellationRequested: false,
            processedCount: 0,
            totalCount: totalCount,
            newSuggestionCount: 0,
            duplicateCount: 0,
            lastProcessedCount: historyScanProgress.lastProcessedCount,
            lastNewSuggestionCount: historyScanProgress.lastNewSuggestionCount,
            lastDuplicateCount: historyScanProgress.lastDuplicateCount,
            lastRunAt: historyScanProgress.lastRunAt,
            errorMessage: nil
        )
    }

    func updateHistoryScan(processedCount: Int, newSuggestionCount: Int, duplicateCount: Int) {
        historyScanProgress.processedCount = processedCount
        historyScanProgress.newSuggestionCount = newSuggestionCount
        historyScanProgress.duplicateCount = duplicateCount
    }

    func requestHistoryScanCancellation() {
        guard historyScanProgress.isRunning else { return }
        historyScanProgress.isCancellationRequested = true
    }

    func finishHistoryScan(
        processedCount: Int,
        newSuggestionCount: Int,
        duplicateCount: Int,
        checkpointEntry: TranscriptionHistoryEntry?
    ) {
        if let checkpointEntry {
            persistHistoryScanCheckpoint(
                DictionaryHistoryScanCheckpoint(
                    lastProcessedAt: checkpointEntry.createdAt,
                    lastHistoryEntryID: checkpointEntry.id
                )
            )
        }

        historyScanProgress = DictionaryHistoryScanProgress(
            isRunning: false,
            isCancellationRequested: false,
            processedCount: processedCount,
            totalCount: processedCount,
            newSuggestionCount: newSuggestionCount,
            duplicateCount: duplicateCount,
            lastProcessedCount: processedCount,
            lastNewSuggestionCount: newSuggestionCount,
            lastDuplicateCount: duplicateCount,
            lastRunAt: Date(),
            errorMessage: nil
        )
    }

    func advanceHistoryScanCheckpoint(to entry: TranscriptionHistoryEntry) {
        persistHistoryScanCheckpoint(
            DictionaryHistoryScanCheckpoint(
                lastProcessedAt: entry.createdAt,
                lastHistoryEntryID: entry.id
            )
        )
    }

    func failHistoryScan(
        processedCount: Int,
        totalCount: Int,
        newSuggestionCount: Int,
        duplicateCount: Int,
        errorMessage: String
    ) {
        historyScanProgress = DictionaryHistoryScanProgress(
            isRunning: false,
            isCancellationRequested: false,
            processedCount: processedCount,
            totalCount: totalCount,
            newSuggestionCount: newSuggestionCount,
            duplicateCount: duplicateCount,
            lastProcessedCount: historyScanProgress.lastProcessedCount,
            lastNewSuggestionCount: historyScanProgress.lastNewSuggestionCount,
            lastDuplicateCount: historyScanProgress.lastDuplicateCount,
            lastRunAt: historyScanProgress.lastRunAt,
            errorMessage: errorMessage
        )
    }

    func cancelHistoryScan(
        processedCount: Int,
        totalCount: Int,
        newSuggestionCount: Int,
        duplicateCount: Int,
        message: String
    ) {
        historyScanProgress = DictionaryHistoryScanProgress(
            isRunning: false,
            isCancellationRequested: false,
            processedCount: processedCount,
            totalCount: totalCount,
            newSuggestionCount: newSuggestionCount,
            duplicateCount: duplicateCount,
            lastProcessedCount: processedCount,
            lastNewSuggestionCount: newSuggestionCount,
            lastDuplicateCount: duplicateCount,
            lastRunAt: Date(),
            errorMessage: message
        )
    }

    func dismiss(term: String, groupID: UUID?) {
        let normalized = DictionaryStore.normalizeTerm(term)
        guard !normalized.isEmpty else { return }
        if let index = suggestions.firstIndex(where: { $0.normalizedTerm == normalized && $0.groupID == groupID }) {
            suggestions[index].status = .dismissed
            suggestions[index].lastSeenAt = Date()
        } else {
            suggestions.append(
                DictionarySuggestion(
                    term: term,
                    normalizedTerm: normalized,
                    sourceContext: .history,
                    status: .dismissed,
                    groupID: groupID
                )
            )
        }
        persist()
    }

    func addToDictionary(id: UUID, dictionaryStore: DictionaryStore) {
        guard let suggestion = suggestions.first(where: { $0.id == id }) else { return }
        addToDictionary(
            term: suggestion.term,
            groupID: suggestion.groupID,
            groupNameSnapshot: suggestion.groupNameSnapshot,
            dictionaryStore: dictionaryStore
        )
    }

    func addToDictionary(
        term: String,
        groupID: UUID?,
        groupNameSnapshot: String?,
        dictionaryStore: DictionaryStore
    ) {
        let normalized = DictionaryStore.normalizeTerm(term)
        guard !normalized.isEmpty else { return }

        if !dictionaryStore.hasEntry(normalizedTerm: normalized, activeGroupID: groupID) {
            try? dictionaryStore.createAutoEntry(
                term: term,
                groupID: groupID,
                groupNameSnapshot: groupNameSnapshot
            )
        }

        if let index = suggestions.firstIndex(where: { $0.normalizedTerm == normalized && $0.groupID == groupID }) {
            suggestions[index].status = .added
            suggestions[index].lastSeenAt = Date()
        } else {
            suggestions.append(
                DictionarySuggestion(
                    term: term,
                    normalizedTerm: normalized,
                    sourceContext: .history,
                    status: .added,
                    groupID: groupID,
                    groupNameSnapshot: groupNameSnapshot
                )
            )
        }
        persist()
    }

    func addAllPendingToDictionary(dictionaryStore: DictionaryStore) -> DictionarySuggestionBulkAddResult {
        guard !pendingSuggestions.isEmpty else {
            return DictionarySuggestionBulkAddResult(addedCount: 0, skippedCount: 0)
        }

        let now = Date()
        var addedCount = 0
        var skippedCount = 0

        for suggestion in pendingSuggestions {
            if dictionaryStore.hasEntry(
                normalizedTerm: suggestion.normalizedTerm,
                activeGroupID: suggestion.groupID
            ) {
                if let index = suggestions.firstIndex(where: { $0.id == suggestion.id }) {
                    suggestions[index].status = .added
                    suggestions[index].lastSeenAt = now
                }
                skippedCount += 1
                continue
            }

            do {
                try dictionaryStore.createAutoEntry(
                    term: suggestion.term,
                    groupID: suggestion.groupID,
                    groupNameSnapshot: suggestion.groupNameSnapshot
                )
                if let index = suggestions.firstIndex(where: { $0.id == suggestion.id }) {
                    suggestions[index].status = .added
                    suggestions[index].lastSeenAt = now
                }
                addedCount += 1
            } catch {
                if dictionaryStore.hasEntry(
                    normalizedTerm: suggestion.normalizedTerm,
                    activeGroupID: suggestion.groupID
                ), let index = suggestions.firstIndex(where: { $0.id == suggestion.id }) {
                    suggestions[index].status = .added
                    suggestions[index].lastSeenAt = now
                }
                skippedCount += 1
            }
        }

        persist()
        return DictionarySuggestionBulkAddResult(addedCount: addedCount, skippedCount: skippedCount)
    }

    func discoverSuggestions(
        in finalText: String,
        activeGroupID: UUID?,
        activeGroupName: String?,
        dictionaryStore: DictionaryStore,
        matchedCandidates: [DictionaryMatchCandidate],
        correctedTerms: [String]
    ) -> [DictionarySuggestionDraft] {
        _ = finalText
        _ = activeGroupID
        _ = activeGroupName
        _ = dictionaryStore
        _ = matchedCandidates
        _ = correctedTerms
        return []
    }

    func applyDiscoveredSuggestions(_ drafts: [DictionarySuggestionDraft], historyEntryID: UUID?) {
        guard !drafts.isEmpty else { return }
        let now = Date()

        for draft in drafts {
            if let index = suggestions.firstIndex(where: {
                $0.normalizedTerm == draft.normalizedTerm && $0.groupID == draft.groupID
            }) {
                suggestions[index].term = draft.term
                suggestions[index].lastSeenAt = now
                suggestions[index].seenCount += 1
                suggestions[index].lastHistoryEntryID = historyEntryID
                suggestions[index].groupNameSnapshot = draft.groupNameSnapshot ?? suggestions[index].groupNameSnapshot
                if suggestions[index].status == .pending {
                    suggestions[index].sourceContext = draft.sourceContext
                }
                appendEvidenceSample(draft.evidenceSample, to: &suggestions[index])
            } else {
                suggestions.append(
                    DictionarySuggestion(
                        term: draft.term,
                        normalizedTerm: draft.normalizedTerm,
                        sourceContext: draft.sourceContext,
                        firstSeenAt: now,
                        lastSeenAt: now,
                        seenCount: 1,
                        lastHistoryEntryID: historyEntryID,
                        groupID: draft.groupID,
                        groupNameSnapshot: draft.groupNameSnapshot,
                        evidenceSamples: draft.evidenceSample.isEmpty ? [] : [draft.evidenceSample]
                    )
                )
            }
        }

        suggestions = deduplicatedSuggestions(suggestions)
        persist()
    }

    func applyHistoryScanCandidates(
        _ candidates: [DictionaryHistoryScanCandidate],
        dictionaryStore: DictionaryStore
    ) -> DictionaryHistoryScanApplyResult {
        guard !candidates.isEmpty else {
            return DictionaryHistoryScanApplyResult(
                newSuggestionCount: 0,
                duplicateCount: 0,
                snapshotsByHistoryID: [:]
            )
        }

        var newSuggestionCount = 0
        var duplicateCount = 0

        for candidate in candidates {
            let normalized = DictionaryStore.normalizeTerm(candidate.term)
            guard !normalized.isEmpty else { continue }
            guard !dictionaryStore.hasEntry(normalizedTerm: normalized, activeGroupID: candidate.groupID) else {
                duplicateCount += 1
                continue
            }

            do {
                try dictionaryStore.createAutoEntry(
                    term: candidate.term,
                    groupID: candidate.groupID,
                    groupNameSnapshot: candidate.groupNameSnapshot
                )
                newSuggestionCount += 1
            } catch {
                if dictionaryStore.hasEntry(normalizedTerm: normalized, activeGroupID: candidate.groupID) {
                    duplicateCount += 1
                }
            }
        }

        return DictionaryHistoryScanApplyResult(
            newSuggestionCount: newSuggestionCount,
            duplicateCount: duplicateCount,
            snapshotsByHistoryID: [:]
        )
    }

    private func appendEvidenceSample(_ sample: String, to suggestion: inout DictionarySuggestion) {
        let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        suggestion.evidenceSamples.removeAll { $0 == trimmed }
        suggestion.evidenceSamples.insert(trimmed, at: 0)
        if suggestion.evidenceSamples.count > evidenceLimit {
            suggestion.evidenceSamples = Array(suggestion.evidenceSamples.prefix(evidenceLimit))
        }
    }

    private func loadFilterSettings() -> DictionarySuggestionFilterSettings {
        guard
            let data = defaults.data(forKey: AppPreferenceKey.dictionarySuggestionFilterSettings),
            let decoded = try? JSONDecoder().decode(DictionarySuggestionFilterSettings.self, from: data)
        else {
            return .defaultValue
        }
        return decoded.sanitized()
    }

    private func deduplicatedSuggestions(_ items: [DictionarySuggestion]) -> [DictionarySuggestion] {
        var mergedByKey: [String: DictionarySuggestion] = [:]
        var keyOrder: [String] = []

        for item in items {
            let key = suggestionKey(normalizedTerm: item.normalizedTerm, groupID: item.groupID)
            if var existing = mergedByKey[key] {
                existing = mergeSuggestion(existing, with: item)
                mergedByKey[key] = existing
            } else {
                mergedByKey[key] = item
                keyOrder.append(key)
            }
        }

        return keyOrder
            .compactMap { mergedByKey[$0] }
            .sorted {
                if $0.lastSeenAt == $1.lastSeenAt {
                    return $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending
                }
                return $0.lastSeenAt > $1.lastSeenAt
            }
    }

    private func mergeSuggestion(_ lhs: DictionarySuggestion, with rhs: DictionarySuggestion) -> DictionarySuggestion {
        let newer = rhs.lastSeenAt >= lhs.lastSeenAt ? rhs : lhs
        let older = rhs.lastSeenAt >= lhs.lastSeenAt ? lhs : rhs

        var merged = older
        merged.term = newer.term
        merged.normalizedTerm = newer.normalizedTerm
        merged.sourceContext = newer.sourceContext
        merged.status = mergedStatus(lhs.status, rhs.status)
        merged.firstSeenAt = min(lhs.firstSeenAt, rhs.firstSeenAt)
        merged.lastSeenAt = max(lhs.lastSeenAt, rhs.lastSeenAt)
        merged.seenCount = max(lhs.seenCount, 0) + max(rhs.seenCount, 0)
        merged.lastHistoryEntryID = newer.lastHistoryEntryID ?? older.lastHistoryEntryID
        merged.groupID = newer.groupID ?? older.groupID
        merged.groupNameSnapshot = newer.groupNameSnapshot ?? older.groupNameSnapshot
        merged.evidenceSamples = mergedEvidenceSamples(primary: newer.evidenceSamples, secondary: older.evidenceSamples)
        return merged
    }

    private func mergedStatus(
        _ lhs: DictionarySuggestionStatus,
        _ rhs: DictionarySuggestionStatus
    ) -> DictionarySuggestionStatus {
        func rank(for status: DictionarySuggestionStatus) -> Int {
            switch status {
            case .pending:
                return 0
            case .dismissed:
                return 1
            case .added:
                return 2
            }
        }

        return rank(for: rhs) >= rank(for: lhs) ? rhs : lhs
    }

    private func mergedEvidenceSamples(primary: [String], secondary: [String]) -> [String] {
        var merged: [String] = []
        for sample in primary + secondary {
            let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !merged.contains(trimmed) else { continue }
            merged.append(trimmed)
            if merged.count >= evidenceLimit {
                break
            }
        }
        return merged
    }

    private func suggestionKey(normalizedTerm: String, groupID: UUID?) -> String {
        "\(normalizedTerm)|\(groupID?.uuidString ?? "global")"
    }

    private func persist() {
        do {
            let normalizedSuggestions = deduplicatedSuggestions(suggestions)
            suggestions = normalizedSuggestions
            let data = try JSONEncoder().encode(normalizedSuggestions)
            let url = try suggestionsFileURL()
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Keep UI responsive even if persistence fails.
        }
    }

    private func suggestionsFileURL() throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("Voxt", isDirectory: true)
            .appendingPathComponent("dictionary-suggestions.json")
    }

    private func persistHistoryScanCheckpoint(_ checkpoint: DictionaryHistoryScanCheckpoint) {
        guard let data = try? JSONEncoder().encode(checkpoint) else { return }
        defaults.set(data, forKey: AppPreferenceKey.dictionarySuggestionHistoryScanCheckpoint)
    }
}
