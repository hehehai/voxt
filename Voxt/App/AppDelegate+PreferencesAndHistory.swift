import Foundation
import AppKit
import CoreAudio

extension AppDelegate {
    var selectedInputDeviceID: AudioDeviceID? {
        let raw = UserDefaults.standard.integer(forKey: AppPreferenceKey.selectedInputDeviceID)
        return raw > 0 ? AudioDeviceID(raw) : nil
    }

    var interactionSoundsEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppPreferenceKey.interactionSoundsEnabled)
    }

    var overlayPosition: OverlayPosition {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.overlayPosition)
        return OverlayPosition(rawValue: raw ?? "") ?? .bottom
    }

    var autoCopyWhenNoFocusedInput: Bool {
        UserDefaults.standard.bool(forKey: AppPreferenceKey.autoCopyWhenNoFocusedInput)
    }

    var translationTargetLanguage: TranslationTargetLanguage {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.translationTargetLanguage)
        return TranslationTargetLanguage(rawValue: raw ?? "") ?? .english
    }

    var translateSelectedTextOnTranslationHotkey: Bool {
        UserDefaults.standard.bool(forKey: AppPreferenceKey.translateSelectedTextOnTranslationHotkey)
    }

    var translationSystemPrompt: String {
        let value = UserDefaults.standard.string(forKey: AppPreferenceKey.translationSystemPrompt)
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        return AppPreferenceKey.defaultTranslationPrompt
    }

    var translationCustomLLMRepo: String {
        let value = UserDefaults.standard.string(forKey: AppPreferenceKey.translationCustomLLMModelRepo)
        if let value, !value.isEmpty {
            return value
        }
        return UserDefaults.standard.string(forKey: AppPreferenceKey.customLLMModelRepo)
            ?? CustomLLMModelManager.defaultModelRepo
    }

    var translationModelProvider: TranslationModelProvider {
        let value = UserDefaults.standard.string(forKey: AppPreferenceKey.translationModelProvider) ?? ""
        return TranslationModelProvider(rawValue: value) ?? .customLLM
    }

    var remoteASRSelectedProvider: RemoteASRProvider {
        let value = UserDefaults.standard.string(forKey: AppPreferenceKey.remoteASRSelectedProvider)
        return RemoteASRProvider(rawValue: value ?? "") ?? .openAIWhisper
    }

    var remoteLLMSelectedProvider: RemoteLLMProvider {
        let value = UserDefaults.standard.string(forKey: AppPreferenceKey.remoteLLMSelectedProvider)
        return RemoteLLMProvider(rawValue: value ?? "") ?? .openAI
    }

    var translationRemoteLLMProvider: RemoteLLMProvider? {
        let value = UserDefaults.standard.string(forKey: AppPreferenceKey.translationRemoteLLMProvider) ?? ""
        return RemoteLLMProvider(rawValue: value)
    }

    var remoteASRConfigurations: [String: RemoteProviderConfiguration] {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.remoteASRProviderConfigurations) ?? ""
        return RemoteModelConfigurationStore.loadConfigurations(from: raw)
    }

    var remoteLLMConfigurations: [String: RemoteProviderConfiguration] {
        let raw = UserDefaults.standard.string(forKey: AppPreferenceKey.remoteLLMProviderConfigurations) ?? ""
        return RemoteModelConfigurationStore.loadConfigurations(from: raw)
    }

    var showInDock: Bool {
        UserDefaults.standard.bool(forKey: AppPreferenceKey.showInDock)
    }

    var historyEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppPreferenceKey.historyEnabled)
    }

    var autoCheckForUpdates: Bool {
        UserDefaults.standard.bool(forKey: AppPreferenceKey.autoCheckForUpdates)
    }

    func appendHistoryIfNeeded(text: String, llmDurationSeconds: TimeInterval?) {
        guard historyEnabled else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let transcriptionModel: String
        switch transcriptionEngine {
        case .dictation:
            transcriptionModel = "Apple Speech Recognition"
        case .mlxAudio:
            let repo = mlxModelManager.currentModelRepo
            transcriptionModel = "\(mlxModelManager.displayTitle(for: repo)) (\(repo))"
        case .remote:
            let provider = remoteASRSelectedProvider
            if let config = remoteASRConfigurations[provider.rawValue], config.hasUsableModel {
                transcriptionModel = "\(provider.title) (\(config.model))"
            } else {
                transcriptionModel = provider.title
            }
        }

        let enhancementModel: String
        switch enhancementMode {
        case .off:
            enhancementModel = "None"
        case .appleIntelligence:
            enhancementModel = "Apple Intelligence (Foundation Models)"
        case .customLLM:
            let repo = customLLMManager.currentModelRepo
            enhancementModel = "\(customLLMManager.displayTitle(for: repo)) (\(repo))"
        case .remoteLLM:
            let provider = remoteLLMSelectedProvider
            if let config = remoteLLMConfigurations[provider.rawValue], config.hasUsableModel {
                enhancementModel = "\(provider.title) (\(config.model))"
            } else {
                enhancementModel = provider.title
            }
        }

        let now = Date()
        let audioDuration = resolvedDuration(from: recordingStartedAt, to: recordingStoppedAt ?? now)
        // ASR processing duration should exclude LLM enhancement time.
        // Measure from recording stop to first ASR text callback when available.
        let processingEnd = transcriptionResultReceivedAt ?? now
        let processingDuration = resolvedDuration(from: transcriptionProcessingStartedAt, to: processingEnd)
        let focusedAppName = lastEnhancementPromptContext?.focusedAppName ?? NSWorkspace.shared.frontmostApplication?.localizedName

        let remoteASRProviderInfo: String?
        let remoteASRModelInfo: String?
        let remoteASREndpointInfo: String?
        if transcriptionEngine == .remote {
            let provider = remoteASRSelectedProvider
            let config = remoteASRConfigurations[provider.rawValue]
            remoteASRProviderInfo = provider.title
            remoteASRModelInfo = config?.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? config?.model : nil
            remoteASREndpointInfo = historyDisplayEndpoint(config?.endpoint)
        } else {
            remoteASRProviderInfo = nil
            remoteASRModelInfo = nil
            remoteASREndpointInfo = nil
        }

        let remoteLLMProviderInfo: String?
        let remoteLLMModelInfo: String?
        let remoteLLMEndpointInfo: String?
        if enhancementMode == .remoteLLM {
            let provider = remoteLLMSelectedProvider
            let config = remoteLLMConfigurations[provider.rawValue]
            remoteLLMProviderInfo = provider.title
            remoteLLMModelInfo = config?.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? config?.model : nil
            remoteLLMEndpointInfo = historyDisplayEndpoint(config?.endpoint)
        } else {
            remoteLLMProviderInfo = nil
            remoteLLMModelInfo = nil
            remoteLLMEndpointInfo = nil
        }

        historyStore.append(
            text: trimmed,
            transcriptionEngine: transcriptionEngine.title,
            transcriptionModel: transcriptionModel,
            enhancementMode: enhancementMode.title,
            enhancementModel: enhancementModel,
            isTranslation: sessionOutputMode == .translation,
            audioDurationSeconds: audioDuration,
            transcriptionProcessingDurationSeconds: processingDuration,
            llmDurationSeconds: llmDurationSeconds,
            focusedAppName: focusedAppName,
            matchedAppGroupName: lastEnhancementPromptContext?.matchedAppGroupName,
            matchedURLGroupName: lastEnhancementPromptContext?.matchedURLGroupName,
            remoteASRProvider: remoteASRProviderInfo,
            remoteASRModel: remoteASRModelInfo,
            remoteASREndpoint: remoteASREndpointInfo,
            remoteLLMProvider: remoteLLMProviderInfo,
            remoteLLMModel: remoteLLMModelInfo,
            remoteLLMEndpoint: remoteLLMEndpointInfo
        )

        lastEnhancementPromptContext = nil
        transcriptionResultReceivedAt = nil
    }

    private func resolvedDuration(from start: Date?, to end: Date?) -> TimeInterval? {
        guard let start, let end else { return nil }
        let value = end.timeIntervalSince(start)
        guard value >= 0 else { return nil }
        return value
    }

    private func historyDisplayEndpoint(_ endpoint: String?) -> String? {
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
