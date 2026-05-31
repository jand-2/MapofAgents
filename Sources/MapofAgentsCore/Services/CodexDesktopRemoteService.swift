import Foundation

public struct CodexDesktopRemote: Codable, Identifiable, Hashable, Sendable {
    public var id: HostID
    public var displayName: String
    public var hostID: String
    public var hostname: String?
    public var identityPath: String?
    public var sshPort: Int?
    public var source: String

    public init(
        id: HostID,
        displayName: String,
        hostID: String,
        hostname: String? = nil,
        identityPath: String? = nil,
        sshPort: Int? = nil,
        source: String
    ) {
        self.id = id
        self.displayName = displayName
        self.hostID = hostID
        self.hostname = hostname
        self.identityPath = identityPath
        self.sshPort = sshPort
        self.source = source
    }

    public var platform: HostPlatform {
        SupervisorHostPlatformResolver.platform(from: displayName)
    }

    public var isConnectable: Bool {
        hostname?.isEmpty == false
    }
}

public enum CodexDesktopRemoteError: LocalizedError, Sendable {
    case stateNotFound
    case invalidState
    case unsupportedPlatform

    public var errorDescription: String? {
        switch self {
        case .stateNotFound:
            return "Codex Desktop remote state was not found."
        case .invalidState:
            return "Codex Desktop remote state could not be read."
        case .unsupportedPlatform:
            return "Codex Desktop remote discovery is only available on macOS in this build."
        }
    }
}

public enum CodexDesktopRemoteService {
    public static func discover() async throws -> [CodexDesktopRemote] {
        try await Task.detached(priority: .utility) {
            try discoverFromDefaultState()
        }.value
    }

    public static func remotes(from data: Data) throws -> [CodexDesktopRemote] {
        let state = try JSONDecoder().decode(CodexDesktopState.self, from: data)
        return (state.managedRemoteConnections ?? [])
            .compactMap(remote(from:))
            .sorted { lhs, rhs in
                if lhs.isConnectable != rhs.isConnectable {
                    return lhs.isConnectable && !rhs.isConnectable
                }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    public static func isValidSSHTarget(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed == value,
              !trimmed.hasPrefix("-"),
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              trimmed.rangeOfCharacter(from: .controlCharacters) == nil,
              !trimmed.contains("/"),
              !trimmed.contains("\\") else {
            return false
        }

        let parts = trimmed.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        let user: Substring?
        let host: Substring
        if parts.count == 2 {
            user = parts[0]
            host = parts[1]
        } else {
            user = nil
            host = parts[0]
        }

        if let user {
            guard !user.isEmpty, user.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }) else {
                return false
            }
        }

        guard !host.isEmpty else {
            return false
        }

        let allowedHostCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-:[]_%"))
        return host.unicodeScalars.allSatisfy { allowedHostCharacters.contains($0) }
    }

    private static func remote(from connection: CodexDesktopManagedRemoteConnection) -> CodexDesktopRemote? {
        guard let hostID = connection.hostID?.nilIfEmpty else {
            return nil
        }

        let displayName = connection.displayName?.nilIfEmpty
            ?? connection.alias?.nilIfEmpty
            ?? connection.hostname?.nilIfEmpty
            ?? hostID

        return CodexDesktopRemote(
            id: HostID(rawValue: machineID(from: hostID)),
            displayName: displayName,
            hostID: hostID,
            hostname: validatedHostname(connection.hostname),
            identityPath: connection.identity?.nilIfEmpty,
            sshPort: connection.sshPort,
            source: connection.source ?? "codex-desktop"
        )
    }

    private static func validatedHostname(_ hostname: String?) -> String? {
        guard let hostname = hostname?.nilIfEmpty else {
            return nil
        }
        return isValidSSHTarget(hostname) ? hostname : nil
    }

    private static func discoverFromDefaultState() throws -> [CodexDesktopRemote] {
        #if os(macOS)
        let stateURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/.codex-global-state.json")
        guard FileManager.default.fileExists(atPath: stateURL.path) else {
            throw CodexDesktopRemoteError.stateNotFound
        }

        do {
            let data = try Data(contentsOf: stateURL)
            return try remotes(from: data)
        } catch {
            throw CodexDesktopRemoteError.invalidState
        }
        #else
        throw CodexDesktopRemoteError.unsupportedPlatform
        #endif
    }

    private static func machineID(from raw: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let compact = raw.lowercased().unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        return "codex-remote-\(String(compact).trimmingCharacters(in: CharacterSet(charactersIn: "-")))"
    }
}

private struct CodexDesktopState: Decodable {
    var managedRemoteConnections: [CodexDesktopManagedRemoteConnection]?

    enum CodingKeys: String, CodingKey {
        case managedRemoteConnections = "codex-managed-remote-connections"
    }
}

private struct CodexDesktopManagedRemoteConnection: Decodable {
    var alias: String?
    var displayName: String?
    var hostID: String?
    var hostname: String?
    var identity: String?
    var source: String?
    var sshPort: Int?

    enum CodingKeys: String, CodingKey {
        case alias
        case displayName
        case hostID = "hostId"
        case hostname
        case identity
        case source
        case sshPort
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
