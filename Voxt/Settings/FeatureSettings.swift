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

struct TranscriptionFeatureSettings: Codable, Hashable, Sendable {
    var asrSelectionID: FeatureModelSelectionID
    var llmEnabled: Bool
    var llmSelectionID: FeatureModelSelectionID
    var prompt: String

    init(
        asrSelectionID: FeatureModelSelectionID,
        llmEnabled: Bool,
        llmSelectionID: FeatureModelSelectionID,
        prompt: String
    ) {
        self.asrSelectionID = asrSelectionID
        self.llmEnabled = llmEnabled
        self.llmSelectionID = llmSelectionID
        self.prompt = prompt
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

    init(
        asrSelectionID: FeatureModelSelectionID,
        llmSelectionID: FeatureModelSelectionID,
        prompt: String,
        appEnhancementEnabled: Bool
    ) {
        self.asrSelectionID = asrSelectionID
        self.llmSelectionID = llmSelectionID
        self.prompt = prompt
        self.appEnhancementEnabled = appEnhancementEnabled
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

enum FeatureSettingsStore {
    static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        guard loadRaw(defaults: defaults) == nil else {
            let settings = load(defaults: defaults)
            syncLegacyMirror(from: settings, defaults: defaults)
            return
        }
        save(deriveFromLegacy(defaults: defaults), defaults: defaults)
    }

    static func load(defaults: UserDefaults = .standard) -> FeatureSettings {
        if let raw = loadRaw(defaults: defaults),
           let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(FeatureSettings.self, from: data) {
            return sanitize(decoded, defaults: defaults)
        }
        let derived = deriveFromLegacy(defaults: defaults)
        save(derived, defaults: defaults)
        return derived
    }

    static func save(_ settings: FeatureSettings, defaults: UserDefaults = .standard) {
        let sanitized = sanitize(settings, defaults: defaults)
        if let data = try? JSONEncoder().encode(sanitized),
           let raw = String(data: data, encoding: .utf8) {
            defaults.set(raw, forKey: AppPreferenceKey.featureSettings)
        }
        syncLegacyMirror(from: sanitized, defaults: defaults)
    }

    static func update(defaults: UserDefaults = .standard, _ mutate: (inout FeatureSettings) -> Void) {
        var settings = load(defaults: defaults)
        mutate(&settings)
        save(settings, defaults: defaults)
    }

    private static func loadRaw(defaults: UserDefaults) -> String? {
        defaults.string(forKey: AppPreferenceKey.featureSettings)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func deriveFromLegacy(defaults: UserDefaults = .standard) -> FeatureSettings {
        let transcriptionASR = legacyASRSelection(defaults: defaults)
        let transcriptionText = legacyTranscriptionTextSelection(defaults: defaults)
        let translationText = legacyTranslationSelection(defaults: defaults)
        let rewriteText = legacyRewriteSelection(defaults: defaults)
        let meetingSummary = legacyMeetingSummarySelection(defaults: defaults)

        return FeatureSettings(
            transcription: TranscriptionFeatureSettings(
                asrSelectionID: transcriptionASR,
                llmEnabled: (EnhancementMode(rawValue: defaults.string(forKey: AppPreferenceKey.enhancementMode) ?? "") ?? .off) != .off,
                llmSelectionID: transcriptionText,
                prompt: defaults.string(forKey: AppPreferenceKey.enhancementSystemPrompt) ?? AppPreferenceKey.defaultEnhancementPrompt
            ),
            translation: TranslationFeatureSettings(
                asrSelectionID: transcriptionASR,
                modelSelectionID: translationText,
                targetLanguageRawValue: (TranslationTargetLanguage(rawValue: defaults.string(forKey: AppPreferenceKey.translationTargetLanguage) ?? "") ?? .english).rawValue,
                prompt: defaults.string(forKey: AppPreferenceKey.translationSystemPrompt) ?? AppPreferenceKey.defaultTranslationPrompt,
                replaceSelectedText: defaults.object(forKey: AppPreferenceKey.translateSelectedTextOnTranslationHotkey) as? Bool ?? true
            ),
            rewrite: RewriteFeatureSettings(
                asrSelectionID: transcriptionASR,
                llmSelectionID: rewriteText,
                prompt: defaults.string(forKey: AppPreferenceKey.rewriteSystemPrompt) ?? AppPreferenceKey.defaultRewritePrompt,
                appEnhancementEnabled: defaults.object(forKey: AppPreferenceKey.appEnhancementEnabled) as? Bool ?? false
            ),
            meeting: MeetingFeatureSettings(
                enabled: defaults.object(forKey: AppPreferenceKey.meetingNotesBetaEnabled) as? Bool ?? false,
                asrSelectionID: transcriptionASR,
                summaryModelSelectionID: meetingSummary,
                summaryPrompt: defaults.string(forKey: AppPreferenceKey.meetingSummaryPromptTemplate) ?? AppPreferenceKey.defaultMeetingSummaryPrompt,
                summaryAutoGenerate: defaults.object(forKey: AppPreferenceKey.meetingSummaryAutoGenerate) as? Bool ?? true,
                realtimeTranslateEnabled: defaults.object(forKey: AppPreferenceKey.meetingRealtimeTranslateEnabled) as? Bool ?? false,
                realtimeTargetLanguageRawValue: defaults.string(forKey: AppPreferenceKey.meetingRealtimeTranslationTargetLanguage) ?? "",
                showOverlayInScreenShare: defaults.object(forKey: AppPreferenceKey.hideMeetingOverlayFromScreenSharing) as? Bool ?? false
            )
        )
    }

    static func syncLegacyMirror(from settings: FeatureSettings, defaults: UserDefaults = .standard) {
        syncLegacyASRSelection(settings.transcription.asrSelectionID, defaults: defaults)
        syncLegacyTranscription(settings.transcription, defaults: defaults)
        syncLegacyTranslation(settings.translation, defaults: defaults)
        syncLegacyRewrite(settings.rewrite, defaults: defaults)
        syncLegacyMeeting(settings.meeting, defaults: defaults)
    }

    static func prepareLegacySession(
        from settings: FeatureSettings,
        outputMode: SessionOutputMode,
        defaults: UserDefaults = .standard
    ) {
        syncLegacyTranscription(settings.transcription, defaults: defaults)
        syncLegacyTranslation(settings.translation, defaults: defaults)
        syncLegacyRewrite(settings.rewrite, defaults: defaults)
        syncLegacyMeeting(settings.meeting, defaults: defaults)

        switch outputMode {
        case .transcription:
            syncLegacyASRSelection(settings.transcription.asrSelectionID, defaults: defaults)
        case .translation:
            syncLegacyASRSelection(settings.translation.asrSelectionID, defaults: defaults)
        case .rewrite:
            syncLegacyASRSelection(settings.rewrite.asrSelectionID, defaults: defaults)
        }
    }

    static func prepareLegacyMeeting(
        from settings: FeatureSettings,
        defaults: UserDefaults = .standard
    ) {
        syncLegacyMeeting(settings.meeting, defaults: defaults)
        syncLegacyTranslation(settings.translation, defaults: defaults)
        syncLegacyASRSelection(settings.meeting.asrSelectionID, defaults: defaults)
    }

    private static func syncLegacyASRSelection(_ selectionID: FeatureModelSelectionID, defaults: UserDefaults) {
        switch selectionID.asrSelection {
        case .dictation:
            defaults.set(TranscriptionEngine.dictation.rawValue, forKey: AppPreferenceKey.transcriptionEngine)
        case .mlx(let repo):
            defaults.set(TranscriptionEngine.mlxAudio.rawValue, forKey: AppPreferenceKey.transcriptionEngine)
            defaults.set(MLXModelManager.canonicalModelRepo(repo), forKey: AppPreferenceKey.mlxModelRepo)
        case .whisper(let modelID):
            defaults.set(TranscriptionEngine.whisperKit.rawValue, forKey: AppPreferenceKey.transcriptionEngine)
            defaults.set(WhisperKitModelManager.canonicalModelID(modelID), forKey: AppPreferenceKey.whisperModelID)
        case .remote(let provider):
            defaults.set(TranscriptionEngine.remote.rawValue, forKey: AppPreferenceKey.transcriptionEngine)
            defaults.set(provider.rawValue, forKey: AppPreferenceKey.remoteASRSelectedProvider)
        case .none:
            defaults.set(TranscriptionEngine.mlxAudio.rawValue, forKey: AppPreferenceKey.transcriptionEngine)
        }
    }

    private static func syncLegacyTranscription(_ settings: TranscriptionFeatureSettings, defaults: UserDefaults) {
        defaults.set(settings.prompt, forKey: AppPreferenceKey.enhancementSystemPrompt)
        guard settings.llmEnabled else {
            defaults.set(EnhancementMode.off.rawValue, forKey: AppPreferenceKey.enhancementMode)
            return
        }

        switch settings.llmSelectionID.textSelection {
        case .appleIntelligence:
            defaults.set(EnhancementMode.appleIntelligence.rawValue, forKey: AppPreferenceKey.enhancementMode)
        case .localLLM(let repo):
            defaults.set(EnhancementMode.customLLM.rawValue, forKey: AppPreferenceKey.enhancementMode)
            defaults.set(repo, forKey: AppPreferenceKey.customLLMModelRepo)
        case .remoteLLM(let provider):
            defaults.set(EnhancementMode.remoteLLM.rawValue, forKey: AppPreferenceKey.enhancementMode)
            defaults.set(provider.rawValue, forKey: AppPreferenceKey.remoteLLMSelectedProvider)
        case .none:
            defaults.set(EnhancementMode.off.rawValue, forKey: AppPreferenceKey.enhancementMode)
        }
    }

    private static func syncLegacyTranslation(_ settings: TranslationFeatureSettings, defaults: UserDefaults) {
        defaults.set(settings.prompt, forKey: AppPreferenceKey.translationSystemPrompt)
        defaults.set(settings.targetLanguage.rawValue, forKey: AppPreferenceKey.translationTargetLanguage)
        defaults.set(settings.replaceSelectedText, forKey: AppPreferenceKey.translateSelectedTextOnTranslationHotkey)

        switch settings.modelSelectionID.translationSelection {
        case .whisperDirectTranslate:
            defaults.set(TranslationModelProvider.whisperKit.rawValue, forKey: AppPreferenceKey.translationModelProvider)
            defaults.set(TranslationModelProvider.customLLM.rawValue, forKey: AppPreferenceKey.translationFallbackModelProvider)
        case .localLLM(let repo):
            defaults.set(TranslationModelProvider.customLLM.rawValue, forKey: AppPreferenceKey.translationModelProvider)
            defaults.set(TranslationModelProvider.customLLM.rawValue, forKey: AppPreferenceKey.translationFallbackModelProvider)
            defaults.set(repo, forKey: AppPreferenceKey.translationCustomLLMModelRepo)
        case .remoteLLM(let provider):
            defaults.set(TranslationModelProvider.remoteLLM.rawValue, forKey: AppPreferenceKey.translationModelProvider)
            defaults.set(TranslationModelProvider.remoteLLM.rawValue, forKey: AppPreferenceKey.translationFallbackModelProvider)
            defaults.set(provider.rawValue, forKey: AppPreferenceKey.translationRemoteLLMProvider)
        case .none:
            defaults.set(TranslationModelProvider.customLLM.rawValue, forKey: AppPreferenceKey.translationModelProvider)
        }
    }

    private static func syncLegacyRewrite(_ settings: RewriteFeatureSettings, defaults: UserDefaults) {
        defaults.set(settings.prompt, forKey: AppPreferenceKey.rewriteSystemPrompt)
        defaults.set(settings.appEnhancementEnabled, forKey: AppPreferenceKey.appEnhancementEnabled)

        switch settings.llmSelectionID.textSelection {
        case .appleIntelligence:
            defaults.set(RewriteModelProvider.customLLM.rawValue, forKey: AppPreferenceKey.rewriteModelProvider)
        case .localLLM(let repo):
            defaults.set(RewriteModelProvider.customLLM.rawValue, forKey: AppPreferenceKey.rewriteModelProvider)
            defaults.set(repo, forKey: AppPreferenceKey.rewriteCustomLLMModelRepo)
        case .remoteLLM(let provider):
            defaults.set(RewriteModelProvider.remoteLLM.rawValue, forKey: AppPreferenceKey.rewriteModelProvider)
            defaults.set(provider.rawValue, forKey: AppPreferenceKey.rewriteRemoteLLMProvider)
        case .none:
            defaults.set(RewriteModelProvider.customLLM.rawValue, forKey: AppPreferenceKey.rewriteModelProvider)
        }
    }

    private static func syncLegacyMeeting(_ settings: MeetingFeatureSettings, defaults: UserDefaults) {
        defaults.set(settings.enabled, forKey: AppPreferenceKey.meetingNotesBetaEnabled)
        defaults.set(settings.summaryPrompt, forKey: AppPreferenceKey.meetingSummaryPromptTemplate)
        defaults.set(settings.summaryAutoGenerate, forKey: AppPreferenceKey.meetingSummaryAutoGenerate)
        defaults.set(settings.realtimeTranslateEnabled, forKey: AppPreferenceKey.meetingRealtimeTranslateEnabled)
        defaults.set(settings.realtimeTargetLanguageRawValue, forKey: AppPreferenceKey.meetingRealtimeTranslationTargetLanguage)
        defaults.set(settings.showOverlayInScreenShare, forKey: AppPreferenceKey.hideMeetingOverlayFromScreenSharing)
        defaults.set(legacyMeetingSummarySelectionID(for: settings.summaryModelSelectionID), forKey: AppPreferenceKey.meetingSummaryModelSelection)
    }

    private static func sanitize(_ settings: FeatureSettings, defaults: UserDefaults) -> FeatureSettings {
        let fallback = deriveFromLegacy(defaults: defaults)
        return FeatureSettings(
            transcription: TranscriptionFeatureSettings(
                asrSelectionID: settings.transcription.asrSelectionID.asrSelection == nil ? fallback.transcription.asrSelectionID : settings.transcription.asrSelectionID,
                llmEnabled: settings.transcription.llmEnabled,
                llmSelectionID: settings.transcription.llmSelectionID.textSelection == nil ? fallback.transcription.llmSelectionID : settings.transcription.llmSelectionID,
                prompt: sanitizedPrompt(settings.transcription.prompt, fallback: AppPreferenceKey.defaultEnhancementPrompt)
            ),
            translation: TranslationFeatureSettings(
                asrSelectionID: settings.translation.asrSelectionID.asrSelection == nil ? fallback.translation.asrSelectionID : settings.translation.asrSelectionID,
                modelSelectionID: settings.translation.modelSelectionID.translationSelection == nil ? fallback.translation.modelSelectionID : settings.translation.modelSelectionID,
                targetLanguageRawValue: settings.translation.targetLanguage.rawValue,
                prompt: sanitizedPrompt(settings.translation.prompt, fallback: AppPreferenceKey.defaultTranslationPrompt),
                replaceSelectedText: settings.translation.replaceSelectedText
            ),
            rewrite: RewriteFeatureSettings(
                asrSelectionID: settings.rewrite.asrSelectionID.asrSelection == nil ? fallback.rewrite.asrSelectionID : settings.rewrite.asrSelectionID,
                llmSelectionID: settings.rewrite.llmSelectionID.textSelection == nil ? fallback.rewrite.llmSelectionID : settings.rewrite.llmSelectionID,
                prompt: sanitizedPrompt(settings.rewrite.prompt, fallback: AppPreferenceKey.defaultRewritePrompt),
                appEnhancementEnabled: settings.rewrite.appEnhancementEnabled
            ),
            meeting: MeetingFeatureSettings(
                enabled: settings.meeting.enabled,
                asrSelectionID: settings.meeting.asrSelectionID.asrSelection == nil ? fallback.meeting.asrSelectionID : settings.meeting.asrSelectionID,
                summaryModelSelectionID: settings.meeting.summaryModelSelectionID.textSelection == nil ? fallback.meeting.summaryModelSelectionID : settings.meeting.summaryModelSelectionID,
                summaryPrompt: sanitizedPrompt(settings.meeting.summaryPrompt, fallback: AppPreferenceKey.defaultMeetingSummaryPrompt),
                summaryAutoGenerate: settings.meeting.summaryAutoGenerate,
                realtimeTranslateEnabled: settings.meeting.realtimeTranslateEnabled,
                realtimeTargetLanguageRawValue: settings.meeting.realtimeTargetLanguage?.rawValue ?? "",
                showOverlayInScreenShare: settings.meeting.showOverlayInScreenShare
            )
        )
    }

    private static func sanitizedPrompt(_ prompt: String, fallback: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : prompt
    }

    private static func legacyASRSelection(defaults: UserDefaults) -> FeatureModelSelectionID {
        let engine = TranscriptionEngine(rawValue: defaults.string(forKey: AppPreferenceKey.transcriptionEngine) ?? "") ?? .mlxAudio
        switch engine {
        case .dictation:
            return .dictation
        case .mlxAudio:
            return .mlx(defaults.string(forKey: AppPreferenceKey.mlxModelRepo) ?? MLXModelManager.defaultModelRepo)
        case .whisperKit:
            return .whisper(defaults.string(forKey: AppPreferenceKey.whisperModelID) ?? WhisperKitModelManager.defaultModelID)
        case .remote:
            let provider = RemoteASRProvider(rawValue: defaults.string(forKey: AppPreferenceKey.remoteASRSelectedProvider) ?? "") ?? .openAIWhisper
            return .remoteASR(provider)
        }
    }

    private static func legacyTranscriptionTextSelection(defaults: UserDefaults) -> FeatureModelSelectionID {
        let mode = EnhancementMode(rawValue: defaults.string(forKey: AppPreferenceKey.enhancementMode) ?? "") ?? .off
        switch mode {
        case .appleIntelligence:
            return .appleIntelligence
        case .customLLM, .off:
            return .localLLM(defaults.string(forKey: AppPreferenceKey.customLLMModelRepo) ?? CustomLLMModelManager.defaultModelRepo)
        case .remoteLLM:
            let provider = RemoteLLMProvider(rawValue: defaults.string(forKey: AppPreferenceKey.remoteLLMSelectedProvider) ?? "") ?? .openAI
            return .remoteLLM(provider)
        }
    }

    private static func legacyTranslationSelection(defaults: UserDefaults) -> FeatureModelSelectionID {
        let provider = TranslationModelProvider(rawValue: defaults.string(forKey: AppPreferenceKey.translationModelProvider) ?? "") ?? .customLLM
        switch provider {
        case .customLLM:
            return .localLLM(defaults.string(forKey: AppPreferenceKey.translationCustomLLMModelRepo) ?? CustomLLMModelManager.defaultModelRepo)
        case .remoteLLM:
            let fallback = RemoteLLMProvider(rawValue: defaults.string(forKey: AppPreferenceKey.remoteLLMSelectedProvider) ?? "") ?? .openAI
            let selected = RemoteLLMProvider(rawValue: defaults.string(forKey: AppPreferenceKey.translationRemoteLLMProvider) ?? "") ?? fallback
            return .remoteLLM(selected)
        case .whisperKit:
            return .whisperDirectTranslate
        }
    }

    private static func legacyRewriteSelection(defaults: UserDefaults) -> FeatureModelSelectionID {
        let provider = RewriteModelProvider(rawValue: defaults.string(forKey: AppPreferenceKey.rewriteModelProvider) ?? "") ?? .customLLM
        switch provider {
        case .customLLM:
            return .localLLM(defaults.string(forKey: AppPreferenceKey.rewriteCustomLLMModelRepo) ?? CustomLLMModelManager.defaultModelRepo)
        case .remoteLLM:
            let fallback = RemoteLLMProvider(rawValue: defaults.string(forKey: AppPreferenceKey.remoteLLMSelectedProvider) ?? "") ?? .openAI
            let selected = RemoteLLMProvider(rawValue: defaults.string(forKey: AppPreferenceKey.rewriteRemoteLLMProvider) ?? "") ?? fallback
            return .remoteLLM(selected)
        }
    }

    private static func legacyMeetingSummarySelection(defaults: UserDefaults) -> FeatureModelSelectionID {
        if let migrated = FeatureModelSelectionID.fromLegacyMeetingSummarySelection(
            defaults.string(forKey: AppPreferenceKey.meetingSummaryModelSelection)
        ) {
            return migrated
        }
        return legacyTranscriptionTextSelection(defaults: defaults)
    }

    private static func legacyMeetingSummarySelectionID(for selectionID: FeatureModelSelectionID) -> String {
        switch selectionID.textSelection {
        case .appleIntelligence:
            return FeatureModelSelectionID.appleIntelligence.rawValue
        case .localLLM(let repo):
            return "custom-llm:\(repo)"
        case .remoteLLM(let provider):
            return "remote-llm:\(provider.rawValue)"
        case .none:
            return ""
        }
    }
}
