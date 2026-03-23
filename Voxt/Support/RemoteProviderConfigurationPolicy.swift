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
                    RemoteEndpointPreset(id: "aliyun-asr-qwen-cn-beijing", title: "Qwen Realtime WS · Beijing", url: "wss://dashscope.aliyuncs.com/api-ws/v1/realtime"),
                    RemoteEndpointPreset(id: "aliyun-asr-qwen-ap-southeast-1", title: "Qwen Realtime WS · Singapore", url: "wss://dashscope-intl.aliyuncs.com/api-ws/v1/realtime"),
                    RemoteEndpointPreset(id: "aliyun-asr-qwen-us-east-1", title: "Qwen Realtime WS · US (Virginia)", url: "wss://dashscope-us.aliyuncs.com/api-ws/v1/realtime")
                ]
            }
            return [
                RemoteEndpointPreset(id: "aliyun-asr-fun-cn-beijing", title: "Realtime WS · Beijing", url: "wss://dashscope.aliyuncs.com/api-ws/v1/inference"),
                RemoteEndpointPreset(id: "aliyun-asr-fun-ap-southeast-1", title: "Realtime WS · Singapore", url: "wss://dashscope-intl.aliyuncs.com/api-ws/v1/inference"),
                RemoteEndpointPreset(id: "aliyun-asr-fun-us-east-1", title: "Realtime WS · US (Virginia)", url: "wss://dashscope-us.aliyuncs.com/api-ws/v1/inference")
            ]
        case .meetingASR(let provider):
            guard provider == .aliyunBailianASR else { return [] }
            return AliyunMeetingASRConfiguration.endpointPresets(for: resolvedModel)
        case .llm(let provider):
            guard provider == .aliyunBailian else { return [] }
            return [
                RemoteEndpointPreset(id: "aliyun-llm-cn-beijing", title: "Beijing", url: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"),
                RemoteEndpointPreset(id: "aliyun-llm-ap-southeast-1", title: "Singapore", url: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions"),
                RemoteEndpointPreset(id: "aliyun-llm-us-east-1", title: "US (Virginia)", url: "https://dashscope-us.aliyuncs.com/compatible-mode/v1/chat/completions")
            ]
        }
    }

    private static func isAliyunQwenRealtimeModel(_ model: String) -> Bool {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("qwen3-asr-flash-realtime")
    }
}
