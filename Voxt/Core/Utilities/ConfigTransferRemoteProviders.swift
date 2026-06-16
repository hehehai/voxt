// ConfigTransferRemoteProviders.swift
// Provides Config Transfer Remote Providers for shared utilities.

import Foundation

extension ConfigurationTransferManager {
    static func sanitizeRemoteConfigurations(_ raw: String) -> [RemoteProviderConfiguration] {
        RemoteModelConfigurationStore.loadConfigurations(
            from: raw,
            sensitiveValueLoading: .metadataOnly
        )
        .values
        .sorted { $0.providerID < $1.providerID }
    }

    static func restoreRemoteConfigurations(_ configurations: [RemoteProviderConfiguration]) -> String {
        let normalized = configurations.map { configuration in
            var resolved = configuration
            if resolved.apiKey == storedRemoteSensitivePlaceholder || resolved.apiKey == sensitivePlaceholder {
                resolved.apiKey = ""
            }
            if resolved.appID == storedRemoteSensitivePlaceholder || resolved.appID == sensitivePlaceholder {
                resolved.appID = ""
            }
            if resolved.accessToken == storedRemoteSensitivePlaceholder || resolved.accessToken == sensitivePlaceholder {
                resolved.accessToken = ""
            }
            return resolved
        }
        let dictionary = Dictionary(uniqueKeysWithValues: normalized.map { ($0.providerID, $0) })
        return RemoteModelConfigurationStore.saveConfigurations(dictionary)
    }
}
