import Foundation

public struct TailnetMachine: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var dnsName: String?
    public var addresses: [String]
    public var platform: HostPlatform
    public var isOnline: Bool
    public var lastSeenAt: Date?

    public init(
        id: String,
        name: String,
        dnsName: String? = nil,
        addresses: [String] = [],
        platform: HostPlatform = .unknown,
        isOnline: Bool = false,
        lastSeenAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.dnsName = dnsName
        self.addresses = addresses
        self.platform = platform
        self.isOnline = isOnline
        self.lastSeenAt = lastSeenAt
    }

    public var displayAddress: String {
        dnsName ?? addresses.first ?? "tailnet"
    }

    public func suggestedWebSocketEndpoint(port: Int = 18_945) -> String? {
        guard let host = dnsName ?? addresses.first else {
            return nil
        }

        let formattedHost = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        let scheme = dnsName != nil ? "wss" : "ws"
        return "\(scheme)://\(formattedHost):\(port)"
    }
}

public enum TailnetDiscoveryError: LocalizedError, Sendable {
    case tailscaleNotFound
    case commandFailed(String)
    case invalidOutput
    case unsupportedPlatform

    public var errorDescription: String? {
        switch self {
        case .tailscaleNotFound:
            return "Tailscale CLI not found."
        case .commandFailed(let message):
            return message.isEmpty ? "Tailscale discovery failed." : message
        case .invalidOutput:
            return "Tailscale returned an unreadable status response."
        case .unsupportedPlatform:
            return "Tailnet discovery is only available on macOS in this build."
        }
    }
}

public enum TailnetDiscoveryService {
    public static func discover() async throws -> [TailnetMachine] {
        try await Task.detached(priority: .utility) {
            try await runStatus()
        }.value
    }

    public static func machines(from data: Data) throws -> [TailnetMachine] {
        let status = try JSONDecoder().decode(TailscaleStatus.self, from: data)
        return (status.peers ?? [:]).compactMap { key, peer in
            machine(from: peer, fallbackID: key)
        }
        .sorted { lhs, rhs in
            if lhs.isOnline != rhs.isOnline {
                return lhs.isOnline && !rhs.isOnline
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func machine(from peer: TailscalePeer, fallbackID: String) -> TailnetMachine? {
        let dnsName = peer.dnsName?.trimmedTailnetDNSName
        let name = peer.hostName?.nilIfEmpty
            ?? dnsName
            ?? peer.tailscaleIPs?.first
            ?? fallbackID

        guard !name.isEmpty else {
            return nil
        }

        return TailnetMachine(
            id: machineID(from: peer.id ?? peer.publicKey ?? dnsName ?? fallbackID),
            name: name,
            dnsName: dnsName,
            addresses: peer.tailscaleIPs ?? [],
            platform: SupervisorHostPlatformResolver.platform(from: peer.os),
            isOnline: peer.online ?? peer.active ?? false,
            lastSeenAt: peer.lastSeen.flatMap(parseDate)
        )
    }

    private static func machineID(from raw: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let compact = raw.lowercased().unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        return "tailnet-\(String(compact).trimmingCharacters(in: CharacterSet(charactersIn: "-")))"
    }

    private static func parseDate(_ value: String) -> Date? {
        guard !value.hasPrefix("0001-01-01") else {
            return nil
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }

    private static func runStatus() async throws -> [TailnetMachine] {
        #if os(macOS)
        guard let executableURL = tailscaleExecutableURL() else {
            throw TailnetDiscoveryError.tailscaleNotFound
        }

        do {
            let result = try await BoundedProcessRunner.run(
                executableURL: executableURL,
                arguments: ["status", "--json"],
                timeout: 8
            )

            guard result.terminationStatus == 0 else {
                throw TailnetDiscoveryError.commandFailed(
                    result.stderr.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }

            return try machines(from: result.stdout.data)
        } catch {
            if error is TailnetDiscoveryError {
                throw error
            }
            throw TailnetDiscoveryError.commandFailed(error.localizedDescription)
        }
        #else
        throw TailnetDiscoveryError.unsupportedPlatform
        #endif
    }

    #if os(macOS)
    private static func tailscaleExecutableURL() -> URL? {
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let candidates = pathEntries.map { "\($0)/tailscale" } + [
            "/opt/homebrew/bin/tailscale",
            "/usr/local/bin/tailscale",
            "/usr/bin/tailscale",
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        ]

        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
    #endif

}

private struct TailscaleStatus: Decodable {
    var peers: [String: TailscalePeer]?

    enum CodingKeys: String, CodingKey {
        case peers = "Peer"
    }
}

private struct TailscalePeer: Decodable {
    var id: String?
    var publicKey: String?
    var hostName: String?
    var dnsName: String?
    var os: String?
    var tailscaleIPs: [String]?
    var online: Bool?
    var active: Bool?
    var lastSeen: String?

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case publicKey = "PublicKey"
        case hostName = "HostName"
        case dnsName = "DNSName"
        case os = "OS"
        case tailscaleIPs = "TailscaleIPs"
        case online = "Online"
        case active = "Active"
        case lastSeen = "LastSeen"
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var trimmedTailnetDNSName: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return trimmed.isEmpty ? nil : trimmed
    }
}
