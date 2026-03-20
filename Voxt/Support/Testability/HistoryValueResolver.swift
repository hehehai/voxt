import Foundation

enum HistoryValueResolver {
    nonisolated static func resolvedKind(for sessionOutputMode: AppDelegate.SessionOutputMode) -> TranscriptionHistoryKind {
        switch sessionOutputMode {
        case .transcription:
            return .normal
        case .translation:
            return .translation
        case .rewrite:
            return .rewrite
        }
    }

    nonisolated static func resolvedDuration(from start: Date?, to end: Date?) -> TimeInterval? {
        guard let start, let end else { return nil }
        let value = end.timeIntervalSince(start)
        return value >= 0 ? value : nil
    }

    nonisolated static func historyDisplayEndpoint(_ endpoint: String?) -> String? {
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
