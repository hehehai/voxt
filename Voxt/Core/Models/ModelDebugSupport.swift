// ModelDebugSupport.swift
// Provides Model Debug Support for model catalog and storage support.

import Foundation
import AVFoundation

struct ASRDebugModelOption: Identifiable, Hashable {
    enum Selection: Hashable {
        case mlx(repo: String)
        case remote(provider: RemoteASRProvider, configuration: RemoteProviderConfiguration)
    }

    let id: String
    let title: String
    let subtitle: String
    let selection: Selection
}

struct LLMDebugModelOption: Identifiable, Hashable {
    enum Selection: Hashable {
        case local(repo: String)
        case remote(provider: RemoteLLMProvider, configuration: RemoteProviderConfiguration)
    }

    let id: String
    let title: String
    let subtitle: String
    let selection: Selection
}

enum LLMDebugPresetKind: Hashable {
    case custom
    case enhancement
    case translation
    case rewrite
    case transcriptSummary
    case appGroup(groupID: UUID)
}

struct LLMDebugPresetOption: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let kind: LLMDebugPresetKind
    let promptTemplate: String
    let variables: [PromptTemplateVariableDescriptor]
    let defaultValues: [String: String]
}

extension LLMDebugPresetOption {
    var runtimeInputDescriptors: [PromptTemplateVariableDescriptor] {
        switch kind {
        case .custom:
            return []
        case .enhancement, .appGroup:
            return [
                PromptTemplateVariableDescriptor(
                    token: AppDelegate.rawTranscriptionTemplateVariable,
                    tipKey: "Template tip {{RAW_TRANSCRIPTION}}"
                ),
                PromptTemplateVariableDescriptor(
                    token: AppDelegate.userMainLanguageTemplateVariable,
                    tipKey: "Template tip {{USER_MAIN_LANGUAGE}}"
                )
            ]
        case .translation:
            return [
                PromptTemplateVariableDescriptor(
                    token: "{{SOURCE_TEXT}}",
                    tipKey: "Template tip {{SOURCE_TEXT}}"
                ),
                PromptTemplateVariableDescriptor(
                    token: "{{TARGET_LANGUAGE}}",
                    tipKey: "Template tip {{TARGET_LANGUAGE}}"
                ),
                PromptTemplateVariableDescriptor(
                    token: AppDelegate.userMainLanguageTemplateVariable,
                    tipKey: "Template tip {{USER_MAIN_LANGUAGE}}"
                )
            ]
        case .rewrite:
            return [
                PromptTemplateVariableDescriptor(
                    token: "{{DICTATED_PROMPT}}",
                    tipKey: "Template tip {{DICTATED_PROMPT}}"
                ),
                PromptTemplateVariableDescriptor(
                    token: "{{SOURCE_TEXT}}",
                    tipKey: "Template tip {{SOURCE_TEXT}}"
                )
            ]
        case .transcriptSummary:
            return TranscriptSummarySupport.promptTemplateVariables.map {
                PromptTemplateVariableDescriptor(token: $0, tipKey: "Template tip \($0)")
            }
        }
    }
}

struct LLMDebugResolvedPrompt: Equatable {
    let content: String
    let inputSummary: String
    let compiledRequest: LLMCompiledRequest?
    let requestMetadata: LLMDebugRequestMetadata?
}

struct LLMDebugRequestMetadata: Equatable {
    let spokenInstruction: String
    let sourceText: String
    let appContextCharacterCount: Int
    let imageAttachmentCount: Int
    let imagePreviews: [LLMDebugImagePreview]
}

struct LLMDebugImagePreview: Equatable {
    let filename: String
    let mimeType: String
    let detail: String
    let data: Data
}

struct DebugAudioClip: Identifiable, Equatable {
    let id: UUID
    let fileURL: URL
    let durationSeconds: Double
    let sampleRate: Double
    let createdAt: Date

    var summaryText: String {
        let duration = String(format: "%.1f", durationSeconds)
        let rate = Int(sampleRate.rounded())
        return "\(duration)s · \(rate) Hz"
    }
}

enum LLMDebugPresetStore {
    static let customPresetID = "custom"

    static func customPrompt(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: AppPreferenceKey.llmDebugCustomPrompt)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func saveCustomPrompt(_ prompt: String, defaults: UserDefaults = .standard) {
        defaults.set(prompt, forKey: AppPreferenceKey.llmDebugCustomPrompt)
    }

    static func promptOverride(for presetID: String, defaults: UserDefaults = .standard) -> String? {
        let overrides = promptOverrides(defaults: defaults)
        return overrides[presetID]
    }

    static func savePromptOverride(_ prompt: String, for presetID: String, defaults: UserDefaults = .standard) {
        var overrides = promptOverrides(defaults: defaults)
        overrides[presetID] = prompt
        savePromptOverrides(overrides, defaults: defaults)
    }

    static func removePromptOverride(for presetID: String, defaults: UserDefaults = .standard) {
        var overrides = promptOverrides(defaults: defaults)
        guard overrides.removeValue(forKey: presetID) != nil else { return }
        savePromptOverrides(overrides, defaults: defaults)
    }

    private static func promptOverrides(defaults: UserDefaults) -> [String: String] {
        guard let data = defaults.data(forKey: AppPreferenceKey.llmDebugPresetPromptOverrides),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    private static func savePromptOverrides(_ overrides: [String: String], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(overrides) else { return }
        defaults.set(data, forKey: AppPreferenceKey.llmDebugPresetPromptOverrides)
    }
}

enum ModelDebugCatalog {
    static func availableASRModels(
        mlxModelManager: MLXModelManager,
        remoteASRConfigurations: [String: RemoteProviderConfiguration]
    ) -> [ASRDebugModelOption] {
        let downloadedMLXRepos = Set(
            MLXModelManager.availableModels.compactMap { model in
                mlxModelManager.isModelDownloaded(repo: model.id) ? model.id : nil
            }
        )

        return availableASRModels(
            downloadedMLXRepos: downloadedMLXRepos,
            remoteASRConfigurations: remoteASRConfigurations
        )
    }

    static func availableASRModels(
        downloadedMLXRepos: Set<String>,
        remoteASRConfigurations: [String: RemoteProviderConfiguration]
    ) -> [ASRDebugModelOption] {
        var options: [ASRDebugModelOption] = []

        let localMLX = MLXModelManager.availableModels.compactMap { model -> ASRDebugModelOption? in
            guard downloadedMLXRepos.contains(model.id) else { return nil }
            return ASRDebugModelOption(
                id: "mlx:\(model.id)",
                title: MLXModelCatalog.displayTitle(for: model.id),
                subtitle: AppLocalization.localizedString("Local MLX Audio"),
                selection: .mlx(repo: model.id)
            )
        }
        options.append(contentsOf: localMLX)

        let remote = RemoteASRProvider.allCases.compactMap { provider -> ASRDebugModelOption? in
            let configuration = RemoteModelConfigurationStore.resolvedASRConfiguration(
                provider: provider,
                stored: remoteASRConfigurations
            )
            guard configuration.isConfigured, configuration.hasUsableModel else { return nil }
            return ASRDebugModelOption(
                id: "remote-asr:\(provider.rawValue)",
                title: "\(provider.title) · \(configuration.model)",
                subtitle: AppLocalization.localizedString("Configured Remote ASR"),
                selection: .remote(provider: provider, configuration: configuration)
            )
        }
        options.append(contentsOf: remote)

        return options
    }

    static func availableLLMModels(
        customLLMManager: CustomLLMModelManager,
        remoteLLMConfigurations: [String: RemoteProviderConfiguration]
    ) -> [LLMDebugModelOption] {
        let downloadedLocalRepos = Set(
            CustomLLMModelCatalog.displayModels(including: customLLMManager.currentModelRepo)
                .compactMap { model in
                    customLLMManager.isModelDownloaded(repo: model.id) ? model.id : nil
                }
        )

        return availableLLMModels(
            downloadedLocalRepos: downloadedLocalRepos,
            currentLocalRepo: customLLMManager.currentModelRepo,
            remoteLLMConfigurations: remoteLLMConfigurations
        )
    }

    static func availableLLMModels(
        downloadedLocalRepos: Set<String>,
        currentLocalRepo: String?,
        remoteLLMConfigurations: [String: RemoteProviderConfiguration]
    ) -> [LLMDebugModelOption] {
        var options: [LLMDebugModelOption] = []

        let local = CustomLLMModelCatalog.displayModels(including: currentLocalRepo)
            .compactMap { model -> LLMDebugModelOption? in
                guard downloadedLocalRepos.contains(model.id) else { return nil }
                return LLMDebugModelOption(
                    id: "local-llm:\(model.id)",
                    title: CustomLLMModelCatalog.displayTitle(for: model.id),
                    subtitle: AppLocalization.localizedString("Local Custom LLM"),
                    selection: .local(repo: model.id)
                )
            }
        options.append(contentsOf: local)

        let remote = RemoteLLMProvider.allCases.compactMap { provider -> LLMDebugModelOption? in
            guard RemoteModelConfigurationStore.isStoredLLMConfigurationConfigured(
                provider: provider,
                stored: remoteLLMConfigurations
            ) else {
                return nil
            }
            let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(
                provider: provider,
                stored: remoteLLMConfigurations
            )
            return LLMDebugModelOption(
                id: "remote-llm:\(provider.rawValue)",
                title: "\(provider.title) · \(configuration.model)",
                subtitle: AppLocalization.localizedString("Configured Remote LLM"),
                selection: .remote(provider: provider, configuration: configuration)
            )
        }
        options.append(contentsOf: remote)

        return options
    }

    static func availableLLMPresets(
        defaults: UserDefaults = .standard,
        promptOverrides: [String: String] = [:]
    ) -> [LLMDebugPresetOption] {
        let userMainLanguage = userMainLanguagePromptValue(defaults: defaults)
        let targetLanguage = TranslationTargetLanguage(
            rawValue: defaults.string(forKey: AppPreferenceKey.translationTargetLanguage) ?? ""
        ) ?? .english
        let featureSettings = FeatureSettingsStore.load(defaults: defaults)

        var presets: [LLMDebugPresetOption] = [
            LLMDebugPresetOption(
                id: LLMDebugPresetStore.customPresetID,
                title: AppLocalization.localizedString("Custom"),
                subtitle: AppLocalization.localizedString("Debug-only preset"),
                kind: .custom,
                promptTemplate: LLMDebugPresetStore.customPrompt(defaults: defaults),
                variables: [],
                defaultValues: [:]
            ),
            LLMDebugPresetOption(
                id: "builtin:enhancement",
                title: AppLocalization.localizedString("Transcription Enhancement"),
                subtitle: AppLocalization.localizedString("Built-in preset"),
                kind: .enhancement,
                promptTemplate: promptOverrides["builtin:enhancement"] ?? featureSettings.transcription.prompt,
                variables: ModelSettingsPromptVariables.enhancement,
                defaultValues: [
                    AppDelegate.rawTranscriptionTemplateVariable: "",
                    AppDelegate.userMainLanguageTemplateVariable: userMainLanguage
                ]
            ),
            LLMDebugPresetOption(
                id: "builtin:translation",
                title: AppLocalization.localizedString("Translation"),
                subtitle: AppLocalization.localizedString("Built-in preset"),
                kind: .translation,
                promptTemplate: promptOverrides["builtin:translation"] ?? featureSettings.translation.prompt,
                variables: ModelSettingsPromptVariables.translation,
                defaultValues: [
                    "{{TARGET_LANGUAGE}}": targetLanguage.instructionName,
                    AppDelegate.userMainLanguageTemplateVariable: userMainLanguage,
                    "{{SOURCE_TEXT}}": ""
                ]
            ),
            LLMDebugPresetOption(
                id: "builtin:rewrite",
                title: AppLocalization.localizedString("Rewrite"),
                subtitle: AppLocalization.localizedString("Built-in preset"),
                kind: .rewrite,
                promptTemplate: promptOverrides["builtin:rewrite"] ?? featureSettings.rewrite.prompt,
                variables: ModelSettingsPromptVariables.rewrite,
                defaultValues: [
                    "{{DICTATED_PROMPT}}": "",
                    "{{SOURCE_TEXT}}": ""
                ]
            ),
            LLMDebugPresetOption(
                id: "builtin:transcript-summary",
                title: AppLocalization.localizedString("Transcript Summary"),
                subtitle: AppLocalization.localizedString("Built-in preset"),
                kind: .transcriptSummary,
                promptTemplate: promptOverrides["builtin:transcript-summary"] ?? AppPromptDefaults.resolvedStoredText(
                    AppPreferenceKey.resolvedTranscriptSummaryPromptTemplate(defaults: defaults),
                    kind: .transcriptSummary,
                    defaults: defaults
                ),
                variables: TranscriptSummarySupport.promptTemplateVariables.map {
                    PromptTemplateVariableDescriptor(token: $0, tipKey: "Template tip \($0)")
                },
                defaultValues: [
                    AppPreferenceKey.asrUserMainLanguageTemplateVariable: userMainLanguage,
                    TranscriptSummarySupport.transcriptRecordTemplateVariable: ""
                ]
            )
        ]

        let groups = loadAppBranchGroups(defaults: defaults)
        presets.append(
            contentsOf: groups.compactMap { group -> LLMDebugPresetOption? in
                let trimmedPrompt = group.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedPrompt.isEmpty else { return nil }
                return LLMDebugPresetOption(
                    id: "group:\(group.id.uuidString)",
                    title: AppLocalization.format("App Enhancement · %@", group.name),
                    subtitle: AppLocalization.localizedString("Saved group preset"),
                    kind: .appGroup(groupID: group.id),
                    promptTemplate: promptOverrides["group:\(group.id.uuidString)"] ?? trimmedPrompt,
                    variables: ModelSettingsPromptVariables.appEnhancement,
                    defaultValues: [
                        AppDelegate.rawTranscriptionTemplateVariable: "",
                        AppDelegate.userMainLanguageTemplateVariable: userMainLanguage
                    ]
                )
            }
        )

        return presets
    }

    private static func userMainLanguagePromptValue(defaults: UserDefaults) -> String {
        let selectedCodes = UserMainLanguageOption.storedSelection(
            from: defaults.string(forKey: AppPreferenceKey.userMainLanguageCodes)
        )
        if let firstCode = selectedCodes.first,
           let option = UserMainLanguageOption.option(for: firstCode) {
            return option.promptName
        }
        return UserMainLanguageOption.fallbackOption().promptName
    }

    private static func loadAppBranchGroups(defaults: UserDefaults) -> [AppBranchGroup] {
        guard let data = defaults.data(forKey: AppPreferenceKey.appBranchGroups),
              let groups = try? JSONDecoder().decode([AppBranchGroup].self, from: data)
        else {
            return []
        }
        return groups
    }
}

enum ModelDebugPromptResolver {
    static func resolve(
        preset: LLMDebugPresetOption,
        values: [String: String],
        defaults: UserDefaults = .standard
    ) -> LLMDebugResolvedPrompt {
        let mergedValues = preset.defaultValues.merging(values) { _, rhs in rhs }
        switch preset.kind {
        case .custom:
            return LLMDebugResolvedPrompt(
                content: preset.promptTemplate,
                inputSummary: "",
                compiledRequest: nil,
                requestMetadata: nil
            )
        case .enhancement, .appGroup:
            let rawTranscription = mergedValues[AppDelegate.rawTranscriptionTemplateVariable] ?? ""
            let userMainLanguage = mergedValues[AppDelegate.userMainLanguageTemplateVariable] ?? ""
            let resolvedPrompt = resolveEnhancementPrompt(
                template: preset.promptTemplate,
                rawTranscription: rawTranscription,
                userMainLanguage: userMainLanguage
            )
            let plan = LLMExecutionPlan(
                task: .enhancement(rawText: rawTranscription),
                provider: .customLLM(repo: CustomLLMModelManager.defaultModelRepo),
                delivery: enhancementDelivery(for: preset),
                promptContent: resolvedPrompt,
                fallbackText: rawTranscription,
                executionStrategy: TaskLLMStrategyResolver.resolve(
                    taskKind: .transcriptionEnhancement,
                    rawText: rawTranscription,
                    promptCharacterCount: resolvedPrompt.count,
                    baseGlossarySelectionPolicy: DictionaryGlossaryPurpose.enhancement.selectionPolicy,
                    capabilities: .unknown
                ),
                outputTokenBudgetHint: nil,
                contextBlocks: compactBlocks([
                    LLMContextBlock(
                        kind: .input,
                        title: "Raw transcription",
                        content: rawTranscription,
                        isStablePrefixCandidate: false
                    )
                ]),
                attachments: [],
                conversationHistory: [],
                previousResponseID: nil,
                responseFormat: nil
            )
            let compiledRequest = LLMExecutionPlanCompiler.compile(plan)
            return LLMDebugResolvedPrompt(
                content: compiledRequestPreview(compiledRequest),
                inputSummary: rawTranscription,
                compiledRequest: compiledRequest,
                requestMetadata: nil
            )
        case .translation:
            let sourceText = mergedValues["{{SOURCE_TEXT}}"] ?? ""
            let resolvedLanguage = resolvedTranslationTargetLanguage(values: mergedValues, defaults: defaults)
            let resolvedPrompt = TranslationPromptBuilder.build(
                systemPrompt: preset.promptTemplate,
                targetLanguage: resolvedLanguage,
                sourceText: sourceText,
                userMainLanguagePromptValue: mergedValues[AppDelegate.userMainLanguageTemplateVariable] ?? "",
                strict: true
            )
            let plan = LLMExecutionPlan(
                task: .translation(sourceText: sourceText, targetLanguage: resolvedLanguage),
                provider: .customLLM(repo: CustomLLMModelManager.defaultModelRepo),
                delivery: variableTemplateDelivery(
                    preset.promptTemplate,
                    variableTokens: ["{{SOURCE_TEXT}}"]
                ),
                promptContent: resolvedPrompt,
                fallbackText: sourceText,
                executionStrategy: TaskLLMStrategyResolver.resolve(
                    taskKind: .translation,
                    rawText: sourceText,
                    promptCharacterCount: resolvedPrompt.count,
                    baseGlossarySelectionPolicy: DictionaryGlossaryPurpose.translation.selectionPolicy,
                    capabilities: .unknown
                ),
                outputTokenBudgetHint: nil,
                contextBlocks: compactBlocks([
                    LLMContextBlock(
                        kind: .input,
                        title: "Source text",
                        content: sourceText,
                        isStablePrefixCandidate: false
                    )
                ]),
                attachments: [],
                conversationHistory: [],
                previousResponseID: nil,
                responseFormat: nil
            )
            let compiledRequest = LLMExecutionPlanCompiler.compile(plan)
            return LLMDebugResolvedPrompt(
                content: compiledRequestPreview(compiledRequest),
                inputSummary: sourceText,
                compiledRequest: compiledRequest,
                requestMetadata: nil
            )
        case .rewrite:
            let dictatedPrompt = mergedValues["{{DICTATED_PROMPT}}"] ?? ""
            let sourceText = mergedValues["{{SOURCE_TEXT}}"] ?? ""
            let appContextCapture = mergedValues.rewriteAppContextCapture
            let resolvedPrompt = RewritePromptBuilder.build(
                systemPrompt: preset.promptTemplate,
                dictatedPrompt: dictatedPrompt,
                sourceText: sourceText,
                structuredAnswerOutput: false,
                directAnswerMode: sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                forceNonEmptyAnswer: false
            )
            let appContextAttachmentCost = appContextCapture?.attachments.estimatedPromptCharacterCost ?? 0
            let plan = LLMExecutionPlan(
                task: .rewrite(
                    dictatedPrompt: dictatedPrompt,
                    sourceText: sourceText,
                    structuredAnswerOutput: false
                ),
                provider: .customLLM(repo: CustomLLMModelManager.defaultModelRepo),
                delivery: variableTemplateDelivery(
                    preset.promptTemplate,
                    variableTokens: ["{{DICTATED_PROMPT}}", "{{SOURCE_TEXT}}"]
                ),
                promptContent: resolvedPrompt,
                fallbackText: sourceText,
                executionStrategy: TaskLLMStrategyResolver.resolve(
                    taskKind: .rewrite,
                    rawText: sourceText.isEmpty ? dictatedPrompt : sourceText,
                    promptCharacterCount: resolvedPrompt.count +
                        (appContextCapture?.textContext.count ?? 0) +
                        appContextAttachmentCost,
                    baseGlossarySelectionPolicy: DictionaryGlossaryPurpose.rewrite.selectionPolicy,
                    capabilities: .unknown
                ),
                outputTokenBudgetHint: nil,
                contextBlocks: compactBlocks([
                    LLMContextBlock(
                        kind: .input,
                        title: "Spoken instruction",
                        content: dictatedPrompt,
                        isStablePrefixCandidate: false
                    ),
                    sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? nil
                        : LLMContextBlock(
                            kind: .input,
                            title: "Selected source text",
                            content: sourceText,
                            isStablePrefixCandidate: false
                        ),
                    RewriteAppContextGuidance.content(
                        hasTextContext: !(appContextCapture?.textContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
                        imageAttachmentCount: appContextCapture?.attachments.count ?? 0,
                        directAnswerMode: sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ).map {
                        LLMContextBlock(
                            kind: .metadata,
                            title: "App context usage rules",
                            content: $0,
                            isStablePrefixCandidate: false
                        )
                    },
                    appContextCapture.map {
                        LLMContextBlock(
                            kind: .app,
                            title: "Active app context",
                            content: $0.textContext,
                            isStablePrefixCandidate: false
                        )
                    }
                ]),
                attachments: appContextCapture?.attachments ?? [],
                conversationHistory: [],
                previousResponseID: nil,
                responseFormat: nil
            )
            let compiledRequest = LLMExecutionPlanCompiler.compile(plan)
            return LLMDebugResolvedPrompt(
                content: compiledRequestPreview(compiledRequest),
                inputSummary: sourceText.isEmpty ? dictatedPrompt : sourceText,
                compiledRequest: compiledRequest,
                requestMetadata: LLMDebugRequestMetadata(
                    spokenInstruction: dictatedPrompt,
                    sourceText: sourceText,
                    appContextCharacterCount: appContextCapture?.textContext.count ?? 0,
                    imageAttachmentCount: appContextCapture?.attachments.count ?? 0,
                    imagePreviews: debugImagePreviews(from: appContextCapture?.attachments ?? [])
                )
            )
        case .transcriptSummary:
            let transcript = TranscriptSummarySupport.transcriptRecord(from: mergedValues)
            let content = TranscriptSummarySupport.summaryPrompt(
                transcript: transcript,
                settings: TranscriptSummarySettingsSnapshot(
                    autoGenerate: false,
                    promptTemplate: preset.promptTemplate,
                    modelSelectionID: nil
                ),
                userMainLanguage: mergedValues[AppPreferenceKey.asrUserMainLanguageTemplateVariable] ?? ""
            )
            let transcriptCharacterCount = transcript.trimmingCharacters(in: .whitespacesAndNewlines).count
            let strategy = TaskLLMExecutionStrategy(
                taskKind: .transcriptSummary,
                rawTextCharacterCount: transcriptCharacterCount,
                promptCharacterCount: content.count,
                mode: .singlePass,
                contextBudgetPolicy: transcriptCharacterCount > TaskLLMStrategyResolver.longTextThreshold ? .reducedForLongInput : .standard,
                glossarySelectionPolicy: DictionaryGlossarySelectionPolicy(maxTerms: 0, maxCharacters: 0),
                outputTokenBudgetHint: nil,
                segmentationCharacterLimit: nil,
                truncationGuard: .disabled
            )
            let plan = LLMExecutionPlan(
                task: .transcriptSummary(transcript: transcript, request: content),
                provider: .customLLM(repo: CustomLLMModelManager.defaultModelRepo),
                delivery: .userMessage,
                promptContent: content,
                fallbackText: "",
                executionStrategy: strategy,
                outputTokenBudgetHint: nil,
                contextBlocks: compactBlocks([
                    LLMContextBlock(
                        kind: .input,
                        title: "Transcript",
                        content: transcript,
                        isStablePrefixCandidate: false
                    )
                ]),
                attachments: [],
                conversationHistory: [],
                previousResponseID: nil,
                responseFormat: nil
            )
            let compiledRequest = LLMExecutionPlanCompiler.compile(plan)
            return LLMDebugResolvedPrompt(
                content: compiledRequestPreview(compiledRequest),
                inputSummary: transcript,
                compiledRequest: compiledRequest,
                requestMetadata: nil
            )
        }
    }

    private static func enhancementDelivery(for preset: LLMDebugPresetOption) -> LLMExecutionDelivery {
        switch preset.kind {
        case .appGroup:
            return .systemPrompt
        case .enhancement:
            return preset.promptTemplate.contains(AppDelegate.rawTranscriptionTemplateVariable)
                ? .userMessage
                : .systemPrompt
        case .custom, .translation, .rewrite, .transcriptSummary:
            return .systemPrompt
        }
    }

    private static func variableTemplateDelivery(
        _ template: String,
        variableTokens: [String]
    ) -> LLMExecutionDelivery {
        variableTokens.contains(where: template.contains) ? .userMessage : .systemPrompt
    }

    private static func resolvedTranslationTargetLanguage(
        values: [String: String],
        defaults: UserDefaults
    ) -> TranslationTargetLanguage {
        let storedTargetLanguage = TranslationTargetLanguage(
            rawValue: defaults.string(forKey: AppPreferenceKey.translationTargetLanguage) ?? ""
        ) ?? .english
        let languageName = values["{{TARGET_LANGUAGE}}"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return TranslationTargetLanguage.allCases.first(where: {
            $0.instructionName.caseInsensitiveCompare(languageName ?? "") == .orderedSame
        }) ?? storedTargetLanguage
    }

    private static func compactBlocks(_ blocks: [LLMContextBlock?]) -> [LLMContextBlock] {
        blocks.compactMap { block in
            guard let block else { return nil }
            return block.trimmedContent.isEmpty ? nil : block
        }
    }

    private static func compiledRequestPreview(_ request: LLMCompiledRequest) -> String {
        let sections = [
            request.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : "[instructions]\n\(request.instructions)",
            request.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : "[prompt]\n\(request.prompt)",
            attachmentPreviewSection(request.attachments)
        ].compactMap { $0 }

        return sections.joined(separator: "\n\n")
    }

    private static func attachmentPreviewSection(_ attachments: [LLMInputAttachment]) -> String? {
        guard !attachments.isEmpty else { return nil }
        let lines = attachments.map { attachment in
            switch attachment {
            case .image(let image):
                return "- image: \(image.filename) · \(image.mimeType) · detail=\(image.detail.rawValue) · \(image.data.count) bytes"
            }
        }
        return """
        [attachments]
        \(lines.joined(separator: "\n"))
        """
    }

    private static func debugImagePreviews(from attachments: [LLMInputAttachment]) -> [LLMDebugImagePreview] {
        attachments.compactMap { attachment in
            switch attachment {
            case .image(let image):
                return LLMDebugImagePreview(
                    filename: image.filename,
                    mimeType: image.mimeType,
                    detail: image.detail.rawValue,
                    data: image.data
                )
            }
        }
    }

    private static func resolveEnhancementPrompt(
        template: String,
        rawTranscription: String,
        userMainLanguage: String
    ) -> String {
        let resolved = template
            .replacingOccurrences(of: AppDelegate.rawTranscriptionTemplateVariable, with: rawTranscription)
            .replacingOccurrences(of: AppDelegate.userMainLanguageTemplateVariable, with: userMainLanguage)

        let languageRules = """
        Runtime language preservation rules:
        - User main language: \(userMainLanguage).
        - Use this only for punctuation, formatting, filler-word cleanup, and ambiguity resolution.
        - It is not an output target. Preserve the original language mix and never translate into the user main language.
        """

        return [resolved, languageRules]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}

enum ModelDebugRuntimeValueKey {
    static let rewriteAppContextCapture = "__VOXT_DEBUG_REWRITE_APP_CONTEXT_CAPTURE__"
}

extension Dictionary where Key == String, Value == String {
    var rewriteAppContextCapture: TranscriptionAppContextCapture? {
        guard let raw = self[ModelDebugRuntimeValueKey.rewriteAppContextCapture],
              let data = raw.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode(DebugRewriteAppContextPayload.self, from: data).capture
    }
}

struct DebugRewriteAppContextPayload: Codable {
    let textContext: String
    let attachments: [DebugRewriteAttachmentPayload]

    var capture: TranscriptionAppContextCapture {
        TranscriptionAppContextCapture(
            textContext: textContext,
            attachments: attachments.map(\.attachment)
        )
    }
}

enum DebugRewriteAttachmentPayload: Codable {
    case image(DebugRewriteImageAttachmentPayload)

    enum CodingKeys: String, CodingKey {
        case type
        case image
    }

    enum AttachmentType: String, Codable {
        case image
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(AttachmentType.self, forKey: .type) {
        case .image:
            self = .image(try container.decode(DebugRewriteImageAttachmentPayload.self, forKey: .image))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .image(let payload):
            try container.encode(AttachmentType.image, forKey: .type)
            try container.encode(payload, forKey: .image)
        }
    }

    var attachment: LLMInputAttachment {
        switch self {
        case .image(let payload):
            return .image(payload.attachment)
        }
    }
}

struct DebugRewriteImageAttachmentPayload: Codable {
    let base64Data: String
    let mimeType: String
    let detail: String
    let filename: String

    var attachment: LLMImageAttachment {
        LLMImageAttachment(
            data: Data(base64Encoded: base64Data) ?? Data(),
            mimeType: mimeType,
            detail: LLMImageAttachmentDetail(rawValue: detail) ?? .auto,
            filename: filename
        )
    }
}

enum DebugAudioClipIO {
    static func temporaryClipURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Voxt-Debug-\(UUID().uuidString)")
            .appendingPathExtension("wav")
    }

    static func clip(for fileURL: URL) throws -> DebugAudioClip {
        let file = try AVAudioFile(forReading: fileURL)
        let sampleRate = file.processingFormat.sampleRate
        let duration = sampleRate > 0
            ? Double(file.length) / sampleRate
            : 0
        return DebugAudioClip(
            id: UUID(),
            fileURL: fileURL,
            durationSeconds: duration,
            sampleRate: sampleRate,
            createdAt: Date()
        )
    }

    static func loadMonoSamples(from fileURL: URL) throws -> (samples: [Float], sampleRate: Double) {
        let file = try AVAudioFile(forReading: fileURL)
        let format = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw NSError(
                domain: "Voxt.ModelDebug",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Unable to allocate audio buffer.")]
            )
        }
        try file.read(into: buffer)

        if let mono = AudioLevelMeter.monoSamples(from: buffer) {
            return (mono, format.sampleRate)
        }

        throw NSError(
            domain: "Voxt.ModelDebug",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: AppLocalization.localizedString("Unable to decode audio samples.")]
        )
    }
}
