// MeetingCompatibilityAliases.swift
// Provides Meeting Compatibility Aliases for meeting session behavior.

import Foundation

typealias MeetingSpeaker = TranscriptSpeaker
typealias MeetingTranscriptSegment = TranscriptSegment
typealias MeetingTranscriptFormatter = TranscriptFormatter
typealias MeetingTranscriptEvent = TranscriptSegmentEvent
typealias MeetingTranscriptAssemblyResult = TranscriptAssemblyResult
typealias MeetingTranscriptAssembler = TranscriptAssembler

typealias MeetingSummaryChatRole = TranscriptSummaryChatRole
typealias MeetingSummaryChatMessage = TranscriptSummaryChatMessage
typealias MeetingSummarySettingsSnapshot = TranscriptSummarySettingsSnapshot
typealias MeetingSummarySnapshot = TranscriptSummarySnapshot
typealias MeetingSummaryProviderStatus = TranscriptSummaryProviderStatus
typealias MeetingSummaryModelOption = TranscriptSummaryModelOption
typealias MeetingSummarySupport = TranscriptSummarySupport

typealias AliyunMeetingASRClient = AliyunRemoteASRClient
typealias AliyunMeetingASRConfiguration = AliyunRemoteASRConfiguration

enum RemoteASRMeetingConfiguration {
    static let setupPath = "Settings > Model > Remote ASR"

    static func requiresDedicatedMeetingModel(
        _ provider: RemoteASRProvider,
        configuration: RemoteProviderConfiguration? = nil
    ) -> Bool {
        false
    }

    static func suggestedMeetingModel(for provider: RemoteASRProvider) -> String {
        provider.suggestedModel
    }

    static func meetingModelOptions(for provider: RemoteASRProvider) -> [RemoteModelOption] {
        provider.modelOptions
    }

    static func hasValidMeetingModel(
        provider: RemoteASRProvider,
        configuration: RemoteProviderConfiguration
    ) -> Bool {
        configuration.isConfigured
    }

    static func resolvedMeetingConfiguration(
        provider _: RemoteASRProvider,
        configuration: RemoteProviderConfiguration
    ) -> RemoteProviderConfiguration {
        configuration
    }

    static func missingMeetingModelStatus(provider: RemoteASRProvider) -> String {
        AppLocalization.format(
            "Remote ASR is not configured for %@. Open %@ > %@.",
            provider.title,
            setupPath,
            provider.title
        )
    }

    static func configuredMeetingModelStatus(_ model: String) -> String {
        AppLocalization.format("Remote ASR: %@", model)
    }

    static func startBlockedMessage(for provider: RemoteASRProvider) -> String {
        AppLocalization.format(
            "Remote ASR is not configured for %@. Open %@ > %@.",
            provider.title,
            setupPath,
            provider.title
        )
    }

    static func startBlockedMessage(
        for provider: RemoteASRProvider,
        configuration _: RemoteProviderConfiguration
    ) -> String {
        startBlockedMessage(for: provider)
    }
}

extension MLXTranscriber {
    func transcribeMeetingChunk(samples: [Float], sampleRate: Double) async -> String? {
        do {
            return try await transcribeBufferedChunk(samples: samples, sampleRate: sampleRate)
        } catch {
            VoxtLog.error("Meeting MLX chunk transcription failed: \(error.localizedDescription)")
            return nil
        }
    }
}

extension RemoteASRTranscriber {
    struct MeetingConfiguration {
        let provider: RemoteASRProvider
        let configuration: RemoteProviderConfiguration
    }

    func currentMeetingConfiguration() -> MeetingConfiguration {
        let rawProvider = UserDefaults.standard.string(forKey: AppPreferenceKey.remoteASRSelectedProvider) ?? ""
        let provider = RemoteASRProvider(rawValue: rawProvider) ?? .openAIWhisper
        let rawConfigurations = UserDefaults.standard.string(forKey: AppPreferenceKey.remoteASRProviderConfigurations) ?? ""
        let configurations = RemoteModelConfigurationStore.loadConfigurations(from: rawConfigurations)
        let configuration = RemoteModelConfigurationStore.resolvedASRConfiguration(
            provider: provider,
            stored: configurations
        )
        return MeetingConfiguration(provider: provider, configuration: configuration)
    }

    func transcribeMeetingAudioFile(_ fileURL: URL) async throws -> String {
        let meetingConfiguration = currentMeetingConfiguration()
        return try await transcribeDebugAudioFile(
            fileURL,
            provider: meetingConfiguration.provider,
            configuration: meetingConfiguration.configuration
        )
    }
}
