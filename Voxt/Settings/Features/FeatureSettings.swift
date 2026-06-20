// FeatureSettings.swift
// Provides Feature Settings for feature settings.

import Foundation

struct FeatureModelSelectionID: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
    let rawValue: String

    var id: String { rawValue }

    init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static let dictation = Self(rawValue: "dictation")
    static let appleIntelligence = Self(rawValue: "apple-intelligence")
    private static let legacyWhisperDirectTranslateRawValue = "whisper-direct-translate"

    static func mlx(_ repo: String) -> Self {
        Self(rawValue: "mlx:\(MLXModelManager.canonicalModelRepo(repo))")
    }

    static func sherpaOnnx(_ modelID: SherpaOnnxModelID) -> Self {
        Self(rawValue: "sherpa:\(modelID.rawValue)")
    }

    static func whisper(_ modelID: String) -> Self {
        .mlx(MLXWhisperMigrationSupport.repo(forLegacyWhisperModelID: modelID))
    }

    static func remoteASR(_ provider: RemoteASRProvider) -> Self {
        Self(rawValue: "remote-asr:\(provider.rawValue)")
    }

    static func localLLM(_ repo: String) -> Self {
        Self(rawValue: "local-llm:\(repo)")
    }

    static func localGGUFTranslation(_ modelID: GGUFTranslationModelID) -> Self {
        Self(rawValue: "local-gguf-translation:\(modelID.rawValue)")
    }

    static func remoteLLM(_ provider: RemoteLLMProvider) -> Self {
        Self(rawValue: "remote-llm:\(provider.rawValue)")
    }

    enum ASRSelection: Hashable, Sendable {
        case dictation
        case mlx(repo: String)
        case sherpaOnnx(modelID: SherpaOnnxModelID)
        case remote(provider: RemoteASRProvider)
    }

    enum TextSelection: Hashable, Sendable {
        case appleIntelligence
        case localLLM(repo: String)
        case remoteLLM(provider: RemoteLLMProvider)
    }

    enum TranslationSelection: Hashable, Sendable {
        case localLLM(repo: String)
        case localGGUF(modelID: GGUFTranslationModelID)
        case remoteLLM(provider: RemoteLLMProvider)
    }

    var asrSelection: ASRSelection? {
        if rawValue == Self.dictation.rawValue {
            return .dictation
        }
        if let repo = payload(after: "mlx:") {
            if SherpaOnnxRuntimeSupport.isAvailable,
               SherpaOnnxModelCatalog.isLegacyFireRedMLXRepo(repo) {
                return .sherpaOnnx(modelID: SherpaOnnxModelCatalog.fireRedModelID)
            }
            return .mlx(repo: MLXModelManager.canonicalModelRepo(repo))
        }
        if let modelID = payload(after: "sherpa:") {
            return .sherpaOnnx(modelID: SherpaOnnxModelID(rawValue: modelID))
        }
        if let modelID = payload(after: "whisper:") {
            return .mlx(repo: MLXWhisperMigrationSupport.repo(forLegacyWhisperModelID: modelID))
        }
        if let value = payload(after: "remote-asr:"),
           let provider = RemoteASRProvider(rawValue: value) {
            return .remote(provider: provider)
        }
        return nil
    }

    var textSelection: TextSelection? {
        if rawValue == Self.appleIntelligence.rawValue {
            return .appleIntelligence
        }
        if let repo = payload(after: "local-llm:") {
            return .localLLM(repo: repo)
        }
        if let value = payload(after: "remote-llm:"),
           let provider = RemoteLLMProvider(rawValue: value) {
            return .remoteLLM(provider: provider)
        }
        return nil
    }

    var translationSelection: TranslationSelection? {
        if rawValue == Self.legacyWhisperDirectTranslateRawValue {
            return .localLLM(repo: CustomLLMModelManager.defaultModelRepo)
        }
        if let repo = payload(after: "local-llm:") {
            return .localLLM(repo: repo)
        }
        if let value = payload(after: "local-gguf-translation:"),
           let modelID = GGUFTranslationModelID(rawValue: value) {
            return .localGGUF(modelID: modelID)
        }
        if let value = payload(after: "remote-llm:"),
           let provider = RemoteLLMProvider(rawValue: value) {
            return .remoteLLM(provider: provider)
        }
        return nil
    }

    private func payload(after prefix: String) -> String? {
        guard rawValue.hasPrefix(prefix) else { return nil }
        let value = String(rawValue.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func fromTranscriptSummaryModelSelection(_ rawValue: String?) -> Self? {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        if trimmed == appleIntelligence.rawValue {
            return .appleIntelligence
        }
        if trimmed.hasPrefix("custom-llm:") {
            return .localLLM(String(trimmed.dropFirst("custom-llm:".count)))
        }
        if trimmed.hasPrefix("remote-llm:") {
            let providerRaw = String(trimmed.dropFirst("remote-llm:".count))
            if let provider = RemoteLLMProvider(rawValue: providerRaw) {
                return .remoteLLM(provider)
            }
        }
        return Self(rawValue: trimmed)
    }
}

enum ObsidianNoteGroupingMode: String, Codable, CaseIterable, Hashable, Sendable {
    case session
    case daily
    case file
}

struct RemindersNoteSyncSettings: Codable, Hashable, Sendable {
    var enabled: Bool
    var selectedListIdentifier: String
    var selectedListTitle: String

    init(
        enabled: Bool = false,
        selectedListIdentifier: String = "",
        selectedListTitle: String = ""
    ) {
        self.enabled = enabled
        self.selectedListIdentifier = selectedListIdentifier
        self.selectedListTitle = selectedListTitle
    }
}

struct ObsidianNoteSyncSettings: Codable, Hashable, Sendable {
    var enabled: Bool
    var vaultPath: String
    var vaultBookmarkData: Data?
    var relativeFolder: String
    var groupingMode: ObsidianNoteGroupingMode

    init(
        enabled: Bool = false,
        vaultPath: String = "",
        vaultBookmarkData: Data? = nil,
        relativeFolder: String = "Voxt",
        groupingMode: ObsidianNoteGroupingMode = .file
    ) {
        self.enabled = enabled
        self.vaultPath = vaultPath
        self.vaultBookmarkData = vaultBookmarkData
        self.relativeFolder = relativeFolder
        self.groupingMode = groupingMode
    }
}

struct TranscriptionNoteFeatureSettings: Codable, Hashable, Sendable {
    var enabled: Bool
    var triggerShortcut: TranscriptionNoteTriggerSettings
    var titleModelSelectionID: FeatureModelSelectionID
    var soundEnabled: Bool
    var soundPreset: InteractionSoundPreset
    var obsidianSync: ObsidianNoteSyncSettings
    var remindersSync: RemindersNoteSyncSettings

    init(
        enabled: Bool = false,
        triggerShortcut: TranscriptionNoteTriggerSettings = .defaultShortcut,
        titleModelSelectionID: FeatureModelSelectionID,
        soundEnabled: Bool = false,
        soundPreset: InteractionSoundPreset = .soft,
        obsidianSync: ObsidianNoteSyncSettings = .init(),
        remindersSync: RemindersNoteSyncSettings = .init()
    ) {
        self.enabled = enabled
        self.triggerShortcut = triggerShortcut
        self.titleModelSelectionID = titleModelSelectionID
        self.soundEnabled = soundEnabled
        self.soundPreset = soundPreset
        self.obsidianSync = obsidianSync
        self.remindersSync = remindersSync
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case triggerShortcut
        case titleModelSelectionID
        case soundEnabled
        case soundPreset
        case obsidianSync
        case remindersSync
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        triggerShortcut = try container.decodeIfPresent(TranscriptionNoteTriggerSettings.self, forKey: .triggerShortcut) ?? .defaultShortcut
        titleModelSelectionID = try container.decode(FeatureModelSelectionID.self, forKey: .titleModelSelectionID)
        soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? false
        soundPreset = try container.decodeIfPresent(InteractionSoundPreset.self, forKey: .soundPreset) ?? .soft
        obsidianSync = try container.decodeIfPresent(ObsidianNoteSyncSettings.self, forKey: .obsidianSync) ?? .init()
        remindersSync = try container.decodeIfPresent(RemindersNoteSyncSettings.self, forKey: .remindersSync) ?? .init()
    }
}

struct TranscriptionAppContextSettings: Codable, Hashable, Sendable {
    var textEnabled: Bool
    var screenshotEnabled: Bool

    var enabled: Bool {
        get { textEnabled || screenshotEnabled }
        set {
            if newValue {
                textEnabled = true
                screenshotEnabled = true
            } else {
                textEnabled = false
                screenshotEnabled = false
            }
        }
    }

    init(
        enabled: Bool = false,
        textEnabled: Bool? = nil,
        screenshotEnabled: Bool? = nil
    ) {
        let resolvedTextEnabled = textEnabled ?? enabled
        let resolvedScreenshotEnabled = screenshotEnabled ?? enabled
        self.textEnabled = resolvedTextEnabled
        self.screenshotEnabled = resolvedScreenshotEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case textEnabled
        case screenshotEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyEnabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        let textEnabled = try container.decodeIfPresent(Bool.self, forKey: .textEnabled)
        let screenshotEnabled = try container.decodeIfPresent(Bool.self, forKey: .screenshotEnabled)
        self.init(
            enabled: legacyEnabled,
            textEnabled: textEnabled,
            screenshotEnabled: screenshotEnabled
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(textEnabled, forKey: .textEnabled)
        try container.encode(screenshotEnabled, forKey: .screenshotEnabled)
    }
}

struct TranscriptionFeatureSettings: Codable, Hashable, Sendable {
    var asrSelectionID: FeatureModelSelectionID
    var llmEnabled: Bool
    var llmSelectionID: FeatureModelSelectionID
    var prompt: String
    var appContext: TranscriptionAppContextSettings
    var notes: TranscriptionNoteFeatureSettings

    init(
        asrSelectionID: FeatureModelSelectionID,
        llmEnabled: Bool,
        llmSelectionID: FeatureModelSelectionID,
        prompt: String,
        appContext: TranscriptionAppContextSettings = .init(),
        notes: TranscriptionNoteFeatureSettings? = nil
    ) {
        self.asrSelectionID = asrSelectionID
        self.llmEnabled = llmEnabled
        self.llmSelectionID = llmSelectionID
        self.prompt = prompt
        self.appContext = appContext
        self.notes = notes ?? TranscriptionNoteFeatureSettings(
            enabled: false,
            triggerShortcut: .defaultShortcut,
            titleModelSelectionID: llmSelectionID.textSelection == nil
                ? .localLLM(CustomLLMModelManager.defaultModelRepo)
                : llmSelectionID
        )
    }

    private enum CodingKeys: String, CodingKey {
        case asrSelectionID
        case llmEnabled
        case llmSelectionID
        case prompt
        case appContext
        case notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let asrSelectionID = try container.decode(FeatureModelSelectionID.self, forKey: .asrSelectionID)
        let llmEnabled = try container.decode(Bool.self, forKey: .llmEnabled)
        let llmSelectionID = try container.decode(FeatureModelSelectionID.self, forKey: .llmSelectionID)
        let prompt = try container.decode(String.self, forKey: .prompt)
        let decodedNotes = try container.decodeIfPresent(TranscriptionNoteFeatureSettings.self, forKey: .notes)
        self.init(
            asrSelectionID: asrSelectionID,
            llmEnabled: llmEnabled,
            llmSelectionID: llmSelectionID,
            prompt: prompt,
            appContext: try container.decodeIfPresent(TranscriptionAppContextSettings.self, forKey: .appContext) ?? .init(),
            notes: decodedNotes
        )
    }
}

struct TranslationFeatureSettings: Codable, Hashable, Sendable {
    var asrSelectionID: FeatureModelSelectionID
    var modelSelectionID: FeatureModelSelectionID
    var targetLanguageRawValue: String
    var prompt: String
    var showResultWindow: Bool

    init(
        asrSelectionID: FeatureModelSelectionID,
        modelSelectionID: FeatureModelSelectionID,
        targetLanguageRawValue: String,
        prompt: String,
        showResultWindow: Bool = true
    ) {
        self.asrSelectionID = asrSelectionID
        self.modelSelectionID = modelSelectionID
        self.targetLanguageRawValue = targetLanguageRawValue
        self.prompt = prompt
        self.showResultWindow = showResultWindow
    }

    var targetLanguage: TranslationTargetLanguage {
        TranslationTargetLanguage(rawValue: targetLanguageRawValue) ?? .english
    }

    private enum CodingKeys: String, CodingKey {
        case asrSelectionID
        case modelSelectionID
        case targetLanguageRawValue
        case prompt
        case showResultWindow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            asrSelectionID: try container.decode(FeatureModelSelectionID.self, forKey: .asrSelectionID),
            modelSelectionID: try container.decode(FeatureModelSelectionID.self, forKey: .modelSelectionID),
            targetLanguageRawValue: try container.decode(String.self, forKey: .targetLanguageRawValue),
            prompt: try container.decode(String.self, forKey: .prompt),
            showResultWindow: try container.decodeIfPresent(Bool.self, forKey: .showResultWindow) ?? true
        )
    }
}

struct RewriteFeatureSettings: Codable, Hashable, Sendable {
    var asrSelectionID: FeatureModelSelectionID
    var llmSelectionID: FeatureModelSelectionID
    var prompt: String
    var appContext: TranscriptionAppContextSettings
    var appEnhancementEnabled: Bool
    var continueShortcut: TranscriptionContinueShortcutSettings

    init(
        asrSelectionID: FeatureModelSelectionID,
        llmSelectionID: FeatureModelSelectionID,
        prompt: String,
        appContext: TranscriptionAppContextSettings = .init(),
        appEnhancementEnabled: Bool,
        continueShortcut: TranscriptionContinueShortcutSettings = .defaultShortcut
    ) {
        self.asrSelectionID = asrSelectionID
        self.llmSelectionID = llmSelectionID
        self.prompt = prompt
        self.appContext = appContext
        self.appEnhancementEnabled = appEnhancementEnabled
        self.continueShortcut = continueShortcut
    }

    private enum CodingKeys: String, CodingKey {
        case asrSelectionID
        case llmSelectionID
        case prompt
        case appContext
        case appEnhancementEnabled
        case continueShortcut
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            asrSelectionID: try container.decode(FeatureModelSelectionID.self, forKey: .asrSelectionID),
            llmSelectionID: try container.decode(FeatureModelSelectionID.self, forKey: .llmSelectionID),
            prompt: try container.decode(String.self, forKey: .prompt),
            appContext: try container.decodeIfPresent(TranscriptionAppContextSettings.self, forKey: .appContext) ?? .init(),
            appEnhancementEnabled: try container.decode(Bool.self, forKey: .appEnhancementEnabled),
            continueShortcut: try container.decodeIfPresent(TranscriptionContinueShortcutSettings.self, forKey: .continueShortcut) ?? .defaultShortcut
        )
    }
}

struct MeetingFeatureSettings: Codable, Hashable, Sendable {
    static let defaultFinalTranscriptOptimizationEnabled = true

    var asrSelectionID: FeatureModelSelectionID
    var summaryModelSelectionID: FeatureModelSelectionID
    var summaryPrompt: String
    var summaryAutoGenerate: Bool
    var realtimeTranslateEnabled: Bool
    var realtimeTargetLanguageRawValue: String
    var hideOverlayFromScreenSharing: Bool
    var chunkingModeRawValue: String
    var speakerDiarizationModelRawValue: String
    var finalTranscriptOptimizationEnabled: Bool

    init(
        asrSelectionID: FeatureModelSelectionID,
        summaryModelSelectionID: FeatureModelSelectionID,
        summaryPrompt: String,
        summaryAutoGenerate: Bool,
        realtimeTranslateEnabled: Bool,
        realtimeTargetLanguageRawValue: String,
        hideOverlayFromScreenSharing: Bool,
        chunkingModeRawValue: String = MeetingChunkingMode.quality.rawValue,
        speakerDiarizationModelRawValue: String = MeetingDiarizationMode.offlineVBx.rawValue,
        finalTranscriptOptimizationEnabled: Bool = MeetingFeatureSettings.defaultFinalTranscriptOptimizationEnabled
    ) {
        self.asrSelectionID = asrSelectionID
        self.summaryModelSelectionID = summaryModelSelectionID
        self.summaryPrompt = summaryPrompt
        self.summaryAutoGenerate = summaryAutoGenerate
        self.realtimeTranslateEnabled = realtimeTranslateEnabled
        self.realtimeTargetLanguageRawValue = realtimeTargetLanguageRawValue
        self.hideOverlayFromScreenSharing = hideOverlayFromScreenSharing
        self.chunkingModeRawValue = chunkingModeRawValue
        self.speakerDiarizationModelRawValue = speakerDiarizationModelRawValue
        self.finalTranscriptOptimizationEnabled = finalTranscriptOptimizationEnabled
    }

    var realtimeTargetLanguage: TranslationTargetLanguage? {
        guard !realtimeTargetLanguageRawValue.isEmpty else { return nil }
        return TranslationTargetLanguage(rawValue: realtimeTargetLanguageRawValue)
    }

    var chunkingMode: MeetingChunkingMode {
        MeetingChunkingMode(rawValue: chunkingModeRawValue) ?? .quality
    }

    var speakerDiarizationModel: MeetingDiarizationMode {
        MeetingDiarizationMode(rawValue: speakerDiarizationModelRawValue) ?? .offlineVBx
    }

    private enum CodingKeys: String, CodingKey {
        case asrSelectionID
        case summaryModelSelectionID
        case summaryPrompt
        case summaryAutoGenerate
        case realtimeTranslateEnabled
        case realtimeTargetLanguageRawValue
        case hideOverlayFromScreenSharing
        case chunkingModeRawValue
        case speakerDiarizationModelRawValue
        case finalTranscriptOptimizationEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            asrSelectionID: try container.decode(FeatureModelSelectionID.self, forKey: .asrSelectionID),
            summaryModelSelectionID: try container.decode(FeatureModelSelectionID.self, forKey: .summaryModelSelectionID),
            summaryPrompt: try container.decode(String.self, forKey: .summaryPrompt),
            summaryAutoGenerate: try container.decode(Bool.self, forKey: .summaryAutoGenerate),
            realtimeTranslateEnabled: try container.decode(Bool.self, forKey: .realtimeTranslateEnabled),
            realtimeTargetLanguageRawValue: try container.decode(String.self, forKey: .realtimeTargetLanguageRawValue),
            hideOverlayFromScreenSharing: try container.decode(Bool.self, forKey: .hideOverlayFromScreenSharing),
            chunkingModeRawValue: try container.decodeIfPresent(String.self, forKey: .chunkingModeRawValue)
                ?? MeetingChunkingMode.quality.rawValue,
            speakerDiarizationModelRawValue: try container.decodeIfPresent(String.self, forKey: .speakerDiarizationModelRawValue)
                ?? MeetingDiarizationMode.offlineVBx.rawValue,
            finalTranscriptOptimizationEnabled: try container.decodeIfPresent(Bool.self, forKey: .finalTranscriptOptimizationEnabled)
                ?? MeetingFeatureSettings.defaultFinalTranscriptOptimizationEnabled
        )
    }
}

struct FeatureSettings: Codable, Hashable, Sendable {
    var transcription: TranscriptionFeatureSettings
    var translation: TranslationFeatureSettings
    var rewrite: RewriteFeatureSettings
    var meeting: MeetingFeatureSettings

    init(
        transcription: TranscriptionFeatureSettings,
        translation: TranslationFeatureSettings,
        rewrite: RewriteFeatureSettings,
        meeting: MeetingFeatureSettings? = nil
    ) {
        self.transcription = transcription
        self.translation = translation
        self.rewrite = rewrite
        self.meeting = meeting ?? MeetingFeatureSettings(
            asrSelectionID: transcription.asrSelectionID,
            summaryModelSelectionID: transcription.llmSelectionID,
            summaryPrompt: "",
            summaryAutoGenerate: true,
            realtimeTranslateEnabled: false,
            realtimeTargetLanguageRawValue: "",
            hideOverlayFromScreenSharing: false
        )
    }

    private enum CodingKeys: String, CodingKey {
        case transcription
        case translation
        case rewrite
        case meeting
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let transcription = try container.decode(TranscriptionFeatureSettings.self, forKey: .transcription)
        let translation = try container.decode(TranslationFeatureSettings.self, forKey: .translation)
        let rewrite = try container.decode(RewriteFeatureSettings.self, forKey: .rewrite)
        let meeting = try container.decodeIfPresent(MeetingFeatureSettings.self, forKey: .meeting)
            ?? MeetingFeatureSettings(
                asrSelectionID: transcription.asrSelectionID,
                summaryModelSelectionID: transcription.llmSelectionID,
                summaryPrompt: "",
                summaryAutoGenerate: true,
                realtimeTranslateEnabled: false,
                realtimeTargetLanguageRawValue: "",
                hideOverlayFromScreenSharing: false
            )
        self.init(
            transcription: transcription,
            translation: translation,
            rewrite: rewrite,
            meeting: meeting
        )
    }
}
