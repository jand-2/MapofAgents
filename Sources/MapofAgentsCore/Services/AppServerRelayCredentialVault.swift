import Foundation

#if canImport(Security)
import Security
#endif

public protocol AppServerRelayCredentialVault: Sendable {
    func save(_ credential: String, reference: String) throws
    func load(reference: String) throws -> String?
    func delete(reference: String) throws
}

public enum AppServerRelayCredentialVaultError: LocalizedError, Sendable {
    case emptyCredential
    case conflictingCredentials(String)
    case unavailable
    case saveFailed(Int32)
    case loadFailed(Int32)
    case deleteFailed(Int32)
    case transactionRollbackFailed(String)

    public var errorDescription: String? {
        switch self {
        case .emptyCredential:
            return "The App Server credential is empty and cannot be stored."
        case .conflictingCredentials(let reference):
            return "Multiple App Server credentials were provided for the same secure reference '\(reference)'."
        case .unavailable:
            return "Secure App Server credential storage is unavailable on this platform."
        case .saveFailed(let status):
            return "The App Server credential could not be saved to Keychain (OSStatus \(status))."
        case .loadFailed(let status):
            return "The App Server credential could not be loaded from Keychain (OSStatus \(status))."
        case .deleteFailed(let status):
            return "The App Server credential could not be removed from Keychain (OSStatus \(status))."
        case .transactionRollbackFailed(let message):
            return "The App Server credential transaction could not be rolled back safely: \(message)"
        }
    }
}

public struct KeychainAppServerRelayCredentialVault: AppServerRelayCredentialVault {
    private static let service = "dev.mapofagents.app-server-relay"

    public init() {}

    public func save(_ credential: String, reference: String) throws {
        let trimmed = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppServerRelayCredentialVaultError.emptyCredential
        }

        #if canImport(Security)
        let query = baseQuery(reference: reference)
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let update: [String: Any] = [
                kSecValueData as String: Data(trimmed.utf8),
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw AppServerRelayCredentialVaultError.saveFailed(updateStatus)
            }
            return
        }
        guard status == errSecItemNotFound else {
            throw AppServerRelayCredentialVaultError.saveFailed(status)
        }

        var attributes = query
        attributes[kSecValueData as String] = Data(trimmed.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AppServerRelayCredentialVaultError.saveFailed(addStatus)
        }
        #else
        throw AppServerRelayCredentialVaultError.unavailable
        #endif
    }

    public func load(reference: String) throws -> String? {
        #if canImport(Security)
        var query = baseQuery(reference: reference)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let credential = String(data: data, encoding: .utf8),
              !credential.isEmpty else {
            throw AppServerRelayCredentialVaultError.loadFailed(status)
        }
        return credential
        #else
        throw AppServerRelayCredentialVaultError.unavailable
        #endif
    }

    public func delete(reference: String) throws {
        #if canImport(Security)
        let status = SecItemDelete(baseQuery(reference: reference) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppServerRelayCredentialVaultError.deleteFailed(status)
        }
        #else
        throw AppServerRelayCredentialVaultError.unavailable
        #endif
    }

    #if canImport(Security)
    private func baseQuery(reference: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: reference,
        ]
    }
    #endif
}
