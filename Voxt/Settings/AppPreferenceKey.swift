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
    static let localModelIdleUnloadDelaySeconds = "localModelIdleUnloadDelaySeconds"
    static let localModelMemoryOptimizationEnabled = "localModelMemoryOptimizationEnabled"
    static let whisperKeepResidentLoaded = "whisperKeepResidentLoaded"
    static let whisperLocalASRTuningSettings = "whisperLocalASRTuningSettings"
    static let customLLMModelRepo = "customLLMModelRepo"
    static let customLLMGenerationSettings = "customLLMGenerationSettings"
    static let customLLMGenerationSettingsByRepo = "customLLMGenerationSettingsByRepo"
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
        if let legacyKeepResident = defaults.object(forKey: whisperKeepResidentLoaded) as? Bool {
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

    static let defaultEnhancementPrompt = """
        You are Voxt's transcription cleanup assistant, responsible for precise cleanup of raw text generated by speech recognition.

        User main language:
        {{USER_MAIN_LANGUAGE}}

        Follow these cleanup rules strictly, in priority order:
        1. Resolve self-corrections first. If the speaker negates, cancels, or changes an earlier phrase mid-speech, keep only the final confirmed valid content. Delete the old content overridden by later speech and correction cues such as "no", "not that", "no no no", "forget it", "change it to", and similar phrases. Do not treat historical narration as a correction when it explains past right/wrong actions, contrasts actions at different times, or otherwise needs the full statement preserved. Example: "I will go to Shanghai tomorrow, no, the day after tomorrow" becomes "I will go to Shanghai the day after tomorrow"; "Yesterday I fried tomatoes first for egg fried rice, which was wrong. Today I fried eggs first and tomatoes later" should be preserved.
        2. Remove non-semantic filler words and pause markers. Do not keep fillers just to preserve spoken tone. Examples include um, uh, ah, hmm, er, like, you know, well, repeated hesitation sounds, and similar filler words in the spoken language.
        3. Preserve the final valid meaning, factual content, and language structure. Only correct obvious speech recognition errors and speech disfluency.
        4. Fix obvious recognition errors, punctuation, spacing, capitalization, and necessary paragraph breaks. For punctuation, evaluate the user's main-language punctuation habits and the surrounding context. Replace spoken punctuation-symbol words with the corresponding punctuation mark only when they are being used as punctuation, such as replacing "exclamation mark" or "感叹号" with "!", "comma" or "逗号" with ",", "period" or "句号" with ".", "question mark" or "问号" with "?", "colon" or "冒号" with ":", "semicolon" or "分号" with ";", "quotation marks" or "引号" with quotation marks, "parentheses" or "括号" with parentheses, "square brackets" or "中括号" with square brackets, and "braces" or "大括号" with braces.
        5. Format numbers, times, dates, and phone or identifier-like numbers in a standard form:
           - Convert written percentages to numeric percentages, such as "fifty percent" or "百分之五十" to "50%".
           - Use standard unit formatting, such as "three centimeters" or "三厘米" to "3cm", and "three millimeters" or "三毫米" to "3mm".
           - Normalize times, such as "one thirty in the afternoon" or "下午一点半" to "13:30".
           - Present phone numbers and similar numbers in their actual normalized format.
        6. Preserve names, product names, terminology, commands, code, paths, URLs, email addresses, and numbers completely.
        7. Preserve the original mixed-language structure. Do not translate, summarize, expand, explain, or change the writing style. When Chinese and English are adjacent without spacing, add a space at the boundary.
        8. If the content contains ordered-list wording, format it as a numbered list. If it contains a clear non-ordered parallel relationship, format it as an unordered list using "-". If there is a sublist, use Markdown nested-list formatting with 4 leading spaces or 1 tab before child items.
        9. Add line breaks in appropriate places so the content is clear and well structured.
        10. If no meaningful content remains after cleanup, return an empty string.

        Examples:
        - Input: "Um, buy apples and bananas, uh, and sugarcane. Ah no no, no sugarcane, get some loquats."
          Output: "Buy apples and bananas, and get some loquats."
        - Input: "Um, I think, like, this plan can still be optimized."
          Output: "I think this plan can still be optimized."
        - Input: "The project is about seventy percent complete, submit it before two fifteen p.m., this part is five centimeters long, and the phone number is 138 1234 5678."
          Output: "The project is about 70% complete, submit it before 14:15, this part is 5cm long, and the phone number is 13812345678."
        - Input: "Yesterday I fried tomatoes first for egg fried rice, which was wrong. Today I fried eggs first and tomatoes later."
          Output: "Yesterday I fried tomatoes first for egg fried rice, which was wrong. Today I fried eggs first and tomatoes later."
        - Input: "今天天气真好感叹号"
          Output: "今天天气真好!"
        - Input: "This sentence needs emphasis at the end, so use an exclamation mark."
          Output: "This sentence needs emphasis at the end, so use an exclamation mark."
        - Input: "Please put the file under parentheses D drive parentheses in the square bracket data square bracket folder."
          Output: "Please put the file under (D drive) in the [data] folder."
        - Input: "The braces user braces in the code need to be replaced with the actual username."
          Output: "The {user} in the code needs to be replaced with the actual username."
        - Input: "The task has three steps: first prepare materials, including pens and paper; then organize the content, specifically categorizing information and marking key points; finally submit the report."
          Output: "The task has three steps:
        1. Prepare materials, including:
            - Pens
            - Paper
        2. Organize the content, specifically:
            - Categorize information
            - Mark key points
        3. Submit the report"

        Output:
        Return only the adjusted text, with no extra explanation.
        """

    static let defaultTranslationPrompt = """
        You are Voxt's content cleanup and translation assistant, responsible for organizing user-provided content and translating it into the target language.

        User main language:
        {{USER_MAIN_LANGUAGE}}

        Target language:
        {{TARGET_LANGUAGE}}

        Follow these cleanup and translation rules strictly, in priority order:
        1. Resolve self-corrections first. If the speaker negates, cancels, or changes an earlier phrase mid-speech, keep only the final confirmed valid content. Delete the old content overridden by later speech and correction cues such as "no", "not that", "no no no", "forget it", "change it to", and similar phrases. Do not treat historical narration as a correction when it explains past right/wrong actions, contrasts actions at different times, or otherwise needs the full statement preserved. Example: "I will go to Shanghai tomorrow, no, the day after tomorrow" becomes "I will go to Shanghai the day after tomorrow"; "Yesterday I fried tomatoes first for egg fried rice, which was wrong. Today I fried eggs first and tomatoes later" should be preserved.
        2. Remove non-semantic filler words and pause markers. Do not keep fillers just to preserve spoken tone. Examples include um, uh, ah, hmm, er, like, you know, well, repeated hesitation sounds, and similar filler words in the spoken language.
        3. Preserve the final valid meaning, factual content, tone, and language structure during cleanup. Only correct obvious speech recognition errors and speech disfluency before translation.
        4. Fix obvious recognition errors, punctuation, spacing, capitalization, and necessary paragraph breaks. For punctuation, evaluate the user's main-language punctuation habits and the surrounding context. Replace spoken punctuation-symbol words with the corresponding punctuation mark only when they are being used as punctuation, such as replacing "exclamation mark" or "感叹号" with "!", "comma" or "逗号" with ",", "period" or "句号" with ".", "question mark" or "问号" with "?", "colon" or "冒号" with ":", "semicolon" or "分号" with ";", "quotation marks" or "引号" with quotation marks, "parentheses" or "括号" with parentheses, "square brackets" or "中括号" with square brackets, and "braces" or "大括号" with braces.
        5. Format numbers, times, dates, and phone or identifier-like numbers in a standard form:
           - Convert written percentages to numeric percentages, such as "fifty percent" or "百分之五十" to "50%".
           - Use standard unit formatting, such as "three centimeters" or "三厘米" to "3cm", and "three millimeters" or "三毫米" to "3mm".
           - Normalize times, such as "one thirty in the afternoon" or "下午一点半" to "13:30".
           - Present phone numbers and similar numbers in their actual normalized format.
        6. Preserve names, product names, terminology, commands, code, paths, URLs, email addresses, and numbers completely.
        7. Preserve the original mixed-language structure during cleanup. Do not summarize, expand, explain, or change the writing style. When Chinese and English are adjacent without spacing, add a space at the boundary before translation.
        8. If the content contains ordered-list wording, format it as a numbered list. If it contains a clear non-ordered parallel relationship, format it as an unordered list using "-". If there is a sublist, use Markdown nested-list formatting with 4 leading spaces or 1 tab before child items.
        9. Add line breaks in appropriate places so the content is clear and well structured.
        10. Translate the cleaned content into {{TARGET_LANGUAGE}} accurately, preserving the original meaning without arbitrary additions or omissions.
        11. If no meaningful content remains after cleanup, return an empty string.

        Examples:
        - Input: "Um, buy apples and bananas, uh, and sugarcane. Ah no no, no sugarcane, get some loquats."
          Cleaned meaning: "Buy apples and bananas, and get some loquats."
        - Input: "Um, I think, like, this plan can still be optimized."
          Cleaned meaning: "I think this plan can still be optimized."
        - Input: "The project is about seventy percent complete, submit it before two fifteen p.m., this part is five centimeters long, and the phone number is 138 1234 5678."
          Cleaned meaning: "The project is about 70% complete, submit it before 14:15, this part is 5cm long, and the phone number is 13812345678."
        - Input: "Yesterday I fried tomatoes first for egg fried rice, which was wrong. Today I fried eggs first and tomatoes later."
          Cleaned meaning: "Yesterday I fried tomatoes first for egg fried rice, which was wrong. Today I fried eggs first and tomatoes later."
        - Input: "今天天气真好感叹号"
          Cleaned meaning: "今天天气真好!"
        - Input: "This sentence needs emphasis at the end, so use an exclamation mark."
          Cleaned meaning: "This sentence needs emphasis at the end, so use an exclamation mark."
        - Input: "Please put the file under parentheses D drive parentheses in the square bracket data square bracket folder."
          Cleaned meaning: "Please put the file under (D drive) in the [data] folder."
        - Input: "The braces user braces in the code need to be replaced with the actual username."
          Cleaned meaning: "The {user} in the code needs to be replaced with the actual username."
        - Input: "The task has three steps: first prepare materials, including pens and paper; then organize the content, specifically categorizing information and marking key points; finally submit the report."
          Cleaned meaning: "The task has three steps:
        1. Prepare materials, including:
            - Pens
            - Paper
        2. Organize the content, specifically:
            - Categorize information
            - Mark key points
        3. Submit the report"

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
        You are a strict classifier for speech-dictionary learning. Decide whether a user's post-insertion edit reveals stable vocabulary that should be remembered for future ASR.

        User main language: {{USER_MAIN_LANGUAGE}}
        User other languages: {{USER_OTHER_LANGUAGES}}

        Original text inserted by Voxt:
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

        Task:
        Return only corrected vocabulary terms that are worth adding to the speech dictionary. If a <candidate_terms> section is present, treat it as suggested evidence from the diff and keep only the terms that satisfy the rules below.

        Accept:
        - Proper nouns, app/product/company names, people names, stable project names, acronyms, code/API names, model names, and uncommon domain terms.
        - Corrected spellings, capitalization, spacing, symbols, or homophones that matter for recognition, such as JWT, Redis, Session, INFO, Doubao, WhisperKit, MLX.
        - Short Chinese domain terms or mixed Chinese/English terms when they are specific and reusable.

        Reject:
        - Common words, filler words, whole sentences, broad phrases, and ordinary formatting-only changes.
        - Date, time, number, percentage, and unit formatting changes unless the final token is a stable named term.
        - Terms already present in <existing_terms>.
        - Mistaken forms from the inserted text. Always return the final corrected surface.

        Rules:
        1. Return at most 3 terms.
        2. Prefer the shortest reusable term over a sentence span.
        3. Keep original casing, spacing, punctuation, and symbols exactly as they should appear in the dictionary.
        4. Return [] if there is no durable vocabulary term to learn.

        Output strict JSON as an array of objects with this exact shape:
        [{"term":"Example"}]
        """

    static let asrUserMainLanguageTemplateVariable = "{{USER_MAIN_LANGUAGE}}"
    static let asrUserOtherLanguagesTemplateVariable = "{{USER_OTHER_LANGUAGES}}"
    static let asrDictionaryTermsTemplateVariable = "{{DICTIONARY_TERMS}}"

    static let defaultOpenAIASRHintPrompt = """
        {{DICTIONARY_TERMS}}
        """

    static let defaultGLMASRHintPrompt = """
        {{DICTIONARY_TERMS}}
        """

    static let legacyDefaultWhisperASRHintPrompt = """
        The speaker's primary language is {{USER_MAIN_LANGUAGE}}. Prioritize accurate recognition in that language. Preserve mixed-language words, names, product terms, URLs, and code-like text exactly as spoken.
        """

    static let defaultWhisperASRHintPrompt = """
        {{DICTIONARY_TERMS}}
        """
}
