// AppPreferenceKey.swift
// Provides App Preference Key for settings shell.

import Foundation

enum AppPreferenceKey {
    static let transcriptionEngine = "transcriptionEngine"
    static let enhancementMode = "enhancementMode"
    static let enhancementSystemPrompt = "enhancementSystemPrompt"
    static let translationSystemPrompt = "translationSystemPrompt"
    static let mlxModelRepo = "mlxModelRepo"
    static let legacyWhisperModelID = "whisperModelID"
    static let localModelIdleUnloadDelaySeconds = "localModelIdleUnloadDelaySeconds"
    static let localModelMemoryOptimizationEnabled = "localModelMemoryOptimizationEnabled"
    static let legacyWhisperKeepResidentLoaded = "whisperKeepResidentLoaded"
    static let customLLMModelRepo = "customLLMModelRepo"
    static let customLLMGenerationSettings = "customLLMGenerationSettings"
    static let customLLMGenerationSettingsByRepo = "customLLMGenerationSettingsByRepo"
    static let translationCustomLLMModelRepo = "translationCustomLLMModelRepo"
    static let translationGGUFModelID = "translationGGUFModelID"
    static let translationModelProvider = "translationModelProvider"
    static let translationFallbackModelProvider = "translationFallbackModelProvider"
    static let rewriteSystemPrompt = "rewriteSystemPrompt"
    static let rewriteCustomLLMModelRepo = "rewriteCustomLLMModelRepo"
    static let rewriteModelProvider = "rewriteModelProvider"
    static let remoteASRSelectedProvider = "remoteASRSelectedProvider"
    static let remoteASRProviderConfigurations = "remoteASRProviderConfigurations"
    static let remoteLLMSelectedProvider = "remoteLLMSelectedProvider"
    static let remoteLLMProviderConfigurations = "remoteLLMProviderConfigurations"
    static let translationRemoteLLMProvider = "translationRemoteLLMProvider"
    static let rewriteRemoteLLMProvider = "rewriteRemoteLLMProvider"
    static let asrHintSettings = "asrHintSettings"
    static let mlxLocalASRTuningSettings = "mlxLocalASRTuningSettings"
    static let modelStorageRootPath = "modelStorageRootPath"
    static let modelStorageRootBookmark = "modelStorageRootBookmark"
    static let useHfMirror = "useHfMirror"
    static let hotkeyInputType = "hotkeyInputType"
    static let hotkeyKeyCode = "hotkeyKeyCode"
    static let hotkeyMouseButtonNumber = "hotkeyMouseButtonNumber"
    static let hotkeyModifiers = "hotkeyModifiers"
    static let hotkeySidedModifiers = "hotkeySidedModifiers"
    static let translationHotkeyInputType = "translationHotkeyInputType"
    static let translationHotkeyKeyCode = "translationHotkeyKeyCode"
    static let translationHotkeyMouseButtonNumber = "translationHotkeyMouseButtonNumber"
    static let translationHotkeyModifiers = "translationHotkeyModifiers"
    static let translationHotkeySidedModifiers = "translationHotkeySidedModifiers"
    static let rewriteHotkeyInputType = "rewriteHotkeyInputType"
    static let rewriteHotkeyKeyCode = "rewriteHotkeyKeyCode"
    static let rewriteHotkeyMouseButtonNumber = "rewriteHotkeyMouseButtonNumber"
    static let rewriteHotkeyModifiers = "rewriteHotkeyModifiers"
    static let rewriteHotkeySidedModifiers = "rewriteHotkeySidedModifiers"
    static let meetingHotkeyInputType = "meetingHotkeyInputType"
    static let meetingHotkeyKeyCode = "meetingHotkeyKeyCode"
    static let meetingHotkeyMouseButtonNumber = "meetingHotkeyMouseButtonNumber"
    static let meetingHotkeyModifiers = "meetingHotkeyModifiers"
    static let meetingHotkeySidedModifiers = "meetingHotkeySidedModifiers"
    static let customPasteHotkeyInputType = "customPasteHotkeyInputType"
    static let customPasteHotkeyMouseButtonNumber = "customPasteHotkeyMouseButtonNumber"
    static let rewriteHotkeyActivationMode = "rewriteHotkeyActivationMode"
    static let hotkeyTriggerMode = "hotkeyTriggerMode"
    static let hotkeyDistinguishModifierSides = "hotkeyDistinguishModifierSides"
    static let hotkeyPreset = "hotkeyPreset"
    static let escapeKeyCancelsOverlaySession = "escapeKeyCancelsOverlaySession"
    static let hotkeyCaptureInProgress = "hotkeyCaptureInProgress"
    static let selectedInputDeviceID = "selectedInputDeviceID"
    static let activeInputDeviceUID = "activeInputDeviceUID"
    static let microphoneAutoSwitchEnabled = "microphoneAutoSwitchEnabled"
    static let microphonePriorityUIDs = "microphonePriorityUIDs"
    static let trackedMicrophoneRecords = "trackedMicrophoneRecords"
    static let interactionSoundsEnabled = "interactionSoundsEnabled"
    static let interactionSoundPreset = "interactionSoundPreset"
    static let muteSystemAudioWhileRecording = "muteSystemAudioWhileRecording"
    static let overlayPosition = "overlayPosition"
    static let overlayCardOpacity = "overlayCardOpacity"
    static let overlayCardCornerRadius = "overlayCardCornerRadius"
    static let overlayScreenEdgeInset = "overlayScreenEdgeInset"
    static let interfaceLanguage = "interfaceLanguage"
    static let translationTargetLanguage = "translationTargetLanguage"
    static let userMainLanguageCodes = "userMainLanguageCodes"
    static let translateSelectedTextOnTranslationHotkey = "translateSelectedTextOnTranslationHotkey"
    static let showSelectedTextTranslationResultWindow = "showSelectedTextTranslationResultWindow"
    static let customPasteHotkeyEnabled = "customPasteHotkeyEnabled"
    static let customPasteHotkeyKeyCode = "customPasteHotkeyKeyCode"
    static let customPasteHotkeyModifiers = "customPasteHotkeyModifiers"
    static let customPasteHotkeySidedModifiers = "customPasteHotkeySidedModifiers"
    static let transcriptionHotkeyBindings = "transcriptionHotkeyBindings"
    static let translationHotkeyBindings = "translationHotkeyBindings"
    static let meetingHotkeyBindings = "meetingHotkeyBindings"
    static let rewriteHotkeyBindings = "rewriteHotkeyBindings"
    static let transcriptSummaryPromptTemplate = "transcriptSummaryPromptTemplate"
    static let transcriptSummaryModelSelection = "transcriptSummaryModelSelection"
    static let hideMeetingOverlayFromScreenSharing = "hideMeetingOverlayFromScreenSharing"
    static let meetingOverlayCollapsed = "meetingOverlayCollapsed"
    static let meetingCaptureMode = "meetingCaptureMode"
    static let meetingChunkingMode = "meetingChunkingMode"
    nonisolated static let meetingServerVADMode = "meetingServerVADMode"
    nonisolated static let meetingSpeakerDiarizationSensitivity = "meetingSpeakerDiarizationSensitivity"
    nonisolated static let meetingSpeakerDiarizationDebugEnabled = "meetingSpeakerDiarizationDebugEnabled"
    nonisolated static let meetingSpeakerDiarizationModel = "meetingSpeakerDiarizationModel"
    nonisolated static let meetingRealtimeDiarizationMode = "meetingRealtimeDiarizationMode"
    static let meetingFinalTranscriptOptimizationEnabled = "meetingFinalTranscriptOptimizationEnabled"
    static let meetingRealtimeTranslateEnabled = "meetingRealtimeTranslateEnabled"
    static let meetingRealtimeTranslationTargetLanguage = "meetingRealtimeTranslationTargetLanguage"
    static let voiceEndCommandEnabled = "voiceEndCommandEnabled"
    static let voiceEndCommandPreset = "voiceEndCommandPreset"
    static let voiceEndCommandText = "voiceEndCommandText"
    static let autoCopyWhenNoFocusedInput = "autoCopyWhenNoFocusedInput"
    static let realtimeTextDisplayEnabled = "realtimeTextDisplayEnabled"
    static let alwaysShowRewriteAnswerCard = "alwaysShowRewriteAnswerCard"
    static let appEnhancementEnabled = "appEnhancementEnabled"
    static let appBranchGroups = "appBranchGroups"
    static let appBranchURLs = "appBranchURLs"
    static let appBranchCustomBrowsers = "appBranchCustomBrowsers"
    static let featureSettings = "featureSettings"
    static let mlxRemoteSizeCache = "mlxRemoteSizeCache"
    static let customLLMRemoteSizeCache = "customLLMRemoteSizeCache"
    static let launchAtLogin = "launchAtLogin"
    static let showInDock = "showInDock"
    static let historyEnabled = "historyEnabled"
    static let historyCleanupEnabled = "historyCleanupEnabled"
    static let historyRetentionPeriod = "historyRetentionPeriod"
    static let historyAudioStorageEnabled = "historyAudioStorageEnabled"
    static let historyAudioStorageRootPath = "historyAudioStorageRootPath"
    static let historyAudioStorageRootBookmark = "historyAudioStorageRootBookmark"

    static let localModelIdleUnloadDelayMinimumSeconds = 10
    static let localModelIdleUnloadDelayMaximumSeconds = 1200
    static let defaultLocalModelIdleUnloadDelaySeconds = 90
    static let legacyLongLocalModelIdleUnloadDelaySeconds = 120

    static func clampedLocalModelIdleUnloadDelaySeconds(_ value: Int) -> Int {
        min(max(value, localModelIdleUnloadDelayMinimumSeconds), localModelIdleUnloadDelayMaximumSeconds)
    }

    static func resolvedLocalModelIdleUnloadDelaySeconds(defaults: UserDefaults = .standard) -> Int {
        if let stored = defaults.object(forKey: localModelIdleUnloadDelaySeconds) as? Int {
            return clampedLocalModelIdleUnloadDelaySeconds(stored)
        }
        if let optimizationEnabled = defaults.object(forKey: localModelMemoryOptimizationEnabled) as? Bool {
            return optimizationEnabled
                ? defaultLocalModelIdleUnloadDelaySeconds
                : legacyLongLocalModelIdleUnloadDelaySeconds
        }
        if let legacyKeepResident = defaults.object(forKey: legacyWhisperKeepResidentLoaded) as? Bool {
            return legacyKeepResident
                ? legacyLongLocalModelIdleUnloadDelaySeconds
                : defaultLocalModelIdleUnloadDelaySeconds
        }
        return defaultLocalModelIdleUnloadDelaySeconds
    }

    static func resolvedTranscriptSummaryPromptTemplate(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: transcriptSummaryPromptTemplate)
    }

    static func setTranscriptSummaryPromptTemplate(_ value: String?, defaults: UserDefaults = .standard) {
        if let value {
            defaults.set(value, forKey: transcriptSummaryPromptTemplate)
        } else {
            defaults.removeObject(forKey: transcriptSummaryPromptTemplate)
        }
    }

    static func resolvedTranscriptSummaryModelSelection(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: transcriptSummaryModelSelection)
    }

    static func setTranscriptSummaryModelSelection(_ value: String?, defaults: UserDefaults = .standard) {
        if let value {
            defaults.set(value, forKey: transcriptSummaryModelSelection)
        } else {
            defaults.removeObject(forKey: transcriptSummaryModelSelection)
        }
    }
    static let dictionaryRecognitionEnabled = "dictionaryRecognitionEnabled"
    static let dictionaryAutoLearningEnabled = "dictionaryAutoLearningEnabled"
    static let dictionaryAutoLearningPrompt = "dictionaryAutoLearningPrompt"
    static let dictionaryHighConfidenceCorrectionEnabled = "dictionaryHighConfidenceCorrectionEnabled"
    static let dictionarySuggestionHistoryScanCheckpoint = "dictionarySuggestionHistoryScanCheckpoint"
    static let dictionarySuggestionFilterSettings = "dictionarySuggestionFilterSettings"
    static let dictionarySuggestionIngestModelOptionID = "dictionarySuggestionIngestModelOptionID"
    static let autoCheckForUpdates = "autoCheckForUpdates"
    static let betaUpdatesEnabled = "betaUpdatesEnabled"
    nonisolated static let hotkeyDebugLoggingEnabled = "hotkeyDebugLoggingEnabled"
    nonisolated static let llmDebugLoggingEnabled = "llmDebugLoggingEnabled"
    static let llmDebugCustomPrompt = "llmDebugCustomPrompt"
    static let llmDebugPresetPromptOverrides = "llmDebugPresetPromptOverrides"
    static let useSystemProxy = "useSystemProxy"
    static let networkProxyMode = "networkProxyMode"
    static let customProxyScheme = "customProxyScheme"
    static let customProxyHost = "customProxyHost"
    static let customProxyPort = "customProxyPort"
    static let customProxyUsername = "customProxyUsername"
    static let customProxyPassword = "customProxyPassword"
    static let onboardingCompleted = "onboardingCompleted"
    static let onboardingLastStepID = "onboardingLastStepID"

    static var defaultEnhancementPrompt: String {
        AppPromptDefaults.text(for: .enhancement, language: .english)
    }

    static var defaultTranslationPrompt: String {
        AppPromptDefaults.text(for: .translation, language: .english)
    }

    static var defaultRewritePrompt: String {
        AppPromptDefaults.text(for: .rewrite, language: .english)
    }

    static var defaultTranscriptSummaryPrompt: String {
        AppPromptDefaults.text(for: .transcriptSummary, language: .english)
    }

    static let automaticDictionaryLearningMainLanguageTemplateVariable = "{{USER_MAIN_LANGUAGE}}"
    static let automaticDictionaryLearningOtherLanguagesTemplateVariable = "{{USER_OTHER_LANGUAGES}}"
    static let automaticDictionaryLearningInsertedTextTemplateVariable = "{{INSERTED}}"
    static let automaticDictionaryLearningBaselineContextTemplateVariable = "{{BEFORE_CTX}}"
    static let automaticDictionaryLearningFinalContextTemplateVariable = "{{AFTER_CTX}}"
    static let automaticDictionaryLearningBaselineFragmentTemplateVariable = "{{BEFORE_EDIT}}"
    static let automaticDictionaryLearningFinalFragmentTemplateVariable = "{{AFTER_EDIT}}"
    static let automaticDictionaryLearningExistingTermsTemplateVariable = "{{EXISTING}}"

    static var defaultAutomaticDictionaryLearningPrompt: String {
        AppPromptDefaults.text(for: .dictionaryAutoLearning, language: .english)
    }

    static let asrUserMainLanguageTemplateVariable = "{{USER_MAIN_LANGUAGE}}"
    static let asrUserOtherLanguagesTemplateVariable = "{{USER_OTHER_LANGUAGES}}"
    static let asrDictionaryTermsTemplateVariable = "{{DICTIONARY_TERMS}}"

    static var defaultOpenAIASRHintPrompt: String {
        AppPromptDefaults.text(for: .openAIASRHint, language: .english)
    }

    static var defaultGLMASRHintPrompt: String {
        AppPromptDefaults.text(for: .glmASRHint, language: .english)
    }

}
