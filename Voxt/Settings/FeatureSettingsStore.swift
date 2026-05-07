import Foundation

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
        let storageReady = storageRepresentation(for: sanitized)
        if let data = try? JSONEncoder().encode(storageReady),
           let raw = String(data: data, encoding: .utf8) {
            defaults.set(raw, forKey: AppPreferenceKey.featureSettings)
        }
        syncLegacyMirror(from: storageReady, defaults: defaults)
        NotificationCenter.default.post(name: .voxtFeatureSettingsDidChange, object: nil)
    }

    static func update(defaults: UserDefaults = .standard, _ mutate: (inout FeatureSettings) -> Void) {
        var settings = load(defaults: defaults)
        mutate(&settings)
        save(settings, defaults: defaults)
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
                prompt: AppPromptDefaults.resolvedStoredText(
                    defaults.string(forKey: AppPreferenceKey.enhancementSystemPrompt),
                    kind: .enhancement,
                    defaults: defaults
                ),
                notes: TranscriptionNoteFeatureSettings(
                    enabled: false,
                    triggerShortcut: .defaultShortcut,
                    titleModelSelectionID: transcriptionText,
                    obsidianSync: .init(),
                    remindersSync: .init()
                )
            ),
            translation: TranslationFeatureSettings(
                asrSelectionID: transcriptionASR,
                modelSelectionID: translationText,
                targetLanguageRawValue: (TranslationTargetLanguage(rawValue: defaults.string(forKey: AppPreferenceKey.translationTargetLanguage) ?? "") ?? .english).rawValue,
                prompt: AppPromptDefaults.resolvedStoredText(
                    defaults.string(forKey: AppPreferenceKey.translationSystemPrompt),
                    kind: .translation,
                    defaults: defaults
                ),
                replaceSelectedText: defaults.object(forKey: AppPreferenceKey.translateSelectedTextOnTranslationHotkey) as? Bool ?? true,
                showResultWindow: defaults.object(forKey: AppPreferenceKey.showSelectedTextTranslationResultWindow) as? Bool ?? true
            ),
            rewrite: RewriteFeatureSettings(
                asrSelectionID: transcriptionASR,
                llmSelectionID: rewriteText,
                prompt: AppPromptDefaults.resolvedStoredText(
                    defaults.string(forKey: AppPreferenceKey.rewriteSystemPrompt),
                    kind: .rewrite,
                    defaults: defaults
                ),
                appEnhancementEnabled: defaults.object(forKey: AppPreferenceKey.appEnhancementEnabled) as? Bool ?? false,
                continueShortcut: .defaultShortcut
            ),
            meeting: MeetingFeatureSettings(
                enabled: defaults.object(forKey: AppPreferenceKey.meetingNotesBetaEnabled) as? Bool ?? false,
                asrSelectionID: supportedMeetingASRSelection(
                    transcriptionASR,
                    defaults: defaults
                ),
                summaryModelSelectionID: meetingSummary,
                summaryPrompt: AppPromptDefaults.resolvedStoredText(
                    defaults.string(forKey: AppPreferenceKey.meetingSummaryPromptTemplate),
                    kind: .meetingSummary,
                    defaults: defaults
                ),
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
        let sanitizedMeeting = sanitizedMeetingSettings(settings.meeting, defaults: defaults)
        syncLegacyMeeting(sanitizedMeeting, defaults: defaults)
        syncLegacyTranslation(settings.translation, defaults: defaults)
        syncLegacyASRSelection(sanitizedMeeting.asrSelectionID, defaults: defaults)
    }

    private static func loadRaw(defaults: UserDefaults) -> String? {
        defaults.string(forKey: AppPreferenceKey.featureSettings)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
        defaults.set(
            AppPromptDefaults.canonicalStoredText(settings.prompt, kind: .enhancement),
            forKey: AppPreferenceKey.enhancementSystemPrompt
        )
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
        defaults.set(
            AppPromptDefaults.canonicalStoredText(settings.prompt, kind: .translation),
            forKey: AppPreferenceKey.translationSystemPrompt
        )
        defaults.set(settings.targetLanguage.rawValue, forKey: AppPreferenceKey.translationTargetLanguage)
        defaults.set(settings.replaceSelectedText, forKey: AppPreferenceKey.translateSelectedTextOnTranslationHotkey)
        defaults.set(settings.showResultWindow, forKey: AppPreferenceKey.showSelectedTextTranslationResultWindow)

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
        defaults.set(
            AppPromptDefaults.canonicalStoredText(settings.prompt, kind: .rewrite),
            forKey: AppPreferenceKey.rewriteSystemPrompt
        )
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
        defaults.set(
            AppPromptDefaults.canonicalStoredText(settings.summaryPrompt, kind: .meetingSummary),
            forKey: AppPreferenceKey.meetingSummaryPromptTemplate
        )
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
                prompt: AppPromptDefaults.resolvedStoredText(
                    sanitizedPrompt(settings.transcription.prompt),
                    kind: .enhancement,
                    defaults: defaults
                ),
                notes: sanitizedNotesSettings(
                    settings.transcription.notes,
                    fallbackSelectionID: fallback.transcription.notes.titleModelSelectionID
                )
            ),
            translation: TranslationFeatureSettings(
                asrSelectionID: settings.translation.asrSelectionID.asrSelection == nil ? fallback.translation.asrSelectionID : settings.translation.asrSelectionID,
                modelSelectionID: settings.translation.modelSelectionID.translationSelection == nil ? fallback.translation.modelSelectionID : settings.translation.modelSelectionID,
                targetLanguageRawValue: settings.translation.targetLanguage.rawValue,
                prompt: AppPromptDefaults.resolvedStoredText(
                    sanitizedPrompt(settings.translation.prompt),
                    kind: .translation,
                    defaults: defaults
                ),
                replaceSelectedText: settings.translation.replaceSelectedText,
                showResultWindow: settings.translation.showResultWindow
            ),
            rewrite: RewriteFeatureSettings(
                asrSelectionID: settings.rewrite.asrSelectionID.asrSelection == nil ? fallback.rewrite.asrSelectionID : settings.rewrite.asrSelectionID,
                llmSelectionID: settings.rewrite.llmSelectionID.textSelection == nil ? fallback.rewrite.llmSelectionID : settings.rewrite.llmSelectionID,
                prompt: AppPromptDefaults.resolvedStoredText(
                    sanitizedPrompt(settings.rewrite.prompt),
                    kind: .rewrite,
                    defaults: defaults
                ),
                appEnhancementEnabled: settings.rewrite.appEnhancementEnabled,
                continueShortcut: sanitizedContinueShortcutSettings(settings.rewrite.continueShortcut)
            ),
            meeting: MeetingFeatureSettings(
                enabled: settings.meeting.enabled,
                asrSelectionID: supportedMeetingASRSelection(
                    settings.meeting.asrSelectionID.asrSelection == nil ? fallback.meeting.asrSelectionID : settings.meeting.asrSelectionID,
                    defaults: defaults
                ),
                summaryModelSelectionID: settings.meeting.summaryModelSelectionID.textSelection == nil ? fallback.meeting.summaryModelSelectionID : settings.meeting.summaryModelSelectionID,
                summaryPrompt: AppPromptDefaults.resolvedStoredText(
                    sanitizedPrompt(settings.meeting.summaryPrompt),
                    kind: .meetingSummary,
                    defaults: defaults
                ),
                summaryAutoGenerate: settings.meeting.summaryAutoGenerate,
                realtimeTranslateEnabled: settings.meeting.realtimeTranslateEnabled,
                realtimeTargetLanguageRawValue: settings.meeting.realtimeTargetLanguage?.rawValue ?? "",
                showOverlayInScreenShare: settings.meeting.showOverlayInScreenShare
            )
        )
    }

    private static func storageRepresentation(for settings: FeatureSettings) -> FeatureSettings {
        FeatureSettings(
            transcription: TranscriptionFeatureSettings(
                asrSelectionID: settings.transcription.asrSelectionID,
                llmEnabled: settings.transcription.llmEnabled,
                llmSelectionID: settings.transcription.llmSelectionID,
                prompt: AppPromptDefaults.canonicalStoredText(settings.transcription.prompt, kind: .enhancement),
                notes: settings.transcription.notes
            ),
            translation: TranslationFeatureSettings(
                asrSelectionID: settings.translation.asrSelectionID,
                modelSelectionID: settings.translation.modelSelectionID,
                targetLanguageRawValue: settings.translation.targetLanguageRawValue,
                prompt: AppPromptDefaults.canonicalStoredText(settings.translation.prompt, kind: .translation),
                replaceSelectedText: settings.translation.replaceSelectedText,
                showResultWindow: settings.translation.showResultWindow
            ),
            rewrite: RewriteFeatureSettings(
                asrSelectionID: settings.rewrite.asrSelectionID,
                llmSelectionID: settings.rewrite.llmSelectionID,
                prompt: AppPromptDefaults.canonicalStoredText(settings.rewrite.prompt, kind: .rewrite),
                appEnhancementEnabled: settings.rewrite.appEnhancementEnabled,
                continueShortcut: settings.rewrite.continueShortcut
            ),
            meeting: MeetingFeatureSettings(
                enabled: settings.meeting.enabled,
                asrSelectionID: settings.meeting.asrSelectionID,
                summaryModelSelectionID: settings.meeting.summaryModelSelectionID,
                summaryPrompt: AppPromptDefaults.canonicalStoredText(settings.meeting.summaryPrompt, kind: .meetingSummary),
                summaryAutoGenerate: settings.meeting.summaryAutoGenerate,
                realtimeTranslateEnabled: settings.meeting.realtimeTranslateEnabled,
                realtimeTargetLanguageRawValue: settings.meeting.realtimeTargetLanguageRawValue,
                showOverlayInScreenShare: settings.meeting.showOverlayInScreenShare
            )
        )
    }

    private static func sanitizedPrompt(_ prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : prompt
    }

    private static func sanitizedNotesSettings(
        _ settings: TranscriptionNoteFeatureSettings,
        fallbackSelectionID: FeatureModelSelectionID
    ) -> TranscriptionNoteFeatureSettings {
        let resolvedSelectionID = settings.titleModelSelectionID.textSelection == nil
            ? fallbackSelectionID
            : settings.titleModelSelectionID
        let resolvedShortcut = settings.triggerShortcut.keyCode == HotkeyPreference.modifierOnlyKeyCode
            ? TranscriptionNoteTriggerSettings.defaultShortcut
            : TranscriptionNoteTriggerSettings(
                keyCode: settings.triggerShortcut.keyCode,
                modifiers: settings.triggerShortcut.modifiers,
                sidedModifiers: settings.triggerShortcut.sidedModifiers
            )
        return TranscriptionNoteFeatureSettings(
            enabled: settings.enabled,
            triggerShortcut: resolvedShortcut,
            titleModelSelectionID: resolvedSelectionID,
            soundEnabled: settings.soundEnabled,
            soundPreset: settings.soundPreset,
            obsidianSync: sanitizedObsidianSyncSettings(settings.obsidianSync),
            remindersSync: sanitizedRemindersSyncSettings(settings.remindersSync)
        )
    }

    private static func sanitizedObsidianSyncSettings(
        _ settings: ObsidianNoteSyncSettings
    ) -> ObsidianNoteSyncSettings {
        let trimmedPath = settings.vaultPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFolder = settings.relativeFolder
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        return ObsidianNoteSyncSettings(
            enabled: settings.enabled,
            vaultPath: trimmedPath,
            vaultBookmarkData: settings.vaultBookmarkData,
            relativeFolder: trimmedFolder.isEmpty ? "Voxt" : trimmedFolder,
            groupingMode: settings.groupingMode
        )
    }

    private static func sanitizedRemindersSyncSettings(
        _ settings: RemindersNoteSyncSettings
    ) -> RemindersNoteSyncSettings {
        let trimmedIdentifier = settings.selectedListIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = settings.selectedListTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return RemindersNoteSyncSettings(
            enabled: settings.enabled,
            selectedListIdentifier: trimmedIdentifier,
            selectedListTitle: trimmedIdentifier.isEmpty ? "" : trimmedTitle
        )
    }

    private static func sanitizedContinueShortcutSettings(
        _ settings: TranscriptionContinueShortcutSettings
    ) -> TranscriptionContinueShortcutSettings {
        guard settings.keyCode != HotkeyPreference.modifierOnlyKeyCode else {
            return .defaultShortcut
        }
        return TranscriptionContinueShortcutSettings(
            keyCode: settings.keyCode,
            modifiers: settings.modifiers,
            sidedModifiers: settings.sidedModifiers
        )
    }

    private static func sanitizedMeetingSettings(
        _ settings: MeetingFeatureSettings,
        defaults: UserDefaults
    ) -> MeetingFeatureSettings {
        MeetingFeatureSettings(
            enabled: settings.enabled,
            asrSelectionID: supportedMeetingASRSelection(settings.asrSelectionID, defaults: defaults),
            summaryModelSelectionID: settings.summaryModelSelectionID,
            summaryPrompt: settings.summaryPrompt,
            summaryAutoGenerate: settings.summaryAutoGenerate,
            realtimeTranslateEnabled: settings.realtimeTranslateEnabled,
            realtimeTargetLanguageRawValue: settings.realtimeTargetLanguageRawValue,
            showOverlayInScreenShare: settings.showOverlayInScreenShare
        )
    }

    private static func supportedMeetingASRSelection(
        _ selectionID: FeatureModelSelectionID,
        defaults: UserDefaults
    ) -> FeatureModelSelectionID {
        let fallbackRepo = MLXModelManager.canonicalModelRepo(
            defaults.string(forKey: AppPreferenceKey.mlxModelRepo) ?? MLXModelManager.defaultModelRepo
        )
        switch selectionID.asrSelection {
        case .whisper:
            return .mlx(fallbackRepo)
        case .none:
            return .mlx(fallbackRepo)
        case .dictation, .mlx, .remote:
            return selectionID
        }
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
