// RelativeNoteTimestampFormatterTests.swift
// Provides Relative Note Timestamp Formatter Tests for Voxt test coverage.

import XCTest
@testable import Voxt

final class RelativeNoteTimestampFormatterTests: XCTestCase {
    private var originalInterfaceLanguage: String?

    override func setUp() {
        super.setUp()
        originalInterfaceLanguage = UserDefaults.standard.string(forKey: AppPreferenceKey.interfaceLanguage)
        UserDefaults.standard.set(AppInterfaceLanguage.english.rawValue, forKey: AppPreferenceKey.interfaceLanguage)
        AppLocalization.refreshLanguageCache()
    }

    override func tearDown() {
        if let originalInterfaceLanguage {
            UserDefaults.standard.set(originalInterfaceLanguage, forKey: AppPreferenceKey.interfaceLanguage)
        } else {
            UserDefaults.standard.removeObject(forKey: AppPreferenceKey.interfaceLanguage)
        }
        AppLocalization.refreshLanguageCache()
        super.tearDown()
    }

    func testNoteCardTimestampHidesDatesOlderThanFifteenDays() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let recent = now.addingTimeInterval(-(3 * 24 * 60 * 60))
        let stale = now.addingTimeInterval(-(16 * 24 * 60 * 60))

        XCTAssertEqual(RelativeNoteTimestampFormatter.noteCardTimestamp(for: recent, now: now), "3 days ago")
        XCTAssertNil(RelativeNoteTimestampFormatter.noteCardTimestamp(for: stale, now: now))
    }

    func testNoteHistoryTimestampFallsBackToAbsoluteDateAfterFifteenDays() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let stale = now.addingTimeInterval(-(16 * 24 * 60 * 60))

        let text = RelativeNoteTimestampFormatter.noteHistoryTimestamp(for: stale, now: now)

        XCTAssertFalse(text.isEmpty)
        XCTAssertNotEqual(text, "16 days ago")
    }
}
