import Foundation

enum OllamaResponseFormat: String, CaseIterable, Identifiable {
    case plain
    case json
    case jsonSchema

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plain:
            return AppLocalization.localizedString("Plain Text")
        case .json:
            return "JSON"
        case .jsonSchema:
            return AppLocalization.localizedString("JSON Schema")
        }
    }
}

enum OllamaThinkMode: String, CaseIterable, Identifiable {
    case off
    case on
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            return AppLocalization.localizedString("Off")
        case .on:
            return AppLocalization.localizedString("On")
        case .low:
            return AppLocalization.localizedString("Low")
        case .medium:
            return AppLocalization.localizedString("Medium")
        case .high:
            return AppLocalization.localizedString("High")
        }
    }
}

enum OMLXResponseFormat: String, CaseIterable, Identifiable {
    case plain
    case jsonSchema

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plain:
            return AppLocalization.localizedString("Plain Text")
        case .jsonSchema:
            return AppLocalization.localizedString("JSON Schema")
        }
    }
}

enum OpenAIReasoningEffort: String, CaseIterable, Identifiable {
    case automatic
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return AppLocalization.localizedString("Default")
        case .none:
            return AppLocalization.localizedString("None")
        case .minimal:
            return AppLocalization.localizedString("Minimal")
        case .low:
            return AppLocalization.localizedString("Low")
        case .medium:
            return AppLocalization.localizedString("Medium")
        case .high:
            return AppLocalization.localizedString("High")
        case .xhigh:
            return AppLocalization.localizedString("Extra High")
        }
    }

    static func supportedCases(forModel model: String) -> [OpenAIReasoningEffort] {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "gpt-5.2-pro" || normalized.hasPrefix("gpt-5.2-pro-") {
            return [.automatic, .medium, .high, .xhigh]
        }
        if normalized == "gpt-5-pro" || normalized.hasPrefix("gpt-5-pro-") {
            return [.automatic, .high]
        }
        if normalized == "gpt-5.2-codex" || normalized.hasPrefix("gpt-5.2-codex-") {
            return [.automatic, .low, .medium, .high, .xhigh]
        }
        if normalized == "gpt-5.1-codex-max" || normalized.hasPrefix("gpt-5.1-codex-max-") {
            return [.automatic, .none, .medium, .high, .xhigh]
        }
        if normalized == "gpt-5.2" || normalized.hasPrefix("gpt-5.2-") {
            return [.automatic, .none, .low, .medium, .high, .xhigh]
        }
        if normalized == "gpt-5.1" || normalized.hasPrefix("gpt-5.1-") {
            return [.automatic, .none, .low, .medium, .high]
        }
        if normalized.hasPrefix("gpt-5") {
            return [.automatic, .minimal, .low, .medium, .high]
        }
        if normalized.hasPrefix("o1") ||
            normalized.hasPrefix("o3") ||
            normalized.hasPrefix("o4") {
            return [.automatic, .low, .medium, .high]
        }
        return [.automatic]
    }

    static func apiValue(selection: String, model: String) -> String? {
        guard let value = OpenAIReasoningEffort(rawValue: selection),
              value != .automatic,
              supportedCases(forModel: model).contains(value)
        else {
            return nil
        }
        return value.rawValue
    }
}

enum OpenAITextVerbosity: String, CaseIterable, Identifiable {
    case automatic
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic:
            return AppLocalization.localizedString("Default")
        case .low:
            return AppLocalization.localizedString("Low")
        case .medium:
            return AppLocalization.localizedString("Medium")
        case .high:
            return AppLocalization.localizedString("High")
        }
    }

    static func supportsModel(_ model: String) -> Bool {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .hasPrefix("gpt-5")
    }

    static func apiValue(selection: String, model: String) -> String? {
        guard supportsModel(model),
              let value = OpenAITextVerbosity(rawValue: selection),
              value != .automatic
        else {
            return nil
        }
        return value.rawValue
    }
}

struct RemoteProviderConfiguration: Codable, Identifiable, Hashable {
    let providerID: String
    var model: String
    var endpoint: String
    var apiKey: String
    var appID: String
    var accessToken: String
    var searchEnabled: Bool
    var openAIChunkPseudoRealtimeEnabled: Bool
    var openAIReasoningEffort: String
    var openAITextVerbosity: String
    var openAIMaxOutputTokens: Int?
    var doubaoDictionaryMode: String
    var doubaoEnableRequestHotwords: Bool
    var doubaoEnableRequestCorrections: Bool
    var ollamaResponseFormat: String
    var ollamaJSONSchema: String
    var ollamaThinkMode: String
    var ollamaKeepAlive: String
    var ollamaLogprobsEnabled: Bool
    var ollamaTopLogprobs: Int?
    var ollamaOptionsJSON: String
    var omlxResponseFormat: String
    var omlxJSONSchema: String
    var omlxIncludeUsageStreamOptions: Bool
    var omlxExtraBodyJSON: String

    var id: String { providerID }

    var hasUsableModel: Bool {
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isConfigured: Bool {
        if RemoteLLMProvider(rawValue: providerID)?.apiKeyIsOptional == true {
            return hasUsableModel
        }
        return hasUsableModel && (
            !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    var doubaoDictionaryModeValue: DoubaoDictionaryMode {
        DoubaoDictionaryMode(rawValue: doubaoDictionaryMode) ?? .requestScoped
    }

    var ollamaResponseFormatValue: OllamaResponseFormat {
        OllamaResponseFormat(rawValue: ollamaResponseFormat) ?? .plain
    }

    var ollamaThinkModeValue: OllamaThinkMode {
        OllamaThinkMode(rawValue: ollamaThinkMode) ?? .off
    }

    var omlxResponseFormatValue: OMLXResponseFormat {
        OMLXResponseFormat(rawValue: omlxResponseFormat) ?? .plain
    }

    var openAIReasoningEffortValue: OpenAIReasoningEffort {
        OpenAIReasoningEffort(rawValue: openAIReasoningEffort) ?? .automatic
    }

    var openAITextVerbosityValue: OpenAITextVerbosity {
        OpenAITextVerbosity(rawValue: openAITextVerbosity) ?? .automatic
    }

    init(
        providerID: String,
        model: String,
        endpoint: String,
        apiKey: String,
        appID: String = "",
        accessToken: String = "",
        searchEnabled: Bool = false,
        openAIChunkPseudoRealtimeEnabled: Bool = false,
        openAIReasoningEffort: String = OpenAIReasoningEffort.automatic.rawValue,
        openAITextVerbosity: String = OpenAITextVerbosity.automatic.rawValue,
        openAIMaxOutputTokens: Int? = nil,
        doubaoDictionaryMode: String = DoubaoDictionaryMode.requestScoped.rawValue,
        doubaoEnableRequestHotwords: Bool = true,
        doubaoEnableRequestCorrections: Bool = true,
        ollamaResponseFormat: String = OllamaResponseFormat.plain.rawValue,
        ollamaJSONSchema: String = "",
        ollamaThinkMode: String = OllamaThinkMode.off.rawValue,
        ollamaKeepAlive: String = "",
        ollamaLogprobsEnabled: Bool = false,
        ollamaTopLogprobs: Int? = nil,
        ollamaOptionsJSON: String = "",
        omlxResponseFormat: String = OMLXResponseFormat.plain.rawValue,
        omlxJSONSchema: String = "",
        omlxIncludeUsageStreamOptions: Bool = false,
        omlxExtraBodyJSON: String = ""
    ) {
        self.providerID = providerID
        self.model = model
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.appID = appID
        self.accessToken = accessToken
        self.searchEnabled = searchEnabled
        self.openAIChunkPseudoRealtimeEnabled = openAIChunkPseudoRealtimeEnabled
        self.openAIReasoningEffort = openAIReasoningEffort
        self.openAITextVerbosity = openAITextVerbosity
        self.openAIMaxOutputTokens = openAIMaxOutputTokens
        self.doubaoDictionaryMode = doubaoDictionaryMode
        self.doubaoEnableRequestHotwords = doubaoEnableRequestHotwords
        self.doubaoEnableRequestCorrections = doubaoEnableRequestCorrections
        self.ollamaResponseFormat = ollamaResponseFormat
        self.ollamaJSONSchema = ollamaJSONSchema
        self.ollamaThinkMode = ollamaThinkMode
        self.ollamaKeepAlive = ollamaKeepAlive
        self.ollamaLogprobsEnabled = ollamaLogprobsEnabled
        self.ollamaTopLogprobs = ollamaTopLogprobs
        self.ollamaOptionsJSON = ollamaOptionsJSON
        self.omlxResponseFormat = omlxResponseFormat
        self.omlxJSONSchema = omlxJSONSchema
        self.omlxIncludeUsageStreamOptions = omlxIncludeUsageStreamOptions
        self.omlxExtraBodyJSON = omlxExtraBodyJSON
    }

    enum CodingKeys: String, CodingKey {
        case providerID
        case model
        case endpoint
        case apiKey
        case appID
        case accessToken
        case searchEnabled
        case openAIChunkPseudoRealtimeEnabled
        case openAIReasoningEffort
        case openAITextVerbosity
        case openAIMaxOutputTokens
        case doubaoDictionaryMode
        case doubaoEnableRequestHotwords
        case doubaoEnableRequestCorrections
        case ollamaResponseFormat
        case ollamaJSONSchema
        case ollamaThinkMode
        case ollamaKeepAlive
        case ollamaLogprobsEnabled
        case ollamaTopLogprobs
        case ollamaOptionsJSON
        case omlxResponseFormat
        case omlxJSONSchema
        case omlxIncludeUsageStreamOptions
        case omlxExtraBodyJSON
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerID = try container.decode(String.self, forKey: .providerID)
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        appID = try container.decodeIfPresent(String.self, forKey: .appID) ?? ""
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken) ?? ""
        let defaultSearchEnabled = RemoteLLMProvider(rawValue: providerID)?.defaultSearchEnabled ?? false
        searchEnabled = try container.decodeIfPresent(Bool.self, forKey: .searchEnabled) ?? defaultSearchEnabled
        openAIChunkPseudoRealtimeEnabled = try container.decodeIfPresent(Bool.self, forKey: .openAIChunkPseudoRealtimeEnabled) ?? false
        openAIReasoningEffort = try container.decodeIfPresent(String.self, forKey: .openAIReasoningEffort) ?? OpenAIReasoningEffort.automatic.rawValue
        openAITextVerbosity = try container.decodeIfPresent(String.self, forKey: .openAITextVerbosity) ?? OpenAITextVerbosity.automatic.rawValue
        openAIMaxOutputTokens = try container.decodeIfPresent(Int.self, forKey: .openAIMaxOutputTokens)
        doubaoDictionaryMode = try container.decodeIfPresent(String.self, forKey: .doubaoDictionaryMode) ?? DoubaoDictionaryMode.requestScoped.rawValue
        doubaoEnableRequestHotwords = try container.decodeIfPresent(Bool.self, forKey: .doubaoEnableRequestHotwords) ?? true
        doubaoEnableRequestCorrections = try container.decodeIfPresent(Bool.self, forKey: .doubaoEnableRequestCorrections) ?? true
        ollamaResponseFormat = try container.decodeIfPresent(String.self, forKey: .ollamaResponseFormat) ?? OllamaResponseFormat.plain.rawValue
        ollamaJSONSchema = try container.decodeIfPresent(String.self, forKey: .ollamaJSONSchema) ?? ""
        ollamaThinkMode = try container.decodeIfPresent(String.self, forKey: .ollamaThinkMode) ?? OllamaThinkMode.off.rawValue
        ollamaKeepAlive = try container.decodeIfPresent(String.self, forKey: .ollamaKeepAlive) ?? ""
        ollamaLogprobsEnabled = try container.decodeIfPresent(Bool.self, forKey: .ollamaLogprobsEnabled) ?? false
        ollamaTopLogprobs = try container.decodeIfPresent(Int.self, forKey: .ollamaTopLogprobs)
        ollamaOptionsJSON = try container.decodeIfPresent(String.self, forKey: .ollamaOptionsJSON) ?? ""
        omlxResponseFormat = try container.decodeIfPresent(String.self, forKey: .omlxResponseFormat) ?? OMLXResponseFormat.plain.rawValue
        omlxJSONSchema = try container.decodeIfPresent(String.self, forKey: .omlxJSONSchema) ?? ""
        omlxIncludeUsageStreamOptions = try container.decodeIfPresent(Bool.self, forKey: .omlxIncludeUsageStreamOptions) ?? false
        omlxExtraBodyJSON = try container.decodeIfPresent(String.self, forKey: .omlxExtraBodyJSON) ?? ""
    }

    nonisolated var withoutSensitiveValues: RemoteProviderConfiguration {
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

    nonisolated private static let redactedSensitiveValuePlaceholder = "__stored__"

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
                resolvedSensitiveValuePresence(for: item)
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
            if !allowedModelIDs.contains(normalized.model),
               !allowsCustomASRModel(provider: provider, model: normalized.model) {
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
            endpoint: "",
            apiKey: ""
        )
    }

    private static func allowsCustomASRModel(provider: RemoteASRProvider, model: String) -> Bool {
        guard provider == .openAIWhisper else { return false }
        return !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            endpoint: "",
            apiKey: "",
            searchEnabled: provider.defaultSearchEnabled
        )
    }

    static func isStoredLLMConfigurationConfigured(
        provider: RemoteLLMProvider,
        stored: [String: RemoteProviderConfiguration]
    ) -> Bool {
        guard stored[provider.rawValue] != nil else { return false }
        let configuration = resolvedLLMConfiguration(provider: provider, stored: stored)
        return configuration.isConfigured && configuration.hasUsableModel
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

    nonisolated private static func resolvedSensitiveValuePresence(for configuration: RemoteProviderConfiguration) -> RemoteProviderConfiguration {
        var resolved = configuration.withoutSensitiveValues
        for field in SensitiveField.allCases {
            let keychainValue = VoxtSecureStorage.string(for: keychainAccount(providerID: configuration.providerID, field: field))
            let currentValue = sensitiveValue(for: field, in: configuration)
            let hasValue = !(keychainValue ?? currentValue)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
            setSensitiveValue(hasValue ? redactedSensitiveValuePlaceholder : "", for: field, in: &resolved)
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
