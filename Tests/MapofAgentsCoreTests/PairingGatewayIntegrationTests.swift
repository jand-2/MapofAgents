import Foundation
import Testing
@testable import MapofAgentsCore

#if os(macOS)
import Darwin
import Network

@Test
func pairingGatewayRevocationFansOutToActiveAndPendingGenerations() {
    let active = MapofAgentsTestGatewayRevocationSpy()
    let pending = MapofAgentsTestGatewayRevocationSpy()

    MapofAgentsPairingGatewayRevocationFanout.revoke(
        deviceID: "revoked-device",
        targets: [active, pending]
    )

    #expect(active.revokedDeviceIDs == ["revoked-device"])
    #expect(pending.revokedDeviceIDs == ["revoked-device"])
}

@Test
func pairingGatewayForceClosesExistingSocketsAtExpiryAndRevocation() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-gateway-integration-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let secret = "test-only-integration-gateway-secret"
    let secretURL = directory.appendingPathComponent("host-secret")
    let registryURL = directory.appendingPathComponent("registry.json")
    try MapofAgentsPrivateFile.write(Data(secret.utf8), to: secretURL)
    let registry = try MapofAgentsCredentialRegistry(fileURL: registryURL)
    let enrollment = try registry.issueEnrollment(
        expiresAt: Date().addingTimeInterval(30),
        token: "test-only-gateway-integration-enrollment"
    )
    _ = try registry.registerDevice(
        enrollmentToken: enrollment,
        deviceName: "Example iPhone",
        deviceID: "gateway-device",
        refreshCredential: "test-only-gateway-integration-refresh"
    )

    let backend = MapofAgentsTestTCPBackend()
    let backendPort = try await backend.start()
    let gatewayPort = try availableLoopbackPort()
    let runtime = MapofAgentsPairingGatewayRuntime()
    try await runtime.ensureRunning(
        listenPort: gatewayPort,
        backendPort: backendPort,
        sharedSecretURL: secretURL,
        registryURL: registryURL,
        backendIsOwned: { true },
        onListenerFailure: {}
    )

    do {
        let expiresAt = Date().addingTimeInterval(0.7)
        let expiringToken = try MapofAgentsMacPairingService.signedBearerToken(
            secret: secret,
            subject: "mapofagents-device:gateway-device",
            expiresAt: expiresAt
        )
        let expiringClient = MapofAgentsTestGatewayClient(port: gatewayPort)
        try await expiringClient.connectAndSend(handshake(token: expiringToken))
        try await backend.waitForAcceptedConnections(1)
        let expiryClosedAt = try await withGatewayTestTimeout(.seconds(2)) {
            try await expiringClient.waitForRemoteClose()
            return Date()
        }
        #expect(expiryClosedAt >= expiresAt.addingTimeInterval(-0.08))

        let revocableToken = try MapofAgentsMacPairingService.signedBearerToken(
            secret: secret,
            subject: "mapofagents-device:gateway-device",
            expiresAt: Date().addingTimeInterval(60)
        )
        let revocableClient = MapofAgentsTestGatewayClient(port: gatewayPort)
        try await revocableClient.connectAndSend(handshake(token: revocableToken))
        try await backend.waitForAcceptedConnections(2)
        let revokedAt = Date()
        await runtime.revoke(deviceID: "gateway-device")
        let revokeClosedAt = try await withGatewayTestTimeout(.seconds(1)) {
            try await revocableClient.waitForRemoteClose()
            return Date()
        }
        #expect(revokeClosedAt.timeIntervalSince(revokedAt) < 0.8)
    } catch {
        await runtime.stop()
        backend.stop()
        throw error
    }

    await runtime.stop()
    backend.stop()
}

@Test
func pairingGatewayRefusesToPublishThroughAPreboundListener() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-gateway-squatter-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let secretURL = directory.appendingPathComponent("host-secret")
    let registryURL = directory.appendingPathComponent("registry.json")
    try MapofAgentsPrivateFile.write(Data("test-only-secret".utf8), to: secretURL)
    _ = try MapofAgentsCredentialRegistry(fileURL: registryURL)

    let occupiedPort = try availableLoopbackPort()
    let squatter = MapofAgentsTestTCPBackend(port: occupiedPort)
    _ = try await squatter.start()
    let backend = MapofAgentsTestTCPBackend()
    let backendPort = try await backend.start()
    let failures = MapofAgentsTestStringRecorder()
    let runtime = MapofAgentsPairingGatewayRuntime()

    await #expect(throws: (any Error).self) {
        try await runtime.ensureRunning(
            listenPort: occupiedPort,
            backendPort: backendPort,
            sharedSecretURL: secretURL,
            registryURL: registryURL,
            backendIsOwned: { true },
            onListenerFailure: { failures.append("failed") }
        )
    }
    #expect(failures.values.contains("failed"))

    await runtime.stop()
    backend.stop()
    squatter.stop()
}

@Test
func credentialExchangeListenerOwnsItsLoopbackPortExclusively() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-exchange-integration-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let secretURL = directory.appendingPathComponent("host-secret")
    let registryURL = directory.appendingPathComponent("registry.json")
    try MapofAgentsPrivateFile.write(Data("test-only-exchange-secret".utf8), to: secretURL)
    let port = try availableLoopbackPort()
    let runtime = MapofAgentsCredentialExchangeRuntime()
    let endpoint = MapofAgentsPairingEndpoint(
        kind: .tailnet,
        url: try #require(URL(string: "wss://example-host.example-tailnet.ts.net")),
        label: "Example Mac"
    )
    try await runtime.ensureRunning(
        port: port,
        registryURL: registryURL,
        hostID: HostID(rawValue: "host-1"),
        sharedSecretURL: secretURL,
        endpoints: [endpoint],
        supportDirectory: "/Users/example/Library/Application Support/mapofagents"
    )

    do {
        let enrollmentToken = try await runtime.issueEnrollment(
            expiresAt: Date().addingTimeInterval(30)
        )
        var request = URLRequest(
            url: try #require(URL(string: "http://127.0.0.1:\(port)/v1/pairing/enroll"))
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            MapofAgentsEnrollmentRequest(
                enrollmentToken: enrollmentToken,
                deviceName: "Example iPhone"
            )
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["hostID"] as? String == "host-1")

        let squatter = MapofAgentsTestTCPBackend(port: port)
        await #expect(throws: (any Error).self) {
            _ = try await squatter.start()
        }
        squatter.stop()
    } catch {
        await runtime.stop()
        throw error
    }
    await runtime.stop()
}

@Test
func credentialExchangeListenerEvictsPartialRequestsAtItsDeadline() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-exchange-slowloris-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let router = try credentialExchangeRouter(in: directory)
    let port = try availableLoopbackPort()
    let listener = try MapofAgentsNetworkCredentialExchangeListener(
        port: port,
        maximumConnections: 4,
        requestTimeout: 0.12
    )
    try await listener.start(router: router)

    let client = MapofAgentsTestGatewayClient(port: port)
    do {
        try await client.connectAndSend(Data("POST /v1/pairing/enroll HTTP/1.1\r\nHost: example-host\r\n".utf8))
        try await withGatewayTestTimeout(.seconds(1)) {
            try await client.waitForRemoteClose()
        }
    } catch {
        await listener.stop()
        throw error
    }
    await listener.stop()
}

@Test
func credentialExchangeListenerCapsConnectionsAndStopDrainsAcceptedRequests() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-exchange-cap-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let router = try credentialExchangeRouter(in: directory)
    let port = try availableLoopbackPort()
    let listener = try MapofAgentsNetworkCredentialExchangeListener(
        port: port,
        maximumConnections: 2,
        requestTimeout: 5
    )
    try await listener.start(router: router)

    let partialRequest = Data("POST /v1/pairing/enroll HTTP/1.1\r\nHost: example-host\r\n".utf8)
    let first = MapofAgentsTestGatewayClient(port: port)
    let second = MapofAgentsTestGatewayClient(port: port)
    let rejected = MapofAgentsTestGatewayClient(port: port)
    do {
        try await first.connectAndSend(partialRequest)
        try await Task.sleep(for: .milliseconds(30))
        try await second.connectAndSend(partialRequest)
        try await Task.sleep(for: .milliseconds(30))
        try? await rejected.connectAndSend(partialRequest)
        try await withGatewayTestTimeout(.seconds(1)) {
            try await rejected.waitForRemoteClose()
        }

        await listener.stop()
        try await withGatewayTestTimeout(.seconds(1)) {
            async let firstClosed: Void = first.waitForRemoteClose()
            async let secondClosed: Void = second.waitForRemoteClose()
            _ = try await (firstClosed, secondClosed)
        }

        let rebound = MapofAgentsTestTCPBackend(port: port)
        _ = try await rebound.start()
        rebound.stop()
    } catch {
        await listener.stop()
        throw error
    }
}

@Test
func pairingGatewayRejectsInvalidCredentialsBeforeOpeningTheBackend() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-gateway-invalid-e2e-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let secret = "test-only-invalid-e2e-secret"
    let secretURL = directory.appendingPathComponent("host-secret")
    let registryURL = directory.appendingPathComponent("registry.json")
    try MapofAgentsPrivateFile.write(Data(secret.utf8), to: secretURL)
    let registry = try MapofAgentsCredentialRegistry(fileURL: registryURL)
    let enrollment = try registry.issueEnrollment(
        expiresAt: Date().addingTimeInterval(30),
        token: "test-only-invalid-e2e-enrollment"
    )
    _ = try registry.registerDevice(
        enrollmentToken: enrollment,
        deviceName: "Example iPhone",
        deviceID: "valid-device",
        refreshCredential: "test-only-invalid-e2e-refresh"
    )

    let backend = MapofAgentsTestTCPBackend()
    let backendPort = try await backend.start()
    let gatewayPort = try availableLoopbackPort()
    let runtime = MapofAgentsPairingGatewayRuntime()
    try await runtime.ensureRunning(
        listenPort: gatewayPort,
        backendPort: backendPort,
        sharedSecretURL: secretURL,
        registryURL: registryURL,
        backendIsOwned: { true },
        onListenerFailure: {}
    )
    let validToken = try MapofAgentsMacPairingService.signedBearerToken(
        secret: secret,
        subject: "mapofagents-device:valid-device",
        expiresAt: Date().addingTimeInterval(60)
    )
    var tamperedToken = validToken
    let signatureStart = tamperedToken.index(after: try #require(tamperedToken.lastIndex(of: ".")))
    tamperedToken.replaceSubrange(
        signatureStart...signatureStart,
        with: tamperedToken[signatureStart] == "A" ? "B" : "A"
    )
    let expiredToken = try MapofAgentsMacPairingService.signedBearerToken(
        secret: secret,
        subject: "mapofagents-device:valid-device",
        expiresAt: Date().addingTimeInterval(-1),
        issuedAt: Date().addingTimeInterval(-60)
    )
    let unregisteredToken = try MapofAgentsMacPairingService.signedBearerToken(
        secret: secret,
        subject: "mapofagents-device:not-registered",
        expiresAt: Date().addingTimeInterval(60)
    )

    for token in [tamperedToken, expiredToken, unregisteredToken] {
        let client = MapofAgentsTestGatewayClient(port: gatewayPort)
        try await client.connectAndSend(handshake(token: token))
        try await withGatewayTestTimeout(.seconds(1)) {
            try await client.waitForRemoteClose()
        }
    }
    try await Task.sleep(for: .milliseconds(80))
    #expect(backend.receivedHandshakes == 0)

    await runtime.stop()
    backend.stop()
}

@Test
func pairingGatewayEvictsPartialUnauthenticatedHandshakes() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-gateway-slowloris-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let secretURL = directory.appendingPathComponent("host-secret")
    let registryURL = directory.appendingPathComponent("registry.json")
    try MapofAgentsPrivateFile.write(Data("test-only-slowloris-secret".utf8), to: secretURL)
    _ = try MapofAgentsCredentialRegistry(fileURL: registryURL)

    let backend = MapofAgentsTestTCPBackend()
    let backendPort = try await backend.start()
    let gatewayPort = try availableLoopbackPort()
    let runtime = MapofAgentsPairingGatewayRuntime()
    try await runtime.ensureRunning(
        listenPort: gatewayPort,
        backendPort: backendPort,
        sharedSecretURL: secretURL,
        registryURL: registryURL,
        backendIsOwned: { true },
        onListenerFailure: {},
        handshakeTimeout: 0.12
    )
    let client = MapofAgentsTestGatewayClient(port: gatewayPort)
    try await client.connectAndSend(Data("GET / HTTP/1.1\r\nHost: example-host\r\n".utf8))
    try await withGatewayTestTimeout(.seconds(1)) {
        try await client.waitForRemoteClose()
    }
    #expect(backend.receivedHandshakes == 0)

    await runtime.stop()
    backend.stop()
}

@Test
func pairingGatewayCapsConcurrentSessionsPerDevice() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-gateway-device-cap-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let secret = "test-only-device-cap-secret"
    let secretURL = directory.appendingPathComponent("host-secret")
    let registryURL = directory.appendingPathComponent("registry.json")
    try MapofAgentsPrivateFile.write(Data(secret.utf8), to: secretURL)
    let registry = try MapofAgentsCredentialRegistry(fileURL: registryURL)
    let enrollment = try registry.issueEnrollment(
        expiresAt: Date().addingTimeInterval(30),
        token: "test-only-device-cap-enrollment"
    )
    _ = try registry.registerDevice(
        enrollmentToken: enrollment,
        deviceName: "Example iPhone",
        deviceID: "capped-device",
        refreshCredential: "test-only-device-cap-refresh"
    )
    let backend = MapofAgentsTestTCPBackend()
    let backendPort = try await backend.start()
    let gatewayPort = try availableLoopbackPort()
    let runtime = MapofAgentsPairingGatewayRuntime()
    try await runtime.ensureRunning(
        listenPort: gatewayPort,
        backendPort: backendPort,
        sharedSecretURL: secretURL,
        registryURL: registryURL,
        backendIsOwned: { true },
        onListenerFailure: {}
    )
    let token = try MapofAgentsMacPairingService.signedBearerToken(
        secret: secret,
        subject: "mapofagents-device:capped-device",
        expiresAt: Date().addingTimeInterval(60)
    )
    var clients: [MapofAgentsTestGatewayClient] = []
    for expected in 1...4 {
        let client = MapofAgentsTestGatewayClient(port: gatewayPort)
        clients.append(client)
        try await client.connectAndSend(handshake(token: token))
        try await backend.waitForAcceptedConnections(expected)
    }
    let rejected = MapofAgentsTestGatewayClient(port: gatewayPort)
    try await rejected.connectAndSend(handshake(token: token))
    try await withGatewayTestTimeout(.seconds(1)) {
        try await rejected.waitForRemoteClose()
    }
    #expect(backend.receivedHandshakes == 4)

    await runtime.stop()
    backend.stop()
    _ = clients
}

@Test
func pairingGatewayReplacementDrainsOldGenerationBeforeRebinding() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-gateway-replacement-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let secret = "test-only-replacement-secret"
    let secretURL = directory.appendingPathComponent("host-secret")
    let registryURL = directory.appendingPathComponent("registry.json")
    try MapofAgentsPrivateFile.write(Data(secret.utf8), to: secretURL)
    let registry = try MapofAgentsCredentialRegistry(fileURL: registryURL)
    let enrollment = try registry.issueEnrollment(
        expiresAt: Date().addingTimeInterval(30),
        token: "test-only-replacement-enrollment"
    )
    _ = try registry.registerDevice(
        enrollmentToken: enrollment,
        deviceName: "Example iPhone",
        deviceID: "replacement-device",
        refreshCredential: "test-only-replacement-refresh"
    )

    let firstBackend = MapofAgentsTestTCPBackend()
    let firstBackendPort = try await firstBackend.start()
    let secondBackend = MapofAgentsTestTCPBackend()
    let secondBackendPort = try await secondBackend.start()
    let gatewayPort = try availableLoopbackPort()
    let failures = MapofAgentsTestStringRecorder()
    let runtime = MapofAgentsPairingGatewayRuntime()
    try await runtime.ensureRunning(
        listenPort: gatewayPort,
        backendPort: firstBackendPort,
        sharedSecretURL: secretURL,
        registryURL: registryURL,
        backendIsOwned: { true },
        onListenerFailure: { failures.append("stale") }
    )
    try await runtime.ensureRunning(
        listenPort: gatewayPort,
        backendPort: secondBackendPort,
        sharedSecretURL: secretURL,
        registryURL: registryURL,
        backendIsOwned: { true },
        onListenerFailure: { failures.append("current") }
    )

    let token = try MapofAgentsMacPairingService.signedBearerToken(
        secret: secret,
        subject: "mapofagents-device:replacement-device",
        expiresAt: Date().addingTimeInterval(60)
    )
    let client = MapofAgentsTestGatewayClient(port: gatewayPort)
    try await client.connectAndSend(handshake(token: token))
    try await secondBackend.waitForAcceptedConnections(1)
    #expect(firstBackend.receivedHandshakes == 0)
    #expect(failures.values.isEmpty)

    await runtime.stop()
    let rebound = MapofAgentsTestTCPBackend(port: gatewayPort)
    _ = try await rebound.start()
    rebound.stop()
    #expect(failures.values.isEmpty)
    firstBackend.stop()
    secondBackend.stop()
}

@Test
func pairingGatewayFailsClosedWhenOwnedBackendDisappears() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-gateway-backend-loss-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let secretURL = directory.appendingPathComponent("host-secret")
    let registryURL = directory.appendingPathComponent("registry.json")
    let secret = "test-only-secret"
    try MapofAgentsPrivateFile.write(Data(secret.utf8), to: secretURL)
    let registry = try MapofAgentsCredentialRegistry(fileURL: registryURL)
    let enrollment = try registry.issueEnrollment(
        expiresAt: Date().addingTimeInterval(30),
        token: "test-only-backend-loss-enrollment"
    )
    _ = try registry.registerDevice(
        enrollmentToken: enrollment,
        deviceName: "Example iPhone",
        deviceID: "backend-loss-device",
        refreshCredential: "test-only-backend-loss-refresh"
    )

    let backend = MapofAgentsTestTCPBackend()
    let backendPort = try await backend.start()
    let gatewayPort = try availableLoopbackPort()
    let backendOwned = MapofAgentsTestBoolBox(true)
    let failures = MapofAgentsTestStringRecorder()
    let runtime = MapofAgentsPairingGatewayRuntime()
    try await runtime.ensureRunning(
        listenPort: gatewayPort,
        backendPort: backendPort,
        sharedSecretURL: secretURL,
        registryURL: registryURL,
        backendIsOwned: { backendOwned.value },
        onListenerFailure: { failures.append("failed-closed") }
    )
    let token = try MapofAgentsMacPairingService.signedBearerToken(
        secret: secret,
        subject: "mapofagents-device:backend-loss-device",
        expiresAt: Date().addingTimeInterval(60)
    )
    let client = MapofAgentsTestGatewayClient(port: gatewayPort)
    try await client.connectAndSend(handshake(token: token))
    try await backend.waitForAcceptedConnections(1)

    backendOwned.value = false
    try await withGatewayTestTimeout(.seconds(2)) {
        while !failures.values.contains("failed-closed") {
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    try await withGatewayTestTimeout(.seconds(1)) {
        try await client.waitForRemoteClose()
    }
    let refusedClient = MapofAgentsTestGatewayClient(port: gatewayPort)
    await #expect(throws: (any Error).self) {
        try await withGatewayTestTimeout(.seconds(1)) {
            try await refusedClient.connectAndSend(handshake(token: token))
        }
    }

    await runtime.stop()
    backend.stop()
}

@Test
func blockedOwnershipProbeDoesNotDelayGatewayExpiryOrRevocation() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-gateway-ownership-isolation-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let secret = "test-only-ownership-isolation-secret"
    let secretURL = directory.appendingPathComponent("host-secret")
    let registryURL = directory.appendingPathComponent("registry.json")
    try MapofAgentsPrivateFile.write(Data(secret.utf8), to: secretURL)
    let registry = try MapofAgentsCredentialRegistry(fileURL: registryURL)
    for deviceID in ["expiring-device", "revoked-device", "probe-device"] {
        let enrollment = try registry.issueEnrollment(
            expiresAt: Date().addingTimeInterval(30),
            token: "test-only-\(deviceID)-enrollment"
        )
        _ = try registry.registerDevice(
            enrollmentToken: enrollment,
            deviceName: "Example iPhone",
            deviceID: deviceID,
            refreshCredential: "test-only-\(deviceID)-refresh"
        )
    }

    let backend = MapofAgentsTestTCPBackend()
    let backendPort = try await backend.start()
    let gatewayPort = try availableLoopbackPort()
    let ownershipProbe = MapofAgentsBlockingOwnershipProbe()
    let runtime = MapofAgentsPairingGatewayRuntime()
    try await runtime.ensureRunning(
        listenPort: gatewayPort,
        backendPort: backendPort,
        sharedSecretURL: secretURL,
        registryURL: registryURL,
        backendIsOwned: { ownershipProbe.check() },
        onListenerFailure: {}
    )

    let expiresAt = Date().addingTimeInterval(2.5)
    let expiringToken = try MapofAgentsMacPairingService.signedBearerToken(
        secret: secret,
        subject: "mapofagents-device:expiring-device",
        expiresAt: expiresAt
    )
    let leaseExpiresAt = try MapofAgentsPairingAccessTokenValidator(
        sharedSecretURL: secretURL,
        registryURL: registryURL
    ).validate(expiringToken).expiresAt
    let revocableToken = try MapofAgentsMacPairingService.signedBearerToken(
        secret: secret,
        subject: "mapofagents-device:revoked-device",
        expiresAt: Date().addingTimeInterval(60)
    )
    let ownershipProbeToken = try MapofAgentsMacPairingService.signedBearerToken(
        secret: secret,
        subject: "mapofagents-device:probe-device",
        expiresAt: Date().addingTimeInterval(60)
    )
    let expiringClient = MapofAgentsTestGatewayClient(port: gatewayPort)
    let revocableClient = MapofAgentsTestGatewayClient(port: gatewayPort)
    let ownershipProbeClient = MapofAgentsTestGatewayClient(port: gatewayPort)

    do {
        try await expiringClient.connectAndSend(handshake(token: expiringToken))
        try await backend.waitForAcceptedConnections(1)
        let expiringCloseTask = Task {
            try await expiringClient.waitForRemoteClose()
        }
        try await revocableClient.connectAndSend(handshake(token: revocableToken))
        try await backend.waitForAcceptedConnections(2)
        let revocableCloseTask = Task {
            try await revocableClient.waitForRemoteClose()
        }

        ownershipProbe.arm()
        try await ownershipProbeClient.connectAndSend(handshake(token: ownershipProbeToken))
        try await ownershipProbe.waitUntilBlocked()

        // Revoke the very connection whose authenticated handshake is waiting
        // on the off-queue ownership probe. It must be visible to revocation
        // before promotion and must never reach the Codex backend.
        try registry.revokeDevice(deviceID: "probe-device")
        await runtime.revoke(deviceID: "probe-device")
        try await withGatewayTestTimeout(.seconds(1)) {
            try await ownershipProbeClient.waitForRemoteClose()
        }

        await runtime.revoke(deviceID: "revoked-device")
        try await withGatewayTestTimeout(.seconds(1)) {
            try await revocableCloseTask.value
        }
        let expiryTimeout = max(1, leaseExpiresAt.timeIntervalSinceNow + 1)
        try await withGatewayTestTimeout(.seconds(expiryTimeout)) {
            try await expiringCloseTask.value
        }
        #expect(ownershipProbe.isBlocked)
        #expect(Date() >= leaseExpiresAt.addingTimeInterval(-0.08))

        ownershipProbe.release()
        try await Task.sleep(for: .milliseconds(80))
        #expect(backend.receivedHandshakes == 2)
        await runtime.stop()
        backend.stop()
    } catch {
        ownershipProbe.release()
        await runtime.stop()
        backend.stop()
        throw error
    }
}

private enum MapofAgentsGatewayTestError: Error {
    case timeout
    case connectionFailed(String)
}

private func credentialExchangeRouter(
    in directory: URL
) throws -> MapofAgentsCredentialExchangeHTTPRouter {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let secretURL = directory.appendingPathComponent("host-secret")
    try MapofAgentsPrivateFile.write(Data("test-only-exchange-router-secret".utf8), to: secretURL)
    let registry = try MapofAgentsCredentialRegistry(
        fileURL: directory.appendingPathComponent("registry.json")
    )
    let handler = MapofAgentsCredentialExchangeHandler(
        registry: registry,
        hostID: HostID(rawValue: "host-1"),
        sharedSecretURL: secretURL,
        endpoints: [],
        supportDirectory: nil
    )
    return MapofAgentsCredentialExchangeHTTPRouter(handler: handler)
}

private func handshake(token: String) -> Data {
    Data(
        "GET / HTTP/1.1\r\nHost: example-host\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGVzdC1vbmx5LWtleQ==\r\nSec-WebSocket-Version: 13\r\nAuthorization: Bearer \(token)\r\n\r\n".utf8
    )
}

private func withGatewayTestTimeout<Value: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw MapofAgentsGatewayTestError.timeout
        }
        let value = try await #require(group.next())
        group.cancelAll()
        return value
    }
}

private func availableLoopbackPort() throws -> UInt16 {
    for _ in 0..<128 {
        let candidate = try probeAvailableLoopbackPort()
        if MapofAgentsTestPortReservations.shared.reserve(candidate) {
            return candidate
        }
    }
    throw POSIXError(.EADDRINUSE)
}

private func probeAvailableLoopbackPort() throws -> UInt16 {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw POSIXError(.EIO) }
    defer { close(descriptor) }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(0)
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    let bindResult = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bindResult == 0 else { throw POSIXError(.EADDRINUSE) }

    var boundAddress = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            getsockname(descriptor, $0, &length)
        }
    }
    guard nameResult == 0 else { throw POSIXError(.EIO) }
    return UInt16(bigEndian: boundAddress.sin_port)
}

private final class MapofAgentsTestPortReservations: @unchecked Sendable {
    static let shared = MapofAgentsTestPortReservations()

    private let lock = NSLock()
    private var ports: Set<UInt16> = []

    func reserve(_ port: UInt16) -> Bool {
        lock.withLock { ports.insert(port).inserted }
    }
}

private final class MapofAgentsTestTCPBackend: @unchecked Sendable {
    private let requestedPort: UInt16?
    private let queue = DispatchQueue(label: "dev.mapofagents.tests.gateway-backend.\(UUID().uuidString)")
    private let lock = NSLock()
    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var receivedHandshakeCount = 0

    init(port: UInt16? = nil) {
        requestedPort = port
    }

    var receivedHandshakes: Int {
        lock.withLock { receivedHandshakeCount }
    }

    func start() async throws -> UInt16 {
        let listener: NWListener
        if let requestedPort, let port = NWEndpoint.Port(rawValue: requestedPort) {
            listener = try NWListener(using: .tcp, on: port)
        } else {
            listener = try NWListener(using: .tcp, on: .any)
        }
        lock.withLock { self.listener = listener }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            lock.withLock { connections.append(connection) }
            connection.stateUpdateHandler = { [weak self, weak connection] state in
                guard let self, let connection, case .ready = state else { return }
                connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1_024) {
                    [weak self, weak connection] data, _, _, error in
                    guard let self, let connection, error == nil,
                          let data, data.range(of: Data("\r\n\r\n".utf8)) != nil else { return }
                    lock.withLock { receivedHandshakeCount += 1 }
                    connection.send(
                        content: Data("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n".utf8),
                        completion: .idempotent
                    )
                }
            }
            connection.start(queue: queue)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = MapofAgentsTestContinuation(continuation)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.resume(returning: ())
                case .failed(let error), .waiting(let error):
                    once.resume(throwing: error)
                case .cancelled:
                    once.resume(throwing: MapofAgentsGatewayTestError.connectionFailed("Listener cancelled"))
                case .setup:
                    break
                @unknown default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        return try #require(listener.port?.rawValue)
    }

    func waitForAcceptedConnections(_ expected: Int) async throws {
        try await withGatewayTestTimeout(.seconds(1)) { [self] in
            while lock.withLock({ receivedHandshakeCount }) < expected {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    func stop() {
        let state = lock.withLock { () -> (NWListener?, [NWConnection]) in
            defer {
                listener = nil
                connections.removeAll()
                receivedHandshakeCount = 0
            }
            return (listener, connections)
        }
        state.0?.cancel()
        state.1.forEach { $0.cancel() }
    }
}

private final class MapofAgentsTestGatewayClient: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "dev.mapofagents.tests.gateway-client.\(UUID().uuidString)")

    init(port: UInt16) {
        connection = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
    }

    func connectAndSend(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = MapofAgentsTestContinuation(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    once.resume(returning: ())
                case .failed(let error), .waiting(let error):
                    once.resume(throwing: error)
                case .cancelled:
                    once.resume(throwing: MapofAgentsGatewayTestError.connectionFailed("Client cancelled"))
                case .setup, .preparing:
                    break
                @unknown default:
                    break
                }
            }
            connection.start(queue: queue)
        }
        connection.stateUpdateHandler = nil
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    func waitForRemoteClose() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = MapofAgentsTestContinuation(continuation)
            receiveUntilClose(once)
        }
    }

    private func receiveUntilClose(_ once: MapofAgentsTestContinuation<Void>) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { [weak self] _, _, isComplete, error in
            guard let self else { return }
            if isComplete || error != nil {
                once.resume(returning: ())
            } else {
                receiveUntilClose(once)
            }
        }
    }

    deinit {
        connection.cancel()
    }
}

private final class MapofAgentsTestContinuation<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: Value) {
        lock.withLock {
            continuation?.resume(returning: value)
            continuation = nil
        }
    }

    func resume(throwing error: Error) {
        lock.withLock {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

private final class MapofAgentsTestStringRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] { lock.withLock { storage } }

    func append(_ value: String) {
        lock.withLock { storage.append(value) }
    }
}

private final class MapofAgentsTestGatewayRevocationSpy: MapofAgentsPairingGatewayRevoking, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var revokedDeviceIDs: [String] { lock.withLock { storage } }

    func revoke(deviceID: String) {
        lock.withLock { storage.append(deviceID) }
    }
}

private final class MapofAgentsTestBoolBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Bool

    init(_ value: Bool) {
        storage = value
    }

    var value: Bool {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
}

private final class MapofAgentsBlockingOwnershipProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseSemaphore = DispatchSemaphore(value: 0)
    private var armed = false
    private var blocked = false
    private var released = false

    var isBlocked: Bool { lock.withLock { blocked && !released } }

    func arm() {
        lock.withLock { armed = true }
    }

    func check() -> Bool {
        let shouldBlock = lock.withLock { () -> Bool in
            guard armed, !blocked else { return false }
            blocked = true
            return true
        }
        if shouldBlock {
            releaseSemaphore.wait()
        }
        return true
    }

    func waitUntilBlocked() async throws {
        try await withGatewayTestTimeout(.seconds(2)) { [self] in
            while !isBlocked {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    func release() {
        let shouldSignal = lock.withLock { () -> Bool in
            guard !released else { return false }
            released = true
            return true
        }
        if shouldSignal {
            releaseSemaphore.signal()
        }
    }
}
#endif
