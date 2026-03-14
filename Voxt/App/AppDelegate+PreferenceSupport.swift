import Foundation

extension AppDelegate {
    func resolvedHistoryKind() -> TranscriptionHistoryKind {
        switch sessionOutputMode {
        case .transcription:
            return .normal
        case .translation:
            return .translation
        case .rewrite:
            return .rewrite
        case .assistant:
            return .assistant
        }
    }

    func resolvedDuration(from start: Date?, to end: Date?) -> TimeInterval? {
        guard let start, let end else { return nil }
        let value = end.timeIntervalSince(start)
        guard value >= 0 else { return nil }
        return value
    }

    func trimmedStringValue(forKey key: String) -> String {
        stringValue(forKey: key).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func stringValue(forKey key: String) -> String {
        defaults.string(forKey: key) ?? ""
    }

    func remoteConfigurations(forKey key: String) -> [String: RemoteProviderConfiguration] {
        RemoteModelConfigurationStore.loadConfigurations(from: stringValue(forKey: key))
    }

    func enumValue<T: RawRepresentable>(forKey key: String, default defaultValue: T) -> T where T.RawValue == String {
        T(rawValue: stringValue(forKey: key)) ?? defaultValue
    }

    func enumValue<T: RawRepresentable>(forKey key: String, default defaultValue: T?) -> T? where T.RawValue == String {
        T(rawValue: stringValue(forKey: key)) ?? defaultValue
    }
}
