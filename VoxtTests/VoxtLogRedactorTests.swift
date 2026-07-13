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

    func testSensitivePrivacyOmitsEntireUserContent() {
        let redacted = VoxtLogRedactor.redact(
            "private transcript and model response",
            privacy: .sensitive
        )

        XCTAssertEqual(redacted, "<redacted>")
        XCTAssertFalse(redacted.contains("transcript"))
    }

    func testLLMContentLoggerDoesNotEvaluateSensitiveMessage() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: AppPreferenceKey.llmDebugLoggingEnabled)
        defaults.set(true, forKey: AppPreferenceKey.llmDebugLoggingEnabled)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: AppPreferenceKey.llmDebugLoggingEnabled)
            } else {
                defaults.removeObject(forKey: AppPreferenceKey.llmDebugLoggingEnabled)
            }
        }

        var evaluated = false
        VoxtLog.llm({
            evaluated = true
            return "private prompt and response"
        }())

        XCTAssertFalse(evaluated)
    }

    func testLLMDebugLoggerEvaluatesSafeMetadataWhenEnabled() {
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: AppPreferenceKey.llmDebugLoggingEnabled)
        defaults.set(true, forKey: AppPreferenceKey.llmDebugLoggingEnabled)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: AppPreferenceKey.llmDebugLoggingEnabled)
            } else {
                defaults.removeObject(forKey: AppPreferenceKey.llmDebugLoggingEnabled)
            }
        }

        var evaluated = false
        VoxtLog.llmDebug({
            evaluated = true
            return "model=test, inputChars=42"
        }())

        XCTAssertTrue(evaluated)
    }
}
