import Foundation

struct AutomaticDictionaryLearningRequest: Equatable {
    let insertedText: String
    let baselineContext: String
    let finalContext: String
    let baselineChangedFragment: String
    let finalChangedFragment: String
    let editRatio: Double
}

enum AutomaticDictionaryLearningMonitor {
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
    static let maximumEditRatio = 0.8
    private static let templateReplacements: [(token: String, value: (AutomaticDictionaryLearningRequest, [String], String, String) -> String)] = [
        (
            AppPreferenceKey.automaticDictionaryLearningMainLanguageTemplateVariable,
            { _, _, userMainLanguage, _ in userMainLanguage }
        ),
        (
            AppPreferenceKey.automaticDictionaryLearningOtherLanguagesTemplateVariable,
            { _, _, _, userOtherLanguages in userOtherLanguages }
        ),
        (
            AppPreferenceKey.automaticDictionaryLearningInsertedTextTemplateVariable,
            { request, _, _, _ in request.insertedText }
        ),
        (
            AppPreferenceKey.automaticDictionaryLearningBaselineContextTemplateVariable,
            { request, _, _, _ in request.baselineContext }
        ),
        (
            AppPreferenceKey.automaticDictionaryLearningFinalContextTemplateVariable,
            { request, _, _, _ in request.finalContext }
        ),
        (
            AppPreferenceKey.automaticDictionaryLearningBaselineFragmentTemplateVariable,
            { request, _, _, _ in request.baselineChangedFragment }
        ),
        (
            AppPreferenceKey.automaticDictionaryLearningFinalFragmentTemplateVariable,
            { request, _, _, _ in request.finalChangedFragment }
        ),
        (
            AppPreferenceKey.automaticDictionaryLearningExistingTermsTemplateVariable,
            { _, existingTerms, _, _ in
                if existingTerms.isEmpty {
                    return "(empty)"
                }
                return existingTerms
                    .prefix(80)
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
        guard baselineText != finalText else {
            return .skipped(reason: "baseline and final text are identical")
        }

        let changeWindow = changedRangeWindow(baselineText: baselineText, finalText: finalText)
        guard changeWindow.hasMeaningfulChange else {
            return .skipped(reason: "changed fragment has no meaningful terms")
        }
        guard changeWindow.editRatio <= maximumEditRatio else {
            return .skipped(
                reason: "edit ratio \(String(format: "%.3f", changeWindow.editRatio)) exceeded limit \(String(format: "%.3f", maximumEditRatio))"
            )
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
        return templateReplacements.reduce(template) { partial, item in
            let value = item.value(request, existingTerms, userMainLanguage, userOtherLanguages)
            return partial.replacingOccurrences(of: item.token, with: value)
        }
    }

    private static func insertedRange(of insertedText: String, in baselineText: String) -> NSRange? {
        let searchRange = NSRange(location: 0, length: (baselineText as NSString).length)
        let match = NSRegularExpression.escapedPattern(for: insertedText)
        guard let regex = try? NSRegularExpression(pattern: match, options: [.caseInsensitive]) else {
            return nil
        }
        return regex.firstMatch(in: baselineText, options: [], range: searchRange)?.range
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
    ) -> (
        baselineRange: NSRange,
        finalRange: NSRange,
        baselineFragment: String,
        finalFragment: String,
        editRatio: Double,
        hasMeaningfulChange: Bool
    ) {
        let baselineChars = Array(baselineText)
        let finalChars = Array(finalText)

        var prefixLength = 0
        while prefixLength < baselineChars.count,
              prefixLength < finalChars.count,
              baselineChars[prefixLength] == finalChars[prefixLength] {
            prefixLength += 1
        }

        var baselineSuffixLength = 0
        while baselineSuffixLength < baselineChars.count - prefixLength,
              baselineSuffixLength < finalChars.count - prefixLength,
              baselineChars[baselineChars.count - 1 - baselineSuffixLength]
                == finalChars[finalChars.count - 1 - baselineSuffixLength] {
            baselineSuffixLength += 1
        }

        let baselineChangeCount = max(0, baselineChars.count - prefixLength - baselineSuffixLength)
        let finalChangeCount = max(0, finalChars.count - prefixLength - baselineSuffixLength)

        let baselineRange = NSRange(location: prefixLength, length: baselineChangeCount)
        let finalRange = NSRange(location: prefixLength, length: finalChangeCount)
        let baselineFragment = fragment(in: baselineText, range: baselineRange)
        let finalFragment = fragment(in: finalText, range: finalRange)
        let baselineMeaningful = DictionaryStore.normalizeTerm(baselineFragment)
        let finalMeaningful = DictionaryStore.normalizeTerm(finalFragment)
        let hasMeaningfulChange = !baselineMeaningful.isEmpty || !finalMeaningful.isEmpty
        let editRatio = Double(max(baselineChangeCount, finalChangeCount))
            / Double(Swift.max(Swift.max(baselineChars.count, finalChars.count), 1))

        return (
            baselineRange: baselineRange,
            finalRange: finalRange,
            baselineFragment: baselineFragment,
            finalFragment: finalFragment,
            editRatio: editRatio,
            hasMeaningfulChange: hasMeaningfulChange
        )
    }

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
}
