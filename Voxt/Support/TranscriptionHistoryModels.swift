import Foundation

extension AssistantHistoryStep {
    init(from recipeStep: ActionAssistantRecipe.Step, title: String, recordedAt: Date = Date()) {
        self.init(
            title: title,
            action: recipeStep.action,
            targetApp: recipeStep.targetApp,
            targetLabel: recipeStep.target?.computedNameContains,
            targetRole: recipeStep.target?.criteria?.first(where: { $0.attribute == "AXRole" })?.value,
            relativeX: recipeStep.params?["relative_x"].flatMap(Double.init),
            relativeY: recipeStep.params?["relative_y"].flatMap(Double.init),
            resolvedTargetLabel: nil,
            resolvedTargetRole: nil,
            resolvedRelativeX: nil,
            resolvedRelativeY: nil,
            success: nil,
            durationMs: nil,
            error: nil,
            diagnosisCategory: nil,
            diagnosisReason: nil,
            params: recipeStep.params,
            note: recipeStep.note,
            waitAfter: recipeStep.waitAfter.map {
                .init(condition: $0.condition, value: $0.value, timeout: $0.timeout)
            },
            recordedAt: recordedAt
        )
    }
}

extension TranscriptionHistoryEntry {
    static func make(
        text: String,
        transcriptionEngine: String,
        transcriptionModel: String,
        enhancementMode: String,
        enhancementModel: String,
        kind: TranscriptionHistoryKind,
        isTranslation: Bool,
        audioDurationSeconds: TimeInterval?,
        transcriptionProcessingDurationSeconds: TimeInterval?,
        llmDurationSeconds: TimeInterval?,
        focusedAppName: String?,
        matchedAppGroupName: String?,
        matchedURLGroupName: String?,
        remoteASRProvider: String?,
        remoteASRModel: String?,
        remoteASREndpoint: String?,
        remoteLLMProvider: String?,
        remoteLLMModel: String?,
        remoteLLMEndpoint: String?,
        assistantSummary: String?,
        assistantActions: [String]?,
        assistantStructuredSteps: [AssistantHistoryStep]?,
        assistantSnapshotPath: String?
    ) -> Self {
        .init(
            id: UUID(),
            text: text,
            createdAt: Date(),
            transcriptionEngine: transcriptionEngine,
            transcriptionModel: transcriptionModel,
            enhancementMode: enhancementMode,
            enhancementModel: enhancementModel,
            kind: kind,
            isTranslation: isTranslation,
            audioDurationSeconds: audioDurationSeconds,
            transcriptionProcessingDurationSeconds: transcriptionProcessingDurationSeconds,
            llmDurationSeconds: llmDurationSeconds,
            focusedAppName: focusedAppName,
            matchedAppGroupName: matchedAppGroupName,
            matchedURLGroupName: matchedURLGroupName,
            remoteASRProvider: remoteASRProvider,
            remoteASRModel: remoteASRModel,
            remoteASREndpoint: remoteASREndpoint,
            remoteLLMProvider: remoteLLMProvider,
            remoteLLMModel: remoteLLMModel,
            remoteLLMEndpoint: remoteLLMEndpoint,
            assistantSummary: assistantSummary,
            assistantActions: assistantActions,
            assistantStructuredSteps: assistantStructuredSteps,
            assistantSnapshotPath: assistantSnapshotPath
        )
    }
}
