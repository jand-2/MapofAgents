import CryptoKit
import Foundation

#if os(macOS)
import Network

enum MapofAgentsPairingGatewayError: LocalizedError, Equatable {
    case invalidHandshake
    case invalidAccessToken
    case accessTokenExpired
    case deviceRevoked
    case backendUnavailable
    case capacityExceeded
    case listenerFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidHandshake:
            return "The secure pairing gateway received an invalid WebSocket handshake."
        case .invalidAccessToken:
            return "The secure pairing gateway rejected the access token."
        case .accessTokenExpired:
            return "The secure pairing access token has expired."
        case .deviceRevoked:
            return "This paired device has been revoked."
        case .backendUnavailable:
            return "The owned Codex App Server backend is unavailable."
        case .capacityExceeded:
            return "The secure pairing gateway has reached its connection limit."
        case .listenerFailed(let message):
            return "The secure pairing gateway could not start: \(message)"
        }
    }
}

struct MapofAgentsPairingAccessTokenClaims: Equatable, Sendable {
    var deviceID: String
    var expiresAt: Date
}

/// Validates the device JWT before any credential is forwarded to Codex App
/// Server. The registry is reloaded for every handshake so revocations made by
/// the credential-exchange listener take effect for new connections even when
/// the two listeners do not share an in-memory registry instance.
struct MapofAgentsPairingAccessTokenValidator: Sendable {
    var sharedSecretURL: URL
    var registryURL: URL
    var expectedIssuer = "mapofagents"
    var expectedAudience = "codex-app-server"
    var clockSkew: TimeInterval = 5

    func validate(_ token: String, now: Date = Date()) throws -> MapofAgentsPairingAccessTokenClaims {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let headerData = Self.base64URLData(String(parts[0])),
              let payloadData = Self.base64URLData(String(parts[1])),
              let signature = Self.base64URLData(String(parts[2])),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              header["alg"] as? String == "HS256",
              header["typ"] as? String == "JWT",
              payload["iss"] as? String == expectedIssuer,
              payload["aud"] as? String == expectedAudience,
              let subject = payload["sub"] as? String,
              subject.hasPrefix("mapofagents-device:"),
              let expiresAtValue = Self.numericDate(payload["exp"]),
              let notBeforeValue = Self.numericDate(payload["nbf"]),
              let issuedAtValue = Self.numericDate(payload["iat"])
        else {
            throw MapofAgentsPairingGatewayError.invalidAccessToken
        }

        let signingInput = "\(parts[0]).\(parts[1])"
        guard let secretData = try? MapofAgentsPrivateFile.read(sharedSecretURL, maximumBytes: 4_096),
              let secretText = String(data: secretData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !secretText.isEmpty else {
            throw MapofAgentsPairingGatewayError.invalidAccessToken
        }
        let expectedSignature = Data(
            HMAC<SHA256>.authenticationCode(
                for: Data(signingInput.utf8),
                using: SymmetricKey(data: Data(secretText.utf8))
            )
        )
        guard Self.constantTimeEqual(signature, expectedSignature) else {
            throw MapofAgentsPairingGatewayError.invalidAccessToken
        }

        let expiresAt = Date(timeIntervalSince1970: expiresAtValue)
        guard expiresAt > now else {
            throw MapofAgentsPairingGatewayError.accessTokenExpired
        }
        let allowedFuture = now.addingTimeInterval(max(0, clockSkew)).timeIntervalSince1970
        guard notBeforeValue <= allowedFuture, issuedAtValue <= allowedFuture else {
            throw MapofAgentsPairingGatewayError.invalidAccessToken
        }

        let deviceID = String(subject.dropFirst("mapofagents-device:".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !deviceID.isEmpty, deviceID.count <= 128 else {
            throw MapofAgentsPairingGatewayError.invalidAccessToken
        }
        let registry = try MapofAgentsCredentialRegistry(fileURL: registryURL)
        guard registry.isDeviceActive(deviceID: deviceID) else {
            throw MapofAgentsPairingGatewayError.deviceRevoked
        }
        return MapofAgentsPairingAccessTokenClaims(deviceID: deviceID, expiresAt: expiresAt)
    }

    private static func numericDate(_ value: Any?) -> TimeInterval? {
        guard let number = value as? NSNumber else { return nil }
        return number.doubleValue
    }

    private static func base64URLData(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: base64)
    }

    private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { difference, pair in
            difference | (pair.0 ^ pair.1)
        } == 0
    }
}

enum MapofAgentsPairingGatewayHandshake {
    static let maximumBytes = 16 * 1_024

    static func bearerToken(in data: Data) throws -> String? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator) else {
            guard data.count <= maximumBytes else {
                throw MapofAgentsPairingGatewayError.invalidHandshake
            }
            return nil
        }
        guard headerRange.upperBound <= maximumBytes,
              let text = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
            throw MapofAgentsPairingGatewayError.invalidHandshake
        }
        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw MapofAgentsPairingGatewayError.invalidHandshake
        }
        let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count == 3,
              requestParts[0].uppercased() == "GET",
              requestParts[2].hasPrefix("HTTP/1.") else {
            throw MapofAgentsPairingGatewayError.invalidHandshake
        }

        var headers: [String: [String]] = [:]
        for line in lines.dropFirst() {
            guard !line.hasPrefix(" "), !line.hasPrefix("\t"),
                  let colon = line.firstIndex(of: ":") else {
                throw MapofAgentsPairingGatewayError.invalidHandshake
            }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !value.isEmpty else {
                throw MapofAgentsPairingGatewayError.invalidHandshake
            }
            headers[name, default: []].append(value)
        }

        guard headers["upgrade"]?.count == 1,
              headers["upgrade"]?.first?.lowercased() == "websocket",
              headers["connection"]?.joined(separator: ",").lowercased()
                .split(separator: ",")
                .map({ $0.trimmingCharacters(in: .whitespaces) })
                .contains("upgrade") == true,
              headers["sec-websocket-key"]?.count == 1,
              headers["authorization"]?.count == 1,
              let authorization = headers["authorization"]?.first else {
            throw MapofAgentsPairingGatewayError.invalidHandshake
        }
        let authorizationParts = authorization.split(separator: " ", omittingEmptySubsequences: true)
        guard authorizationParts.count == 2,
              authorizationParts[0].lowercased() == "bearer",
              !authorizationParts[1].isEmpty else {
            throw MapofAgentsPairingGatewayError.invalidHandshake
        }
        return String(authorizationParts[1])
    }
}

final class MapofAgentsPairingConnectionLease: @unchecked Sendable {
    private let lock = NSLock()
    private var expiryTask: Task<Void, Never>?

    func start(
        expiresAt: Date,
        onExpire: @escaping @Sendable () -> Void
    ) {
        let delay = max(0, expiresAt.timeIntervalSinceNow)
        let task = Task {
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            onExpire()
        }
        let previous = lock.withLock { () -> Task<Void, Never>? in
            defer { expiryTask = task }
            return expiryTask
        }
        previous?.cancel()
    }

    func cancel() {
        let task = lock.withLock { () -> Task<Void, Never>? in
            defer { expiryTask = nil }
            return expiryTask
        }
        task?.cancel()
    }

    deinit {
        cancel()
    }
}

protocol MapofAgentsPairingGatewayRevoking: AnyObject, Sendable {
    func revoke(deviceID: String)
}

enum MapofAgentsPairingGatewayRevocationFanout {
    static func revoke(
        deviceID: String,
        targets: [any MapofAgentsPairingGatewayRevoking]
    ) {
        targets.forEach { $0.revoke(deviceID: deviceID) }
    }
}

actor MapofAgentsPairingGatewayRuntime {
    static let shared = MapofAgentsPairingGatewayRuntime()

    private var listener: MapofAgentsNetworkPairingGateway?
    private var pendingListener: MapofAgentsNetworkPairingGateway?
    private var configuration: Configuration?
    private var generation = 0

    private struct Configuration: Equatable {
        var listenPort: UInt16
        var backendPort: UInt16
        var sharedSecretURL: URL
        var registryURL: URL
        var handshakeTimeout: TimeInterval
    }

    func ensureRunning(
        listenPort: UInt16,
        backendPort: UInt16,
        sharedSecretURL: URL,
        registryURL: URL,
        backendIsOwned: @escaping @Sendable () -> Bool,
        onListenerFailure: @escaping @Sendable () -> Void,
        handshakeTimeout: TimeInterval = 5
    ) async throws {
        let next = Configuration(
            listenPort: listenPort,
            backendPort: backendPort,
            sharedSecretURL: sharedSecretURL,
            registryURL: registryURL,
            handshakeTimeout: max(0.1, handshakeTimeout)
        )
        if configuration == next, listener?.isReady == true {
            return
        }

        generation &+= 1
        let operationGeneration = generation
        let previousListener = listener ?? pendingListener
        listener = nil
        pendingListener = nil
        configuration = nil
        if let previousListener {
            await previousListener.stop()
        }
        guard generation == operationGeneration else {
            throw CancellationError()
        }

        let guardedFailure: @Sendable () -> Void = { [weak self] in
            Task {
                await self?.handleListenerFailure(
                    generation: operationGeneration,
                    action: onListenerFailure
                )
            }
        }
        let listener = try MapofAgentsNetworkPairingGateway(
            listenPort: listenPort,
            backendPort: backendPort,
            validator: MapofAgentsPairingAccessTokenValidator(
                sharedSecretURL: sharedSecretURL,
                registryURL: registryURL
            ),
            backendIsOwned: backendIsOwned,
            onListenerFailure: guardedFailure,
            handshakeTimeout: next.handshakeTimeout
        )
        pendingListener = listener
        do {
            try await listener.start()
            try Task.checkCancellation()
        } catch {
            if generation == operationGeneration, pendingListener === listener {
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
        self.listener = listener
        configuration = next
    }

    func revoke(deviceID: String) {
        let targets: [any MapofAgentsPairingGatewayRevoking] = [listener, pendingListener]
            .compactMap { $0 }
        MapofAgentsPairingGatewayRevocationFanout.revoke(
            deviceID: deviceID,
            targets: targets
        )
    }

    func stop() async {
        generation &+= 1
        let activeListener = listener ?? pendingListener
        listener = nil
        pendingListener = nil
        configuration = nil
        if let activeListener {
            await activeListener.stop()
        }
    }

    private func handleListenerFailure(
        generation: Int,
        action: @escaping @Sendable () -> Void
    ) {
        guard self.generation == generation else { return }
        action()
    }
}

private final class MapofAgentsNetworkPairingGateway: MapofAgentsPairingGatewayRevoking, @unchecked Sendable {
    private static let maximumConnections = 64
    private static let maximumConnectionsPerDevice = 4

    private let listenPort: NWEndpoint.Port
    private let backendPort: NWEndpoint.Port
    private let validator: MapofAgentsPairingAccessTokenValidator
    private let backendIsOwned: @Sendable () -> Bool
    private let onListenerFailure: @Sendable () -> Void
    private let handshakeTimeout: TimeInterval
    private let queue = DispatchQueue(label: "dev.mapofagents.pairing-gateway")
    private let ownershipQueue = DispatchQueue(label: "dev.mapofagents.pairing-gateway.ownership")
    private let stateLock = NSLock()
    private var listener: NWListener?
    private var ready = false
    private var sessions: [UUID: MapofAgentsPairingGatewayConnection] = [:]
    private var isStopping = false
    private var didNotifyFailure = false
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []
    private var startState: MapofAgentsPairingGatewayListenerStartState?

    var isReady: Bool {
        stateLock.withLock { ready }
    }

    init(
        listenPort: UInt16,
        backendPort: UInt16,
        validator: MapofAgentsPairingAccessTokenValidator,
        backendIsOwned: @escaping @Sendable () -> Bool,
        onListenerFailure: @escaping @Sendable () -> Void,
        handshakeTimeout: TimeInterval
    ) throws {
        guard let listenPort = NWEndpoint.Port(rawValue: listenPort),
              let backendPort = NWEndpoint.Port(rawValue: backendPort) else {
            throw MapofAgentsPairingGatewayError.listenerFailed("Invalid loopback port.")
        }
        self.listenPort = listenPort
        self.backendPort = backendPort
        self.validator = validator
        self.backendIsOwned = backendIsOwned
        self.onListenerFailure = onListenerFailure
        self.handshakeTimeout = handshakeTimeout
    }

    func start() async throws {
        if isReady { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: listenPort)
        parameters.allowLocalEndpointReuse = false
        parameters.acceptLocalOnly = true
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            onListenerFailure()
            throw MapofAgentsPairingGatewayError.listenerFailed(error.localizedDescription)
        }
        stateLock.withLock { self.listener = listener }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let startState = MapofAgentsPairingGatewayListenerStartState(continuation: continuation)
            self.startState = startState
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    guard !isStopping else {
                        listener.cancel()
                        return
                    }
                    stateLock.withLock { ready = true }
                    scheduleBackendHealthCheck()
                    startState.succeed()
                    self.startState = nil
                case .failed(let error), .waiting(let error):
                    failClosed()
                    startState.fail(MapofAgentsPairingGatewayError.listenerFailed(error.localizedDescription))
                    self.startState = nil
                case .cancelled:
                    stateLock.withLock { ready = false }
                    closeAllSessions()
                    if !isStopping {
                        notifyFailureOnce()
                    }
                    startState.fail(MapofAgentsPairingGatewayError.listenerFailed("The listener was cancelled."))
                    self.startState = nil
                    completeStop()
                case .setup:
                    break
                @unknown default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] client in
                self?.accept(client)
            }
            listener.start(queue: queue)
        }
    }

    func revoke(deviceID: String) {
        queue.async { [weak self] in
            guard let self else { return }
            let matching = sessions.values.filter { $0.deviceID == deviceID }
            matching.forEach { $0.closeOnQueue() }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                guard stateLock.withLock({ listener != nil }) else {
                    closeAllSessions()
                    continuation.resume()
                    return
                }
                stopWaiters.append(continuation)
                isStopping = true
                stateLock.withLock { ready = false }
                closeAllSessions()
                stateLock.withLock { listener }?.cancel()
                queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self, isStopping else { return }
                    completeStop()
                }
            }
        }
    }

    private func accept(_ client: NWConnection) {
        guard isReady, !isStopping, sessions.count < Self.maximumConnections else {
            client.cancel()
            return
        }
        let id = UUID()
        let session = MapofAgentsPairingGatewayConnection(
            id: id,
            client: client,
            backendPort: backendPort,
            validator: validator,
            verifyBackendOwnership: { [weak self] completion in
                self?.verifyBackendOwnership(completion)
            },
            queue: queue,
            handshakeTimeout: handshakeTimeout,
            authorizeDevice: { [weak self] id, deviceID in
                guard let self, sessions[id] != nil else { return false }
                return sessions.values.count { $0.id != id && $0.deviceID == deviceID }
                    < Self.maximumConnectionsPerDevice
            },
            onClose: { [weak self] id in
                self?.sessions[id] = nil
            }
        )
        sessions[id] = session
        session.start()
    }

    private func scheduleBackendHealthCheck() {
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, isReady else { return }
            verifyBackendOwnership { [weak self] isOwned in
                guard let self, isReady, !isStopping else { return }
                guard isOwned else {
                    failClosed()
                    return
                }
                scheduleBackendHealthCheck()
            }
        }
    }

    private func verifyBackendOwnership(
        _ completion: @escaping @Sendable (Bool) -> Void
    ) {
        ownershipQueue.async { [weak self] in
            guard let self else { return }
            let isOwned = backendIsOwned()
            queue.async { [weak self] in
                guard self != nil else { return }
                completion(isOwned)
            }
        }
    }

    private func failClosed() {
        stateLock.withLock { ready = false }
        closeAllSessions()
        notifyFailureOnce()
        stateLock.withLock { listener }?.cancel()
    }

    private func notifyFailureOnce() {
        guard !didNotifyFailure else { return }
        didNotifyFailure = true
        onListenerFailure()
    }

    private func closeAllSessions() {
        let activeSessions = Array(sessions.values)
        sessions.removeAll()
        activeSessions.forEach { $0.closeOnQueue() }
    }

    private func completeStop() {
        startState?.fail(CancellationError())
        startState = nil
        let listener = stateLock.withLock { () -> NWListener? in
            ready = false
            defer { self.listener = nil }
            return self.listener
        }
        listener?.newConnectionHandler = nil
        listener?.stateUpdateHandler = nil
        closeAllSessions()
        isStopping = false
        let waiters = stopWaiters
        stopWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private final class MapofAgentsPairingGatewayListenerStartState: @unchecked Sendable {
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

private final class MapofAgentsPairingGatewayConnection: @unchecked Sendable {
    let id: UUID
    private(set) var deviceID: String?

    private let client: NWConnection
    private let backendPort: NWEndpoint.Port
    private let validator: MapofAgentsPairingAccessTokenValidator
    private let verifyBackendOwnership: @Sendable (@escaping @Sendable (Bool) -> Void) -> Void
    private let queue: DispatchQueue
    private let handshakeTimeout: TimeInterval
    private let authorizeDevice: @Sendable (UUID, String) -> Bool
    private let onClose: @Sendable (UUID) -> Void
    private var backend: NWConnection?
    private var handshakeBuffer = Data()
    private let connectionLease = MapofAgentsPairingConnectionLease()
    private let handshakeLease = MapofAgentsPairingConnectionLease()
    private var isClosed = false

    init(
        id: UUID,
        client: NWConnection,
        backendPort: NWEndpoint.Port,
        validator: MapofAgentsPairingAccessTokenValidator,
        verifyBackendOwnership: @escaping @Sendable (@escaping @Sendable (Bool) -> Void) -> Void,
        queue: DispatchQueue,
        handshakeTimeout: TimeInterval,
        authorizeDevice: @escaping @Sendable (UUID, String) -> Bool,
        onClose: @escaping @Sendable (UUID) -> Void
    ) {
        self.id = id
        self.client = client
        self.backendPort = backendPort
        self.validator = validator
        self.verifyBackendOwnership = verifyBackendOwnership
        self.queue = queue
        self.handshakeTimeout = handshakeTimeout
        self.authorizeDevice = authorizeDevice
        self.onClose = onClose
    }

    func start() {
        handshakeLease.start(expiresAt: Date().addingTimeInterval(handshakeTimeout)) { [weak self] in
            self?.close()
        }
        client.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                receiveHandshake()
            case .failed, .waiting, .cancelled:
                finish()
            case .setup, .preparing:
                break
            @unknown default:
                finish()
            }
        }
        client.start(queue: queue)
    }

    func close() {
        queue.async { [weak self] in
            self?.finish()
        }
    }

    func closeOnQueue() {
        finish()
    }

    private func receiveHandshake() {
        guard !isClosed else { return }
        client.receive(
            minimumIncompleteLength: 1,
            maximumLength: MapofAgentsPairingGatewayHandshake.maximumBytes
        ) { [weak self] data, _, isComplete, error in
            guard let self, !isClosed else { return }
            if let data, !data.isEmpty {
                handshakeBuffer.append(data)
            }
            if let error {
                sendHTTPError(status: 400, message: error.localizedDescription)
                return
            }
            do {
                guard let token = try MapofAgentsPairingGatewayHandshake.bearerToken(in: handshakeBuffer) else {
                    guard !isComplete else {
                        throw MapofAgentsPairingGatewayError.invalidHandshake
                    }
                    receiveHandshake()
                    return
                }
                let claims = try validator.validate(token)
                // Tag the connection before the asynchronous ownership probe
                // so an immediate device revocation can close an in-flight
                // authenticated handshake as well as a promoted session.
                deviceID = claims.deviceID
                verifyBackendOwnership { [weak self] isOwned in
                    guard let self, !isClosed else { return }
                    guard isOwned else {
                        sendHTTPError(
                            status: 503,
                            message: MapofAgentsPairingGatewayError.backendUnavailable.localizedDescription
                        )
                        return
                    }
                    do {
                        // Registry revocation can happen while the ownership
                        // probe is off-queue. Revalidate before opening Codex.
                        let currentClaims = try validator.validate(token)
                        guard currentClaims.deviceID == claims.deviceID else {
                            throw MapofAgentsPairingGatewayError.invalidAccessToken
                        }
                        guard authorizeDevice(id, currentClaims.deviceID) else {
                            sendHTTPError(
                                status: 503,
                                message: MapofAgentsPairingGatewayError.capacityExceeded.localizedDescription
                            )
                            return
                        }
                        handshakeLease.cancel()
                        scheduleExpiry(currentClaims.expiresAt)
                        connectBackend(initialHandshake: handshakeBuffer)
                    } catch let error as MapofAgentsPairingGatewayError {
                        sendHTTPError(status: 401, message: error.localizedDescription)
                    } catch {
                        sendHTTPError(status: 401, message: "Unauthorized")
                    }
                }
            } catch let error as MapofAgentsPairingGatewayError {
                let status = error == .backendUnavailable || error == .capacityExceeded ? 503 : 401
                sendHTTPError(status: status, message: error.localizedDescription)
            } catch {
                sendHTTPError(status: 401, message: "Unauthorized")
            }
        }
    }

    private func connectBackend(initialHandshake: Data) {
        guard !isClosed else { return }
        let backend = NWConnection(host: "127.0.0.1", port: backendPort, using: .tcp)
        self.backend = backend
        backend.stateUpdateHandler = { [weak self] state in
            guard let self, !isClosed else { return }
            switch state {
            case .ready:
                verifyBackendOwnership { [weak self] isOwned in
                    guard let self, !isClosed else { return }
                    guard isOwned else {
                        sendHTTPError(
                            status: 503,
                            message: MapofAgentsPairingGatewayError.backendUnavailable.localizedDescription
                        )
                        return
                    }
                    pump(from: backend, to: client)
                    backend.send(content: initialHandshake, completion: .contentProcessed { [weak self] error in
                        guard let self else { return }
                        if error == nil {
                            pump(from: client, to: backend)
                        } else {
                            finish()
                        }
                    })
                }
            case .failed, .waiting, .cancelled:
                sendHTTPError(status: 503, message: MapofAgentsPairingGatewayError.backendUnavailable.localizedDescription)
            case .setup, .preparing:
                break
            @unknown default:
                finish()
            }
        }
        backend.start(queue: queue)
    }

    private func pump(from source: NWConnection, to destination: NWConnection) {
        guard !isClosed else { return }
        source.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) { [weak self] data, _, isComplete, error in
            guard let self, !isClosed else { return }
            guard error == nil, !isComplete else {
                finish()
                return
            }
            guard let data, !data.isEmpty else {
                pump(from: source, to: destination)
                return
            }
            destination.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let self else { return }
                if error == nil {
                    pump(from: source, to: destination)
                } else {
                    finish()
                }
            })
        }
    }

    private func scheduleExpiry(_ expiresAt: Date) {
        connectionLease.start(expiresAt: expiresAt) { [weak self] in
            self?.close()
        }
    }

    private func sendHTTPError(status: Int, message: String) {
        guard !isClosed else { return }
        let safeMessage = message
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let body = Data("{\"error\":\"\(safeMessage)\"}".utf8)
        let reason = status == 503 ? "Service Unavailable" : "Unauthorized"
        var response = Data(
            "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: \(body.count)\r\n\r\n".utf8
        )
        response.append(body)
        client.send(content: response, completion: .contentProcessed { [weak self] _ in
            self?.finish()
        })
    }

    private func finish() {
        guard !isClosed else { return }
        isClosed = true
        handshakeLease.cancel()
        connectionLease.cancel()
        client.stateUpdateHandler = nil
        backend?.stateUpdateHandler = nil
        client.cancel()
        backend?.cancel()
        backend = nil
        onClose(id)
    }
}
#endif
