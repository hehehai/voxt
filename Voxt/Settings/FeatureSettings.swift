import Foundation

struct FeatureModelSelectionID: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
    let rawValue: String

    var id: String { rawValue }

    init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static let dictation = Self(rawValue: "dictation")
    static let appleIntelligence = Self(rawValue: "apple-intelligence")
    static let whisperDirectTranslate = Self(rawValue: "whisper-direct-translate")

    static func mlx(_ repo: String) -> Self {
        Self(rawValue: "mlx:\(MLXModelManager.canonicalModelRepo(repo))")
    }

    static func whisper(_ modelID: String) -> Self {
        Self(rawValue: "whisper:\(WhisperKitModelManager.canonicalModelID(modelID))")
    }

    static func remoteASR(_ provider: RemoteASRProvider) -> Self {
        Self(rawValue: "remote-asr:\(provider.rawValue)")
    }

    static func localLLM(_ repo: String) -> Self {
        Self(rawValue: "local-llm:\(repo)")
    }

    static func remoteLLM(_ provider: RemoteLLMProvider) -> Self {
        Self(rawValue: "remote-llm:\(provider.rawValue)")
    }

    enum ASRSelection: Hashable, Sendable {
        case dictation
        case mlx(repo: String)
        case whisper(modelID: String)
        case remote(provider: RemoteASRProvider)
    }

    enum TextSelection: Hashable, Sendable {
        case appleIntelligence
        case localLLM(repo: String)
        case remoteLLM(provider: RemoteLLMProvider)
    }

    enum TranslationSelection: Hashable, Sendable {
        case whisperDirectTranslate
        case localLLM(repo: String)
        case remoteLLM(provider: RemoteLLMProvider)
    }

    var asrSelection: ASRSelection? {
        if rawValue == Self.dictation.rawValue {
            return .dictation
        }
        if let repo = payload(after: "mlx:") {
            return .mlx(repo: MLXModelManager.canonicalModelRepo(repo))
        }
        if let modelID = payload(after: "whisper:") {
            return .whisper(modelID: WhisperKitModelManager.canonicalModelID(modelID))
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
        if rawValue == Self.whisperDirectTranslate.rawValue {
            return .whisperDirectTranslate
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

    private func payload(after prefix: String) -> String? {
        guard rawValue.hasPrefix(prefix) else { return nil }
        let value = String(rawValue.dropFirst(prefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static func fromLegacyMeetingSummarySelection(_ rawValue: String?) -> Self? {
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

    init(
        enabled: Bool = false,
        triggerShortcut: TranscriptionNoteTriggerSettings = .defaultShortcut,
        titleModelSelectionID: FeatureModelSelectionID,
        soundEnabled: Bool = false,
        soundPreset: InteractionSoundPreset = .soft,
        obsidianSync: ObsidianNoteSyncSettings = .init()
    ) {
        self.enabled = enabled
        self.triggerShortcut = triggerShortcut
        self.titleModelSelectionID = titleModelSelectionID
        self.soundEnabled = soundEnabled
        self.soundPreset = soundPreset
        self.obsidianSync = obsidianSync
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case triggerShortcut
        case titleModelSelectionID
        case soundEnabled
        case soundPreset
        case obsidianSync
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        triggerShortcut = try container.decodeIfPresent(TranscriptionNoteTriggerSettings.self, forKey: .triggerShortcut) ?? .defaultShortcut
        titleModelSelectionID = try container.decode(FeatureModelSelectionID.self, forKey: .titleModelSelectionID)
        soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? false
        soundPreset = try container.decodeIfPresent(InteractionSoundPreset.self, forKey: .soundPreset) ?? .soft
        obsidianSync = try container.decodeIfPresent(ObsidianNoteSyncSettings.self, forKey: .obsidianSync) ?? .init()
    }
}

struct TranscriptionFeatureSettings: Codable, Hashable, Sendable {
    var asrSelectionID: FeatureModelSelectionID
    var llmEnabled: Bool
    var llmSelectionID: FeatureModelSelectionID
    var prompt: String
    var notes: TranscriptionNoteFeatureSettings

    init(
        asrSelectionID: FeatureModelSelectionID,
        llmEnabled: Bool,
        llmSelectionID: FeatureModelSelectionID,
        prompt: String,
        notes: TranscriptionNoteFeatureSettings? = nil
    ) {
        self.asrSelectionID = asrSelectionID
        self.llmEnabled = llmEnabled
        self.llmSelectionID = llmSelectionID
        self.prompt = prompt
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
            notes: decodedNotes
        )
    }
}

struct TranslationFeatureSettings: Codable, Hashable, Sendable {
    var asrSelectionID: FeatureModelSelectionID
    var modelSelectionID: FeatureModelSelectionID
    var targetLanguageRawValue: String
    var prompt: String
    var replaceSelectedText: Bool

    init(
        asrSelectionID: FeatureModelSelectionID,
        modelSelectionID: FeatureModelSelectionID,
        targetLanguageRawValue: String,
        prompt: String,
        replaceSelectedText: Bool
    ) {
        self.asrSelectionID = asrSelectionID
        self.modelSelectionID = modelSelectionID
        self.targetLanguageRawValue = targetLanguageRawValue
        self.prompt = prompt
        self.replaceSelectedText = replaceSelectedText
    }

    var targetLanguage: TranslationTargetLanguage {
        TranslationTargetLanguage(rawValue: targetLanguageRawValue) ?? .english
    }
}

struct RewriteFeatureSettings: Codable, Hashable, Sendable {
    var asrSelectionID: FeatureModelSelectionID
    var llmSelectionID: FeatureModelSelectionID
    var prompt: String
    var appEnhancementEnabled: Bool
    var continueShortcut: TranscriptionContinueShortcutSettings

    init(
        asrSelectionID: FeatureModelSelectionID,
        llmSelectionID: FeatureModelSelectionID,
        prompt: String,
        appEnhancementEnabled: Bool,
        continueShortcut: TranscriptionContinueShortcutSettings = .defaultShortcut
    ) {
        self.asrSelectionID = asrSelectionID
        self.llmSelectionID = llmSelectionID
        self.prompt = prompt
        self.appEnhancementEnabled = appEnhancementEnabled
        self.continueShortcut = continueShortcut
    }

    private enum CodingKeys: String, CodingKey {
        case asrSelectionID
        case llmSelectionID
        case prompt
        case appEnhancementEnabled
        case continueShortcut
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            asrSelectionID: try container.decode(FeatureModelSelectionID.self, forKey: .asrSelectionID),
            llmSelectionID: try container.decode(FeatureModelSelectionID.self, forKey: .llmSelectionID),
            prompt: try container.decode(String.self, forKey: .prompt),
            appEnhancementEnabled: try container.decode(Bool.self, forKey: .appEnhancementEnabled),
            continueShortcut: try container.decodeIfPresent(TranscriptionContinueShortcutSettings.self, forKey: .continueShortcut) ?? .defaultShortcut
        )
    }
}

struct MeetingFeatureSettings: Codable, Hashable, Sendable {
    var enabled: Bool
    var asrSelectionID: FeatureModelSelectionID
    var summaryModelSelectionID: FeatureModelSelectionID
    var summaryPrompt: String
    var summaryAutoGenerate: Bool
    var realtimeTranslateEnabled: Bool
    var realtimeTargetLanguageRawValue: String
    var showOverlayInScreenShare: Bool

    init(
        enabled: Bool,
        asrSelectionID: FeatureModelSelectionID,
        summaryModelSelectionID: FeatureModelSelectionID,
        summaryPrompt: String,
        summaryAutoGenerate: Bool,
        realtimeTranslateEnabled: Bool,
        realtimeTargetLanguageRawValue: String,
        showOverlayInScreenShare: Bool
    ) {
        self.enabled = enabled
        self.asrSelectionID = asrSelectionID
        self.summaryModelSelectionID = summaryModelSelectionID
        self.summaryPrompt = summaryPrompt
        self.summaryAutoGenerate = summaryAutoGenerate
        self.realtimeTranslateEnabled = realtimeTranslateEnabled
        self.realtimeTargetLanguageRawValue = realtimeTargetLanguageRawValue
        self.showOverlayInScreenShare = showOverlayInScreenShare
    }

    var realtimeTargetLanguage: TranslationTargetLanguage? {
        guard !realtimeTargetLanguageRawValue.isEmpty else { return nil }
        return TranslationTargetLanguage(rawValue: realtimeTargetLanguageRawValue)
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
        meeting: MeetingFeatureSettings
    ) {
        self.transcription = transcription
        self.translation = translation
        self.rewrite = rewrite
        self.meeting = meeting
    }
}
