import Foundation
import Security

enum VoxtSecureStorage {
    nonisolated private static let defaultServiceName: String = {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.voxt.Voxt"
        return "\(bundleID).secure-storage"
    }()

    nonisolated private static var serviceName: String {
        defaultServiceName
    }

    nonisolated static func string(for account: String) -> String? {
        var query = baseQuery(for: account)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            print("[Voxt] [WARN] Keychain read failed. account=\(account), status=\(status)")
            return nil
        }
    }

    nonisolated static func set(_ value: String, for account: String) {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            removeValue(for: account)
            return
        }

        let data = Data(value.utf8)
        let query = baseQuery(for: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if updateStatus != errSecSuccess {
                print("[Voxt] [WARN] Keychain update failed. account=\(account), status=\(updateStatus)")
            }
        case errSecItemNotFound:
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            if addStatus != errSecSuccess {
                print("[Voxt] [WARN] Keychain add failed. account=\(account), status=\(addStatus)")
            }
        default:
            print("[Voxt] [WARN] Keychain lookup before write failed. account=\(account), status=\(status)")
        }
    }

    nonisolated static func removeValue(for account: String) {
        let status = SecItemDelete(baseQuery(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            print("[Voxt] [WARN] Keychain delete failed. account=\(account), status=\(status)")
            return
        }
    }

    nonisolated static func clearAllForTesting() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            print("[Voxt] [WARN] Keychain reset failed. status=\(status)")
            return
        }
    }

    nonisolated private static func baseQuery(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
    }
}
