// ModelTestGate.swift
// Provides Model Test Gate for test support.

import XCTest

enum ModelTestGate {
    static let environmentVariable = "VOXT_RUN_MODEL_TESTS"

    static func requireEnabled(_ testDescription: String) throws {
        let rawValue = ProcessInfo.processInfo.environment[environmentVariable]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let enabledValues: Set<String> = ["1", "true", "yes", "on"]

        guard let rawValue, enabledValues.contains(rawValue) else {
            throw XCTSkip(
                "\(testDescription) skipped by default. Set \(environmentVariable)=1 when running model tests explicitly."
            )
        }
    }
}
