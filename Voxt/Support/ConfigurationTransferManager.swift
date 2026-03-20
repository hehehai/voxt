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

    struct FileEnvironment {
        let dictionaryEntriesURL: () throws -> URL
        let dictionarySuggestionsURL: () throws -> URL

        static let live = FileEnvironment(
            dictionaryEntriesURL: { try dictionaryFileURL() },
            dictionarySuggestionsURL: { try dictionarySuggestionsFileURL() }
        )
    }

    struct ExportPayload: Codable {
        var version: Int
        var exportedAt: String
        var general: GeneralSettings
        var model: ModelSettings
        var dictionary: DictionarySettings?
        var appBranch: AppBranchSettings
        var hotkey: HotkeySettings
    }

    struct GeneralSettings: Codable {
        var interfaceLanguage: String
        var selectedInputDeviceID: Int
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
        var alwaysShowRewriteAnswerCard: Bool
        var launchAtLogin: Bool
        var showInDock: Bool
        var historyEnabled: Bool
        var historyRetentionPeriod: String
        var autoCheckForUpdates: Bool
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
            case alwaysShowRewriteAnswerCard
            case launchAtLogin
            case showInDock
            case historyEnabled
            case historyRetentionPeriod
            case autoCheckForUpdates
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

        init(
            interfaceLanguage: String,
            selectedInputDeviceID: Int,
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
            alwaysShowRewriteAnswerCard: Bool,
            launchAtLogin: Bool,
            showInDock: Bool,
            historyEnabled: Bool,
            historyRetentionPeriod: String,
            autoCheckForUpdates: Bool,
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
            self.alwaysShowRewriteAnswerCard = alwaysShowRewriteAnswerCard
            self.launchAtLogin = launchAtLogin
            self.showInDock = showInDock
            self.historyEnabled = historyEnabled
            self.historyRetentionPeriod = historyRetentionPeriod
            self.autoCheckForUpdates = autoCheckForUpdates
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
            selectedInputDeviceID = try container.decode(Int.self, forKey: .selectedInputDeviceID)
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
            translateSelectedTextOnTranslationHotkey = try container.decode(Bool.self, forKey: .translateSelectedTextOnTranslationHotkey)
            voiceEndCommandEnabled = try container.decodeIfPresent(Bool.self, forKey: .voiceEndCommandEnabled) ?? false
            voiceEndCommandPreset = try container.decodeIfPresent(String.self, forKey: .voiceEndCommandPreset) ?? VoiceEndCommandPreset.over.rawValue
            voiceEndCommandText = try container.decodeIfPresent(String.self, forKey: .voiceEndCommandText) ?? ""
            autoCopyWhenNoFocusedInput = try container.decode(Bool.self, forKey: .autoCopyWhenNoFocusedInput)
            alwaysShowRewriteAnswerCard = try container.decodeIfPresent(Bool.self, forKey: .alwaysShowRewriteAnswerCard) ?? false
            launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
            showInDock = try container.decode(Bool.self, forKey: .showInDock)
            historyEnabled = try container.decode(Bool.self, forKey: .historyEnabled)
            historyRetentionPeriod = try container.decode(String.self, forKey: .historyRetentionPeriod)
            autoCheckForUpdates = try container.decode(Bool.self, forKey: .autoCheckForUpdates)
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
    }

    struct ModelSettings: Codable {
        var transcriptionEngine: String
        var enhancementMode: String
        var enhancementSystemPrompt: String
        var translationSystemPrompt: String
        var rewriteSystemPrompt: String
        var asrHintSettings: String
        var mlxModelRepo: String
        var customLLMModelRepo: String
        var translationCustomLLMModelRepo: String
        var rewriteCustomLLMModelRepo: String
        var translationModelProvider: String
        var rewriteModelProvider: String
        var remoteASRSelectedProvider: String
        var remoteLLMSelectedProvider: String
        var translationRemoteLLMProvider: String
        var rewriteRemoteLLMProvider: String
        var useHfMirror: Bool
        var remoteASRProviderConfigurations: [SanitizedRemoteProviderConfiguration]
        var remoteLLMProviderConfigurations: [SanitizedRemoteProviderConfiguration]

        private enum CodingKeys: String, CodingKey {
            case transcriptionEngine
            case enhancementMode
            case enhancementSystemPrompt
            case translationSystemPrompt
            case rewriteSystemPrompt
            case asrHintSettings
            case mlxModelRepo
            case customLLMModelRepo
            case translationCustomLLMModelRepo
            case rewriteCustomLLMModelRepo
            case translationModelProvider
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
            mlxModelRepo: String,
            customLLMModelRepo: String,
            translationCustomLLMModelRepo: String,
            rewriteCustomLLMModelRepo: String,
            translationModelProvider: String,
            rewriteModelProvider: String,
            remoteASRSelectedProvider: String,
            remoteLLMSelectedProvider: String,
            translationRemoteLLMProvider: String,
            rewriteRemoteLLMProvider: String,
            useHfMirror: Bool,
            remoteASRProviderConfigurations: [SanitizedRemoteProviderConfiguration],
            remoteLLMProviderConfigurations: [SanitizedRemoteProviderConfiguration]
        ) {
            self.transcriptionEngine = transcriptionEngine
            self.enhancementMode = enhancementMode
            self.enhancementSystemPrompt = enhancementSystemPrompt
            self.translationSystemPrompt = translationSystemPrompt
            self.rewriteSystemPrompt = rewriteSystemPrompt
            self.asrHintSettings = asrHintSettings
            self.mlxModelRepo = mlxModelRepo
            self.customLLMModelRepo = customLLMModelRepo
            self.translationCustomLLMModelRepo = translationCustomLLMModelRepo
            self.rewriteCustomLLMModelRepo = rewriteCustomLLMModelRepo
            self.translationModelProvider = translationModelProvider
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
            mlxModelRepo = try container.decode(String.self, forKey: .mlxModelRepo)
            customLLMModelRepo = try container.decode(String.self, forKey: .customLLMModelRepo)
            translationCustomLLMModelRepo = try container.decode(String.self, forKey: .translationCustomLLMModelRepo)
            rewriteCustomLLMModelRepo = try container.decode(String.self, forKey: .rewriteCustomLLMModelRepo)
            translationModelProvider = try container.decode(String.self, forKey: .translationModelProvider)
            rewriteModelProvider = try container.decode(String.self, forKey: .rewriteModelProvider)
            remoteASRSelectedProvider = try container.decode(String.self, forKey: .remoteASRSelectedProvider)
            remoteLLMSelectedProvider = try container.decode(String.self, forKey: .remoteLLMSelectedProvider)
            translationRemoteLLMProvider = try container.decode(String.self, forKey: .translationRemoteLLMProvider)
            rewriteRemoteLLMProvider = try container.decode(String.self, forKey: .rewriteRemoteLLMProvider)
            useHfMirror = try container.decode(Bool.self, forKey: .useHfMirror)
            remoteASRProviderConfigurations = try container.decode([SanitizedRemoteProviderConfiguration].self, forKey: .remoteASRProviderConfigurations)
            remoteLLMProviderConfigurations = try container.decode([SanitizedRemoteProviderConfiguration].self, forKey: .remoteLLMProviderConfigurations)
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
        var highConfidenceCorrectionEnabled: Bool
        var suggestionFilterSettings: DictionarySuggestionFilterSettings
        var suggestionIngestModelOptionID: String
        var historyScanCheckpoint: DictionaryHistoryScanCheckpoint?
        var entries: [DictionaryEntry]
        var suggestions: [DictionarySuggestion]

        private enum CodingKeys: String, CodingKey {
            case recognitionEnabled
            case autoLearningEnabled
            case highConfidenceCorrectionEnabled
            case suggestionFilterSettings
            case suggestionIngestModelOptionID
            case historyScanCheckpoint
            case entries
            case suggestions
        }

        init(
            recognitionEnabled: Bool,
            autoLearningEnabled: Bool,
            highConfidenceCorrectionEnabled: Bool,
            suggestionFilterSettings: DictionarySuggestionFilterSettings,
            suggestionIngestModelOptionID: String,
            historyScanCheckpoint: DictionaryHistoryScanCheckpoint?,
            entries: [DictionaryEntry],
            suggestions: [DictionarySuggestion]
        ) {
            self.recognitionEnabled = recognitionEnabled
            self.autoLearningEnabled = autoLearningEnabled
            self.highConfidenceCorrectionEnabled = highConfidenceCorrectionEnabled
            self.suggestionFilterSettings = suggestionFilterSettings
            self.suggestionIngestModelOptionID = suggestionIngestModelOptionID
            self.historyScanCheckpoint = historyScanCheckpoint
            self.entries = entries
            self.suggestions = suggestions
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            recognitionEnabled = try container.decode(Bool.self, forKey: .recognitionEnabled)
            autoLearningEnabled = try container.decode(Bool.self, forKey: .autoLearningEnabled)
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
            entries = try container.decodeIfPresent([DictionaryEntry].self, forKey: .entries) ?? []
            suggestions = try container.decodeIfPresent([DictionarySuggestion].self, forKey: .suggestions) ?? []
        }
    }

    struct HotkeySettings: Codable {
        var hotkeyKeyCode: Int
        var hotkeyModifiers: Int
        var hotkeySidedModifiers: Int
        var translationHotkeyKeyCode: Int
        var translationHotkeyModifiers: Int
        var translationHotkeySidedModifiers: Int
        var rewriteHotkeyKeyCode: Int
        var rewriteHotkeyModifiers: Int
        var rewriteHotkeySidedModifiers: Int
        var hotkeyTriggerMode: String
        var hotkeyDistinguishModifierSides: Bool
        var hotkeyPreset: String
        var escapeKeyCancelsOverlaySession: Bool

        private enum CodingKeys: String, CodingKey {
            case hotkeyKeyCode
            case hotkeyModifiers
            case hotkeySidedModifiers
            case translationHotkeyKeyCode
            case translationHotkeyModifiers
            case translationHotkeySidedModifiers
            case rewriteHotkeyKeyCode
            case rewriteHotkeyModifiers
            case rewriteHotkeySidedModifiers
            case hotkeyTriggerMode
            case hotkeyDistinguishModifierSides
            case hotkeyPreset
            case escapeKeyCancelsOverlaySession
        }

        init(
            hotkeyKeyCode: Int,
            hotkeyModifiers: Int,
            hotkeySidedModifiers: Int,
            translationHotkeyKeyCode: Int,
            translationHotkeyModifiers: Int,
            translationHotkeySidedModifiers: Int,
            rewriteHotkeyKeyCode: Int,
            rewriteHotkeyModifiers: Int,
            rewriteHotkeySidedModifiers: Int,
            hotkeyTriggerMode: String,
            hotkeyDistinguishModifierSides: Bool,
            hotkeyPreset: String,
            escapeKeyCancelsOverlaySession: Bool
        ) {
            self.hotkeyKeyCode = hotkeyKeyCode
            self.hotkeyModifiers = hotkeyModifiers
            self.hotkeySidedModifiers = hotkeySidedModifiers
            self.translationHotkeyKeyCode = translationHotkeyKeyCode
            self.translationHotkeyModifiers = translationHotkeyModifiers
            self.translationHotkeySidedModifiers = translationHotkeySidedModifiers
            self.rewriteHotkeyKeyCode = rewriteHotkeyKeyCode
            self.rewriteHotkeyModifiers = rewriteHotkeyModifiers
            self.rewriteHotkeySidedModifiers = rewriteHotkeySidedModifiers
            self.hotkeyTriggerMode = hotkeyTriggerMode
            self.hotkeyDistinguishModifierSides = hotkeyDistinguishModifierSides
            self.hotkeyPreset = hotkeyPreset
            self.escapeKeyCancelsOverlaySession = escapeKeyCancelsOverlaySession
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            hotkeyKeyCode = try container.decode(Int.self, forKey: .hotkeyKeyCode)
            hotkeyModifiers = try container.decode(Int.self, forKey: .hotkeyModifiers)
            hotkeySidedModifiers = try container.decode(Int.self, forKey: .hotkeySidedModifiers)
            translationHotkeyKeyCode = try container.decode(Int.self, forKey: .translationHotkeyKeyCode)
            translationHotkeyModifiers = try container.decode(Int.self, forKey: .translationHotkeyModifiers)
            translationHotkeySidedModifiers = try container.decode(Int.self, forKey: .translationHotkeySidedModifiers)
            rewriteHotkeyKeyCode = try container.decode(Int.self, forKey: .rewriteHotkeyKeyCode)
            rewriteHotkeyModifiers = try container.decode(Int.self, forKey: .rewriteHotkeyModifiers)
            rewriteHotkeySidedModifiers = try container.decode(Int.self, forKey: .rewriteHotkeySidedModifiers)
            hotkeyTriggerMode = try container.decode(String.self, forKey: .hotkeyTriggerMode)
            hotkeyDistinguishModifierSides = try container.decode(Bool.self, forKey: .hotkeyDistinguishModifierSides)
            hotkeyPreset = try container.decode(String.self, forKey: .hotkeyPreset)
            escapeKeyCancelsOverlaySession = try container.decodeIfPresent(
                Bool.self,
                forKey: .escapeKeyCancelsOverlaySession
            ) ?? true
        }
    }

    struct SanitizedRemoteProviderConfiguration: Codable {
        var providerID: String
        var model: String
        var endpoint: String
        var apiKey: String
        var appID: String
        var accessToken: String
        var openAIChunkPseudoRealtimeEnabled: Bool
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
        customLLMManager: CustomLLMModelManager
    ) -> [MissingConfigurationIssue] {
        var issues: [MissingConfigurationIssue] = []

        let engine = TranscriptionEngine(rawValue: defaults.string(forKey: AppPreferenceKey.transcriptionEngine) ?? "") ?? .mlxAudio
        let enhancementMode = EnhancementMode(rawValue: defaults.string(forKey: AppPreferenceKey.enhancementMode) ?? "") ?? .off
        let selectedRemoteASR = RemoteASRProvider(rawValue: defaults.string(forKey: AppPreferenceKey.remoteASRSelectedProvider) ?? "") ?? .openAIWhisper
        let selectedRemoteLLM = RemoteLLMProvider(rawValue: defaults.string(forKey: AppPreferenceKey.remoteLLMSelectedProvider) ?? "") ?? .openAI
        let remoteASR = RemoteModelConfigurationStore.loadConfigurations(from: defaults.string(forKey: AppPreferenceKey.remoteASRProviderConfigurations) ?? "")
        let remoteLLM = RemoteModelConfigurationStore.loadConfigurations(from: defaults.string(forKey: AppPreferenceKey.remoteLLMProviderConfigurations) ?? "")

        if engine == .mlxAudio {
            let repo = defaults.string(forKey: AppPreferenceKey.mlxModelRepo) ?? MLXModelManager.defaultModelRepo
            if !mlxModelManager.isModelDownloaded(repo: repo) {
                issues.append(.init(scope: .mlxModel(repo), message: AppLocalization.localizedString("Model needs to be installed.")))
            }
        }

        if engine == .remote {
            let config = RemoteModelConfigurationStore.resolvedASRConfiguration(provider: selectedRemoteASR, stored: remoteASR)
            if !config.isConfigured {
                issues.append(.init(scope: .remoteASRProvider(selectedRemoteASR), message: AppLocalization.localizedString("Configuration required.")))
            }
        }

        switch enhancementMode {
        case .customLLM:
            let repo = defaults.string(forKey: AppPreferenceKey.customLLMModelRepo) ?? CustomLLMModelManager.defaultModelRepo
            if !customLLMManager.isModelDownloaded(repo: repo) {
                issues.append(.init(scope: .customLLMModel(repo), message: AppLocalization.localizedString("Model needs to be installed.")))
            }
        case .remoteLLM:
            let config = RemoteModelConfigurationStore.resolvedLLMConfiguration(provider: selectedRemoteLLM, stored: remoteLLM)
            if !config.isConfigured {
                issues.append(.init(scope: .remoteLLMProvider(selectedRemoteLLM), message: AppLocalization.localizedString("Configuration required.")))
            }
        default:
            break
        }

        let translationProvider = TranslationModelProvider(rawValue: defaults.string(forKey: AppPreferenceKey.translationModelProvider) ?? "") ?? .customLLM
        switch translationProvider {
        case .remoteLLM:
            let raw = defaults.string(forKey: AppPreferenceKey.translationRemoteLLMProvider) ?? ""
            if let provider = RemoteLLMProvider(rawValue: raw.isEmpty ? selectedRemoteLLM.rawValue : raw) {
                let config = RemoteModelConfigurationStore.resolvedLLMConfiguration(provider: provider, stored: remoteLLM)
                if !config.isConfigured {
                    issues.append(.init(scope: .translationRemoteLLM(provider), message: AppLocalization.localizedString("Configuration required.")))
                }
            }
        case .customLLM:
            let repo = defaults.string(forKey: AppPreferenceKey.translationCustomLLMModelRepo) ?? CustomLLMModelManager.defaultModelRepo
            if !customLLMManager.isModelDownloaded(repo: repo) {
                issues.append(.init(scope: .translationCustomLLM(repo), message: AppLocalization.localizedString("Model needs to be installed.")))
            }
        }

        let rewriteProvider = RewriteModelProvider(rawValue: defaults.string(forKey: AppPreferenceKey.rewriteModelProvider) ?? "") ?? .customLLM
        switch rewriteProvider {
        case .remoteLLM:
            let raw = defaults.string(forKey: AppPreferenceKey.rewriteRemoteLLMProvider) ?? ""
            if let provider = RemoteLLMProvider(rawValue: raw.isEmpty ? selectedRemoteLLM.rawValue : raw) {
                let config = RemoteModelConfigurationStore.resolvedLLMConfiguration(provider: provider, stored: remoteLLM)
                if !config.isConfigured {
                    issues.append(.init(scope: .rewriteRemoteLLM(provider), message: AppLocalization.localizedString("Configuration required.")))
                }
            }
        case .customLLM:
            let repo = defaults.string(forKey: AppPreferenceKey.rewriteCustomLLMModelRepo) ?? CustomLLMModelManager.defaultModelRepo
            if !customLLMManager.isModelDownloaded(repo: repo) {
                issues.append(.init(scope: .rewriteCustomLLM(repo), message: AppLocalization.localizedString("Model needs to be installed.")))
            }
        }

        return Array(Set(issues)).sorted { $0.id < $1.id }
    }

    private static func makeExportPayload(
        defaults: UserDefaults,
        environment: FileEnvironment
    ) -> ExportPayload {
        let general = GeneralSettings(
            interfaceLanguage: defaults.string(forKey: AppPreferenceKey.interfaceLanguage) ?? AppInterfaceLanguage.system.rawValue,
            selectedInputDeviceID: defaults.integer(forKey: AppPreferenceKey.selectedInputDeviceID),
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
            translateSelectedTextOnTranslationHotkey: defaults.object(forKey: AppPreferenceKey.translateSelectedTextOnTranslationHotkey) as? Bool ?? true,
            voiceEndCommandEnabled: defaults.object(forKey: AppPreferenceKey.voiceEndCommandEnabled) as? Bool ?? false,
            voiceEndCommandPreset: defaults.string(forKey: AppPreferenceKey.voiceEndCommandPreset) ?? VoiceEndCommandPreset.over.rawValue,
            voiceEndCommandText: defaults.string(forKey: AppPreferenceKey.voiceEndCommandText) ?? "",
            autoCopyWhenNoFocusedInput: defaults.bool(forKey: AppPreferenceKey.autoCopyWhenNoFocusedInput),
            alwaysShowRewriteAnswerCard: defaults.bool(forKey: AppPreferenceKey.alwaysShowRewriteAnswerCard),
            launchAtLogin: defaults.bool(forKey: AppPreferenceKey.launchAtLogin),
            showInDock: defaults.bool(forKey: AppPreferenceKey.showInDock),
            historyEnabled: defaults.object(forKey: AppPreferenceKey.historyEnabled) as? Bool ?? true,
            historyRetentionPeriod: defaults.string(forKey: AppPreferenceKey.historyRetentionPeriod) ?? HistoryRetentionPeriod.forever.rawValue,
            autoCheckForUpdates: defaults.object(forKey: AppPreferenceKey.autoCheckForUpdates) as? Bool ?? true,
            hotkeyDebugLoggingEnabled: defaults.bool(forKey: AppPreferenceKey.hotkeyDebugLoggingEnabled),
            llmDebugLoggingEnabled: defaults.bool(forKey: AppPreferenceKey.llmDebugLoggingEnabled),
            useSystemProxy: defaults.object(forKey: AppPreferenceKey.useSystemProxy) as? Bool ?? true,
            networkProxyMode: defaults.string(forKey: AppPreferenceKey.networkProxyMode) ?? "system",
            customProxyScheme: defaults.string(forKey: AppPreferenceKey.customProxyScheme) ?? "",
            customProxyHost: defaults.string(forKey: AppPreferenceKey.customProxyHost) ?? "",
            customProxyPort: defaults.string(forKey: AppPreferenceKey.customProxyPort) ?? "",
            customProxyUsername: defaults.string(forKey: AppPreferenceKey.customProxyUsername) ?? "",
            customProxyPassword: sanitizeSensitive(defaults.string(forKey: AppPreferenceKey.customProxyPassword) ?? "")
        )

        return ExportPayload(
            version: 9,
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            general: general,
            model: .init(
                transcriptionEngine: defaults.string(forKey: AppPreferenceKey.transcriptionEngine) ?? TranscriptionEngine.mlxAudio.rawValue,
                enhancementMode: defaults.string(forKey: AppPreferenceKey.enhancementMode) ?? EnhancementMode.off.rawValue,
                enhancementSystemPrompt: defaults.string(forKey: AppPreferenceKey.enhancementSystemPrompt) ?? AppPreferenceKey.defaultEnhancementPrompt,
                translationSystemPrompt: defaults.string(forKey: AppPreferenceKey.translationSystemPrompt) ?? AppPreferenceKey.defaultTranslationPrompt,
                rewriteSystemPrompt: defaults.string(forKey: AppPreferenceKey.rewriteSystemPrompt) ?? AppPreferenceKey.defaultRewritePrompt,
                asrHintSettings: defaults.string(forKey: AppPreferenceKey.asrHintSettings) ?? ASRHintSettingsStore.defaultStoredValue(),
                mlxModelRepo: defaults.string(forKey: AppPreferenceKey.mlxModelRepo) ?? MLXModelManager.defaultModelRepo,
                customLLMModelRepo: defaults.string(forKey: AppPreferenceKey.customLLMModelRepo) ?? CustomLLMModelManager.defaultModelRepo,
                translationCustomLLMModelRepo: defaults.string(forKey: AppPreferenceKey.translationCustomLLMModelRepo) ?? CustomLLMModelManager.defaultModelRepo,
                rewriteCustomLLMModelRepo: defaults.string(forKey: AppPreferenceKey.rewriteCustomLLMModelRepo) ?? CustomLLMModelManager.defaultModelRepo,
                translationModelProvider: defaults.string(forKey: AppPreferenceKey.translationModelProvider) ?? TranslationModelProvider.customLLM.rawValue,
                rewriteModelProvider: defaults.string(forKey: AppPreferenceKey.rewriteModelProvider) ?? RewriteModelProvider.customLLM.rawValue,
                remoteASRSelectedProvider: defaults.string(forKey: AppPreferenceKey.remoteASRSelectedProvider) ?? RemoteASRProvider.openAIWhisper.rawValue,
                remoteLLMSelectedProvider: defaults.string(forKey: AppPreferenceKey.remoteLLMSelectedProvider) ?? RemoteLLMProvider.openAI.rawValue,
                translationRemoteLLMProvider: defaults.string(forKey: AppPreferenceKey.translationRemoteLLMProvider) ?? "",
                rewriteRemoteLLMProvider: defaults.string(forKey: AppPreferenceKey.rewriteRemoteLLMProvider) ?? "",
                useHfMirror: defaults.bool(forKey: AppPreferenceKey.useHfMirror),
                remoteASRProviderConfigurations: sanitizeRemoteConfigurations(defaults.string(forKey: AppPreferenceKey.remoteASRProviderConfigurations) ?? ""),
                remoteLLMProviderConfigurations: sanitizeRemoteConfigurations(defaults.string(forKey: AppPreferenceKey.remoteLLMProviderConfigurations) ?? "")
            ),
            dictionary: .init(
                recognitionEnabled: defaults.object(forKey: AppPreferenceKey.dictionaryRecognitionEnabled) as? Bool ?? true,
                autoLearningEnabled: defaults.object(forKey: AppPreferenceKey.dictionaryAutoLearningEnabled) as? Bool ?? true,
                highConfidenceCorrectionEnabled: defaults.object(forKey: AppPreferenceKey.dictionaryHighConfidenceCorrectionEnabled) as? Bool ?? true,
                suggestionFilterSettings: loadDictionarySuggestionFilterSettings(defaults: defaults),
                suggestionIngestModelOptionID: defaults.string(forKey: AppPreferenceKey.dictionarySuggestionIngestModelOptionID) ?? "",
                historyScanCheckpoint: loadDictionaryHistoryScanCheckpoint(defaults: defaults),
                entries: loadDictionaryEntries(environment: environment),
                suggestions: loadDictionarySuggestions(environment: environment)
            ),
            appBranch: .init(
                appEnhancementEnabled: defaults.bool(forKey: AppPreferenceKey.appEnhancementEnabled),
                groups: loadAppBranchGroups(defaults: defaults),
                urls: loadBranchURLs(defaults: defaults),
                customBrowsersJSON: defaults.string(forKey: AppPreferenceKey.appBranchCustomBrowsers) ?? "[]"
            ),
            hotkey: .init(
                hotkeyKeyCode: defaults.integer(forKey: AppPreferenceKey.hotkeyKeyCode),
                hotkeyModifiers: defaults.integer(forKey: AppPreferenceKey.hotkeyModifiers),
                hotkeySidedModifiers: defaults.integer(forKey: AppPreferenceKey.hotkeySidedModifiers),
                translationHotkeyKeyCode: defaults.integer(forKey: AppPreferenceKey.translationHotkeyKeyCode),
                translationHotkeyModifiers: defaults.integer(forKey: AppPreferenceKey.translationHotkeyModifiers),
                translationHotkeySidedModifiers: defaults.integer(forKey: AppPreferenceKey.translationHotkeySidedModifiers),
                rewriteHotkeyKeyCode: defaults.integer(forKey: AppPreferenceKey.rewriteHotkeyKeyCode),
                rewriteHotkeyModifiers: defaults.integer(forKey: AppPreferenceKey.rewriteHotkeyModifiers),
                rewriteHotkeySidedModifiers: defaults.integer(forKey: AppPreferenceKey.rewriteHotkeySidedModifiers),
                hotkeyTriggerMode: defaults.string(forKey: AppPreferenceKey.hotkeyTriggerMode) ?? HotkeyPreference.defaultTriggerMode.rawValue,
                hotkeyDistinguishModifierSides: defaults.object(forKey: AppPreferenceKey.hotkeyDistinguishModifierSides) as? Bool ?? HotkeyPreference.defaultDistinguishModifierSides,
                hotkeyPreset: defaults.string(forKey: AppPreferenceKey.hotkeyPreset) ?? HotkeyPreference.defaultPreset.rawValue,
                escapeKeyCancelsOverlaySession: defaults.object(forKey: AppPreferenceKey.escapeKeyCancelsOverlaySession) as? Bool ?? true
            )
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
        defaults.set(general.translateSelectedTextOnTranslationHotkey, forKey: AppPreferenceKey.translateSelectedTextOnTranslationHotkey)
        defaults.set(general.voiceEndCommandEnabled, forKey: AppPreferenceKey.voiceEndCommandEnabled)
        defaults.set(general.voiceEndCommandPreset, forKey: AppPreferenceKey.voiceEndCommandPreset)
        defaults.set(general.voiceEndCommandText, forKey: AppPreferenceKey.voiceEndCommandText)
        defaults.set(general.autoCopyWhenNoFocusedInput, forKey: AppPreferenceKey.autoCopyWhenNoFocusedInput)
        defaults.set(general.alwaysShowRewriteAnswerCard, forKey: AppPreferenceKey.alwaysShowRewriteAnswerCard)
        defaults.set(general.launchAtLogin, forKey: AppPreferenceKey.launchAtLogin)
        defaults.set(general.showInDock, forKey: AppPreferenceKey.showInDock)
        defaults.set(general.historyEnabled, forKey: AppPreferenceKey.historyEnabled)
        defaults.set(general.historyRetentionPeriod, forKey: AppPreferenceKey.historyRetentionPeriod)
        defaults.set(general.autoCheckForUpdates, forKey: AppPreferenceKey.autoCheckForUpdates)
        defaults.set(general.hotkeyDebugLoggingEnabled, forKey: AppPreferenceKey.hotkeyDebugLoggingEnabled)
        defaults.set(general.llmDebugLoggingEnabled, forKey: AppPreferenceKey.llmDebugLoggingEnabled)
        defaults.set(general.useSystemProxy, forKey: AppPreferenceKey.useSystemProxy)
        defaults.set(general.networkProxyMode, forKey: AppPreferenceKey.networkProxyMode)
        defaults.set(general.customProxyScheme, forKey: AppPreferenceKey.customProxyScheme)
        defaults.set(general.customProxyHost, forKey: AppPreferenceKey.customProxyHost)
        defaults.set(general.customProxyPort, forKey: AppPreferenceKey.customProxyPort)
        defaults.set(general.customProxyUsername, forKey: AppPreferenceKey.customProxyUsername)
        defaults.set(resolveImportedSensitive(general.customProxyPassword), forKey: AppPreferenceKey.customProxyPassword)

        defaults.set(model.transcriptionEngine, forKey: AppPreferenceKey.transcriptionEngine)
        defaults.set(model.enhancementMode, forKey: AppPreferenceKey.enhancementMode)
        defaults.set(model.enhancementSystemPrompt, forKey: AppPreferenceKey.enhancementSystemPrompt)
        defaults.set(model.translationSystemPrompt, forKey: AppPreferenceKey.translationSystemPrompt)
        defaults.set(model.rewriteSystemPrompt, forKey: AppPreferenceKey.rewriteSystemPrompt)
        defaults.set(model.asrHintSettings, forKey: AppPreferenceKey.asrHintSettings)
        defaults.set(model.mlxModelRepo, forKey: AppPreferenceKey.mlxModelRepo)
        defaults.set(model.customLLMModelRepo, forKey: AppPreferenceKey.customLLMModelRepo)
        defaults.set(model.translationCustomLLMModelRepo, forKey: AppPreferenceKey.translationCustomLLMModelRepo)
        defaults.set(model.rewriteCustomLLMModelRepo, forKey: AppPreferenceKey.rewriteCustomLLMModelRepo)
        defaults.set(model.translationModelProvider, forKey: AppPreferenceKey.translationModelProvider)
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
            defaults.set(dictionary.highConfidenceCorrectionEnabled, forKey: AppPreferenceKey.dictionaryHighConfidenceCorrectionEnabled)
            defaults.set(dictionary.suggestionIngestModelOptionID, forKey: AppPreferenceKey.dictionarySuggestionIngestModelOptionID)
            if let suggestionFilterData = try? JSONEncoder().encode(dictionary.suggestionFilterSettings.sanitized()) {
                defaults.set(suggestionFilterData, forKey: AppPreferenceKey.dictionarySuggestionFilterSettings)
            }
            persistDictionaryHistoryScanCheckpoint(dictionary.historyScanCheckpoint, defaults: defaults)
            persistDictionaryEntries(dictionary.entries, environment: environment)
            persistDictionarySuggestions(dictionary.suggestions, environment: environment)
        }

        defaults.set(appBranch.appEnhancementEnabled, forKey: AppPreferenceKey.appEnhancementEnabled)
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

        defaults.set(hotkey.hotkeyKeyCode, forKey: AppPreferenceKey.hotkeyKeyCode)
        defaults.set(hotkey.hotkeyModifiers, forKey: AppPreferenceKey.hotkeyModifiers)
        defaults.set(hotkey.hotkeySidedModifiers, forKey: AppPreferenceKey.hotkeySidedModifiers)
        defaults.set(hotkey.translationHotkeyKeyCode, forKey: AppPreferenceKey.translationHotkeyKeyCode)
        defaults.set(hotkey.translationHotkeyModifiers, forKey: AppPreferenceKey.translationHotkeyModifiers)
        defaults.set(hotkey.translationHotkeySidedModifiers, forKey: AppPreferenceKey.translationHotkeySidedModifiers)
        defaults.set(hotkey.rewriteHotkeyKeyCode, forKey: AppPreferenceKey.rewriteHotkeyKeyCode)
        defaults.set(hotkey.rewriteHotkeyModifiers, forKey: AppPreferenceKey.rewriteHotkeyModifiers)
        defaults.set(hotkey.rewriteHotkeySidedModifiers, forKey: AppPreferenceKey.rewriteHotkeySidedModifiers)
        defaults.set(hotkey.hotkeyTriggerMode, forKey: AppPreferenceKey.hotkeyTriggerMode)
        defaults.set(hotkey.hotkeyDistinguishModifierSides, forKey: AppPreferenceKey.hotkeyDistinguishModifierSides)
        defaults.set(hotkey.hotkeyPreset, forKey: AppPreferenceKey.hotkeyPreset)
        defaults.set(hotkey.escapeKeyCancelsOverlaySession, forKey: AppPreferenceKey.escapeKeyCancelsOverlaySession)
    }

    private static func sanitizeRemoteConfigurations(_ raw: String) -> [SanitizedRemoteProviderConfiguration] {
        let stored = RemoteModelConfigurationStore.loadConfigurations(from: raw)
        return stored.values.sorted(by: { $0.providerID < $1.providerID }).map {
            SanitizedRemoteProviderConfiguration(
                providerID: $0.providerID,
                model: $0.model,
                endpoint: $0.endpoint,
                apiKey: sanitizeSensitive($0.apiKey),
                appID: sanitizeSensitive($0.appID),
                accessToken: sanitizeSensitive($0.accessToken),
                openAIChunkPseudoRealtimeEnabled: $0.openAIChunkPseudoRealtimeEnabled
            )
        }
    }

    private static func restoreRemoteConfigurations(_ values: [SanitizedRemoteProviderConfiguration]) -> String {
        let mapped = Dictionary(uniqueKeysWithValues: values.map { item in
            (
                item.providerID,
                RemoteProviderConfiguration(
                    providerID: item.providerID,
                    model: item.model,
                    endpoint: item.endpoint,
                    apiKey: resolveImportedSensitive(item.apiKey),
                    appID: resolveImportedSensitive(item.appID),
                    accessToken: resolveImportedSensitive(item.accessToken),
                    openAIChunkPseudoRealtimeEnabled: item.openAIChunkPseudoRealtimeEnabled
                )
            )
        })
        return RemoteModelConfigurationStore.saveConfigurations(mapped)
    }

    private static func loadAppBranchGroups(defaults: UserDefaults) -> [ExportedAppBranchGroup] {
        guard let data = defaults.data(forKey: AppPreferenceKey.appBranchGroups),
              let groups = try? JSONDecoder().decode([AppBranchGroup].self, from: data)
        else {
            return []
        }
        return groups.map {
            ExportedAppBranchGroup(
                id: $0.id,
                name: $0.name,
                prompt: $0.prompt,
                appBundleIDs: $0.appBundleIDs,
                appRefs: $0.appRefs,
                urlPatternIDs: $0.urlPatternIDs,
                isExpanded: $0.isExpanded,
                iconPlaceholder: "app-icon-placeholder"
            )
        }
    }

    private static func loadBranchURLs(defaults: UserDefaults) -> [ExportedBranchURLItem] {
        guard let data = defaults.data(forKey: AppPreferenceKey.appBranchURLs),
              let urls = try? JSONDecoder().decode([BranchURLItem].self, from: data)
        else {
            return []
        }
        return urls.map { ExportedBranchURLItem(id: $0.id, pattern: $0.pattern, iconPlaceholder: "url-icon-placeholder") }
    }

    private static func loadDictionaryEntries(environment: FileEnvironment) -> [DictionaryEntry] {
        guard let url = try? environment.dictionaryEntriesURL(),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([DictionaryEntry].self, from: data)
        else {
            return []
        }
        return entries
    }

    private static func loadDictionarySuggestionFilterSettings(
        defaults: UserDefaults
    ) -> DictionarySuggestionFilterSettings {
        guard
            let data = defaults.data(forKey: AppPreferenceKey.dictionarySuggestionFilterSettings),
            let settings = try? JSONDecoder().decode(DictionarySuggestionFilterSettings.self, from: data)
        else {
            return .defaultValue
        }
        return settings.sanitized()
    }

    private static func loadDictionaryHistoryScanCheckpoint(
        defaults: UserDefaults
    ) -> DictionaryHistoryScanCheckpoint? {
        guard
            let data = defaults.data(forKey: AppPreferenceKey.dictionarySuggestionHistoryScanCheckpoint),
            let checkpoint = try? JSONDecoder().decode(DictionaryHistoryScanCheckpoint.self, from: data)
        else {
            return nil
        }
        return checkpoint
    }

    private static func persistDictionaryHistoryScanCheckpoint(
        _ checkpoint: DictionaryHistoryScanCheckpoint?,
        defaults: UserDefaults
    ) {
        guard let checkpoint else {
            defaults.removeObject(forKey: AppPreferenceKey.dictionarySuggestionHistoryScanCheckpoint)
            return
        }

        guard let data = try? JSONEncoder().encode(checkpoint) else {
            defaults.removeObject(forKey: AppPreferenceKey.dictionarySuggestionHistoryScanCheckpoint)
            return
        }
        defaults.set(data, forKey: AppPreferenceKey.dictionarySuggestionHistoryScanCheckpoint)
    }

    private static func persistDictionaryEntries(
        _ entries: [DictionaryEntry],
        environment: FileEnvironment
    ) {
        guard let url = try? environment.dictionaryEntriesURL(),
              let data = try? JSONEncoder().encode(entries)
        else {
            return
        }

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Ignore config import dictionary persistence failures.
        }
    }

    private static func loadDictionarySuggestions(environment: FileEnvironment) -> [DictionarySuggestion] {
        guard let url = try? environment.dictionarySuggestionsURL(),
              let data = try? Data(contentsOf: url),
              let suggestions = try? JSONDecoder().decode([DictionarySuggestion].self, from: data)
        else {
            return []
        }
        return suggestions
    }

    private static func persistDictionarySuggestions(
        _ suggestions: [DictionarySuggestion],
        environment: FileEnvironment
    ) {
        guard let url = try? environment.dictionarySuggestionsURL(),
              let data = try? JSONEncoder().encode(suggestions)
        else {
            return
        }

        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Ignore config import dictionary persistence failures.
        }
    }

    private static func sanitizeSensitive(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : sensitivePlaceholder
    }

    private static func resolveImportedSensitive(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == sensitivePlaceholder ? "" : trimmed
    }

    private static func dictionaryFileURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("Voxt", isDirectory: true)
            .appendingPathComponent("dictionary.json")
    }

    private static func dictionarySuggestionsFileURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("Voxt", isDirectory: true)
            .appendingPathComponent("dictionary-suggestions.json")
    }
}
