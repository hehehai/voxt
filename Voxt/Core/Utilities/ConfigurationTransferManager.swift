// ConfigurationTransferManager.swift
// Provides Configuration Transfer Manager for shared utilities.

import Foundation
import UniformTypeIdentifiers
import SwiftUI

struct ConfigurationExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8)
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = text
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

enum ConfigurationTransferManager {
    static let sensitivePlaceholder = "__VOXT_REQUIRED__"
    static let storedRemoteSensitivePlaceholder = "__stored__"

    struct FileEnvironment {
        let dictionaryEntriesURL: () throws -> URL
        let dictionarySuggestionsURL: () throws -> URL
        let dictionaryRepository: () -> DictionaryRepositoryProtocol?

        init(
            dictionaryEntriesURL: @escaping () throws -> URL = { try ConfigurationTransferManager.dictionaryFileURL() },
            dictionarySuggestionsURL: @escaping () throws -> URL = { try ConfigurationTransferManager.dictionarySuggestionsFileURL() },
            dictionaryRepository: @escaping () -> DictionaryRepositoryProtocol? = { DictionaryRepository() }
        ) {
            self.dictionaryEntriesURL = dictionaryEntriesURL
            self.dictionarySuggestionsURL = dictionarySuggestionsURL
            self.dictionaryRepository = dictionaryRepository
        }

        static let live = FileEnvironment()
    }

    struct ExportPayload: Codable {
        var version: Int
        var exportedAt: String
        var general: GeneralSettings
        var model: ModelSettings
        var feature: FeatureSettings?
        var dictionary: DictionarySettings?
        var appBranch: AppBranchSettings
        var hotkey: HotkeySettings
    }

    struct GeneralSettings: Codable {
        var interfaceLanguage: String
        var selectedInputDeviceID: Int
        var activeInputDeviceUID: String?
        var microphoneAutoSwitchEnabled: Bool
        var microphonePriorityUIDs: [String]
        var trackedMicrophoneRecords: [TrackedMicrophoneRecord]
        var modelStorageRootPath: String
        var interactionSoundsEnabled: Bool
        var interactionSoundPreset: String
        var muteSystemAudioWhileRecording: Bool
        var overlayPosition: String
        var overlayCardOpacity: Int
        var overlayCardCornerRadius: Int
        var overlayScreenEdgeInset: Int
        var translationTargetLanguage: String
        var userMainLanguageCodes: [String]
        var translateSelectedTextOnTranslationHotkey: Bool
        var voiceEndCommandEnabled: Bool
        var voiceEndCommandPreset: String
        var voiceEndCommandText: String
        var autoCopyWhenNoFocusedInput: Bool
        var realtimeTextDisplayEnabled: Bool
        var alwaysShowRewriteAnswerCard: Bool
        var launchAtLogin: Bool
        var showInDock: Bool
        var historyEnabled: Bool
        var historyCleanupEnabled: Bool
        var historyRetentionPeriod: String
        var autoCheckForUpdates: Bool
        var betaUpdatesEnabled: Bool
        var hotkeyDebugLoggingEnabled: Bool
        var llmDebugLoggingEnabled: Bool
        var useSystemProxy: Bool
        var networkProxyMode: String
        var customProxyScheme: String
        var customProxyHost: String
        var customProxyPort: String
        var customProxyUsername: String
        var customProxyPassword: String

        private enum CodingKeys: String, CodingKey {
            case interfaceLanguage
            case selectedInputDeviceID
            case activeInputDeviceUID
            case microphoneAutoSwitchEnabled
            case microphonePriorityUIDs
            case trackedMicrophoneRecords
            case modelStorageRootPath
            case interactionSoundsEnabled
            case interactionSoundPreset
            case muteSystemAudioWhileRecording
            case overlayPosition
            case overlayCardOpacity
            case overlayCardCornerRadius
            case overlayScreenEdgeInset
            case translationTargetLanguage
            case userMainLanguageCodes
            case translateSelectedTextOnTranslationHotkey
            case voiceEndCommandEnabled
            case voiceEndCommandPreset
            case voiceEndCommandText
            case autoCopyWhenNoFocusedInput
            case realtimeTextDisplayEnabled
            case alwaysShowRewriteAnswerCard
            case launchAtLogin
            case showInDock
            case historyEnabled
            case historyCleanupEnabled
            case historyRetentionPeriod
            case autoCheckForUpdates
            case betaUpdatesEnabled
            case hotkeyDebugLoggingEnabled
            case llmDebugLoggingEnabled
            case useSystemProxy
            case networkProxyMode
            case customProxyScheme
            case customProxyHost
            case customProxyPort
            case customProxyUsername
            case customProxyPassword
        }

        private enum LegacyCodingKeys: String, CodingKey {
            case manualSelectedInputDeviceUID
        }

        init(
            interfaceLanguage: String,
            selectedInputDeviceID: Int,
            activeInputDeviceUID: String?,
            microphoneAutoSwitchEnabled: Bool,
            microphonePriorityUIDs: [String],
            trackedMicrophoneRecords: [TrackedMicrophoneRecord],
            modelStorageRootPath: String,
            interactionSoundsEnabled: Bool,
            interactionSoundPreset: String,
            muteSystemAudioWhileRecording: Bool,
            overlayPosition: String,
            overlayCardOpacity: Int,
            overlayCardCornerRadius: Int,
            overlayScreenEdgeInset: Int,
            translationTargetLanguage: String,
            userMainLanguageCodes: [String],
            translateSelectedTextOnTranslationHotkey: Bool,
            voiceEndCommandEnabled: Bool,
            voiceEndCommandPreset: String,
            voiceEndCommandText: String,
            autoCopyWhenNoFocusedInput: Bool,
            realtimeTextDisplayEnabled: Bool,
            alwaysShowRewriteAnswerCard: Bool,
            launchAtLogin: Bool,
            showInDock: Bool,
            historyEnabled: Bool,
            historyCleanupEnabled: Bool,
            historyRetentionPeriod: String,
            autoCheckForUpdates: Bool,
            betaUpdatesEnabled: Bool,
            hotkeyDebugLoggingEnabled: Bool,
            llmDebugLoggingEnabled: Bool,
            useSystemProxy: Bool,
            networkProxyMode: String,
            customProxyScheme: String,
            customProxyHost: String,
            customProxyPort: String,
            customProxyUsername: String,
            customProxyPassword: String
        ) {
            self.interfaceLanguage = interfaceLanguage
            self.selectedInputDeviceID = selectedInputDeviceID
            let trimmedActiveUID = activeInputDeviceUID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self.activeInputDeviceUID = trimmedActiveUID.isEmpty ? nil : trimmedActiveUID
            self.microphoneAutoSwitchEnabled = microphoneAutoSwitchEnabled
            self.microphonePriorityUIDs = microphonePriorityUIDs
            self.trackedMicrophoneRecords = trackedMicrophoneRecords
            self.modelStorageRootPath = modelStorageRootPath
            self.interactionSoundsEnabled = interactionSoundsEnabled
            self.interactionSoundPreset = interactionSoundPreset
            self.muteSystemAudioWhileRecording = muteSystemAudioWhileRecording
            self.overlayPosition = overlayPosition
            self.overlayCardOpacity = overlayCardOpacity
            self.overlayCardCornerRadius = overlayCardCornerRadius
            self.overlayScreenEdgeInset = overlayScreenEdgeInset
            self.translationTargetLanguage = translationTargetLanguage
            self.userMainLanguageCodes = UserMainLanguageOption.sanitizedSelection(userMainLanguageCodes)
            self.translateSelectedTextOnTranslationHotkey = translateSelectedTextOnTranslationHotkey
            self.voiceEndCommandEnabled = voiceEndCommandEnabled
            self.voiceEndCommandPreset = voiceEndCommandPreset
            self.voiceEndCommandText = voiceEndCommandText
            self.autoCopyWhenNoFocusedInput = autoCopyWhenNoFocusedInput
            self.realtimeTextDisplayEnabled = realtimeTextDisplayEnabled
            self.alwaysShowRewriteAnswerCard = alwaysShowRewriteAnswerCard
            self.launchAtLogin = launchAtLogin
            self.showInDock = showInDock
            self.historyEnabled = historyEnabled
            self.historyCleanupEnabled = historyCleanupEnabled
            self.historyRetentionPeriod = historyRetentionPeriod
            self.autoCheckForUpdates = autoCheckForUpdates
            self.betaUpdatesEnabled = betaUpdatesEnabled
            self.hotkeyDebugLoggingEnabled = hotkeyDebugLoggingEnabled
            self.llmDebugLoggingEnabled = llmDebugLoggingEnabled
            self.useSystemProxy = useSystemProxy
            self.networkProxyMode = networkProxyMode
            self.customProxyScheme = customProxyScheme
            self.customProxyHost = customProxyHost
            self.customProxyPort = customProxyPort
            self.customProxyUsername = customProxyUsername
            self.customProxyPassword = customProxyPassword
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            interfaceLanguage = try container.decode(String.self, forKey: .interfaceLanguage)
            selectedInputDeviceID = try container.decodeIfPresent(Int.self, forKey: .selectedInputDeviceID) ?? 0
            let decodedActiveUID = try container.decodeIfPresent(String.self, forKey: .activeInputDeviceUID)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
            let decodedManualUID = try legacyContainer.decodeIfPresent(String.self, forKey: .manualSelectedInputDeviceUID)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            activeInputDeviceUID = !decodedActiveUID.isEmpty ? decodedActiveUID : (decodedManualUID.isEmpty ? nil : decodedManualUID)
            microphoneAutoSwitchEnabled = try container.decodeIfPresent(Bool.self, forKey: .microphoneAutoSwitchEnabled) ?? true
            microphonePriorityUIDs = try container.decodeIfPresent([String].self, forKey: .microphonePriorityUIDs) ?? []
            trackedMicrophoneRecords = try container.decodeIfPresent([TrackedMicrophoneRecord].self, forKey: .trackedMicrophoneRecords) ?? []
            modelStorageRootPath = try container.decodeIfPresent(String.self, forKey: .modelStorageRootPath) ?? ""
            interactionSoundsEnabled = try container.decode(Bool.self, forKey: .interactionSoundsEnabled)
            interactionSoundPreset = try container.decode(String.self, forKey: .interactionSoundPreset)
            muteSystemAudioWhileRecording = try container.decodeIfPresent(Bool.self, forKey: .muteSystemAudioWhileRecording) ?? false
            overlayPosition = try container.decode(String.self, forKey: .overlayPosition)
            overlayCardOpacity = try container.decodeIfPresent(Int.self, forKey: .overlayCardOpacity) ?? 82
            overlayCardCornerRadius = try container.decodeIfPresent(Int.self, forKey: .overlayCardCornerRadius) ?? 24
            overlayScreenEdgeInset = try container.decodeIfPresent(Int.self, forKey: .overlayScreenEdgeInset) ?? 30
            translationTargetLanguage = try container.decode(String.self, forKey: .translationTargetLanguage)
            userMainLanguageCodes = UserMainLanguageOption.sanitizedSelection(
                try container.decodeIfPresent([String].self, forKey: .userMainLanguageCodes)
                    ?? UserMainLanguageOption.defaultSelectionCodes()
            )
            translateSelectedTextOnTranslationHotkey = try container.decodeIfPresent(Bool.self, forKey: .translateSelectedTextOnTranslationHotkey) ?? true
            voiceEndCommandEnabled = try container.decodeIfPresent(Bool.self, forKey: .voiceEndCommandEnabled) ?? false
            voiceEndCommandPreset = try container.decodeIfPresent(String.self, forKey: .voiceEndCommandPreset) ?? VoiceEndCommandPreset.over.rawValue
            voiceEndCommandText = try container.decodeIfPresent(String.self, forKey: .voiceEndCommandText) ?? ""
            autoCopyWhenNoFocusedInput = try container.decode(Bool.self, forKey: .autoCopyWhenNoFocusedInput)
            realtimeTextDisplayEnabled = try container.decodeIfPresent(Bool.self, forKey: .realtimeTextDisplayEnabled) ?? true
            alwaysShowRewriteAnswerCard = try container.decodeIfPresent(Bool.self, forKey: .alwaysShowRewriteAnswerCard) ?? false
            launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
            showInDock = try container.decode(Bool.self, forKey: .showInDock)
            historyEnabled = try container.decodeIfPresent(Bool.self, forKey: .historyEnabled) ?? true
            historyCleanupEnabled = try container.decodeIfPresent(Bool.self, forKey: .historyCleanupEnabled) ?? true
            historyRetentionPeriod = try container.decodeIfPresent(String.self, forKey: .historyRetentionPeriod) ?? HistoryRetentionPeriod.ninetyDays.rawValue
            autoCheckForUpdates = try container.decode(Bool.self, forKey: .autoCheckForUpdates)
            betaUpdatesEnabled = try container.decodeIfPresent(Bool.self, forKey: .betaUpdatesEnabled) ?? false
            hotkeyDebugLoggingEnabled = try container.decode(Bool.self, forKey: .hotkeyDebugLoggingEnabled)
            llmDebugLoggingEnabled = try container.decode(Bool.self, forKey: .llmDebugLoggingEnabled)
            useSystemProxy = try container.decode(Bool.self, forKey: .useSystemProxy)
            networkProxyMode = try container.decode(String.self, forKey: .networkProxyMode)
            customProxyScheme = try container.decode(String.self, forKey: .customProxyScheme)
            customProxyHost = try container.decode(String.self, forKey: .customProxyHost)
            customProxyPort = try container.decode(String.self, forKey: .customProxyPort)
            customProxyUsername = try container.decode(String.self, forKey: .customProxyUsername)
            customProxyPassword = try container.decode(String.self, forKey: .customProxyPassword)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(interfaceLanguage, forKey: .interfaceLanguage)
            try container.encode(selectedInputDeviceID, forKey: .selectedInputDeviceID)
            try container.encodeIfPresent(activeInputDeviceUID, forKey: .activeInputDeviceUID)
            try container.encode(microphoneAutoSwitchEnabled, forKey: .microphoneAutoSwitchEnabled)
            try container.encode(microphonePriorityUIDs, forKey: .microphonePriorityUIDs)
            try container.encode(trackedMicrophoneRecords, forKey: .trackedMicrophoneRecords)
            try container.encode(modelStorageRootPath, forKey: .modelStorageRootPath)
            try container.encode(interactionSoundsEnabled, forKey: .interactionSoundsEnabled)
            try container.encode(interactionSoundPreset, forKey: .interactionSoundPreset)
            try container.encode(muteSystemAudioWhileRecording, forKey: .muteSystemAudioWhileRecording)
            try container.encode(overlayPosition, forKey: .overlayPosition)
            try container.encode(overlayCardOpacity, forKey: .overlayCardOpacity)
            try container.encode(overlayCardCornerRadius, forKey: .overlayCardCornerRadius)
            try container.encode(overlayScreenEdgeInset, forKey: .overlayScreenEdgeInset)
            try container.encode(translationTargetLanguage, forKey: .translationTargetLanguage)
            try container.encode(userMainLanguageCodes, forKey: .userMainLanguageCodes)
            try container.encode(translateSelectedTextOnTranslationHotkey, forKey: .translateSelectedTextOnTranslationHotkey)
            try container.encode(voiceEndCommandEnabled, forKey: .voiceEndCommandEnabled)
            try container.encode(voiceEndCommandPreset, forKey: .voiceEndCommandPreset)
            try container.encode(voiceEndCommandText, forKey: .voiceEndCommandText)
            try container.encode(autoCopyWhenNoFocusedInput, forKey: .autoCopyWhenNoFocusedInput)
            try container.encode(realtimeTextDisplayEnabled, forKey: .realtimeTextDisplayEnabled)
            try container.encode(alwaysShowRewriteAnswerCard, forKey: .alwaysShowRewriteAnswerCard)
            try container.encode(launchAtLogin, forKey: .launchAtLogin)
            try container.encode(showInDock, forKey: .showInDock)
            try container.encode(historyEnabled, forKey: .historyEnabled)
            try container.encode(historyCleanupEnabled, forKey: .historyCleanupEnabled)
            try container.encode(historyRetentionPeriod, forKey: .historyRetentionPeriod)
            try container.encode(autoCheckForUpdates, forKey: .autoCheckForUpdates)
            try container.encode(betaUpdatesEnabled, forKey: .betaUpdatesEnabled)
            try container.encode(hotkeyDebugLoggingEnabled, forKey: .hotkeyDebugLoggingEnabled)
            try container.encode(llmDebugLoggingEnabled, forKey: .llmDebugLoggingEnabled)
            try container.encode(useSystemProxy, forKey: .useSystemProxy)
            try container.encode(networkProxyMode, forKey: .networkProxyMode)
            try container.encode(customProxyScheme, forKey: .customProxyScheme)
            try container.encode(customProxyHost, forKey: .customProxyHost)
            try container.encode(customProxyPort, forKey: .customProxyPort)
            try container.encode(customProxyUsername, forKey: .customProxyUsername)
            try container.encode(customProxyPassword, forKey: .customProxyPassword)
        }
    }

    struct ModelSettings: Codable {
        var transcriptionEngine: String
        var enhancementMode: String
        var enhancementSystemPrompt: String
        var translationSystemPrompt: String
        var rewriteSystemPrompt: String
        var asrHintSettings: String
        var whisperLocalASRTuningSettings: String
        var mlxLocalASRTuningSettings: String
        var mlxModelRepo: String
        var whisperModelID: String
        var whisperTemperature: Double
        var whisperVADEnabled: Bool
        var whisperTimestampsEnabled: Bool
        var whisperRealtimeEnabled: Bool
        var localModelIdleUnloadDelaySeconds: Int
        var localModelMemoryOptimizationEnabled: Bool
        var whisperKeepResidentLoaded: Bool
        var customLLMModelRepo: String
        var customLLMGenerationSettings: String
        var customLLMGenerationSettingsByRepo: String
        var translationCustomLLMModelRepo: String
        var rewriteCustomLLMModelRepo: String
        var translationModelProvider: String
        var translationFallbackModelProvider: String
        var rewriteModelProvider: String
        var remoteASRSelectedProvider: String
        var remoteLLMSelectedProvider: String
        var translationRemoteLLMProvider: String
        var rewriteRemoteLLMProvider: String
        var useHfMirror: Bool
        var remoteASRProviderConfigurations: [RemoteProviderConfiguration]
        var remoteLLMProviderConfigurations: [RemoteProviderConfiguration]

        private enum CodingKeys: String, CodingKey {
            case transcriptionEngine
            case enhancementMode
            case enhancementSystemPrompt
            case translationSystemPrompt
            case rewriteSystemPrompt
            case asrHintSettings
            case whisperLocalASRTuningSettings
            case mlxLocalASRTuningSettings
            case mlxModelRepo
            case whisperModelID
            case whisperTemperature
            case whisperVADEnabled
            case whisperTimestampsEnabled
            case whisperRealtimeEnabled
            case localModelIdleUnloadDelaySeconds
            case localModelMemoryOptimizationEnabled
            case whisperKeepResidentLoaded
            case customLLMModelRepo
            case customLLMGenerationSettings
            case customLLMGenerationSettingsByRepo
            case translationCustomLLMModelRepo
            case rewriteCustomLLMModelRepo
            case translationModelProvider
            case translationFallbackModelProvider
            case rewriteModelProvider
            case remoteASRSelectedProvider
            case remoteLLMSelectedProvider
            case translationRemoteLLMProvider
            case rewriteRemoteLLMProvider
            case useHfMirror
            case remoteASRProviderConfigurations
            case remoteLLMProviderConfigurations
        }

        init(
            transcriptionEngine: String,
            enhancementMode: String,
            enhancementSystemPrompt: String,
            translationSystemPrompt: String,
            rewriteSystemPrompt: String,
            asrHintSettings: String,
            whisperLocalASRTuningSettings: String,
            mlxLocalASRTuningSettings: String,
            mlxModelRepo: String,
            whisperModelID: String,
            whisperTemperature: Double,
            whisperVADEnabled: Bool,
            whisperTimestampsEnabled: Bool,
            whisperRealtimeEnabled: Bool,
            localModelIdleUnloadDelaySeconds: Int,
            customLLMModelRepo: String,
            customLLMGenerationSettings: String,
            customLLMGenerationSettingsByRepo: String,
            translationCustomLLMModelRepo: String,
            rewriteCustomLLMModelRepo: String,
            translationModelProvider: String,
            translationFallbackModelProvider: String,
            rewriteModelProvider: String,
            remoteASRSelectedProvider: String,
            remoteLLMSelectedProvider: String,
            translationRemoteLLMProvider: String,
            rewriteRemoteLLMProvider: String,
            useHfMirror: Bool,
            remoteASRProviderConfigurations: [RemoteProviderConfiguration],
            remoteLLMProviderConfigurations: [RemoteProviderConfiguration]
        ) {
            self.transcriptionEngine = transcriptionEngine
            self.enhancementMode = enhancementMode
            self.enhancementSystemPrompt = enhancementSystemPrompt
            self.translationSystemPrompt = translationSystemPrompt
            self.rewriteSystemPrompt = rewriteSystemPrompt
            self.asrHintSettings = asrHintSettings
            self.whisperLocalASRTuningSettings = whisperLocalASRTuningSettings
            self.mlxLocalASRTuningSettings = mlxLocalASRTuningSettings
            self.mlxModelRepo = MLXModelManager.canonicalModelRepo(mlxModelRepo)
            self.whisperModelID = whisperModelID
            self.whisperTemperature = whisperTemperature
            self.whisperVADEnabled = whisperVADEnabled
            self.whisperTimestampsEnabled = whisperTimestampsEnabled
            self.whisperRealtimeEnabled = whisperRealtimeEnabled
            let clampedIdleUnloadDelay = AppPreferenceKey.clampedLocalModelIdleUnloadDelaySeconds(localModelIdleUnloadDelaySeconds)
            self.localModelIdleUnloadDelaySeconds = clampedIdleUnloadDelay
            self.localModelMemoryOptimizationEnabled = clampedIdleUnloadDelay <= AppPreferenceKey.defaultLocalModelIdleUnloadDelaySeconds
            self.whisperKeepResidentLoaded = !self.localModelMemoryOptimizationEnabled
            self.customLLMModelRepo = customLLMModelRepo
            self.customLLMGenerationSettings = CustomLLMGenerationSettingsStore.storageValue(
                for: CustomLLMGenerationSettingsStore.resolvedSettings(from: customLLMGenerationSettings)
            )
            self.customLLMGenerationSettingsByRepo = CustomLLMGenerationSettingsStore.storageValue(
                forByRepo: CustomLLMGenerationSettingsStore.resolvedByRepo(from: customLLMGenerationSettingsByRepo)
            )
            self.translationCustomLLMModelRepo = translationCustomLLMModelRepo
            self.rewriteCustomLLMModelRepo = rewriteCustomLLMModelRepo
            self.translationModelProvider = translationModelProvider
            self.translationFallbackModelProvider = translationFallbackModelProvider
            self.rewriteModelProvider = rewriteModelProvider
            self.remoteASRSelectedProvider = remoteASRSelectedProvider
            self.remoteLLMSelectedProvider = remoteLLMSelectedProvider
            self.translationRemoteLLMProvider = translationRemoteLLMProvider
            self.rewriteRemoteLLMProvider = rewriteRemoteLLMProvider
            self.useHfMirror = useHfMirror
            self.remoteASRProviderConfigurations = remoteASRProviderConfigurations
            self.remoteLLMProviderConfigurations = remoteLLMProviderConfigurations
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            transcriptionEngine = try container.decode(String.self, forKey: .transcriptionEngine)
            enhancementMode = try container.decode(String.self, forKey: .enhancementMode)
            enhancementSystemPrompt = try container.decode(String.self, forKey: .enhancementSystemPrompt)
            translationSystemPrompt = try container.decode(String.self, forKey: .translationSystemPrompt)
            rewriteSystemPrompt = try container.decode(String.self, forKey: .rewriteSystemPrompt)
            asrHintSettings = try container.decodeIfPresent(String.self, forKey: .asrHintSettings) ?? ASRHintSettingsStore.defaultStoredValue()
            whisperLocalASRTuningSettings = try container.decodeIfPresent(String.self, forKey: .whisperLocalASRTuningSettings)
                ?? WhisperLocalTuningSettingsStore.defaultStoredValue()
            mlxLocalASRTuningSettings = try container.decodeIfPresent(String.self, forKey: .mlxLocalASRTuningSettings)
                ?? "{}"
            mlxModelRepo = MLXModelManager.canonicalModelRepo(
                try container.decode(String.self, forKey: .mlxModelRepo)
            )
            whisperModelID = try container.decodeIfPresent(String.self, forKey: .whisperModelID) ?? WhisperKitModelManager.defaultModelID
            whisperTemperature = try container.decodeIfPresent(Double.self, forKey: .whisperTemperature) ?? 0.0
            whisperVADEnabled = try container.decodeIfPresent(Bool.self, forKey: .whisperVADEnabled) ?? true
            whisperTimestampsEnabled = try container.decodeIfPresent(Bool.self, forKey: .whisperTimestampsEnabled) ?? false
            whisperRealtimeEnabled = try container.decodeIfPresent(Bool.self, forKey: .whisperRealtimeEnabled) ?? false
            if let idleUnloadDelay = try container.decodeIfPresent(Int.self, forKey: .localModelIdleUnloadDelaySeconds) {
                localModelIdleUnloadDelaySeconds = AppPreferenceKey.clampedLocalModelIdleUnloadDelaySeconds(idleUnloadDelay)
            } else if let optimizationEnabled = try container.decodeIfPresent(Bool.self, forKey: .localModelMemoryOptimizationEnabled) {
                localModelIdleUnloadDelaySeconds = optimizationEnabled
                    ? AppPreferenceKey.defaultLocalModelIdleUnloadDelaySeconds
                    : AppPreferenceKey.legacyLongLocalModelIdleUnloadDelaySeconds
            } else if let legacyKeepResident = try container.decodeIfPresent(Bool.self, forKey: .whisperKeepResidentLoaded) {
                localModelIdleUnloadDelaySeconds = legacyKeepResident
                    ? AppPreferenceKey.legacyLongLocalModelIdleUnloadDelaySeconds
                    : AppPreferenceKey.defaultLocalModelIdleUnloadDelaySeconds
            } else {
                localModelIdleUnloadDelaySeconds = AppPreferenceKey.defaultLocalModelIdleUnloadDelaySeconds
            }
            localModelMemoryOptimizationEnabled = localModelIdleUnloadDelaySeconds <= AppPreferenceKey.defaultLocalModelIdleUnloadDelaySeconds
            whisperKeepResidentLoaded = !localModelMemoryOptimizationEnabled
            customLLMModelRepo = try container.decode(String.self, forKey: .customLLMModelRepo)
            customLLMGenerationSettings = try container.decodeIfPresent(String.self, forKey: .customLLMGenerationSettings)
                ?? CustomLLMGenerationSettingsStore.defaultStoredValue()
            customLLMGenerationSettingsByRepo = try container.decodeIfPresent(String.self, forKey: .customLLMGenerationSettingsByRepo)
                ?? CustomLLMGenerationSettingsStore.defaultByRepoStoredValue()
            translationCustomLLMModelRepo = try container.decode(String.self, forKey: .translationCustomLLMModelRepo)
            rewriteCustomLLMModelRepo = try container.decode(String.self, forKey: .rewriteCustomLLMModelRepo)
            translationModelProvider = try container.decode(String.self, forKey: .translationModelProvider)
            translationFallbackModelProvider = try container.decodeIfPresent(String.self, forKey: .translationFallbackModelProvider) ?? TranslationModelProvider.customLLM.rawValue
            rewriteModelProvider = try container.decode(String.self, forKey: .rewriteModelProvider)
            remoteASRSelectedProvider = try container.decode(String.self, forKey: .remoteASRSelectedProvider)
            remoteLLMSelectedProvider = try container.decode(String.self, forKey: .remoteLLMSelectedProvider)
            translationRemoteLLMProvider = try container.decode(String.self, forKey: .translationRemoteLLMProvider)
            rewriteRemoteLLMProvider = try container.decode(String.self, forKey: .rewriteRemoteLLMProvider)
            useHfMirror = try container.decode(Bool.self, forKey: .useHfMirror)
            remoteASRProviderConfigurations = try container.decode([RemoteProviderConfiguration].self, forKey: .remoteASRProviderConfigurations)
            remoteLLMProviderConfigurations = try container.decode([RemoteProviderConfiguration].self, forKey: .remoteLLMProviderConfigurations)
            whisperLocalASRTuningSettings = WhisperLocalTuningSettingsStore.storageValue(
                for: WhisperLocalTuningSettingsStore.resolvedSettings(from: whisperLocalASRTuningSettings)
            )
            mlxLocalASRTuningSettings = MLXLocalTuningSettingsStore.storageValue(
                for: MLXLocalTuningSettingsStore.load(from: mlxLocalASRTuningSettings)
            )
            customLLMGenerationSettings = CustomLLMGenerationSettingsStore.storageValue(
                for: CustomLLMGenerationSettingsStore.resolvedSettings(from: customLLMGenerationSettings)
            )
            customLLMGenerationSettingsByRepo = CustomLLMGenerationSettingsStore.storageValue(
                forByRepo: CustomLLMGenerationSettingsStore.resolvedByRepo(from: customLLMGenerationSettingsByRepo)
            )
        }
    }

    struct AppBranchSettings: Codable {
        var appEnhancementEnabled: Bool
        var groups: [ExportedAppBranchGroup]
        var urls: [ExportedBranchURLItem]
        var customBrowsersJSON: String
    }

    struct DictionarySettings: Codable {
        var recognitionEnabled: Bool
        var autoLearningEnabled: Bool
        var autoLearningPrompt: String
        var highConfidenceCorrectionEnabled: Bool
        var suggestionFilterSettings: DictionarySuggestionFilterSettings
        var suggestionIngestModelOptionID: String
        var historyScanCheckpoint: DictionaryHistoryScanCheckpoint?
        var categories: [DictionaryCategory]
        var entries: [DictionaryEntry]
        var suggestions: [DictionarySuggestion]

        private enum CodingKeys: String, CodingKey {
            case recognitionEnabled
            case autoLearningEnabled
            case autoLearningPrompt
            case highConfidenceCorrectionEnabled
            case suggestionFilterSettings
            case suggestionIngestModelOptionID
            case historyScanCheckpoint
            case categories
            case entries
            case suggestions
        }

        init(
            recognitionEnabled: Bool,
            autoLearningEnabled: Bool,
            autoLearningPrompt: String,
            highConfidenceCorrectionEnabled: Bool,
            suggestionFilterSettings: DictionarySuggestionFilterSettings,
            suggestionIngestModelOptionID: String,
            historyScanCheckpoint: DictionaryHistoryScanCheckpoint?,
            categories: [DictionaryCategory],
            entries: [DictionaryEntry],
            suggestions: [DictionarySuggestion]
        ) {
            self.recognitionEnabled = recognitionEnabled
            self.autoLearningEnabled = autoLearningEnabled
            self.autoLearningPrompt = autoLearningPrompt
            self.highConfidenceCorrectionEnabled = highConfidenceCorrectionEnabled
            self.suggestionFilterSettings = suggestionFilterSettings
            self.suggestionIngestModelOptionID = suggestionIngestModelOptionID
            self.historyScanCheckpoint = historyScanCheckpoint
            self.categories = categories
            self.entries = entries
            self.suggestions = suggestions
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            recognitionEnabled = try container.decode(Bool.self, forKey: .recognitionEnabled)
            autoLearningEnabled = try container.decode(Bool.self, forKey: .autoLearningEnabled)
            autoLearningPrompt = try container.decodeIfPresent(String.self, forKey: .autoLearningPrompt) ?? ""
            highConfidenceCorrectionEnabled = try container.decode(Bool.self, forKey: .highConfidenceCorrectionEnabled)
            suggestionFilterSettings = try container.decodeIfPresent(
                DictionarySuggestionFilterSettings.self,
                forKey: .suggestionFilterSettings
            ) ?? .defaultValue
            suggestionIngestModelOptionID = try container.decodeIfPresent(
                String.self,
                forKey: .suggestionIngestModelOptionID
            ) ?? ""
            historyScanCheckpoint = try container.decodeIfPresent(
                DictionaryHistoryScanCheckpoint.self,
                forKey: .historyScanCheckpoint
            )
            categories = try container.decodeIfPresent([DictionaryCategory].self, forKey: .categories) ?? []
            entries = try container.decodeIfPresent([DictionaryEntry].self, forKey: .entries) ?? []
            suggestions = try container.decodeIfPresent([DictionarySuggestion].self, forKey: .suggestions) ?? []
        }
    }

    struct HotkeySettings: Codable {
        var hotkeyInputType: String
        var hotkeyKeyCode: Int
        var hotkeyMouseButtonNumber: Int?
        var hotkeyModifiers: Int
        var hotkeySidedModifiers: Int
        var translationHotkeyInputType: String
        var translationHotkeyKeyCode: Int
        var translationHotkeyMouseButtonNumber: Int?
        var translationHotkeyModifiers: Int
        var translationHotkeySidedModifiers: Int
        var rewriteHotkeyInputType: String
        var rewriteHotkeyKeyCode: Int
        var rewriteHotkeyMouseButtonNumber: Int?
        var rewriteHotkeyModifiers: Int
        var rewriteHotkeySidedModifiers: Int
        var customPasteHotkeyInputType: String
        var customPasteHotkeyMouseButtonNumber: Int?
        var rewriteHotkeyActivationMode: String
        var hotkeyTriggerMode: String
        var hotkeyDistinguishModifierSides: Bool
        var hotkeyPreset: String
        var escapeKeyCancelsOverlaySession: Bool

        private enum CodingKeys: String, CodingKey {
            case hotkeyInputType
            case hotkeyKeyCode
            case hotkeyMouseButtonNumber
            case hotkeyModifiers
            case hotkeySidedModifiers
            case translationHotkeyInputType
            case translationHotkeyKeyCode
            case translationHotkeyMouseButtonNumber
            case translationHotkeyModifiers
            case translationHotkeySidedModifiers
            case rewriteHotkeyInputType
            case rewriteHotkeyKeyCode
            case rewriteHotkeyMouseButtonNumber
            case rewriteHotkeyModifiers
            case rewriteHotkeySidedModifiers
            case customPasteHotkeyInputType
            case customPasteHotkeyMouseButtonNumber
            case rewriteHotkeyActivationMode
            case hotkeyTriggerMode
            case hotkeyDistinguishModifierSides
            case hotkeyPreset
            case escapeKeyCancelsOverlaySession
        }

        init(
            hotkeyInputType: String,
            hotkeyKeyCode: Int,
            hotkeyMouseButtonNumber: Int?,
            hotkeyModifiers: Int,
            hotkeySidedModifiers: Int,
            translationHotkeyInputType: String,
            translationHotkeyKeyCode: Int,
            translationHotkeyMouseButtonNumber: Int?,
            translationHotkeyModifiers: Int,
            translationHotkeySidedModifiers: Int,
            rewriteHotkeyInputType: String,
            rewriteHotkeyKeyCode: Int,
            rewriteHotkeyMouseButtonNumber: Int?,
            rewriteHotkeyModifiers: Int,
            rewriteHotkeySidedModifiers: Int,
            customPasteHotkeyInputType: String,
            customPasteHotkeyMouseButtonNumber: Int?,
            rewriteHotkeyActivationMode: String,
            hotkeyTriggerMode: String,
            hotkeyDistinguishModifierSides: Bool,
            hotkeyPreset: String,
            escapeKeyCancelsOverlaySession: Bool
        ) {
            self.hotkeyInputType = hotkeyInputType
            self.hotkeyKeyCode = hotkeyKeyCode
            self.hotkeyMouseButtonNumber = hotkeyMouseButtonNumber
            self.hotkeyModifiers = hotkeyModifiers
            self.hotkeySidedModifiers = hotkeySidedModifiers
            self.translationHotkeyInputType = translationHotkeyInputType
            self.translationHotkeyKeyCode = translationHotkeyKeyCode
            self.translationHotkeyMouseButtonNumber = translationHotkeyMouseButtonNumber
            self.translationHotkeyModifiers = translationHotkeyModifiers
            self.translationHotkeySidedModifiers = translationHotkeySidedModifiers
            self.rewriteHotkeyInputType = rewriteHotkeyInputType
            self.rewriteHotkeyKeyCode = rewriteHotkeyKeyCode
            self.rewriteHotkeyMouseButtonNumber = rewriteHotkeyMouseButtonNumber
            self.rewriteHotkeyModifiers = rewriteHotkeyModifiers
            self.rewriteHotkeySidedModifiers = rewriteHotkeySidedModifiers
            self.customPasteHotkeyInputType = customPasteHotkeyInputType
            self.customPasteHotkeyMouseButtonNumber = customPasteHotkeyMouseButtonNumber
            self.rewriteHotkeyActivationMode = rewriteHotkeyActivationMode
            self.hotkeyTriggerMode = hotkeyTriggerMode
            self.hotkeyDistinguishModifierSides = hotkeyDistinguishModifierSides
            self.hotkeyPreset = hotkeyPreset
            self.escapeKeyCancelsOverlaySession = escapeKeyCancelsOverlaySession
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            hotkeyInputType = try container.decodeIfPresent(String.self, forKey: .hotkeyInputType)
                ?? HotkeyPreference.Hotkey.Input.Kind.keyboard.rawValue
            hotkeyKeyCode = try container.decode(Int.self, forKey: .hotkeyKeyCode)
            hotkeyMouseButtonNumber = try container.decodeIfPresent(Int.self, forKey: .hotkeyMouseButtonNumber)
            hotkeyModifiers = try container.decode(Int.self, forKey: .hotkeyModifiers)
            hotkeySidedModifiers = try container.decode(Int.self, forKey: .hotkeySidedModifiers)
            translationHotkeyInputType = try container.decodeIfPresent(String.self, forKey: .translationHotkeyInputType)
                ?? HotkeyPreference.Hotkey.Input.Kind.keyboard.rawValue
            translationHotkeyKeyCode = try container.decode(Int.self, forKey: .translationHotkeyKeyCode)
            translationHotkeyMouseButtonNumber = try container.decodeIfPresent(Int.self, forKey: .translationHotkeyMouseButtonNumber)
            translationHotkeyModifiers = try container.decode(Int.self, forKey: .translationHotkeyModifiers)
            translationHotkeySidedModifiers = try container.decode(Int.self, forKey: .translationHotkeySidedModifiers)
            rewriteHotkeyInputType = try container.decodeIfPresent(String.self, forKey: .rewriteHotkeyInputType)
                ?? HotkeyPreference.Hotkey.Input.Kind.keyboard.rawValue
            rewriteHotkeyKeyCode = try container.decode(Int.self, forKey: .rewriteHotkeyKeyCode)
            rewriteHotkeyMouseButtonNumber = try container.decodeIfPresent(Int.self, forKey: .rewriteHotkeyMouseButtonNumber)
            rewriteHotkeyModifiers = try container.decode(Int.self, forKey: .rewriteHotkeyModifiers)
            rewriteHotkeySidedModifiers = try container.decode(Int.self, forKey: .rewriteHotkeySidedModifiers)
            customPasteHotkeyInputType = try container.decodeIfPresent(String.self, forKey: .customPasteHotkeyInputType)
                ?? HotkeyPreference.Hotkey.Input.Kind.keyboard.rawValue
            customPasteHotkeyMouseButtonNumber = try container.decodeIfPresent(Int.self, forKey: .customPasteHotkeyMouseButtonNumber)
            rewriteHotkeyActivationMode = try container.decodeIfPresent(
                String.self,
                forKey: .rewriteHotkeyActivationMode
            ) ?? HotkeyPreference.defaultRewriteActivationMode.rawValue
            hotkeyTriggerMode = try container.decode(String.self, forKey: .hotkeyTriggerMode)
            hotkeyDistinguishModifierSides = try container.decode(Bool.self, forKey: .hotkeyDistinguishModifierSides)
            hotkeyPreset = try container.decode(String.self, forKey: .hotkeyPreset)
            escapeKeyCancelsOverlaySession = try container.decodeIfPresent(
                Bool.self,
                forKey: .escapeKeyCancelsOverlaySession
            ) ?? true
        }
    }

    struct ExportedAppBranchGroup: Codable {
        var id: UUID
        var name: String
        var prompt: String
        var appBundleIDs: [String]
        var appRefs: [AppBranchAppRef]
        var urlPatternIDs: [UUID]
        var isExpanded: Bool
        var iconPlaceholder: String
    }

    struct ExportedBranchURLItem: Codable {
        var id: UUID
        var pattern: String
        var iconPlaceholder: String
    }

    struct MissingConfigurationIssue: Identifiable, Hashable {
        enum Scope: Hashable {
            case remoteASRProvider(RemoteASRProvider)
            case remoteLLMProvider(RemoteLLMProvider)
            case mlxModel(String)
            case whisperModel(String)
            case customLLMModel(String)
            case translationRemoteLLM(RemoteLLMProvider)
            case rewriteRemoteLLM(RemoteLLMProvider)
            case translationCustomLLM(String)
            case rewriteCustomLLM(String)
        }

        let scope: Scope
        let message: String

        var id: String {
            switch scope {
            case .remoteASRProvider(let provider):
                return "asr:\(provider.rawValue)"
            case .remoteLLMProvider(let provider):
                return "llm:\(provider.rawValue)"
            case .mlxModel(let repo):
                return "mlx:\(repo)"
            case .whisperModel(let modelID):
                return "whisper:\(modelID)"
            case .customLLMModel(let repo):
                return "custom:\(repo)"
            case .translationRemoteLLM(let provider):
                return "translation-llm:\(provider.rawValue)"
            case .rewriteRemoteLLM(let provider):
                return "rewrite-llm:\(provider.rawValue)"
            case .translationCustomLLM(let repo):
                return "translation-custom:\(repo)"
            case .rewriteCustomLLM(let repo):
                return "rewrite-custom:\(repo)"
            }
        }
    }

    static func exportJSONString(
        defaults: UserDefaults = .standard,
        environment: FileEnvironment = .live
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(makeExportPayload(defaults: defaults, environment: environment))
        guard let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return text
    }

    static func importConfiguration(
        from json: String,
        defaults: UserDefaults = .standard,
        environment: FileEnvironment = .live
    ) throws {
        let data = Data(json.utf8)
        let payload = try JSONDecoder().decode(ExportPayload.self, from: data)
        apply(payload: payload, defaults: defaults, environment: environment)
    }

    static func missingConfigurationIssues(
        defaults: UserDefaults = .standard,
        mlxModelManager: MLXModelManager,
        whisperModelManager: WhisperKitModelManager,
        customLLMManager: CustomLLMModelManager
    ) -> [MissingConfigurationIssue] {
        var issues: [MissingConfigurationIssue] = []

        let featureSettings = FeatureSettingsStore.load(defaults: defaults)
        let remoteASR = RemoteModelConfigurationStore.loadConfigurations(
            from: defaults.string(forKey: AppPreferenceKey.remoteASRProviderConfigurations) ?? "",
            sensitiveValueLoading: .metadataOnly
        )
        let remoteLLM = RemoteModelConfigurationStore.loadConfigurations(
            from: defaults.string(forKey: AppPreferenceKey.remoteLLMProviderConfigurations) ?? "",
            sensitiveValueLoading: .metadataOnly
        )

        appendASRIssues(
            for: featureSettings.transcription.asrSelectionID,
            issues: &issues,
            remoteASR: remoteASR,
            mlxModelManager: mlxModelManager,
            whisperModelManager: whisperModelManager
        )
        if featureSettings.transcription.llmEnabled {
            appendTextModelIssues(
                for: featureSettings.transcription.llmSelectionID,
                issues: &issues,
                remoteLLM: remoteLLM,
                customLLMManager: customLLMManager
            )
        }

        appendASRIssues(
            for: featureSettings.translation.asrSelectionID,
            issues: &issues,
            remoteASR: remoteASR,
            mlxModelManager: mlxModelManager,
            whisperModelManager: whisperModelManager
        )
        appendTranslationModelIssues(
            for: featureSettings.translation,
            issues: &issues,
            remoteLLM: remoteLLM,
            customLLMManager: customLLMManager
        )

        appendASRIssues(
            for: featureSettings.rewrite.asrSelectionID,
            issues: &issues,
            remoteASR: remoteASR,
            mlxModelManager: mlxModelManager,
            whisperModelManager: whisperModelManager
        )
        appendTextModelIssues(
            for: featureSettings.rewrite.llmSelectionID,
            issues: &issues,
            remoteLLM: remoteLLM,
            customLLMManager: customLLMManager
        )

        return Array(Set(issues)).sorted { $0.id < $1.id }
    }
    private static func makeExportPayload(
        defaults: UserDefaults,
        environment: FileEnvironment
    ) -> ExportPayload {
        let proxyCredentials = VoxtNetworkSession.proxyCredentials(defaults: defaults)

        let general = GeneralSettings(
            interfaceLanguage: defaults.string(forKey: AppPreferenceKey.interfaceLanguage) ?? AppInterfaceLanguage.system.rawValue,
            selectedInputDeviceID: defaults.integer(forKey: AppPreferenceKey.selectedInputDeviceID),
            activeInputDeviceUID: MicrophonePreferenceManager.activeInputDeviceUID(defaults: defaults),
            microphoneAutoSwitchEnabled: MicrophonePreferenceManager.autoSwitchEnabled(defaults: defaults),
            microphonePriorityUIDs: MicrophonePreferenceManager.priorityUIDs(defaults: defaults),
            trackedMicrophoneRecords: MicrophonePreferenceManager.trackedRecords(defaults: defaults),
            modelStorageRootPath: defaults.string(forKey: AppPreferenceKey.modelStorageRootPath) ?? "",
            interactionSoundsEnabled: defaults.bool(forKey: AppPreferenceKey.interactionSoundsEnabled),
            interactionSoundPreset: defaults.string(forKey: AppPreferenceKey.interactionSoundPreset) ?? "",
            muteSystemAudioWhileRecording: defaults.bool(forKey: AppPreferenceKey.muteSystemAudioWhileRecording),
            overlayPosition: defaults.string(forKey: AppPreferenceKey.overlayPosition) ?? OverlayPosition.bottom.rawValue,
            overlayCardOpacity: defaults.object(forKey: AppPreferenceKey.overlayCardOpacity) as? Int ?? 82,
            overlayCardCornerRadius: defaults.object(forKey: AppPreferenceKey.overlayCardCornerRadius) as? Int ?? 24,
            overlayScreenEdgeInset: defaults.object(forKey: AppPreferenceKey.overlayScreenEdgeInset) as? Int ?? 30,
            translationTargetLanguage: defaults.string(forKey: AppPreferenceKey.translationTargetLanguage) ?? TranslationTargetLanguage.english.rawValue,
            userMainLanguageCodes: UserMainLanguageOption.storedSelection(
                from: defaults.string(forKey: AppPreferenceKey.userMainLanguageCodes)
            ),
            translateSelectedTextOnTranslationHotkey: true,
            voiceEndCommandEnabled: defaults.object(forKey: AppPreferenceKey.voiceEndCommandEnabled) as? Bool ?? false,
            voiceEndCommandPreset: defaults.string(forKey: AppPreferenceKey.voiceEndCommandPreset) ?? VoiceEndCommandPreset.over.rawValue,
            voiceEndCommandText: defaults.string(forKey: AppPreferenceKey.voiceEndCommandText) ?? "",
            autoCopyWhenNoFocusedInput: defaults.bool(forKey: AppPreferenceKey.autoCopyWhenNoFocusedInput),
            realtimeTextDisplayEnabled: defaults.object(forKey: AppPreferenceKey.realtimeTextDisplayEnabled) as? Bool ?? true,
            alwaysShowRewriteAnswerCard: defaults.bool(forKey: AppPreferenceKey.alwaysShowRewriteAnswerCard),
            launchAtLogin: defaults.bool(forKey: AppPreferenceKey.launchAtLogin),
            showInDock: defaults.bool(forKey: AppPreferenceKey.showInDock),
            historyEnabled: true,
            historyCleanupEnabled: defaults.object(forKey: AppPreferenceKey.historyCleanupEnabled) as? Bool ?? true,
            historyRetentionPeriod: defaults.string(forKey: AppPreferenceKey.historyRetentionPeriod) ?? HistoryRetentionPeriod.ninetyDays.rawValue,
            autoCheckForUpdates: defaults.object(forKey: AppPreferenceKey.autoCheckForUpdates) as? Bool ?? true,
            betaUpdatesEnabled: defaults.object(forKey: AppPreferenceKey.betaUpdatesEnabled) as? Bool ?? false,
            hotkeyDebugLoggingEnabled: defaults.bool(forKey: AppPreferenceKey.hotkeyDebugLoggingEnabled),
            llmDebugLoggingEnabled: defaults.bool(forKey: AppPreferenceKey.llmDebugLoggingEnabled),
            useSystemProxy: defaults.object(forKey: AppPreferenceKey.useSystemProxy) as? Bool ?? true,
            networkProxyMode: defaults.string(forKey: AppPreferenceKey.networkProxyMode) ?? "system",
            customProxyScheme: defaults.string(forKey: AppPreferenceKey.customProxyScheme) ?? "",
            customProxyHost: defaults.string(forKey: AppPreferenceKey.customProxyHost) ?? "",
            customProxyPort: defaults.string(forKey: AppPreferenceKey.customProxyPort) ?? "",
            customProxyUsername: proxyCredentials.username,
            customProxyPassword: sanitizeSensitive(proxyCredentials.password)
        )

        let model = ModelSettings(
            transcriptionEngine: defaults.string(forKey: AppPreferenceKey.transcriptionEngine) ?? TranscriptionEngine.mlxAudio.rawValue,
            enhancementMode: defaults.string(forKey: AppPreferenceKey.enhancementMode) ?? EnhancementMode.off.rawValue,
            enhancementSystemPrompt: AppPromptDefaults.resolvedStoredText(
                defaults.string(forKey: AppPreferenceKey.enhancementSystemPrompt),
                kind: .enhancement,
                defaults: defaults
            ),
            translationSystemPrompt: AppPromptDefaults.resolvedStoredText(
                defaults.string(forKey: AppPreferenceKey.translationSystemPrompt),
                kind: .translation,
                defaults: defaults
            ),
            rewriteSystemPrompt: AppPromptDefaults.resolvedStoredText(
                defaults.string(forKey: AppPreferenceKey.rewriteSystemPrompt),
                kind: .rewrite,
                defaults: defaults
            ),
            asrHintSettings: defaults.string(forKey: AppPreferenceKey.asrHintSettings) ?? ASRHintSettingsStore.defaultStoredValue(),
            whisperLocalASRTuningSettings: defaults.string(forKey: AppPreferenceKey.whisperLocalASRTuningSettings)
                ?? WhisperLocalTuningSettingsStore.defaultStoredValue(),
            mlxLocalASRTuningSettings: defaults.string(forKey: AppPreferenceKey.mlxLocalASRTuningSettings) ?? "{}",
            mlxModelRepo: MLXModelManager.canonicalModelRepo(
                defaults.string(forKey: AppPreferenceKey.mlxModelRepo) ?? MLXModelManager.defaultModelRepo
            ),
            whisperModelID: defaults.string(forKey: AppPreferenceKey.whisperModelID) ?? WhisperKitModelManager.defaultModelID,
            whisperTemperature: defaults.object(forKey: AppPreferenceKey.whisperTemperature) as? Double ?? 0.0,
            whisperVADEnabled: defaults.object(forKey: AppPreferenceKey.whisperVADEnabled) as? Bool ?? true,
            whisperTimestampsEnabled: defaults.object(forKey: AppPreferenceKey.whisperTimestampsEnabled) as? Bool ?? false,
            whisperRealtimeEnabled: defaults.object(forKey: AppPreferenceKey.whisperRealtimeEnabled) as? Bool ?? false,
            localModelIdleUnloadDelaySeconds: AppPreferenceKey.resolvedLocalModelIdleUnloadDelaySeconds(defaults: defaults),
            customLLMModelRepo: defaults.string(forKey: AppPreferenceKey.customLLMModelRepo) ?? CustomLLMModelManager.defaultModelRepo,
            customLLMGenerationSettings: defaults.string(forKey: AppPreferenceKey.customLLMGenerationSettings)
                ?? CustomLLMGenerationSettingsStore.defaultStoredValue(),
            customLLMGenerationSettingsByRepo: defaults.string(forKey: AppPreferenceKey.customLLMGenerationSettingsByRepo)
                ?? CustomLLMGenerationSettingsStore.defaultByRepoStoredValue(),
            translationCustomLLMModelRepo: defaults.string(forKey: AppPreferenceKey.translationCustomLLMModelRepo) ?? CustomLLMModelManager.defaultModelRepo,
            rewriteCustomLLMModelRepo: defaults.string(forKey: AppPreferenceKey.rewriteCustomLLMModelRepo) ?? CustomLLMModelManager.defaultModelRepo,
            translationModelProvider: defaults.string(forKey: AppPreferenceKey.translationModelProvider) ?? TranslationModelProvider.customLLM.rawValue,
            translationFallbackModelProvider: defaults.string(forKey: AppPreferenceKey.translationFallbackModelProvider) ?? TranslationModelProvider.customLLM.rawValue,
            rewriteModelProvider: defaults.string(forKey: AppPreferenceKey.rewriteModelProvider) ?? RewriteModelProvider.customLLM.rawValue,
            remoteASRSelectedProvider: defaults.string(forKey: AppPreferenceKey.remoteASRSelectedProvider) ?? RemoteASRProvider.openAIWhisper.rawValue,
            remoteLLMSelectedProvider: defaults.string(forKey: AppPreferenceKey.remoteLLMSelectedProvider) ?? RemoteLLMProvider.openAI.rawValue,
            translationRemoteLLMProvider: defaults.string(forKey: AppPreferenceKey.translationRemoteLLMProvider) ?? "",
            rewriteRemoteLLMProvider: defaults.string(forKey: AppPreferenceKey.rewriteRemoteLLMProvider) ?? "",
            useHfMirror: defaults.bool(forKey: AppPreferenceKey.useHfMirror),
            remoteASRProviderConfigurations: sanitizeRemoteConfigurations(defaults.string(forKey: AppPreferenceKey.remoteASRProviderConfigurations) ?? ""),
            remoteLLMProviderConfigurations: sanitizeRemoteConfigurations(defaults.string(forKey: AppPreferenceKey.remoteLLMProviderConfigurations) ?? "")
        )

        let dictionary = DictionarySettings(
            recognitionEnabled: defaults.object(forKey: AppPreferenceKey.dictionaryRecognitionEnabled) as? Bool ?? true,
            autoLearningEnabled: defaults.object(forKey: AppPreferenceKey.dictionaryAutoLearningEnabled) as? Bool ?? true,
            autoLearningPrompt: AppPromptDefaults.canonicalStoredText(
                AppPromptDefaults.resolvedStoredText(
                    defaults.string(forKey: AppPreferenceKey.dictionaryAutoLearningPrompt),
                    kind: .dictionaryAutoLearning,
                    defaults: defaults
                ),
                kind: .dictionaryAutoLearning
            ),
            highConfidenceCorrectionEnabled: defaults.object(forKey: AppPreferenceKey.dictionaryHighConfidenceCorrectionEnabled) as? Bool ?? true,
            suggestionFilterSettings: loadDictionarySuggestionFilterSettings(defaults: defaults),
            suggestionIngestModelOptionID: defaults.string(forKey: AppPreferenceKey.dictionarySuggestionIngestModelOptionID) ?? "",
            historyScanCheckpoint: loadDictionaryHistoryScanCheckpoint(defaults: defaults),
            categories: loadDictionaryCategories(environment: environment),
            entries: loadDictionaryEntries(environment: environment),
            suggestions: loadDictionarySuggestions(environment: environment)
        )

        let appBranch = AppBranchSettings(
            appEnhancementEnabled: true,
            groups: loadAppBranchGroups(defaults: defaults),
            urls: loadBranchURLs(defaults: defaults),
            customBrowsersJSON: defaults.string(forKey: AppPreferenceKey.appBranchCustomBrowsers) ?? "[]"
        )

        let hotkey = HotkeySettings(
            hotkeyInputType: defaults.string(forKey: AppPreferenceKey.hotkeyInputType) ?? HotkeyPreference.Hotkey.Input.Kind.keyboard.rawValue,
            hotkeyKeyCode: defaults.integer(forKey: AppPreferenceKey.hotkeyKeyCode),
            hotkeyMouseButtonNumber: defaults.object(forKey: AppPreferenceKey.hotkeyMouseButtonNumber) as? Int,
            hotkeyModifiers: defaults.integer(forKey: AppPreferenceKey.hotkeyModifiers),
            hotkeySidedModifiers: defaults.integer(forKey: AppPreferenceKey.hotkeySidedModifiers),
            translationHotkeyInputType: defaults.string(forKey: AppPreferenceKey.translationHotkeyInputType) ?? HotkeyPreference.Hotkey.Input.Kind.keyboard.rawValue,
            translationHotkeyKeyCode: defaults.integer(forKey: AppPreferenceKey.translationHotkeyKeyCode),
            translationHotkeyMouseButtonNumber: defaults.object(forKey: AppPreferenceKey.translationHotkeyMouseButtonNumber) as? Int,
            translationHotkeyModifiers: defaults.integer(forKey: AppPreferenceKey.translationHotkeyModifiers),
            translationHotkeySidedModifiers: defaults.integer(forKey: AppPreferenceKey.translationHotkeySidedModifiers),
            rewriteHotkeyInputType: defaults.string(forKey: AppPreferenceKey.rewriteHotkeyInputType) ?? HotkeyPreference.Hotkey.Input.Kind.keyboard.rawValue,
            rewriteHotkeyKeyCode: defaults.integer(forKey: AppPreferenceKey.rewriteHotkeyKeyCode),
            rewriteHotkeyMouseButtonNumber: defaults.object(forKey: AppPreferenceKey.rewriteHotkeyMouseButtonNumber) as? Int,
            rewriteHotkeyModifiers: defaults.integer(forKey: AppPreferenceKey.rewriteHotkeyModifiers),
            rewriteHotkeySidedModifiers: defaults.integer(forKey: AppPreferenceKey.rewriteHotkeySidedModifiers),
            customPasteHotkeyInputType: defaults.string(forKey: AppPreferenceKey.customPasteHotkeyInputType) ?? HotkeyPreference.Hotkey.Input.Kind.keyboard.rawValue,
            customPasteHotkeyMouseButtonNumber: defaults.object(forKey: AppPreferenceKey.customPasteHotkeyMouseButtonNumber) as? Int,
            rewriteHotkeyActivationMode: HotkeyPreference.loadRewriteActivationMode(defaults: defaults).rawValue,
            hotkeyTriggerMode: HotkeyPreference.loadTriggerMode(defaults: defaults).rawValue,
            hotkeyDistinguishModifierSides: defaults.object(forKey: AppPreferenceKey.hotkeyDistinguishModifierSides) as? Bool ?? HotkeyPreference.defaultDistinguishModifierSides,
            hotkeyPreset: defaults.string(forKey: AppPreferenceKey.hotkeyPreset) ?? HotkeyPreference.defaultPreset.rawValue,
            escapeKeyCancelsOverlaySession: defaults.object(forKey: AppPreferenceKey.escapeKeyCancelsOverlaySession) as? Bool ?? true
        )

        return ExportPayload(
            version: 20,
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            general: general,
            model: model,
            feature: FeatureSettingsStore.load(defaults: defaults),
            dictionary: dictionary,
            appBranch: appBranch,
            hotkey: hotkey
        )
    }

    private static func apply(
        payload: ExportPayload,
        defaults: UserDefaults,
        environment: FileEnvironment
    ) {
        let general = payload.general
        let model = payload.model
        let dictionary = payload.dictionary
        let appBranch = payload.appBranch
        let hotkey = payload.hotkey

        defaults.set(general.interfaceLanguage, forKey: AppPreferenceKey.interfaceLanguage)
        defaults.set(general.selectedInputDeviceID, forKey: AppPreferenceKey.selectedInputDeviceID)
        if let activeInputDeviceUID = general.activeInputDeviceUID {
            defaults.set(activeInputDeviceUID, forKey: AppPreferenceKey.activeInputDeviceUID)
        } else {
            defaults.removeObject(forKey: AppPreferenceKey.activeInputDeviceUID)
        }
        defaults.removeObject(forKey: "manualSelectedInputDeviceUID")
        defaults.set(general.microphoneAutoSwitchEnabled, forKey: AppPreferenceKey.microphoneAutoSwitchEnabled)
        defaults.set(general.microphonePriorityUIDs, forKey: AppPreferenceKey.microphonePriorityUIDs)
        persistTrackedMicrophoneRecords(general.trackedMicrophoneRecords, defaults: defaults)
        defaults.set(general.modelStorageRootPath, forKey: AppPreferenceKey.modelStorageRootPath)
        defaults.removeObject(forKey: AppPreferenceKey.modelStorageRootBookmark)
        defaults.set(general.interactionSoundsEnabled, forKey: AppPreferenceKey.interactionSoundsEnabled)
        defaults.set(general.interactionSoundPreset, forKey: AppPreferenceKey.interactionSoundPreset)
        defaults.set(general.muteSystemAudioWhileRecording, forKey: AppPreferenceKey.muteSystemAudioWhileRecording)
        defaults.set(general.overlayPosition, forKey: AppPreferenceKey.overlayPosition)
        defaults.set(general.overlayCardOpacity, forKey: AppPreferenceKey.overlayCardOpacity)
        defaults.set(general.overlayCardCornerRadius, forKey: AppPreferenceKey.overlayCardCornerRadius)
        defaults.set(general.overlayScreenEdgeInset, forKey: AppPreferenceKey.overlayScreenEdgeInset)
        defaults.set(general.translationTargetLanguage, forKey: AppPreferenceKey.translationTargetLanguage)
        defaults.set(
            UserMainLanguageOption.storageValue(for: general.userMainLanguageCodes),
            forKey: AppPreferenceKey.userMainLanguageCodes
        )
        defaults.set(true, forKey: AppPreferenceKey.translateSelectedTextOnTranslationHotkey)
        defaults.set(general.voiceEndCommandEnabled, forKey: AppPreferenceKey.voiceEndCommandEnabled)
        defaults.set(general.voiceEndCommandPreset, forKey: AppPreferenceKey.voiceEndCommandPreset)
        defaults.set(general.voiceEndCommandText, forKey: AppPreferenceKey.voiceEndCommandText)
        defaults.set(general.autoCopyWhenNoFocusedInput, forKey: AppPreferenceKey.autoCopyWhenNoFocusedInput)
        defaults.set(general.realtimeTextDisplayEnabled, forKey: AppPreferenceKey.realtimeTextDisplayEnabled)
        defaults.set(general.alwaysShowRewriteAnswerCard, forKey: AppPreferenceKey.alwaysShowRewriteAnswerCard)
        defaults.set(general.launchAtLogin, forKey: AppPreferenceKey.launchAtLogin)
        defaults.set(general.showInDock, forKey: AppPreferenceKey.showInDock)
        defaults.set(true, forKey: AppPreferenceKey.historyEnabled)
        defaults.set(general.historyCleanupEnabled, forKey: AppPreferenceKey.historyCleanupEnabled)
        defaults.set(general.historyRetentionPeriod, forKey: AppPreferenceKey.historyRetentionPeriod)
        defaults.set(general.autoCheckForUpdates, forKey: AppPreferenceKey.autoCheckForUpdates)
        defaults.set(general.betaUpdatesEnabled, forKey: AppPreferenceKey.betaUpdatesEnabled)
        defaults.set(general.hotkeyDebugLoggingEnabled, forKey: AppPreferenceKey.hotkeyDebugLoggingEnabled)
        defaults.set(general.llmDebugLoggingEnabled, forKey: AppPreferenceKey.llmDebugLoggingEnabled)
        defaults.set(general.useSystemProxy, forKey: AppPreferenceKey.useSystemProxy)
        defaults.set(general.networkProxyMode, forKey: AppPreferenceKey.networkProxyMode)
        defaults.set(general.customProxyScheme, forKey: AppPreferenceKey.customProxyScheme)
        defaults.set(general.customProxyHost, forKey: AppPreferenceKey.customProxyHost)
        defaults.set(general.customProxyPort, forKey: AppPreferenceKey.customProxyPort)
        VoxtNetworkSession.setCustomProxyCredentials(
            username: general.customProxyUsername,
            password: resolveImportedSensitive(general.customProxyPassword),
            defaults: defaults
        )

        defaults.set(model.transcriptionEngine, forKey: AppPreferenceKey.transcriptionEngine)
        defaults.set(model.enhancementMode, forKey: AppPreferenceKey.enhancementMode)
        defaults.set(model.enhancementSystemPrompt, forKey: AppPreferenceKey.enhancementSystemPrompt)
        defaults.set(model.translationSystemPrompt, forKey: AppPreferenceKey.translationSystemPrompt)
        defaults.set(model.rewriteSystemPrompt, forKey: AppPreferenceKey.rewriteSystemPrompt)
        defaults.set(model.asrHintSettings, forKey: AppPreferenceKey.asrHintSettings)
        defaults.set(model.whisperLocalASRTuningSettings, forKey: AppPreferenceKey.whisperLocalASRTuningSettings)
        defaults.set(model.mlxLocalASRTuningSettings, forKey: AppPreferenceKey.mlxLocalASRTuningSettings)
        defaults.set(MLXModelManager.canonicalModelRepo(model.mlxModelRepo), forKey: AppPreferenceKey.mlxModelRepo)
        defaults.set(WhisperKitModelManager.canonicalModelID(model.whisperModelID), forKey: AppPreferenceKey.whisperModelID)
        defaults.set(model.whisperTemperature, forKey: AppPreferenceKey.whisperTemperature)
        defaults.set(model.whisperVADEnabled, forKey: AppPreferenceKey.whisperVADEnabled)
        defaults.set(model.whisperTimestampsEnabled, forKey: AppPreferenceKey.whisperTimestampsEnabled)
        defaults.set(model.whisperRealtimeEnabled, forKey: AppPreferenceKey.whisperRealtimeEnabled)
        let clampedIdleUnloadDelay = AppPreferenceKey.clampedLocalModelIdleUnloadDelaySeconds(model.localModelIdleUnloadDelaySeconds)
        let legacyOptimizationEnabled = clampedIdleUnloadDelay <= AppPreferenceKey.defaultLocalModelIdleUnloadDelaySeconds
        defaults.set(clampedIdleUnloadDelay, forKey: AppPreferenceKey.localModelIdleUnloadDelaySeconds)
        defaults.set(legacyOptimizationEnabled, forKey: AppPreferenceKey.localModelMemoryOptimizationEnabled)
        defaults.set(!legacyOptimizationEnabled, forKey: AppPreferenceKey.whisperKeepResidentLoaded)
        defaults.set(model.customLLMModelRepo, forKey: AppPreferenceKey.customLLMModelRepo)
        defaults.set(model.customLLMGenerationSettings, forKey: AppPreferenceKey.customLLMGenerationSettings)
        defaults.set(model.customLLMGenerationSettingsByRepo, forKey: AppPreferenceKey.customLLMGenerationSettingsByRepo)
        defaults.set(model.translationCustomLLMModelRepo, forKey: AppPreferenceKey.translationCustomLLMModelRepo)
        defaults.set(model.rewriteCustomLLMModelRepo, forKey: AppPreferenceKey.rewriteCustomLLMModelRepo)
        defaults.set(model.translationModelProvider, forKey: AppPreferenceKey.translationModelProvider)
        defaults.set(
            TranslationProviderResolver.sanitizedFallbackProvider(
                TranslationModelProvider(rawValue: model.translationFallbackModelProvider) ?? .customLLM
            ).rawValue,
            forKey: AppPreferenceKey.translationFallbackModelProvider
        )
        defaults.set(model.rewriteModelProvider, forKey: AppPreferenceKey.rewriteModelProvider)
        defaults.set(model.remoteASRSelectedProvider, forKey: AppPreferenceKey.remoteASRSelectedProvider)
        defaults.set(model.remoteLLMSelectedProvider, forKey: AppPreferenceKey.remoteLLMSelectedProvider)
        defaults.set(model.translationRemoteLLMProvider, forKey: AppPreferenceKey.translationRemoteLLMProvider)
        defaults.set(model.rewriteRemoteLLMProvider, forKey: AppPreferenceKey.rewriteRemoteLLMProvider)
        defaults.set(model.useHfMirror, forKey: AppPreferenceKey.useHfMirror)
        defaults.set(restoreRemoteConfigurations(model.remoteASRProviderConfigurations), forKey: AppPreferenceKey.remoteASRProviderConfigurations)
        defaults.set(restoreRemoteConfigurations(model.remoteLLMProviderConfigurations), forKey: AppPreferenceKey.remoteLLMProviderConfigurations)

        if let dictionary {
            defaults.set(dictionary.recognitionEnabled, forKey: AppPreferenceKey.dictionaryRecognitionEnabled)
            defaults.set(dictionary.autoLearningEnabled, forKey: AppPreferenceKey.dictionaryAutoLearningEnabled)
            defaults.set(
                AppPromptDefaults.canonicalStoredText(
                    dictionary.autoLearningPrompt,
                    kind: .dictionaryAutoLearning
                ),
                forKey: AppPreferenceKey.dictionaryAutoLearningPrompt
            )
            defaults.set(dictionary.highConfidenceCorrectionEnabled, forKey: AppPreferenceKey.dictionaryHighConfidenceCorrectionEnabled)
            defaults.set(dictionary.suggestionIngestModelOptionID, forKey: AppPreferenceKey.dictionarySuggestionIngestModelOptionID)
            if let suggestionFilterData = try? JSONEncoder().encode(dictionary.suggestionFilterSettings.sanitized()) {
                defaults.set(suggestionFilterData, forKey: AppPreferenceKey.dictionarySuggestionFilterSettings)
            }
            persistDictionaryHistoryScanCheckpoint(dictionary.historyScanCheckpoint, defaults: defaults)
            persistDictionary(
                entries: dictionary.entries,
                categories: dictionary.categories,
                environment: environment
            )
            persistDictionarySuggestions(dictionary.suggestions, environment: environment)
        }

        defaults.set(true, forKey: AppPreferenceKey.appEnhancementEnabled)
        if let groupsData = try? JSONEncoder().encode(appBranch.groups.map {
            AppBranchGroup(
                id: $0.id,
                name: $0.name,
                prompt: $0.prompt,
                appBundleIDs: $0.appBundleIDs,
                appRefs: $0.appRefs,
                urlPatternIDs: $0.urlPatternIDs,
                isExpanded: $0.isExpanded
            )
        }) {
            defaults.set(groupsData, forKey: AppPreferenceKey.appBranchGroups)
        }
        if let urlsData = try? JSONEncoder().encode(appBranch.urls.map { BranchURLItem(id: $0.id, pattern: $0.pattern) }),
           !urlsData.isEmpty {
            defaults.set(urlsData, forKey: AppPreferenceKey.appBranchURLs)
        }
        defaults.set(appBranch.customBrowsersJSON, forKey: AppPreferenceKey.appBranchCustomBrowsers)

        defaults.set(hotkey.hotkeyInputType, forKey: AppPreferenceKey.hotkeyInputType)
        defaults.set(hotkey.hotkeyKeyCode, forKey: AppPreferenceKey.hotkeyKeyCode)
        setOptional(hotkey.hotkeyMouseButtonNumber, forKey: AppPreferenceKey.hotkeyMouseButtonNumber, defaults: defaults)
        defaults.set(hotkey.hotkeyModifiers, forKey: AppPreferenceKey.hotkeyModifiers)
        defaults.set(hotkey.hotkeySidedModifiers, forKey: AppPreferenceKey.hotkeySidedModifiers)
        defaults.set(hotkey.translationHotkeyInputType, forKey: AppPreferenceKey.translationHotkeyInputType)
        defaults.set(hotkey.translationHotkeyKeyCode, forKey: AppPreferenceKey.translationHotkeyKeyCode)
        setOptional(hotkey.translationHotkeyMouseButtonNumber, forKey: AppPreferenceKey.translationHotkeyMouseButtonNumber, defaults: defaults)
        defaults.set(hotkey.translationHotkeyModifiers, forKey: AppPreferenceKey.translationHotkeyModifiers)
        defaults.set(hotkey.translationHotkeySidedModifiers, forKey: AppPreferenceKey.translationHotkeySidedModifiers)
        defaults.set(hotkey.rewriteHotkeyInputType, forKey: AppPreferenceKey.rewriteHotkeyInputType)
        defaults.set(hotkey.rewriteHotkeyKeyCode, forKey: AppPreferenceKey.rewriteHotkeyKeyCode)
        setOptional(hotkey.rewriteHotkeyMouseButtonNumber, forKey: AppPreferenceKey.rewriteHotkeyMouseButtonNumber, defaults: defaults)
        defaults.set(hotkey.rewriteHotkeyModifiers, forKey: AppPreferenceKey.rewriteHotkeyModifiers)
        defaults.set(hotkey.rewriteHotkeySidedModifiers, forKey: AppPreferenceKey.rewriteHotkeySidedModifiers)
        defaults.set(hotkey.customPasteHotkeyInputType, forKey: AppPreferenceKey.customPasteHotkeyInputType)
        setOptional(hotkey.customPasteHotkeyMouseButtonNumber, forKey: AppPreferenceKey.customPasteHotkeyMouseButtonNumber, defaults: defaults)
        let rewriteActivationMode = HotkeyPreference.RewriteActivationMode(
            rawValue: hotkey.rewriteHotkeyActivationMode
        ) ?? HotkeyPreference.defaultRewriteActivationMode
        HotkeyPreference.saveRewriteActivationMode(rewriteActivationMode, defaults: defaults)
        let triggerMode = HotkeyPreference.TriggerMode(rawValue: hotkey.hotkeyTriggerMode)
            ?? HotkeyPreference.defaultTriggerMode
        HotkeyPreference.saveTriggerMode(triggerMode, defaults: defaults)
        defaults.set(hotkey.hotkeyDistinguishModifierSides, forKey: AppPreferenceKey.hotkeyDistinguishModifierSides)
        defaults.set(hotkey.hotkeyPreset, forKey: AppPreferenceKey.hotkeyPreset)
        defaults.set(hotkey.escapeKeyCancelsOverlaySession, forKey: AppPreferenceKey.escapeKeyCancelsOverlaySession)

        let featureSettings = payload.feature ?? FeatureSettingsStore.deriveFromLegacy(defaults: defaults)
        FeatureSettingsStore.save(featureSettings, defaults: defaults)
    }

    private static func setOptional(_ value: Int?, forKey key: String, defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    static func sanitizeSensitive(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : sensitivePlaceholder
    }

    static func resolveImportedSensitive(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == sensitivePlaceholder ? "" : trimmed
    }
}
