import CryptoKit
import Foundation

#if os(macOS)
import Darwin
#endif

public enum MapofAgentsPairingError: LocalizedError, Sendable {
    case invalidPairingCode
    case missingEndpoint
    case missingExpiration
    case expired
    case unsupportedPlatform
    case codexNotInstalled
    case tailscaleNotInstalled
    case tailscaleStatusUnavailable(String)
    case tailscaleServeFailed(String)
    case missingSecureTailnetEndpoint
    case hostServerStartFailed(String)
    case cleartextIPAddressEndpointRequiresDNSName
    case insecureRemoteEndpointRequiresTLS

    public var errorDescription: String? {
        switch self {
        case .invalidPairingCode:
            return "This mapofagents pairing code is not valid."
        case .missingEndpoint:
            return "The pairing code does not include a usable endpoint."
        case .missingExpiration:
            return "This mapofagents pairing code is missing its expiration time."
        case .expired:
            return "This mapofagents pairing code has expired."
        case .unsupportedPlatform:
            return "Pairing host generation is only available on macOS."
        case .codexNotInstalled:
            return "Could not find the codex executable needed to host iPhone pairing."
        case .tailscaleNotInstalled:
            return "Could not find the Tailscale command needed to create a private secure iPhone route."
        case .tailscaleStatusUnavailable(let message):
            return "Could not read this Mac's Tailscale MagicDNS identity: \(message)"
        case .tailscaleServeFailed(let message):
            return "Could not configure private Tailscale Serve TLS termination: \(message)"
        case .missingSecureTailnetEndpoint:
            return "This Mac does not have a usable Tailscale MagicDNS HTTPS identity. Enable MagicDNS and HTTPS certificates for the tailnet, then try again."
        case .hostServerStartFailed(let message):
            return "Could not start the mapofagents Mac host server: \(message)"
        case .cleartextIPAddressEndpointRequiresDNSName:
            return "This pairing only has cleartext IP endpoints. Pair again using a secure Tailscale Serve MagicDNS endpoint."
        case .insecureRemoteEndpointRequiresTLS:
            return "This pairing uses an insecure remote websocket endpoint. Use `wss://` for remote pairings."
        }
    }
}

public enum MapofAgentsPairingEndpointKind: String, Codable, CaseIterable, Sendable {
    case tailnet
    case local
    case manual
}

public struct MapofAgentsPairingEndpoint: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var kind: MapofAgentsPairingEndpointKind
    public var url: URL
    public var label: String

    public init(
        id: String = UUID().uuidString,
        kind: MapofAgentsPairingEndpointKind,
        url: URL,
        label: String
    ) {
        self.id = id
        self.kind = kind
        self.url = url
        self.label = label
    }

    public var connectionPriority: Int {
        MapofAgentsEndpointOrdering.priority(for: self)
    }

    public var isIPhoneCompanionConnectable: Bool {
        Self.isSecureIPhoneCompanionEndpoint(url)
    }

    public static func isCleartextIPAddressEndpoint(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "ws",
              let host = url.host?.trimmingCharacters(in: CharacterSet(charactersIn: "[]")),
              !host.isEmpty
        else {
            return false
        }
        return isIPv4Address(host) || host.contains(":")
    }

    public static func isSecureIPhoneCompanionEndpoint(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host?.trimmingCharacters(in: CharacterSet(charactersIn: "[]")),
              !host.isEmpty else {
            return false
        }

        if scheme == "wss" {
            return true
        }

        if scheme != "ws" {
            return false
        }

        return isLoopbackHost(host)
    }

    private static func isIPv4Address(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let value = Int(part), (0...255).contains(value) else {
                return false
            }
            let text = String(part)
            return String(value) == text || text == "0"
        }
    }

    private static func isLoopbackHost(_ host: String) -> Bool {
        let normalized = host.lowercased()
        return normalized == "localhost" || normalized == "127.0.0.1" || normalized == "::1"
    }
}

public struct MapofAgentsPairingPayload: Codable, Hashable, Sendable {
    public static let urlScheme = "mapofagents"
    public static let urlHost = "pair"
    public static let currentVersion = 2

    public var version: Int
    public var hostID: HostID
    public var name: String
    public var endpoints: [MapofAgentsPairingEndpoint]
    public var bearerToken: String
    public var enrollmentToken: String?
    public var credentialExchangeURL: URL?
    public var createdAt: Date
    public var expiresAt: Date?
    public var mapofagentsSupportDirectory: String?

    public init(
        version: Int = Self.currentVersion,
        hostID: HostID,
        name: String,
        endpoints: [MapofAgentsPairingEndpoint],
        bearerToken: String = "",
        enrollmentToken: String? = nil,
        credentialExchangeURL: URL? = nil,
        createdAt: Date = Date(),
        expiresAt: Date? = Date().addingTimeInterval(30 * 60),
        mapofagentsSupportDirectory: String? = nil
    ) {
        self.version = version
        self.hostID = hostID
        self.name = name
        self.endpoints = endpoints
        self.bearerToken = bearerToken
        self.enrollmentToken = enrollmentToken?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.credentialExchangeURL = credentialExchangeURL
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.mapofagentsSupportDirectory = mapofagentsSupportDirectory?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt < Date()
    }

    public func validateForImport() throws {
        guard expiresAt != nil else {
            throw MapofAgentsPairingError.missingExpiration
        }
        guard !isExpired else {
            throw MapofAgentsPairingError.expired
        }
        guard !endpoints.isEmpty else {
            throw MapofAgentsPairingError.missingEndpoint
        }
        guard endpoints.allSatisfy(\.isIPhoneCompanionConnectable) else {
            throw MapofAgentsPairingError.missingEndpoint
        }
        if version >= Self.currentVersion {
            guard bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  enrollmentToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  let credentialExchangeURL,
                  Self.isSecureCredentialExchangeURL(credentialExchangeURL),
                  Self.exchangeHostMatchesTailnetEndpoint(
                      credentialExchangeURL,
                      endpoints: endpoints
                  ) else {
                throw MapofAgentsPairingError.invalidPairingCode
            }
        } else {
            guard !bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MapofAgentsPairingError.invalidPairingCode
            }
        }
    }

    public var preferredEndpoints: [MapofAgentsPairingEndpoint] {
        MapofAgentsEndpointOrdering.preferredEndpoints(endpoints)
    }

    public func pairingURL() throws -> URL {
        guard !endpoints.isEmpty,
              endpoints.allSatisfy(\.isIPhoneCompanionConnectable) else {
            throw MapofAgentsPairingError.missingEndpoint
        }
        if version >= Self.currentVersion {
            guard bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  enrollmentToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                  let credentialExchangeURL,
                  Self.isSecureCredentialExchangeURL(credentialExchangeURL),
                  Self.exchangeHostMatchesTailnetEndpoint(
                      credentialExchangeURL,
                      endpoints: endpoints
                  ) else {
                throw MapofAgentsPairingError.invalidPairingCode
            }
        } else if bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw MapofAgentsPairingError.invalidPairingCode
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(self)
        let payload = data.base64URLEncodedString()
        var components = URLComponents()
        components.scheme = Self.urlScheme
        components.host = Self.urlHost
        components.queryItems = [
            URLQueryItem(name: "payload", value: payload),
        ]
        guard let url = components.url else {
            throw MapofAgentsPairingError.invalidPairingCode
        }
        return url
    }

    public static func decode(from string: String) throws -> MapofAgentsPairingPayload {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed),
           url.scheme == Self.urlScheme || trimmed.contains("payload=") {
            return try decode(from: url)
        }

        guard let data = Data(base64URLEncoded: trimmed) else {
            throw MapofAgentsPairingError.invalidPairingCode
        }
        return try decode(from: data)
    }

    public static func decode(from url: URL) throws -> MapofAgentsPairingPayload {
        guard url.scheme == Self.urlScheme,
              url.host == Self.urlHost,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let payload = components.queryItems?.first(where: { $0.name == "payload" })?.value,
              let data = Data(base64URLEncoded: payload) else {
            throw MapofAgentsPairingError.invalidPairingCode
        }
        return try decode(from: data)
    }

    private static func decode(from data: Data) throws -> MapofAgentsPairingPayload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .mapofagentsFlexibleISO8601
        let payload = try decoder.decode(MapofAgentsPairingPayload.self, from: data)
        guard !payload.endpoints.isEmpty else {
            throw MapofAgentsPairingError.missingEndpoint
        }
        return payload
    }

    public static func isSecureCredentialExchangeURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              isCertificateEligibleTailnetHost(host),
              url.port == MapofAgentsMacPairingService.defaultCredentialExchangeHTTPSPort,
              url.path == "/v1/pairing",
              url.query == nil,
              url.fragment == nil,
              url.user == nil,
              url.password == nil else {
            return false
        }
        return true
    }

    private static func exchangeHostMatchesTailnetEndpoint(
        _ exchangeURL: URL,
        endpoints: [MapofAgentsPairingEndpoint]
    ) -> Bool {
        guard let exchangeHost = exchangeURL.host?.lowercased() else { return false }
        return endpoints.contains { endpoint in
            endpoint.kind == .tailnet
                && endpoint.url.scheme?.lowercased() == "wss"
                && endpoint.url.host?.lowercased() == exchangeHost
        }
    }

    private static func isCertificateEligibleTailnetHost(_ value: String) -> Bool {
        guard value.hasSuffix(".ts.net"), !value.contains("..") else {
            return false
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        return value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            guard let first = label.unicodeScalars.first,
                  let last = label.unicodeScalars.last,
                  first != "-",
                  last != "-" else {
                return false
            }
            return label.unicodeScalars.allSatisfy(allowed.contains)
        }
    }

}

public struct MapofAgentsPairingEndpointFailure: Codable, Hashable, Sendable {
    public var message: String
    public var timestamp: Date

    public init(message: String, timestamp: Date = Date()) {
        self.message = message
        self.timestamp = timestamp
    }
}

public struct MapofAgentsPairedHost: Codable, Hashable, Identifiable, Sendable {
    public static let currentPersistenceVersion = 3

    public var version: Int
    public var id: HostID
    public var name: String
    public var endpoints: [MapofAgentsPairingEndpoint]
    public var bearerToken: String
    public var credentialExchangeURL: URL?
    public var deviceID: String?
    public var pairedAt: Date
    public var mapofagentsSupportDirectory: String?
    public var lastSuccessfulEndpointID: String?
    public var lastSuccessfulEndpointURL: URL?
    public var lastConnectedAt: Date?
    public var endpointFailures: [String: MapofAgentsPairingEndpointFailure]

    public var persistenceVersion: Int {
        get { version }
        set { version = newValue }
    }

    public init(
        version: Int = Self.currentPersistenceVersion,
        id: HostID,
        name: String,
        endpoints: [MapofAgentsPairingEndpoint],
        bearerToken: String,
        credentialExchangeURL: URL? = nil,
        deviceID: String? = nil,
        pairedAt: Date = Date(),
        mapofagentsSupportDirectory: String? = nil,
        lastSuccessfulEndpointID: String? = nil,
        lastSuccessfulEndpointURL: URL? = nil,
        lastConnectedAt: Date? = nil,
        endpointFailures: [String: MapofAgentsPairingEndpointFailure] = [:]
    ) {
        self.version = version
        self.id = id
        self.name = name
        self.endpoints = endpoints
        self.bearerToken = bearerToken
        self.credentialExchangeURL = credentialExchangeURL
        self.deviceID = deviceID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.pairedAt = pairedAt
        self.mapofagentsSupportDirectory = mapofagentsSupportDirectory?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.lastSuccessfulEndpointID = lastSuccessfulEndpointID?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.lastSuccessfulEndpointURL = lastSuccessfulEndpointURL
        self.lastConnectedAt = lastConnectedAt
        self.endpointFailures = endpointFailures
    }

    public init(payload: MapofAgentsPairingPayload) {
        self.init(
            id: payload.hostID,
            name: payload.name,
            endpoints: payload.endpoints,
            bearerToken: payload.bearerToken,
            credentialExchangeURL: payload.credentialExchangeURL,
            mapofagentsSupportDirectory: payload.mapofagentsSupportDirectory
        )
    }

    public var preferredEndpoints: [MapofAgentsPairingEndpoint] {
        MapofAgentsEndpointOrdering.preferredEndpoints(
            endpoints,
            lastSuccessfulEndpointID: lastSuccessfulEndpointID,
            lastSuccessfulEndpointURL: lastSuccessfulEndpointURL
        )
    }

    public func isLastSuccessfulEndpoint(_ endpoint: MapofAgentsPairingEndpoint) -> Bool {
        MapofAgentsEndpointOrdering.isLastSuccessfulEndpoint(
            endpoint,
            lastSuccessfulEndpointID: lastSuccessfulEndpointID,
            lastSuccessfulEndpointURL: lastSuccessfulEndpointURL
        )
    }

    public func failure(for endpoint: MapofAgentsPairingEndpoint) -> MapofAgentsPairingEndpointFailure? {
        endpointFailures[endpoint.id]
    }

    public mutating func recordSuccessfulConnection(
        to endpoint: MapofAgentsPairingEndpoint,
        at date: Date = Date()
    ) {
        lastSuccessfulEndpointID = endpoint.id
        lastSuccessfulEndpointURL = endpoint.url
        lastConnectedAt = date
        endpointFailures[endpoint.id] = nil
    }

    public mutating func recordConnectionFailure(
        to endpoint: MapofAgentsPairingEndpoint,
        message: String,
        at date: Date = Date()
    ) {
        endpointFailures[endpoint.id] = MapofAgentsPairingEndpointFailure(message: message, timestamp: date)
    }

    public func encodedString() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self).base64URLEncodedString()
    }

    public static func decode(from string: String) throws -> MapofAgentsPairedHost {
        guard let data = Data(base64URLEncoded: string.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw MapofAgentsPairingError.invalidPairingCode
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .mapofagentsFlexibleISO8601
        let host = try decoder.decode(MapofAgentsPairedHost.self, from: data)
        guard !host.endpoints.isEmpty else {
            throw MapofAgentsPairingError.missingEndpoint
        }
        return host
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case persistenceVersion
        case id
        case name
        case endpoints
        case bearerToken
        case credentialExchangeURL
        case deviceID
        case pairedAt
        case mapofagentsSupportDirectory
        case lastSuccessfulEndpointID
        case lastSuccessfulEndpointURL
        case lastConnectedAt
        case endpointFailures
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try container.decodeIfPresent(Int.self, forKey: .version)
                ?? container.decodeIfPresent(Int.self, forKey: .persistenceVersion)
                ?? 1,
            id: try container.decode(HostID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            endpoints: try container.decode([MapofAgentsPairingEndpoint].self, forKey: .endpoints),
            bearerToken: try container.decodeIfPresent(String.self, forKey: .bearerToken) ?? "",
            credentialExchangeURL: try container.decodeIfPresent(URL.self, forKey: .credentialExchangeURL),
            deviceID: try container.decodeIfPresent(String.self, forKey: .deviceID),
            pairedAt: try container.decode(Date.self, forKey: .pairedAt),
            mapofagentsSupportDirectory: try container.decodeIfPresent(String.self, forKey: .mapofagentsSupportDirectory),
            lastSuccessfulEndpointID: try container.decodeIfPresent(String.self, forKey: .lastSuccessfulEndpointID),
            lastSuccessfulEndpointURL: try container.decodeIfPresent(URL.self, forKey: .lastSuccessfulEndpointURL),
            lastConnectedAt: try container.decodeIfPresent(Date.self, forKey: .lastConnectedAt),
            endpointFailures: try container.decodeIfPresent(
                [String: MapofAgentsPairingEndpointFailure].self,
                forKey: .endpointFailures
            ) ?? [:]
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(endpoints, forKey: .endpoints)
        // Access tokens are decode-only for legacy migration and process-memory only.
        // Paired-host records contain routing and device identity, never secrets.
        try container.encodeIfPresent(credentialExchangeURL, forKey: .credentialExchangeURL)
        try container.encodeIfPresent(deviceID, forKey: .deviceID)
        try container.encode(pairedAt, forKey: .pairedAt)
        try container.encodeIfPresent(mapofagentsSupportDirectory, forKey: .mapofagentsSupportDirectory)
        try container.encodeIfPresent(lastSuccessfulEndpointID, forKey: .lastSuccessfulEndpointID)
        try container.encodeIfPresent(lastSuccessfulEndpointURL, forKey: .lastSuccessfulEndpointURL)
        try container.encodeIfPresent(lastConnectedAt, forKey: .lastConnectedAt)
        if !endpointFailures.isEmpty {
            try container.encode(endpointFailures, forKey: .endpointFailures)
        }
    }
}

private enum MapofAgentsEndpointOrdering {
    static func preferredEndpoints(
        _ endpoints: [MapofAgentsPairingEndpoint],
        lastSuccessfulEndpointID: String? = nil,
        lastSuccessfulEndpointURL: URL? = nil
    ) -> [MapofAgentsPairingEndpoint] {
        endpoints.enumerated()
            .sorted { lhs, rhs in
                let lhsLastGood = isLastSuccessfulEndpoint(
                    lhs.element,
                    lastSuccessfulEndpointID: lastSuccessfulEndpointID,
                    lastSuccessfulEndpointURL: lastSuccessfulEndpointURL
                ) ? 0 : 1
                let rhsLastGood = isLastSuccessfulEndpoint(
                    rhs.element,
                    lastSuccessfulEndpointID: lastSuccessfulEndpointID,
                    lastSuccessfulEndpointURL: lastSuccessfulEndpointURL
                ) ? 0 : 1

                if lhsLastGood != rhsLastGood {
                    return lhsLastGood < rhsLastGood
                }

                let lhsPriority = priority(for: lhs.element)
                let rhsPriority = priority(for: rhs.element)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }

                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    static func priority(for endpoint: MapofAgentsPairingEndpoint) -> Int {
        switch endpoint.kind {
        case .tailnet:
            return 0
        case .local:
            return isLocalBonjourEndpoint(endpoint) ? 1 : 2
        case .manual:
            return 2
        }
    }

    static func isLastSuccessfulEndpoint(
        _ endpoint: MapofAgentsPairingEndpoint,
        lastSuccessfulEndpointID: String?,
        lastSuccessfulEndpointURL: URL?
    ) -> Bool {
        if let lastSuccessfulEndpointID,
           !lastSuccessfulEndpointID.isEmpty,
           endpoint.id == lastSuccessfulEndpointID {
            return true
        }

        if let lastSuccessfulEndpointURL,
           endpoint.url.absoluteString == lastSuccessfulEndpointURL.absoluteString {
            return true
        }

        return false
    }

    private static func isLocalBonjourEndpoint(_ endpoint: MapofAgentsPairingEndpoint) -> Bool {
        guard endpoint.kind == .local else { return false }
        let host = endpoint.url.host ?? endpoint.label
        return host
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
            .hasSuffix(".local")
    }
}

public enum MapofAgentsMacPairingService {
    public static let defaultPort = 18_945
    public static let defaultCredentialExchangePort: UInt16 = 18_946
    public static let defaultPairingGatewayPort: UInt16 = 18_947
    public static let defaultCredentialExchangeHTTPSPort = 8_443
    public static let pairingSessionDuration: TimeInterval = 30 * 60
    private static let signedBearerIssuer = "mapofagents"
    private static let signedBearerAudience = "codex-app-server"
    private static let signedBearerSubject = "mapofagents-pairing"
    private static let signedBearerClockSkewSeconds = 5

    #if os(macOS)
    struct CommandEnvironment: Sendable {
        var codexExecutableURL: @Sendable () -> URL?
        var tailscaleExecutableURL: @Sendable () -> URL?
        var run: @Sendable (URL, [String]) throws -> BoundedProcessResult
        var ensureForegroundServe: @Sendable (URL, [String], String) throws -> Void
        var stopForegroundServes: @Sendable () -> Void

        init(
            codexExecutableURL: @escaping @Sendable () -> URL?,
            tailscaleExecutableURL: @escaping @Sendable () -> URL?,
            run: @escaping @Sendable (URL, [String]) throws -> BoundedProcessResult,
            ensureForegroundServe: (@Sendable (URL, [String], String) throws -> Void)? = nil,
            stopForegroundServes: (@Sendable () -> Void)? = nil
        ) {
            self.codexExecutableURL = codexExecutableURL
            self.tailscaleExecutableURL = tailscaleExecutableURL
            self.run = run
            self.ensureForegroundServe = ensureForegroundServe ?? { executableURL, arguments, _ in
                let result = try run(executableURL, arguments)
                guard result.terminationStatus == 0 else {
                    throw MapofAgentsPairingError.tailscaleServeFailed(
                        commandDiagnostic(
                            result,
                            fallback: "Tailscale Serve exited with status \(result.terminationStatus)."
                        )
                    )
                }
            }
            self.stopForegroundServes = stopForegroundServes ?? {}
        }

        static let live = CommandEnvironment(
            codexExecutableURL: {
                LocalCodexDiscovery.findCodexExecutable().map(URL.init(fileURLWithPath:))
            },
            tailscaleExecutableURL: {
                discoverTailscaleExecutableURL()
            },
            run: { executableURL, arguments in
                try BoundedProcessRunner.runBlocking(
                    executableURL: executableURL,
                    arguments: arguments,
                    timeout: 8
                )
            },
            ensureForegroundServe: { executableURL, arguments, key in
                try MapofAgentsTailnetServeRegistry.ensureRoute(
                    key: key,
                    executableURL: executableURL,
                    arguments: arguments
                )
            },
            stopForegroundServes: {
                MapofAgentsTailnetServeRegistry.stopAll()
            }
        )
    }

    private actor HostOperationLock {
        private var isLocked = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func acquire() async {
            if !isLocked {
                isLocked = true
                return
            }
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        func release() {
            if waiters.isEmpty {
                isLocked = false
            } else {
                waiters.removeFirst().resume()
            }
        }
    }

    private static let hostOperationLock = HostOperationLock()

    private struct HostConfiguration: Sendable {
        var supportDirectory: URL
        var hostID: HostID
        var endpoint: MapofAgentsPairingEndpoint
        var credentialExchangeURL: URL
    }

    public static func ensureHostServerRunning(port: Int = defaultPort) async throws {
        try await withHostOperation {
            _ = try await ensureHostServerRunningUnlocked(
                port: port,
                gatewayPort: defaultPairingGatewayPort,
                credentialExchangePort: defaultCredentialExchangePort,
                credentialExchangeHTTPSPort: defaultCredentialExchangeHTTPSPort,
                commands: .live
            )
        }
    }

    private static func ensureHostServerRunningUnlocked(
        port: Int,
        gatewayPort: UInt16,
        credentialExchangePort: UInt16,
        credentialExchangeHTTPSPort: Int,
        commands: CommandEnvironment
    ) async throws -> HostConfiguration {
        let paths = try ApplicationPaths.defaultPaths()
        let supportDirectory = paths.applicationSupportDirectory
        try migrateLegacyBackgroundRoutesIfNeeded(
            in: supportDirectory,
            commands: commands
        )
        let hostName = localHostName()
        let hostID = try persistentHostID(in: supportDirectory, hostName: hostName)
        let secret = try ensureStableHostSecret(in: supportDirectory)
        let readinessToken = try signedBearerToken(
            secret: secret,
            subject: "mapofagents-host-readiness",
            expiresAt: Date().addingTimeInterval(MapofAgentsCredentialExchangeHandler.accessTokenDuration)
        )

        if !(await isHostServerReady(port: port, supportDirectory: supportDirectory, token: readinessToken)) {
            try? stopHostServer(supportDirectory: supportDirectory, port: port)
            try startHostServer(
                supportDirectory: supportDirectory,
                port: port,
                commands: commands
            )

            var becameReady = false
            for _ in 0..<12 {
                try? await Task.sleep(for: .milliseconds(250))
                if await isHostServerReady(port: port, supportDirectory: supportDirectory, token: readinessToken) {
                    becameReady = true
                    break
                }
            }
            guard becameReady else {
                try? stopHostServer(supportDirectory: supportDirectory, port: port)
                throw MapofAgentsPairingError.hostServerStartFailed(recentLogSnippet(in: supportDirectory))
            }
        }

        let endpoint = try secureTailnetEndpoint(commands: commands)
        let exchangeURL = try credentialExchangeURL(
            endpoint: endpoint,
            httpsPort: credentialExchangeHTTPSPort
        )
        try await MapofAgentsCredentialExchangeRuntime.shared.ensureRunning(
            port: credentialExchangePort,
            registryURL: credentialRegistryURL(in: supportDirectory),
            hostID: hostID,
            sharedSecretURL: sharedSecretURL(in: supportDirectory),
            endpoints: [endpoint],
            supportDirectory: supportDirectory.standardizedFileURL.path
        )
        guard let backendPort = UInt16(exactly: port) else {
            throw MapofAgentsPairingError.hostServerStartFailed("The backend port is outside the valid TCP range.")
        }
        try await MapofAgentsPairingGatewayRuntime.shared.ensureRunning(
            listenPort: gatewayPort,
            backendPort: backendPort,
            sharedSecretURL: sharedSecretURL(in: supportDirectory),
            registryURL: credentialRegistryURL(in: supportDirectory),
            backendIsOwned: {
                isOwnedHostServerRunning(port: port, supportDirectory: supportDirectory)
            },
            onListenerFailure: {
                commands.stopForegroundServes()
            }
        )
        try configureSecureTailnetRoutes(
            appServerPort: Int(gatewayPort),
            credentialExchangePort: credentialExchangePort,
            credentialExchangeHTTPSPort: credentialExchangeHTTPSPort,
            commands: commands
        )
        return HostConfiguration(
            supportDirectory: supportDirectory,
            hostID: hostID,
            endpoint: endpoint,
            credentialExchangeURL: exchangeURL
        )
    }

    public static func beginPairingSession(
        port: Int = defaultPort,
        duration: TimeInterval = pairingSessionDuration
    ) async throws -> MapofAgentsPairingPayload {
        try await withHostOperation {
            try await beginPairingSessionUnlocked(
                port: port,
                gatewayPort: defaultPairingGatewayPort,
                duration: duration,
                credentialExchangePort: defaultCredentialExchangePort,
                credentialExchangeHTTPSPort: defaultCredentialExchangeHTTPSPort,
                commands: .live
            )
        }
    }

    private static func beginPairingSessionUnlocked(
        port: Int,
        gatewayPort: UInt16,
        duration: TimeInterval,
        credentialExchangePort: UInt16,
        credentialExchangeHTTPSPort: Int,
        commands: CommandEnvironment
    ) async throws -> MapofAgentsPairingPayload {
        let configuration = try await ensureHostServerRunningUnlocked(
            port: port,
            gatewayPort: gatewayPort,
            credentialExchangePort: credentialExchangePort,
            credentialExchangeHTTPSPort: credentialExchangeHTTPSPort,
            commands: commands
        )
        let expiresAt = Date().addingTimeInterval(duration)
        let enrollmentToken = try await MapofAgentsCredentialExchangeRuntime.shared.issueEnrollment(
            expiresAt: expiresAt
        )
        return try makePayload(
            enrollmentToken: enrollmentToken,
            credentialExchangeURL: configuration.credentialExchangeURL,
            supportDirectory: configuration.supportDirectory,
            expiresAt: expiresAt,
            endpoints: [configuration.endpoint]
        )
    }

    public static func pairedDevices(
        port: Int = defaultPort
    ) async throws -> [MapofAgentsPairedDeviceSummary] {
        try await withHostOperation {
            if let active = await MapofAgentsCredentialExchangeRuntime.shared.activeDeviceSummariesIfRunning() {
                return active
            }
            let paths = try ApplicationPaths.defaultPaths()
            let registry = try MapofAgentsCredentialRegistry(
                fileURL: credentialRegistryURL(in: paths.applicationSupportDirectory)
            )
            return registry.activeDeviceSummaries()
        }
    }

    public static func revokePairedDevice(
        id deviceID: String,
        port: Int = defaultPort
    ) async throws {
        try await withHostOperation {
            let revokedInRunningExchange = try await MapofAgentsCredentialExchangeRuntime.shared
                .revokeDeviceIfRunning(deviceID: deviceID)
            if !revokedInRunningExchange {
                let paths = try ApplicationPaths.defaultPaths()
                let registry = try MapofAgentsCredentialRegistry(
                    fileURL: credentialRegistryURL(in: paths.applicationSupportDirectory)
                )
                try registry.revokeDevice(deviceID: deviceID)
            }
            await MapofAgentsPairingGatewayRuntime.shared.revoke(deviceID: deviceID)
        }
    }

    public static func hasActivePairedDevices() -> Bool {
        guard let paths = try? ApplicationPaths.defaultPaths() else { return false }
        let registryURL = credentialRegistryURL(in: paths.applicationSupportDirectory)
        guard let data = try? MapofAgentsPrivateFile.read(registryURL, maximumBytes: 1_048_576) else {
            return false
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .mapofagentsFlexibleISO8601
        guard let snapshot = try? decoder.decode(MapofAgentsCredentialRegistrySnapshot.self, from: data) else {
            return false
        }
        return snapshot.devices.contains { $0.revokedAt == nil }
    }

    public static func stopPairingSession(port: Int = defaultPort) async throws {
        try await withHostOperation {
            await MapofAgentsPairingGatewayRuntime.shared.stop()
            await MapofAgentsCredentialExchangeRuntime.shared.stop()
            try terminateHostRuntime(port: port)
        }
    }

    public static func migrateLegacyPersistentRoutesIfNeeded() async throws {
        try await withHostOperation {
            let paths = try ApplicationPaths.defaultPaths()
            try migrateLegacyBackgroundRoutesIfNeeded(
                in: paths.applicationSupportDirectory,
                commands: .live
            )
        }
    }

    static func makePayload(
        enrollmentToken: String,
        credentialExchangeURL: URL,
        supportDirectory: URL,
        expiresAt: Date?,
        endpoints: [MapofAgentsPairingEndpoint]
    ) throws -> MapofAgentsPairingPayload {
        guard !endpoints.isEmpty,
              endpoints.allSatisfy({ endpoint in
                  endpoint.kind == .tailnet
                      && endpoint.url.scheme?.lowercased() == "wss"
                      && endpoint.isIPhoneCompanionConnectable
              }) else {
            throw MapofAgentsPairingError.missingSecureTailnetEndpoint
        }
        let hostName = localHostName()
        let payload = MapofAgentsPairingPayload(
            hostID: try persistentHostID(in: supportDirectory, hostName: hostName),
            name: hostName,
            endpoints: endpoints,
            enrollmentToken: enrollmentToken,
            credentialExchangeURL: credentialExchangeURL,
            expiresAt: expiresAt,
            mapofagentsSupportDirectory: supportDirectory.standardizedFileURL.path
        )
        try payload.validateForImport()
        return payload
    }

    private static func withHostOperation<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        await hostOperationLock.acquire()
        do {
            try Task.checkCancellation()
            let value = try await operation()
            await hostOperationLock.release()
            return value
        } catch {
            await hostOperationLock.release()
            throw error
        }
    }

    static func signedBearerToken(
        secret: String,
        subject: String = signedBearerSubject,
        expiresAt: Date,
        issuedAt: Date = Date()
    ) throws -> String {
        let header: [String: Any] = [
            "alg": "HS256",
            "typ": "JWT",
        ]
        let payload: [String: Any] = [
            "iss": signedBearerIssuer,
            "aud": signedBearerAudience,
            "sub": subject,
            "iat": Int(issuedAt.timeIntervalSince1970),
            "nbf": Int(issuedAt.addingTimeInterval(-Double(signedBearerClockSkewSeconds)).timeIntervalSince1970),
            "exp": Int(ceil(expiresAt.timeIntervalSince1970)),
        ]
        let signingInput = try [
            base64URLJSON(header),
            base64URLJSON(payload),
        ].joined(separator: ".")
        let key = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(signingInput.utf8), using: key)
        return "\(signingInput).\(Data(signature).base64URLEncodedString())"
    }

    static func signedBearerExpiration(_ token: String) -> Date? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let payloadData = Data(base64URLEncoded: String(parts[1])),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            return nil
        }

        if let expiration = payload["exp"] as? NSNumber {
            return Date(timeIntervalSince1970: expiration.doubleValue)
        }
        if let expiration = payload["exp"] as? TimeInterval {
            return Date(timeIntervalSince1970: expiration)
        }
        return nil
    }

    private static func base64URLJSON(_ object: [String: Any]) throws -> String {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            .base64URLEncodedString()
    }

    public static func terminateHostRuntime(port: Int = defaultPort) throws {
        CommandEnvironment.live.stopForegroundServes()
        let paths = try ApplicationPaths.defaultPaths()
        try stopHostServer(supportDirectory: paths.applicationSupportDirectory, port: port)
    }

    private static func sharedSecretURL(in supportDirectory: URL) -> URL {
        supportDirectory.appendingPathComponent("mac-lan-app-server.shared-secret")
    }

    private static func credentialRegistryURL(in supportDirectory: URL) -> URL {
        supportDirectory.appendingPathComponent("pairing-credential-registry.json")
    }

    static func migrateLegacyBackgroundRoutesIfNeeded(
        in supportDirectory: URL,
        commands: CommandEnvironment
    ) throws {
        let markerURL = supportDirectory.appendingPathComponent("foreground-tailscale-serve-v1")
        guard !FileManager.default.fileExists(atPath: markerURL.path) else { return }
        let legacyArtifacts = [
            sharedSecretURL(in: supportDirectory),
            credentialRegistryURL(in: supportDirectory),
            supportDirectory.appendingPathComponent("pairing-host-id.txt"),
        ]
        guard legacyArtifacts.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            try MapofAgentsPrivateFile.write(Data("not-needed\n".utf8), to: markerURL)
            return
        }
        guard let executableURL = commands.tailscaleExecutableURL() else {
            throw MapofAgentsPairingError.tailscaleNotInstalled
        }

        for arguments in Self.legacyBackgroundServeDisableArguments {
            let result = try commands.run(executableURL, arguments)
            guard result.terminationStatus == 0 else {
                throw MapofAgentsPairingError.tailscaleServeFailed(
                    commandDiagnostic(
                        result,
                        fallback: "Could not remove a legacy persistent Tailscale Serve route."
                    )
                )
            }
        }
        try MapofAgentsPrivateFile.write(Data("migrated\n".utf8), to: markerURL)
    }

    static let legacyBackgroundServeDisableArguments: [[String]] = [
        ["serve", "--yes", "--tls-terminated-tcp=443", "off"],
        ["serve", "--yes", "--https=8443", "off"],
    ]

    @discardableResult
    static func ensureStableHostSecret(in supportDirectory: URL) throws -> String {
        let fileURL = sharedSecretURL(in: supportDirectory)
        let legacyPairingTokenURL = supportDirectory.appendingPathComponent("mac-lan-app-server.token")
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        if let data = try? MapofAgentsPrivateFile.read(fileURL, maximumBytes: 4_096),
           let existing = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            try? FileManager.default.removeItem(at: legacyPairingTokenURL)
            return existing
        }

        let secret = MapofAgentsCredentialSecrets.randomCredential()
        try MapofAgentsPrivateFile.write(Data(secret.utf8), to: fileURL)
        try? FileManager.default.removeItem(at: legacyPairingTokenURL)
        return secret
    }

    private static func logURL(in supportDirectory: URL) -> URL {
        supportDirectory.appendingPathComponent("mac-lan-app-server.log")
    }

    private static func pidURL(in supportDirectory: URL) -> URL {
        supportDirectory.appendingPathComponent("mac-lan-app-server.pid")
    }

    private static func isHostServerReady(port: Int, supportDirectory: URL, token: String) async -> Bool {
        guard isOwnedHostServerRunning(port: port, supportDirectory: supportDirectory) else {
            return false
        }
        guard let url = URL(string: "ws://127.0.0.1:\(port)") else {
            return false
        }
        do {
            _ = try await AppServerEndpointVerifier.verify(url: url, bearerToken: token, timeout: 2)
            return true
        } catch {
            return false
        }
    }

    private static func startHostServer(
        supportDirectory: URL,
        port: Int,
        commands: CommandEnvironment
    ) throws {
        guard let codexExecutableURL = commands.codexExecutableURL() else {
            throw MapofAgentsPairingError.codexNotInstalled
        }

        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let outputPipe = Pipe()
        let logDrain = MapofAgentsHostLogDrain(
            pipe: outputPipe,
            fileURL: logURL(in: supportDirectory)
        )
        try logDrain.start()

        let process = Process()
        let processGeneration = UUID()
        process.executableURL = codexExecutableURL
        process.arguments = appServerArguments(port: port, supportDirectory: supportDirectory)
        process.standardInput = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.terminationHandler = { terminatedProcess in
            let terminatedCurrentGeneration = MapofAgentsHostProcessRegistry.remove(
                processID: terminatedProcess.processIdentifier,
                generation: processGeneration
            )
            if terminatedCurrentGeneration {
                commands.stopForegroundServes()
            }
        }

        do {
            try process.run()
            MapofAgentsHostProcessRegistry.insert(
                process: process,
                logDrain: logDrain,
                generation: processGeneration
            )
            guard process.isRunning else {
                _ = MapofAgentsHostProcessRegistry.remove(
                    processID: process.processIdentifier,
                    generation: processGeneration
                )
                throw MapofAgentsPairingError.hostServerStartFailed(
                    "Codex App Server exited during startup."
                )
            }
            try MapofAgentsPrivateFile.write(
                Data("\(process.processIdentifier)".utf8),
                to: pidURL(in: supportDirectory)
            )
        } catch {
            if process.isRunning {
                process.terminate()
            }
            MapofAgentsHostProcessRegistry.remove(processID: process.processIdentifier)
            logDrain.stop()
            throw MapofAgentsPairingError.hostServerStartFailed(error.localizedDescription)
        }
    }

    static func appServerArguments(port: Int, supportDirectory: URL) -> [String] {
        [
            "app-server",
            "--listen",
            "ws://127.0.0.1:\(port)",
            "--ws-auth",
            "signed-bearer-token",
            "--ws-shared-secret-file",
            sharedSecretURL(in: supportDirectory).path,
            "--ws-issuer",
            signedBearerIssuer,
            "--ws-audience",
            signedBearerAudience,
            "--ws-max-clock-skew-seconds",
            "\(signedBearerClockSkewSeconds)",
        ]
    }

    private static func stopHostServer(supportDirectory: URL, port: Int) throws {
        let pidFile = pidURL(in: supportDirectory)
        guard
            let pidData = try? MapofAgentsPrivateFile.read(pidFile, maximumBytes: 128),
            let rawPID = String(data: pidData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            let pid = Int32(rawPID)
        else {
            return
        }

        guard isTrackedHostServerProcess(pid: pid, port: port, supportDirectory: supportDirectory) else {
            try? FileManager.default.removeItem(at: pidFile)
            return
        }

        MapofAgentsHostProcessRegistry.remove(processID: pid)
        kill(pid, SIGTERM)
        try? FileManager.default.removeItem(at: pidFile)
    }

    private static func isTrackedHostServerProcess(pid: Int32, port: Int, supportDirectory: URL) -> Bool {
        guard pid > 1, kill(pid, 0) == 0 else {
            return false
        }
        guard let rawUID = runText(
            "/bin/ps",
            arguments: ["-ww", "-p", String(pid), "-o", "uid="],
            timeout: 1
        ),
              let processUID = uid_t(rawUID.trimmingCharacters(in: .whitespacesAndNewlines)),
              processUID == geteuid() else {
            return false
        }
        guard let command = runText(
            "/bin/ps",
            arguments: ["-ww", "-p", String(pid), "-o", "command="],
            timeout: 1
        ) else {
            return false
        }
        let lowercased = command.lowercased()
        return lowercased.contains("codex")
            && lowercased.contains("app-server")
            && lowercased.contains("\(port)")
            && command.contains(sharedSecretURL(in: supportDirectory).path)
    }

    private static func processOwnsLoopbackListener(pid: Int32, port: Int) -> Bool {
        guard let output = runText(
            "/usr/sbin/lsof",
            arguments: [
                "-nP",
                "-a",
                "-p", String(pid),
                "-iTCP@127.0.0.1:\(port)",
                "-sTCP:LISTEN",
                "-Fpn",
            ],
            timeout: 1
        ) else {
            return false
        }
        let fields = Set(output.split(whereSeparator: \.isNewline).map(String.init))
        return fields.contains("p\(pid)") && fields.contains("n127.0.0.1:\(port)")
    }

    static func isOwnedHostServerRunning(port: Int, supportDirectory: URL) -> Bool {
        let pidFile = pidURL(in: supportDirectory)
        guard let pidData = try? MapofAgentsPrivateFile.read(pidFile, maximumBytes: 128),
              let rawPID = String(data: pidData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(rawPID) else {
            return false
        }
        return isTrackedHostServerProcess(pid: pid, port: port, supportDirectory: supportDirectory)
            && processOwnsLoopbackListener(pid: pid, port: port)
    }

    private static func recentLogSnippet(in supportDirectory: URL) -> String {
        guard let data = try? MapofAgentsPrivateFile.tail(
            of: logURL(in: supportDirectory),
            maximumBytes: 16_384
        ),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else {
            return "The process did not become ready."
        }

        return String(text.suffix(1_200))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "The process did not become ready."
    }

    static func persistentHostID(in supportDirectory: URL, hostName _: String) throws -> HostID {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let hostIDURL = supportDirectory.appendingPathComponent("pairing-host-id.txt")
        if let data = try? MapofAgentsPrivateFile.read(hostIDURL, maximumBytes: 4_096),
           let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: hostIDURL.path)
            return HostID(rawValue: value)
        }

        let hostID = "paired-mac-\(UUID().uuidString.lowercased())"
        try MapofAgentsPrivateFile.write(Data(hostID.utf8), to: hostIDURL)
        return HostID(rawValue: hostID)
    }

    static func prepareSecureTailnetRoute(
        port: Int,
        commands: CommandEnvironment
    ) throws -> MapofAgentsPairingEndpoint {
        guard let executableURL = commands.tailscaleExecutableURL() else {
            throw MapofAgentsPairingError.tailscaleNotInstalled
        }
        let endpoint = try secureTailnetEndpoint(executableURL: executableURL, commands: commands)
        do {
            try commands.ensureForegroundServe(
                executableURL,
                tailscaleServeArguments(port: port),
                "app-server-\(port)"
            )
        } catch let error as MapofAgentsPairingError {
            throw error
        } catch {
            throw MapofAgentsPairingError.tailscaleServeFailed(error.localizedDescription)
        }
        return endpoint
    }

    static func prepareSecureTailnetRoutes(
        appServerPort: Int,
        credentialExchangePort: UInt16,
        credentialExchangeHTTPSPort: Int,
        commands: CommandEnvironment
    ) throws -> MapofAgentsPairingEndpoint {
        let endpoint = try secureTailnetEndpoint(commands: commands)
        try configureSecureTailnetRoutes(
            appServerPort: appServerPort,
            credentialExchangePort: credentialExchangePort,
            credentialExchangeHTTPSPort: credentialExchangeHTTPSPort,
            commands: commands
        )
        return endpoint
    }

    private static func configureSecureTailnetRoutes(
        appServerPort: Int,
        credentialExchangePort: UInt16,
        credentialExchangeHTTPSPort: Int,
        commands: CommandEnvironment
    ) throws {
        guard let executableURL = commands.tailscaleExecutableURL() else {
            throw MapofAgentsPairingError.tailscaleNotInstalled
        }
        for arguments in [
            tailscaleServeArguments(port: appServerPort),
            tailscaleCredentialExchangeServeArguments(
                loopbackPort: credentialExchangePort,
                httpsPort: credentialExchangeHTTPSPort
            ),
        ] {
            do {
                let key = arguments.contains(where: { $0.hasPrefix("--tls-terminated-tcp=") })
                    ? "app-server-\(appServerPort)"
                    : "credential-exchange-\(credentialExchangeHTTPSPort)"
                try commands.ensureForegroundServe(executableURL, arguments, key)
            } catch let error as MapofAgentsPairingError {
                commands.stopForegroundServes()
                throw error
            } catch {
                commands.stopForegroundServes()
                throw MapofAgentsPairingError.tailscaleServeFailed(error.localizedDescription)
            }
        }
    }

    static func secureTailnetEndpoint(
        commands: CommandEnvironment
    ) throws -> MapofAgentsPairingEndpoint {
        guard let executableURL = commands.tailscaleExecutableURL() else {
            throw MapofAgentsPairingError.tailscaleNotInstalled
        }
        return try secureTailnetEndpoint(executableURL: executableURL, commands: commands)
    }

    private static func secureTailnetEndpoint(
        executableURL: URL,
        commands: CommandEnvironment
    ) throws -> MapofAgentsPairingEndpoint {
        let result: BoundedProcessResult
        do {
            result = try commands.run(executableURL, ["status", "--json"])
        } catch {
            throw MapofAgentsPairingError.tailscaleStatusUnavailable(error.localizedDescription)
        }
        guard result.terminationStatus == 0 else {
            throw MapofAgentsPairingError.tailscaleStatusUnavailable(
                commandDiagnostic(result, fallback: "Tailscale status exited with status \(result.terminationStatus).")
            )
        }
        guard let object = try? JSONSerialization.jsonObject(with: result.stdout.data) as? [String: Any],
              let selfInfo = object["Self"] as? [String: Any],
              let rawDNSName = selfInfo["DNSName"] as? String else {
            throw MapofAgentsPairingError.missingSecureTailnetEndpoint
        }

        let dnsName = rawDNSName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        guard isValidMagicDNSName(dnsName) else {
            throw MapofAgentsPairingError.missingSecureTailnetEndpoint
        }

        var components = URLComponents()
        components.scheme = "wss"
        components.host = dnsName
        guard let url = components.url,
              url.host?.lowercased() == dnsName,
              MapofAgentsPairingEndpoint.isSecureIPhoneCompanionEndpoint(url) else {
            throw MapofAgentsPairingError.missingSecureTailnetEndpoint
        }
        return MapofAgentsPairingEndpoint(kind: .tailnet, url: url, label: dnsName)
    }

    static func tailscaleServeArguments(port: Int) -> [String] {
        [
            "serve",
            "--yes",
            "--tls-terminated-tcp=443",
            "tcp://127.0.0.1:\(port)",
        ]
    }

    static func tailscaleCredentialExchangeServeArguments(
        loopbackPort: UInt16,
        httpsPort: Int
    ) -> [String] {
        [
            "serve",
            "--yes",
            "--https=\(httpsPort)",
            "http://127.0.0.1:\(loopbackPort)",
        ]
    }

    static func credentialExchangeURL(
        endpoint: MapofAgentsPairingEndpoint,
        httpsPort: Int
    ) throws -> URL {
        guard endpoint.kind == .tailnet,
              let host = endpoint.url.host,
              isValidMagicDNSName(host.lowercased()),
              httpsPort == defaultCredentialExchangeHTTPSPort else {
            throw MapofAgentsPairingError.missingSecureTailnetEndpoint
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.port = httpsPort == 443 ? nil : httpsPort
        components.path = "/v1/pairing"
        guard let url = components.url,
              MapofAgentsPairingPayload.isSecureCredentialExchangeURL(url) else {
            throw MapofAgentsPairingError.missingSecureTailnetEndpoint
        }
        return url
    }

    private static func isValidMagicDNSName(_ value: String) -> Bool {
        guard value.hasSuffix(".ts.net"), !value.contains("..") else {
            return false
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        return value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            guard let first = label.unicodeScalars.first,
                  let last = label.unicodeScalars.last,
                  first != "-",
                  last != "-" else {
                return false
            }
            return label.unicodeScalars.allSatisfy(allowed.contains)
        }
    }

    private static func commandDiagnostic(
        _ result: BoundedProcessResult,
        fallback: String
    ) -> String {
        let stderr = result.stderr.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = result.stdout.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = stderr.nilIfEmpty ?? stdout.nilIfEmpty ?? fallback
        return String(message.suffix(800))
    }

    private static func localHostName() -> String {
        runText("/usr/sbin/scutil", arguments: ["--get", "LocalHostName"])?.nilIfEmpty
            ?? ProcessInfo.processInfo.hostName
    }

    private static func discoverTailscaleExecutableURL() -> URL? {
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

    private static func runText(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval = 8
    ) -> String? {
        guard let data = runData(executable, arguments: arguments, timeout: timeout) else { return nil }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func runData(
        _ executable: String,
        arguments: [String],
        timeout: TimeInterval = 8
    ) -> Data? {
        do {
            let result = try BoundedProcessRunner.runBlocking(
                executableURL: URL(fileURLWithPath: executable),
                arguments: arguments,
                timeout: timeout
            )
            guard result.terminationStatus == 0 else { return nil }
            return result.stdout.data
        } catch {
            return nil
        }
    }

    private static func safeIdentifier(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let compact = value.lowercased().unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        return String(compact)
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    #else
    public static func ensureHostServerRunning(port: Int = defaultPort) async throws {
        throw MapofAgentsPairingError.unsupportedPlatform
    }

    public static func makePayload(port: Int = defaultPort) throws -> MapofAgentsPairingPayload {
        throw MapofAgentsPairingError.unsupportedPlatform
    }
    #endif
}

#if os(macOS)
final class MapofAgentsTailnetServeResources: @unchecked Sendable {
    let generation: UUID
    let process: Process
    let logDrain: MapofAgentsHostLogDrain

    init(generation: UUID, process: Process, logDrain: MapofAgentsHostLogDrain) {
        self.generation = generation
        self.process = process
        self.logDrain = logDrain
    }
}

enum MapofAgentsTailnetServeRegistry {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var resources: [String: MapofAgentsTailnetServeResources] = [:]

    private static let guardianScript = #"""
    parent_pid="$1"
    shift
    "$@" &
    serve_pid=$!

    cleanup() {
      kill "$serve_pid" >/dev/null 2>&1 || true
      wait "$serve_pid" >/dev/null 2>&1 || true
    }

    trap 'cleanup; exit 0' HUP INT TERM
    while kill -0 "$serve_pid" >/dev/null 2>&1; do
      current_parent="$(ps -o ppid= -p $$ | tr -d ' ')"
      if [ "$current_parent" != "$parent_pid" ]; then
        cleanup
        exit 0
      fi
      sleep 0.2
    done
    wait "$serve_pid"
    exit $?
    """#

    static func ensureRoute(
        key: String,
        executableURL: URL,
        arguments: [String],
        supportDirectory: URL? = nil
    ) throws {
        let stale = lock.withLock { () -> MapofAgentsTailnetServeResources? in
            guard let existing = resources[key] else { return nil }
            if existing.process.isRunning {
                return nil
            }
            return resources.removeValue(forKey: key)
        }
        stale?.logDrain.stop()
        if lock.withLock({ resources[key]?.process.isRunning == true }) {
            return
        }

        let root = try supportDirectory ?? ApplicationPaths.defaultPaths().applicationSupportDirectory
        let safeKey = key.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        let logURL = root.appendingPathComponent("tailscale-serve-\(String(safeKey)).log")
        let outputPipe = Pipe()
        let logDrain = MapofAgentsHostLogDrain(
            pipe: outputPipe,
            fileURL: logURL,
            maximumBytes: 262_144,
            rotationCount: 1
        )
        try logDrain.start()

        let process = Process()
        let generation = UUID()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            guardianScript,
            "mapofagents-tailscale-serve-guardian",
            "\(Darwin.getpid())",
            executableURL.path,
        ] + arguments
        process.standardInput = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.terminationHandler = { _ in
            remove(key: key, generation: generation)
        }

        do {
            try process.run()
            lock.withLock {
                resources[key] = MapofAgentsTailnetServeResources(
                    generation: generation,
                    process: process,
                    logDrain: logDrain
                )
            }
            Thread.sleep(forTimeInterval: 0.3)
            guard process.isRunning else {
                remove(key: key, generation: generation)
                let detail = (try? MapofAgentsPrivateFile.tail(of: logURL, maximumBytes: 8_192))
                    .flatMap { String(data: $0, encoding: .utf8) }?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let message = detail.flatMap { $0.isEmpty ? nil : $0 }
                    ?? "The foreground Tailscale Serve route exited during startup."
                throw MapofAgentsPairingError.tailscaleServeFailed(
                    message
                )
            }
        } catch {
            if process.isRunning {
                process.terminate()
            }
            remove(key: key, generation: generation)
            logDrain.stop()
            throw error
        }
    }

    static func stopAll() {
        let active = lock.withLock { () -> [MapofAgentsTailnetServeResources] in
            let values = Array(resources.values)
            resources.removeAll()
            return values
        }
        for resource in active where resource.process.isRunning {
            resource.process.terminate()
        }
        for _ in 0..<50 where active.contains(where: { $0.process.isRunning }) {
            Thread.sleep(forTimeInterval: 0.02)
        }
        active.forEach { $0.logDrain.stop() }
    }

    static func activeRouteCountForTesting() -> Int {
        lock.withLock { resources.values.count { $0.process.isRunning } }
    }

    private static func remove(key: String, generation: UUID) {
        let removed = lock.withLock { () -> MapofAgentsTailnetServeResources? in
            guard resources[key]?.generation == generation else { return nil }
            return resources.removeValue(forKey: key)
        }
        removed?.logDrain.stop()
    }
}

final class MapofAgentsHostLogDrain: @unchecked Sendable {
    private let pipe: Pipe
    private let fileURL: URL
    private let maximumBytes: Int
    private let rotationCount: Int
    private let queue = DispatchQueue(label: "dev.mapofagents.host-log")

    init(
        pipe: Pipe,
        fileURL: URL,
        maximumBytes: Int = 1_048_576,
        rotationCount: Int = 2
    ) {
        self.pipe = pipe
        self.fileURL = fileURL
        self.maximumBytes = max(1, maximumBytes)
        self.rotationCount = max(1, rotationCount)
    }

    func start() throws {
        try prepareCurrentFileIfNeeded()
        for index in 1...rotationCount {
            try normalizeExistingLog(at: rotatedFileURL(index: index))
        }
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async { [weak self] in
                try? self?.append(data)
            }
        }
    }

    func stop() {
        pipe.fileHandleForReading.readabilityHandler = nil
    }

    func append(_ data: Data) throws {
        try prepareCurrentFileIfNeeded()
        let payload = data.count > maximumBytes ? Data(data.suffix(maximumBytes)) : data
        let currentSize = try MapofAgentsPrivateFile.regularFileSize(at: fileURL) ?? 0
        if payload.count > maximumBytes - currentSize {
            try rotate()
        }
        try prepareCurrentFileIfNeeded()
        try MapofAgentsPrivateFile.append(payload, to: fileURL)
    }

    private func rotate() throws {
        let fileManager = FileManager.default
        for index in stride(from: rotationCount, through: 1, by: -1) {
            let destination = rotatedFileURL(index: index)
            if try MapofAgentsPrivateFile.regularFileSize(at: destination) != nil {
                try fileManager.removeItem(at: destination)
            }
            let source = index == 1
                ? fileURL
                : rotatedFileURL(index: index - 1)
            if try MapofAgentsPrivateFile.regularFileSize(at: source) != nil {
                try normalizeExistingLog(at: source)
                try fileManager.moveItem(at: source, to: destination)
                try MapofAgentsPrivateFile.restrictPermissions(of: destination)
            }
        }
    }

    private func prepareCurrentFileIfNeeded() throws {
        if try MapofAgentsPrivateFile.regularFileSize(at: fileURL) == nil {
            try MapofAgentsPrivateFile.write(Data(), to: fileURL)
        } else {
            try normalizeExistingLog(at: fileURL)
        }
    }

    private func normalizeExistingLog(at url: URL) throws {
        guard let size = try MapofAgentsPrivateFile.regularFileSize(at: url) else { return }
        if size > maximumBytes {
            let tail = try MapofAgentsPrivateFile.tail(of: url, maximumBytes: maximumBytes)
            try MapofAgentsPrivateFile.write(tail, to: url)
        } else {
            try MapofAgentsPrivateFile.restrictPermissions(of: url)
        }
    }

    private func rotatedFileURL(index: Int) -> URL {
        URL(fileURLWithPath: "\(fileURL.path).\(index)")
    }
}

private final class MapofAgentsHostProcessResources: @unchecked Sendable {
    let generation: UUID
    let process: Process
    let logDrain: MapofAgentsHostLogDrain

    init(generation: UUID, process: Process, logDrain: MapofAgentsHostLogDrain) {
        self.generation = generation
        self.process = process
        self.logDrain = logDrain
    }
}

struct MapofAgentsHostProcessGenerationTracker: Sendable {
    private(set) var current: UUID?

    mutating func install(_ generation: UUID) {
        current = generation
    }

    mutating func retire(_ generation: UUID) -> Bool {
        guard current == generation else { return false }
        current = nil
        return true
    }

    mutating func invalidate(_ generation: UUID) {
        if current == generation {
            current = nil
        }
    }
}

private enum MapofAgentsHostProcessRegistry {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var resources: [Int32: MapofAgentsHostProcessResources] = [:]
    nonisolated(unsafe) private static var generations = MapofAgentsHostProcessGenerationTracker()

    static func insert(process: Process, logDrain: MapofAgentsHostLogDrain, generation: UUID) {
        let displaced = lock.withLock { () -> MapofAgentsHostProcessResources? in
            let displaced = resources.updateValue(
                MapofAgentsHostProcessResources(
                    generation: generation,
                    process: process,
                    logDrain: logDrain
                ),
                forKey: process.processIdentifier
            )
            generations.install(generation)
            return displaced
        }
        displaced?.logDrain.stop()
    }

    static func remove(processID: Int32) {
        let removed = lock.withLock { () -> MapofAgentsHostProcessResources? in
            let removed = resources.removeValue(forKey: processID)
            if let removed {
                generations.invalidate(removed.generation)
            }
            return removed
        }
        removed?.logDrain.stop()
    }

    static func remove(processID: Int32, generation: UUID) -> Bool {
        let result = lock.withLock { () -> (MapofAgentsHostProcessResources?, Bool) in
            guard resources[processID]?.generation == generation else {
                return (nil, false)
            }
            let removed = resources.removeValue(forKey: processID)
            return (removed, generations.retire(generation))
        }
        let removed = result.0
        removed?.logDrain.stop()
        return result.1
    }
}
#endif

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded value: String) {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = base64.count % 4
        if padding > 0 {
            base64.append(String(repeating: "=", count: 4 - padding))
        }
        self.init(base64Encoded: base64)
    }
}

private extension JSONDecoder.DateDecodingStrategy {
    static let mapofagentsFlexibleISO8601 = custom { decoder in
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        if let date = ISO8601DateFormatter.mapofagentsDate(from: value) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected an ISO 8601 date string."
        )
    }
}

private extension ISO8601DateFormatter {
    static func mapofagentsDate(from value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
