// GGUFUTF8OutputAccumulatorTests.swift
// Provides GGUF UTF-8 output accumulator tests for Voxt test coverage.

import XCTest
@testable import Voxt

final class GGUFUTF8OutputAccumulatorTests: XCTestCase {
    func testWaitsForCompleteMultibyteSequenceBeforeDecoding() {
        var accumulator = GGUFUTF8OutputAccumulator()
        let text = "繁體工程師 français"
        let bytes = Array(text.utf8)
        let splitIndex = bytes.firstIndex(of: 0x94) ?? 1

        XCTAssertNil(accumulator.append(Array(bytes[..<splitIndex])))
        XCTAssertEqual(accumulator.append(Array(bytes[splitIndex...])), text)
        XCTAssertEqual(accumulator.finalizedText(), text)
        XCTAssertFalse(accumulator.finalizedWithReplacementCharacters)
    }

    func testFinalizesInvalidUTF8WithReplacementFlag() {
        var accumulator = GGUFUTF8OutputAccumulator()

        XCTAssertNil(accumulator.append([0xE7]))
        XCTAssertEqual(accumulator.finalizedText(), "\u{FFFD}")
        XCTAssertTrue(accumulator.finalizedWithReplacementCharacters)
    }
}
