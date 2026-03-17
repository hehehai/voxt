import Foundation

struct RewriteAnswerPayload {
    let title: String
    let content: String
}

struct SessionFinalizeContext {
    var outputText: String
    let llmDurationSeconds: TimeInterval?
    var dictionaryMatches: [DictionaryMatchCandidate]
    var dictionaryCorrectedTerms: [String]
    var dictionarySuggestions: [DictionarySuggestionDraft]
    var historyEntryID: UUID?
    var rewriteAnswerPayload: RewriteAnswerPayload?
}

protocol SessionFinalizeStage {
    var name: String { get }
    func run(context: inout SessionFinalizeContext)
}

struct SessionFinalizePipelineRunner {
    let stages: [any SessionFinalizeStage]

    func run(initial: SessionFinalizeContext) -> SessionFinalizeContext {
        var context = initial
        for stage in stages {
            stage.run(context: &context)
        }
        return context
    }
}
