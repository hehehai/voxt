import Foundation

struct RemoteEndpointPreset: Identifiable, Hashable {
    let id: String
    let title: String
    let url: String
}

enum RemoteProviderConfigurationPolicy {
    static let customModelOptionID = "__voxt_custom_model__"

    static func llmProvider(for target: RemoteProviderTestTarget) -> RemoteLLMProvider? {
        if case .llm(let provider) = target {
            return provider
        }
        return nil
    }

    static func isDoubaoASRTest(_ target: RemoteProviderTestTarget) -> Bool {
        if case .asr(let provider) = target {
            return provider == .doubaoASR
        }
        if case .meetingASR(let provider) = target {
            return provider == .doubaoASR
        }
        return false
    }

    static func isOpenAIASRTest(_ target: RemoteProviderTestTarget) -> Bool {
        if case .asr(let provider) = target {
            return provider == .openAIWhisper
        }
        if case .meetingASR(let provider) = target {
            return provider == .openAIWhisper
        }
        return false
    }

    static func testTargetLogName(_ target: RemoteProviderTestTarget) -> String {
        switch target {
        case .asr:
            return "asr"
        case .meetingASR:
            return "meeting-asr"
        case .llm:
            return "llm"
        }
    }

    static func providerModelOptions(target: RemoteProviderTestTarget, configuredModel: String) -> [RemoteModelOption] {
        switch target {
        case .asr(let provider):
            return provider.modelOptions
        case .meetingASR(let provider):
            return RemoteASRMeetingConfiguration.meetingModelOptions(for: provider)
        case .llm(let provider):
            return provider.modelOptions
        }
    }

    static func pickerModelOptionIDs(target: RemoteProviderTestTarget, configuredModel: String) -> [String] {
        if let llmProvider = llmProvider(for: target) {
            return (llmProvider.latestModelOptions + llmProvider.basicModelOptions + llmProvider.advancedModelOptions).map(\.id) + [customModelOptionID]
        }
        return providerModelOptions(target: target, configuredModel: configuredModel).map(\.id)
    }

    static func resolvedSelection(
        target: RemoteProviderTestTarget,
        selectedProviderModel: String,
        configuredModel: String
    ) -> String {
        let ids = pickerModelOptionIDs(target: target, configuredModel: configuredModel)
        let trimmedSelected = selectedProviderModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if ids.contains(trimmedSelected) {
            return trimmedSelected
        }
        let trimmedConfigured = configuredModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if ids.contains(trimmedConfigured) {
            return trimmedConfigured
        }
        if llmProvider(for: target) != nil {
            return customModelOptionID
        }
        return ids.first ?? trimmedSelected
    }

    static func initialSelection(target: RemoteProviderTestTarget, configuredModel: String) -> String {
        let ids = pickerModelOptionIDs(target: target, configuredModel: configuredModel)
        if llmProvider(for: target) != nil {
            let trimmedConfigured = configuredModel.trimmingCharacters(in: .whitespacesAndNewlines)
            return ids.contains(trimmedConfigured) ? trimmedConfigured : customModelOptionID
        }
        return ids.contains(configuredModel) ? configuredModel : (ids.first ?? configuredModel)
    }

    static func resolvedModelValue(
        target: RemoteProviderTestTarget,
        resolvedSelection: String,
        customModelID: String
    ) -> String {
        if let llmProvider = llmProvider(for: target), resolvedSelection == customModelOptionID {
            let trimmedCustom = customModelID.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedCustom.isEmpty ? llmProvider.suggestedModel : trimmedCustom
        }
        return resolvedSelection
    }

    static func endpointPresets(target: RemoteProviderTestTarget, resolvedModel: String) -> [RemoteEndpointPreset] {
        switch target {
        case .asr(let provider):
            guard provider == .aliyunBailianASR else { return [] }
            if isAliyunQwenRealtimeModel(resolvedModel) {
                return [
                    RemoteEndpointPreset(id: "aliyun-asr-qwen-cn-beijing", title: AppLocalization.localizedString("Qwen Realtime WS · Beijing"), url: "wss://dashscope.aliyuncs.com/api-ws/v1/realtime"),
                    RemoteEndpointPreset(id: "aliyun-asr-qwen-ap-southeast-1", title: AppLocalization.localizedString("Qwen Realtime WS · Singapore"), url: "wss://dashscope-intl.aliyuncs.com/api-ws/v1/realtime"),
                    RemoteEndpointPreset(id: "aliyun-asr-qwen-us-east-1", title: AppLocalization.localizedString("Qwen Realtime WS · US (Virginia)"), url: "wss://dashscope-us.aliyuncs.com/api-ws/v1/realtime")
                ]
            }
            return [
                RemoteEndpointPreset(id: "aliyun-asr-fun-cn-beijing", title: AppLocalization.localizedString("Realtime WS · Beijing"), url: "wss://dashscope.aliyuncs.com/api-ws/v1/inference"),
                RemoteEndpointPreset(id: "aliyun-asr-fun-ap-southeast-1", title: AppLocalization.localizedString("Realtime WS · Singapore"), url: "wss://dashscope-intl.aliyuncs.com/api-ws/v1/inference"),
                RemoteEndpointPreset(id: "aliyun-asr-fun-us-east-1", title: AppLocalization.localizedString("Realtime WS · US (Virginia)"), url: "wss://dashscope-us.aliyuncs.com/api-ws/v1/inference")
            ]
        case .meetingASR(let provider):
            guard provider == .aliyunBailianASR else { return [] }
            return AliyunMeetingASRConfiguration.endpointPresets(for: resolvedModel)
        case .llm(let provider):
            switch provider {
            case .aliyunBailian:
                return [
                    RemoteEndpointPreset(id: "aliyun-llm-cn-beijing", title: AppLocalization.localizedString("Beijing"), url: "https://dashscope.aliyuncs.com/compatible-mode/v1/responses"),
                    RemoteEndpointPreset(id: "aliyun-llm-ap-southeast-1", title: AppLocalization.localizedString("Singapore"), url: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/responses"),
                    RemoteEndpointPreset(id: "aliyun-llm-us-east-1", title: AppLocalization.localizedString("US (Virginia)"), url: "https://dashscope-us.aliyuncs.com/compatible-mode/v1/responses")
                ]
            case .volcengine:
                return [
                    RemoteEndpointPreset(id: "volcengine-llm-cn-beijing", title: AppLocalization.localizedString("Beijing"), url: "https://ark.cn-beijing.volces.com/api/v3/responses")
                ]
            default:
                return []
            }
        }
    }

    static func remappedEndpointOnModelChange(
        target: RemoteProviderTestTarget,
        previousModel: String,
        newModel: String,
        currentEndpoint: String
    ) -> String {
        let trimmedEndpoint = currentEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let oldPresets = endpointPresets(target: target, resolvedModel: previousModel)
        let newPresets = endpointPresets(target: target, resolvedModel: newModel)

        guard !newPresets.isEmpty else { return currentEndpoint }
        if trimmedEndpoint.isEmpty {
            return newPresets.first?.url ?? currentEndpoint
        }

        let oldPresetURLs = Set(oldPresets.map(\.url))
        let newPresetURLs = Set(newPresets.map(\.url))
        if newPresetURLs.contains(trimmedEndpoint) {
            return trimmedEndpoint
        }
        guard oldPresetURLs.contains(trimmedEndpoint) || hostMatchesAnyPreset(trimmedEndpoint, presets: oldPresets) else {
            return currentEndpoint
        }

        if let remapped = newPresets.first(where: { preset in
            presetHost(preset.url) == presetHost(trimmedEndpoint)
        }) {
            return remapped.url
        }
        return newPresets.first?.url ?? currentEndpoint
    }

    private static func isAliyunQwenRealtimeModel(_ model: String) -> Bool {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("qwen3-asr-flash-realtime")
    }

    private static func hostMatchesAnyPreset(_ endpoint: String, presets: [RemoteEndpointPreset]) -> Bool {
        let host = presetHost(endpoint)
        return presets.contains { preset in
            presetHost(preset.url) == host
        }
    }

    private static func presetHost(_ value: String) -> String? {
        URL(string: value)?.host?.lowercased()
    }
}
