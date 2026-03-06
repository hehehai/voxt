enum AppPreferenceKey {
    static let transcriptionEngine = "transcriptionEngine"
    static let enhancementMode = "enhancementMode"
    static let enhancementSystemPrompt = "enhancementSystemPrompt"
    static let translationSystemPrompt = "translationSystemPrompt"
    static let mlxModelRepo = "mlxModelRepo"
    static let customLLMModelRepo = "customLLMModelRepo"
    static let translationCustomLLMModelRepo = "translationCustomLLMModelRepo"
    static let modelStorageRootPath = "modelStorageRootPath"
    static let modelStorageRootBookmark = "modelStorageRootBookmark"
    static let useHfMirror = "useHfMirror"
    static let hotkeyKeyCode = "hotkeyKeyCode"
    static let hotkeyModifiers = "hotkeyModifiers"
    static let translationHotkeyKeyCode = "translationHotkeyKeyCode"
    static let translationHotkeyModifiers = "translationHotkeyModifiers"
    static let hotkeyTriggerMode = "hotkeyTriggerMode"
    static let selectedInputDeviceID = "selectedInputDeviceID"
    static let interactionSoundsEnabled = "interactionSoundsEnabled"
    static let interactionSoundPreset = "interactionSoundPreset"
    static let overlayPosition = "overlayPosition"
    static let interfaceLanguage = "interfaceLanguage"
    static let translationTargetLanguage = "translationTargetLanguage"
    static let translateSelectedTextOnTranslationHotkey = "translateSelectedTextOnTranslationHotkey"
    static let autoCopyWhenNoFocusedInput = "autoCopyWhenNoFocusedInput"
    static let appEnhancementEnabled = "appEnhancementEnabled"
    static let appBranchGroups = "appBranchGroups"
    static let appBranchURLs = "appBranchURLs"
    static let appBranchCustomBrowsers = "appBranchCustomBrowsers"
    static let customLLMRemoteSizeCache = "customLLMRemoteSizeCache"
    static let launchAtLogin = "launchAtLogin"
    static let showInDock = "showInDock"
    static let historyEnabled = "historyEnabled"
    static let historyRetentionPeriod = "historyRetentionPeriod"
    static let autoCheckForUpdates = "autoCheckForUpdates"

    static let defaultEnhancementPrompt = """
        You are Voxt, a speech-to-text transcription assistant. Your only job is to enhance raw transcription output. Fix punctuation, add missing commas, correct capitalization, and improve formatting. Do not alter the meaning, tone, or substance of the text. Clean up non-sematic tone words，Do not add, remove, or rephrase any content. Do not add commentary or explanations. Return only the cleaned-up text. If there is a mixed language, please pay attention to keep the mixed language semantics.
        """

    static let defaultTranslationPrompt = """
        You are Voxt's translation assistant.
        Translate the input text to {target_language}.
        Preserve meaning, tone, names, numbers, and formatting.
        Translate short text as well when it contains linguistic content.
        Keep proper nouns, URLs, emails, and pure numbers unchanged when appropriate.
        Do not output explanations, notes, or markdown.
        Return only the translated text.
        """
}
