import Foundation

enum RemoteASRMeetingConfiguration {
    static let setupPath = "Settings > Model > Remote ASR"

    static func requiresDedicatedMeetingModel(
        _ provider: RemoteASRProvider,
        configuration: RemoteProviderConfiguration? = nil
    ) -> Bool {
        switch provider {
        case .doubaoASR, .aliyunBailianASR:
            guard let configuration else { return true }
            return !RemoteASRRealtimeSupport.usesRealtimeMeetingProfile(
                provider: provider,
                configuration: configuration
            )
        case .openAIWhisper, .glmASR:
            return false
        }
    }

    static func suggestedMeetingModel(for provider: RemoteASRProvider) -> String {
        switch provider {
        case .doubaoASR:
            return DoubaoASRConfiguration.meetingModelTurbo
        case .aliyunBailianASR:
            return AliyunMeetingASRConfiguration.defaultMeetingModel
        case .openAIWhisper, .glmASR:
            return provider.suggestedModel
        }
    }

    static func meetingModelOptions(for provider: RemoteASRProvider) -> [RemoteModelOption] {
        switch provider {
        case .doubaoASR:
            return [
                RemoteModelOption(id: DoubaoASRConfiguration.meetingModelTurbo, title: "Doubao Flash ASR Turbo")
            ]
        case .aliyunBailianASR:
            return AliyunMeetingASRConfiguration.meetingModelOptions()
        case .openAIWhisper, .glmASR:
            return []
        }
    }

    static func hasValidMeetingModel(
        provider: RemoteASRProvider,
        configuration: RemoteProviderConfiguration
    ) -> Bool {
        guard requiresDedicatedMeetingModel(provider, configuration: configuration) else { return true }
        guard configuration.hasUsableMeetingModel else { return false }
        switch provider {
        case .aliyunBailianASR:
            return AliyunMeetingASRConfiguration.validationError(
                model: configuration.meetingModel,
                endpoint: configuration.endpoint
            ) == nil
        case .doubaoASR, .openAIWhisper, .glmASR:
            return true
        }
    }

    static func resolvedMeetingConfiguration(
        provider: RemoteASRProvider,
        configuration: RemoteProviderConfiguration
    ) -> RemoteProviderConfiguration {
        guard requiresDedicatedMeetingModel(provider, configuration: configuration) else { return configuration }
        var resolved = configuration
        let trimmedModel = configuration.meetingModel.trimmingCharacters(in: .whitespacesAndNewlines)
        switch provider {
        case .doubaoASR:
            resolved.model = DoubaoASRConfiguration.canonicalMeetingModel(trimmedModel)
        case .aliyunBailianASR:
            resolved.model = AliyunMeetingASRConfiguration.normalizedMeetingModel(trimmedModel)
        case .openAIWhisper, .glmASR:
            resolved.model = trimmedModel.isEmpty ? suggestedMeetingModel(for: provider) : trimmedModel
        }
        return resolved
    }

    static func missingMeetingModelStatus(
        provider: RemoteASRProvider
    ) -> String {
        AppLocalization.format(
            "Meeting ASR not configured. Open %@ > %@ > Meeting ASR.",
            setupPath,
            provider.title
        )
    }

    static func configuredMeetingModelStatus(
        _ model: String
    ) -> String {
        AppLocalization.format("Meeting ASR: %@", model)
    }

    static func startBlockedMessage(for provider: RemoteASRProvider) -> String {
        AppLocalization.format(
            "Meeting ASR is not configured for %@. Open %@ > %@ > Meeting ASR.",
            provider.title,
            setupPath,
            provider.title
        )
    }

    static func startBlockedMessage(
        for provider: RemoteASRProvider,
        configuration: RemoteProviderConfiguration
    ) -> String {
        if !configuration.hasUsableMeetingModel {
            return startBlockedMessage(for: provider)
        }
        if provider == .aliyunBailianASR,
           let validationError = AliyunMeetingASRConfiguration.validationError(
            model: configuration.meetingModel,
            endpoint: configuration.endpoint
           ) {
            return validationError
        }
        return startBlockedMessage(for: provider)
    }
}
