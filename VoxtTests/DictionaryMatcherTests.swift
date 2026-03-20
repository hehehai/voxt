import XCTest
@testable import Voxt

final class DictionaryMatcherTests: XCTestCase {
    func testObservedVariantRequiresAutomaticReplacement() {
        let matcher = DictionaryMatcher(
            entries: [TestFactories.makeEntry(term: "Anthropic", observedVariants: ["anthropic ai"])],
            blockedGlobalMatchKeys: []
        )

        let withoutAutomatic = matcher.applyCorrections(to: "anthropic ai", automaticReplacementEnabled: false)
        XCTAssertEqual(withoutAutomatic.text, "anthropic ai")

        let withAutomatic = matcher.applyCorrections(to: "anthropic ai", automaticReplacementEnabled: true)
        XCTAssertEqual(withAutomatic.text, "Anthropic")
        XCTAssertEqual(withAutomatic.correctedTerms, ["Anthropic"])
    }

    func testFuzzyLatinWindowIsDetected() {
        let matcher = DictionaryMatcher(
            entries: [TestFactories.makeEntry(term: "Kubernetes")],
            blockedGlobalMatchKeys: []
        )

        let candidates = matcher.recallCandidates(
            in: "kubernetez cluster"
        )

        XCTAssertTrue(
            candidates.contains { $0.term == "Kubernetes" && $0.reason == .fuzzyWindow }
        )
    }

    func testOverlappingReplacementsDoNotApplyMultipleCorrectionsToSameSpan() {
        let matcher = DictionaryMatcher(
            entries: [
                TestFactories.makeEntry(term: "OpenAI", replacementTerms: ["open ai"]),
                TestFactories.makeEntry(term: "AI", replacementTerms: ["ai"])
            ],
            blockedGlobalMatchKeys: []
        )

        let result = matcher.applyCorrections(
            to: "open ai",
            automaticReplacementEnabled: false
        )

        XCTAssertEqual(result.text, "open AI")
        XCTAssertEqual(result.correctedTerms, ["AI"])
    }

    func testCJKExactMatchDoesNotRequireWhitespaceBoundaries() {
        let matcher = DictionaryMatcher(
            entries: [TestFactories.makeEntry(term: "你好")],
            blockedGlobalMatchKeys: []
        )

        let context = matcher.promptContext(for: "你好世界")

        XCTAssertEqual(context.candidates.first?.term, "你好")
    }

    func testPromptContextDeduplicatesCanonicalTermsAndHonorsLimit() {
        let entries = (1...13).map { TestFactories.makeEntry(term: "Term\($0)") }
        let matcher = DictionaryMatcher(entries: entries, blockedGlobalMatchKeys: [])
        let text = entries.map(\.term).joined(separator: " ")

        let glossary = matcher.promptContext(for: text).glossaryText()

        XCTAssertEqual(glossary.split(separator: "\n").count, 12)
        XCTAssertFalse(glossary.contains("- Term13"))
    }
}
