import CryptoKit
import Foundation

#if os(macOS)
import Darwin
import Network
#endif

public enum MapofAgentsCredentialExchangeError: LocalizedError, Sendable, Equatable {
    case invalidExchangeURL
    case invalidRequest
    case enrollmentInvalid
    case enrollmentExpired
    case refreshCredentialMissing
    case refreshCredentialInvalid
    case deviceRevoked
    case registryFull
    case hostMismatch
    case listenerFailed(String)
    case serverRejected(status: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidExchangeURL:
            return "The pairing credential exchange must use a private HTTPS endpoint."
        case .invalidRequest:
            return "The pairing credential request is invalid."
        case .enrollmentInvalid:
            return "This pairing enrollment has already been used or is not valid."
        case .enrollmentExpired:
            return "This pairing enrollment has expired. Generate a new pairing code on the Mac."
        case .refreshCredentialMissing:
            return "The paired device credential is missing from Keychain. Pair this device again."
        case .refreshCredentialInvalid:
            return "The paired device credential is no longer valid. Pair this device again."
        case .deviceRevoked:
            return "This paired device has been revoked. Pair this device again to reconnect."
        case .registryFull:
            return "The Mac has reached its paired-device limit. Revoke an old device before pairing another one."
        case .hostMismatch:
            return "The credential exchange response belongs to a different Mac."
        case .listenerFailed(let message):
            return "The local pairing credential service could not start: \(message)"
        case .serverRejected(_, let message):
            return message
        }
    }
}

public struct MapofAgentsEnrollmentRequest: Codable, Hashable, Sendable {
    public var enrollmentToken: String
    public var deviceName: String
    public var deviceID: String
    public var refreshCredential: String

    public init(
        enrollmentToken: String,
        deviceName: String,
        deviceID: String = UUID().uuidString.lowercased(),
        refreshCredential: String? = nil
    ) {
        self.enrollmentToken = enrollmentToken
        self.deviceName = deviceName
        self.deviceID = deviceID
        self.refreshCredential = refreshCredential ?? Self.randomCredential()
    }

    private static func randomCredential(byteCount: Int = 32) -> String {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<byteCount).map { _ in
            UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
        })
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    }
}

public struct MapofAgentsEnrollmentResponse: Codable, Hashable, Sendable {
    public var hostID: HostID
    public var deviceID: String
    public var refreshCredential: String
    public var accessToken: String
    public var accessTokenExpiresAt: Date
    public var endpoints: [MapofAgentsPairingEndpoint]
    public var mapofagentsSupportDirectory: String?

    public init(
        hostID: HostID,
        deviceID: String,
        refreshCredential: String,
        accessToken: String,
        accessTokenExpiresAt: Date,
        endpoints: [MapofAgentsPairingEndpoint],
        mapofagentsSupportDirectory: String? = nil
    ) {
        self.hostID = hostID
        self.deviceID = deviceID
        self.refreshCredential = refreshCredential
        self.accessToken = accessToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.endpoints = endpoints
        self.mapofagentsSupportDirectory = mapofagentsSupportDirectory
    }
}

public struct MapofAgentsRefreshRequest: Codable, Hashable, Sendable {
    public var hostID: HostID
    public var deviceID: String
    public var refreshCredential: String

    public init(hostID: HostID, deviceID: String, refreshCredential: String) {
        self.hostID = hostID
        self.deviceID = deviceID
        self.refreshCredential = refreshCredential
    }
}

public struct MapofAgentsRefreshResponse: Codable, Hashable, Sendable {
    public var accessToken: String
    public var accessTokenExpiresAt: Date

    public init(accessToken: String, accessTokenExpiresAt: Date) {
        self.accessToken = accessToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
    }
}

public struct MapofAgentsRevokeResponse: Codable, Hashable, Sendable {
    public var revoked: Bool

    public init(revoked: Bool) {
        self.revoked = revoked
    }
}

public protocol MapofAgentsCredentialExchanging: Sendable {
    func enroll(
        at exchangeURL: URL,
        enrollmentToken: String,
        deviceName: String
    ) async throws -> MapofAgentsEnrollmentResponse

    func refresh(
        at exchangeURL: URL,
        request: MapofAgentsRefreshRequest
    ) async throws -> MapofAgentsRefreshResponse

    func revoke(
        at exchangeURL: URL,
        request: MapofAgentsRefreshRequest
    ) async throws
}

public struct MapofAgentsURLSessionCredentialExchangeClient: MapofAgentsCredentialExchanging {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func enroll(
        at exchangeURL: URL,
        enrollmentToken: String,
        deviceName: String
    ) async throws -> MapofAgentsEnrollmentResponse {
        let request = MapofAgentsEnrollmentRequest(
            enrollmentToken: enrollmentToken,
            deviceName: deviceName
        )
        let url = try actionURL(base: exchangeURL, action: "enroll")
        do {
            return try await post(request, to: url, response: MapofAgentsEnrollmentResponse.self)
        } catch let error as MapofAgentsCredentialExchangeError {
            guard case .serverRejected(let status, _) = error, status >= 500 else { throw error }
            return try await post(request, to: url, response: MapofAgentsEnrollmentResponse.self)
        } catch {
            // Reuse the exact client-generated device ID and refresh secret.
            // The host treats this request as idempotent if the first response
            // was lost after registration committed.
            return try await post(request, to: url, response: MapofAgentsEnrollmentResponse.self)
        }
    }

    public func refresh(
        at exchangeURL: URL,
        request: MapofAgentsRefreshRequest
    ) async throws -> MapofAgentsRefreshResponse {
        try await post(
            request,
            to: try actionURL(base: exchangeURL, action: "refresh"),
            response: MapofAgentsRefreshResponse.self
        )
    }

    public func revoke(
        at exchangeURL: URL,
        request: MapofAgentsRefreshRequest
    ) async throws {
        _ = try await post(
            request,
            to: try actionURL(base: exchangeURL, action: "revoke"),
            response: MapofAgentsRevokeResponse.self
        )
    }

    private func actionURL(base: URL, action: String) throws -> URL {
        guard MapofAgentsPairingPayload.isSecureCredentialExchangeURL(base),
              base.query == nil,
              base.fragment == nil,
              base.user == nil,
              base.password == nil else {
            throw MapofAgentsCredentialExchangeError.invalidExchangeURL
        }
        return base.appendingPathComponent(action, isDirectory: false)
    }

    private func post<Request: Encodable, Response: Decodable>(
        _ value: Request,
        to url: URL,
        response: Response.Type
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(value)

        let (data, urlResponse) = try await session.data(
            for: request,
            delegate: MapofAgentsNoRedirectURLSessionDelegate.shared
        )
        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw MapofAgentsCredentialExchangeError.invalidRequest
        }
        guard httpResponse.url == url else {
            throw MapofAgentsCredentialExchangeError.invalidExchangeURL
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data).error)
                ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            throw MapofAgentsCredentialExchangeError.serverRejected(
                status: httpResponse.statusCode,
                message: message
            )
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .mapofagentsCredentialExchangeISO8601
        return try decoder.decode(Response.self, from: data)
    }
}

final class MapofAgentsNoRedirectURLSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = MapofAgentsNoRedirectURLSessionDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private struct ErrorEnvelope: Codable, Sendable {
    var error: String
}

public struct MapofAgentsPairedDeviceSummary: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var createdAt: Date
    public var lastRefreshedAt: Date

    public init(id: String, name: String, createdAt: Date, lastRefreshedAt: Date) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.lastRefreshedAt = lastRefreshedAt
    }
}

public enum MapofAgentsPairingCredentialRetirement {
    public static func retire(
        _ host: MapofAgentsPairedHost,
        credentialVault: any MapofAgentsPairingCredentialVault,
        credentialExchange: any MapofAgentsCredentialExchanging
    ) async throws {
        guard let deviceID = host.deviceID,
              let exchangeURL = host.credentialExchangeURL,
              let refreshCredential = try credentialVault.loadRefreshCredential(
                hostID: host.id,
                deviceID: deviceID
              ) else {
            throw MapofAgentsCredentialExchangeError.refreshCredentialMissing
        }

        try await credentialExchange.revoke(
            at: exchangeURL,
            request: MapofAgentsRefreshRequest(
                hostID: host.id,
                deviceID: deviceID,
                refreshCredential: refreshCredential
            )
        )
        try credentialVault.deleteRefreshCredential(hostID: host.id, deviceID: deviceID)
    }
}

public actor MapofAgentsPairedHostAccessTokenProvider: AppServerAccessTokenProviding {
    private let hostID: HostID
    private let deviceID: String
    private let exchangeURL: URL
    private let credentialVault: any MapofAgentsPairingCredentialVault
    private let exchangeClient: any MapofAgentsCredentialExchanging
    private var initialAccessToken: AppServerAccessToken?
    private var refreshTask: Task<AppServerAccessToken?, Error>?

    public init(
        hostID: HostID,
        deviceID: String,
        exchangeURL: URL,
        initialAccessToken: String? = nil,
        initialAccessTokenExpiresAt: Date? = nil,
        credentialVault: any MapofAgentsPairingCredentialVault = KeychainMapofAgentsPairingCredentialVault(),
        exchangeClient: any MapofAgentsCredentialExchanging = MapofAgentsURLSessionCredentialExchangeClient()
    ) {
        self.hostID = hostID
        self.deviceID = deviceID
        self.exchangeURL = exchangeURL
        let normalizedInitialAccessToken = initialAccessToken?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.initialAccessToken = normalizedInitialAccessToken?.isEmpty == false
            ? AppServerAccessToken(
                value: normalizedInitialAccessToken ?? "",
                expiresAt: initialAccessTokenExpiresAt
            )
            : nil
        self.credentialVault = credentialVault
        self.exchangeClient = exchangeClient
    }

    public func accessToken() async throws -> AppServerAccessToken? {
        if let initialAccessToken {
            self.initialAccessToken = nil
            if initialAccessToken.expiresAt.map({ $0 > Date() }) != false {
                return initialAccessToken
            }
        }
        if let refreshTask {
            return try await refreshTask.value
        }

        let hostID = hostID
        let deviceID = deviceID
        let exchangeURL = exchangeURL
        let credentialVault = credentialVault
        let exchangeClient = exchangeClient
        let task = Task<AppServerAccessToken?, Error> {
            guard let refreshCredential = try credentialVault.loadRefreshCredential(
                hostID: hostID,
                deviceID: deviceID
            ) else {
                throw MapofAgentsCredentialExchangeError.refreshCredentialMissing
            }
            let response = try await exchangeClient.refresh(
                at: exchangeURL,
                request: MapofAgentsRefreshRequest(
                    hostID: hostID,
                    deviceID: deviceID,
                    refreshCredential: refreshCredential
                )
            )
            return AppServerAccessToken(
                value: response.accessToken,
                expiresAt: response.accessTokenExpiresAt
            )
        }
        refreshTask = task
        do {
            let token = try await task.value
            refreshTask = nil
            return token
        } catch {
            refreshTask = nil
            throw error
        }
    }
}

#if os(macOS)
enum MapofAgentsPrivateFile {
    private static let ownerReadWritePermissions = mode_t(0o600)

    static func write(_ data: Data, to url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".private-\(UUID().uuidString)")
        var descriptor = Darwin.open(
            temporaryURL.path,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            ownerReadWritePermissions
        )
        guard descriptor >= 0 else { throw currentPOSIXError() }

        do {
            guard Darwin.fchmod(descriptor, ownerReadWritePermissions) == 0 else {
                throw currentPOSIXError()
            }
            try writeAll(data, to: descriptor)
            guard Darwin.fsync(descriptor) == 0 else { throw currentPOSIXError() }
            let closeResult = Darwin.close(descriptor)
            descriptor = -1
            guard closeResult == 0 else { throw currentPOSIXError() }
            guard Darwin.rename(temporaryURL.path, url.path) == 0 else {
                throw currentPOSIXError()
            }
        } catch {
            if descriptor >= 0 {
                Darwin.close(descriptor)
            }
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    static func append(_ data: Data, to url: URL) throws {
        let descriptor = Darwin.open(
            url.path,
            O_WRONLY | O_APPEND | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
        )
        guard descriptor >= 0 else { throw currentPOSIXError() }
        defer { Darwin.close(descriptor) }

        try validateRegularFile(descriptor)
        guard Darwin.fchmod(descriptor, ownerReadWritePermissions) == 0 else {
            throw currentPOSIXError()
        }
        try writeAll(data, to: descriptor)
    }

    static func restrictPermissions(of url: URL) throws {
        let descriptor = Darwin.open(
            url.path,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
        )
        guard descriptor >= 0 else { throw currentPOSIXError() }
        defer { Darwin.close(descriptor) }

        try validateRegularFile(descriptor)
        guard Darwin.fchmod(descriptor, ownerReadWritePermissions) == 0 else {
            throw currentPOSIXError()
        }
    }

    static func regularFileSize(at url: URL) throws -> Int? {
        let descriptor = Darwin.open(
            url.path,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
        )
        if descriptor < 0 {
            if errno == ENOENT { return nil }
            throw currentPOSIXError()
        }
        defer { Darwin.close(descriptor) }

        let status = try regularFileStatus(descriptor)
        guard status.st_size >= 0, status.st_size <= off_t(Int.max) else {
            throw POSIXError(.EFBIG)
        }
        return Int(status.st_size)
    }

    static func read(_ url: URL, maximumBytes: Int) throws -> Data {
        let descriptor = Darwin.open(
            url.path,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
        )
        guard descriptor >= 0 else { throw currentPOSIXError() }
        defer { Darwin.close(descriptor) }

        let status = try regularFileStatus(descriptor)
        let boundedMaximum = max(0, maximumBytes)
        guard status.st_size >= 0, status.st_size <= off_t(boundedMaximum) else {
            throw POSIXError(.EFBIG)
        }

        var result = Data(count: Int(status.st_size))
        let count = try result.withUnsafeMutableBytes { buffer -> Int in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            var total = 0
            while total < buffer.count {
                let readCount = Darwin.read(
                    descriptor,
                    baseAddress.advanced(by: total),
                    buffer.count - total
                )
                if readCount < 0 {
                    if errno == EINTR { continue }
                    throw currentPOSIXError()
                }
                if readCount == 0 { break }
                total += readCount
            }
            return total
        }
        if count < result.count {
            result.removeSubrange(count..<result.count)
        }
        return result
    }

    static func tail(of url: URL, maximumBytes: Int) throws -> Data {
        let descriptor = Darwin.open(
            url.path,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
        )
        guard descriptor >= 0 else { throw currentPOSIXError() }
        defer { Darwin.close(descriptor) }

        let status = try regularFileStatus(descriptor)
        let boundedMaximum = max(0, maximumBytes)
        let available = min(off_t(boundedMaximum), max(0, status.st_size))
        let offset = max(0, status.st_size - available)
        guard Darwin.lseek(descriptor, offset, SEEK_SET) >= 0 else {
            throw currentPOSIXError()
        }

        var result = Data(count: Int(available))
        let count = try result.withUnsafeMutableBytes { buffer -> Int in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            var total = 0
            while total < buffer.count {
                let readCount = Darwin.read(
                    descriptor,
                    baseAddress.advanced(by: total),
                    buffer.count - total
                )
                if readCount < 0 {
                    if errno == EINTR { continue }
                    throw currentPOSIXError()
                }
                if readCount == 0 { break }
                total += readCount
            }
            return total
        }
        if count < result.count {
            result.removeSubrange(count..<result.count)
        }
        return result
    }

    private static func regularFileStatus(_ descriptor: Int32) throws -> stat {
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0 else { throw currentPOSIXError() }
        guard (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw POSIXError(.EINVAL)
        }
        return status
    }

    private static func validateRegularFile(_ descriptor: Int32) throws {
        _ = try regularFileStatus(descriptor)
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var total = 0
            while total < buffer.count {
                let writeCount = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: total),
                    buffer.count - total
                )
                if writeCount < 0 {
                    if errno == EINTR { continue }
                    throw currentPOSIXError()
                }
                guard writeCount > 0 else { throw POSIXError(.EIO) }
                total += writeCount
            }
        }
    }

    private static func currentPOSIXError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

struct MapofAgentsCredentialRegistrySnapshot: Codable, Sendable {
    static let currentVersion = 1

    var version: Int = currentVersion
    var pendingEnrollments: [PendingEnrollment] = []
    var devices: [Device] = []

    struct PendingEnrollment: Codable, Sendable {
        var tokenHash: String
        var createdAt: Date
        var expiresAt: Date
    }

    struct Device: Codable, Sendable {
        var id: String
        var name: String
        var refreshCredentialHash: String
        var enrollmentTokenHash: String?
        var createdAt: Date
        var lastRefreshedAt: Date
        var revokedAt: Date?
    }
}

final class MapofAgentsCredentialRegistry: @unchecked Sendable {
    // A gateway JWT identifies a device by its stable ID. Keep revoked IDs
    // reserved until every access token issued for that identity must have
    // expired, otherwise re-enrolling the ID could resurrect an old token.
    static let revokedDeviceIDRetention: TimeInterval =
        MapofAgentsCredentialExchangeHandler.accessTokenDuration + 30

    struct Limits: Sendable {
        var pendingEnrollments: Int
        var devices: Int

        static let `default` = Limits(pendingEnrollments: 16, devices: 32)
    }

    struct Registration: Sendable {
        var deviceID: String
        var refreshCredential: String
    }

    private let fileURL: URL
    private let limits: Limits
    private let lock = NSLock()
    private var snapshot: MapofAgentsCredentialRegistrySnapshot

    init(fileURL: URL, limits: Limits = .default) throws {
        self.fileURL = fileURL
        self.limits = Limits(
            pendingEnrollments: max(1, limits.pendingEnrollments),
            devices: max(1, limits.devices)
        )
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .mapofagentsCredentialExchangeISO8601
            snapshot = try decoder.decode(
                MapofAgentsCredentialRegistrySnapshot.self,
                from: MapofAgentsPrivateFile.read(fileURL, maximumBytes: 1_048_576)
            )
            try Self.restrictPermissions(of: fileURL)
        } else {
            snapshot = MapofAgentsCredentialRegistrySnapshot()
        }
    }

    func issueEnrollment(
        expiresAt: Date,
        now: Date = Date(),
        token: String = MapofAgentsCredentialSecrets.randomCredential()
    ) throws -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, expiresAt > now else {
            throw MapofAgentsCredentialExchangeError.invalidRequest
        }
        return try lock.withLock {
            pruneExpiredEnrollments(now: now)
            while snapshot.pendingEnrollments.count >= limits.pendingEnrollments {
                snapshot.pendingEnrollments.removeFirst()
            }
            let tokenHash = MapofAgentsCredentialSecrets.hash(trimmed)
            snapshot.pendingEnrollments.removeAll { $0.tokenHash == tokenHash }
            snapshot.pendingEnrollments.append(
                .init(tokenHash: tokenHash, createdAt: now, expiresAt: expiresAt)
            )
            try persistLocked()
            return trimmed
        }
    }

    func registerDevice(
        enrollmentToken: String,
        deviceName: String,
        now: Date = Date(),
        deviceID: String = UUID().uuidString.lowercased(),
        refreshCredential: String = MapofAgentsCredentialSecrets.randomCredential()
    ) throws -> Registration {
        try lock.withLock {
            pruneExpiredDeviceTombstones(now: now)
            let tokenHash = MapofAgentsCredentialSecrets.hash(enrollmentToken)
            let normalizedDeviceID = String(
                deviceID.trimmingCharacters(in: .whitespacesAndNewlines).prefix(128)
            )
            let normalizedCredential = refreshCredential.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedDeviceID.isEmpty, !normalizedCredential.isEmpty else {
                throw MapofAgentsCredentialExchangeError.invalidRequest
            }

            if let existing = snapshot.devices.first(where: {
                $0.id == normalizedDeviceID
                    && $0.enrollmentTokenHash.map {
                        MapofAgentsCredentialSecrets.constantTimeEqual($0, tokenHash)
                    } == true
            }) {
                guard existing.revokedAt == nil else {
                    throw MapofAgentsCredentialExchangeError.deviceRevoked
                }
                guard MapofAgentsCredentialSecrets.constantTimeEqual(
                    existing.refreshCredentialHash,
                    MapofAgentsCredentialSecrets.hash(normalizedCredential)
                ) else {
                    throw MapofAgentsCredentialExchangeError.enrollmentInvalid
                }
                return Registration(
                    deviceID: normalizedDeviceID,
                    refreshCredential: normalizedCredential
                )
            }

            // Device IDs are client-selected so the iPhone can keep a stable
            // Keychain identity. A different enrollment must never seize an
            // active identity or reuse a revoked identity while an access
            // token for that subject could still be valid.
            if snapshot.devices.contains(where: { $0.id == normalizedDeviceID }) {
                throw MapofAgentsCredentialExchangeError.enrollmentInvalid
            }

            guard let enrollmentIndex = snapshot.pendingEnrollments.firstIndex(where: {
                MapofAgentsCredentialSecrets.constantTimeEqual($0.tokenHash, tokenHash)
            }) else {
                throw MapofAgentsCredentialExchangeError.enrollmentInvalid
            }
            guard snapshot.pendingEnrollments[enrollmentIndex].expiresAt > now else {
                snapshot.pendingEnrollments.remove(at: enrollmentIndex)
                try persistLocked()
                throw MapofAgentsCredentialExchangeError.enrollmentExpired
            }

            // Retained revocation tombstones count toward the configured
            // bound. Prefer a temporary registry-full response over dropping
            // an identity while one of its signed tokens can still be valid.
            guard snapshot.devices.count < limits.devices else {
                throw MapofAgentsCredentialExchangeError.registryFull
            }

            snapshot.pendingEnrollments.remove(at: enrollmentIndex)
            snapshot.devices.append(
                .init(
                    id: normalizedDeviceID,
                    name: String(deviceName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(128)),
                    refreshCredentialHash: MapofAgentsCredentialSecrets.hash(normalizedCredential),
                    enrollmentTokenHash: tokenHash,
                    createdAt: now,
                    lastRefreshedAt: now,
                    revokedAt: nil
                )
            )
            try persistLocked()
            return Registration(
                deviceID: normalizedDeviceID,
                refreshCredential: normalizedCredential
            )
        }
    }

    func validateRefreshCredential(
        deviceID: String,
        refreshCredential: String,
        now: Date = Date()
    ) throws {
        try lock.withLock {
            guard let index = snapshot.devices.firstIndex(where: { $0.id == deviceID }) else {
                throw MapofAgentsCredentialExchangeError.refreshCredentialInvalid
            }
            guard snapshot.devices[index].revokedAt == nil else {
                throw MapofAgentsCredentialExchangeError.deviceRevoked
            }
            let actualHash = MapofAgentsCredentialSecrets.hash(refreshCredential)
            guard MapofAgentsCredentialSecrets.constantTimeEqual(
                snapshot.devices[index].refreshCredentialHash,
                actualHash
            ) else {
                throw MapofAgentsCredentialExchangeError.refreshCredentialInvalid
            }
            snapshot.devices[index].lastRefreshedAt = now
            try persistLocked()
        }
    }

    func revoke(
        deviceID: String,
        refreshCredential: String,
        now: Date = Date()
    ) throws {
        try lock.withLock {
            guard let index = snapshot.devices.firstIndex(where: { $0.id == deviceID }) else {
                throw MapofAgentsCredentialExchangeError.refreshCredentialInvalid
            }
            let actualHash = MapofAgentsCredentialSecrets.hash(refreshCredential)
            guard MapofAgentsCredentialSecrets.constantTimeEqual(
                snapshot.devices[index].refreshCredentialHash,
                actualHash
            ) else {
                throw MapofAgentsCredentialExchangeError.refreshCredentialInvalid
            }
            guard snapshot.devices[index].revokedAt == nil else {
                return
            }
            snapshot.devices[index].revokedAt = now
            try persistLocked()
        }
    }

    func activeDeviceSummaries() -> [MapofAgentsPairedDeviceSummary] {
        lock.withLock {
            snapshot.devices
                .filter { $0.revokedAt == nil }
                .map {
                    MapofAgentsPairedDeviceSummary(
                        id: $0.id,
                        name: $0.name.isEmpty ? "iPhone" : $0.name,
                        createdAt: $0.createdAt,
                        lastRefreshedAt: $0.lastRefreshedAt
                    )
                }
                .sorted { $0.lastRefreshedAt > $1.lastRefreshedAt }
        }
    }

    func isDeviceActive(deviceID: String) -> Bool {
        lock.withLock {
            snapshot.devices.contains { $0.id == deviceID && $0.revokedAt == nil }
        }
    }

    func revokeDevice(deviceID: String, now: Date = Date()) throws {
        try lock.withLock {
            guard let index = snapshot.devices.firstIndex(where: { $0.id == deviceID }) else {
                throw MapofAgentsCredentialExchangeError.refreshCredentialInvalid
            }
            guard snapshot.devices[index].revokedAt == nil else { return }
            snapshot.devices[index].revokedAt = now
            try persistLocked()
        }
    }

    func snapshotForTesting() -> MapofAgentsCredentialRegistrySnapshot {
        lock.withLock { snapshot }
    }

    private func pruneExpiredEnrollments(now: Date) {
        snapshot.pendingEnrollments.removeAll { $0.expiresAt <= now }
    }

    private func pruneExpiredDeviceTombstones(now: Date) {
        snapshot.devices.removeAll { device in
            guard let revokedAt = device.revokedAt else { return false }
            return now.timeIntervalSince(revokedAt) >= Self.revokedDeviceIDRetention
        }
    }

    private func persistLocked() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try MapofAgentsPrivateFile.write(encoder.encode(snapshot), to: fileURL)
    }

    private static func restrictPermissions(of url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}

enum MapofAgentsCredentialSecrets {
    static func randomCredential(byteCount: Int = 32) -> String {
        var generator = SystemRandomNumberGenerator()
        let data = Data((0..<max(16, byteCount)).map { _ in
            UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
        })
        return data.mapofagentsBase64URLEncodedString()
    }

    static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let lhsBytes = Array(lhs.utf8)
        let rhsBytes = Array(rhs.utf8)
        guard lhsBytes.count == rhsBytes.count else { return false }
        var difference: UInt8 = 0
        for index in lhsBytes.indices {
            difference |= lhsBytes[index] ^ rhsBytes[index]
        }
        return difference == 0
    }
}

final class MapofAgentsCredentialExchangeHandler: @unchecked Sendable {
    static let accessTokenDuration: TimeInterval = 5 * 60

    private let lock = NSLock()
    private let registry: MapofAgentsCredentialRegistry
    private let hostID: HostID
    private let sharedSecretURL: URL
    private let now: @Sendable () -> Date
    private let onDeviceRevoked: @Sendable (String) -> Void
    private var endpoints: [MapofAgentsPairingEndpoint]
    private var supportDirectory: String?

    init(
        registry: MapofAgentsCredentialRegistry,
        hostID: HostID,
        sharedSecretURL: URL,
        endpoints: [MapofAgentsPairingEndpoint],
        supportDirectory: String?,
        now: @escaping @Sendable () -> Date = Date.init,
        onDeviceRevoked: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.registry = registry
        self.hostID = hostID
        self.sharedSecretURL = sharedSecretURL
        self.endpoints = endpoints
        self.supportDirectory = supportDirectory
        self.now = now
        self.onDeviceRevoked = onDeviceRevoked
    }

    func update(
        endpoints: [MapofAgentsPairingEndpoint],
        supportDirectory: String?
    ) {
        lock.withLock {
            self.endpoints = endpoints
            self.supportDirectory = supportDirectory
        }
    }

    func issueEnrollment(expiresAt: Date) throws -> String {
        try registry.issueEnrollment(expiresAt: expiresAt, now: now())
    }

    func enroll(_ request: MapofAgentsEnrollmentRequest) throws -> MapofAgentsEnrollmentResponse {
        let issuedAt = now()
        let registration = try registry.registerDevice(
            enrollmentToken: request.enrollmentToken,
            deviceName: request.deviceName,
            now: issuedAt,
            deviceID: request.deviceID,
            refreshCredential: request.refreshCredential
        )
        let expiresAt = issuedAt.addingTimeInterval(Self.accessTokenDuration)
        let accessToken = try makeAccessToken(deviceID: registration.deviceID, issuedAt: issuedAt, expiresAt: expiresAt)
        let configuration = lock.withLock { (endpoints, supportDirectory) }
        return MapofAgentsEnrollmentResponse(
            hostID: hostID,
            deviceID: registration.deviceID,
            refreshCredential: registration.refreshCredential,
            accessToken: accessToken,
            accessTokenExpiresAt: expiresAt,
            endpoints: configuration.0,
            mapofagentsSupportDirectory: configuration.1
        )
    }

    func refresh(_ request: MapofAgentsRefreshRequest) throws -> MapofAgentsRefreshResponse {
        guard request.hostID == hostID else {
            throw MapofAgentsCredentialExchangeError.hostMismatch
        }
        let issuedAt = now()
        try registry.validateRefreshCredential(
            deviceID: request.deviceID,
            refreshCredential: request.refreshCredential,
            now: issuedAt
        )
        let expiresAt = issuedAt.addingTimeInterval(Self.accessTokenDuration)
        return MapofAgentsRefreshResponse(
            accessToken: try makeAccessToken(
                deviceID: request.deviceID,
                issuedAt: issuedAt,
                expiresAt: expiresAt
            ),
            accessTokenExpiresAt: expiresAt
        )
    }

    func revoke(_ request: MapofAgentsRefreshRequest) throws -> MapofAgentsRevokeResponse {
        guard request.hostID == hostID else {
            throw MapofAgentsCredentialExchangeError.hostMismatch
        }
        try registry.revoke(
            deviceID: request.deviceID,
            refreshCredential: request.refreshCredential,
            now: now()
        )
        onDeviceRevoked(request.deviceID)
        return MapofAgentsRevokeResponse(revoked: true)
    }

    func activeDeviceSummaries() -> [MapofAgentsPairedDeviceSummary] {
        registry.activeDeviceSummaries()
    }

    func revokeDevice(deviceID: String) throws {
        try registry.revokeDevice(deviceID: deviceID, now: now())
        onDeviceRevoked(deviceID)
    }

    private func makeAccessToken(deviceID: String, issuedAt: Date, expiresAt: Date) throws -> String {
        guard let secretText = try String(
            data: MapofAgentsPrivateFile.read(sharedSecretURL, maximumBytes: 4_096),
            encoding: .utf8
        ) else {
            throw MapofAgentsCredentialExchangeError.listenerFailed("The host signing secret is not UTF-8.")
        }
        let secret = secretText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else {
            throw MapofAgentsCredentialExchangeError.listenerFailed("The host signing secret is empty.")
        }
        return try MapofAgentsMacPairingService.signedBearerToken(
            secret: secret,
            subject: "mapofagents-device:\(deviceID)",
            expiresAt: expiresAt,
            issuedAt: issuedAt
        )
    }
}

struct MapofAgentsCredentialExchangeHTTPRequest: Sendable {
    var method: String
    var path: String
    var body: Data
}

struct MapofAgentsCredentialExchangeHTTPResponse: Sendable {
    var status: Int
    var body: Data
}

final class MapofAgentsCredentialExchangeHTTPRouter: @unchecked Sendable {
    private let handler: MapofAgentsCredentialExchangeHandler

    init(handler: MapofAgentsCredentialExchangeHandler) {
        self.handler = handler
    }

    func route(_ request: MapofAgentsCredentialExchangeHTTPRequest) -> MapofAgentsCredentialExchangeHTTPResponse {
        guard request.method == "POST" else {
            return errorResponse(status: 405, message: "Only POST requests are supported.")
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .mapofagentsCredentialExchangeISO8601
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            switch request.path {
            case "/v1/pairing/enroll":
                return .init(
                    status: 200,
                    body: try encoder.encode(handler.enroll(try decoder.decode(MapofAgentsEnrollmentRequest.self, from: request.body)))
                )
            case "/v1/pairing/refresh":
                return .init(
                    status: 200,
                    body: try encoder.encode(handler.refresh(try decoder.decode(MapofAgentsRefreshRequest.self, from: request.body)))
                )
            case "/v1/pairing/revoke":
                return .init(
                    status: 200,
                    body: try encoder.encode(handler.revoke(try decoder.decode(MapofAgentsRefreshRequest.self, from: request.body)))
                )
            default:
                return errorResponse(status: 404, message: "Credential exchange route not found.")
            }
        } catch let error as MapofAgentsCredentialExchangeError {
            switch error {
            case .enrollmentInvalid, .enrollmentExpired:
                return errorResponse(status: 410, message: error.localizedDescription)
            case .refreshCredentialInvalid, .deviceRevoked:
                return errorResponse(status: 401, message: error.localizedDescription)
            case .hostMismatch:
                return errorResponse(status: 409, message: error.localizedDescription)
            case .registryFull:
                return errorResponse(status: 429, message: error.localizedDescription)
            case .listenerFailed:
                return errorResponse(status: 500, message: error.localizedDescription)
            default:
                return errorResponse(status: 400, message: error.localizedDescription)
            }
        } catch {
            return errorResponse(status: 400, message: MapofAgentsCredentialExchangeError.invalidRequest.localizedDescription)
        }
    }

    private func errorResponse(status: Int, message: String) -> MapofAgentsCredentialExchangeHTTPResponse {
        let data = (try? JSONEncoder().encode(ErrorEnvelope(error: message))) ?? Data("{}".utf8)
        return .init(status: status, body: data)
    }
}

protocol MapofAgentsCredentialExchangeListening: AnyObject, Sendable {
    var isReady: Bool { get }
    func start(router: MapofAgentsCredentialExchangeHTTPRouter) async throws
    func stop() async
}

final class MapofAgentsNetworkCredentialExchangeListener: MapofAgentsCredentialExchangeListening, @unchecked Sendable {
    static let maximumRequestBytes = 32 * 1_024
    static let defaultMaximumConnections = 64
    static let defaultRequestTimeout: TimeInterval = 5

    private let port: NWEndpoint.Port
    private let maximumConnections: Int
    private let requestTimeout: TimeInterval
    private let queue = DispatchQueue(label: "dev.mapofagents.credential-exchange")
    private let lock = NSLock()
    private var listener: NWListener?
    private var ready = false
    private var connections: [UUID: MapofAgentsCredentialExchangeHTTPConnection] = [:]
    private var isStopping = false
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []
    private var startState: ListenerStartState?

    var isReady: Bool {
        lock.withLock { ready }
    }

    init(
        port: UInt16,
        maximumConnections: Int = defaultMaximumConnections,
        requestTimeout: TimeInterval = defaultRequestTimeout
    ) throws {
        guard let port = NWEndpoint.Port(rawValue: port) else {
            throw MapofAgentsCredentialExchangeError.listenerFailed("Invalid loopback port.")
        }
        self.port = port
        self.maximumConnections = max(1, maximumConnections)
        self.requestTimeout = max(0.1, requestTimeout)
    }

    func start(router: MapofAgentsCredentialExchangeHTTPRouter) async throws {
        if isReady { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        // Never share the credential-exchange port with another local process;
        // Tailscale Serve forwards one-time enrollment and refresh credentials
        // here after terminating TLS.
        parameters.allowLocalEndpointReuse = false
        parameters.acceptLocalOnly = true
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw MapofAgentsCredentialExchangeError.listenerFailed(error.localizedDescription)
        }
        self.listener = listener

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let startState = ListenerStartState(continuation: continuation)
            self.startState = startState
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard self?.isStopping != true else {
                        listener.cancel()
                        return
                    }
                    self?.lock.withLock { self?.ready = true }
                    startState.succeed()
                    self?.startState = nil
                case .failed(let error), .waiting(let error):
                    self?.lock.withLock { self?.ready = false }
                    startState.fail(MapofAgentsCredentialExchangeError.listenerFailed(error.localizedDescription))
                    self?.startState = nil
                case .cancelled:
                    self?.lock.withLock { self?.ready = false }
                    startState.fail(MapofAgentsCredentialExchangeError.listenerFailed("The listener was cancelled."))
                    self?.startState = nil
                    self?.completeStop()
                case .setup:
                    break
                @unknown default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection, router: router)
            }
            listener.start(queue: queue)
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                guard listener != nil else {
                    closeAllConnections()
                    continuation.resume()
                    return
                }
                stopWaiters.append(continuation)
                isStopping = true
                lock.withLock { ready = false }
                closeAllConnections()
                listener?.cancel()
                queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, isStopping else { return }
                    completeStop()
                }
            }
        }
    }

    private func accept(
        _ connection: NWConnection,
        router: MapofAgentsCredentialExchangeHTTPRouter
    ) {
        guard isReady, !isStopping, connections.count < maximumConnections else {
            connection.cancel()
            return
        }
        let id = UUID()
        let session = MapofAgentsCredentialExchangeHTTPConnection(
            id: id,
            connection: connection,
            queue: queue,
            router: router,
            requestTimeout: requestTimeout,
            onClose: { [weak self] id in
                self?.connections[id] = nil
            }
        )
        connections[id] = session
        session.start()
    }

    private func closeAllConnections() {
        let active = Array(connections.values)
        connections.removeAll()
        active.forEach { $0.closeOnQueue() }
    }

    private func completeStop() {
        startState?.fail(CancellationError())
        startState = nil
        let listener = self.listener
        self.listener = nil
        listener?.newConnectionHandler = nil
        listener?.stateUpdateHandler = nil
        lock.withLock { ready = false }
        closeAllConnections()
        isStopping = false
        let waiters = stopWaiters
        stopWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private final class ListenerStartState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func succeed() {
        lock.withLock {
            continuation?.resume()
            continuation = nil
        }
    }

    func fail(_ error: Error) {
        lock.withLock {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

private final class MapofAgentsCredentialExchangeHTTPConnection: @unchecked Sendable {
    private let id: UUID
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let router: MapofAgentsCredentialExchangeHTTPRouter
    private let requestTimeout: TimeInterval
    private let onClose: @Sendable (UUID) -> Void
    private var buffer = Data()
    private var timeoutWorkItem: DispatchWorkItem?
    private var isClosed = false

    init(
        id: UUID,
        connection: NWConnection,
        queue: DispatchQueue,
        router: MapofAgentsCredentialExchangeHTTPRouter,
        requestTimeout: TimeInterval,
        onClose: @escaping @Sendable (UUID) -> Void
    ) {
        self.id = id
        self.connection = connection
        self.queue = queue
        self.router = router
        self.requestTimeout = requestTimeout
        self.onClose = onClose
    }

    func start() {
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            self?.finish()
        }
        self.timeoutWorkItem = timeoutWorkItem
        queue.asyncAfter(deadline: .now() + requestTimeout, execute: timeoutWorkItem)
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .ready:
                receiveNextChunk()
            case .failed, .cancelled:
                finish()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func closeOnQueue() {
        finish()
    }

    private func receiveNextChunk() {
        guard !isClosed else { return }
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: MapofAgentsNetworkCredentialExchangeListener.maximumRequestBytes
        ) { [weak self] data, _, isComplete, error in
            guard let self, !isClosed else { return }
            if let data, !data.isEmpty {
                buffer.append(data)
            }
            guard buffer.count <= MapofAgentsNetworkCredentialExchangeListener.maximumRequestBytes else {
                send(.init(status: 413, body: Data("{\"error\":\"Request too large.\"}".utf8)))
                return
            }
            switch Self.parseRequest(buffer) {
            case .complete(let request):
                send(router.route(request))
            case .incomplete where error == nil && !isComplete:
                receiveNextChunk()
            case .incomplete, .invalid:
                send(.init(status: 400, body: Data("{\"error\":\"Invalid request.\"}".utf8)))
            }
        }
    }

    private func send(_ response: MapofAgentsCredentialExchangeHTTPResponse) {
        let reason: String
        switch response.status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        case 409: reason = "Conflict"
        case 410: reason = "Gone"
        case 413: reason = "Content Too Large"
        case 429: reason = "Too Many Requests"
        case 500: reason = "Internal Server Error"
        default: reason = "Error"
        }
        var data = Data(
            "HTTP/1.1 \(response.status) \(reason)\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: \(response.body.count)\r\n\r\n".utf8
        )
        data.append(response.body)
        connection.send(content: data, completion: .contentProcessed { [weak self] _ in
            self?.finish()
        })
    }

    private func finish() {
        guard !isClosed else { return }
        isClosed = true
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        onClose(id)
    }

    private enum ParseResult {
        case incomplete
        case invalid
        case complete(MapofAgentsCredentialExchangeHTTPRequest)
    }

    private static func parseRequest(_ data: Data) -> ParseResult {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator) else {
            return .incomplete
        }
        guard let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
            return .invalid
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return .invalid }
        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count == 3,
              requestParts[2].hasPrefix("HTTP/1.") else {
            return .invalid
        }
        var contentLength: Int?
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if name == "content-length" {
                guard contentLength == nil, let length = Int(value), length >= 0 else {
                    return .invalid
                }
                contentLength = length
            }
            if name == "transfer-encoding" {
                return .invalid
            }
        }
        guard let contentLength,
              contentLength <= MapofAgentsNetworkCredentialExchangeListener.maximumRequestBytes else {
            return .invalid
        }
        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + contentLength else { return .incomplete }
        guard data.count == bodyStart + contentLength else { return .invalid }
        return .complete(
            .init(
                method: String(requestParts[0]).uppercased(),
                path: String(requestParts[1]),
                body: data.subdata(in: bodyStart..<(bodyStart + contentLength))
            )
        )
    }
}

actor MapofAgentsCredentialExchangeRuntime {
    typealias ListenerFactory = @Sendable (UInt16) throws -> any MapofAgentsCredentialExchangeListening

    static let shared = MapofAgentsCredentialExchangeRuntime()

    private let listenerFactory: ListenerFactory
    private var listener: (any MapofAgentsCredentialExchangeListening)?
    private var pendingListener: (any MapofAgentsCredentialExchangeListening)?
    private var handler: MapofAgentsCredentialExchangeHandler?
    private var configuration: Configuration?
    private var generation = 0

    private struct Configuration: Equatable {
        var port: UInt16
        var registryURL: URL
        var hostID: HostID
        var sharedSecretURL: URL
    }

    init(listenerFactory: @escaping ListenerFactory = { port in
        try MapofAgentsNetworkCredentialExchangeListener(port: port)
    }) {
        self.listenerFactory = listenerFactory
    }

    func ensureRunning(
        port: UInt16,
        registryURL: URL,
        hostID: HostID,
        sharedSecretURL: URL,
        endpoints: [MapofAgentsPairingEndpoint],
        supportDirectory: String?
    ) async throws {
        let next = Configuration(
            port: port,
            registryURL: registryURL,
            hostID: hostID,
            sharedSecretURL: sharedSecretURL
        )
        if configuration == next, listener?.isReady == true {
            handler?.update(endpoints: endpoints, supportDirectory: supportDirectory)
            return
        }

        generation &+= 1
        let operationGeneration = generation
        let previousListener = listener ?? pendingListener
        listener = nil
        pendingListener = nil
        handler = nil
        configuration = nil
        if let previousListener {
            await previousListener.stop()
        }
        guard generation == operationGeneration else {
            throw CancellationError()
        }

        let registry = try MapofAgentsCredentialRegistry(fileURL: registryURL)
        let handler = MapofAgentsCredentialExchangeHandler(
            registry: registry,
            hostID: hostID,
            sharedSecretURL: sharedSecretURL,
            endpoints: endpoints,
            supportDirectory: supportDirectory,
            onDeviceRevoked: { deviceID in
                Task {
                    await MapofAgentsPairingGatewayRuntime.shared.revoke(deviceID: deviceID)
                }
            }
        )
        let router = MapofAgentsCredentialExchangeHTTPRouter(handler: handler)
        let listener = try listenerFactory(port)
        pendingListener = listener
        do {
            try await listener.start(router: router)
            try Task.checkCancellation()
        } catch {
            if generation == operationGeneration {
                pendingListener = nil
            }
            await listener.stop()
            throw error
        }
        guard generation == operationGeneration else {
            await listener.stop()
            throw CancellationError()
        }
        pendingListener = nil
        self.handler = handler
        self.listener = listener
        configuration = next
    }

    func issueEnrollment(expiresAt: Date) throws -> String {
        guard let handler else {
            throw MapofAgentsCredentialExchangeError.listenerFailed("The exchange listener is not running.")
        }
        return try handler.issueEnrollment(expiresAt: expiresAt)
    }

    func activeDeviceSummariesIfRunning() -> [MapofAgentsPairedDeviceSummary]? {
        handler?.activeDeviceSummaries()
    }

    func revokeDeviceIfRunning(deviceID: String) throws -> Bool {
        guard let handler else { return false }
        try handler.revokeDevice(deviceID: deviceID)
        return true
    }

    func stop() async {
        generation &+= 1
        let activeListener = listener ?? pendingListener
        listener = nil
        pendingListener = nil
        handler = nil
        configuration = nil
        if let activeListener {
            await activeListener.stop()
        }
    }
}
#endif

private extension Data {
    func mapofagentsBase64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension JSONDecoder.DateDecodingStrategy {
    static let mapofagentsCredentialExchangeISO8601 = custom { decoder in
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        if let date = standard.date(from: value) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected an ISO 8601 date."
        )
    }
}
