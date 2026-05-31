import Foundation

#if canImport(Security)
import Security
#endif

public enum MapofAgentsPairingTokenVault {
    private static let service = "dev.mapofagents.pairing-token"

    public enum VaultError: LocalizedError, Sendable {
        case missingToken
        case unavailable
        case saveFailed(Int32)
        case deleteFailed(Int32)

        public var errorDescription: String? {
            switch self {
            case .missingToken:
                return "The paired Mac token is empty and could not be saved securely."
            case .unavailable:
                return "Secure token storage is not available on this platform."
            case .saveFailed(let status):
                return "The paired Mac token could not be saved to Keychain (OSStatus \(status))."
            case .deleteFailed(let status):
                return "The paired Mac token could not be removed from Keychain (OSStatus \(status))."
            }
        }
    }

    public static func save(_ token: String, for hostID: HostID) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw VaultError.missingToken }

        #if canImport(Security)
        let account = hostID.rawValue
        let data = Data(trimmed.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let deleteStatus = SecItemDelete(query as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            throw VaultError.deleteFailed(deleteStatus)
        }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw VaultError.saveFailed(addStatus)
        }
        #else
        throw VaultError.unavailable
        #endif
    }

    public static func load(for hostID: HostID) -> String? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostID.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            return nil
        }
        return token
        #else
        return nil
        #endif
    }

    public static func delete(for hostID: HostID) throws {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostID.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultError.deleteFailed(status)
        }
        #else
        throw VaultError.unavailable
        #endif
    }
}
