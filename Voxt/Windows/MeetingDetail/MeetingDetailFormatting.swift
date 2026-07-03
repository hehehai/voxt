// MeetingDetailFormatting.swift
// Provides Meeting Detail Formatting for meeting detail windows.

import Foundation

enum MeetingDetailFormatting {
    static func summaryParagraphs(_ body: String) -> [String] {
        body
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
