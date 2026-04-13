import Foundation
import AppKit
import CoreAudio

extension AppDelegate {
    private struct HistoryTextModelMetadata {
        let modeTitle: String
        let modelTitle: String
        let remoteProviderTitle: String?
        let remoteModelTitle: String?
        let remoteEndpoint: String?
    }

    private var defaults: UserDefaults {
        .standard
    }

    var featureSettings: FeatureSettings {
        FeatureSettingsStore.load(defaults: defaults)
    }

    func updateFeatureSettings(_ mutate: (inout FeatureSettings) -> Void) {
        FeatureSettingsStore.update(defaults: defaults, mutate)
    }

    var transcriptionFeatureSettings: TranscriptionFeatureSettings {
        featureSettings.transcription
    }

    var translationFeatureSettings: TranslationFeatureSettings {
        featureSettings.translation
    }

    var rewriteFeatureSettings: RewriteFeatureSettings {
        featureSettings.rewrite
    }

    var meetingFeatureSettings: MeetingFeatureSettings {
        featureSettings.meeting
    }

    func prepareLegacySettingsForSession(outputMode: SessionOutputMode) {
        FeatureSettingsStore.prepareLegacySession(
            from: featureSettings,
            outputMode: outputMode,
            defaults: defaults
        )
    }

    func prepareLegacySettingsForMeeting() {
        FeatureSettingsStore.prepareLegacyMeeting(from: featureSettings, defaults: defaults)
    }

    var selectedInputDeviceUID: String? {
        MicrophonePreferenceManager.activeInputDeviceUID(defaults: defaults)
    }

    var selectedInputDeviceID: AudioDeviceID? {
        MicrophonePreferenceManager.activeInputDeviceID(
            defaults: defaults,
            availableDevices: inputDevicesSnapshot
        )
    }

    var microphoneAutoSwitchEnabled: Bool {
        MicrophonePreferenceManager.autoSwitchEnabled(defaults: defaults)
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

    var userOtherMainLanguagesPromptValue: String {
        DictionaryHistoryScanPromptLanguageSupport.otherLanguagesPromptValue(
            from: userMainLanguageCodes
        )
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
        false
    }

    var autoCheckForUpdates: Bool {
        defaults.bool(forKey: AppPreferenceKey.autoCheckForUpdates)
    }

    func appendHistoryIfNeeded(
        text: String,
        displayTitle: String? = nil,
        llmDurationSeconds: TimeInterval?,
        dictionaryHitTerms: [String],
        dictionaryCorrectedTerms: [String],
        dictionarySuggestedTerms: [DictionarySuggestionSnapshot]
    ) -> UUID? {
        guard historyEnabled else { return nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let trimmedDisplayTitle = displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines)

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

        let historyKind = resolvedHistoryKind()
        let textModelMetadata = resolvedHistoryTextModelMetadata(for: historyKind)

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

        let entryID = historyStore.append(
            text: trimmed,
            transcriptionEngine: transcriptionEngine.title,
            transcriptionModel: transcriptionModel,
            enhancementMode: textModelMetadata.modeTitle,
            enhancementModel: textModelMetadata.modelTitle,
            kind: historyKind,
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
            remoteLLMProvider: textModelMetadata.remoteProviderTitle,
            remoteLLMModel: textModelMetadata.remoteModelTitle,
            remoteLLMEndpoint: textModelMetadata.remoteEndpoint,
            whisperWordTimings: transcriptionEngine == .whisperKit && whisperTimestampsEnabled
                ? whisperTranscriber?.latestWordTimings
                : nil,
            displayTitle: trimmedDisplayTitle?.isEmpty == false ? trimmedDisplayTitle : nil,
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

    private func resolvedHistoryTextModelMetadata(for kind: TranscriptionHistoryKind) -> HistoryTextModelMetadata {
        switch kind {
        case .normal:
            guard transcriptionFeatureSettings.llmEnabled else {
                return HistoryTextModelMetadata(
                    modeTitle: EnhancementMode.off.title,
                    modelTitle: "None",
                    remoteProviderTitle: nil,
                    remoteModelTitle: nil,
                    remoteEndpoint: nil
                )
            }
            return resolvedHistoryTextModelMetadata(for: transcriptionFeatureSettings.llmSelectionID.textSelection)
        case .translation:
            return resolvedTranslationHistoryTextModelMetadata()
        case .rewrite:
            return resolvedHistoryTextModelMetadata(for: rewriteFeatureSettings.llmSelectionID.textSelection)
        case .meeting:
            return resolvedHistoryTextModelMetadata(for: meetingFeatureSettings.summaryModelSelectionID.textSelection)
        }
    }

    private func resolvedTranslationHistoryTextModelMetadata() -> HistoryTextModelMetadata {
        switch translationFeatureSettings.modelSelectionID.translationSelection {
        case .whisperDirectTranslate:
            let whisperTitle = TranslationModelProvider.whisperKit.title
            return HistoryTextModelMetadata(
                modeTitle: whisperTitle,
                modelTitle: whisperTitle,
                remoteProviderTitle: nil,
                remoteModelTitle: nil,
                remoteEndpoint: nil
            )
        case .localLLM(let repo):
            return HistoryTextModelMetadata(
                modeTitle: TranslationModelProvider.customLLM.title,
                modelTitle: "\(customLLMManager.displayTitle(for: repo)) (\(repo))",
                remoteProviderTitle: nil,
                remoteModelTitle: nil,
                remoteEndpoint: nil
            )
        case .remoteLLM(let provider):
            return resolvedRemoteHistoryTextModelMetadata(
                provider: provider,
                modeTitle: TranslationModelProvider.remoteLLM.title
            )
        case .none:
            return HistoryTextModelMetadata(
                modeTitle: EnhancementMode.off.title,
                modelTitle: "None",
                remoteProviderTitle: nil,
                remoteModelTitle: nil,
                remoteEndpoint: nil
            )
        }
    }

    private func resolvedHistoryTextModelMetadata(
        for selection: FeatureModelSelectionID.TextSelection?
    ) -> HistoryTextModelMetadata {
        switch selection {
        case .appleIntelligence:
            return HistoryTextModelMetadata(
                modeTitle: EnhancementMode.appleIntelligence.title,
                modelTitle: "Apple Intelligence (Foundation Models)",
                remoteProviderTitle: nil,
                remoteModelTitle: nil,
                remoteEndpoint: nil
            )
        case .localLLM(let repo):
            return HistoryTextModelMetadata(
                modeTitle: EnhancementMode.customLLM.title,
                modelTitle: "\(customLLMManager.displayTitle(for: repo)) (\(repo))",
                remoteProviderTitle: nil,
                remoteModelTitle: nil,
                remoteEndpoint: nil
            )
        case .remoteLLM(let provider):
            return resolvedRemoteHistoryTextModelMetadata(
                provider: provider,
                modeTitle: EnhancementMode.remoteLLM.title
            )
        case .none:
            return HistoryTextModelMetadata(
                modeTitle: EnhancementMode.off.title,
                modelTitle: "None",
                remoteProviderTitle: nil,
                remoteModelTitle: nil,
                remoteEndpoint: nil
            )
        }
    }

    private func resolvedRemoteHistoryTextModelMetadata(
        provider: RemoteLLMProvider,
        modeTitle: String
    ) -> HistoryTextModelMetadata {
        let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(
            provider: provider,
            stored: remoteLLMConfigurations
        )
        let trimmedModel = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        return HistoryTextModelMetadata(
            modeTitle: modeTitle,
            modelTitle: trimmedModel.isEmpty ? provider.title : "\(provider.title) (\(trimmedModel))",
            remoteProviderTitle: provider.title,
            remoteModelTitle: trimmedModel.isEmpty ? nil : trimmedModel,
            remoteEndpoint: historyDisplayEndpoint(configuration.endpoint)
        )
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
