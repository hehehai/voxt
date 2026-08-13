// RemoteASRSupport.swift
// Provides Remote ASRSupport for remote ASR adapters.

import Foundation

enum AliyunQwenRealtimeSessionKind: Equatable {
    case qwenASR
    case omniASR

    var transcriptionModel: String? {
        switch self {
        case .qwenASR:
            return nil
        case .omniASR:
            return "qwen3-asr-flash-realtime"
        }
    }

    var shouldCommitBeforeFinish: Bool {
        switch self {
        case .qwenASR:
            return false
        case .omniASR:
            return false
        }
    }
}

enum AliyunQwenRealtimePayloadSupport {
    static func sessionUpdatePayload(
        kind: AliyunQwenRealtimeSessionKind,
        hintPayload: ResolvedASRHintPayload,
        includesTurnDetection: Bool = true,
        settings: AliyunASRModelSettings = AliyunASRModelSettings()
    ) -> [String: Any] {
        var transcriptionPayload: [String: Any] = [:]
        if let transcriptionModel = kind.transcriptionModel {
            transcriptionPayload["model"] = transcriptionModel
        }
        if let language = hintPayload.language?.trimmingCharacters(in: .whitespacesAndNewlines), !language.isEmpty {
            transcriptionPayload["language"] = language
        }
        var session: [String: Any] = [
            "modalities": ["text"],
            "input_audio_format": "pcm",
            "sample_rate": 16000,
            "input_audio_transcription": transcriptionPayload
        ]
        if includesTurnDetection && !(kind == .qwenASR && settings.useManualCommit) {
            session["turn_detection"] = [
                "type": "server_vad",
                "threshold": min(max(settings.serverVADThreshold, -1), 1),
                "silence_duration_ms": min(max(settings.serverVADSilenceDurationMilliseconds, 200), 6000)
            ]
        }
        return [
            "event_id": UUID().uuidString.lowercased(),
            "type": "session.update",
            "session": session
        ]
    }
}

enum AliyunFunRealtimePayloadSupport {
    static func supportsContext(model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("qwen-audio-3.0-asr-flash-streaming")
            || normalized == "fun-asr-realtime"
            || normalized == "fun-asr-realtime-2025-11-07"
    }

    static func context(model: String, phrases: [String]) -> [[String: Any]] {
        guard supportsContext(model: model) else { return [] }
        let text = phrases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let truncated = String(text.prefix(400))
        guard !truncated.isEmpty else { return [] }
        return [[
            "role": "user",
            "content": [[
                "type": "input_text",
                "text": truncated
            ]]
        ]]
    }

    static func parameters(
        model: String,
        hintPayload: ResolvedASRHintPayload,
        settings: AliyunASRModelSettings = AliyunASRModelSettings(),
        includeHotwords: Bool = true
    ) -> [String: Any] {
        let capabilities = AliyunASRModelCapabilities.forModel(model)
        var parameters: [String: Any] = [
            "sample_rate": 16000,
            "format": "pcm"
        ]
        if capabilities.supportsLanguageHints, !hintPayload.languageHints.isEmpty {
            let languageHints = Array(hintPayload.languageHints.prefix(capabilities.maximumLanguageHints))
            if !languageHints.isEmpty {
                parameters["language_hints"] = languageHints
            }
        }
        if includeHotwords,
           capabilities.supportsInlineVocabulary,
           !hintPayload.contextualPhrases.isEmpty {
            var vocabulary: [String: Int] = [:]
            for phrase in hintPayload.contextualPhrases {
                let term = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !term.isEmpty else { continue }
                vocabulary[term] = 4
            }
            if !vocabulary.isEmpty {
                parameters["vocabulary"] = vocabulary
            }
        }
        if capabilities.supportsMaxSentenceSilence {
            parameters["max_sentence_silence"] = min(max(settings.maxSentenceSilenceMilliseconds, 200), 6000)
        }
        if capabilities.supportsServerVAD {
            parameters["speech_noise_threshold"] = min(max(settings.serverVADThreshold, -1), 1)
        }
        if capabilities.supportsSemanticPunctuation {
            parameters["semantic_punctuation_enabled"] = settings.semanticPunctuationEnabled
        }
        if capabilities.supportsPunctuationPrediction {
            parameters["punctuation_prediction_enabled"] = settings.punctuationPredictionEnabled
        }
        if capabilities.supportsInverseTextNormalization {
            parameters["inverse_text_normalization_enabled"] = settings.inverseTextNormalizationEnabled
        }
        if capabilities.supportsDisfluencyRemoval {
            parameters["disfluency_removal_enabled"] = settings.disfluencyRemovalEnabled
        }
        return parameters
    }
}

enum RemoteASRTextSupport {
    static func xiaomiMiMoASRPayload(
        model: String,
        audioData: Data,
        mimeType: String,
        hintPayload: ResolvedASRHintPayload
    ) -> [String: Any] {
        let effectiveModel = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? RemoteASRProvider.xiaomiMiMoASR.suggestedModel
            : model
        let language = xiaomiMiMoLanguage(from: hintPayload.language)
        let audioDataURI = "data:\(mimeType);base64,\(audioData.base64EncodedString())"

        return [
            "model": effectiveModel,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_audio",
                            "input_audio": [
                                "data": audioDataURI
                            ]
                        ]
                    ]
                ]
            ],
            "asr_options": [
                "language": language
            ]
        ]
    }

    static func xiaomiMiMoLanguage(from language: String?) -> String {
        let normalized = language?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        switch normalized {
        case "zh", "en":
            return normalized
        default:
            return "auto"
        }
    }

    static func openAITranscriptionMultipartFields(
        model: String,
        hintPayload: ResolvedASRHintPayload
    ) -> [String: String] {
        let effectiveModel = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? RemoteASRProvider.openAIWhisper.suggestedModel
            : model
        var fields: [String: String] = [
            "response_format": "json"
        ]
        if let language = hintPayload.language?.trimmingCharacters(in: .whitespacesAndNewlines), !language.isEmpty {
            fields["language"] = language
        }
        if effectiveModel != "gpt-4o-transcribe-diarize",
           let prompt = hintPayload.prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty {
            fields["prompt"] = prompt
        }
        return fields
    }

    static func extractTextFragment(fromLine line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let data = line.data(using: .utf8) else {
            return trimmed
        }

        if let object = try? JSONSerialization.jsonObject(with: data) {
            if let value = extractText(in: object), !value.isEmpty {
                return normalizedTextFragment(value)
            }
            return nil
        }

        if let loose = extractLooseTextField(from: trimmed), !loose.isEmpty {
            return normalizedTextFragment(loose)
        }

        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) ||
            (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            return nil
        }

        return normalizedTextFragment(trimmed)
    }

    static func extractStreamErrorMessage(fromLine line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return extractStreamErrorMessage(in: object)
    }

    static func extractLooseTextField(from line: String) -> String? {
        let patterns = [
            #"(?:["']?text["']?\s*:\s*["'])([^"']+)(?:["'])"#,
            #"(?:["']?transcript["']?\s*:\s*["'])([^"']+)(?:["'])"#,
            #"(?:["']?result_text["']?\s*:\s*["'])([^"']+)(?:["'])"#,
            #"(?:["']?text["']?\s*:\s*)([^,}\]]+)"#,
            #"(?:["']?transcript["']?\s*:\s*)([^,}\]]+)"#,
            #"(?:["']?result_text["']?\s*:\s*)([^,}\]]+)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, options: [], range: range),
                  match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: line) else {
                continue
            }
            var value = String(line[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
                (value.hasPrefix("'") && value.hasSuffix("'")) {
                value.removeFirst()
                value.removeLast()
                value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if !value.isEmpty {
                return value
            }
        }
        return nil
    }

    static func normalizedTextFragment(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if isLikelyJSONObjectString(trimmed) {
            if let data = trimmed.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data),
               let nested = extractText(in: object),
               !nested.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !isLikelyJSONObjectString(nested) {
                return nested.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let loose = extractLooseTextField(from: trimmed),
               !isLikelyJSONObjectString(loose) {
                return loose.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return nil
        }

        return trimmed
    }

    static func isLikelyJSONObjectString(_ value: String) -> Bool {
        (value.hasPrefix("{") && value.hasSuffix("}")) ||
        (value.hasPrefix("[") && value.hasSuffix("]"))
    }

    static func extractDoubaoText(in object: Any) -> String? {
        if let dict = object as? [String: Any],
           let result = dict["result"] as? [String: Any],
           let text = result["text"] as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !RemoteASRTextSanitizer.isLikelyIdentifierText(trimmed) {
                return trimmed
            }
        }

        var candidates: [String] = []

        func appendCandidate(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !RemoteASRTextSanitizer.isLikelyIdentifierText(trimmed) else { return }
            candidates.append(trimmed)
        }

        func walk(_ node: Any) {
            if let dict = node as? [String: Any] {
                let directTextKeys = ["text", "transcript", "utterance", "utterance_text", "result_text"]
                for key in directTextKeys {
                    if let value = dict[key] as? String {
                        appendCandidate(value)
                    }
                }

                let containerKeys = ["result", "results", "utterances", "payload_msg", "payload", "data", "nbest", "alternatives"]
                for key in containerKeys {
                    if let value = dict[key] {
                        walk(value)
                    }
                }

                for (_, value) in dict {
                    if value is [String: Any] || value is [Any] {
                        walk(value)
                    }
                }
                return
            }

            if let array = node as? [Any] {
                for item in array {
                    walk(item)
                }
            }
        }

        walk(object)
        return candidates.max(by: { $0.count < $1.count })
    }

    static func extractText(in object: Any) -> String? {
        if let text = object as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            if isLikelyJSONObjectString(trimmed) {
                if let data = trimmed.data(using: .utf8),
                   let nestedObject = try? JSONSerialization.jsonObject(with: data),
                   let nestedText = extractText(in: nestedObject),
                   !nestedText.isEmpty {
                    return nestedText
                }
                if let loose = extractLooseTextField(from: trimmed), !loose.isEmpty {
                    return loose
                }
                return nil
            }
            return trimmed
        }
        if let dict = object as? [String: Any] {
            let preferredKeys = ["delta", "text", "transcript", "result_text", "content", "utterance", "data"]
            for key in preferredKeys {
                if let value = dict[key], let text = extractText(in: value), !text.isEmpty {
                    return text
                }
            }
            for value in dict.values {
                if (value is [String: Any] || value is [Any]),
                   let text = extractText(in: value),
                   !text.isEmpty {
                    return text
                }
            }
        }
        if let array = object as? [Any] {
            for item in array {
                if let text = extractText(in: item), !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }

    private static func extractStreamErrorMessage(in object: Any) -> String? {
        if let dict = object as? [String: Any] {
            if let value = dict["error"],
               let message = extractStreamErrorDescription(from: value) {
                return message
            }

            let markerKeys = ["event", "type", "status"]
            let isErrorPayload = markerKeys.contains { key in
                guard let value = dict[key] as? String else { return false }
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return ["error", "failed", "failure"].contains(normalized)
            }
            if isErrorPayload {
                let messageKeys = ["message", "msg", "error_message", "detail", "code"]
                for key in messageKeys {
                    if let value = dict[key],
                       let message = extractStreamErrorDescription(from: value) {
                        return message
                    }
                }
                return "StepFun ASR stream returned an error event."
            }
        }

        return nil
    }

    private static func extractStreamErrorDescription(from object: Any) -> String? {
        if let text = object as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let number = object as? NSNumber {
            return number.stringValue
        }

        if let dict = object as? [String: Any] {
            let preferredKeys = ["message", "msg", "error_message", "detail", "code"]
            for key in preferredKeys {
                if let value = dict[key],
                   let message = extractStreamErrorDescription(from: value) {
                    return message
                }
            }
        }

        if let array = object as? [Any] {
            for item in array {
                if let message = extractStreamErrorDescription(from: item) {
                    return message
                }
            }
        }

        return nil
    }

    static func mergeStreamFragment(current: String, incoming: String) -> String {
        let fragment = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fragment.isEmpty else { return current }
        if current.isEmpty { return fragment }
        if fragment == current { return current }
        if fragment.hasPrefix(current) { return fragment }
        if current.hasPrefix(fragment) { return current }
        if fragment.contains(current) { return fragment }
        if current.contains(fragment) { return current }

        // Streaming deltas overlap only at their boundary. Bounding the scan avoids
        // quadratic work as a long transcript grows while preserving ample context.
        let maxOverlap = min(min(current.count, fragment.count), 512)
        if maxOverlap > 0 {
            for length in stride(from: maxOverlap, through: 1, by: -1) {
                let currentSuffix = String(current.suffix(length))
                let incomingPrefix = String(fragment.prefix(length))
                if currentSuffix == incomingPrefix {
                    return current + fragment.dropFirst(length)
                }
            }
        }
        return current + fragment
    }

    static func collectText(from bytes: URLSession.AsyncBytes) async throws -> String {
        var chunks: [String] = []
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                chunks.append(trimmed)
            }
            if chunks.count >= 6 { break }
        }
        return chunks.joined(separator: " | ")
    }
}

enum StepFunSSEDataPayload: Equatable {
    case delta(String)
    case completed(String)
    case error(String)
    case fragment(String)
    case ignore
}

enum StepFunPayloadSupport {
    static func supportsSSEPrompt(model: String) -> Bool {
        let capabilities = StepFunASRModelCapabilities.forModel(model)
        return capabilities.supportsPrompt && !capabilities.usesRealtimeWebSocket
    }

    static func transcriptionPayload(
        model: String,
        hintPayload: ResolvedASRHintPayload,
        includeTimestamp: Bool = false,
        includePrompt: Bool = false,
        includeHotwords: Bool = true,
        fullRerunOnCommit: Bool? = nil
    ) -> [String: Any] {
        let capabilities = StepFunASRModelCapabilities.forModel(model)
        var payload: [String: Any] = [
            "model": model,
            "language": hintPayload.language ?? "zh",
            "enable_itn": true
        ]
        if includeTimestamp {
            payload["enable_timestamp"] = true
        }
        if includeHotwords,
           capabilities.supportsHotwords,
           !hintPayload.contextualPhrases.isEmpty {
            payload["hotwords"] = hintPayload.contextualPhrases
        }
        if includePrompt,
           capabilities.supportsPrompt,
           let prompt = hintPayload.prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty {
            payload["prompt"] = prompt
        }
        if let fullRerunOnCommit {
            payload["full_rerun_on_commit"] = fullRerunOnCommit
        }
        return payload
    }

    static func audioFormatPayload() -> [String: Any] {
        [
            "type": "pcm",
            "codec": "pcm_s16le",
            "rate": 16000,
            "bits": 16,
            "channel": 1
        ]
    }

    static func sessionUpdatePayload(
        model: String,
        hintPayload: ResolvedASRHintPayload,
        useServerVAD: Bool
    ) -> [String: Any] {
        var input: [String: Any] = [
            "format": audioFormatPayload(),
            "transcription": transcriptionPayload(
                model: model,
                hintPayload: hintPayload,
                includePrompt: true,
                includeHotwords: false,
                fullRerunOnCommit: true
            )
        ]
        if useServerVAD {
            input["turn_detection"] = [
                "type": "server_vad",
                "silence_duration_ms": 800,
                "threshold": 0.5
            ]
        }
        return [
            "event_id": UUID().uuidString.lowercased(),
            "type": "session.update",
            "session": [
                "audio": [
                    "input": input
                ]
            ]
        ]
    }

    static func parseSSEDataLine(_ line: String) -> StepFunSSEDataPayload {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .ignore }

        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return .fragment(trimmed)
        }

        guard let dict = object as? [String: Any] else {
            if let text = RemoteASRTextSupport.extractText(in: object),
               let normalized = RemoteASRTextSupport.normalizedTextFragment(text) {
                return .fragment(normalized)
            }
            return .ignore
        }

        let type = (dict["type"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        switch type {
        case "transcript.text.delta":
            guard let value = dict["delta"],
                  let text = RemoteASRTextSupport.extractText(in: value),
                  let normalized = RemoteASRTextSupport.normalizedTextFragment(text) else {
                return .ignore
            }
            return .delta(normalized)
        case "transcript.text.done":
            guard let value = dict["text"],
                  let text = RemoteASRTextSupport.extractText(in: value),
                  let normalized = RemoteASRTextSupport.normalizedTextFragment(text) else {
                return .ignore
            }
            return .completed(normalized)
        default:
            if type == "error" || type.hasSuffix(".error") {
                return .error(RemoteASRTextSupport.extractStreamErrorMessage(fromLine: trimmed) ?? trimmed)
            }
        }

        if let text = RemoteASRTextSupport.extractTextFragment(fromLine: trimmed) {
            return .fragment(text)
        }
        return .ignore
    }
}

enum RemoteASREndpointSupport {
    static func audioMIMEType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "mp3":
            return "audio/mpeg"
        case "m4a":
            return "audio/mp4"
        case "ogg":
            return "audio/ogg"
        default:
            return "audio/wav"
        }
    }

    static func resolvedAliyunFunRealtimeEndpoint(_ endpoint: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "wss://dashscope.aliyuncs.com/api-ws/v1/inference"
        }
        if var components = URLComponents(string: trimmed) {
            let normalizedPath = components.path.lowercased()
            if normalizedPath.hasSuffix("/api-ws/v1/inference") {
                return trimmed
            }
            if normalizedPath.hasSuffix("/api-ws/v1/realtime") {
                components.path = components.path.replacingOccurrences(of: "/api-ws/v1/realtime", with: "/api-ws/v1/inference")
                components.queryItems = nil
                return components.string ?? trimmed
            }
            if normalizedPath.hasSuffix("/models") {
                return replacingPathSuffix(in: trimmed, oldSuffix: "/models", newSuffix: "/api-ws/v1/inference")
            }
            if normalizedPath.hasSuffix("/chat/completions") {
                return replacingPathSuffix(in: trimmed, oldSuffix: "/chat/completions", newSuffix: "/api-ws/v1/inference")
            }
            if normalizedPath.hasSuffix("/v1") {
                return appendingPath(trimmed, suffix: "/inference")
            }
        }
        return trimmed
    }

    static func isAliyunFunRealtimeModel(_ model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("qwen-audio-3.0-asr-flash-streaming")
            || normalized.hasPrefix("fun-asr")
            || normalized.hasPrefix("paraformer-realtime")
    }

    static func isAliyunQwenRealtimeModel(_ model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("qwen3-asr-flash-realtime")
    }

    static func isAliyunOmniRealtimeModel(_ model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("qwen3.5-omni-flash-realtime")
            || normalized.hasPrefix("qwen3.5-omni-plus-realtime")
            || normalized.hasPrefix("qwen-omni-turbo-realtime")
    }

    static func aliyunQwenRealtimeSessionKind(for model: String) -> AliyunQwenRealtimeSessionKind? {
        if isAliyunQwenRealtimeModel(model) {
            return .qwenASR
        }
        if isAliyunOmniRealtimeModel(model) {
            return .omniASR
        }
        return nil
    }

    static func isAliyunFileTranscriptionModel(_ model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("qwen3-asr-flash-filetrans")
            || normalized == "fun-asr"
            || normalized == "paraformer-v2"
    }

    static func resolvedAliyunQwenRealtimeEndpoint(_ endpoint: String, model: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? model

        guard !trimmed.isEmpty else {
            return "wss://dashscope.aliyuncs.com/api-ws/v1/realtime?model=\(encodedModel)"
        }
        guard var components = URLComponents(string: trimmed) else {
            return trimmed
        }
        let normalizedPath = components.path.lowercased()
        if normalizedPath.hasSuffix("/api-ws/v1/realtime") {
            var items = components.queryItems ?? []
            if !items.contains(where: { $0.name == "model" }) {
                items.append(URLQueryItem(name: "model", value: model))
                components.queryItems = items
            }
            return components.string ?? trimmed
        }
        if normalizedPath.hasSuffix("/api-ws/v1/inference") {
            components.path = components.path.replacingOccurrences(of: "/api-ws/v1/inference", with: "/api-ws/v1/realtime")
            var items = components.queryItems ?? []
            if !items.contains(where: { $0.name == "model" }) {
                items.append(URLQueryItem(name: "model", value: model))
            }
            components.queryItems = items
            return components.string ?? trimmed
        }
        if normalizedPath.hasSuffix("/chat/completions") {
            let base = replacingPathSuffix(in: trimmed, oldSuffix: "/chat/completions", newSuffix: "/api-ws/v1/realtime")
            return base.contains("?") ? base : "\(base)?model=\(encodedModel)"
        }
        return trimmed
    }

    static func resolvedStepFunSSEEndpoint(_ endpoint: String) -> String {
        normalizedEndpoint(endpoint, defaultValue: "https://api.stepfun.com/v1/audio/asr/sse")
    }

    static func resolvedStepFunRealtimeEndpoint(_ endpoint: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "wss://api.stepfun.com/v1/realtime/asr/stream"
        }
        guard var components = URLComponents(string: trimmed) else {
            return trimmed
        }
        let normalizedPath = components.path.lowercased()
        if normalizedPath.hasSuffix("/v1/realtime/asr/stream") {
            components.scheme = "wss"
            return components.string ?? trimmed
        }
        if normalizedPath.hasSuffix("/v1/audio/asr/sse") ||
            normalizedPath.hasSuffix("/step_plan/v1/audio/asr/sse") {
            components.scheme = "wss"
            components.path = "/v1/realtime/asr/stream"
            components.queryItems = nil
            return components.string ?? trimmed
        }
        if normalizedPath.hasSuffix("/v1") {
            components.scheme = "wss"
            components.path = appendingPath(components.path, suffix: "/realtime/asr/stream")
            components.queryItems = nil
            return components.string ?? trimmed
        }
        return trimmed
    }

    static func normalizedEndpoint(_ value: String, defaultValue: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultValue : trimmed
    }

    static func resolvedDoubaoResourceID(from configuration: RemoteProviderConfiguration) -> String {
        DoubaoASRConfiguration.resolvedResourceID(configuration.model)
    }

    static func resolvedDoubaoEndpoint(from configuration: RemoteProviderConfiguration) -> String {
        DoubaoASRConfiguration.resolvedEndpoint(configuration.endpoint, model: configuration.model)
    }

    static func resolvedDoubaoStreamingEndpoint(from configuration: RemoteProviderConfiguration) -> String {
        DoubaoASRConfiguration.resolvedStreamingEndpoint(configuration.endpoint, model: configuration.model)
    }

    static func resolvedXiaomiMiMoASREndpoint(_ endpoint: String) -> String {
        normalizedChatCompletionsEndpoint(
            endpoint,
            defaultValue: "https://api.xiaomimimo.com/v1/chat/completions"
        )
    }

    private static func appendingPath(_ value: String, suffix: String) -> String {
        value.hasSuffix("/") ? value + suffix.dropFirst() : value + suffix
    }

    private static func normalizedChatCompletionsEndpoint(_ value: String, defaultValue: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultValue }
        guard let url = URL(string: trimmed) else { return trimmed }
        let normalizedPath = url.path.lowercased()
        if normalizedPath.hasSuffix("/chat/completions") {
            return trimmed
        }
        if normalizedPath.hasSuffix("/models") {
            return replacingPathSuffix(in: trimmed, oldSuffix: "/models", newSuffix: "/chat/completions")
        }
        if normalizedPath.hasSuffix("/v1") {
            return appendingPath(trimmed, suffix: "/chat/completions")
        }
        if normalizedPath.isEmpty || normalizedPath == "/" {
            return appendingPath(trimmed, suffix: "/v1/chat/completions")
        }
        return trimmed
    }

    private static func replacingPathSuffix(in value: String, oldSuffix: String, newSuffix: String) -> String {
        guard value.lowercased().hasSuffix(oldSuffix) else { return value }
        return String(value.dropLast(oldSuffix.count)) + newSuffix
    }
}

enum StepFunSupport {
    /// Extracts raw PCM data from a WAV file by walking RIFF chunks and
    /// returning the contents of the "data" chunk.
    static func extractPCMData(fromWAV wavData: Data) throws -> Data {
        guard wavData.count > 44 else {
            throw NSError(
                domain: "Voxt.StepFun",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "WAV file too small for StepFun ASR."]
            )
        }

        var offset = 12
        while offset + 8 <= wavData.count {
            let chunkID = String(data: wavData.subdata(in: offset..<offset + 4), encoding: .ascii) ?? ""
            let chunkSize = wavData.withUnsafeBytes { ptr in
                ptr.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self)
            }
            let size = Int(chunkSize)
            if chunkID == "data" {
                let dataStart = offset + 8
                let dataEnd = min(dataStart + size, wavData.count)
                guard dataEnd > dataStart else {
                    throw NSError(
                        domain: "Voxt.StepFun",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "WAV data chunk is empty."]
                    )
                }
                return wavData.subdata(in: dataStart..<dataEnd)
            }
            offset += 8 + size
            if size % 2 != 0 { offset += 1 }
        }

        guard wavData.count > 44 else {
            throw NSError(
                domain: "Voxt.StepFun",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Cannot locate WAV data chunk."]
            )
        }
        return wavData.subdata(in: 44..<wavData.count)
    }
}
