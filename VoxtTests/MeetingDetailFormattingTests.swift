import XCTest
@testable import Voxt

final class MeetingDetailFormattingTests: XCTestCase {
    func testSummaryParagraphsSplitsOnBlankLinesAndTrimsWhitespace() {
        let paragraphs = MeetingDetailFormatting.summaryParagraphs("""
        
          First paragraph.
        
        
          Second paragraph with spaces.
        
        Third paragraph.
        """)

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
