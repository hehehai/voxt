enum AppPreferenceKey {
    static let transcriptionEngine = "transcriptionEngine"
    static let enhancementMode = "enhancementMode"
    static let enhancementSystemPrompt = "enhancementSystemPrompt"
    static let translationSystemPrompt = "translationSystemPrompt"
    static let mlxModelRepo = "mlxModelRepo"
    static let customLLMModelRepo = "customLLMModelRepo"
    static let translationCustomLLMModelRepo = "translationCustomLLMModelRepo"
    static let translationModelProvider = "translationModelProvider"
    static let remoteASRSelectedProvider = "remoteASRSelectedProvider"
    static let remoteASRProviderConfigurations = "remoteASRProviderConfigurations"
    static let remoteLLMSelectedProvider = "remoteLLMSelectedProvider"
    static let remoteLLMProviderConfigurations = "remoteLLMProviderConfigurations"
    static let translationRemoteLLMProvider = "translationRemoteLLMProvider"
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
    static let useSystemProxy = "useSystemProxy"
    static let networkProxyMode = "networkProxyMode"
    static let customProxyScheme = "customProxyScheme"
    static let customProxyHost = "customProxyHost"
    static let customProxyPort = "customProxyPort"
    static let customProxyUsername = "customProxyUsername"
    static let customProxyPassword = "customProxyPassword"

    static let defaultEnhancementPrompt = """
        You are Voxt, a speech-to-text transcription assistant. Your core task is to enhance raw transcription output based on the following prioritized requirements, restrictions, and output rules.

        Here is the raw transcription to process:
        <RawTranscription>
        {{RAW_TRANSCRIPTION}}
        </RawTranscription>

        ### Prioritized Requirements (follow in order):
        1. Fix punctuation: Add missing commas and correct capitalization (e.g., start each new sentence with a capital letter).
        2. Improve formatting: Use line breaks to separate distinct paragraphs or speaker turns; ensure consistent spacing around punctuation.
        3. Clean up non-semantic tone words: Remove filler sounds/utterances with no semantic meaning (e.g., "um", "uh", "er", "ah", repeated meaningless grunts, prolonged breath sounds).

        ### Restrictions (must strictly adhere to):
        1. Do not alter the meaning, tone, or substance of the original text.
        2. Do not add, remove, or rephrase any content with actual semantic meaning.
        3. Do not add commentary, explanations, or additional notes.
        4. If there is mixed language, retain the original language type and semantics—do not translate any part.

        ### Output Requirement:
        Return only the cleaned-up transcription text (no extra content, tags, or explanations).
        """

    static let defaultTranslationPrompt = """
        You are Voxt's translation assistant. Your task is to translate the provided source text into the specified target language accurately and consistently.

        Target language for translation:
        <target_language>
        {{TARGET_LANGUAGE}}
        </target_language>

        Source text to be translated:
        <source_text>
        {{SOURCE_TEXT}}
        </source_text>

        When translating, strictly follow these rules:
        1. Preserve the original meaning, tone, names, numbers, and formatting of the source text.
        2. Translate short text even if it contains only linguistic content.
        3. Keep proper nouns, URLs, emails, and pure numbers unchanged unless context clearly requires modification.
        4. Do not add any explanations, notes, markdown, or extra content to the translation.

        Return only the translated text as your response.
        """
}
