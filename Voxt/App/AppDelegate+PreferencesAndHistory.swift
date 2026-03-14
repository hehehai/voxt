import Foundation
import AppKit
import CoreAudio

extension AppDelegate {
    var defaults: UserDefaults {
        .standard
    }

    var selectedInputDeviceID: AudioDeviceID? {
        let raw = defaults.integer(forKey: AppPreferenceKey.selectedInputDeviceID)
        return raw > 0 ? AudioDeviceID(raw) : nil
    }

    var interactionSoundsEnabled: Bool {
        defaults.bool(forKey: AppPreferenceKey.interactionSoundsEnabled)
    }

    var overlayPosition: OverlayPosition {
        enumValue(forKey: AppPreferenceKey.overlayPosition, default: .bottom)
    }

    var autoCopyWhenNoFocusedInput: Bool {
        defaults.bool(forKey: AppPreferenceKey.autoCopyWhenNoFocusedInput)
    }

    var translationTargetLanguage: TranslationTargetLanguage {
        enumValue(forKey: AppPreferenceKey.translationTargetLanguage, default: .english)
    }

    var translateSelectedTextOnTranslationHotkey: Bool {
        defaults.bool(forKey: AppPreferenceKey.translateSelectedTextOnTranslationHotkey)
    }

    var voiceEndCommandEnabled: Bool {
        defaults.bool(forKey: AppPreferenceKey.voiceEndCommandEnabled)
    }

    var voiceEndCommandPreset: VoiceEndCommandPreset {
        if let preset = enumValue(forKey: AppPreferenceKey.voiceEndCommandPreset, default: Optional<VoiceEndCommandPreset>.none) {
            return preset
        }

        let legacyCustomValue = trimmedStringValue(forKey: AppPreferenceKey.voiceEndCommandText)
        return legacyCustomValue.isEmpty ? .over : .custom
    }

    var voiceEndCommandText: String {
        if let presetCommand = voiceEndCommandPreset.resolvedCommand {
            return presetCommand
        }
        return trimmedStringValue(forKey: AppPreferenceKey.voiceEndCommandText)
    }

    var translationSystemPrompt: String {
        let value = defaults.string(forKey: AppPreferenceKey.translationSystemPrompt)
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        return AppPreferenceKey.defaultTranslationPrompt
    }

    var translationCustomLLMRepo: String {
        let value = defaults.string(forKey: AppPreferenceKey.translationCustomLLMModelRepo)
        if let value, !value.isEmpty {
            return value
        }
        return defaults.string(forKey: AppPreferenceKey.customLLMModelRepo)
            ?? CustomLLMModelManager.defaultModelRepo
    }

    var translationModelProvider: TranslationModelProvider {
        enumValue(forKey: AppPreferenceKey.translationModelProvider, default: .customLLM)
    }

    var remoteASRSelectedProvider: RemoteASRProvider {
        enumValue(forKey: AppPreferenceKey.remoteASRSelectedProvider, default: .openAIWhisper)
    }

    var remoteLLMSelectedProvider: RemoteLLMProvider {
        enumValue(forKey: AppPreferenceKey.remoteLLMSelectedProvider, default: .openAI)
    }

    var translationRemoteLLMProvider: RemoteLLMProvider? {
        enumValue(forKey: AppPreferenceKey.translationRemoteLLMProvider, default: Optional<RemoteLLMProvider>.none)
    }

    var rewriteSystemPrompt: String {
        let value = defaults.string(forKey: AppPreferenceKey.rewriteSystemPrompt)
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        return AppPreferenceKey.defaultRewritePrompt
    }

    var rewriteCustomLLMRepo: String {
        let value = defaults.string(forKey: AppPreferenceKey.rewriteCustomLLMModelRepo)
        if let value, !value.isEmpty {
            return value
        }
        return defaults.string(forKey: AppPreferenceKey.customLLMModelRepo)
            ?? CustomLLMModelManager.defaultModelRepo
    }

    var rewriteModelProvider: RewriteModelProvider {
        enumValue(forKey: AppPreferenceKey.rewriteModelProvider, default: .customLLM)
    }

    var rewriteRemoteLLMProvider: RemoteLLMProvider? {
        enumValue(forKey: AppPreferenceKey.rewriteRemoteLLMProvider, default: Optional<RemoteLLMProvider>.none)
    }

    var remoteASRConfigurations: [String: RemoteProviderConfiguration] {
        remoteConfigurations(forKey: AppPreferenceKey.remoteASRProviderConfigurations)
    }

    var remoteLLMConfigurations: [String: RemoteProviderConfiguration] {
        remoteConfigurations(forKey: AppPreferenceKey.remoteLLMProviderConfigurations)
    }

    var showInDock: Bool {
        defaults.bool(forKey: AppPreferenceKey.showInDock)
    }

    var historyEnabled: Bool {
        defaults.bool(forKey: AppPreferenceKey.historyEnabled)
    }

    var autoCheckForUpdates: Bool {
        defaults.bool(forKey: AppPreferenceKey.autoCheckForUpdates)
    }

    func appendHistoryIfNeeded(text: String, llmDurationSeconds: TimeInterval?) {
        guard historyEnabled else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let metadata = currentHistoryMetadata()

        let now = Date()
        let audioDuration = resolvedDuration(from: recordingStartedAt, to: recordingStoppedAt ?? now)
        // ASR processing duration should exclude LLM enhancement time.
        // Measure from recording stop to first ASR text callback when available.
        let processingEnd = transcriptionResultReceivedAt ?? now
        let processingDuration = resolvedDuration(from: transcriptionProcessingStartedAt, to: processingEnd)

        historyStore.append(
            text: trimmed,
            transcriptionEngine: transcriptionEngine.title,
            transcriptionModel: metadata.transcriptionModel,
            enhancementMode: enhancementMode.title,
            enhancementModel: metadata.enhancementModel,
            kind: resolvedHistoryKind(),
            isTranslation: sessionOutputMode == .translation,
            audioDurationSeconds: audioDuration,
            transcriptionProcessingDurationSeconds: processingDuration,
            llmDurationSeconds: llmDurationSeconds,
            focusedAppName: metadata.focusedAppName,
            matchedAppGroupName: lastEnhancementPromptContext?.matchedAppGroupName,
            matchedURLGroupName: lastEnhancementPromptContext?.matchedURLGroupName,
            remoteASRProvider: metadata.remoteASRProvider,
            remoteASRModel: metadata.remoteASRModel,
            remoteASREndpoint: metadata.remoteASREndpoint,
            remoteLLMProvider: metadata.remoteLLMProvider,
            remoteLLMModel: metadata.remoteLLMModel,
            remoteLLMEndpoint: metadata.remoteLLMEndpoint,
            assistantSummary: nil,
            assistantActions: nil,
            assistantStructuredSteps: nil,
            assistantSnapshotPath: nil
        )

        lastEnhancementPromptContext = nil
        transcriptionResultReceivedAt = nil
    }

    func appendAssistantHistoryIfNeeded(
        text: String,
        llmDurationSeconds: TimeInterval?,
        summary: String,
        snapshotPath: String? = nil
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard defaults.bool(forKey: AppPreferenceKey.historyEnabled) else { return }

        let metadata = currentHistoryMetadata()

        let audioDuration = resolvedDuration(from: recordingStartedAt, to: recordingStoppedAt)
        let processingDuration = resolvedDuration(from: transcriptionProcessingStartedAt, to: transcriptionResultReceivedAt)

        let trimmedSnapshotPath: String? = {
            let trimmedValue = snapshotPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmedValue.isEmpty ? nil : trimmedValue
        }()

        historyStore.append(
            text: trimmed,
            transcriptionEngine: transcriptionEngine.title,
            transcriptionModel: metadata.transcriptionModel,
            enhancementMode: enhancementMode.title,
            enhancementModel: metadata.enhancementModel,
            kind: .assistant,
            isTranslation: false,
            audioDurationSeconds: audioDuration,
            transcriptionProcessingDurationSeconds: processingDuration,
            llmDurationSeconds: llmDurationSeconds,
            focusedAppName: metadata.focusedAppName,
            matchedAppGroupName: lastEnhancementPromptContext?.matchedAppGroupName,
            matchedURLGroupName: lastEnhancementPromptContext?.matchedURLGroupName,
            remoteASRProvider: metadata.remoteASRProvider,
            remoteASRModel: metadata.remoteASRModel,
            remoteASREndpoint: metadata.remoteASREndpoint,
            remoteLLMProvider: metadata.remoteLLMProvider,
            remoteLLMModel: metadata.remoteLLMModel,
            remoteLLMEndpoint: metadata.remoteLLMEndpoint,
            assistantSummary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            assistantActions: assistantActionHistory.isEmpty ? nil : assistantActionHistory,
            assistantStructuredSteps: assistantStructuredHistory.isEmpty ? nil : assistantStructuredHistory,
            assistantSnapshotPath: trimmedSnapshotPath
        )

        lastEnhancementPromptContext = nil
        transcriptionResultReceivedAt = nil
    }

    func historyDisplayEndpoint(_ endpoint: String?) -> String? {
        let trimmed = endpoint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return AppLocalization.localizedString("Default") }
        guard var components = URLComponents(string: trimmed) else { return trimmed }
        components.queryItems = components.queryItems?.map { item in
            let lower = item.name.lowercased()
            if lower == "key" || lower == "api_key" || lower.contains("token") {
                return URLQueryItem(name: item.name, value: "<redacted>")
            }
            return item
        }
        return components.string ?? trimmed
    }

}
