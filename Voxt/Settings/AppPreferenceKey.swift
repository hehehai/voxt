import Foundation

enum AppPreferenceKey {
    static let transcriptionEngine = "transcriptionEngine"
    static let enhancementMode = "enhancementMode"
    static let enhancementSystemPrompt = "enhancementSystemPrompt"
    static let translationSystemPrompt = "translationSystemPrompt"
    static let mlxModelRepo = "mlxModelRepo"
    static let whisperModelID = "whisperModelID"
    static let whisperTemperature = "whisperTemperature"
    static let whisperVADEnabled = "whisperVADEnabled"
    static let whisperTimestampsEnabled = "whisperTimestampsEnabled"
    static let whisperRealtimeEnabled = "whisperRealtimeEnabled"
    static let localModelMemoryOptimizationEnabled = "localModelMemoryOptimizationEnabled"
    static let whisperKeepResidentLoaded = "whisperKeepResidentLoaded"
    static let whisperLocalASRTuningSettings = "whisperLocalASRTuningSettings"
    static let customLLMModelRepo = "customLLMModelRepo"
    static let translationCustomLLMModelRepo = "translationCustomLLMModelRepo"
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
    static let hotkeyKeyCode = "hotkeyKeyCode"
    static let hotkeyModifiers = "hotkeyModifiers"
    static let hotkeySidedModifiers = "hotkeySidedModifiers"
    static let translationHotkeyKeyCode = "translationHotkeyKeyCode"
    static let translationHotkeyModifiers = "translationHotkeyModifiers"
    static let translationHotkeySidedModifiers = "translationHotkeySidedModifiers"
    static let rewriteHotkeyKeyCode = "rewriteHotkeyKeyCode"
    static let rewriteHotkeyModifiers = "rewriteHotkeyModifiers"
    static let rewriteHotkeySidedModifiers = "rewriteHotkeySidedModifiers"
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
    static let transcriptSummaryPromptTemplate = "transcriptSummaryPromptTemplate"
    static let transcriptSummaryModelSelection = "transcriptSummaryModelSelection"
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
    static let whisperRemoteSizeCache = "whisperRemoteSizeCache"
    static let customLLMRemoteSizeCache = "customLLMRemoteSizeCache"
    static let launchAtLogin = "launchAtLogin"
    static let showInDock = "showInDock"
    static let historyEnabled = "historyEnabled"
    static let historyCleanupEnabled = "historyCleanupEnabled"
    static let historyRetentionPeriod = "historyRetentionPeriod"
    static let historyAudioStorageEnabled = "historyAudioStorageEnabled"
    static let historyAudioStorageRootPath = "historyAudioStorageRootPath"
    static let historyAudioStorageRootBookmark = "historyAudioStorageRootBookmark"

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

    static let defaultEnhancementPrompt = """
        You are Voxt's transcription cleanup assistant, responsible for precise cleanup of raw text generated by speech recognition.

        User main language:
        {{USER_MAIN_LANGUAGE}}

        Follow these cleanup rules strictly:
        1. Preserve the speaker's original meaning, tone, and language structure. Only correct obvious speech recognition errors.
        2. If the speaker self-corrects mid-sentence, keep only the final confirmed expression. Example: "I will go to Shanghai tomorrow, no, the day after tomorrow" should become "I will go to Shanghai the day after tomorrow."
        3. Fix obvious recognition errors, punctuation, spacing, capitalization, and necessary paragraph breaks. Format numbers, times, dates, identifiers, and phone numbers in a standard readable form.
        4. Remove meaningless filler words or pause markers only when doing so does not affect meaning. Examples include um, uh, like, you know, well, hmm, er, and similar filler words in the spoken language.
        5. Preserve names, product names, terminology, commands, code, paths, URLs, email addresses, and numbers completely.
        6. Preserve the original mixed-language structure. Do not translate, summarize, expand, explain, or change the writing style. When Chinese and English are adjacent without spacing, add a space at the boundary.
        7. If the content contains ordered-list wording, format it as a numbered list.
        8. If no meaningful content remains after cleanup, return an empty string.

        Output:
        Return only the cleaned text, with no extra explanation.
        """

    static let defaultTranslationPrompt = """
        You are Voxt's content cleanup and translation assistant, responsible for organizing user-provided content and translating it into the target language.

        Target language:
        {{TARGET_LANGUAGE}}

        User main language:
        {{USER_MAIN_LANGUAGE}}

        Follow these rules strictly:
        1. Preserve the original meaning, tone, and core information. First clean up the content precisely by fixing obvious wording errors, punctuation, spacing, capitalization, and necessary paragraph breaks. Format numbers, times, dates, identifiers, and phone numbers in a standard readable form.
        2. If the content contains self-correction, keep only the final confirmed expression. Example: "I will go to Shanghai tomorrow, no, the day after tomorrow" should be organized as "I will go to Shanghai the day after tomorrow."
        3. Remove meaningless filler words or pause markers only when doing so does not affect meaning. Examples include um, uh, like, you know, well, hmm, er, and similar filler words in the spoken language.
        4. Preserve names, product names, terminology, commands, code, paths, URLs, email addresses, and numbers completely.
        5. Preserve core information from the original mixed-language structure. When Chinese and English are adjacent without spacing, add a space at the boundary before translation.
        6. If the content contains ordered-list wording, first organize it as a numbered list before translation.
        7. Translate the cleaned content into the target language accurately, preserving the original meaning without arbitrary additions or omissions.
        8. If no meaningful content remains after processing, return an empty string.

        Output:
        Return only the cleaned and translated text, with no extra explanation.
        """

    static let defaultRewritePrompt = """
        You are Voxt's rewrite assistant.

        Goal:
        Apply the user's spoken instruction to the current text, or generate the requested content directly when no source text is provided.

        Rules:
        1. Follow the spoken instruction precisely.
        2. If source text exists, transform it accordingly; otherwise answer directly with the requested content.
        3. Return only the final text to insert.
        4. Do not include explanations, markdown, labels, or commentary.
        """

    static let defaultTranscriptSummaryPrompt = TranscriptSummarySupport.defaultPromptTemplate()
    static let automaticDictionaryLearningMainLanguageTemplateVariable = "{{USER_MAIN_LANGUAGE}}"
    static let automaticDictionaryLearningOtherLanguagesTemplateVariable = "{{USER_OTHER_LANGUAGES}}"
    static let automaticDictionaryLearningInsertedTextTemplateVariable = "{{INSERTED}}"
    static let automaticDictionaryLearningBaselineContextTemplateVariable = "{{BEFORE_CTX}}"
    static let automaticDictionaryLearningFinalContextTemplateVariable = "{{AFTER_CTX}}"
    static let automaticDictionaryLearningBaselineFragmentTemplateVariable = "{{BEFORE_EDIT}}"
    static let automaticDictionaryLearningFinalFragmentTemplateVariable = "{{AFTER_EDIT}}"
    static let automaticDictionaryLearningExistingTermsTemplateVariable = "{{EXISTING}}"
    static let defaultAutomaticDictionaryLearningPrompt = """
        You review a dictation correction and decide which vocabulary terms should be added to a speech dictionary.

        User main language: {{USER_MAIN_LANGUAGE}}
        User other languages: {{USER_OTHER_LANGUAGES}}

        Original inserted text:
        <inserted_text>
        {{INSERTED}}
        </inserted_text>

        Baseline context captured right after insertion:
        <baseline_context>
        {{BEFORE_CTX}}
        </baseline_context>

        Final context captured after the user edited the same input:
        <final_context>
        {{AFTER_CTX}}
        </final_context>

        Baseline changed fragment:
        <baseline_changed_fragment>
        {{BEFORE_EDIT}}
        </baseline_changed_fragment>

        Final changed fragment:
        <final_changed_fragment>
        {{AFTER_EDIT}}
        </final_changed_fragment>

        Existing dictionary terms:
        <existing_terms>
        {{EXISTING}}
        </existing_terms>

        Return only vocabulary terms worth adding to the dictionary. Prefer durable proper nouns, product names, company names, personal names, technical terms, and uncommon domain terminology that appear in the final corrected text.

        Rules:
        1. Return an empty array if the user only appended more text, made unrelated edits, or corrected punctuation or casing only.
        2. Do not return common words, filler, whole sentences, or long phrases.
        3. Do not return anything already present in the existing dictionary list.
        4. Use the final corrected form, not the mistaken form.
        Output strict JSON as an array of objects with this exact shape:
        [{"term":"Example"}]
        """

    static let asrUserMainLanguageTemplateVariable = "{{USER_MAIN_LANGUAGE}}"
    static let asrUserOtherLanguagesTemplateVariable = "{{USER_OTHER_LANGUAGES}}"
    static let asrDictionaryTermsTemplateVariable = "{{DICTIONARY_TERMS}}"

    static let defaultOpenAIASRHintPrompt = """
        The speaker's primary language is {{USER_MAIN_LANGUAGE}}. Prioritize accurate transcription in that language while preserving mixed-language words, names, product terms, URLs, and code-like text exactly as spoken.
        """

    static let defaultGLMASRHintPrompt = """
        The speaker's primary language is {{USER_MAIN_LANGUAGE}}. Prioritize accurate recognition in that language. Preserve names, terminology, mixed-language content, and code-like text exactly as spoken.
        """

    static let legacyDefaultWhisperASRHintPrompt = """
        The speaker's primary language is {{USER_MAIN_LANGUAGE}}. Prioritize accurate recognition in that language. Preserve mixed-language words, names, product terms, URLs, and code-like text exactly as spoken.
        """

    static let defaultWhisperASRHintPrompt = """
        The speaker's primary language is {{USER_MAIN_LANGUAGE}}. Prioritize accurate transcription in that language while preserving mixed-language words, names, product terms, URLs, and code-like text exactly as spoken.

        Prefer these dictionary terms when they match the audio:
        {{DICTIONARY_TERMS}}
        """
}
