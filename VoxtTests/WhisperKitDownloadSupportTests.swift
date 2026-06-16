// WhisperKitDownloadSupportTests.swift
// Provides Whisper Kit Download Support Tests for Voxt test coverage.

import XCTest
@testable import Voxt

final class WhisperKitDownloadSupportTests: XCTestCase {
    func testMetadataRecoveryRetryDetectionMatchesKnownErrorText() {
        let error = NSError(
            domain: "Test",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "File metadata must have been retrieved before opening."]
        )

        XCTAssertTrue(WhisperKitDownloadSupport.shouldRetryAfterMetadataRecovery(for: error))
    }

    func testMetadataRecoveryRetryDetectionIgnoresUnrelatedErrors() {
        let error = NSError(
            domain: "Test",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Network connection was lost."]
        )

        XCTAssertFalse(WhisperKitDownloadSupport.shouldRetryAfterMetadataRecovery(for: error))
    }

    func testFileResolveURLEncodesNestedPathComponents() throws {
        let url = try WhisperKitDownloadSupport.fileResolveURL(
            baseURL: URL(string: "https://hf-mirror.com")!,
            repo: "argmaxinc/whisperkit-coreml",
            path: "openai_whisper-base/model weights.bin"
        )

        XCTAssertEqual(
            url.absoluteString,
            "https://hf-mirror.com/argmaxinc/whisperkit-coreml/resolve/main/openai_whisper-base/model%20weights.bin?download=true"
        )
    }
}
