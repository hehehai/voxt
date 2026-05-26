import SwiftUI
import UniformTypeIdentifiers

extension RemoteProviderConfigurationSheet {
    var isOllamaLLMProvider: Bool {
        llmProviderForPicker == .ollama
    }

    var isOMLXLLMProvider: Bool {
        llmProviderForPicker == .omlx
    }

    var isOpenAILLMProvider: Bool {
        llmProviderForPicker == .openAI
    }

    var isCodexLLMProvider: Bool {
        llmProviderForPicker == .codex
    }

    var isStepFunLLMProvider: Bool {
        llmProviderForPicker == .stepFun
    }

    var supportsStepFunReasoningEffort: Bool {
        isStepFunLLMProvider &&
            resolvedModelValue().trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "step-3.5-flash-2603"
    }

    var usesOpenAIResponsesOptions: Bool {
        isOpenAILLMProvider
    }

    var showsLargeAdvancedProviderSection: Bool {
        llmProviderForPicker != nil && !isCodexLLMProvider
    }

    var apiKeyFieldTitle: String {
        if isCodexLLMProvider {
            return AppLocalization.localizedString("Codex Credentials")
        }
        return (llmProviderForPicker?.apiKeyIsOptional == true)
            ? AppLocalization.localizedString("API Key (Optional)")
            : AppLocalization.localizedString("API Key")
    }

    var apiKeyFieldPlaceholder: String {
        if isCodexLLMProvider {
            return AppLocalization.localizedString("Uses ~/.codex/auth.json")
        }
        return (llmProviderForPicker?.apiKeyIsOptional == true)
            ? AppLocalization.localizedString("Paste API key (optional)")
            : AppLocalization.localizedString("Paste API key")
    }

    var providerModelMenuOptions: [SettingsMenuOption<String>] {
        var options = providerModelOptions.map { SettingsMenuOption(value: $0.id, title: $0.title) }
        if supportsCustomProviderModelSelection {
            options.append(SettingsMenuOption(value: customModelOptionID, title: AppLocalization.localizedString("Custom...")))
        }
        return options
    }

    var providerModelSelectedTitle: String {
        providerModelMenuOptions.first(where: { $0.value == resolvedSelectionForPicker })?.title
            ?? AppLocalization.localizedString("Custom...")
    }

    var supportsCustomProviderModelSelection: Bool {
        RemoteProviderConfigurationPolicy.supportsCustomModelSelection(target: testTarget)
    }

    var shouldShowCustomProviderModelField: Bool {
        supportsCustomProviderModelSelection && resolvedSelectionForPicker == customModelOptionID
    }

    var customProviderModelPlaceholder: String {
        if isOpenAIASRTest {
            return AppLocalization.localizedString("e.g. gpt-4o-transcribe-xxx")
        }
        return AppLocalization.localizedString("e.g. doubao-seed-2-0-pro-260215")
    }

    var ollamaResponseFormatMenuOptions: [SettingsMenuOption<String>] {
        OllamaResponseFormat.allCases.map { option in
            SettingsMenuOption(value: option.rawValue, title: option.title)
        }
    }

    var ollamaResponseFormatSelectedTitle: String {
        OllamaResponseFormat(rawValue: ollamaResponseFormat)?.title
            ?? OllamaResponseFormat.plain.title
    }

    var shouldShowOllamaJSONSchemaField: Bool {
        shouldShowOllamaJSONSchemaField(for: ollamaResponseFormat)
    }

    var ollamaThinkModeMenuOptions: [SettingsMenuOption<String>] {
        OllamaThinkMode.allCases.map { option in
            SettingsMenuOption(value: option.rawValue, title: option.title)
        }
    }

    var ollamaThinkModeSelectedTitle: String {
        OllamaThinkMode(rawValue: ollamaThinkMode)?.title
            ?? OllamaThinkMode.off.title
    }

    var omlxResponseFormatMenuOptions: [SettingsMenuOption<String>] {
        OMLXResponseFormat.allCases.map { option in
            SettingsMenuOption(value: option.rawValue, title: option.title)
        }
    }

    var omlxResponseFormatSelectedTitle: String {
        OMLXResponseFormat(rawValue: omlxResponseFormat)?.title
            ?? OMLXResponseFormat.plain.title
    }

    var shouldShowOMLXJSONSchemaField: Bool {
        shouldShowOMLXJSONSchemaField(for: omlxResponseFormat)
    }

    var openAIReasoningEffortMenuOptions: [SettingsMenuOption<String>] {
        OpenAIReasoningEffort.supportedCases(forModel: resolvedModelValue()).map { option in
            SettingsMenuOption(value: option.rawValue, title: option.title)
        }
    }

    var openAIReasoningEffortSelectedTitle: String {
        OpenAIReasoningEffort(rawValue: openAIReasoningEffort)?.title
            ?? OpenAIReasoningEffort.automatic.title
    }

    var openAITextVerbosityMenuOptions: [SettingsMenuOption<String>] {
        guard OpenAITextVerbosity.supportsModel(resolvedModelValue()) else {
            return [SettingsMenuOption(value: OpenAITextVerbosity.automatic.rawValue, title: OpenAITextVerbosity.automatic.title)]
        }
        return OpenAITextVerbosity.allCases.map { option in
            SettingsMenuOption(value: option.rawValue, title: option.title)
        }
    }

    var openAITextVerbositySelectedTitle: String {
        OpenAITextVerbosity(rawValue: openAITextVerbosity)?.title
            ?? OpenAITextVerbosity.automatic.title
    }

    var generationCapabilities: LLMProviderCapabilities? {
        llmProviderForPicker.map { LLMProviderCapabilityRegistry.capabilities(for: $0) }
    }

    var shouldShowGenerationThinking: Bool {
        if isStepFunLLMProvider {
            return generationThinkingModeMenuOptions.count > 1
        }
        guard let capabilities = generationCapabilities else { return false }
        return capabilities.supportsThinkingToggle ||
            (capabilities.supportsThinkingEffort && (!isStepFunLLMProvider || supportsStepFunReasoningEffort)) ||
            capabilities.supportsThinkingBudget
    }

    var shouldShowGenerationAdvancedControls: Bool {
        guard let capabilities = generationCapabilities else { return false }
        return capabilities.supportsTopK ||
            capabilities.supportsMinP ||
            capabilities.supportsSeed ||
            capabilities.supportsPenalties ||
            capabilities.supportsLogprobs ||
            capabilities.supportsResponseFormat
    }

    var shouldShowGenerationExpertControls: Bool {
        guard let capabilities = generationCapabilities else { return false }
        return capabilities.supportsExtraBody || capabilities.supportsExtraOptions
    }

    var generationThinkingModeMenuOptions: [SettingsMenuOption<String>] {
        if isStepFunLLMProvider {
            var options = [SettingsMenuOption(value: LLMThinkingMode.off.rawValue, title: AppLocalization.localizedString("Off"))]
            if supportsStepFunReasoningEffort {
                options.append(SettingsMenuOption(value: LLMThinkingMode.effort.rawValue, title: AppLocalization.localizedString("Effort")))
            }
            return options
        }
        guard let capabilities = generationCapabilities else { return [] }
        var options = [SettingsMenuOption(value: LLMThinkingMode.providerDefault.rawValue, title: AppLocalization.localizedString("Default"))]
        if capabilities.supportsThinkingToggle {
            options.append(SettingsMenuOption(value: LLMThinkingMode.off.rawValue, title: AppLocalization.localizedString("Off")))
            options.append(SettingsMenuOption(value: LLMThinkingMode.on.rawValue, title: AppLocalization.localizedString("On")))
        }
        if capabilities.supportsThinkingEffort && (!isStepFunLLMProvider || supportsStepFunReasoningEffort) {
            options.append(SettingsMenuOption(value: LLMThinkingMode.effort.rawValue, title: AppLocalization.localizedString("Effort")))
        }
        if capabilities.supportsThinkingBudget {
            options.append(SettingsMenuOption(value: LLMThinkingMode.budget.rawValue, title: AppLocalization.localizedString("Budget")))
        }
        return options
    }

    var generationThinkingModeSelectedTitle: String {
        generationThinkingModeMenuOptions.first(where: { $0.value == generationThinkingMode })?.title
            ?? (isStepFunLLMProvider ? AppLocalization.localizedString("Off") : AppLocalization.localizedString("Default"))
    }

    var sanitizedGenerationThinkingMode: LLMThinkingMode {
        let mode = LLMThinkingMode(rawValue: generationThinkingMode) ?? .providerDefault
        let supportedValues = Set(generationThinkingModeMenuOptions.map(\.value))
        if isStepFunLLMProvider, !supportedValues.contains(mode.rawValue) {
            return .off
        }
        return supportedValues.contains(mode.rawValue) ? mode : .providerDefault
    }

    var generationThinkingEffortMenuOptions: [SettingsMenuOption<String>] {
        let values: [String]
        if usesOpenAIResponsesOptions {
            values = OpenAIReasoningEffort.supportedCases(forModel: resolvedModelValue())
                .filter { $0 != .automatic }
                .map(\.rawValue)
        } else if isStepFunLLMProvider {
            values = supportsStepFunReasoningEffort ? ["low", "high"] : []
        } else if isOllamaLLMProvider {
            values = [
                OllamaThinkMode.low.rawValue,
                OllamaThinkMode.medium.rawValue,
                OllamaThinkMode.high.rawValue
            ]
        } else {
            values = ["none", "minimal", "low", "medium", "high", "xhigh"]
        }
        return values.map { SettingsMenuOption(value: $0, title: generationEffortTitle($0)) }
    }

    var generationThinkingEffortSelectedTitle: String {
        generationThinkingEffortMenuOptions.first(where: { $0.value == generationThinkingEffort })?.title
            ?? AppLocalization.localizedString("Default")
    }

    var generationResponseFormatMenuOptions: [SettingsMenuOption<String>] {
        guard generationCapabilities?.supportsResponseFormat == true else { return [] }
        var formats: [LLMResponseFormat] = [.plain, .json]
        if isOllamaLLMProvider || isOMLXLLMProvider {
            formats.append(.jsonSchema)
        }
        return formats.map { SettingsMenuOption(value: $0.rawValue, title: $0.title) }
    }

    var generationResponseFormatSelectedTitle: String {
        generationResponseFormatMenuOptions.first(where: { $0.value == generationResponseFormat })?.title
            ?? LLMResponseFormat.plain.title
    }

    var shouldShowGenerationJSONSchemaField: Bool {
        LLMResponseFormat(rawValue: generationResponseFormat) == .jsonSchema &&
            (isOllamaLLMProvider || isOMLXLLMProvider)
    }

    var currentConfigurationSnapshot: RemoteProviderConfiguration {
        RemoteProviderConfiguration(
            providerID: configuration.providerID,
            model: resolvedModelValue(),
            endpoint: isDoubaoASRTest ? "" : endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: (isDoubaoASRTest || isCodexLLMProvider) ? "" : apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            appID: appID.trimmingCharacters(in: .whitespacesAndNewlines),
            accessToken: accessToken.trimmingCharacters(in: .whitespacesAndNewlines),
            searchEnabled: (llmProviderForPicker?.supportsHostedSearch == true) ? searchEnabled : false,
            openAIChunkPseudoRealtimeEnabled: isOpenAIASRTest ? openAIChunkPseudoRealtimeEnabled : false,
            openAIReasoningEffort: usesOpenAIResponsesOptions ? openAIReasoningEffortSnapshot() : OpenAIReasoningEffort.automatic.rawValue,
            openAITextVerbosity: usesOpenAIResponsesOptions ? openAITextVerbosity : OpenAITextVerbosity.automatic.rawValue,
            openAIMaxOutputTokens: usesOpenAIResponsesOptions ? parsedOptionalInt(generationMaxOutputTokensText) : nil,
            doubaoDictionaryMode: doubaoDictionaryMode,
            doubaoEnableRequestHotwords: doubaoEnableRequestHotwords,
            doubaoEnableRequestCorrections: doubaoEnableRequestCorrections,
            ollamaResponseFormat: isOllamaLLMProvider ? ollamaResponseFormatSnapshot() : ollamaResponseFormat,
            ollamaJSONSchema: ollamaJSONSchema.trimmingCharacters(in: .whitespacesAndNewlines),
            ollamaThinkMode: isOllamaLLMProvider ? ollamaThinkModeSnapshot() : ollamaThinkMode,
            ollamaKeepAlive: ollamaKeepAlive.trimmingCharacters(in: .whitespacesAndNewlines),
            ollamaLogprobsEnabled: isOllamaLLMProvider ? generationLogprobsEnabled : ollamaLogprobsEnabled,
            ollamaTopLogprobs: isOllamaLLMProvider ? parsedOptionalInt(generationTopLogprobsText) : parsedOllamaTopLogprobsValue(),
            ollamaOptionsJSON: isOllamaLLMProvider ? generationExtraOptionsJSON.trimmingCharacters(in: .whitespacesAndNewlines) : ollamaOptionsJSON.trimmingCharacters(in: .whitespacesAndNewlines),
            omlxResponseFormat: isOMLXLLMProvider ? omlxResponseFormatSnapshot() : omlxResponseFormat,
            omlxJSONSchema: omlxJSONSchema.trimmingCharacters(in: .whitespacesAndNewlines),
            omlxIncludeUsageStreamOptions: omlxIncludeUsageStreamOptions,
            omlxExtraBodyJSON: isOMLXLLMProvider ? generationExtraBodyJSON.trimmingCharacters(in: .whitespacesAndNewlines) : omlxExtraBodyJSON.trimmingCharacters(in: .whitespacesAndNewlines),
            codexAuthFilePath: isCodexLLMProvider ? codexAuthFilePath.trimmingCharacters(in: .whitespacesAndNewlines) : configuration.codexAuthFilePath,
            codexAuthFileBookmark: isCodexLLMProvider ? codexAuthFileBookmark : configuration.codexAuthFileBookmark,
            codexFastModeEnabled: isCodexLLMProvider ? codexFastModeEnabled : configuration.codexFastModeEnabled,
            generationSettings: currentGenerationSettingsSnapshot()
        )
    }

    func currentGenerationSettingsSnapshot() -> LLMGenerationSettings {
        guard let provider = llmProviderForPicker else {
            return configuration.generationSettings
        }
        let capabilities = LLMProviderCapabilityRegistry.capabilities(for: provider)
        var settings = LLMGenerationSettings()
        if isStepFunLLMProvider {
            settings.thinking = .off
        }
        settings.maxOutputTokens = capabilities.supportsMaxOutputTokens ? parsedOptionalInt(generationMaxOutputTokensText) : nil
        settings.temperature = capabilities.supportsTemperature ? parsedOptionalDouble(generationTemperatureText) : nil
        settings.topP = capabilities.supportsTopP ? parsedOptionalDouble(generationTopPText) : nil
        settings.topK = capabilities.supportsTopK ? parsedOptionalInt(generationTopKText) : nil
        settings.minP = capabilities.supportsMinP ? parsedOptionalDouble(generationMinPText) : nil
        settings.seed = capabilities.supportsSeed ? parsedOptionalInt(generationSeedText) : nil
        settings.stop = capabilities.supportsStopSequences ? parsedStopSequences() : []
        if capabilities.supportsPenalties {
            settings.frequencyPenalty = parsedOptionalDouble(generationFrequencyPenaltyText)
            if !isStepFunLLMProvider {
                settings.presencePenalty = parsedOptionalDouble(generationPresencePenaltyText)
                settings.repetitionPenalty = parsedOptionalDouble(generationRepetitionPenaltyText)
            }
        }
        if capabilities.supportsLogprobs {
            settings.logprobs = generationLogprobsEnabled
            settings.topLogprobs = parsedOptionalInt(generationTopLogprobsText)
        }
        if capabilities.supportsResponseFormat {
            settings.responseFormat = LLMResponseFormat(rawValue: generationResponseFormat) ?? .plain
        }
        if shouldShowGenerationThinking {
            settings.thinking = LLMThinkingSettings(
                mode: sanitizedGenerationThinkingMode,
                effort: normalizedOptionalString(generationThinkingEffort),
                budgetTokens: parsedOptionalInt(generationThinkingBudgetText),
                exposeReasoning: false
            )
        }
        if capabilities.supportsExtraBody {
            settings.extraBodyJSON = generationExtraBodyJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if capabilities.supportsExtraOptions {
            settings.extraOptionsJSON = generationExtraOptionsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return settings
    }

    func configureGenerationSettingsState() {
        let provider = llmProviderForPicker
        let settings = provider.map { configuration.effectiveGenerationSettings(provider: $0) } ?? configuration.generationSettings
        generationMaxOutputTokensText = settings.maxOutputTokens.map(String.init) ?? ""
        generationTemperatureText = settings.temperature.map(Self.formatOptionalDouble) ?? ""
        generationTopPText = settings.topP.map(Self.formatOptionalDouble) ?? ""
        generationTopKText = settings.topK.map(String.init) ?? ""
        generationMinPText = settings.minP.map(Self.formatOptionalDouble) ?? ""
        generationSeedText = settings.seed.map(String.init) ?? ""
        generationStopText = settings.stop.joined(separator: "\n")
        generationPresencePenaltyText = settings.presencePenalty.map(Self.formatOptionalDouble) ?? ""
        generationFrequencyPenaltyText = settings.frequencyPenalty.map(Self.formatOptionalDouble) ?? ""
        generationRepetitionPenaltyText = settings.repetitionPenalty.map(Self.formatOptionalDouble) ?? ""
        generationLogprobsEnabled = settings.logprobs
        generationTopLogprobsText = settings.topLogprobs.map(String.init) ?? ""
        generationResponseFormat = settings.responseFormat.rawValue
        generationThinkingMode = settings.thinking.mode.rawValue
        generationThinkingEffort = settings.thinking.effort ?? ""
        generationThinkingBudgetText = settings.thinking.budgetTokens.map(String.init) ?? ""
        generationExtraBodyJSON = settings.extraBodyJSON
        generationExtraOptionsJSON = settings.extraOptionsJSON
    }

    var isDoubaoASRTest: Bool {
        RemoteProviderConfigurationPolicy.isDoubaoASRTest(testTarget)
    }

    var isOpenAIASRTest: Bool {
        RemoteProviderConfigurationPolicy.isOpenAIASRTest(testTarget)
    }

    var customModelOptionID: String {
        RemoteProviderConfigurationPolicy.customModelOptionID
    }

    var asrProviderForSheet: RemoteASRProvider? {
        if case .asr(let provider) = testTarget {
            return provider
        }
        return nil
    }

    var activeProviderNotice: String? {
        switch testTarget {
        case .asr(let provider):
            let active = RemoteASRProvider(rawValue: selectedRemoteASRProviderRaw) ?? .openAIWhisper
            guard active != provider else { return nil }
            return AppLocalization.format(
                "Current active Remote ASR provider is %@. Testing %@ here does not switch the active provider.",
                active.title,
                provider.title
            )
        case .llm(let provider):
            let active = RemoteLLMProvider(rawValue: selectedRemoteLLMProviderRaw) ?? .openAI
            guard active != provider else { return nil }
            return AppLocalization.format(
                "Current active Remote LLM provider is %@. Testing %@ here does not switch the active provider.",
                active.title,
                provider.title
            )
        }
    }

    var providerModelOptions: [RemoteModelOption] {
        if isCodexLLMProvider,
           let dynamicCodexModelOptions,
           !dynamicCodexModelOptions.isEmpty {
            return dynamicCodexModelOptions
        }
        return RemoteProviderConfigurationPolicy.providerModelOptions(
            target: testTarget,
            configuredModel: configuration.model
        )
    }

    var resolvedSelectionForPicker: String {
        let ids = pickerModelOptionIDs
        let trimmedSelected = selectedProviderModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if ids.contains(trimmedSelected) {
            return trimmedSelected
        }
        let trimmedConfigured = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if ids.contains(trimmedConfigured) {
            return trimmedConfigured
        }
        if supportsCustomProviderModelSelection {
            return customModelOptionID
        }
        return ids.first ?? trimmedSelected
    }

    var pickerModelOptionIDs: [String] {
        var ids = providerModelOptions.map(\.id)
        if supportsCustomProviderModelSelection {
            ids.append(customModelOptionID)
        }
        return ids
    }

    var providerModelSelectionBinding: Binding<String> {
        Binding(
            get: { resolvedSelectionForPicker },
            set: {
                handleProviderModelSelectionChange($0)
            }
        )
    }

    var llmProviderForPicker: RemoteLLMProvider? {
        RemoteProviderConfigurationPolicy.llmProvider(for: testTarget)
    }

    var showsSearchSection: Bool {
        llmProviderForPicker?.supportsHostedSearch == true
    }

    func configureModelSelection() {
        let ids = pickerModelOptionIDs
        if supportsCustomProviderModelSelection {
            let trimmedConfigured = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
            selectedProviderModel = ids.contains(trimmedConfigured) ? trimmedConfigured : customModelOptionID
            return
        }
        selectedProviderModel = ids.contains(configuration.model) ? configuration.model : (ids.first ?? configuration.model)
    }

    func handleProviderModelSelectionChange(_ newValue: String) {
        let previousModel = resolvedModelValue()
        selectedProviderModel = newValue
        customModelID = RemoteProviderConfigurationPolicy.nextCustomModelID(
            previousResolvedModel: previousModel,
            newSelection: newValue,
            currentCustomModelID: customModelID,
            supportsCustomSelection: supportsCustomProviderModelSelection
        )

        endpoint = RemoteProviderConfigurationPolicy.remappedEndpointOnModelChange(
            target: testTarget,
            previousModel: previousModel,
            newModel: resolvedModelValue(),
            currentEndpoint: endpoint
        )
    }

    func resolvedModelValue() -> String {
        RemoteProviderConfigurationPolicy.resolvedModelValue(
            target: testTarget,
            resolvedSelection: resolvedSelectionForPicker,
            customModelID: customModelID
        )
    }

    var endpointPresets: [RemoteEndpointPreset] {
        RemoteProviderConfigurationPolicy.endpointPresets(
            target: testTarget,
            resolvedModel: resolvedModelValue()
        )
    }

    var endpointPresetHintText: String? {
        guard !endpointPresets.isEmpty else { return nil }
        guard let provider = llmProviderForPicker else { return nil }

        switch provider {
        case .aliyunBailian:
            return AppLocalization.localizedString("Aliyun API keys are region-specific; use the matching endpoint.")
        case .volcengine:
            return AppLocalization.localizedString("Volcengine models should use the Responses endpoint in the same region as the API key.")
        case .codex:
            return nil
        default:
            return nil
        }
    }

    var endpointFieldPlaceholder: String {
        RemoteProviderConfigurationPolicy.endpointPlaceholder(
            target: testTarget,
            resolvedModel: resolvedModelValue()
        )
    }

    func initialEndpointValue() -> String {
        let trimmedEndpoint = configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEndpoint.isEmpty, isCodexLLMProvider else {
            return configuration.endpoint
        }
        return RemoteLLMRuntimeClient().resolvedLLMEndpoint(
            provider: .codex,
            endpoint: "",
            model: resolvedModelValue()
        )
    }

    var codexAuthFileDisplayPath: String {
        let selectedPath = codexAuthFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selectedPath.isEmpty {
            return selectedPath
        }
        return CodexOAuthCredentialProvider().authFilePath()
    }

    var hasCustomCodexAuthFilePath: Bool {
        !codexAuthFilePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func chooseCodexAuthFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [.json]
        panel.directoryURL = URL(fileURLWithPath: codexAuthFileDisplayPath)
            .deletingLastPathComponent()
        panel.message = AppLocalization.localizedString("Choose Codex auth.json")

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }

        do {
            codexAuthFileBookmark = try SecurityScopedBookmarkSupport.createBookmark(for: selectedURL)
            codexAuthFilePath = selectedURL.path
            codexAuthFileSelectionError = nil
            dynamicCodexModelOptions = nil
            loadCodexModelOptionsIfNeeded()
        } catch {
            codexAuthFileSelectionError = AppLocalization.format(
                "Failed to update Codex auth path: %@",
                error.localizedDescription
            )
        }
    }

    func clearCodexAuthFileSelection() {
        codexAuthFilePath = ""
        codexAuthFileBookmark = nil
        codexAuthFileSelectionError = nil
        dynamicCodexModelOptions = nil
        loadCodexModelOptionsIfNeeded()
    }

    func loadCodexModelOptionsIfNeeded() {
        guard isCodexLLMProvider else { return }
        var snapshot = currentConfigurationSnapshot
        snapshot.endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            let options = await RemoteLLMRuntimeClient().codexModelOptions(configuration: snapshot)
            await MainActor.run {
                dynamicCodexModelOptions = options
                if !pickerModelOptionIDs.contains(selectedProviderModel) {
                    configureModelSelection()
                }
            }
        }
    }

    func testConnection() {
        guard let snapshot = validatedCurrentConfigurationSnapshot() else { return }
        runConnectionTest(for: testTarget, modelForLog: snapshot.model, snapshot: snapshot)
    }

    func saveConfiguration() {
        guard let snapshot = validatedCurrentConfigurationSnapshot() else { return }
        onSave(snapshot)
        dismiss()
    }

    func validatedCurrentConfigurationSnapshot() -> RemoteProviderConfiguration? {
        if let message = validationMessage() {
            testResultIsSuccess = false
            testResultMessage = message
            return nil
        }
        return currentConfigurationSnapshot
    }

    func validationMessage() -> String? {
        if let generationMessage = validationMessageForGenerationSettings() {
            return generationMessage
        }
        if isOllamaLLMProvider {
            return validationMessageForOllamaSettings(
                responseFormat: ollamaResponseFormatSnapshot(),
                jsonSchema: ollamaJSONSchema,
                optionsJSON: generationExtraOptionsJSON,
                logprobsEnabled: generationLogprobsEnabled,
                topLogprobsText: generationTopLogprobsText
            )
        }
        if isOMLXLLMProvider {
            return validationMessageForOMLXSettings(
                responseFormat: omlxResponseFormatSnapshot(),
                jsonSchema: omlxJSONSchema,
                extraBodyJSON: generationExtraBodyJSON
            )
        }
        return nil
    }

    func validationMessageForGenerationSettings() -> String? {
        guard let capabilities = generationCapabilities else { return nil }
        var positiveIntFields = [(String, String)]()
        if capabilities.supportsMaxOutputTokens {
            positiveIntFields.append((generationMaxOutputTokensText, AppLocalization.localizedString("Max Output Tokens")))
        }
        if capabilities.supportsTopK {
            positiveIntFields.append((generationTopKText, AppLocalization.localizedString("Top K")))
        }
        if sanitizedGenerationThinkingMode == .budget {
            positiveIntFields.append((generationThinkingBudgetText, AppLocalization.localizedString("Thinking Budget")))
        }
        if sanitizedGenerationThinkingMode == .budget,
           generationThinkingBudgetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppLocalization.format("%@ must be a positive integer.", AppLocalization.localizedString("Thinking Budget"))
        }
        for (text, fieldName) in positiveIntFields where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0 else {
                return AppLocalization.format("%@ must be a positive integer.", fieldName)
            }
        }
        var integerFields = [(String, String)]()
        if capabilities.supportsSeed {
            integerFields.append((generationSeedText, AppLocalization.localizedString("Seed")))
        }
        if capabilities.supportsLogprobs && generationLogprobsEnabled {
            integerFields.append((generationTopLogprobsText, AppLocalization.localizedString("Top Logprobs")))
        }
        for (text, fieldName) in integerFields where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), value >= 0 else {
                return AppLocalization.format("%@ must be a non-negative integer.", fieldName)
            }
        }
        var doubleFields = [(String, String)]()
        if capabilities.supportsTemperature {
            doubleFields.append((generationTemperatureText, AppLocalization.localizedString("Temperature")))
        }
        if capabilities.supportsTopP {
            doubleFields.append((generationTopPText, AppLocalization.localizedString("Top P")))
        }
        if capabilities.supportsMinP {
            doubleFields.append((generationMinPText, AppLocalization.localizedString("Min P")))
        }
        if capabilities.supportsPenalties {
            doubleFields.append((generationFrequencyPenaltyText, AppLocalization.localizedString("Frequency Penalty")))
            if !isStepFunLLMProvider {
                doubleFields.append((generationPresencePenaltyText, AppLocalization.localizedString("Presence Penalty")))
                doubleFields.append((generationRepetitionPenaltyText, AppLocalization.localizedString("Repetition Penalty")))
            }
        }
        for (text, fieldName) in doubleFields where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) != nil else {
                return AppLocalization.format("%@ must be a number.", fieldName)
            }
        }
        if capabilities.supportsExtraBody,
           let extraBodyMessage = validateJSONObjectField(
               generationExtraBodyJSON,
               fieldName: AppLocalization.localizedString("Extra Body JSON"),
               requiresValue: false
           ) {
            return extraBodyMessage
        }
        if capabilities.supportsExtraOptions,
           let extraOptionsMessage = validateJSONObjectField(
               generationExtraOptionsJSON,
               fieldName: AppLocalization.localizedString("Options JSON"),
               requiresValue: false
           ) {
            return extraOptionsMessage
        }
        return nil
    }

    func validateOllamaTopLogprobs() -> String? {
        validateOllamaTopLogprobs(
            enabled: ollamaLogprobsEnabled,
            text: ollamaTopLogprobsText
        )
    }

    func shouldShowOllamaJSONSchemaField(for responseFormat: String) -> Bool {
        OllamaResponseFormat(rawValue: responseFormat) == .jsonSchema
    }

    func shouldShowOMLXJSONSchemaField(for responseFormat: String) -> Bool {
        OMLXResponseFormat(rawValue: responseFormat) == .jsonSchema
    }

    func validationMessageForOllamaSettings(
        responseFormat: String,
        jsonSchema: String,
        optionsJSON: String,
        logprobsEnabled: Bool,
        topLogprobsText: String
    ) -> String? {
        if let topLogprobsMessage = validateOllamaTopLogprobs(
            enabled: logprobsEnabled,
            text: topLogprobsText
        ) {
            return topLogprobsMessage
        }
        if let optionsMessage = validateJSONObjectField(
            optionsJSON,
            fieldName: AppLocalization.localizedString("Options JSON"),
            requiresValue: false
        ) {
            return optionsMessage
        }
        if shouldShowOllamaJSONSchemaField(for: responseFormat),
           let schemaMessage = validateJSONObjectField(
               jsonSchema,
               fieldName: AppLocalization.localizedString("JSON Schema"),
               requiresValue: true
           ) {
            return schemaMessage
        }
        return nil
    }

    func validationMessageForOMLXSettings(
        responseFormat: String,
        jsonSchema: String,
        extraBodyJSON: String
    ) -> String? {
        if let extraBodyMessage = validateJSONObjectField(
            extraBodyJSON,
            fieldName: AppLocalization.localizedString("Extra Body JSON"),
            requiresValue: false
        ) {
            return extraBodyMessage
        }
        if shouldShowOMLXJSONSchemaField(for: responseFormat),
           let schemaMessage = validateJSONObjectField(
               jsonSchema,
               fieldName: AppLocalization.localizedString("JSON Schema"),
               requiresValue: true
           ) {
            return schemaMessage
        }
        return nil
    }

    func validateOllamaTopLogprobs(enabled: Bool, text: String) -> String? {
        guard enabled else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Int(trimmed), value >= 0 else {
            return AppLocalization.localizedString("Top Logprobs must be a non-negative integer.")
        }
        return nil
    }

    func validationMessageForOpenAISettings(maxOutputTokensText: String) -> String? {
        let trimmed = maxOutputTokensText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Int(trimmed), value > 0 else {
            return AppLocalization.localizedString("Max Output Tokens must be a positive integer.")
        }
        return nil
    }

    func validateJSONObjectField(_ value: String, fieldName: String, requiresValue: Bool) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return requiresValue ? AppLocalization.format("%@ must be a JSON object.", fieldName) : nil
        }
        guard let data = trimmed.data(using: .utf8) else {
            return AppLocalization.format("%@ must be valid JSON.", fieldName)
        }
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            object is [String: Any]
        else {
            return AppLocalization.format("%@ must be a JSON object.", fieldName)
        }
        return nil
    }

    func parsedOllamaTopLogprobsValue() -> Int? {
        let trimmed = ollamaTopLogprobsText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }

    func parsedOpenAIMaxOutputTokensValue() -> Int? {
        let trimmed = openAIMaxOutputTokensText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }

    func parsedOptionalInt(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Int(trimmed)
    }

    func parsedOptionalDouble(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    func parsedStopSequences() -> [String] {
        generationStopText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func normalizedOptionalString(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func openAIReasoningEffortSnapshot() -> String {
        guard LLMThinkingMode(rawValue: generationThinkingMode) == .effort,
              let effort = normalizedOptionalString(generationThinkingEffort),
              OpenAIReasoningEffort(rawValue: effort) != nil
        else {
            return OpenAIReasoningEffort.automatic.rawValue
        }
        return effort
    }

    func ollamaResponseFormatSnapshot() -> String {
        switch LLMResponseFormat(rawValue: generationResponseFormat) {
        case .json:
            return OllamaResponseFormat.json.rawValue
        case .jsonSchema:
            return OllamaResponseFormat.jsonSchema.rawValue
        case .plain, nil:
            return OllamaResponseFormat.plain.rawValue
        }
    }

    func omlxResponseFormatSnapshot() -> String {
        switch LLMResponseFormat(rawValue: generationResponseFormat) {
        case .jsonSchema:
            return OMLXResponseFormat.jsonSchema.rawValue
        case .plain, .json, nil:
            return OMLXResponseFormat.plain.rawValue
        }
    }

    func ollamaThinkModeSnapshot() -> String {
        switch LLMThinkingMode(rawValue: generationThinkingMode) {
        case .off:
            return OllamaThinkMode.off.rawValue
        case .on, .budget:
            return OllamaThinkMode.on.rawValue
        case .effort:
            switch generationThinkingEffort {
            case OllamaThinkMode.low.rawValue:
                return OllamaThinkMode.low.rawValue
            case OllamaThinkMode.medium.rawValue:
                return OllamaThinkMode.medium.rawValue
            case OllamaThinkMode.high.rawValue:
                return OllamaThinkMode.high.rawValue
            default:
                return OllamaThinkMode.on.rawValue
            }
        case .providerDefault, nil:
            return OllamaThinkMode.off.rawValue
        }
    }

    func generationEffortTitle(_ value: String) -> String {
        if let openAIEffort = OpenAIReasoningEffort(rawValue: value) {
            return openAIEffort.title
        }
        switch value {
        case "none":
            return AppLocalization.localizedString("None")
        case "minimal":
            return AppLocalization.localizedString("Minimal")
        case "low":
            return AppLocalization.localizedString("Low")
        case "medium":
            return AppLocalization.localizedString("Medium")
        case "high":
            return AppLocalization.localizedString("High")
        case "xhigh":
            return AppLocalization.localizedString("Extra High")
        default:
            return value
        }
    }

    nonisolated static func formatOptionalDouble(_ value: Double) -> String {
        String(format: "%g", value)
    }

    func runConnectionTest(
        for target: RemoteProviderTestTarget,
        modelForLog: String,
        snapshot: RemoteProviderConfiguration
    ) {
        isTestingConnection = true
        testResultMessage = nil
        testResultIsSuccess = false
        VoxtLog.info(
            "Remote provider test started. target=\(RemoteProviderConfigurationPolicy.testTargetLogName(target)), provider=\(configuration.providerID), model=\(modelForLog), endpoint=\(sanitizedEndpointForLog(snapshot.endpoint)), proxyMode=\(VoxtNetworkSession.modeDescription), hasAPIKey=\(!snapshot.apiKey.isEmpty), hasAppID=\(!snapshot.appID.isEmpty), hasAccessToken=\(!snapshot.accessToken.isEmpty)"
        )

        Task {
            do {
                let tester = RemoteProviderConnectivityTester(testTarget: target)
                let message = try await tester.run(configuration: snapshot)
                await MainActor.run {
                    isTestingConnection = false
                    testResultIsSuccess = true
                    testResultMessage = message
                    VoxtLog.info(
                        "Remote provider test succeeded. target=\(RemoteProviderConfigurationPolicy.testTargetLogName(target)), provider=\(configuration.providerID), model=\(modelForLog), message=\(message)"
                    )
                }
            } catch {
                await MainActor.run {
                    isTestingConnection = false
                    testResultIsSuccess = false
                    let message = VoxtNetworkSession.directModeConflictMessage(for: error) ?? error.localizedDescription
                    testResultMessage = message
                    VoxtLog.warning(
                        "Remote provider test failed. target=\(RemoteProviderConfigurationPolicy.testTargetLogName(target)), provider=\(configuration.providerID), model=\(modelForLog), error=\(message)"
                    )
                }
            }
        }
    }

    func sanitizedEndpointForLog(_ endpoint: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "<default>" : trimmed
    }
}
