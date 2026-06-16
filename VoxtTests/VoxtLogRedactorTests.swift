// VoxtLogRedactorTests.swift
// Provides Voxt Log Redactor Tests for Voxt test coverage.

import XCTest
@testable import Voxt

final class VoxtLogRedactorTests: XCTestCase {
    func testRedactsCommonSecretShapes() {
        let text = """
        Authorization: Bearer abc.def.ghi
        apiKey=sk-test-secret
        access_token=token-value
        https://example.com/path?token=query-secret&safe=1
        """

        let redacted = VoxtLogRedactor.redact(text)

        XCTAssertFalse(redacted.contains("abc.def.ghi"))
        XCTAssertFalse(redacted.contains("sk-test-secret"))
        XCTAssertFalse(redacted.contains("token-value"))
        XCTAssertFalse(redacted.contains("query-secret"))
        XCTAssertTrue(redacted.contains("<redacted>"))
        XCTAssertTrue(redacted.contains("safe=1"))
    }

    func testPreviewRedactsAndTruncates() {
        let preview = VoxtLogRedactor.preview(
            "apiKey=secret-value " + String(repeating: "x", count: 80),
            limit: 30
        )

        XCTAssertFalse(preview.contains("secret-value"))
        XCTAssertTrue(preview.contains("<redacted>"))
        XCTAssertTrue(preview.contains("[truncated]"))
    }

    func testRedactsHomeDirectory() {
        let home = NSHomeDirectory()
        let redacted = VoxtLogRedactor.redact("path=\(home)/Documents/private.txt")

        XCTAssertFalse(redacted.contains(home))
        XCTAssertTrue(redacted.contains("~/Documents/private.txt"))
    }
}
