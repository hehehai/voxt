import Foundation

enum DictionaryGlossaryPurpose {
    case enhancement
    case translation
    case rewrite
}

enum DictionaryGlossaryPromptComposer {
    nonisolated static func append(
        prompt: String,
        glossary: String?,
        purpose: DictionaryGlossaryPurpose
    ) -> String {
        let trimmedGlossary = glossary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedGlossary.isEmpty else { return prompt }

        let instruction: String
        switch purpose {
        case .enhancement:
            instruction = """
            ### Dictionary Guidance
            Prefer these exact spellings when the transcript context indicates the user meant them:
            \(trimmedGlossary)

            If a nearby phrase looks like one of these terms, prefer the exact spelling above.
            """
        case .translation:
            instruction = """
            ### Dictionary Guidance
            When the source text refers to these proper nouns or product terms, preserve their exact spelling unless translation clearly requires otherwise:
            \(trimmedGlossary)
            """
        case .rewrite:
            instruction = """
            ### Dictionary Guidance
            Prefer these exact term spellings in the final output when relevant:
            \(trimmedGlossary)
            """
        }

        return "\(prompt)\n\n\(instruction)"
    }
}
