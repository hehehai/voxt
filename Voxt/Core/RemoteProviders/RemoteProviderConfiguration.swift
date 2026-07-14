// RemoteProviderConfiguration.swift
// Provides Remote Provider Configuration for remote provider configuration.

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
        if normalized == "gpt-5.3-codex-spark" || normalized.hasPrefix("gpt-5.3-codex-spark-") {
            return [.automatic, .none, .low, .medium, .high]
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

fileprivate nonisolated struct RemoteStoredCredentialPresence: Codable, Hashable {
    var apiKey: Bool
    var appID: Bool
    var accessToken: Bool

    init(apiKey: String, appID: String, accessToken: String) {
        self.apiKey = Self.isPresent(apiKey)
        self.appID = Self.isPresent(appID)
        self.accessToken = Self.isPresent(accessToken)
    }

    private static func isPresent(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isEmpty: Bool {
        !apiKey && !appID && !accessToken
    }
}

struct RemoteProviderConfiguration: Codable, Identifiable, Hashable {
    let providerID: String
    var model: String
    var endpoint: String
    var apiKey: String
    var appID: String
    var accessToken: String
    fileprivate var storedCredentialPresence: RemoteStoredCredentialPresence?
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
    var codexAuthFilePath: String
    var codexAuthFileBookmark: Data?
    var codexFastModeEnabled: Bool
    var generationSettings: LLMGenerationSettings

    var id: String { providerID }

    var hasUsableModel: Bool {
        !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isConfigured: Bool {
        if RemoteLLMProvider(rawValue: providerID)?.apiKeyIsOptional == true {
            return hasUsableModel
        }
        if providerID == RemoteASRProvider.doubaoASR.rawValue {
            return hasUsableModel &&
                !appID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    var resolvedCodexAuthFilePath: String {
        codexAuthFilePath.trimmingCharacters(in: .whitespacesAndNewlines)
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
        omlxExtraBodyJSON: String = "",
        codexAuthFilePath: String = "",
        codexAuthFileBookmark: Data? = nil,
        codexFastModeEnabled: Bool = false,
        generationSettings: LLMGenerationSettings? = nil
    ) {
        self.providerID = providerID
        self.model = model
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.appID = appID
        self.accessToken = accessToken
        storedCredentialPresence = RemoteStoredCredentialPresence(
            apiKey: apiKey,
            appID: appID,
            accessToken: accessToken
        )
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
        self.codexAuthFilePath = codexAuthFilePath
        self.codexAuthFileBookmark = codexAuthFileBookmark
        self.codexFastModeEnabled = codexFastModeEnabled
        self.generationSettings = generationSettings ?? LLMGenerationSettings.legacy(
            providerID: providerID,
            openAIReasoningEffort: openAIReasoningEffort,
            openAIMaxOutputTokens: openAIMaxOutputTokens,
            ollamaResponseFormat: ollamaResponseFormat,
            ollamaThinkMode: ollamaThinkMode,
            ollamaLogprobsEnabled: ollamaLogprobsEnabled,
            ollamaTopLogprobs: ollamaTopLogprobs,
            ollamaOptionsJSON: ollamaOptionsJSON,
            omlxResponseFormat: omlxResponseFormat,
            omlxExtraBodyJSON: omlxExtraBodyJSON
        )
    }

    enum CodingKeys: String, CodingKey {
        case providerID
        case model
        case endpoint
        case apiKey
        case appID
        case accessToken
        case storedCredentialPresence
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
        case codexAuthFilePath
        case codexAuthFileBookmark
        case codexFastModeEnabled
        case generationSettings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providerID = try container.decode(String.self, forKey: .providerID)
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        appID = try container.decodeIfPresent(String.self, forKey: .appID) ?? ""
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken) ?? ""
        storedCredentialPresence = try container.decodeIfPresent(
            RemoteStoredCredentialPresence.self,
            forKey: .storedCredentialPresence
        )
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
        codexAuthFilePath = try container.decodeIfPresent(String.self, forKey: .codexAuthFilePath) ?? ""
        codexAuthFileBookmark = try container.decodeIfPresent(Data.self, forKey: .codexAuthFileBookmark)
        codexFastModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .codexFastModeEnabled) ?? false
        generationSettings = try container.decodeIfPresent(LLMGenerationSettings.self, forKey: .generationSettings)
            ?? LLMGenerationSettings.legacy(
                providerID: providerID,
                openAIReasoningEffort: openAIReasoningEffort,
                openAIMaxOutputTokens: openAIMaxOutputTokens,
                ollamaResponseFormat: ollamaResponseFormat,
                ollamaThinkMode: ollamaThinkMode,
                ollamaLogprobsEnabled: ollamaLogprobsEnabled,
                ollamaTopLogprobs: ollamaTopLogprobs,
                ollamaOptionsJSON: ollamaOptionsJSON,
                omlxResponseFormat: omlxResponseFormat,
                omlxExtraBodyJSON: omlxExtraBodyJSON
            )
    }

    nonisolated var withoutSensitiveValues: RemoteProviderConfiguration {
        var sanitized = self
        sanitized.storedCredentialPresence = RemoteStoredCredentialPresence(
            apiKey: apiKey,
            appID: appID,
            accessToken: accessToken
        )
        sanitized.apiKey = ""
        sanitized.appID = ""
        sanitized.accessToken = ""
        return sanitized
    }
}

enum RemoteModelConfigurationStore {
    private static let currentCredentialMigrationVersion = 1

    enum SaveError: LocalizedError, Equatable {
        case secureStorageUnavailable
        case metadataEncodingFailed

        var errorDescription: String? {
            switch self {
            case .secureStorageUnavailable:
                return AppLocalization.localizedString(
                    "Configuration could not be saved securely. Check Keychain access and try again."
                )
            case .metadataEncodingFailed:
                return AppLocalization.localizedString(
                    "Configuration could not be encoded. Please try again."
                )
            }
        }
    }

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

    private nonisolated struct StoredSensitiveValues: Codable {
        var apiKey: String
        var appID: String
        var accessToken: String

        init(configuration: RemoteProviderConfiguration) {
            apiKey = configuration.apiKey
            appID = configuration.appID
            accessToken = configuration.accessToken
        }

        var isEmpty: Bool {
            [apiKey, appID, accessToken].allSatisfy {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }

        func applying(to configuration: RemoteProviderConfiguration) -> RemoteProviderConfiguration {
            var resolved = configuration
            resolved.apiKey = apiKey
            resolved.appID = appID
            resolved.accessToken = accessToken
            resolved.storedCredentialPresence = RemoteStoredCredentialPresence(
                apiKey: apiKey,
                appID: appID,
                accessToken: accessToken
            )
            return resolved
        }
    }

    private nonisolated enum CredentialMigrationResolution {
        case values(StoredSensitiveValues)
        case missing
        case unavailable
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

    static func loadConfiguration(
        providerID: String,
        from raw: String,
        sensitiveValueLoading: SensitiveValueLoading = .includeStoredValues
    ) -> RemoteProviderConfiguration? {
        guard let item = decodedConfigurations(from: raw)
            .map(normalizedCompatibilityValues(for:))
            .first(where: { $0.providerID == providerID })
        else {
            return nil
        }

        switch sensitiveValueLoading {
        case .metadataOnly:
            return resolvedSensitiveValuePresence(for: item)
        case .includeStoredValues:
            return resolvedSensitiveValues(for: item)
        }
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
    ) -> Result<String, SaveError> {
        var items = decodedConfigurations(from: raw).map(normalizedCompatibilityValues(for:))
        let sanitized = configuration.withoutSensitiveValues

        if let existingIndex = items.firstIndex(where: { $0.providerID == configuration.providerID }) {
            items[existingIndex] = sanitized
        } else {
            items.append(sanitized)
        }

        guard let encoded = encodedConfigurations(items.sorted(by: { $0.providerID < $1.providerID })) else {
            return .failure(.metadataEncodingFailed)
        }
        guard persistSensitiveValues(for: configuration) else {
            return .failure(.secureStorageUnavailable)
        }
        return .success(encoded)
    }

    static func migrateLegacyStoredSecrets(defaults: UserDefaults = .standard) {
        guard defaults.integer(forKey: AppPreferenceKey.remoteCredentialMigrationVersion)
            < currentCredentialMigrationVersion
        else {
            return
        }

        let asrCompleted = migrateLegacyStoredSecrets(
            defaultsKey: AppPreferenceKey.remoteASRProviderConfigurations,
            defaults: defaults
        )
        let llmCompleted = migrateLegacyStoredSecrets(
            defaultsKey: AppPreferenceKey.remoteLLMProviderConfigurations,
            defaults: defaults
        )
        guard asrCompleted, llmCompleted else { return }
        defaults.set(
            currentCredentialMigrationVersion,
            forKey: AppPreferenceKey.remoteCredentialMigrationVersion
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

    static func resolvedASRConfiguration(
        provider: RemoteASRProvider,
        from raw: String
    ) -> RemoteProviderConfiguration {
        let stored = loadConfiguration(providerID: provider.rawValue, from: raw)
            .map { [provider.rawValue: $0] } ?? [:]
        return resolvedASRConfiguration(provider: provider, stored: stored)
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

    static func resolvedLLMConfiguration(
        provider: RemoteLLMProvider,
        from raw: String
    ) -> RemoteProviderConfiguration {
        let stored = loadConfiguration(providerID: provider.rawValue, from: raw)
            .map { [provider.rawValue: $0] } ?? [:]
        return resolvedLLMConfiguration(provider: provider, stored: stored)
    }

    static func isStoredLLMConfigurationConfigured(
        provider: RemoteLLMProvider,
        stored: [String: RemoteProviderConfiguration]
    ) -> Bool {
        guard stored[provider.rawValue] != nil else { return false }
        let configuration = resolvedLLMConfiguration(provider: provider, stored: stored)
        return configuration.isConfigured && configuration.hasUsableModel
    }

    @discardableResult
    private static func migrateLegacyStoredSecrets(defaultsKey: String, defaults: UserDefaults) -> Bool {
        let raw = defaults.string(forKey: defaultsKey) ?? ""
        guard !raw.isEmpty else { return true }
        let decoded = decodedConfigurations(from: raw)
        let normalized = decoded.map(normalizedCompatibilityValues(for:))
        var changed = false
        var completed = true
        let migrated = normalized.map { configuration in
            if hasInlineSensitiveValues(configuration) {
                guard persistSensitiveValues(for: configuration) else {
                    completed = false
                    return configuration
                }
                changed = true
                return configuration.withoutSensitiveValues
            }

            // An explicit empty presence mask means the user never configured a
            // credential (or intentionally cleared it). Do not touch Keychain.
            if configuration.storedCredentialPresence?.isEmpty == true {
                return configuration
            }

            switch credentialMigrationResolution(for: configuration) {
            case .values(let values):
                // An empty bundled tombstone is not a configured credential. It
                // only needs to replace a stale positive presence mask.
                guard !values.isEmpty || configuration.storedCredentialPresence != nil else {
                    return configuration
                }
                let resolved = values.applying(to: configuration).withoutSensitiveValues
                if resolved != configuration {
                    changed = true
                }
                return resolved
            case .missing:
                // No metadata and no stored value means this provider was never
                // configured, so there is nothing to migrate.
                guard configuration.storedCredentialPresence != nil else {
                    return configuration
                }
                // A previous build may have left a positive mask after losing
                // the Keychain item. Persist one definitive empty mask so the UI
                // asks for the credential once and future launches do no work.
                let resolved = configuration.withoutSensitiveValues
                if resolved != configuration {
                    changed = true
                }
                return resolved
            case .unavailable:
                // Never turn an inconclusive Keychain read into data loss. Leave
                // the migration pending and retry on a later launch.
                completed = false
                return configuration
            }
        }

        if changed {
            let encoded = encodeConfigurations(migrated)
            if encoded != raw {
                defaults.set(encoded, forKey: defaultsKey)
            }
        }
        return completed
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
        encodedConfigurations(items) ?? ""
    }

    nonisolated private static func encodedConfigurations(
        _ items: [RemoteProviderConfiguration]
    ) -> String? {
        guard let data = try? JSONEncoder().encode(items) else { return nil }
        return String(data: data, encoding: .utf8)
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
        let bundledAccount = bundledKeychainAccount(providerID: configuration.providerID)
        if let stored = VoxtSecureStorage.string(for: bundledAccount),
           let data = stored.data(using: .utf8),
           let values = try? JSONDecoder().decode(StoredSensitiveValues.self, from: data) {
            return values.applying(to: configuration)
        }

        var resolved = configuration
        var foundLegacyValue = false
        for field in SensitiveField.allCases {
            let keychainValue = VoxtSecureStorage.string(
                for: legacyKeychainAccount(providerID: configuration.providerID, field: field)
            )
            let currentValue = sensitiveValue(for: field, in: configuration)
            let finalValue = keychainValue ?? currentValue
            foundLegacyValue = foundLegacyValue || keychainValue != nil
            setSensitiveValue(finalValue, for: field, in: &resolved)
        }

        if foundLegacyValue || hasInlineSensitiveValues(resolved) {
            _ = persistSensitiveValues(for: resolved)
        }
        return resolved
    }

    nonisolated private static func credentialMigrationResolution(
        for configuration: RemoteProviderConfiguration
    ) -> CredentialMigrationResolution {
        let bundledAccount = bundledKeychainAccount(providerID: configuration.providerID)
        switch VoxtSecureStorage.migrationValue(for: bundledAccount) {
        case .value(let stored):
            if let data = stored.data(using: .utf8),
               let values = try? JSONDecoder().decode(StoredSensitiveValues.self, from: data) {
                return .values(values)
            }
            // A corrupt bundled item is unusable, but an older per-field copy
            // may still be recoverable below.
        case .missing:
            break
        case .unavailable:
            return .unavailable
        }

        var resolved = configuration
        for field in SensitiveField.allCases {
            setSensitiveValue("", for: field, in: &resolved)
        }
        var foundLegacyValue = false
        for field in SensitiveField.allCases {
            let account = legacyKeychainAccount(providerID: configuration.providerID, field: field)
            switch VoxtSecureStorage.migrationValue(for: account) {
            case .value(let value):
                guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                foundLegacyValue = true
                setSensitiveValue(value, for: field, in: &resolved)
            case .missing:
                continue
            case .unavailable:
                return .unavailable
            }
        }

        guard foundLegacyValue else {
            return .missing
        }
        guard persistSensitiveValues(for: resolved) else {
            return .unavailable
        }
        return .values(StoredSensitiveValues(configuration: resolved))
    }

    nonisolated private static func resolvedSensitiveValuePresence(for configuration: RemoteProviderConfiguration) -> RemoteProviderConfiguration {
        var resolved = configuration.withoutSensitiveValues
        if let presence = configuration.storedCredentialPresence {
            applySensitiveValuePresence(presence, to: &resolved)
            return resolved
        }

        let bundledAccount = bundledKeychainAccount(providerID: configuration.providerID)
        if let stored = VoxtSecureStorage.string(for: bundledAccount),
           let data = stored.data(using: .utf8),
           let values = try? JSONDecoder().decode(StoredSensitiveValues.self, from: data) {
            applySensitiveValuePresence(
                RemoteStoredCredentialPresence(
                    apiKey: values.apiKey,
                    appID: values.appID,
                    accessToken: values.accessToken
                ),
                to: &resolved
            )
            return resolved
        }

        for field in SensitiveField.allCases {
            let hasKeychainValue = VoxtSecureStorage.hasString(
                for: legacyKeychainAccount(providerID: configuration.providerID, field: field)
            )
            let currentValue = sensitiveValue(for: field, in: configuration)
            let hasValue = hasKeychainValue || !currentValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            setSensitiveValue(hasValue ? redactedSensitiveValuePlaceholder : "", for: field, in: &resolved)
        }
        return resolved
    }

    nonisolated private static func applySensitiveValuePresence(
        _ presence: RemoteStoredCredentialPresence,
        to configuration: inout RemoteProviderConfiguration
    ) {
        configuration.apiKey = presence.apiKey ? redactedSensitiveValuePlaceholder : ""
        configuration.appID = presence.appID ? redactedSensitiveValuePlaceholder : ""
        configuration.accessToken = presence.accessToken ? redactedSensitiveValuePlaceholder : ""
        configuration.storedCredentialPresence = presence
    }

    @discardableResult
    nonisolated private static func persistSensitiveValues(
        for configuration: RemoteProviderConfiguration
    ) -> Bool {
        let values = StoredSensitiveValues(configuration: configuration)
        let bundledAccount = bundledKeychainAccount(providerID: configuration.providerID)
        guard let data = try? JSONEncoder().encode(values),
              let encoded = String(data: data, encoding: .utf8),
              VoxtSecureStorage.set(encoded, for: bundledAccount)
        else {
            return false
        }

        // The bundled item is authoritative as soon as it is written. In
        // particular, an encoded empty value acts as a tombstone so a failed
        // cleanup cannot make an old per-field credential visible again.
        var removedAllLegacyItems = true
        for field in SensitiveField.allCases {
            if !VoxtSecureStorage.removeValueWithoutUserInteraction(
                for: legacyKeychainAccount(providerID: configuration.providerID, field: field)
            ) {
                removedAllLegacyItems = false
            }
        }

        // Once every legacy account is gone, an empty tombstone is no longer
        // needed. Failure to remove it is harmless: it still resolves to the
        // same empty credential set and can be retried on a later save.
        if values.isEmpty, removedAllLegacyItems {
            _ = VoxtSecureStorage.removeValueWithoutUserInteraction(for: bundledAccount)
        }
        return true
    }

    nonisolated private static func hasInlineSensitiveValues(_ configuration: RemoteProviderConfiguration) -> Bool {
        SensitiveField.allCases.contains { field in
            !sensitiveValue(for: field, in: configuration)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        }
    }

    nonisolated private static func bundledKeychainAccount(providerID: String) -> String {
        "remote-provider.\(providerID).credentials"
    }

    nonisolated private static func legacyKeychainAccount(providerID: String, field: SensitiveField) -> String {
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
