import Foundation

struct AutomaticDictionaryLearningRequest: Equatable {
    let insertedText: String
    let baselineContext: String
    let finalContext: String
    let baselineChangedFragment: String
    let finalChangedFragment: String
    let editRatio: Double
}

struct AutomaticDictionaryLearningObservationState: Equatable {
    let baselineText: String
    var latestText: String
    var didObserveChange: Bool
    var lastChangeElapsedSeconds: TimeInterval?
    var consecutiveMissingSnapshots: Int

    init(baselineText: String) {
        self.baselineText = baselineText
        self.latestText = baselineText
        self.didObserveChange = false
        self.lastChangeElapsedSeconds = nil
        self.consecutiveMissingSnapshots = 0
    }
}

enum AutomaticDictionaryLearningObservationDecision: Equatable {
    case continueObserving
    case stopWithoutAnalysis
    case settleForAnalysis(finalText: String)
}

enum AutomaticDictionaryLearningMonitor {
    private struct WhitespaceCollapsedProjection {
        let text: String
        let originalStarts: [Int]
        let originalEnds: [Int]
    }

    private struct PromptContext {
        let request: AutomaticDictionaryLearningRequest
        let existingTerms: [String]
        let userMainLanguage: String
        let userOtherLanguages: String
    }

    private struct ChangeWindow: Equatable {
        let baselineRange: NSRange
        let finalRange: NSRange
        let baselineFragment: String
        let finalFragment: String
        let editRatio: Double
        let hasMeaningfulChange: Bool
        let containsDeletionOnlyChangeGroup: Bool
    }

    private struct SemanticToken: Equatable {
        let text: String
        let normalizedText: String
        let start: Int
        let end: Int
    }

    private struct SemanticChangeGroup: Equatable {
        let baselineStartToken: Int?
        let baselineEndToken: Int?
        let finalStartToken: Int?
        let finalEndToken: Int?
    }

    private struct SemanticChangeSummary: Equatable {
        let baselineRange: NSRange
        let finalRange: NSRange
        let baselineFragment: String
        let finalFragment: String
        let baselineChangedCharacterCount: Int
        let finalChangedCharacterCount: Int
        let containsDeletionOnlyChangeGroup: Bool
    }

    private struct ScoredSemanticChangeSummary {
        let summary: SemanticChangeSummary
        let score: Int
    }

    enum RequestOutcome: Equatable {
        case ready(AutomaticDictionaryLearningRequest)
        case skipped(reason: String)
    }

    static let startupDelayNanoseconds: UInt64 = 900_000_000
    static let pollIntervalNanoseconds: UInt64 = 1_000_000_000
    static let initialSnapshotRetryCount = 3
    static let initialSnapshotRetryNanoseconds: UInt64 = 500_000_000
    static let observationWindowSeconds: TimeInterval = 30
    static let idleSettleSeconds: TimeInterval = 4
    static let maxConsecutiveMissingSnapshotsBeforeStop = 3
    static let maxConsecutiveMissingSnapshotsAfterObservedChange = 3
    static let maximumEditRatio = 0.8
    private static let templateReplacements: [(token: String, value: (PromptContext) -> String)] = [
        (
            AppPreferenceKey.automaticDictionaryLearningMainLanguageTemplateVariable,
            { $0.userMainLanguage }
        ),
        (
            AppPreferenceKey.automaticDictionaryLearningOtherLanguagesTemplateVariable,
            { $0.userOtherLanguages }
        ),
        (
            AppPreferenceKey.automaticDictionaryLearningInsertedTextTemplateVariable,
            { $0.request.insertedText }
        ),
        (
            AppPreferenceKey.automaticDictionaryLearningBaselineContextTemplateVariable,
            { $0.request.baselineContext }
        ),
        (
            AppPreferenceKey.automaticDictionaryLearningFinalContextTemplateVariable,
            { $0.request.finalContext }
        ),
        (
            AppPreferenceKey.automaticDictionaryLearningBaselineFragmentTemplateVariable,
            { $0.request.baselineChangedFragment }
        ),
        (
            AppPreferenceKey.automaticDictionaryLearningFinalFragmentTemplateVariable,
            { $0.request.finalChangedFragment }
        ),
        (
            AppPreferenceKey.automaticDictionaryLearningExistingTermsTemplateVariable,
            { context in
                if context.existingTerms.isEmpty {
                    return "(empty)"
                }
                return context.existingTerms
                    .prefix(20)
                    .map { "- \($0)" }
                    .joined(separator: "\n")
            }
        )
    ]

    static func makeLearningRequest(
        insertedText rawInsertedText: String,
        baselineText rawBaselineText: String,
        finalText rawFinalText: String
    ) -> RequestOutcome {
        let insertedText = rawInsertedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let baselineText = rawBaselineText.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalText = rawFinalText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !insertedText.isEmpty, !baselineText.isEmpty, !finalText.isEmpty else {
            return .skipped(reason: "empty inserted/baseline/final text")
        }

        if let insertedScopedOutcome = insertedScopedLearningRequest(
            insertedText: insertedText,
            baselineText: baselineText,
            finalText: finalText
        ) {
            return insertedScopedOutcome
        }

        let primaryOutcome = scopedLearningRequest(
            insertedText: insertedText,
            baselineText: baselineText,
            finalText: finalText
        )
        if case .ready = primaryOutcome {
            return primaryOutcome
        }

        if let fallbackOutcome = lineScopedLearningRequest(
            insertedText: insertedText,
            baselineText: baselineText,
            finalText: finalText
        ),
           case .ready = fallbackOutcome {
            return fallbackOutcome
        }

        return primaryOutcome
    }

    static func observationScopedText(
        insertedText rawInsertedText: String,
        baselineText rawBaselineText: String,
        currentText rawCurrentText: String
    ) -> String {
        let insertedText = rawInsertedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let baselineText = rawBaselineText.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentText = rawCurrentText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !insertedText.isEmpty, !baselineText.isEmpty else {
            return sanitizeScopedLineText(currentText)
        }

        guard let insertedRange = insertedRange(of: insertedText, in: baselineText) else {
            return sanitizeObservationScopedText(
                insertedText: insertedText,
                baselineScopedText: insertedText,
                currentText: currentText
            )
        }

        let baselineScopedText = scopedTextForInsertedRange(
            in: baselineText,
            insertedRange: insertedRange,
            fallback: insertedText
        )
        return sanitizeObservationScopedText(
            insertedText: insertedText,
            baselineScopedText: baselineScopedText,
            currentText: currentText
        )
    }

    private static func insertedScopedLearningRequest(
        insertedText: String,
        baselineText: String,
        finalText: String
    ) -> RequestOutcome? {
        guard baselineText != finalText else {
            return .skipped(reason: "baseline and final text are identical")
        }
        guard let baselineInsertedRange = insertedRange(of: insertedText, in: baselineText) else {
            return nil
        }

        let baselineScopedText = scopedTextForInsertedRange(
            in: baselineText,
            insertedRange: baselineInsertedRange,
            fallback: insertedText
        )
        let finalScopedText = extractFinalScopedText(
            insertedText: insertedText,
            baselineScopedText: baselineScopedText,
            finalText: finalText
        )

        guard !finalScopedText.isEmpty else {
            return nil
        }

        let changeWindow = changedRangeWindow(
            baselineText: baselineScopedText,
            finalText: finalScopedText
        )
        guard changeWindow.hasMeaningfulChange else {
            return .skipped(reason: "changed fragment has no meaningful terms")
        }
        guard let insertedScopedRange = insertedRange(of: insertedText, in: baselineScopedText) else {
            return .skipped(reason: "inserted text not found inside baseline snapshot")
        }
        guard changeIntersectsInsertedText(
            baselineChangeRange: changeWindow.baselineRange,
            insertedRange: insertedScopedRange
        ) else {
            return .skipped(reason: "detected edit does not intersect inserted text")
        }
        guard changeWindow.editRatio <= maximumEditRatio else {
            return .skipped(
                reason: "edit ratio \(String(format: "%.3f", changeWindow.editRatio)) exceeded limit \(String(format: "%.3f", maximumEditRatio))"
            )
        }

        return .ready(
            AutomaticDictionaryLearningRequest(
                insertedText: insertedText,
                baselineContext: baselineScopedText,
                finalContext: finalScopedText,
                baselineChangedFragment: changeWindow.baselineFragment,
                finalChangedFragment: changeWindow.finalFragment,
                editRatio: changeWindow.editRatio
            )
        )
    }

    private static func scopedLearningRequest(
        insertedText: String,
        baselineText: String,
        finalText: String
    ) -> RequestOutcome {
        guard baselineText != finalText else {
            return .skipped(reason: "baseline and final text are identical")
        }

        let changeWindow = changedRangeWindow(baselineText: baselineText, finalText: finalText)
        guard changeWindow.hasMeaningfulChange else {
            return .skipped(reason: "changed fragment has no meaningful terms")
        }
        guard let insertedRange = insertedRange(of: insertedText, in: baselineText) else {
            return .skipped(reason: "inserted text not found inside baseline snapshot")
        }
        guard changeIntersectsInsertedText(
            baselineChangeRange: changeWindow.baselineRange,
            insertedRange: insertedRange
        ) else {
            return .skipped(reason: "detected edit does not intersect inserted text")
        }
        guard changeWindow.editRatio <= maximumEditRatio else {
            return .skipped(
                reason: "edit ratio \(String(format: "%.3f", changeWindow.editRatio)) exceeded limit \(String(format: "%.3f", maximumEditRatio))"
            )
        }

        let baselineContextRange = union(
            lhs: insertedRange,
            rhs: changeWindow.baselineRange,
            upperBound: baselineText.count
        )
        let finalAnchorRange = NSRange(
            location: min(changeWindow.finalRange.location, max(finalText.count - 1, 0)),
            length: changeWindow.finalRange.length
        )
        let baselineContext = contextualSnippet(
            in: baselineText,
            focusRange: baselineContextRange,
            radius: 72
        )
        let finalContext = contextualSnippet(
            in: finalText,
            focusRange: finalAnchorRange,
            radius: 72
        )

        return .ready(
            AutomaticDictionaryLearningRequest(
                insertedText: insertedText,
                baselineContext: baselineContext,
                finalContext: finalContext,
                baselineChangedFragment: changeWindow.baselineFragment,
                finalChangedFragment: changeWindow.finalFragment,
                editRatio: changeWindow.editRatio
            )
        )
    }

    private static func lineScopedLearningRequest(
        insertedText: String,
        baselineText: String,
        finalText: String
    ) -> RequestOutcome? {
        guard let insertedRange = insertedRange(of: insertedText, in: baselineText) else {
            return nil
        }

        let baselineNSString = baselineText as NSString
        let baselineLineRange = baselineNSString.lineRange(for: insertedRange)
        let baselineLine = baselineNSString.substring(with: baselineLineRange)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baselineLine.isEmpty else {
            return nil
        }

        guard let finalLine = bestMatchingLine(
            primaryTarget: insertedText,
            secondaryTarget: baselineLine,
            within: finalText
        ) else {
            return nil
        }

        return scopedLearningRequest(
            insertedText: insertedText,
            baselineText: baselineLine,
            finalText: finalLine
        )
    }

    private static func scopedTextForInsertedRange(
        in text: String,
        insertedRange: NSRange,
        fallback: String
    ) -> String {
        let textNSString = text as NSString
        let lineRange = textNSString.lineRange(for: insertedRange)
        let lineText = sanitizeScopedLineText(
            textNSString.substring(with: lineRange)
        )
        return lineText.isEmpty ? fallback : lineText
    }

    private static func extractFinalScopedText(
        insertedText: String,
        baselineScopedText: String,
        finalText: String
    ) -> String {
        if !finalText.contains("\n") {
            return sanitizeScopedLineText(finalText)
        }

        if let bestLine = bestMatchingLine(
            primaryTarget: insertedText,
            secondaryTarget: baselineScopedText,
            within: finalText
        ) {
            return bestLine
        }

        return sanitizeScopedLineText(finalText)
    }

    private static func sanitizeObservationScopedText(
        insertedText: String,
        baselineScopedText: String,
        currentText: String
    ) -> String {
        if !currentText.contains("\n") {
            return sanitizeScopedLineText(currentText)
        }

        if let bestLine = bestMatchingLine(
            primaryTarget: insertedText,
            secondaryTarget: baselineScopedText,
            within: currentText
        ) {
            return bestLine
        }

        return ""
    }

    private static func normalizedDirectCandidateFragment(_ fragment: String) -> String {
        fragment
            .replacingOccurrences(of: #"^\s*>+\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?，。；：！？\"'()[]{}<>"))
    }

    private static func areEquivalentTerms(_ lhs: String, _ rhs: String) -> Bool {
        DictionaryStore.normalizeTerm(lhs) == DictionaryStore.normalizeTerm(rhs)
    }

    private static func isDirectCandidateTermLike(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count >= 2,
              trimmed.count <= 48,
              !trimmed.contains("\n"),
              !trimmed.contains("。"),
              !trimmed.contains("！"),
              !trimmed.contains("？"),
              !trimmed.contains("；") else {
            return false
        }

        let parts = trimmed.split(whereSeparator: \.isWhitespace)
        guard !parts.isEmpty, parts.count <= 4 else {
            return false
        }

        let hasASCIIWord = trimmed.contains { isASCIIWordCharacter($0) }
        let hasIdeographic = trimmed.contains { isIdeographicCharacter($0) }

        if hasASCIIWord {
            return true
        }
        if hasIdeographic, parts.count == 1, trimmed.count <= 8 {
            return true
        }
        return hasASCIIWord && hasIdeographic
    }

    static func buildPrompt(
        template rawTemplate: String,
        for request: AutomaticDictionaryLearningRequest,
        existingTerms: [String],
        userMainLanguage: String,
        userOtherLanguages: String
    ) -> String {
        let template = AppPromptDefaults.resolvedStoredText(
            rawTemplate,
            kind: .dictionaryAutoLearning
        )
        let context = PromptContext(
            request: request,
            existingTerms: existingTerms,
            userMainLanguage: userMainLanguage,
            userOtherLanguages: userOtherLanguages
        )
        let resolvedTemplate = templateReplacements.reduce(template) { partial, item in
            let value = item.value(context)
            return partial.replacingOccurrences(of: item.token, with: value)
        }
        return """
        \(resolvedTemplate)

        补充判断规则：
        5. 如果 <baseline_changed_fragment> 和 <final_changed_fragment> 都是短词或短语，且 final 明显是在纠正 baseline 的专有名词、产品名、工具名、技术术语、命令或混合语言词汇，直接返回 final 的最终正确写法。
        6. 类似 “Cloud Code -> Claude Code”、“Go Host -> Ghostty”、“Wechart -> WeChat”、“SG 骆魔鬼群 -> SGLang 魔鬼群” 这类错拼、音近词、错分词修正，优先返回最终完整词汇。
        7. 即使上下文是一整句，也不要返回整句；只返回最短、最稳定、最终纠正后的词汇。
        """
    }

    static func directCandidateTerms(
        for request: AutomaticDictionaryLearningRequest,
        existingTerms: [String]
    ) -> [String] {
        let baselineCandidate = normalizedDirectCandidateFragment(request.baselineChangedFragment)
        let finalCandidate = normalizedDirectCandidateFragment(request.finalChangedFragment)

        guard !baselineCandidate.isEmpty, !finalCandidate.isEmpty else {
            return []
        }
        guard !areEquivalentTerms(baselineCandidate, finalCandidate) else {
            return []
        }
        guard isDirectCandidateTermLike(baselineCandidate),
              isDirectCandidateTermLike(finalCandidate) else {
            return []
        }

        let normalizedExisting = Set(existingTerms.map(DictionaryStore.normalizeTerm))
        let normalizedFinal = DictionaryStore.normalizeTerm(finalCandidate)
        guard !normalizedFinal.isEmpty,
              !normalizedExisting.contains(normalizedFinal) else {
            return []
        }

        return [finalCandidate]
    }

    static func observeMissingSnapshot(
        state: inout AutomaticDictionaryLearningObservationState
    ) -> AutomaticDictionaryLearningObservationDecision {
        state.consecutiveMissingSnapshots += 1

        if !state.didObserveChange,
           state.consecutiveMissingSnapshots >= maxConsecutiveMissingSnapshotsBeforeStop {
            return .stopWithoutAnalysis
        }

        if state.didObserveChange,
           state.consecutiveMissingSnapshots >= maxConsecutiveMissingSnapshotsAfterObservedChange,
           let lastChangeElapsedSeconds = state.lastChangeElapsedSeconds,
           lastChangeElapsedSeconds >= idleSettleSeconds {
            if shouldContinueObservingForPotentialReplacement(
                baselineText: state.baselineText,
                currentFinalText: state.latestText
            ) {
                return .continueObserving
            }
            return .settleForAnalysis(finalText: state.latestText)
        }

        return .continueObserving
    }

    static func observeSnapshot(
        text: String,
        elapsedSinceLastChange: TimeInterval?,
        state: inout AutomaticDictionaryLearningObservationState
    ) -> AutomaticDictionaryLearningObservationDecision {
        state.consecutiveMissingSnapshots = 0

        guard text != state.latestText else {
            guard state.didObserveChange,
                  let elapsedSinceLastChange,
                  elapsedSinceLastChange >= idleSettleSeconds else {
                return .continueObserving
            }

            if shouldContinueObservingForPotentialReplacement(
                baselineText: state.baselineText,
                currentFinalText: state.latestText
            ) {
                return .continueObserving
            }
            return .settleForAnalysis(finalText: state.latestText)
        }

        state.latestText = text
        state.didObserveChange = true
        state.lastChangeElapsedSeconds = 0
        return .continueObserving
    }

    static func shouldFinalizeWhileFocused(
        decision: AutomaticDictionaryLearningObservationDecision
    ) -> Bool {
        switch decision {
        case .continueObserving, .settleForAnalysis:
            return false
        case .stopWithoutAnalysis:
            return true
        }
    }

    static func shouldContinueObservingForPotentialReplacement(
        baselineText: String,
        currentFinalText: String
    ) -> Bool {
        let changeWindow = changedRangeWindow(
            baselineText: baselineText,
            finalText: currentFinalText
        )
        let baselineMeaningful = DictionaryStore.normalizeTerm(changeWindow.baselineFragment)
        let finalMeaningful = DictionaryStore.normalizeTerm(changeWindow.finalFragment)
        if !baselineMeaningful.isEmpty && finalMeaningful.isEmpty {
            return true
        }
        return changeWindow.containsDeletionOnlyChangeGroup
    }

    private static func insertedRange(of insertedText: String, in baselineText: String) -> NSRange? {
        let searchRange = NSRange(location: 0, length: (baselineText as NSString).length)
        let match = NSRegularExpression.escapedPattern(for: insertedText)
        guard let regex = try? NSRegularExpression(pattern: match, options: [.caseInsensitive]) else {
            return relaxedInsertedRange(of: insertedText, in: baselineText)
        }
        if let exact = regex.firstMatch(in: baselineText, options: [], range: searchRange)?.range {
            return exact
        }
        return relaxedInsertedRange(of: insertedText, in: baselineText)
    }

    private static func relaxedInsertedRange(of insertedText: String, in baselineText: String) -> NSRange? {
        let baselineProjection = collapseWhitespace(in: baselineText)
        let insertedProjection = collapseWhitespace(in: insertedText)

        guard !baselineProjection.text.isEmpty, !insertedProjection.text.isEmpty else {
            return nil
        }
        guard let matchedRange = baselineProjection.text.range(
            of: insertedProjection.text,
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        let lowerBound = baselineProjection.text.distance(
            from: baselineProjection.text.startIndex,
            to: matchedRange.lowerBound
        )
        let upperBound = baselineProjection.text.distance(
            from: baselineProjection.text.startIndex,
            to: matchedRange.upperBound
        )
        guard lowerBound < baselineProjection.originalStarts.count,
              upperBound > 0,
              upperBound - 1 < baselineProjection.originalEnds.count else {
            return nil
        }

        let location = baselineProjection.originalStarts[lowerBound]
        let end = baselineProjection.originalEnds[upperBound - 1]
        return NSRange(location: location, length: max(0, end - location))
    }

    private static func collapseWhitespace(in text: String) -> WhitespaceCollapsedProjection {
        var characters: [Character] = []
        var originalStarts: [Int] = []
        var originalEnds: [Int] = []
        var utf16Location = 0

        for character in text {
            let scalarString = String(character)
            let utf16Length = (scalarString as NSString).length
            defer { utf16Location += utf16Length }

            if scalarString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }

            characters.append(character)
            originalStarts.append(utf16Location)
            originalEnds.append(utf16Location + utf16Length)
        }

        return WhitespaceCollapsedProjection(
            text: String(characters),
            originalStarts: originalStarts,
            originalEnds: originalEnds
        )
    }

    private static func changeIntersectsInsertedText(
        baselineChangeRange: NSRange,
        insertedRange: NSRange
    ) -> Bool {
        if baselineChangeRange.length == 0 {
            return baselineChangeRange.location > insertedRange.location
                && baselineChangeRange.location < insertedRange.location + insertedRange.length
        }
        return NSIntersectionRange(baselineChangeRange, insertedRange).length > 0
    }

    private static func changedRangeWindow(
        baselineText: String,
        finalText: String
    ) -> ChangeWindow {
        let summary = semanticChangeSummary(
            baselineText: baselineText,
            finalText: finalText
        )
        let baselineFragment = summary.baselineFragment
        let finalFragment = summary.finalFragment
        let baselineMeaningful = DictionaryStore.normalizeTerm(baselineFragment)
        let finalMeaningful = DictionaryStore.normalizeTerm(finalFragment)
        let hasMeaningfulChange = !baselineMeaningful.isEmpty || !finalMeaningful.isEmpty
        let baselineChars = Array(baselineText)
        let finalChars = Array(finalText)
        let editRatio = Double(max(summary.baselineChangedCharacterCount, summary.finalChangedCharacterCount))
            / Double(Swift.max(Swift.max(baselineChars.count, finalChars.count), 1))

        return ChangeWindow(
            baselineRange: summary.baselineRange,
            finalRange: summary.finalRange,
            baselineFragment: baselineFragment,
            finalFragment: finalFragment,
            editRatio: editRatio,
            hasMeaningfulChange: hasMeaningfulChange,
            containsDeletionOnlyChangeGroup: summary.containsDeletionOnlyChangeGroup
        )
    }

    private static func semanticChangeSummary(
        baselineText: String,
        finalText: String
    ) -> SemanticChangeSummary {
        let baselineTokens = semanticTokens(in: baselineText)
        let finalTokens = semanticTokens(in: finalText)

        guard !baselineTokens.isEmpty || !finalTokens.isEmpty else {
            return SemanticChangeSummary(
                baselineRange: NSRange(location: 0, length: 0),
                finalRange: NSRange(location: 0, length: 0),
                baselineFragment: "",
                finalFragment: "",
                baselineChangedCharacterCount: 0,
                finalChangedCharacterCount: 0,
                containsDeletionOnlyChangeGroup: false
            )
        }

        let matches = longestCommonSubsequenceMatches(
            baselineTokens: baselineTokens,
            finalTokens: finalTokens
        )
        let groups = semanticChangeGroups(
            baselineCount: baselineTokens.count,
            finalCount: finalTokens.count,
            matches: matches
        )
        let relevantGroups = groups.filter { $0.baselineStartToken != nil || $0.finalStartToken != nil }
        let deletionOnlyGroupExists = relevantGroups.contains {
            $0.baselineStartToken != nil && $0.finalStartToken == nil
        }
        let candidateGroups = semanticCandidateGroups(
            relevantGroups: relevantGroups,
            baselineText: baselineText,
            baselineTokens: baselineTokens,
            finalText: finalText,
            finalTokens: finalTokens
        )
        guard let selectedSummary = bestSemanticChangeSummary(
            candidateGroups: candidateGroups,
            relevantGroups: relevantGroups,
            baselineText: baselineText,
            baselineTokens: baselineTokens,
            finalText: finalText,
            finalTokens: finalTokens
        ) else {
            return SemanticChangeSummary(
                baselineRange: NSRange(location: 0, length: 0),
                finalRange: NSRange(location: 0, length: 0),
                baselineFragment: "",
                finalFragment: "",
                baselineChangedCharacterCount: 0,
                finalChangedCharacterCount: 0,
                containsDeletionOnlyChangeGroup: deletionOnlyGroupExists
            )
        }

        return SemanticChangeSummary(
            baselineRange: selectedSummary.baselineRange,
            finalRange: selectedSummary.finalRange,
            baselineFragment: selectedSummary.baselineFragment,
            finalFragment: selectedSummary.finalFragment,
            baselineChangedCharacterCount: selectedSummary.baselineChangedCharacterCount,
            finalChangedCharacterCount: selectedSummary.finalChangedCharacterCount,
            containsDeletionOnlyChangeGroup: deletionOnlyGroupExists
        )
    }

    private static func semanticCandidateGroups(
        relevantGroups: [SemanticChangeGroup],
        baselineText: String,
        baselineTokens: [SemanticToken],
        finalText: String,
        finalTokens: [SemanticToken]
    ) -> [SemanticChangeGroup] {
        guard !relevantGroups.isEmpty else {
            return []
        }

        var candidates: [SemanticChangeGroup] = []
        func appendUnique(_ group: SemanticChangeGroup) {
            guard !candidates.contains(group) else { return }
            candidates.append(group)
        }

        for group in relevantGroups {
            appendUnique(group)
        }

        let clusteredGroups = clusteredSemanticChangeGroups(
            relevantGroups: relevantGroups,
            baselineText: baselineText,
            baselineTokens: baselineTokens,
            finalText: finalText,
            finalTokens: finalTokens
        )
        for group in clusteredGroups {
            appendUnique(group)
        }

        if clusteredGroups.count <= 1,
           let mergedGroup = mergeSemanticChangeGroups(relevantGroups) {
            appendUnique(mergedGroup)
        }

        return candidates
    }

    private static func clusteredSemanticChangeGroups(
        relevantGroups: [SemanticChangeGroup],
        baselineText: String,
        baselineTokens: [SemanticToken],
        finalText: String,
        finalTokens: [SemanticToken]
    ) -> [SemanticChangeGroup] {
        guard var current = relevantGroups.first else {
            return []
        }

        var clusters: [SemanticChangeGroup] = []

        for next in relevantGroups.dropFirst() {
            if shouldMergeSemanticChangeGroups(
                current,
                next,
                baselineText: baselineText,
                baselineTokens: baselineTokens,
                finalText: finalText,
                finalTokens: finalTokens
            ),
               let merged = mergeSemanticChangeGroups([current, next]) {
                current = merged
            } else {
                clusters.append(current)
                current = next
            }
        }

        clusters.append(current)
        return clusters
    }

    private static func shouldMergeSemanticChangeGroups(
        _ lhs: SemanticChangeGroup,
        _ rhs: SemanticChangeGroup,
        baselineText: String,
        baselineTokens: [SemanticToken],
        finalText: String,
        finalTokens: [SemanticToken]
    ) -> Bool {
        let maximumTokenGap = 3

        if let baselineGap = tokenGapSize(lhs.baselineEndToken, rhs.baselineStartToken),
           baselineGap > maximumTokenGap {
            return false
        }
        if let finalGap = tokenGapSize(lhs.finalEndToken, rhs.finalStartToken),
           finalGap > maximumTokenGap {
            return false
        }

        if hasClauseBoundaryBetween(
            text: baselineText,
            tokens: baselineTokens,
            leftEndToken: lhs.baselineEndToken,
            rightStartToken: rhs.baselineStartToken
        ) {
            return false
        }
        if hasClauseBoundaryBetween(
            text: finalText,
            tokens: finalTokens,
            leftEndToken: lhs.finalEndToken,
            rightStartToken: rhs.finalStartToken
        ) {
            return false
        }

        return true
    }

    private static func mergeSemanticChangeGroups(
        _ groups: [SemanticChangeGroup]
    ) -> SemanticChangeGroup? {
        guard !groups.isEmpty else {
            return nil
        }
        return SemanticChangeGroup(
            baselineStartToken: groups.compactMap(\.baselineStartToken).min(),
            baselineEndToken: groups.compactMap(\.baselineEndToken).max(),
            finalStartToken: groups.compactMap(\.finalStartToken).min(),
            finalEndToken: groups.compactMap(\.finalEndToken).max()
        )
    }

    private static func tokenGapSize(_ leftEndToken: Int?, _ rightStartToken: Int?) -> Int? {
        guard let leftEndToken, let rightStartToken else {
            return nil
        }
        return max(0, rightStartToken - leftEndToken - 1)
    }

    private static func hasClauseBoundaryBetween(
        text: String,
        tokens: [SemanticToken],
        leftEndToken: Int?,
        rightStartToken: Int?
    ) -> Bool {
        guard let leftEndToken,
              let rightStartToken,
              leftEndToken >= 0,
              rightStartToken >= 0,
              leftEndToken < tokens.count,
              rightStartToken < tokens.count,
              leftEndToken < rightStartToken else {
            return false
        }

        let start = tokens[leftEndToken].end
        let end = tokens[rightStartToken].start
        let characters = Array(text)
        guard start < end, end <= characters.count else {
            return false
        }

        return characters[start..<end].contains { clauseBoundaryCharacters.contains($0) }
    }

    private static func bestSemanticChangeSummary(
        candidateGroups: [SemanticChangeGroup],
        relevantGroups: [SemanticChangeGroup],
        baselineText: String,
        baselineTokens: [SemanticToken],
        finalText: String,
        finalTokens: [SemanticToken]
    ) -> SemanticChangeSummary? {
        var best: ScoredSemanticChangeSummary?

        for group in candidateGroups {
            let prefersPhraseCompletion = !relevantGroups.contains(group)
            let summary = semanticChangeSummary(
                baselineText: baselineText,
                baselineTokens: baselineTokens,
                baselineStartToken: group.baselineStartToken,
                baselineEndToken: group.baselineEndToken,
                finalText: finalText,
                finalTokens: finalTokens,
                finalStartToken: group.finalStartToken,
                finalEndToken: group.finalEndToken,
                allowSharedTrailingIdeographicSuffixExpansion: prefersPhraseCompletion || relevantGroups.count == 1
            )

            let score = semanticChangeSummaryScore(summary) + semanticPhraseCompletionBonus(
                summary,
                prefersPhraseCompletion: prefersPhraseCompletion
            )
            guard score > Int.min else {
                continue
            }

            if let best, best.score >= score {
                continue
            }
            best = ScoredSemanticChangeSummary(summary: summary, score: score)
        }

        return best?.summary
    }

    private static func semanticChangeSummaryScore(_ summary: SemanticChangeSummary) -> Int {
        let baselineFragment = summary.baselineFragment
        let finalFragment = summary.finalFragment
        let baselineMeaningful = DictionaryStore.normalizeTerm(baselineFragment)
        let finalMeaningful = DictionaryStore.normalizeTerm(finalFragment)

        guard !baselineMeaningful.isEmpty || !finalMeaningful.isEmpty else {
            return Int.min
        }

        let maximumFragmentLength = max(baselineFragment.count, finalFragment.count)
        let punctuationPenalty = sentenceBoundaryPenalty(in: baselineFragment) + sentenceBoundaryPenalty(in: finalFragment)

        var score = 0
        if isDirectCandidateTermLike(finalFragment) {
            score += 120
        }
        if isDirectCandidateTermLike(baselineFragment) {
            score += 60
        }
        if containsMixedScript(finalFragment) {
            score += 60
        }
        if containsMixedScript(baselineFragment) {
            score += 25
        }
        if maximumFragmentLength <= 12 {
            score += 25
        }
        if summary.baselineChangedCharacterCount <= 12, summary.finalChangedCharacterCount <= 12 {
            score += 25
        }

        score -= maximumFragmentLength
        score -= max(summary.baselineChangedCharacterCount, summary.finalChangedCharacterCount)
        score -= punctuationPenalty

        return score
    }

    private static func semanticPhraseCompletionBonus(
        _ summary: SemanticChangeSummary,
        prefersPhraseCompletion: Bool
    ) -> Int {
        guard prefersPhraseCompletion else {
            return 0
        }

        let baselineFragment = summary.baselineFragment
        let finalFragment = summary.finalFragment
        var score = 0

        if containsMixedScript(finalFragment) || containsMixedScript(baselineFragment) {
            score += 45
        }
        if isDirectCandidateTermLike(finalFragment),
           finalFragment.count >= 4 {
            score += 20
        }

        return score
    }

    private static func sentenceBoundaryPenalty(in text: String) -> Int {
        text.reduce(into: 0) { partial, character in
            if clauseBoundaryCharacters.contains(character) {
                partial += 40
            }
            if character == "\n" {
                partial += 60
            }
        }
    }

    private static func containsMixedScript(_ text: String) -> Bool {
        let hasASCIIWord = text.contains { isASCIIWordCharacter($0) }
        let hasIdeographic = text.contains { isIdeographicCharacter($0) }
        return hasASCIIWord && hasIdeographic
    }

    private static func semanticChangeSummary(
        baselineText: String,
        baselineTokens: [SemanticToken],
        baselineStartToken: Int?,
        baselineEndToken: Int?,
        finalText: String,
        finalTokens: [SemanticToken],
        finalStartToken: Int?,
        finalEndToken: Int?,
        allowSharedTrailingIdeographicSuffixExpansion: Bool
    ) -> SemanticChangeSummary {
        let shouldExpandForwardPhrase =
            shouldExpandForwardPhrase(
                in: baselineText,
                tokens: baselineTokens,
                startToken: baselineStartToken,
                endToken: baselineEndToken
            ) || shouldExpandForwardPhrase(
                in: finalText,
                tokens: finalTokens,
                startToken: finalStartToken,
                endToken: finalEndToken
            )
        let adjustedBaselineEndToken = shouldExpandForwardPhrase
            ? forwardExpandableEndToken(
                in: baselineText,
                tokens: baselineTokens,
                endToken: baselineEndToken
            )
            : baselineEndToken
        let adjustedFinalEndToken = shouldExpandForwardPhrase
            ? forwardExpandableEndToken(
                in: finalText,
                tokens: finalTokens,
                endToken: finalEndToken
            )
            : finalEndToken
        let sharedContiguousSuffixLength = allowSharedTrailingIdeographicSuffixExpansion
            ? sharedContiguousSuffixLength(
                baselineText: baselineText,
                baselineTokens: baselineTokens,
                baselineEndToken: adjustedBaselineEndToken,
                finalText: finalText,
                finalTokens: finalTokens,
                finalEndToken: adjustedFinalEndToken
            )
            : 0
        let fullyAdjustedBaselineEndToken = adjustedBaselineEndToken.map {
            min($0 + sharedContiguousSuffixLength, baselineTokens.count - 1)
        }
        let fullyAdjustedFinalEndToken = adjustedFinalEndToken.map {
            min($0 + sharedContiguousSuffixLength, finalTokens.count - 1)
        }
        let trimmedBounds = shouldExpandForwardPhrase
            ? (
                baselineStartToken,
                fullyAdjustedBaselineEndToken,
                finalStartToken,
                fullyAdjustedFinalEndToken
            )
            : trimmingSharedAffixTokenBounds(
                baselineTokens: baselineTokens,
                baselineStartToken: baselineStartToken,
                baselineEndToken: fullyAdjustedBaselineEndToken,
                finalTokens: finalTokens,
                finalStartToken: finalStartToken,
                finalEndToken: fullyAdjustedFinalEndToken,
                preservedTrailingSharedTokenCount: sharedContiguousSuffixLength
            )

        let baselineRange = tokenCoverRange(
            tokens: baselineTokens,
            startToken: trimmedBounds.0,
            endToken: trimmedBounds.1
        )
        let finalRange = tokenCoverRange(
            tokens: finalTokens,
            startToken: trimmedBounds.2,
            endToken: trimmedBounds.3
        )
        let prefixExpandedRanges = expandingSharedIdeographicPrefixRanges(
            baselineText: baselineText,
            baselineRange: baselineRange,
            finalText: finalText,
            finalRange: finalRange
        )
        let expandedRanges = allowSharedTrailingIdeographicSuffixExpansion
            ? expandingSharedIdeographicSuffixRanges(
                baselineText: baselineText,
                baselineRange: prefixExpandedRanges.0,
                finalText: finalText,
                finalRange: prefixExpandedRanges.1
            )
            : prefixExpandedRanges
        return SemanticChangeSummary(
            baselineRange: expandedRanges.0,
            finalRange: expandedRanges.1,
            baselineFragment: fragment(in: baselineText, range: expandedRanges.0),
            finalFragment: fragment(in: finalText, range: expandedRanges.1),
            baselineChangedCharacterCount: expandedRanges.0.length,
            finalChangedCharacterCount: expandedRanges.1.length,
            containsDeletionOnlyChangeGroup: false
        )
    }

    private static func semanticTokens(in text: String) -> [SemanticToken] {
        let characters = Array(text)
        var index = 0
        var tokens: [SemanticToken] = []

        while index < characters.count {
            let character = characters[index]

            if character.isWhitespace || isPunctuationCharacter(character) {
                index += 1
                continue
            }

            let start = index

            if isASCIIWordCharacter(character) {
                index += 1
                while index < characters.count, isASCIIWordCharacter(characters[index]) {
                    index += 1
                }
            } else if isIdeographicCharacter(character) {
                index += 1
            } else {
                index += 1
                while index < characters.count,
                      !characters[index].isWhitespace,
                      !isPunctuationCharacter(characters[index]),
                      !isASCIIWordCharacter(characters[index]),
                      !isIdeographicCharacter(characters[index]) {
                    index += 1
                }
            }

            let tokenText = String(characters[start..<index])
            tokens.append(
                SemanticToken(
                    text: tokenText,
                    normalizedText: tokenText,
                    start: start,
                    end: index
                )
            )
        }

        return tokens
    }

    private static func longestCommonSubsequenceMatches(
        baselineTokens: [SemanticToken],
        finalTokens: [SemanticToken]
    ) -> [(Int, Int)] {
        let baselineCount = baselineTokens.count
        let finalCount = finalTokens.count
        var dp = Array(
            repeating: Array(repeating: 0, count: finalCount + 1),
            count: baselineCount + 1
        )

        if baselineCount > 0, finalCount > 0 {
            for baselineIndex in stride(from: baselineCount - 1, through: 0, by: -1) {
                for finalIndex in stride(from: finalCount - 1, through: 0, by: -1) {
                    if baselineTokens[baselineIndex].normalizedText == finalTokens[finalIndex].normalizedText {
                        dp[baselineIndex][finalIndex] = dp[baselineIndex + 1][finalIndex + 1] + 1
                    } else {
                        dp[baselineIndex][finalIndex] = max(
                            dp[baselineIndex + 1][finalIndex],
                            dp[baselineIndex][finalIndex + 1]
                        )
                    }
                }
            }
        }

        var matches: [(Int, Int)] = []
        var baselineIndex = 0
        var finalIndex = 0

        while baselineIndex < baselineCount, finalIndex < finalCount {
            if baselineTokens[baselineIndex].normalizedText == finalTokens[finalIndex].normalizedText {
                matches.append((baselineIndex, finalIndex))
                baselineIndex += 1
                finalIndex += 1
            } else if dp[baselineIndex + 1][finalIndex] >= dp[baselineIndex][finalIndex + 1] {
                baselineIndex += 1
            } else {
                finalIndex += 1
            }
        }

        return matches
    }

    private static func semanticChangeGroups(
        baselineCount: Int,
        finalCount: Int,
        matches: [(Int, Int)]
    ) -> [SemanticChangeGroup] {
        var groups: [SemanticChangeGroup] = []
        var previousBaselineIndex = -1
        var previousFinalIndex = -1
        let sentinelMatches = matches + [(baselineCount, finalCount)]

        for (nextBaselineIndex, nextFinalIndex) in sentinelMatches {
            let baselineStart = previousBaselineIndex + 1
            let baselineEnd = nextBaselineIndex - 1
            let finalStart = previousFinalIndex + 1
            let finalEnd = nextFinalIndex - 1

            if baselineStart <= baselineEnd || finalStart <= finalEnd {
                groups.append(
                    SemanticChangeGroup(
                        baselineStartToken: baselineStart <= baselineEnd ? baselineStart : nil,
                        baselineEndToken: baselineStart <= baselineEnd ? baselineEnd : nil,
                        finalStartToken: finalStart <= finalEnd ? finalStart : nil,
                        finalEndToken: finalStart <= finalEnd ? finalEnd : nil
                    )
                )
            }

            previousBaselineIndex = nextBaselineIndex
            previousFinalIndex = nextFinalIndex
        }

        return groups
    }

    private static func tokenCoverRange(
        tokens: [SemanticToken],
        startToken: Int?,
        endToken: Int?
    ) -> NSRange {
        guard let startToken, let endToken,
              startToken <= endToken,
              startToken >= 0,
              endToken < tokens.count else {
            return NSRange(location: 0, length: 0)
        }

        let start = tokens[startToken].start
        let end = tokens[endToken].end
        return NSRange(location: start, length: max(0, end - start))
    }

    private static func shouldExpandForwardPhrase(
        in text: String,
        tokens: [SemanticToken],
        startToken: Int?,
        endToken: Int?
    ) -> Bool {
        guard let startToken, let endToken,
              startToken == endToken,
              endToken + 1 < tokens.count,
              isASCIIWordToken(tokens[startToken]),
              isASCIIWordToken(tokens[endToken + 1]),
              onlyWhitespaceBetween(
                text,
                leftEnd: tokens[endToken].end,
                rightStart: tokens[endToken + 1].start
              ) else {
            return false
        }

        let current = tokens[startToken].text
        let next = tokens[endToken + 1].text
        if next.lowercased() == current.lowercased() {
            return true
        }
        if next.count >= 2, next == next.uppercased() {
            return true
        }
        guard let first = next.first else {
            return false
        }
        return first.isUppercase
    }

    private static func forwardExpandableEndToken(
        in text: String,
        tokens: [SemanticToken],
        endToken: Int?
    ) -> Int? {
        guard let endToken else {
            return endToken
        }
        guard endToken + 1 < tokens.count,
              isASCIIWordToken(tokens[endToken + 1]),
              onlyWhitespaceBetween(
                text,
                leftEnd: tokens[endToken].end,
                rightStart: tokens[endToken + 1].start
              ) else {
            return endToken
        }
        return min(endToken + 1, tokens.count - 1)
    }

    private static func sharedContiguousSuffixLength(
        baselineText: String,
        baselineTokens: [SemanticToken],
        baselineEndToken: Int?,
        finalText: String,
        finalTokens: [SemanticToken],
        finalEndToken: Int?
    ) -> Int {
        guard let baselineEndToken, let finalEndToken else {
            return 0
        }

        var baselineIndex = baselineEndToken + 1
        var finalIndex = finalEndToken + 1
        var sharedCount = 0

        while baselineIndex < baselineTokens.count,
              finalIndex < finalTokens.count,
              baselineTokens[baselineIndex].text == finalTokens[finalIndex].text,
              isIdeographicToken(baselineTokens[baselineIndex]),
              isIdeographicToken(finalTokens[finalIndex]),
              isContiguousWithoutWhitespace(
                baselineText,
                previousEnd: baselineTokens[baselineIndex - 1].end,
                nextStart: baselineTokens[baselineIndex].start
              ),
              isContiguousWithoutWhitespace(
                finalText,
                previousEnd: finalTokens[finalIndex - 1].end,
                nextStart: finalTokens[finalIndex].start
              ) {
            sharedCount += 1
            baselineIndex += 1
            finalIndex += 1
        }

        return sharedCount
    }

    private static func trimmingSharedAffixTokenBounds(
        baselineTokens: [SemanticToken],
        baselineStartToken: Int?,
        baselineEndToken: Int?,
        finalTokens: [SemanticToken],
        finalStartToken: Int?,
        finalEndToken: Int?,
        preservedTrailingSharedTokenCount: Int
    ) -> (Int?, Int?, Int?, Int?) {
        guard let baselineStartToken, let baselineEndToken,
              let finalStartToken, let finalEndToken else {
            return (baselineStartToken, baselineEndToken, finalStartToken, finalEndToken)
        }

        let baselineSlice = Array(baselineTokens[baselineStartToken...baselineEndToken])
        let finalSlice = Array(finalTokens[finalStartToken...finalEndToken])
        guard !baselineSlice.isEmpty, !finalSlice.isEmpty else {
            return (baselineStartToken, baselineEndToken, finalStartToken, finalEndToken)
        }

        var sharedPrefix = 0
        while sharedPrefix < baselineSlice.count,
              sharedPrefix < finalSlice.count,
              baselineSlice[sharedPrefix].text == finalSlice[sharedPrefix].text {
            sharedPrefix += 1
        }

        var sharedSuffix = 0
        let suffixTrimLimit = max(0, min(baselineSlice.count, finalSlice.count) - preservedTrailingSharedTokenCount)
        while sharedSuffix < baselineSlice.count - sharedPrefix,
              sharedSuffix < finalSlice.count - sharedPrefix,
              sharedSuffix < suffixTrimLimit,
              baselineSlice[baselineSlice.count - 1 - sharedSuffix].text
                == finalSlice[finalSlice.count - 1 - sharedSuffix].text {
            sharedSuffix += 1
        }

        let trimmedBaselineStart = min(baselineStartToken + sharedPrefix, baselineEndToken)
        let trimmedFinalStart = min(finalStartToken + sharedPrefix, finalEndToken)
        let trimmedBaselineEnd = max(trimmedBaselineStart, baselineEndToken - sharedSuffix)
        let trimmedFinalEnd = max(trimmedFinalStart, finalEndToken - sharedSuffix)

        return (trimmedBaselineStart, trimmedBaselineEnd, trimmedFinalStart, trimmedFinalEnd)
    }

    private static func expandingSharedIdeographicSuffixRanges(
        baselineText: String,
        baselineRange: NSRange,
        finalText: String,
        finalRange: NSRange
    ) -> (NSRange, NSRange) {
        let baselineChars = Array(baselineText)
        let finalChars = Array(finalText)
        guard baselineRange.length > 0, finalRange.length > 0 else {
            return (baselineRange, finalRange)
        }
        guard baselineRange.location + baselineRange.length <= baselineChars.count,
              finalRange.location + finalRange.length <= finalChars.count else {
            return (baselineRange, finalRange)
        }

        var baselineEnd = baselineRange.location + baselineRange.length
        var finalEnd = finalRange.location + finalRange.length

        while baselineEnd < baselineChars.count,
              finalEnd < finalChars.count {
            let baselineNext = baselineChars[baselineEnd]
            let finalNext = finalChars[finalEnd]
            guard baselineNext == finalNext,
                  isIdeographicCharacter(baselineNext),
                  !commonIdeographicSuffixStopCharacters.contains(baselineNext),
                  isContiguousWithoutWhitespace(
                    baselineText,
                    previousEnd: baselineEnd - 1,
                    nextStart: baselineEnd
                  ),
                  isContiguousWithoutWhitespace(
                    finalText,
                    previousEnd: finalEnd - 1,
                    nextStart: finalEnd
                  ) else {
                break
            }

            baselineEnd += 1
            finalEnd += 1
        }

        return (
            NSRange(location: baselineRange.location, length: baselineEnd - baselineRange.location),
            NSRange(location: finalRange.location, length: finalEnd - finalRange.location)
        )
    }

    private static func expandingSharedIdeographicPrefixRanges(
        baselineText: String,
        baselineRange: NSRange,
        finalText: String,
        finalRange: NSRange
    ) -> (NSRange, NSRange) {
        let baselineChars = Array(baselineText)
        let finalChars = Array(finalText)
        guard baselineRange.length > 0, finalRange.length > 0 else {
            return (baselineRange, finalRange)
        }
        guard baselineRange.location + baselineRange.length <= baselineChars.count,
              finalRange.location + finalRange.length <= finalChars.count else {
            return (baselineRange, finalRange)
        }

        var baselineStart = baselineRange.location
        var finalStart = finalRange.location

        while baselineStart > 0,
              finalStart > 0 {
            let baselinePrevious = baselineChars[baselineStart - 1]
            let finalPrevious = finalChars[finalStart - 1]
            guard baselinePrevious == finalPrevious,
                  isIdeographicCharacter(baselinePrevious),
                  !commonIdeographicSuffixStopCharacters.contains(baselinePrevious),
                  isContiguousWithoutWhitespace(
                    baselineText,
                    previousEnd: baselineStart - 1,
                    nextStart: baselineStart
                  ),
                  isContiguousWithoutWhitespace(
                    finalText,
                    previousEnd: finalStart - 1,
                    nextStart: finalStart
                  ) else {
                break
            }

            baselineStart -= 1
            finalStart -= 1
        }

        return (
            NSRange(
                location: baselineStart,
                length: baselineRange.location + baselineRange.length - baselineStart
            ),
            NSRange(
                location: finalStart,
                length: finalRange.location + finalRange.length - finalStart
            )
        )
    }

    private static func isASCIIWordToken(_ token: SemanticToken) -> Bool {
        token.text.allSatisfy { isASCIIWordCharacter($0) }
    }

    private static func isIdeographicToken(_ token: SemanticToken) -> Bool {
        token.text.allSatisfy { isIdeographicCharacter($0) }
    }

    private static func onlyWhitespaceBetween(
        _ text: String,
        leftEnd: Int,
        rightStart: Int
    ) -> Bool {
        let characters = Array(text)
        guard leftEnd <= rightStart, rightStart <= characters.count else {
            return false
        }
        guard leftEnd < rightStart else {
            return true
        }
        return characters[leftEnd..<rightStart].allSatisfy(\.isWhitespace)
    }

    private static func isContiguousWithoutWhitespace(
        _ text: String,
        previousEnd: Int,
        nextStart: Int
    ) -> Bool {
        let characters = Array(text)
        guard previousEnd <= nextStart, nextStart <= characters.count else {
            return false
        }
        guard previousEnd < nextStart else {
            return true
        }
        return characters[previousEnd..<nextStart].allSatisfy { !$0.isWhitespace && !isPunctuationCharacter($0) }
    }

    private static func isASCIIWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && CharacterSet.alphanumerics.contains(scalar)
                || CharacterSet(charactersIn: "_-").contains(scalar)
        }
    }

    private static func isIdeographicCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { $0.properties.isIdeographic }
    }

    private static func isPunctuationCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy {
            CharacterSet.punctuationCharacters.contains($0)
                || CharacterSet.symbols.contains($0)
        }
    }

    private static let commonIdeographicSuffixStopCharacters: Set<Character> = ["的", "了", "呢", "吗", "啊", "呀", "吧"]
    private static let clauseBoundaryCharacters: Set<Character> = ["。", "！", "？", "；", ".", "!", "?", ";", "\n"]

    private static func fragment(in text: String, range: NSRange) -> String {
        guard let swiftRange = Range(range, in: text) else { return "" }
        return String(text[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func union(lhs: NSRange, rhs: NSRange, upperBound: Int) -> NSRange {
        let start = min(lhs.location, rhs.location)
        let end = min(
            max(lhs.location + lhs.length, rhs.location + rhs.length),
            upperBound
        )
        return NSRange(location: start, length: max(end - start, 0))
    }

    private static func contextualSnippet(
        in text: String,
        focusRange: NSRange,
        radius: Int
    ) -> String {
        let characters = Array(text)
        guard !characters.isEmpty else { return "" }

        let start = max(0, focusRange.location - radius)
        let end = min(characters.count, focusRange.location + max(focusRange.length, 1) + radius)
        guard start < end else { return text }

        var snippet = String(characters[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        if start > 0 {
            snippet = "…" + snippet
        }
        if end < characters.count {
            snippet += "…"
        }
        return snippet
    }

    private static func bestMatchingLine(
        primaryTarget: String,
        secondaryTarget: String?,
        within finalText: String
    ) -> String? {
        let finalNSString = finalText as NSString
        let searchRange = NSRange(location: 0, length: finalNSString.length)
        var bestLine: String?
        var bestScore = Int.min

        finalText.enumerateSubstrings(in: Range(searchRange, in: finalText)!, options: [.byLines, .substringNotRequired]) {
            _, substringRange, _, _ in
            let rawLine = String(finalText[substringRange])
            let line = sanitizeScopedLineText(rawLine)
            guard !line.isEmpty else { return }

            let score = bestLineScore(
                line: line,
                primaryTarget: primaryTarget,
                secondaryTarget: secondaryTarget
            )
            if score > bestScore {
                bestScore = score
                bestLine = line
            }
        }

        let minimumUsefulScore = minimumUsefulLineScore(
            primaryTarget: primaryTarget,
            secondaryTarget: secondaryTarget
        )
        guard bestScore >= minimumUsefulScore else {
            return nil
        }
        return bestLine
    }

    private static func bestLineScore(
        line: String,
        primaryTarget: String,
        secondaryTarget: String?
    ) -> Int {
        let primaryScore = lineSimilarityScore(primaryTarget, line)
        let secondaryScore = secondaryTarget.map { lineSimilarityScore($0, line) } ?? Int.min
        let score = max(primaryScore, secondaryScore)
        if isObservationNoiseLine(line) {
            return score - max(6, line.count / 4)
        }
        return score
    }

    private static func minimumUsefulLineScore(
        primaryTarget: String,
        secondaryTarget: String?
    ) -> Int {
        let primaryCount = normalizedLineMatchingText(primaryTarget).count
        let secondaryCount = secondaryTarget.map { normalizedLineMatchingText($0).count } ?? 0
        return max(6, max(primaryCount, secondaryCount) / 4)
    }

    private static func lineSimilarityScore(_ lhs: String, _ rhs: String) -> Int {
        let lhsChars = Array(normalizedLineMatchingText(lhs))
        let rhsChars = Array(normalizedLineMatchingText(rhs))
        guard !lhsChars.isEmpty, !rhsChars.isEmpty else {
            return 0
        }

        var prefix = 0
        while prefix < lhsChars.count,
              prefix < rhsChars.count,
              lhsChars[prefix] == rhsChars[prefix] {
            prefix += 1
        }

        var suffix = 0
        while suffix < lhsChars.count - prefix,
              suffix < rhsChars.count - prefix,
              lhsChars[lhsChars.count - 1 - suffix] == rhsChars[rhsChars.count - 1 - suffix] {
            suffix += 1
        }

        let commonSubstring = longestCommonSubstringLength(lhsChars, rhsChars)
        let lhsText = String(lhsChars)
        let rhsText = String(rhsChars)
        let containmentBonus: Int
        if lhsText.contains(rhsText) || rhsText.contains(lhsText) {
            containmentBonus = min(lhsChars.count, rhsChars.count)
        } else {
            containmentBonus = 0
        }

        return prefix + suffix + (commonSubstring * 2) + containmentBonus
    }

    private static func longestCommonSubstringLength(
        _ lhsChars: [Character],
        _ rhsChars: [Character]
    ) -> Int {
        guard !lhsChars.isEmpty, !rhsChars.isEmpty else {
            return 0
        }

        var previous = Array(repeating: 0, count: rhsChars.count + 1)
        var longest = 0

        for lhsIndex in 1...lhsChars.count {
            var current = Array(repeating: 0, count: rhsChars.count + 1)
            for rhsIndex in 1...rhsChars.count {
                if lhsChars[lhsIndex - 1] == rhsChars[rhsIndex - 1] {
                    current[rhsIndex] = previous[rhsIndex - 1] + 1
                    longest = max(longest, current[rhsIndex])
                }
            }
            previous = current
        }

        return longest
    }

    private static func normalizedLineMatchingText(_ text: String) -> String {
        sanitizeScopedLineText(text)
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isObservationNoiseLine(_ text: String) -> Bool {
        let line = sanitizeScopedLineText(text)
        guard !line.isEmpty else { return true }

        if line.hasPrefix("zsh:") || line.hasPrefix("bash:") || line.hasPrefix("fish:") {
            return true
        }

        if line.contains("command not found:") || line.contains("no such file or directory") {
            return true
        }

        if line.hasPrefix("~/") || line.hasPrefix("/") {
            return true
        }

        return false
    }

    private static func sanitizeScopedLineText(_ text: String) -> String {
        var line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("> ") {
            line.removeFirst(2)
        } else if line == ">" {
            line = ""
        }
        return line.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
