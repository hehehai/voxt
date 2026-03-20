import Foundation
@testable import Voxt

enum TestFactories {
    static func makeEntry(
        term: String,
        replacementTerms: [String] = [],
        observedVariants: [String] = [],
        groupID: UUID? = nil,
        status: DictionaryEntryStatus = .active
    ) -> DictionaryEntry {
        DictionaryEntry(
            term: term,
            normalizedTerm: normalizedDictionaryTerm(term),
            groupID: groupID,
            source: .manual,
            status: status,
            observedVariants: observedVariants.map {
                ObservedVariant(
                    text: $0,
                    normalizedText: normalizedDictionaryTerm($0),
                    confidence: .medium
                )
            },
            replacementTerms: replacementTerms.map {
                DictionaryReplacementTerm(
                    text: $0,
                    normalizedText: normalizedDictionaryTerm($0)
                )
            }
        )
    }

    static func makeRemoteConfiguration(
        providerID: String,
        model: String,
        endpoint: String = "",
        apiKey: String = "",
        appID: String = "",
        accessToken: String = "",
        openAIChunkPseudoRealtimeEnabled: Bool = false
    ) -> RemoteProviderConfiguration {
        RemoteProviderConfiguration(
            providerID: providerID,
            model: model,
            endpoint: endpoint,
            apiKey: apiKey,
            appID: appID,
            accessToken: accessToken,
            openAIChunkPseudoRealtimeEnabled: openAIChunkPseudoRealtimeEnabled
        )
    }

    static func makeAppBranchGroup(
        id: UUID = UUID(),
        name: String,
        prompt: String,
        appBundleIDs: [String] = [],
        urlPatternIDs: [UUID] = []
    ) -> AppBranchGroup {
        AppBranchGroup(
            id: id,
            name: name,
            prompt: prompt,
            appBundleIDs: appBundleIDs,
            appRefs: appBundleIDs.map { AppBranchAppRef(bundleID: $0, displayName: $0) },
            urlPatternIDs: urlPatternIDs,
            isExpanded: true
        )
    }

    static func makeURLItem(id: UUID = UUID(), pattern: String) -> BranchURLItem {
        BranchURLItem(id: id, pattern: pattern)
    }

    static func makeDictionarySuggestion(term: String, groupID: UUID? = nil) -> DictionarySuggestion {
        DictionarySuggestion(
            term: term,
            normalizedTerm: normalizedDictionaryTerm(term),
            sourceContext: .history,
            groupID: groupID
        )
    }
}

private func normalizedDictionaryTerm(_ input: String) -> String {
    let folded = input.folding(
        options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
        locale: .current
    )
    var output = ""
    var previousWasWhitespace = false

    for scalar in folded.unicodeScalars {
        if isDictionaryWordScalar(scalar) {
            output.unicodeScalars.append(scalar)
            previousWasWhitespace = false
        } else if CharacterSet.whitespacesAndNewlines.contains(scalar)
                    || CharacterSet.punctuationCharacters.contains(scalar)
                    || CharacterSet.symbols.contains(scalar) {
            if !previousWasWhitespace && !output.isEmpty {
                output.append(" ")
                previousWasWhitespace = true
            }
        }
    }

    return output.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func isDictionaryWordScalar(_ scalar: UnicodeScalar) -> Bool {
    CharacterSet.alphanumerics.contains(scalar)
        || isHanLike(scalar)
        || isKana(scalar)
        || isHangul(scalar)
}

private func isHanLike(_ scalar: UnicodeScalar) -> Bool {
    switch scalar.value {
    case 0x4E00...0x9FFF,
         0x3400...0x4DBF,
         0x20000...0x2A6DF,
         0x2A700...0x2B73F,
         0x2B740...0x2B81F,
         0x2B820...0x2CEAF:
        return true
    default:
        return false
    }
}

private func isKana(_ scalar: UnicodeScalar) -> Bool {
    switch scalar.value {
    case 0x3040...0x309F,
         0x30A0...0x30FF,
         0x31F0...0x31FF,
         0xFF66...0xFF9D:
        return true
    default:
        return false
    }
}

private func isHangul(_ scalar: UnicodeScalar) -> Bool {
    switch scalar.value {
    case 0x1100...0x11FF,
         0x3130...0x318F,
         0xAC00...0xD7AF:
        return true
    default:
        return false
    }
}
