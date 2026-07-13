import Foundation
@testable import MapofAgentsCore

final class TestRelayCredentialVault: @unchecked Sendable, AppServerRelayCredentialVault {
    private let lock = NSLock()
    private var credentials: [String: String] = [:]
    private var deleteFailures: Set<String> = []

    func save(_ credential: String, reference: String) throws {
        lock.lock()
        defer { lock.unlock() }
        credentials[reference] = credential
    }

    func load(reference: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return credentials[reference]
    }

    func delete(reference: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if deleteFailures.remove(reference) != nil {
            throw TestRelayCredentialVaultError.injectedDeleteFailure
        }
        credentials.removeValue(forKey: reference)
    }

    func credential(for reference: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return credentials[reference]
    }

    func failNextDelete(reference: String) {
        lock.lock()
        defer { lock.unlock() }
        deleteFailures.insert(reference)
    }
}

private enum TestRelayCredentialVaultError: Error {
    case injectedDeleteFailure
}
