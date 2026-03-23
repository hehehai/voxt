import Foundation
import AppKit
import CoreAudio

extension AppDelegate {
    private var defaults: UserDefaults {
        .standard
    }

    var selectedInputDeviceID: AudioDeviceID? {
        let raw = defaults.integer(forKey: AppPreferenceKey.selectedInputDeviceID)
        return raw > 0 ? AudioDeviceID(raw) : nil
    }

    var interactionSoundsEnabled: Bool {
        defaults.bool(forKey: AppPreferenceKey.interactionSoundsEnabled)
    }

    var muteSystemAudioWhileRecording: Bool {
        defaults.bool(forKey: AppPreferenceKey.muteSystemAudioWhileRecording)
    }

    var meetingNotesBetaEnabled: Bool {
        defaults.bool(forKey: AppPreferenceKey.meetingNotesBetaEnabled)
    }

    var overlayPosition: OverlayPosition {
        enumValue(forKey: AppPreferenceKey.overlayPosition, default: .bottom)
    }

    var autoCopyWhenNoFocusedInput: Bool {
        defaults.bool(forKey: AppPreferenceKey.autoCopyWhenNoFocusedInput)
    }

    var alwaysShowRewriteAnswerCard: Bool {
        defaults.bool(forKey: AppPreferenceKey.alwaysShowRewriteAnswerCard)
    }

    var translationTargetLanguage: TranslationTargetLanguage {
        enumValue(forKey: AppPreferenceKey.translationTargetLanguage, default: .english)
    }

    var meetingRealtimeTranslationTargetLanguage: TranslationTargetLanguage? {
        enumValue(
            forKey: AppPreferenceKey.meetingRealtimeTranslationTargetLanguage,
            default: Optional<TranslationTargetLanguage>.none
        )
    }

    var userMainLanguageCodes: [String] {
        UserMainLanguageOption.storedSelection(
            from: defaults.string(forKey: AppPreferenceKey.userMainLanguageCodes)
        )
    }

    var userMainLanguage: UserMainLanguageOption {
        let selectedCodes = userMainLanguageCodes
        if let firstCode = selectedCodes.first,
           let option = UserMainLanguageOption.option(for: firstCode) {
            return option
        }
        return UserMainLanguageOption.fallbackOption()
    }

    var userMainLanguagePromptValue: String {
        userMainLanguage.promptName
    }

    var translateSelectedTextOnTranslationHotkey: Bool {
        defaults.bool(forKey: AppPreferenceKey.translateSelectedTextOnTranslationHotkey)
    }

    var voiceEndCommandEnabled: Bool {
        defaults.bool(forKey: AppPreferenceKey.voiceEndCommandEnabled)
    }

    var voiceEndCommandPreset: VoiceEndCommandPreset {
        if let preset = enumValue(forKey: AppPreferenceKey.voiceEndCommandPreset, default: Optional<VoiceEndCommandPreset>.none) {
            return preset
        }

        let legacyCustomValue = trimmedStringValue(forKey: AppPreferenceKey.voiceEndCommandText)
        return legacyCustomValue.isEmpty ? .over : .custom
    }

    var voiceEndCommandText: String {
        if let presetCommand = voiceEndCommandPreset.resolvedCommand {
            return presetCommand
        }
        return trimmedStringValue(forKey: AppPreferenceKey.voiceEndCommandText)
    }

    var translationSystemPrompt: String {
        let value = defaults.string(forKey: AppPreferenceKey.translationSystemPrompt)
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        return AppPreferenceKey.defaultTranslationPrompt
    }

    var translationCustomLLMRepo: String {
        let value = defaults.string(forKey: AppPreferenceKey.translationCustomLLMModelRepo)
        if let value, !value.isEmpty {
            return value
        }
        return defaults.string(forKey: AppPreferenceKey.customLLMModelRepo)
            ?? CustomLLMModelManager.defaultModelRepo
    }

    var translationModelProvider: TranslationModelProvider {
        enumValue(forKey: AppPreferenceKey.translationModelProvider, default: .customLLM)
    }

    var translationFallbackModelProvider: TranslationModelProvider {
        let stored = enumValue(forKey: AppPreferenceKey.translationFallbackModelProvider, default: Optional<TranslationModelProvider>.none)
        return TranslationProviderResolver.sanitizedFallbackProvider(stored ?? .customLLM)
    }

    var remoteASRSelectedProvider: RemoteASRProvider {
        enumValue(forKey: AppPreferenceKey.remoteASRSelectedProvider, default: .openAIWhisper)
    }

    var remoteLLMSelectedProvider: RemoteLLMProvider {
        enumValue(forKey: AppPreferenceKey.remoteLLMSelectedProvider, default: .openAI)
    }

    var translationRemoteLLMProvider: RemoteLLMProvider? {
        enumValue(forKey: AppPreferenceKey.translationRemoteLLMProvider, default: Optional<RemoteLLMProvider>.none)
    }

    var rewriteSystemPrompt: String {
        let value = defaults.string(forKey: AppPreferenceKey.rewriteSystemPrompt)
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        return AppPreferenceKey.defaultRewritePrompt
    }

    var rewriteCustomLLMRepo: String {
        let value = defaults.string(forKey: AppPreferenceKey.rewriteCustomLLMModelRepo)
        if let value, !value.isEmpty {
            return value
        }
        return defaults.string(forKey: AppPreferenceKey.customLLMModelRepo)
            ?? CustomLLMModelManager.defaultModelRepo
    }

    var rewriteModelProvider: RewriteModelProvider {
        enumValue(forKey: AppPreferenceKey.rewriteModelProvider, default: .customLLM)
    }

    var rewriteRemoteLLMProvider: RemoteLLMProvider? {
        enumValue(forKey: AppPreferenceKey.rewriteRemoteLLMProvider, default: Optional<RemoteLLMProvider>.none)
    }

    var remoteASRConfigurations: [String: RemoteProviderConfiguration] {
        remoteConfigurations(forKey: AppPreferenceKey.remoteASRProviderConfigurations)
    }

    var remoteLLMConfigurations: [String: RemoteProviderConfiguration] {
        remoteConfigurations(forKey: AppPreferenceKey.remoteLLMProviderConfigurations)
    }

    var showInDock: Bool {
        defaults.bool(forKey: AppPreferenceKey.showInDock)
    }

    var whisperTemperature: Double {
        defaults.double(forKey: AppPreferenceKey.whisperTemperature)
    }

    var whisperVADEnabled: Bool {
        defaults.object(forKey: AppPreferenceKey.whisperVADEnabled) as? Bool ?? true
    }

    var whisperTimestampsEnabled: Bool {
        defaults.object(forKey: AppPreferenceKey.whisperTimestampsEnabled) as? Bool ?? false
    }

    var whisperRealtimeEnabled: Bool {
        defaults.object(forKey: AppPreferenceKey.whisperRealtimeEnabled) as? Bool ?? true
    }

    var whisperKeepResidentLoaded: Bool {
        defaults.object(forKey: AppPreferenceKey.whisperKeepResidentLoaded) as? Bool ?? true
    }

    var historyEnabled: Bool {
        defaults.bool(forKey: AppPreferenceKey.historyEnabled)
    }

    var dictionaryAutoLearningEnabled: Bool {
        defaults.object(forKey: AppPreferenceKey.dictionaryAutoLearningEnabled) as? Bool ?? true
    }

    var autoCheckForUpdates: Bool {
        defaults.bool(forKey: AppPreferenceKey.autoCheckForUpdates)
    }

    func appendHistoryIfNeeded(
        text: String,
        llmDurationSeconds: TimeInterval?,
        dictionaryHitTerms: [String],
        dictionaryCorrectedTerms: [String],
        dictionarySuggestedTerms: [DictionarySuggestionSnapshot]
    ) -> UUID? {
        guard historyEnabled else { return nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let transcriptionModel: String
        switch transcriptionEngine {
        case .dictation:
            transcriptionModel = "Apple Speech Recognition"
        case .mlxAudio:
            let repo = mlxModelManager.currentModelRepo
            transcriptionModel = "\(mlxModelManager.displayTitle(for: repo)) (\(repo))"
        case .whisperKit:
            let modelID = whisperModelManager.currentModelID
            transcriptionModel = "\(whisperModelManager.displayTitle(for: modelID)) (\(modelID))"
        case .remote:
            let provider = remoteASRSelectedProvider
            if let config = remoteASRConfigurations[provider.rawValue], config.hasUsableModel {
                transcriptionModel = "\(provider.title) (\(config.model))"
            } else {
                transcriptionModel = provider.title
            }
        }

        let enhancementModel: String
        switch enhancementMode {
        case .off:
            enhancementModel = "None"
        case .appleIntelligence:
            enhancementModel = "Apple Intelligence (Foundation Models)"
        case .customLLM:
            let repo = customLLMManager.currentModelRepo
            enhancementModel = "\(customLLMManager.displayTitle(for: repo)) (\(repo))"
        case .remoteLLM:
            let provider = remoteLLMSelectedProvider
            if let config = remoteLLMConfigurations[provider.rawValue], config.hasUsableModel {
                enhancementModel = "\(provider.title) (\(config.model))"
            } else {
                enhancementModel = provider.title
            }
        }

        let now = Date()
        let audioDuration = resolvedDuration(from: recordingStartedAt, to: recordingStoppedAt ?? now)
        // ASR processing duration should exclude LLM enhancement time.
        // Measure from recording stop to first ASR text callback when available.
        let processingEnd = transcriptionResultReceivedAt ?? now
        let processingDuration = resolvedDuration(from: transcriptionProcessingStartedAt, to: processingEnd)
        let focusedAppName = lastEnhancementPromptContext?.focusedAppName ?? NSWorkspace.shared.frontmostApplication?.localizedName

        let remoteASRProviderInfo: String?
        let remoteASRModelInfo: String?
        let remoteASREndpointInfo: String?
        if transcriptionEngine == .remote {
            let provider = remoteASRSelectedProvider
            let config = remoteASRConfigurations[provider.rawValue]
            remoteASRProviderInfo = provider.title
            remoteASRModelInfo = config?.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? config?.model : nil
            remoteASREndpointInfo = historyDisplayEndpoint(config?.endpoint)
        } else {
            remoteASRProviderInfo = nil
            remoteASRModelInfo = nil
            remoteASREndpointInfo = nil
        }

        let remoteLLMProviderInfo: String?
        let remoteLLMModelInfo: String?
        let remoteLLMEndpointInfo: String?
        if enhancementMode == .remoteLLM {
            let provider = remoteLLMSelectedProvider
            let config = remoteLLMConfigurations[provider.rawValue]
            remoteLLMProviderInfo = provider.title
            remoteLLMModelInfo = config?.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? config?.model : nil
            remoteLLMEndpointInfo = historyDisplayEndpoint(config?.endpoint)
        } else {
            remoteLLMProviderInfo = nil
            remoteLLMModelInfo = nil
            remoteLLMEndpointInfo = nil
        }

        let entryID = historyStore.append(
            text: trimmed,
            transcriptionEngine: transcriptionEngine.title,
            transcriptionModel: transcriptionModel,
            enhancementMode: enhancementMode.title,
            enhancementModel: enhancementModel,
            kind: resolvedHistoryKind(),
            isTranslation: sessionOutputMode == .translation,
            audioDurationSeconds: audioDuration,
            transcriptionProcessingDurationSeconds: processingDuration,
            llmDurationSeconds: llmDurationSeconds,
            focusedAppName: focusedAppName,
            matchedGroupID: lastEnhancementPromptContext?.matchedGroupID,
            matchedAppGroupName: lastEnhancementPromptContext?.matchedAppGroupName,
            matchedURLGroupName: lastEnhancementPromptContext?.matchedURLGroupName,
            remoteASRProvider: remoteASRProviderInfo,
            remoteASRModel: remoteASRModelInfo,
            remoteASREndpoint: remoteASREndpointInfo,
            remoteLLMProvider: remoteLLMProviderInfo,
            remoteLLMModel: remoteLLMModelInfo,
            remoteLLMEndpoint: remoteLLMEndpointInfo,
            whisperWordTimings: transcriptionEngine == .whisperKit && whisperTimestampsEnabled
                ? whisperTranscriber?.latestWordTimings
                : nil,
            dictionaryHitTerms: dictionaryHitTerms,
            dictionaryCorrectedTerms: dictionaryCorrectedTerms,
            dictionarySuggestedTerms: dictionarySuggestedTerms
        )

        lastEnhancementPromptContext = nil
        transcriptionResultReceivedAt = nil

        if entryID != nil {
            scheduleAutomaticDictionaryHistorySuggestionScanIfNeeded()
        }

        return entryID
    }

    private func resolvedHistoryKind() -> TranscriptionHistoryKind {
        HistoryValueResolver.resolvedKind(for: sessionOutputMode)
    }

    private func resolvedDuration(from start: Date?, to end: Date?) -> TimeInterval? {
        HistoryValueResolver.resolvedDuration(from: start, to: end)
    }

    private func historyDisplayEndpoint(_ endpoint: String?) -> String? {
        HistoryValueResolver.historyDisplayEndpoint(endpoint)
    }

    private func trimmedStringValue(forKey key: String) -> String {
        stringValue(forKey: key).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stringValue(forKey key: String) -> String {
        defaults.string(forKey: key) ?? ""
    }

    private func remoteConfigurations(forKey key: String) -> [String: RemoteProviderConfiguration] {
        RemoteModelConfigurationStore.loadConfigurations(from: stringValue(forKey: key))
    }

    private func enumValue<T: RawRepresentable>(forKey key: String, default defaultValue: T) -> T where T.RawValue == String {
        T(rawValue: stringValue(forKey: key)) ?? defaultValue
    }

    private func enumValue<T: RawRepresentable>(forKey key: String, default defaultValue: T?) -> T? where T.RawValue == String {
        T(rawValue: stringValue(forKey: key)) ?? defaultValue
    }
}
