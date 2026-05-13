import Foundation

struct SanitizedRemoteProviderConfiguration: Codable {
    var providerID: String
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

    init(
        providerID: String,
        model: String,
        endpoint: String,
        apiKey: String,
        appID: String,
        accessToken: String,
        searchEnabled: Bool,
        openAIChunkPseudoRealtimeEnabled: Bool,
        openAIReasoningEffort: String,
        openAITextVerbosity: String,
        openAIMaxOutputTokens: Int?,
        doubaoDictionaryMode: String,
        doubaoEnableRequestHotwords: Bool,
        doubaoEnableRequestCorrections: Bool,
        ollamaResponseFormat: String,
        ollamaJSONSchema: String,
        ollamaThinkMode: String,
        ollamaKeepAlive: String,
        ollamaLogprobsEnabled: Bool,
        ollamaTopLogprobs: Int?,
        ollamaOptionsJSON: String,
        omlxResponseFormat: String,
        omlxJSONSchema: String,
        omlxIncludeUsageStreamOptions: Bool,
        omlxExtraBodyJSON: String
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
}

extension ConfigurationTransferManager {
    static func sanitizeRemoteConfigurations(_ raw: String) -> [SanitizedRemoteProviderConfiguration] {
        let stored = RemoteModelConfigurationStore.loadConfigurations(from: raw)
        return stored.values.sorted(by: { $0.providerID < $1.providerID }).map {
            SanitizedRemoteProviderConfiguration(
                providerID: $0.providerID,
                model: $0.model,
                endpoint: $0.endpoint,
                apiKey: sanitizeSensitive($0.apiKey),
                appID: sanitizeSensitive($0.appID),
                accessToken: sanitizeSensitive($0.accessToken),
                searchEnabled: $0.searchEnabled,
                openAIChunkPseudoRealtimeEnabled: $0.openAIChunkPseudoRealtimeEnabled,
                openAIReasoningEffort: $0.openAIReasoningEffort,
                openAITextVerbosity: $0.openAITextVerbosity,
                openAIMaxOutputTokens: $0.openAIMaxOutputTokens,
                doubaoDictionaryMode: $0.doubaoDictionaryMode,
                doubaoEnableRequestHotwords: $0.doubaoEnableRequestHotwords,
                doubaoEnableRequestCorrections: $0.doubaoEnableRequestCorrections,
                ollamaResponseFormat: $0.ollamaResponseFormat,
                ollamaJSONSchema: $0.ollamaJSONSchema,
                ollamaThinkMode: $0.ollamaThinkMode,
                ollamaKeepAlive: $0.ollamaKeepAlive,
                ollamaLogprobsEnabled: $0.ollamaLogprobsEnabled,
                ollamaTopLogprobs: $0.ollamaTopLogprobs,
                ollamaOptionsJSON: $0.ollamaOptionsJSON,
                omlxResponseFormat: $0.omlxResponseFormat,
                omlxJSONSchema: $0.omlxJSONSchema,
                omlxIncludeUsageStreamOptions: $0.omlxIncludeUsageStreamOptions,
                omlxExtraBodyJSON: $0.omlxExtraBodyJSON
            )
        }
    }

    static func restoreRemoteConfigurations(_ values: [SanitizedRemoteProviderConfiguration]) -> String {
        let mapped = Dictionary(uniqueKeysWithValues: values.map { item in
            (
                item.providerID,
                RemoteProviderConfiguration(
                    providerID: item.providerID,
                    model: item.model,
                    endpoint: item.endpoint,
                    apiKey: resolveImportedSensitive(item.apiKey),
                    appID: resolveImportedSensitive(item.appID),
                    accessToken: resolveImportedSensitive(item.accessToken),
                    searchEnabled: item.searchEnabled,
                    openAIChunkPseudoRealtimeEnabled: item.openAIChunkPseudoRealtimeEnabled,
                    openAIReasoningEffort: item.openAIReasoningEffort,
                    openAITextVerbosity: item.openAITextVerbosity,
                    openAIMaxOutputTokens: item.openAIMaxOutputTokens,
                    doubaoDictionaryMode: item.doubaoDictionaryMode,
                    doubaoEnableRequestHotwords: item.doubaoEnableRequestHotwords,
                    doubaoEnableRequestCorrections: item.doubaoEnableRequestCorrections,
                    ollamaResponseFormat: item.ollamaResponseFormat,
                    ollamaJSONSchema: item.ollamaJSONSchema,
                    ollamaThinkMode: item.ollamaThinkMode,
                    ollamaKeepAlive: item.ollamaKeepAlive,
                    ollamaLogprobsEnabled: item.ollamaLogprobsEnabled,
                    ollamaTopLogprobs: item.ollamaTopLogprobs,
                    ollamaOptionsJSON: item.ollamaOptionsJSON,
                    omlxResponseFormat: item.omlxResponseFormat,
                    omlxJSONSchema: item.omlxJSONSchema,
                    omlxIncludeUsageStreamOptions: item.omlxIncludeUsageStreamOptions,
                    omlxExtraBodyJSON: item.omlxExtraBodyJSON
                )
            )
        })
        return RemoteModelConfigurationStore.saveConfigurations(mapped)
    }
}
