import Foundation
import AppKit

private enum VoxtNoteTitleModel {
    case appleIntelligence
    case customLLM(repo: String)
    case remoteLLM(provider: RemoteLLMProvider, configuration: RemoteProviderConfiguration)
}

extension AppDelegate {
    func appendVoxtNote(text: String, sessionID: UUID) {
        let fallbackTitle = VoxtNoteTitleSupport.fallbackTitle(from: text)
        let resolvedTitleModel = resolvedVoxtNoteTitleModel()
        let initialState: NoteTitleGenerationState = resolvedTitleModel == nil ? .fallback : .pending

        guard let item = noteStore.append(
            sessionID: sessionID,
            text: text,
            title: fallbackTitle,
            titleGenerationState: initialState
        ) else {
            return
        }

        noteWindowManager.show()

        guard let resolvedTitleModel else { return }
        Task { @MainActor [weak self] in
            await self?.generateVoxtNoteTitle(
                for: item.id,
                text: item.text,
                fallbackTitle: fallbackTitle,
                model: resolvedTitleModel
            )
        }
    }

    private func generateVoxtNoteTitle(
        for noteID: UUID,
        text: String,
        fallbackTitle: String,
        model: VoxtNoteTitleModel
    ) async {
        do {
            let generatedTitle = try await runVoxtNoteTitlePrompt(
                voxtNoteTitlePrompt(for: text),
                model: model
            )
            let normalizedTitle = VoxtNoteTitleSupport.normalizedGeneratedTitle(generatedTitle)
            let resolvedTitle = normalizedTitle.isEmpty ? fallbackTitle : normalizedTitle
            let resolvedState: NoteTitleGenerationState = normalizedTitle.isEmpty ? .fallback : .generated
            _ = noteStore.updateTitle(resolvedTitle, state: resolvedState, for: noteID)
            VoxtLog.info(
                "Voxt note title generated. noteID=\(noteID.uuidString), state=\(resolvedState.rawValue), titleChars=\(resolvedTitle.count)"
            )
        } catch {
            _ = noteStore.updateTitle(fallbackTitle, state: .fallback, for: noteID)
            VoxtLog.warning("Voxt note title generation failed. noteID=\(noteID.uuidString), error=\(error.localizedDescription)")
        }
    }

    private func resolvedVoxtNoteTitleModel() -> VoxtNoteTitleModel? {
        switch noteFeatureSettings.titleModelSelectionID.textSelection {
        case .appleIntelligence:
            guard let enhancer else { return nil }
            if #available(macOS 26.0, *) {
                guard TextEnhancer.isAvailable else { return nil }
                _ = enhancer
                return .appleIntelligence
            }
            return nil
        case .localLLM(let repo):
            guard customLLMManager.isModelDownloaded(repo: repo) else { return nil }
            return .customLLM(repo: repo)
        case .remoteLLM(let provider):
            let configuration = RemoteModelConfigurationStore.resolvedLLMConfiguration(
                provider: provider,
                stored: remoteLLMConfigurations
            )
            guard configuration.isConfigured, configuration.hasUsableModel else { return nil }
            return .remoteLLM(provider: provider, configuration: configuration)
        case .none:
            return nil
        }
    }

    private func runVoxtNoteTitlePrompt(
        _ prompt: String,
        model: VoxtNoteTitleModel
    ) async throws -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return "" }

        switch model {
        case .appleIntelligence:
            guard let enhancer else {
                throw NSError(
                    domain: "Voxt.NoteTitle",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "Apple Intelligence is unavailable.")]
                )
            }
            if #available(macOS 26.0, *) {
                return try await enhancer.enhance(userPrompt: trimmedPrompt)
            }
            throw NSError(
                domain: "Voxt.NoteTitle",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Apple Intelligence requires macOS 26 or later.")]
            )
        case .customLLM(let repo):
            return try await customLLMManager.enhance(userPrompt: trimmedPrompt, repo: repo)
        case .remoteLLM(let provider, let configuration):
            return try await RemoteLLMRuntimeClient().enhance(
                userPrompt: trimmedPrompt,
                provider: provider,
                configuration: configuration
            )
        }
    }

    private func voxtNoteTitlePrompt(for text: String) -> String {
        """
        You are Voxt's note title generator.

        Generate a very short plain-text title for the note below.

        Rules:
        1. Reply in the user's main language.
        2. Return one line only.
        3. Keep it concise and specific.
        4. Avoid quotes, numbering, markdown, or extra explanation.
        5. Prefer 4-8 words, or under 20 Chinese characters.

        User main language: \(userMainLanguagePromptValue)

        Note text:
        \(text)
        """
    }
}
