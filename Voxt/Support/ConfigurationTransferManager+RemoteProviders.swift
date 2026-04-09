import Foundation

struct SanitizedRemoteProviderConfiguration: Codable {
    var providerID: String
    var model: String
    var meetingModel: String
    var endpoint: String
    var apiKey: String
    var appID: String
    var accessToken: String
    var openAIChunkPseudoRealtimeEnabled: Bool
    var doubaoDictionaryMode: String
    var doubaoEnableRequestHotwords: Bool
    var doubaoEnableRequestCorrections: Bool

    enum CodingKeys: String, CodingKey {
        case providerID
        case model
        case meetingModel
        case endpoint
        case apiKey
        case appID
        case accessToken
        case openAIChunkPseudoRealtimeEnabled
        case doubaoDictionaryMode
        case doubaoEnableRequestHotwords
        case doubaoEnableRequestCorrections
    }

    init(
        providerID: String,
        model: String,
        meetingModel: String,
        endpoint: String,
        apiKey: String,
        appID: String,
        accessToken: String,
        openAIChunkPseudoRealtimeEnabled: Bool,
        doubaoDictionaryMode: String,
        doubaoEnableRequestHotwords: Bool,
        doubaoEnableRequestCorrections: Bool
    ) {
        self.providerID = providerID
        self.model = model
        self.meetingModel = meetingModel
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.appID = appID
        self.accessToken = accessToken
        self.openAIChunkPseudoRealtimeEnabled = openAIChunkPseudoRealtimeEnabled
        self.doubaoDictionaryMode = doubaoDictionaryMode
        self.doubaoEnableRequestHotwords = doubaoEnableRequestHotwords
        self.doubaoEnableRequestCorrections = doubaoEnableRequestCorrections
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
        openAIChunkPseudoRealtimeEnabled = try container.decodeIfPresent(Bool.self, forKey: .openAIChunkPseudoRealtimeEnabled) ?? false
        doubaoDictionaryMode = try container.decodeIfPresent(String.self, forKey: .doubaoDictionaryMode) ?? DoubaoDictionaryMode.requestScoped.rawValue
        doubaoEnableRequestHotwords = try container.decodeIfPresent(Bool.self, forKey: .doubaoEnableRequestHotwords) ?? true
        doubaoEnableRequestCorrections = try container.decodeIfPresent(Bool.self, forKey: .doubaoEnableRequestCorrections) ?? true
    }
}

extension ConfigurationTransferManager {
    static func sanitizeRemoteConfigurations(_ raw: String) -> [SanitizedRemoteProviderConfiguration] {
        let stored = RemoteModelConfigurationStore.loadConfigurations(from: raw)
        return stored.values.sorted(by: { $0.providerID < $1.providerID }).map {
            SanitizedRemoteProviderConfiguration(
                providerID: $0.providerID,
                model: $0.model,
                meetingModel: $0.meetingModel,
                endpoint: $0.endpoint,
                apiKey: sanitizeSensitive($0.apiKey),
                appID: sanitizeSensitive($0.appID),
                accessToken: sanitizeSensitive($0.accessToken),
                openAIChunkPseudoRealtimeEnabled: $0.openAIChunkPseudoRealtimeEnabled,
                doubaoDictionaryMode: $0.doubaoDictionaryMode,
                doubaoEnableRequestHotwords: $0.doubaoEnableRequestHotwords,
                doubaoEnableRequestCorrections: $0.doubaoEnableRequestCorrections
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
                    meetingModel: item.meetingModel,
                    endpoint: item.endpoint,
                    apiKey: resolveImportedSensitive(item.apiKey),
                    appID: resolveImportedSensitive(item.appID),
                    accessToken: resolveImportedSensitive(item.accessToken),
                    openAIChunkPseudoRealtimeEnabled: item.openAIChunkPseudoRealtimeEnabled,
                    doubaoDictionaryMode: item.doubaoDictionaryMode,
                    doubaoEnableRequestHotwords: item.doubaoEnableRequestHotwords,
                    doubaoEnableRequestCorrections: item.doubaoEnableRequestCorrections
                )
            )
        })
        return RemoteModelConfigurationStore.saveConfigurations(mapped)
    }
}
