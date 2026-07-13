import Foundation

#if canImport(Security)
import Security
#endif

public protocol MapofAgentsPairingCredentialVault: Sendable {
    func saveRefreshCredential(_ credential: String, hostID: HostID, deviceID: String) throws
    func loadRefreshCredential(hostID: HostID, deviceID: String) throws -> String?
    func deleteRefreshCredential(hostID: HostID, deviceID: String) throws
}

public struct KeychainMapofAgentsPairingCredentialVault: MapofAgentsPairingCredentialVault {
    private static let service = "dev.mapofagents.pairing-refresh-credential"

    public init() {}

    public func saveRefreshCredential(_ credential: String, hostID: HostID, deviceID: String) throws {
        let trimmed = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MapofAgentsPairingTokenVault.VaultError.missingToken }

        #if canImport(Security)
        let query = baseQuery(hostID: hostID, deviceID: deviceID)
        let existingStatus = SecItemCopyMatching(query as CFDictionary, nil)
        if existingStatus == errSecSuccess {
            let update: [String: Any] = [
                kSecValueData as String: Data(trimmed.utf8),
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw MapofAgentsPairingTokenVault.VaultError.saveFailed(updateStatus)
            }
            return
        }
        guard existingStatus == errSecItemNotFound else {
            throw MapofAgentsPairingTokenVault.VaultError.saveFailed(existingStatus)
        }

        var attributes = query
        attributes[kSecValueData as String] = Data(trimmed.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw MapofAgentsPairingTokenVault.VaultError.saveFailed(addStatus)
        }
        #else
        throw MapofAgentsPairingTokenVault.VaultError.unavailable
        #endif
    }

    public func loadRefreshCredential(hostID: HostID, deviceID: String) throws -> String? {
        #if canImport(Security)
        var query = baseQuery(hostID: hostID, deviceID: deviceID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let credential = String(data: data, encoding: .utf8),
              !credential.isEmpty else {
            throw MapofAgentsPairingTokenVault.VaultError.loadFailed(status)
        }
        return credential
        #else
        throw MapofAgentsPairingTokenVault.VaultError.unavailable
        #endif
    }

    public func deleteRefreshCredential(hostID: HostID, deviceID: String) throws {
        #if canImport(Security)
        let status = SecItemDelete(baseQuery(hostID: hostID, deviceID: deviceID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MapofAgentsPairingTokenVault.VaultError.deleteFailed(status)
        }
        #else
        throw MapofAgentsPairingTokenVault.VaultError.unavailable
        #endif
    }

    static func credentialReference(hostID: HostID, deviceID: String) -> String {
        Data("\(hostID.rawValue)\u{0}\(deviceID)".utf8).base64EncodedString()
    }

    #if canImport(Security)
    private func baseQuery(hostID: HostID, deviceID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.credentialReference(hostID: hostID, deviceID: deviceID),
        ]
    }
    #endif
}

public enum MapofAgentsPairingTokenVault {
    private static let service = "dev.mapofagents.pairing-token"

    public enum VaultError: LocalizedError, Sendable {
        case missingToken
        case unavailable
        case saveFailed(Int32)
        case loadFailed(Int32)
        case deleteFailed(Int32)

        public var errorDescription: String? {
            switch self {
            case .missingToken:
                return "The paired Mac token is empty and could not be saved securely."
            case .unavailable:
                return "Secure token storage is not available on this platform."
            case .saveFailed(let status):
                return "The paired Mac token could not be saved to Keychain (OSStatus \(status))."
            case .loadFailed(let status):
                return "The paired Mac credential could not be loaded from Keychain (OSStatus \(status))."
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
