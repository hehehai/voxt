// FeatureSettingsStore.swift
// Provides Feature Settings Store for feature settings.

import Foundation

enum FeatureSettingsStore {
    static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        removeObsoleteLatencyProfileKeys(defaults: defaults)
        enforceAlwaysOnLegacyFlags(defaults: defaults)
        guard loadRaw(defaults: defaults) == nil else {
            return
        }
        save(deriveFromLegacy(defaults: defaults), defaults: defaults)
    }

    static func load(defaults: UserDefaults = .standard) -> FeatureSettings {
        removeObsoleteLatencyProfileKeys(defaults: defaults)
        enforceAlwaysOnLegacyFlags(defaults: defaults)
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
        removeObsoleteLatencyProfileKeys(defaults: defaults)
        enforceAlwaysOnLegacyFlags(defaults: defaults)
        let sanitized = sanitize(settings, defaults: defaults)
        let storageReady = storageRepresentation(for: sanitized)
        if let data = try? JSONEncoder().encode(storageReady),
           let raw = String(data: data, encoding: .utf8) {
            defaults.set(raw, forKey: AppPreferenceKey.featureSettings)
        }
        // Keep feature-specific keys that runtime flows still read in sync.
        // VAD mode is global and is not read from or written to meeting settings.
        syncLegacyTranscription(storageReady.transcription, defaults: defaults)
        syncLegacyTranslation(storageReady.translation, defaults: defaults)
        syncLegacyRewrite(storageReady.rewrite, defaults: defaults)
        syncLegacyMeeting(storageReady.meeting, defaults: defaults)
        NotificationCenter.default.post(name: .voxtFeatureSettingsDidChange, object: nil)
    }

    static func update(defaults: UserDefaults = .standard, _ mutate: (inout FeatureSettings) -> Void) {
        var settings = load(defaults: defaults)
        mutate(&settings)
        save(settings, defaults: defaults)
    }

    static func saveTranscriptionPrompt(
        _ prompt: String,
        presetID: String? = nil,
        defaults: UserDefaults = .standard
    ) {
        update(defaults: defaults) { settings in
            settings.transcription.prompt = AppPromptDefaults.canonicalStoredText(prompt, kind: .enhancement)
            settings.transcription.promptPresetID = presetID
        }
    }

    static func saveTranslationPrompt(
        _ prompt: String,
        presetID: String? = nil,
        defaults: UserDefaults = .standard
    ) {
        update(defaults: defaults) { settings in
            settings.translation.prompt = AppPromptDefaults.canonicalStoredText(prompt, kind: .translation)
            settings.translation.promptPresetID = presetID
        }
    }

    static func saveRewritePrompt(
        _ prompt: String,
        presetID: String? = nil,
        defaults: UserDefaults = .standard
    ) {
        update(defaults: defaults) { settings in
            settings.rewrite.prompt = AppPromptDefaults.canonicalStoredText(prompt, kind: .rewrite)
            settings.rewrite.promptPresetID = presetID
        }
    }

    private static func removeObsoleteLatencyProfileKeys(defaults: UserDefaults) {
        defaults.removeObject(forKey: "enhancementLatencyProfile")
        defaults.removeObject(forKey: "translationLatencyProfile")
        defaults.removeObject(forKey: "rewriteLatencyProfile")
    }

    private static func enforceAlwaysOnLegacyFlags(defaults: UserDefaults) {
        defaults.set(true, forKey: AppPreferenceKey.translateSelectedTextOnTranslationHotkey)
        defaults.set(true, forKey: AppPreferenceKey.appEnhancementEnabled)
    }

    static func deriveFromLegacy(defaults: UserDefaults = .standard) -> FeatureSettings {
        let transcriptionASR = legacyASRSelection(defaults: defaults)
        let transcriptionText = legacyTranscriptionTextSelection(defaults: defaults)
        let translationText = legacyTranslationSelection(defaults: defaults)
        let rewriteText = legacyRewriteSelection(defaults: defaults)
        let promptLanguage = AppPromptDefaults.interfaceLanguage(from: defaults)
        let transcriptionPrompt = AppPromptDefaults.resolvedStoredText(
            defaults.string(forKey: AppPreferenceKey.enhancementSystemPrompt),
            kind: .enhancement,
            defaults: defaults
        )
        let translationPrompt = AppPromptDefaults.resolvedStoredText(
            defaults.string(forKey: AppPreferenceKey.translationSystemPrompt),
            kind: .translation,
            defaults: defaults
        )
        let rewritePrompt = AppPromptDefaults.resolvedStoredText(
            defaults.string(forKey: AppPreferenceKey.rewriteSystemPrompt),
            kind: .rewrite,
            defaults: defaults
        )

        return FeatureSettings(
            transcription: TranscriptionFeatureSettings(
                asrSelectionID: transcriptionASR,
                llmEnabled: (EnhancementMode(rawValue: defaults.string(forKey: AppPreferenceKey.enhancementMode) ?? "") ?? .off) != .off,
                llmSelectionID: transcriptionText,
                prompt: transcriptionPrompt,
                promptPresetID: FeaturePromptPresetCatalog.inferredPresetID(
                    storedID: nil,
                    prompt: transcriptionPrompt,
                    kind: .enhancement,
                    language: promptLanguage
                ),
                appContext: .init(),
                notes: TranscriptionNoteFeatureSettings(
                    enabled: true,
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
                prompt: translationPrompt,
                promptPresetID: FeaturePromptPresetCatalog.inferredPresetID(
                    storedID: nil,
                    prompt: translationPrompt,
                    kind: .translation,
                    language: promptLanguage
                ),
                showResultWindow: defaults.object(forKey: AppPreferenceKey.showSelectedTextTranslationResultWindow) as? Bool ?? true
            ),
            rewrite: RewriteFeatureSettings(
                asrSelectionID: transcriptionASR,
                llmSelectionID: rewriteText,
                prompt: rewritePrompt,
                promptPresetID: FeaturePromptPresetCatalog.inferredPresetID(
                    storedID: nil,
                    prompt: rewritePrompt,
                    kind: .rewrite,
                    language: promptLanguage
                ),
                appContext: .init(),
                appEnhancementEnabled: true,
                continueShortcut: .defaultShortcut
            ),
            meeting: MeetingFeatureSettings(
                asrSelectionID: supportedMeetingASRSelection(
                    transcriptionASR,
                    defaults: defaults
                ),
                summaryModelSelectionID: transcriptionText,
                summaryPrompt: "",
                summaryAutoGenerate: true,
                realtimeTranslateEnabled: false,
                realtimeTargetLanguageRawValue: defaults.string(forKey: AppPreferenceKey.meetingRealtimeTranslationTargetLanguage) ?? "",
                hideOverlayFromScreenSharing: defaults.object(forKey: AppPreferenceKey.hideMeetingOverlayFromScreenSharing) as? Bool ?? false,
                chunkingModeRawValue: MeetingChunkingMode.stored(in: defaults).rawValue,
                sileroVADSensitivityRawValue: MeetingSileroVADSensitivity.stored(defaults: defaults).rawValue,
                speakerDiarizationModelRawValue: MeetingDiarizationMode.stored(in: defaults).rawValue,
                finalTranscriptOptimizationEnabled: legacyFinalTranscriptOptimizationEnabled(defaults: defaults)
            )
        )
    }

    static func prepareLegacySession(
        from settings: FeatureSettings,
        outputMode: SessionOutputMode,
        defaults: UserDefaults = .standard
    ) {
        syncLegacyTranscription(settings.transcription, defaults: defaults)
        syncLegacyTranslation(settings.translation, defaults: defaults)
        syncLegacyRewrite(settings.rewrite, defaults: defaults)

        switch outputMode {
        case .transcription:
            syncLegacyASRSelection(settings.transcription.asrSelectionID, defaults: defaults)
        case .translation:
            syncLegacyASRSelection(settings.translation.asrSelectionID, defaults: defaults)
        case .rewrite:
            syncLegacyASRSelection(settings.rewrite.asrSelectionID, defaults: defaults)
        }
    }

    static func prepareMeetingRuntime(
        from settings: FeatureSettings,
        defaults: UserDefaults = .standard
    ) {
        let sanitizedMeeting = sanitizedMeetingSettings(settings.meeting, defaults: defaults)
        syncLegacyTranslation(settings.translation, defaults: defaults)
        syncLegacyASRSelection(sanitizedMeeting.asrSelectionID, defaults: defaults)
        syncLegacyMeeting(sanitizedMeeting, defaults: defaults)
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
        case .sherpaOnnx(let modelID):
            defaults.set(TranscriptionEngine.sherpaOnnx.rawValue, forKey: AppPreferenceKey.transcriptionEngine)
            defaults.set(modelID.rawValue, forKey: AppPreferenceKey.sherpaOnnxASRModelID)
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
        defaults.set(true, forKey: AppPreferenceKey.translateSelectedTextOnTranslationHotkey)
        defaults.set(settings.showResultWindow, forKey: AppPreferenceKey.showSelectedTextTranslationResultWindow)

        switch settings.modelSelectionID.translationSelection {
        case .localLLM(let repo):
            defaults.set(TranslationModelProvider.customLLM.rawValue, forKey: AppPreferenceKey.translationModelProvider)
            defaults.set(TranslationModelProvider.customLLM.rawValue, forKey: AppPreferenceKey.translationFallbackModelProvider)
            defaults.set(repo, forKey: AppPreferenceKey.translationCustomLLMModelRepo)
        case .localGGUF(let modelID):
            defaults.set(TranslationModelProvider.localGGUF.rawValue, forKey: AppPreferenceKey.translationModelProvider)
            defaults.set(TranslationModelProvider.localGGUF.rawValue, forKey: AppPreferenceKey.translationFallbackModelProvider)
            defaults.set(modelID.rawValue, forKey: AppPreferenceKey.translationGGUFModelID)
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
        defaults.set(settings.chunkingMode.rawValue, forKey: AppPreferenceKey.meetingChunkingMode)
        defaults.set(settings.sileroVADSensitivity.rawValue, forKey: AppPreferenceKey.meetingSileroVADSensitivity)
        defaults.set(settings.speakerDiarizationModel.rawValue, forKey: AppPreferenceKey.meetingSpeakerDiarizationModel)
        defaults.set(
            settings.finalTranscriptOptimizationEnabled,
            forKey: AppPreferenceKey.meetingFinalTranscriptOptimizationEnabled
        )
    }

    private static func sanitize(_ settings: FeatureSettings, defaults: UserDefaults) -> FeatureSettings {
        let fallback = deriveFromLegacy(defaults: defaults)
        let promptLanguage = AppPromptDefaults.interfaceLanguage(from: defaults)
        let resolvedTranscriptionPrompt = AppPromptDefaults.resolvedStoredText(
            sanitizedPrompt(settings.transcription.prompt),
            kind: .enhancement,
            defaults: defaults
        )
        let transcriptionPrompt = FeaturePromptPresetCatalog.resolvedPrompt(
            storedID: settings.transcription.promptPresetID,
            prompt: resolvedTranscriptionPrompt,
            kind: .enhancement,
            language: promptLanguage
        )
        let resolvedTranslationPrompt = AppPromptDefaults.resolvedStoredText(
            sanitizedPrompt(settings.translation.prompt),
            kind: .translation,
            defaults: defaults
        )
        let translationPrompt = FeaturePromptPresetCatalog.resolvedPrompt(
            storedID: settings.translation.promptPresetID,
            prompt: resolvedTranslationPrompt,
            kind: .translation,
            language: promptLanguage
        )
        let resolvedRewritePrompt = AppPromptDefaults.resolvedStoredText(
            sanitizedPrompt(settings.rewrite.prompt),
            kind: .rewrite,
            defaults: defaults
        )
        let rewritePrompt = FeaturePromptPresetCatalog.resolvedPrompt(
            storedID: settings.rewrite.promptPresetID,
            prompt: resolvedRewritePrompt,
            kind: .rewrite,
            language: promptLanguage
        )
        let transcriptionASR = sanitizedASRSelection(
            settings.transcription.asrSelectionID,
            fallback: fallback.transcription.asrSelectionID
        )
        let translationASR = sanitizedASRSelection(
            settings.translation.asrSelectionID,
            fallback: fallback.translation.asrSelectionID
        )
        let rewriteASR = sanitizedASRSelection(
            settings.rewrite.asrSelectionID,
            fallback: fallback.rewrite.asrSelectionID
        )
        return FeatureSettings(
            transcription: TranscriptionFeatureSettings(
                asrSelectionID: transcriptionASR,
                llmEnabled: settings.transcription.llmEnabled,
                llmSelectionID: settings.transcription.llmSelectionID.textSelection == nil ? fallback.transcription.llmSelectionID : settings.transcription.llmSelectionID,
                prompt: transcriptionPrompt,
                promptPresetID: FeaturePromptPresetCatalog.inferredPresetID(
                    storedID: settings.transcription.promptPresetID,
                    prompt: transcriptionPrompt,
                    kind: .enhancement,
                    language: promptLanguage
                ),
                appContext: settings.transcription.appContext,
                notes: sanitizedNotesSettings(
                    settings.transcription.notes,
                    fallbackSelectionID: fallback.transcription.notes.titleModelSelectionID
                )
            ),
            translation: TranslationFeatureSettings(
                asrSelectionID: translationASR,
                modelSelectionID: sanitizedTranslationSelection(
                    settings.translation.modelSelectionID,
                    fallback: fallback.translation.modelSelectionID
                ),
                targetLanguageRawValue: settings.translation.targetLanguage.rawValue,
                prompt: translationPrompt,
                promptPresetID: FeaturePromptPresetCatalog.inferredPresetID(
                    storedID: settings.translation.promptPresetID,
                    prompt: translationPrompt,
                    kind: .translation,
                    language: promptLanguage
                ),
                showResultWindow: settings.translation.showResultWindow
            ),
            rewrite: RewriteFeatureSettings(
                asrSelectionID: rewriteASR,
                llmSelectionID: settings.rewrite.llmSelectionID.textSelection == nil ? fallback.rewrite.llmSelectionID : settings.rewrite.llmSelectionID,
                prompt: rewritePrompt,
                promptPresetID: FeaturePromptPresetCatalog.inferredPresetID(
                    storedID: settings.rewrite.promptPresetID,
                    prompt: rewritePrompt,
                    kind: .rewrite,
                    language: promptLanguage
                ),
                appContext: settings.rewrite.appContext,
                appEnhancementEnabled: true,
                continueShortcut: sanitizedContinueShortcutSettings(settings.rewrite.continueShortcut)
            ),
            meeting: MeetingFeatureSettings(
                asrSelectionID: supportedMeetingASRSelection(
                    sanitizedASRSelection(
                        settings.meeting.asrSelectionID,
                        fallback: fallback.meeting.asrSelectionID
                    ),
                    defaults: defaults
                ),
                summaryModelSelectionID: settings.meeting.summaryModelSelectionID.textSelection == nil ? fallback.meeting.summaryModelSelectionID : settings.meeting.summaryModelSelectionID,
                summaryPrompt: AppPromptDefaults.resolvedStoredText(
                    sanitizedPrompt(settings.meeting.summaryPrompt),
                    kind: .transcriptSummary,
                    defaults: defaults
                ),
                summaryAutoGenerate: settings.meeting.summaryAutoGenerate,
                realtimeTranslateEnabled: settings.meeting.realtimeTranslateEnabled,
                realtimeTargetLanguageRawValue: settings.meeting.realtimeTargetLanguage?.rawValue ?? "",
                hideOverlayFromScreenSharing: settings.meeting.hideOverlayFromScreenSharing,
                chunkingModeRawValue: settings.meeting.chunkingMode.rawValue,
                sileroVADSensitivityRawValue: settings.meeting.sileroVADSensitivity.rawValue,
                speakerDiarizationModelRawValue: settings.meeting.speakerDiarizationModel.rawValue,
                finalTranscriptOptimizationEnabled: settings.meeting.finalTranscriptOptimizationEnabled
            )
        )
    }

    private static func sanitizedASRSelection(
        _ selectionID: FeatureModelSelectionID,
        fallback: FeatureModelSelectionID
    ) -> FeatureModelSelectionID {
        switch selectionID.asrSelection {
        case .dictation, .mlx, .sherpaOnnx, .remote:
            return selectionID
        case .none:
            return fallback
        }
    }

    private static func sanitizedTranslationSelection(
        _ selectionID: FeatureModelSelectionID,
        fallback: FeatureModelSelectionID
    ) -> FeatureModelSelectionID {
        switch selectionID.translationSelection {
        case .localLLM, .localGGUF, .remoteLLM:
            return selectionID
        case .none:
            return fallback
        }
    }

    private static func storageRepresentation(for settings: FeatureSettings) -> FeatureSettings {
        FeatureSettings(
            transcription: TranscriptionFeatureSettings(
                asrSelectionID: settings.transcription.asrSelectionID,
                llmEnabled: settings.transcription.llmEnabled,
                llmSelectionID: settings.transcription.llmSelectionID,
                prompt: AppPromptDefaults.canonicalStoredText(settings.transcription.prompt, kind: .enhancement),
                promptPresetID: settings.transcription.promptPresetID,
                appContext: settings.transcription.appContext,
                notes: settings.transcription.notes
            ),
            translation: TranslationFeatureSettings(
                asrSelectionID: settings.translation.asrSelectionID,
                modelSelectionID: settings.translation.modelSelectionID,
                targetLanguageRawValue: settings.translation.targetLanguageRawValue,
                prompt: AppPromptDefaults.canonicalStoredText(settings.translation.prompt, kind: .translation),
                promptPresetID: settings.translation.promptPresetID,
                showResultWindow: settings.translation.showResultWindow
            ),
            rewrite: RewriteFeatureSettings(
                asrSelectionID: settings.rewrite.asrSelectionID,
                llmSelectionID: settings.rewrite.llmSelectionID,
                prompt: AppPromptDefaults.canonicalStoredText(settings.rewrite.prompt, kind: .rewrite),
                promptPresetID: settings.rewrite.promptPresetID,
                appContext: settings.rewrite.appContext,
                appEnhancementEnabled: true,
                continueShortcut: settings.rewrite.continueShortcut
            ),
            meeting: MeetingFeatureSettings(
                asrSelectionID: settings.meeting.asrSelectionID,
                summaryModelSelectionID: settings.meeting.summaryModelSelectionID,
                summaryPrompt: AppPromptDefaults.canonicalStoredText(settings.meeting.summaryPrompt, kind: .transcriptSummary),
                summaryAutoGenerate: settings.meeting.summaryAutoGenerate,
                realtimeTranslateEnabled: settings.meeting.realtimeTranslateEnabled,
                realtimeTargetLanguageRawValue: settings.meeting.realtimeTargetLanguageRawValue,
                hideOverlayFromScreenSharing: settings.meeting.hideOverlayFromScreenSharing,
                chunkingModeRawValue: settings.meeting.chunkingMode.rawValue,
                sileroVADSensitivityRawValue: settings.meeting.sileroVADSensitivity.rawValue,
                speakerDiarizationModelRawValue: settings.meeting.speakerDiarizationModel.rawValue,
                finalTranscriptOptimizationEnabled: settings.meeting.finalTranscriptOptimizationEnabled
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
            enabled: true,
            triggerShortcut: resolvedShortcut,
            titleModelSelectionID: resolvedSelectionID,
            panel: VoxtNotePanelSettings(
                corner: settings.panel.corner,
                revealDelay: min(max(settings.panel.revealDelay, 0.2), 2.0),
                hideDelay: min(max(settings.panel.hideDelay, 0.1), 2.0),
                isTranslucent: settings.panel.isTranslucent
            ),
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
            asrSelectionID: supportedMeetingASRSelection(settings.asrSelectionID, defaults: defaults),
            summaryModelSelectionID: settings.summaryModelSelectionID,
            summaryPrompt: settings.summaryPrompt,
            summaryAutoGenerate: settings.summaryAutoGenerate,
            realtimeTranslateEnabled: settings.realtimeTranslateEnabled,
            realtimeTargetLanguageRawValue: settings.realtimeTargetLanguageRawValue,
            hideOverlayFromScreenSharing: settings.hideOverlayFromScreenSharing,
            chunkingModeRawValue: settings.chunkingMode.rawValue,
            sileroVADSensitivityRawValue: settings.sileroVADSensitivity.rawValue,
            speakerDiarizationModelRawValue: settings.speakerDiarizationModel.rawValue,
            finalTranscriptOptimizationEnabled: settings.finalTranscriptOptimizationEnabled
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
        case .none:
            return .mlx(fallbackRepo)
        case .dictation, .mlx, .sherpaOnnx, .remote:
            return selectionID
        }
    }

    private static func legacyASRSelection(defaults: UserDefaults) -> FeatureModelSelectionID {
        let engineRaw = defaults.string(forKey: AppPreferenceKey.transcriptionEngine)
        let engine = TranscriptionEngine.resolved(rawValue: engineRaw)
        switch engine {
        case .dictation:
            return .dictation
        case .mlxAudio:
            if engineRaw == "whisperKit" {
                return .mlx(
                    MLXWhisperMigrationSupport.repo(
                        forLegacyWhisperModelID: defaults.string(forKey: AppPreferenceKey.legacyWhisperModelID)
                            ?? MLXWhisperMigrationSupport.defaultLegacyModelID
                    )
                )
            }
            let storedRepo = defaults.string(forKey: AppPreferenceKey.mlxModelRepo) ?? MLXModelManager.defaultModelRepo
            if SherpaOnnxRuntimeSupport.isAvailable,
               SherpaOnnxModelCatalog.isLegacyFireRedMLXRepo(storedRepo) {
                return .sherpaOnnx(SherpaOnnxModelCatalog.fireRedModelID)
            }
            return .mlx(storedRepo)
        case .sherpaOnnx:
            return .sherpaOnnx(
                SherpaOnnxModelID(
                    rawValue: defaults.string(forKey: AppPreferenceKey.sherpaOnnxASRModelID)
                        ?? SherpaOnnxModelCatalog.defaultModelID.rawValue
                )
            )
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
        let provider = TranslationModelProvider.resolved(
            rawValue: defaults.string(forKey: AppPreferenceKey.translationModelProvider)
        )
        switch provider {
        case .customLLM:
            return .localLLM(defaults.string(forKey: AppPreferenceKey.translationCustomLLMModelRepo) ?? CustomLLMModelManager.defaultModelRepo)
        case .localGGUF:
            return .localGGUFTranslation(
                GGUFTranslationModelCatalog.resolvedModelID(
                    defaults.string(forKey: AppPreferenceKey.translationGGUFModelID)
                )
            )
        case .remoteLLM:
            let fallback = RemoteLLMProvider(rawValue: defaults.string(forKey: AppPreferenceKey.remoteLLMSelectedProvider) ?? "") ?? .openAI
            let selected = RemoteLLMProvider(rawValue: defaults.string(forKey: AppPreferenceKey.translationRemoteLLMProvider) ?? "") ?? fallback
            return .remoteLLM(selected)
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

    private static func legacyFinalTranscriptOptimizationEnabled(defaults: UserDefaults) -> Bool {
        defaults.object(forKey: AppPreferenceKey.meetingFinalTranscriptOptimizationEnabled) as? Bool
            ?? MeetingFeatureSettings.defaultFinalTranscriptOptimizationEnabled
    }

}
