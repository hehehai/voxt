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
        }

        let now = Date()
        let audioDuration = resolvedDuration(from: recordingStartedAt, to: recordingStoppedAt ?? now)
        let processingDuration = resolvedDuration(from: transcriptionProcessingStartedAt, to: now)
        let focusedAppName = lastEnhancementPromptContext?.focusedAppName ?? NSWorkspace.shared.frontmostApplication?.localizedName

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
            matchedURLGroupName: lastEnhancementPromptContext?.matchedURLGroupName
        )

        lastEnhancementPromptContext = nil
    }

    private func resolvedDuration(from start: Date?, to end: Date?) -> TimeInterval? {
        guard let start, let end else { return nil }
        let value = end.timeIntervalSince(start)
        guard value >= 0 else { return nil }
        return value
    }
}
