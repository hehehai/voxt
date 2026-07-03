// TranscriptionDetailSupport.swift
// Provides Transcription Detail Support for transcription processing.

import Foundation

struct TranscriptionFollowUpProviderStatus: Equatable, Sendable {
    let isAvailable: Bool
    let message: String
}

enum TranscriptionDetailSupport {
    static func title(for kind: TranscriptionHistoryKind) -> String {
        switch kind {
        case .normal:
            return String(localized: "Transcription Details")
        case .translation:
            return String(localized: "Translation Details")
        case .rewrite:
            return String(localized: "Rewrite Details")
        case .transcript:
            return String(localized: "Transcript Details")
        }
    }

    static func followUpPrompt(
        entry: TranscriptionHistoryEntry,
        history: [TranscriptSummaryChatMessage],
        question: String,
        userMainLanguage: String
    ) -> String {
        let trimmedHistory = history
            .map { message in
                let roleLabel = message.role == .user ? "User" : "Assistant"
                return "\(roleLabel): \(message.content)"
            }
            .joined(separator: "\n")

        return """
        You are Voxt's saved transcription follow-up assistant.

        Answer the user's follow-up question using the saved result below.

        Rules:
        1. Treat the saved result text as the primary source of truth.
        2. Use previous chat only as supplemental context.
        3. Reply in the user's main language.
        4. Answer directly and clearly.
        5. Do not invent facts. If the saved result does not contain enough information, say so explicitly.
        6. Return plain text only. Do not return JSON or markdown code fences.

        User main language: \(userMainLanguage)
        Result type: \(entry.kind.rawValue)
        Result created at: \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))

        Saved result text:
        \(entry.text)

        Previous follow-up chat:
        \(trimmedHistory.isEmpty ? "None" : trimmedHistory)

        Current user question:
        \(question)
        """
    }
}
