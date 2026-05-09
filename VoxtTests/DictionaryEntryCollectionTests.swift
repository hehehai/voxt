import XCTest
@testable import Voxt

final class DictionaryEntryCollectionTests: XCTestCase {
    func testFilteredEntriesSeparatesManualAndAutoSources() {
        let entries = DictionaryEntryCollection.sortedEntries([
            makeEntry(term: "Voxt", source: .manual, updatedAt: Date(timeIntervalSince1970: 100)),
            makeEntry(term: "Waxed", source: .auto, updatedAt: Date(timeIntervalSince1970: 200)),
            makeEntry(term: "Ghostty", source: .manual, updatedAt: Date(timeIntervalSince1970: 300))
        ])

        let cache = DictionaryEntryCollection.filteredEntriesCache(for: entries)

        XCTAssertEqual(cache[.all]?.map(\.term), ["Ghostty", "Waxed", "Voxt"])
        XCTAssertEqual(cache[.manualAdded]?.map(\.term), ["Ghostty", "Voxt"])
        XCTAssertEqual(cache[.autoAdded]?.map(\.term), ["Waxed"])
    }

    func testPromptBiasTermsTextPrioritizesHigherMatchCountAndRespectsLimits() {
        let highPriority = makeEntry(
            term: "Anthropic",
            source: .manual,
            matchCount: 9,
            updatedAt: Date(timeIntervalSince1970: 200)
        )
        let secondary = makeEntry(
            term: "OpenAI",
            source: .manual,
            matchCount: 4,
            updatedAt: Date(timeIntervalSince1970: 150)
        )
        let duplicateNormalized = makeEntry(
            term: "openai",
            source: .manual,
            matchCount: 3,
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        let bias = DictionaryEntryCollection.promptBiasTermsText(
            from: [secondary, duplicateNormalized, highPriority],
            activeGroupID: nil,
            maxCount: 2,
            maxCharacters: 32
        )

        XCTAssertEqual(bias, "Anthropic\nOpenAI")
    }

    func testPromptBiasTermsTextPrefersScopedEntriesOverBlockedGlobals() {
        let sharedKey = "Voxt"
        let groupID = UUID()
        let global = makeEntry(
            term: sharedKey,
            source: .manual,
            groupID: nil,
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let scoped = makeEntry(
            term: sharedKey,
            source: .manual,
            groupID: groupID,
            matchCount: 5,
            updatedAt: Date(timeIntervalSince1970: 300)
        )
        let extraGlobal = makeEntry(
            term: "Ghostty",
            source: .manual,
            groupID: nil,
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        let bias = DictionaryEntryCollection.promptBiasTermsText(
            from: [global, scoped, extraGlobal],
            activeGroupID: groupID,
            maxCount: 5,
            maxCharacters: 80
        )

        XCTAssertEqual(bias, "Voxt\nGhostty")
    }
}

private extension DictionaryEntryCollectionTests {
    func makeEntry(
        term: String,
        source: DictionaryEntrySource,
        groupID: UUID? = nil,
        matchCount: Int = 0,
        updatedAt: Date = Date()
    ) -> DictionaryEntry {
        DictionaryEntry(
            term: term,
            normalizedTerm: DictionaryStore.normalizeTerm(term),
            groupID: groupID,
            source: source,
            updatedAt: updatedAt,
            matchCount: matchCount
        )
    }
}
