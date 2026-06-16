// MeetingDetailFormattingTests.swift
// Provides Meeting Detail Formatting Tests for Voxt test coverage.

import XCTest
@testable import Voxt

final class MeetingDetailFormattingTests: XCTestCase {
    func testSummaryParagraphsSplitsOnBlankLinesAndTrimsWhitespace() {
        let paragraphs = MeetingDetailFormatting.summaryParagraphs(
            "\n  First paragraph.\n\n\n  Second paragraph with spaces.\n\nThird paragraph."
        )

        XCTAssertEqual(
            paragraphs,
            [
                "First paragraph.",
                "Second paragraph with spaces.",
                "Third paragraph."
            ]
        )
    }

    func testSummaryParagraphsDropsEmptyBlocks() {
        XCTAssertEqual(MeetingDetailFormatting.summaryParagraphs(" \n\n \n\n"), [])
    }
}
