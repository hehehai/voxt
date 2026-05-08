import Foundation

enum RecordingSessionSupport {
    static func outputLabel(for outputMode: SessionOutputMode) -> String {
        switch outputMode {
        case .transcription:
            return "transcription"
        case .translation:
            return "translation"
        case .rewrite:
            return "rewrite"
        }
    }

    static func textModelRoutingDescription(
        outputMode: SessionOutputMode,
        transcriptionSettings: TranscriptionFeatureSettings,
        translationSettings: TranslationFeatureSettings,
        rewriteSettings: RewriteFeatureSettings
    ) -> String {
        switch outputMode {
        case .transcription:
            guard transcriptionSettings.llmEnabled else {
                return "transcription: none"
            }
            switch transcriptionSettings.llmSelectionID.textSelection {
            case .appleIntelligence:
                return "transcription: apple-intelligence"
            case .localLLM(let repo):
                return "transcription: local-llm(\(repo))"
            case .remoteLLM(let provider):
                return "transcription: remote-llm(\(provider.rawValue))"
            case .none:
                return "transcription: none"
            }
        case .translation:
            switch translationSettings.modelSelectionID.translationSelection {
            case .whisperDirectTranslate:
                return "translation: whisper-direct-translate"
            case .localLLM(let repo):
                return "translation: local-llm(\(repo))"
            case .remoteLLM(let provider):
                return "translation: remote-llm(\(provider.rawValue))"
            case .none:
                return "translation: none"
            }
        case .rewrite:
            switch rewriteSettings.llmSelectionID.textSelection {
            case .appleIntelligence:
                return "rewrite: apple-intelligence"
            case .localLLM(let repo):
                return "rewrite: local-llm(\(repo))"
            case .remoteLLM(let provider):
                return "rewrite: remote-llm(\(provider.rawValue))"
            case .none:
                return "rewrite: none"
            }
        }
    }

    static func overlayIconMode(for outputMode: SessionOutputMode) -> OverlaySessionIconMode {
        switch outputMode {
        case .transcription:
            return .transcription
        case .translation:
            return .translation
        case .rewrite:
            return .rewrite
        }
    }

    static func fallbackInjectBundleID(
        from bundleID: String?,
        ownBundleID: String?
    ) -> String? {
        guard let bundleID,
              let ownBundleID,
              bundleID != ownBundleID
        else {
            return nil
        }
        return bundleID
    }

    static func normalizedTranscriptionDisplayText(
        _ rawText: String,
        transcriptionEngine: TranscriptionEngine,
        remoteProvider: RemoteASRProvider,
        userMainLanguage: UserMainLanguageOption
    ) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let extractedText: String
        if transcriptionEngine == .remote, remoteProvider == .openAIWhisper {
            guard (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
                  (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) else {
                extractedText = trimmed
                return ChineseScriptNormalizer.normalize(extractedText, preferredMainLanguage: userMainLanguage)
            }

            guard let data = trimmed.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let extracted = extractTranscriptionTextValue(from: object),
                  !extracted.isEmpty else {
                extractedText = trimmed
                return ChineseScriptNormalizer.normalize(extractedText, preferredMainLanguage: userMainLanguage)
            }
            extractedText = extracted
        } else {
            extractedText = trimmed
        }

        return ChineseScriptNormalizer.normalize(extractedText, preferredMainLanguage: userMainLanguage)
    }

    static func stopRecordingFallbackTimeoutSeconds(
        transcriptionEngine: TranscriptionEngine,
        remoteProvider: RemoteASRProvider
    ) -> TimeInterval {
        switch transcriptionEngine {
        case .whisperKit:
            return 20
        case .mlxAudio:
            return 20
        case .dictation:
            return 8
        case .remote:
            break
        }
        switch remoteProvider {
        case .openAIWhisper, .glmASR:
            return 60
        case .doubaoASR, .aliyunBailianASR:
            return 8
        }
    }

    static func extractTranscriptionTextValue(from object: Any) -> String? {
        if let text = object as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let dict = object as? [String: Any] {
            let preferredKeys = ["text", "transcript", "result_text", "utterance", "content", "data"]
            for key in preferredKeys {
                if let value = dict[key],
                   let extracted = extractTranscriptionTextValue(from: value),
                   !extracted.isEmpty {
                    return extracted
                }
            }

            for value in dict.values {
                if let extracted = extractTranscriptionTextValue(from: value),
                   !extracted.isEmpty {
                    return extracted
                }
            }
            return nil
        }

        if let array = object as? [Any] {
            for item in array {
                if let extracted = extractTranscriptionTextValue(from: item),
                   !extracted.isEmpty {
                    return extracted
                }
            }
        }

        return nil
    }
}
