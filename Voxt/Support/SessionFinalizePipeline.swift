import Foundation

struct SessionFinalizeContext {
    var outputText: String
    let llmDurationSeconds: TimeInterval?
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
