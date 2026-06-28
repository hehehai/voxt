// EntryValidationSupportTests.swift
// Provides Entry Validation Support Tests for Voxt test coverage.

import XCTest
@testable import Voxt

final class EntryValidationSupportTests: XCTestCase {
    func testPrepareAllowsDuplicateNormalizedHotwordTerm() throws {
        let existingEntry = TestFactories.makeEntry(term: "Voxt")

        XCTAssertNoThrow(
            try DictionaryEntryInputPreparer.prepare(
                term: "voxt",
                replacementTerms: [],
                groupID: nil,
                entries: [existingEntry]
            )
        )
    }
}
