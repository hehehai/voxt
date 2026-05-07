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
        hintPayload: ResolvedASRHintPayload
    ) -> [String: Any] {
        var transcriptionPayload: [String: Any] = [:]
        if let transcriptionModel = kind.transcriptionModel {
            transcriptionPayload["model"] = transcriptionModel
        }
        if let language = hintPayload.language?.trimmingCharacters(in: .whitespacesAndNewlines), !language.isEmpty {
            transcriptionPayload["language"] = language
        }
        return [
            "event_id": UUID().uuidString.lowercased(),
            "type": "session.update",
            "session": [
                "modalities": ["text"],
                "input_audio_format": "pcm",
                "sample_rate": 16000,
                "input_audio_transcription": transcriptionPayload,
                "turn_detection": [
                    "type": "server_vad",
                    "threshold": 0.0,
                    "silence_duration_ms": 400
                ]
            ]
        ]
    }
}

enum RemoteASRTextSupport {
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

    static func mergeStreamFragment(current: String, incoming: String) -> String {
        let fragment = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fragment.isEmpty else { return current }
        if current.isEmpty { return fragment }
        if fragment == current { return current }
        if fragment.hasPrefix(current) { return fragment }
        if current.hasPrefix(fragment) { return current }
        if fragment.contains(current) { return fragment }
        if current.contains(fragment) { return current }

        let maxOverlap = min(current.count, fragment.count)
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
        return normalized.hasPrefix("fun-asr") || normalized.hasPrefix("paraformer-realtime")
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

    private static func appendingPath(_ value: String, suffix: String) -> String {
        value.hasSuffix("/") ? value + suffix.dropFirst() : value + suffix
    }

    private static func replacingPathSuffix(in value: String, oldSuffix: String, newSuffix: String) -> String {
        guard value.lowercased().hasSuffix(oldSuffix) else { return value }
        return String(value.dropLast(oldSuffix.count)) + newSuffix
    }
}
