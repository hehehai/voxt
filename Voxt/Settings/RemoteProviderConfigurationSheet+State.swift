import SwiftUI

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

    var showsLargeAdvancedProviderSection: Bool {
        isOpenAILLMProvider || isOllamaLLMProvider || isOMLXLLMProvider
    }

    var apiKeyFieldTitle: String {
        (llmProviderForPicker?.apiKeyIsOptional == true)
            ? AppLocalization.localizedString("API Key (Optional)")
            : AppLocalization.localizedString("API Key")
    }

    var apiKeyFieldPlaceholder: String {
        (llmProviderForPicker?.apiKeyIsOptional == true)
            ? AppLocalization.localizedString("Paste API key (optional)")
            : AppLocalization.localizedString("Paste API key")
    }

    var providerModelMenuOptions: [SettingsMenuOption<String>] {
        if let llmProvider = llmProviderForPicker {
            var options = (
                llmProvider.latestModelOptions +
                llmProvider.basicModelOptions +
                llmProvider.advancedModelOptions
            ).map { SettingsMenuOption(value: $0.id, title: $0.title) }
            if supportsCustomProviderModelSelection {
                options.append(SettingsMenuOption(value: customModelOptionID, title: AppLocalization.localizedString("Custom...")))
            }
            return options
        }
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

    var currentConfigurationSnapshot: RemoteProviderConfiguration {
        RemoteProviderConfiguration(
            providerID: configuration.providerID,
            model: resolvedModelValue(),
            endpoint: isDoubaoASRTest ? "" : endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: isDoubaoASRTest ? "" : apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            appID: appID.trimmingCharacters(in: .whitespacesAndNewlines),
            accessToken: accessToken.trimmingCharacters(in: .whitespacesAndNewlines),
            searchEnabled: (llmProviderForPicker?.supportsHostedSearch == true) ? searchEnabled : false,
            openAIChunkPseudoRealtimeEnabled: isOpenAIASRTest ? openAIChunkPseudoRealtimeEnabled : false,
            openAIReasoningEffort: isOpenAILLMProvider ? openAIReasoningEffort : OpenAIReasoningEffort.automatic.rawValue,
            openAITextVerbosity: isOpenAILLMProvider ? openAITextVerbosity : OpenAITextVerbosity.automatic.rawValue,
            openAIMaxOutputTokens: isOpenAILLMProvider ? parsedOpenAIMaxOutputTokensValue() : nil,
            doubaoDictionaryMode: doubaoDictionaryMode,
            doubaoEnableRequestHotwords: doubaoEnableRequestHotwords,
            doubaoEnableRequestCorrections: doubaoEnableRequestCorrections,
            ollamaResponseFormat: ollamaResponseFormat,
            ollamaJSONSchema: ollamaJSONSchema.trimmingCharacters(in: .whitespacesAndNewlines),
            ollamaThinkMode: ollamaThinkMode,
            ollamaKeepAlive: ollamaKeepAlive.trimmingCharacters(in: .whitespacesAndNewlines),
            ollamaLogprobsEnabled: ollamaLogprobsEnabled,
            ollamaTopLogprobs: parsedOllamaTopLogprobsValue(),
            ollamaOptionsJSON: ollamaOptionsJSON.trimmingCharacters(in: .whitespacesAndNewlines),
            omlxResponseFormat: omlxResponseFormat,
            omlxJSONSchema: omlxJSONSchema.trimmingCharacters(in: .whitespacesAndNewlines),
            omlxIncludeUsageStreamOptions: omlxIncludeUsageStreamOptions,
            omlxExtraBodyJSON: omlxExtraBodyJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        )
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
        RemoteProviderConfigurationPolicy.providerModelOptions(
            target: testTarget,
            configuredModel: configuration.model
        )
    }

    var resolvedSelectionForPicker: String {
        RemoteProviderConfigurationPolicy.resolvedSelection(
            target: testTarget,
            selectedProviderModel: selectedProviderModel,
            configuredModel: configuration.model
        )
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
        selectedProviderModel = RemoteProviderConfigurationPolicy.initialSelection(
            target: testTarget,
            configuredModel: configuration.model
        )
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
        if isOllamaLLMProvider {
            return validationMessageForOllamaSettings(
                responseFormat: ollamaResponseFormat,
                jsonSchema: ollamaJSONSchema,
                optionsJSON: ollamaOptionsJSON,
                logprobsEnabled: ollamaLogprobsEnabled,
                topLogprobsText: ollamaTopLogprobsText
            )
        }
        if isOMLXLLMProvider {
            return validationMessageForOMLXSettings(
                responseFormat: omlxResponseFormat,
                jsonSchema: omlxJSONSchema,
                extraBodyJSON: omlxExtraBodyJSON
            )
        }
        if isOpenAILLMProvider {
            return validationMessageForOpenAISettings(
                maxOutputTokensText: openAIMaxOutputTokensText
            )
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
