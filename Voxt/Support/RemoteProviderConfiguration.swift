import Foundation

struct RemoteProviderConfiguration: Codable, Identifiable, Hashable {
    let providerID: String
    var model: String
    var meetingModel: String
    var endpoint: String
    var apiKey: String
    var appID: String
    var accessToken: String
    var searchEnabled: Bool
    var openAIChunkPseudoRealtimeEnabled: Bool
    var doubaoDictionaryMode: String
    var doubaoEnableRequestHotwords: Bool
    var doubaoEnableRequestCorrections: Bool

    var id: String { providerID }

    var hasUsableModel: Bool {
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasUsableMeetingModel: Bool {
        !meetingModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isConfigured: Bool {
        hasUsableModel && (
            !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    var doubaoDictionaryModeValue: DoubaoDictionaryMode {
        DoubaoDictionaryMode(rawValue: doubaoDictionaryMode) ?? .requestScoped
    }

    init(
        providerID: String,
        model: String,
        meetingModel: String = "",
        endpoint: String,
        apiKey: String,
        appID: String = "",
        accessToken: String = "",
        searchEnabled: Bool = false,
        openAIChunkPseudoRealtimeEnabled: Bool = false,
        doubaoDictionaryMode: String = DoubaoDictionaryMode.requestScoped.rawValue,
        doubaoEnableRequestHotwords: Bool = true,
        doubaoEnableRequestCorrections: Bool = true
    ) {
        self.providerID = providerID
        self.model = model
        self.meetingModel = meetingModel
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.appID = appID
        self.accessToken = accessToken
        self.searchEnabled = searchEnabled
        self.openAIChunkPseudoRealtimeEnabled = openAIChunkPseudoRealtimeEnabled
        self.doubaoDictionaryMode = doubaoDictionaryMode
        self.doubaoEnableRequestHotwords = doubaoEnableRequestHotwords
        self.doubaoEnableRequestCorrections = doubaoEnableRequestCorrections
    }

    enum CodingKeys: String, CodingKey {
        case providerID
        case model
        case meetingModel
        case endpoint
        case apiKey
        case appID
        case accessToken
        case searchEnabled
        case openAIChunkPseudoRealtimeEnabled
        case doubaoDictionaryMode
        case doubaoEnableRequestHotwords
        case doubaoEnableRequestCorrections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerID = try container.decode(String.self, forKey: .providerID)
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        meetingModel = try container.decodeIfPresent(String.self, forKey: .meetingModel) ?? ""
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        appID = try container.decodeIfPresent(String.self, forKey: .appID) ?? ""
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken) ?? ""
        let defaultSearchEnabled = RemoteLLMProvider(rawValue: providerID)?.defaultSearchEnabled ?? false
        searchEnabled = try container.decodeIfPresent(Bool.self, forKey: .searchEnabled) ?? defaultSearchEnabled
        openAIChunkPseudoRealtimeEnabled = try container.decodeIfPresent(Bool.self, forKey: .openAIChunkPseudoRealtimeEnabled) ?? false
        doubaoDictionaryMode = try container.decodeIfPresent(String.self, forKey: .doubaoDictionaryMode) ?? DoubaoDictionaryMode.requestScoped.rawValue
        doubaoEnableRequestHotwords = try container.decodeIfPresent(Bool.self, forKey: .doubaoEnableRequestHotwords) ?? true
        doubaoEnableRequestCorrections = try container.decodeIfPresent(Bool.self, forKey: .doubaoEnableRequestCorrections) ?? true
    }

    var withoutSensitiveValues: RemoteProviderConfiguration {
        var sanitized = self
        sanitized.apiKey = ""
        sanitized.appID = ""
        sanitized.accessToken = ""
        return sanitized
    }
}

enum RemoteModelConfigurationStore {
    enum SensitiveValueLoading {
        case metadataOnly
        case includeStoredValues
    }

    private enum SensitiveField: String, CaseIterable {
        case apiKey
        case appID
        case accessToken
    }

    static func loadConfigurations(
        from raw: String,
        sensitiveValueLoading: SensitiveValueLoading = .includeStoredValues
    ) -> [String: RemoteProviderConfiguration] {
        let items = decodedConfigurations(from: raw).map(normalizedCompatibilityValues(for:))
        return Dictionary(uniqueKeysWithValues: items.map { item in
            let resolved = switch sensitiveValueLoading {
            case .metadataOnly:
                item.withoutSensitiveValues
            case .includeStoredValues:
                resolvedSensitiveValues(for: item)
            }
            return (resolved.providerID, resolved)
        })
    }

    static func saveConfigurations(_ values: [String: RemoteProviderConfiguration]) -> String {
        let items = values.values.sorted(by: { $0.providerID < $1.providerID })
        for item in items {
            persistSensitiveValues(for: item)
        }
        return encodeConfigurations(items.map(\.withoutSensitiveValues))
    }

    static func saveConfiguration(
        _ configuration: RemoteProviderConfiguration,
        updating raw: String
    ) -> String {
        var items = decodedConfigurations(from: raw).map(normalizedCompatibilityValues(for:))
        let sanitized = configuration.withoutSensitiveValues

        if let existingIndex = items.firstIndex(where: { $0.providerID == configuration.providerID }) {
            items[existingIndex] = sanitized
        } else {
            items.append(sanitized)
        }

        persistSensitiveValues(for: configuration)
        return encodeConfigurations(items.sorted(by: { $0.providerID < $1.providerID }))
    }

    static func migrateLegacyStoredSecrets(defaults: UserDefaults = .standard) {
        migrateLegacyStoredSecrets(
            defaultsKey: AppPreferenceKey.remoteASRProviderConfigurations,
            defaults: defaults
        )
        migrateLegacyStoredSecrets(
            defaultsKey: AppPreferenceKey.remoteLLMProviderConfigurations,
            defaults: defaults
        )
    }

    // Temporary compatibility migration for persisted legacy LLM endpoints.
    // Remove this after the legacy upgrade window closes and all supported users
    // have moved through a version that rewrites old `/models` and
    // `/chat/completions` URLs to `/responses`.
    static func migrateLegacyLLMEndpoints(defaults: UserDefaults = .standard) {
        let defaultsKey = AppPreferenceKey.remoteLLMProviderConfigurations
        let raw = defaults.string(forKey: defaultsKey) ?? ""
        guard !raw.isEmpty else { return }

        let decoded = decodedConfigurations(from: raw)
        let migrated = encodeConfigurations(decoded.map(normalizedCompatibilityValues(for:)))
        if migrated != raw {
            defaults.set(migrated, forKey: defaultsKey)
        }
    }

    static func resolvedASRConfiguration(
        provider: RemoteASRProvider,
        stored: [String: RemoteProviderConfiguration]
    ) -> RemoteProviderConfiguration {
        let allowedModelIDs = Set(provider.modelOptions.map(\.id))
        if let existing = stored[provider.rawValue] {
            var normalized = existing
            if !allowedModelIDs.contains(normalized.model) {
                normalized.model = provider.suggestedModel
            }
            if provider != .openAIWhisper {
                normalized.openAIChunkPseudoRealtimeEnabled = false
            }
            return normalized
        }
        return RemoteProviderConfiguration(
            providerID: provider.rawValue,
            model: provider.suggestedModel,
            meetingModel: "",
            endpoint: "",
            apiKey: ""
        )
    }

    static func resolvedLLMConfiguration(
        provider: RemoteLLMProvider,
        stored: [String: RemoteProviderConfiguration]
    ) -> RemoteProviderConfiguration {
        if let existing = stored[provider.rawValue] {
            var normalized = normalizedCompatibilityValues(for: existing)
            if !provider.supportsHostedSearch {
                normalized.searchEnabled = false
            }
            return normalized
        }
        return RemoteProviderConfiguration(
            providerID: provider.rawValue,
            model: provider.suggestedModel,
            meetingModel: "",
            endpoint: "",
            apiKey: "",
            searchEnabled: provider.defaultSearchEnabled
        )
    }

    private static func migrateLegacyStoredSecrets(defaultsKey: String, defaults: UserDefaults) {
        let raw = defaults.string(forKey: defaultsKey) ?? ""
        guard !raw.isEmpty else { return }
        let decoded = decodedConfigurations(from: raw)
        guard decoded.contains(where: hasInlineSensitiveValues) else { return }

        let normalized = decoded.map(normalizedCompatibilityValues(for:))
        for configuration in normalized {
            persistSensitiveValues(for: configuration)
        }
        let sanitized = encodeConfigurations(normalized.map(\.withoutSensitiveValues))
        if sanitized != raw {
            defaults.set(sanitized, forKey: defaultsKey)
        }
    }

    nonisolated private static func decodedConfigurations(from raw: String) -> [RemoteProviderConfiguration] {
        guard let data = raw.data(using: .utf8), !data.isEmpty else {
            return []
        }
        do {
            return try JSONDecoder().decode([RemoteProviderConfiguration].self, from: data)
        } catch {
            return []
        }
    }

    nonisolated private static func encodeConfigurations(_ items: [RemoteProviderConfiguration]) -> String {
        guard let data = try? JSONEncoder().encode(items),
              let text = String(data: data, encoding: .utf8)
        else {
            return ""
        }
        return text
    }

    nonisolated private static func normalizedCompatibilityValues(
        for configuration: RemoteProviderConfiguration
    ) -> RemoteProviderConfiguration {
        guard let provider = RemoteLLMProvider(rawValue: configuration.providerID) else {
            return configuration
        }

        var normalized = configuration
        if !provider.supportsHostedSearch {
            normalized.searchEnabled = false
        }

        let trimmedEndpoint = configuration.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard provider.usesResponsesAPI, !trimmedEndpoint.isEmpty else {
            return normalized
        }

        let runtimeClient = RemoteLLMRuntimeClient()
        normalized.endpoint = runtimeClient.resolvedLLMEndpoint(
            provider: provider,
            endpoint: trimmedEndpoint,
            model: configuration.model
        )
        return normalized
    }

    nonisolated private static func resolvedSensitiveValues(for configuration: RemoteProviderConfiguration) -> RemoteProviderConfiguration {
        var resolved = configuration
        for field in SensitiveField.allCases {
            let keychainValue = VoxtSecureStorage.string(for: keychainAccount(providerID: configuration.providerID, field: field))
            let currentValue = sensitiveValue(for: field, in: configuration)
            let finalValue = keychainValue ?? currentValue
            if keychainValue == nil, !currentValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VoxtSecureStorage.set(currentValue, for: keychainAccount(providerID: configuration.providerID, field: field))
            }
            setSensitiveValue(finalValue, for: field, in: &resolved)
        }
        return resolved
    }

    nonisolated private static func persistSensitiveValues(for configuration: RemoteProviderConfiguration) {
        for field in SensitiveField.allCases {
            let value = sensitiveValue(for: field, in: configuration)
            VoxtSecureStorage.set(value, for: keychainAccount(providerID: configuration.providerID, field: field))
        }
    }

    nonisolated private static func hasInlineSensitiveValues(_ configuration: RemoteProviderConfiguration) -> Bool {
        SensitiveField.allCases.contains { field in
            !sensitiveValue(for: field, in: configuration)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        }
    }

    nonisolated private static func keychainAccount(providerID: String, field: SensitiveField) -> String {
        "remote-provider.\(providerID).\(field.rawValue)"
    }

    nonisolated private static func sensitiveValue(
        for field: SensitiveField,
        in configuration: RemoteProviderConfiguration
    ) -> String {
        switch field {
        case .apiKey:
            return configuration.apiKey
        case .appID:
            return configuration.appID
        case .accessToken:
            return configuration.accessToken
        }
    }

    nonisolated private static func setSensitiveValue(
        _ value: String,
        for field: SensitiveField,
        in configuration: inout RemoteProviderConfiguration
    ) {
        switch field {
        case .apiKey:
            configuration.apiKey = value
        case .appID:
            configuration.appID = value
        case .accessToken:
            configuration.accessToken = value
        }
    }
}
