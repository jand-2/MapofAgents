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
        case .hostServerStartFailed(let message):
            return "Could not start the mapofagents Mac host server: \(message)"
        case .cleartextIPAddressEndpointRequiresDNSName:
            return "This pairing only has cleartext IP endpoints. Pair again with a Tailscale MagicDNS or .local endpoint."
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

    public var version: Int
    public var hostID: HostID
    public var name: String
    public var endpoints: [MapofAgentsPairingEndpoint]
    public var bearerToken: String
    public var createdAt: Date
    public var expiresAt: Date?
    public var mapofagentsSupportDirectory: String?

    public init(
        version: Int = 1,
        hostID: HostID,
        name: String,
        endpoints: [MapofAgentsPairingEndpoint],
        bearerToken: String,
        createdAt: Date = Date(),
        expiresAt: Date? = Date().addingTimeInterval(30 * 60),
        mapofagentsSupportDirectory: String? = nil
    ) {
        self.version = version
        self.hostID = hostID
        self.name = name
        self.endpoints = endpoints
        self.bearerToken = bearerToken
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
    }

    public var preferredEndpoints: [MapofAgentsPairingEndpoint] {
        MapofAgentsEndpointOrdering.preferredEndpoints(endpoints)
    }

    public func pairingURL() throws -> URL {
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
    public static let currentPersistenceVersion = 2

    public var version: Int
    public var id: HostID
    public var name: String
    public var endpoints: [MapofAgentsPairingEndpoint]
    public var bearerToken: String
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
            bearerToken: try container.decode(String.self, forKey: .bearerToken),
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
        try container.encode(bearerToken, forKey: .bearerToken)
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
    public static let pairingSessionDuration: TimeInterval = 30 * 60
    private static let signedBearerIssuer = "mapofagents"
    private static let signedBearerAudience = "codex-app-server"
    private static let signedBearerSubject = "mapofagents-pairing"
    private static let signedBearerClockSkewSeconds = 5

    #if os(macOS)
    public static func ensureHostServerRunning(port: Int = defaultPort) async throws {
        let paths = try ApplicationPaths.defaultPaths()
        var session = try currentPairingSession(in: paths.applicationSupportDirectory)
        if session == nil {
            try? stopHostServer(supportDirectory: paths.applicationSupportDirectory, port: port)
            session = try rotateToken(
                in: paths.applicationSupportDirectory,
                expiresAt: Date().addingTimeInterval(pairingSessionDuration)
            )
        }
        let activeSession = try requirePairingSession(session)

        if await isHostServerReady(port: port, supportDirectory: paths.applicationSupportDirectory, token: activeSession.token) {
            schedulePairingExpiration(
                token: activeSession.token,
                supportDirectory: paths.applicationSupportDirectory,
                port: port,
                expiresAt: activeSession.expiresAt
            )
            return
        }

        try startHostServer(supportDirectory: paths.applicationSupportDirectory, port: port)

        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(250))
            if await isHostServerReady(port: port, supportDirectory: paths.applicationSupportDirectory, token: activeSession.token) {
                schedulePairingExpiration(
                    token: activeSession.token,
                    supportDirectory: paths.applicationSupportDirectory,
                    port: port,
                    expiresAt: activeSession.expiresAt
                )
                return
            }
        }

        expirePairingSessionIfCurrentToken(
            token: activeSession.token,
            supportDirectory: paths.applicationSupportDirectory,
            port: port
        )
        throw MapofAgentsPairingError.hostServerStartFailed(recentLogSnippet(in: paths.applicationSupportDirectory))
    }

    public static func beginPairingSession(
        port: Int = defaultPort,
        duration: TimeInterval = pairingSessionDuration
    ) async throws -> MapofAgentsPairingPayload {
        let paths = try ApplicationPaths.defaultPaths()
        try? stopHostServer(supportDirectory: paths.applicationSupportDirectory, port: port)
        let expiresAt = Date().addingTimeInterval(duration)
        let session = try rotateToken(in: paths.applicationSupportDirectory, expiresAt: expiresAt)
        try startHostServer(supportDirectory: paths.applicationSupportDirectory, port: port)

        for _ in 0..<12 {
            try? await Task.sleep(for: .milliseconds(250))
            if await isHostServerReady(port: port, supportDirectory: paths.applicationSupportDirectory, token: session.token) {
                let payload = try makePayload(
                    port: port,
                    token: session.token,
                    supportDirectory: paths.applicationSupportDirectory,
                    expiresAt: expiresAt
                )
                schedulePairingExpiration(
                    token: session.token,
                    supportDirectory: paths.applicationSupportDirectory,
                    port: port,
                    expiresAt: expiresAt
                )
                return payload
            }
        }

        expirePairingSessionIfCurrentToken(
            token: session.token,
            supportDirectory: paths.applicationSupportDirectory,
            port: port
        )
        throw MapofAgentsPairingError.hostServerStartFailed(recentLogSnippet(in: paths.applicationSupportDirectory))
    }

    public static func stopPairingSession(port: Int = defaultPort) async throws {
        let paths = try ApplicationPaths.defaultPaths()
        try stopHostServer(supportDirectory: paths.applicationSupportDirectory, port: port)
        try? FileManager.default.removeItem(at: tokenURL(in: paths.applicationSupportDirectory))
        try? FileManager.default.removeItem(at: sharedSecretURL(in: paths.applicationSupportDirectory))
    }

    public static func makePayload(port: Int = defaultPort) throws -> MapofAgentsPairingPayload {
        let paths = try ApplicationPaths.defaultPaths()
        guard let session = try currentPairingSession(in: paths.applicationSupportDirectory) else {
            throw MapofAgentsPairingError.expired
        }
        let payload = try makePayload(
            port: port,
            token: session.token,
            supportDirectory: paths.applicationSupportDirectory,
            expiresAt: session.expiresAt
        )
        schedulePairingExpiration(
            token: session.token,
            supportDirectory: paths.applicationSupportDirectory,
            port: port,
            expiresAt: session.expiresAt
        )
        return payload
    }

    private static func makePayload(
        port: Int,
        token: String,
        supportDirectory: URL,
        expiresAt: Date?
    ) throws -> MapofAgentsPairingPayload {
        let hostName = localHostName()
        return MapofAgentsPairingPayload(
            hostID: try persistentHostID(in: supportDirectory, hostName: hostName),
            name: hostName,
            endpoints: endpoints(port: port),
            bearerToken: token,
            expiresAt: expiresAt,
            mapofagentsSupportDirectory: supportDirectory.standardizedFileURL.path
        )
    }

    private struct PairingAuthSession {
        var token: String
        var expiresAt: Date
    }

    private static func requirePairingSession(_ session: PairingAuthSession?) throws -> PairingAuthSession {
        guard let session else {
            throw MapofAgentsPairingError.expired
        }
        return session
    }

    private static func currentPairingSession(in supportDirectory: URL, now: Date = Date()) throws -> PairingAuthSession? {
        guard
            let token = currentToken(in: supportDirectory),
            let expiresAt = signedBearerExpiration(token),
            expiresAt > now,
            FileManager.default.fileExists(atPath: sharedSecretURL(in: supportDirectory).path)
        else {
            return nil
        }
        return PairingAuthSession(token: token, expiresAt: expiresAt)
    }

    private static func rotateToken(in supportDirectory: URL, expiresAt: Date) throws -> PairingAuthSession {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let secret = generateToken()
        let token = try signedBearerToken(secret: secret, expiresAt: expiresAt)
        try secret.write(to: sharedSecretURL(in: supportDirectory), atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sharedSecretURL(in: supportDirectory).path)
        try token.write(to: tokenURL(in: supportDirectory), atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL(in: supportDirectory).path)
        return PairingAuthSession(token: token, expiresAt: expiresAt)
    }

    private static func generateToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<32)
            .map { _ in String(format: "%02x", UInt8.random(in: UInt8.min...UInt8.max, using: &generator)) }
            .joined()
    }

    static func signedBearerToken(secret: String, expiresAt: Date, issuedAt: Date = Date()) throws -> String {
        let header: [String: Any] = [
            "alg": "HS256",
            "typ": "JWT",
        ]
        let payload: [String: Any] = [
            "iss": signedBearerIssuer,
            "aud": signedBearerAudience,
            "sub": signedBearerSubject,
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

    private static func schedulePairingExpiration(
        token: String,
        supportDirectory: URL,
        port: Int,
        expiresAt: Date
    ) {
        let delay = max(0, expiresAt.timeIntervalSinceNow)
        let milliseconds = min(delay * 1_000, Double(Int.max))
        _ = Task.detached(priority: .utility) {
            if milliseconds > 0 {
                try? await Task.sleep(for: .milliseconds(Int(milliseconds)))
            }
            expirePairingSessionIfCurrentToken(token: token, supportDirectory: supportDirectory, port: port)
        }
    }

    static func expirePairingSessionIfCurrentToken(token: String, supportDirectory: URL, port: Int = defaultPort) {
        guard currentToken(in: supportDirectory) == token else {
            return
        }

        try? stopHostServer(supportDirectory: supportDirectory, port: port)
        try? FileManager.default.removeItem(at: tokenURL(in: supportDirectory))
        try? FileManager.default.removeItem(at: sharedSecretURL(in: supportDirectory))
    }

    private static func currentToken(in supportDirectory: URL) -> String? {
        try? String(contentsOf: tokenURL(in: supportDirectory), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private static func tokenURL(in supportDirectory: URL) -> URL {
        supportDirectory.appendingPathComponent("mac-lan-app-server.token")
    }

    private static func sharedSecretURL(in supportDirectory: URL) -> URL {
        supportDirectory.appendingPathComponent("mac-lan-app-server.shared-secret")
    }

    private static func logURL(in supportDirectory: URL) -> URL {
        supportDirectory.appendingPathComponent("mac-lan-app-server.log")
    }

    private static func pidURL(in supportDirectory: URL) -> URL {
        supportDirectory.appendingPathComponent("mac-lan-app-server.pid")
    }

    private static func isHostServerReady(port: Int, supportDirectory: URL, token: String) async -> Bool {
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

    private static func startHostServer(supportDirectory: URL, port: Int) throws {
        guard let codexPath = LocalCodexDiscovery.findCodexExecutable() else {
            throw MapofAgentsPairingError.codexNotInstalled
        }

        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logURL(in: supportDirectory).path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL(in: supportDirectory))
        try logHandle.seekToEnd()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = [
            "app-server",
            "--listen",
            "ws://0.0.0.0:\(port)",
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
        process.standardInput = Pipe()
        process.standardOutput = logHandle
        process.standardError = logHandle

        do {
            try process.run()
            try "\(process.processIdentifier)"
                .write(to: pidURL(in: supportDirectory), atomically: true, encoding: .utf8)
        } catch {
            throw MapofAgentsPairingError.hostServerStartFailed(error.localizedDescription)
        }
    }

    private static func stopHostServer(supportDirectory: URL, port: Int) throws {
        let pidFile = pidURL(in: supportDirectory)
        guard
            let rawPID = try? String(contentsOf: pidFile, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            let pid = Int32(rawPID)
        else {
            return
        }

        guard isTrackedHostServerProcess(pid: pid, port: port, supportDirectory: supportDirectory) else {
            try? FileManager.default.removeItem(at: pidFile)
            return
        }

        kill(pid, SIGTERM)
        try? FileManager.default.removeItem(at: pidFile)
    }

    private static func isTrackedHostServerProcess(pid: Int32, port: Int, supportDirectory: URL) -> Bool {
        guard let command = runText("/bin/ps", arguments: ["-p", String(pid), "-o", "command="]) else {
            return false
        }
        let lowercased = command.lowercased()
        return lowercased.contains("codex")
            && lowercased.contains("app-server")
            && lowercased.contains("\(port)")
            && command.contains(sharedSecretURL(in: supportDirectory).path)
    }

    private static func recentLogSnippet(in supportDirectory: URL) -> String {
        guard let data = try? Data(contentsOf: logURL(in: supportDirectory)),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else {
            return "The process did not become ready."
        }

        return String(text.suffix(1_200))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "The process did not become ready."
    }

    private static func persistentHostID(in supportDirectory: URL, hostName: String) throws -> HostID {
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let hostIDURL = supportDirectory.appendingPathComponent("pairing-host-id.txt")
        if let value = try? String(contentsOf: hostIDURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return HostID(rawValue: value)
        }

        let hostID = "paired-mac-\(safeIdentifier(hostName))"
        try hostID.write(to: hostIDURL, atomically: true, encoding: .utf8)
        return HostID(rawValue: hostID)
    }

    private static func endpoints(port: Int) -> [MapofAgentsPairingEndpoint] {
        var seen = Set<String>()
        var endpoints: [MapofAgentsPairingEndpoint] = []

        func append(_ kind: MapofAgentsPairingEndpointKind, host: String, label: String) {
            let cleaned = host.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard !cleaned.isEmpty else { return }
            let formattedHost = cleaned.contains(":") && !cleaned.hasPrefix("[") ? "[\(cleaned)]" : cleaned
            guard let url = URL(string: "ws://\(formattedHost):\(port)") else { return }
            guard seen.insert(url.absoluteString).inserted else { return }
            endpoints.append(MapofAgentsPairingEndpoint(kind: kind, url: url, label: label))
        }

        for host in tailnetHosts() {
            append(.tailnet, host: host, label: host)
        }

        for host in localHosts() {
            append(.local, host: host, label: host)
        }

        return endpoints
    }

    private static func tailnetHosts() -> [String] {
        var hosts: [String] = []

        if let statusData = runTailscale(arguments: ["status", "--json"]),
           let object = try? JSONSerialization.jsonObject(with: statusData) as? [String: Any],
           let selfInfo = object["Self"] as? [String: Any] {
            if let dnsName = selfInfo["DNSName"] as? String {
                hosts.append(dnsName)
            }
            if let addresses = selfInfo["TailscaleIPs"] as? [String] {
                hosts.append(contentsOf: addresses)
            }
        }

        if hosts.isEmpty,
           let ipData = runTailscale(arguments: ["ip", "-4"]),
           let ipOutput = String(data: ipData, encoding: .utf8) {
            hosts.append(contentsOf: ipOutput.split(whereSeparator: \.isNewline).map(String.init))
        }

        if hosts.isEmpty {
            hosts.append(contentsOf: tailscaleIPv4AddressesFromIfconfig())
        }

        return stableUnique(hosts)
    }

    private static func localHosts() -> [String] {
        var hosts = [String]()
        if let localHostName = runText("/usr/sbin/scutil", arguments: ["--get", "LocalHostName"])?.nilIfEmpty {
            hosts.append("\(localHostName).local")
        }
        hosts.append(ProcessInfo.processInfo.hostName)
        hosts.append("mac-host.lan")
        return stableUnique(hosts)
    }

    private static func localHostName() -> String {
        runText("/usr/sbin/scutil", arguments: ["--get", "LocalHostName"])?.nilIfEmpty
            ?? ProcessInfo.processInfo.hostName
    }

    private static func runTailscale(arguments: [String]) -> Data? {
        guard let executable = tailscaleExecutableURL() else { return nil }
        return runData(executable.path, arguments: arguments)
    }

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

    private static func tailscaleIPv4AddressesFromIfconfig() -> [String] {
        guard let output = runText("/sbin/ifconfig", arguments: []) else {
            return []
        }

        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let parts = line.split(separator: " ").map(String.init)
                guard let inetIndex = parts.firstIndex(of: "inet"),
                      inetIndex + 1 < parts.count else {
                    return nil
                }
                let address = parts[inetIndex + 1]
                guard isTailscaleIPv4Address(address) else { return nil }
                return address
            }
    }

    private static func isTailscaleIPv4Address(_ value: String) -> Bool {
        let parts = value.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts[0] == 100 else { return false }
        return (64...127).contains(parts[1])
    }

    private static func runText(_ executable: String, arguments: [String]) -> String? {
        guard let data = runData(executable, arguments: arguments) else { return nil }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func runData(_ executable: String, arguments: [String]) -> Data? {
        do {
            let result = try BoundedProcessRunner.runBlocking(
                executableURL: URL(fileURLWithPath: executable),
                arguments: arguments,
                timeout: 8
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

    private static func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard !normalized.isEmpty, seen.insert(normalized.lowercased()).inserted else {
                continue
            }
            result.append(normalized)
        }
        return result
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
