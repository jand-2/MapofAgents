import Foundation
import Testing
@testable import MapofAgentsCore

#if os(macOS)
import Darwin
#endif

private func base64URLDecodedData(_ value: String) -> Data? {
    var base64 = value
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let padding = base64.count % 4
    if padding > 0 {
        base64.append(String(repeating: "=", count: 4 - padding))
    }
    return Data(base64Encoded: base64)
}

@Test
func pairingPayloadRoundTripsThroughURL() throws {
    let tailnetURL = try #require(URL(string: "wss://example-host.example-tailnet.ts.net"))
    let localURL = try #require(URL(string: "wss://example-relay.test"))
    let exchangeURL = try #require(URL(string: "https://example-host.example-tailnet.ts.net:8443/v1/pairing"))
    let supportDirectory = "/Users/test/Library/Application Support/mapofagents"
    let payload = MapofAgentsPairingPayload(
        hostID: HostID(rawValue: "paired-mac"),
        name: "Mac mini",
        endpoints: [
            MapofAgentsPairingEndpoint(kind: .local, url: localURL, label: "Example relay"),
            MapofAgentsPairingEndpoint(kind: .tailnet, url: tailnetURL, label: "example-host.example-tailnet.ts.net"),
        ],
        enrollmentToken: "one-time-enrollment",
        credentialExchangeURL: exchangeURL,
        createdAt: Date(timeIntervalSince1970: 10),
        expiresAt: Date(timeIntervalSince1970: 1_000),
        mapofagentsSupportDirectory: supportDirectory
    )

    let url = try payload.pairingURL()
    let decoded = try MapofAgentsPairingPayload.decode(from: url)

    #expect(url.scheme == "mapofagents")
    #expect(url.host == "pair")
    #expect(decoded.hostID == payload.hostID)
    #expect(decoded.bearerToken.isEmpty)
    #expect(decoded.enrollmentToken == "one-time-enrollment")
    #expect(decoded.credentialExchangeURL == exchangeURL)
    #expect(decoded.mapofagentsSupportDirectory == supportDirectory)
    #expect(decoded.preferredEndpoints.first?.kind == .tailnet)
    #expect(decoded.preferredEndpoints.first?.url == tailnetURL)
}

@Test
func pairingPayloadRefusesToEmitAnyCleartextRemoteEndpoint() throws {
    let cleartextURL = try #require(URL(string: "ws://example-host.local:19001"))
    let secureURL = try #require(URL(string: "wss://example-host.example-tailnet.ts.net"))
    let exchangeURL = try #require(URL(string: "https://example-host.example-tailnet.ts.net:8443/v1/pairing"))
    let payload = MapofAgentsPairingPayload(
        hostID: HostID(rawValue: "paired-mac"),
        name: "Example Mac",
        endpoints: [
            MapofAgentsPairingEndpoint(kind: .local, url: cleartextURL, label: "example-host.local"),
            MapofAgentsPairingEndpoint(
                kind: .tailnet,
                url: secureURL,
                label: "example-host.example-tailnet.ts.net"
            ),
        ],
        enrollmentToken: "one-time-enrollment",
        credentialExchangeURL: exchangeURL
    )

    #expect(throws: MapofAgentsPairingError.self) {
        _ = try payload.pairingURL()
    }
    #expect(throws: MapofAgentsPairingError.self) {
        try payload.validateForImport()
    }
}

@Test
func pairingPayloadRejectsRedirectedOrMalformedCredentialExchangeURL() throws {
    let endpointURL = try #require(URL(string: "wss://example-host.example-tailnet.ts.net"))
    let redirectedExchangeURL = try #require(URL(string: "https://other-host.example-tailnet.ts.net:8443/v1/pairing"))
    let endpoint = MapofAgentsPairingEndpoint(
        kind: .tailnet,
        url: endpointURL,
        label: "Example Mac"
    )
    let redirected = MapofAgentsPairingPayload(
        hostID: HostID(rawValue: "paired-mac"),
        name: "Example Mac",
        endpoints: [endpoint],
        enrollmentToken: "one-time-enrollment",
        credentialExchangeURL: redirectedExchangeURL
    )

    #expect(throws: MapofAgentsPairingError.self) {
        try redirected.validateForImport()
    }
    #expect(throws: MapofAgentsPairingError.self) {
        _ = try redirected.pairingURL()
    }

    for value in [
        "https://example-host.example-tailnet.ts.net/v1/pairing",
        "https://example-host.example-tailnet.ts.net:8443/not-pairing",
        "https://example-host.example-tailnet.ts.net:8443/v1/pairing?redirect=true",
        "https://example-host.local:8443/v1/pairing",
        "http://example-host.example-tailnet.ts.net:8443/v1/pairing",
    ] {
        let url = try #require(URL(string: value))
        #expect(MapofAgentsPairingPayload.isSecureCredentialExchangeURL(url) == false)
    }
}

@Test
func credentialExchangeHTTPClientRefusesRedirectsBeforeCredentialsCanBeForwarded() throws {
    let originalURL = try #require(URL(string: "https://example-host.example-tailnet.ts.net:8443/v1/pairing/enroll"))
    let redirectedURL = try #require(URL(string: "https://redirect.example.test/collect"))
    let response = try #require(HTTPURLResponse(
        url: originalURL,
        statusCode: 307,
        httpVersion: "HTTP/1.1",
        headerFields: ["Location": redirectedURL.absoluteString]
    ))
    let task = URLSession.shared.dataTask(with: originalURL)
    var followedRequest: URLRequest? = URLRequest(url: redirectedURL)

    MapofAgentsNoRedirectURLSessionDelegate.shared.urlSession(
        .shared,
        task: task,
        willPerformHTTPRedirection: response,
        newRequest: URLRequest(url: redirectedURL)
    ) { request in
        followedRequest = request
    }

    #expect(followedRequest == nil)
}

@Test
func pairingPayloadAcceptsFractionalSecondDates() throws {
    let endpointURL = try #require(URL(string: "ws://100.64.0.10:18945"))
    let payload = """
    {
      "version": 1,
      "hostID": "paired-mac",
      "name": "Mac mini",
      "endpoints": [
        {
          "id": "endpoint",
          "kind": "tailnet",
          "url": "\(endpointURL.absoluteString)",
          "label": "100.64.0.10"
        }
      ],
      "bearerToken": "secret",
      "createdAt": "2026-05-22T19:15:44.123456Z",
      "expiresAt": "2026-05-22T19:45:44.654321Z"
    }
    """
    let url = try pairingURL(forJSONObject: payload)

    let decoded = try MapofAgentsPairingPayload.decode(from: url)

    #expect(decoded.hostID == HostID(rawValue: "paired-mac"))
    #expect(decoded.preferredEndpoints.first?.url == endpointURL)
    #expect(decoded.createdAt.timeIntervalSince1970 > 0)
}

@Test
func pairingPayloadStillDecodesAndValidatesSecureLegacyQR() throws {
    let endpointURL = try #require(URL(string: "wss://example-host.example-tailnet.ts.net"))
    let payload = MapofAgentsPairingPayload(
        version: 1,
        hostID: HostID(rawValue: "paired-mac"),
        name: "Legacy Mac",
        endpoints: [
            MapofAgentsPairingEndpoint(kind: .tailnet, url: endpointURL, label: "Legacy Mac"),
        ],
        bearerToken: "legacy-short-lived-access",
        expiresAt: Date().addingTimeInterval(60)
    )

    let decoded = try MapofAgentsPairingPayload.decode(from: payload.pairingURL())
    try decoded.validateForImport()
    #expect(decoded.version == 1)
    #expect(decoded.bearerToken == "legacy-short-lived-access")
    #expect(decoded.credentialExchangeURL == nil)
}

@Test
func pairingPayloadImportRequiresExpiration() throws {
    let endpointURL = try #require(URL(string: "ws://mac-mini.tailnet.ts.net:18945"))
    let payload = MapofAgentsPairingPayload(
        hostID: HostID(rawValue: "paired-mac"),
        name: "Mac mini",
        endpoints: [
            MapofAgentsPairingEndpoint(kind: .tailnet, url: endpointURL, label: "mac-mini.tailnet.ts.net"),
        ],
        bearerToken: "secret",
        expiresAt: nil
    )

    #expect(throws: MapofAgentsPairingError.self) {
        try payload.validateForImport()
    }
}

#if os(macOS)
@Test
func pairingSignedBearerTokenCarriesServerExpiry() throws {
    let issuedAt = Date(timeIntervalSince1970: 1_000)
    let expiresAt = Date(timeIntervalSince1970: 1_600)
    let token = try MapofAgentsMacPairingService.signedBearerToken(
        secret: String(repeating: "a", count: 32),
        expiresAt: expiresAt,
        issuedAt: issuedAt
    )
    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    #expect(parts.count == 3)
    let payloadData = try #require(base64URLDecodedData(String(parts[1])))
    let payload = try #require(try JSONSerialization.jsonObject(with: payloadData) as? [String: Any])

    #expect(payload["iss"] as? String == "mapofagents")
    #expect(payload["aud"] as? String == "codex-app-server")
    #expect(payload["sub"] as? String == "mapofagents-pairing")
    #expect((payload["iat"] as? NSNumber)?.intValue == 1_000)
    #expect((payload["nbf"] as? NSNumber)?.intValue == 995)
    #expect((payload["exp"] as? NSNumber)?.intValue == 1_600)
    #expect(MapofAgentsMacPairingService.signedBearerExpiration(token) == expiresAt)
}

@Test
func pairingHostSecretPersistsAcrossSessionsWithOwnerOnlyPermissions() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-pairing-secret-tests-\(UUID().uuidString)", isDirectory: true)
    let secretURL = directory.appendingPathComponent("mac-lan-app-server.shared-secret")
    defer {
        try? FileManager.default.removeItem(at: directory)
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let legacyTokenURL = directory.appendingPathComponent("mac-lan-app-server.token")
    try "legacy-short-lived-token".write(to: legacyTokenURL, atomically: true, encoding: .utf8)

    let first = try MapofAgentsMacPairingService.ensureStableHostSecret(in: directory)
    let second = try MapofAgentsMacPairingService.ensureStableHostSecret(in: directory)
    let attributes = try FileManager.default.attributesOfItem(atPath: secretURL.path)
    let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue

    #expect(first == second)
    #expect(first.count >= 32)
    #expect(permissions == 0o600)
    #expect(FileManager.default.fileExists(atPath: legacyTokenURL.path) == false)
}

@Test
func pairingHostIdentityIsRandomStableAndMigratesExistingValue() throws {
    let firstDirectory = temporaryPairingDirectory("host-id-first")
    let secondDirectory = temporaryPairingDirectory("host-id-second")
    let legacyDirectory = temporaryPairingDirectory("host-id-legacy")
    defer {
        try? FileManager.default.removeItem(at: firstDirectory)
        try? FileManager.default.removeItem(at: secondDirectory)
        try? FileManager.default.removeItem(at: legacyDirectory)
    }

    let first = try MapofAgentsMacPairingService.persistentHostID(
        in: firstDirectory,
        hostName: "Same Host Name"
    )
    let afterRename = try MapofAgentsMacPairingService.persistentHostID(
        in: firstDirectory,
        hostName: "Renamed Host"
    )
    let otherMachine = try MapofAgentsMacPairingService.persistentHostID(
        in: secondDirectory,
        hostName: "Same Host Name"
    )

    try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
    try "paired-mac-existing".write(
        to: legacyDirectory.appendingPathComponent("pairing-host-id.txt"),
        atomically: true,
        encoding: .utf8
    )
    let migrated = try MapofAgentsMacPairingService.persistentHostID(
        in: legacyDirectory,
        hostName: "Ignored"
    )

    #expect(first == afterRename)
    #expect(first != otherMachine)
    #expect(first.rawValue.hasPrefix("paired-mac-"))
    #expect(migrated == HostID(rawValue: "paired-mac-existing"))
}

@Test
func macPairingAppServerBindsOnlyToLoopback() {
    let supportDirectory = URL(
        fileURLWithPath: "/Users/example/Library/Application Support/mapofagents",
        isDirectory: true
    )
    let arguments = MapofAgentsMacPairingService.appServerArguments(
        port: 19_001,
        supportDirectory: supportDirectory
    )

    #expect(arguments.contains("ws://127.0.0.1:19001"))
    #expect(arguments.contains(where: { $0.contains("0.0.0.0") }) == false)
}

@Test
func macPairingConfiguresPrivateForegroundTLSRouteAndReturnsMagicDNSEndpoint() throws {
    let port = 19_001
    let environment = pairingCommandEnvironment(
        dnsName: "example-host.example-tailnet.ts.net."
    )

    let endpoint = try MapofAgentsMacPairingService.prepareSecureTailnetRoute(
        port: port,
        commands: environment
    )
    let serveArguments = MapofAgentsMacPairingService.tailscaleServeArguments(port: port)
    let exchangeArguments = MapofAgentsMacPairingService.tailscaleCredentialExchangeServeArguments(
        loopbackPort: 19_002,
        httpsPort: 8_443
    )

    #expect(serveArguments == [
        "serve",
        "--yes",
        "--tls-terminated-tcp=443",
        "tcp://127.0.0.1:19001",
    ])
    #expect(serveArguments.contains(where: { $0.localizedCaseInsensitiveContains("funnel") }) == false)
    #expect(exchangeArguments == [
        "serve",
        "--yes",
        "--https=8443",
        "http://127.0.0.1:19002",
    ])
    #expect(exchangeArguments.contains(where: { $0.localizedCaseInsensitiveContains("funnel") }) == false)
    #expect(serveArguments.contains("--bg") == false)
    #expect(exchangeArguments.contains("--bg") == false)
    #expect(endpoint.kind == .tailnet)
    #expect(endpoint.url.absoluteString == "wss://example-host.example-tailnet.ts.net")
    #expect(endpoint.isIPhoneCompanionConnectable)
}

@Test
func macPairingRejectsStatusWithoutCertificateEligibleMagicDNSName() {
    let environment = pairingCommandEnvironment(dnsName: "example-host.local")

    #expect(throws: MapofAgentsPairingError.self) {
        _ = try MapofAgentsMacPairingService.prepareSecureTailnetRoute(
            port: 19_001,
            commands: environment
        )
    }
}

@Test
func macPairingDoesNotRequireTailscaleToBeInstalledInTests() {
    let environment = MapofAgentsMacPairingService.CommandEnvironment(
        codexExecutableURL: { URL(fileURLWithPath: "/usr/bin/codex") },
        tailscaleExecutableURL: { nil },
        run: { _, _ in pairingCommandResult(status: 2, stderr: "Should not run") }
    )

    do {
        _ = try MapofAgentsMacPairingService.prepareSecureTailnetRoute(
            port: 19_001,
            commands: environment
        )
        Issue.record("Expected missing Tailscale discovery to fail.")
    } catch let error as MapofAgentsPairingError {
        guard case .tailscaleNotInstalled = error else {
            Issue.record("Expected tailscaleNotInstalled, got \(error).")
            return
        }
    } catch {
        Issue.record("Expected MapofAgentsPairingError, got \(error).")
    }
}

@Test
func macPairingPayloadBuilderRejectsCleartextFallbackEndpoints() throws {
    let cleartextURL = try #require(URL(string: "ws://example-host.local:19001"))
    let endpoint = MapofAgentsPairingEndpoint(
        kind: .local,
        url: cleartextURL,
        label: "example-host.local"
    )

    #expect(throws: MapofAgentsPairingError.self) {
        _ = try MapofAgentsMacPairingService.makePayload(
            enrollmentToken: "example-enrollment",
            credentialExchangeURL: try #require(URL(string: "https://example-host.example-tailnet.ts.net:8443/v1/pairing")),
            supportDirectory: FileManager.default.temporaryDirectory,
            expiresAt: Date().addingTimeInterval(60),
            endpoints: [endpoint]
        )
    }
}

@Test
func macPairingSurfacesTailscaleServeFailure() {
    let environment = pairingCommandEnvironment(
        dnsName: "example-host.example-tailnet.ts.net",
        serveStatus: 1,
        serveError: "HTTPS certificates are not enabled"
    )

    do {
        _ = try MapofAgentsMacPairingService.prepareSecureTailnetRoute(
            port: 19_001,
            commands: environment
        )
        Issue.record("Expected Tailscale Serve configuration to fail.")
    } catch let error as MapofAgentsPairingError {
        guard case .tailscaleServeFailed(let message) = error else {
            Issue.record("Expected tailscaleServeFailed, got \(error).")
            return
        }
        #expect(message.contains("HTTPS certificates are not enabled"))
    } catch {
        Issue.record("Expected MapofAgentsPairingError, got \(error).")
    }
}

@Test
func macPairingReassertsBothPrivateServeRoutes() throws {
    let recorder = PairingCommandRecorder()
    let environment = pairingCommandEnvironment(
        dnsName: "example-host.example-tailnet.ts.net",
        recorder: recorder
    )

    let endpoint = try MapofAgentsMacPairingService.prepareSecureTailnetRoutes(
        appServerPort: 19_001,
        credentialExchangePort: 19_002,
        credentialExchangeHTTPSPort: 8_443,
        commands: environment
    )
    let serveCommands = recorder.arguments.filter { $0.first == "serve" }

    #expect(endpoint.url.absoluteString == "wss://example-host.example-tailnet.ts.net")
    #expect(serveCommands == [
        MapofAgentsMacPairingService.tailscaleServeArguments(port: 19_001),
        MapofAgentsMacPairingService.tailscaleCredentialExchangeServeArguments(
            loopbackPort: 19_002,
            httpsPort: 8_443
        ),
    ])
    #expect(serveCommands.flatMap { $0 }.contains(where: { $0.localizedCaseInsensitiveContains("funnel") }) == false)
}

@Test
func macPairingMigratesLegacyBackgroundRoutesOnceWithoutTouchingFreshInstalls() throws {
    let freshDirectory = temporaryPairingDirectory("serve-migration-fresh")
    let legacyDirectory = temporaryPairingDirectory("serve-migration-legacy")
    defer {
        try? FileManager.default.removeItem(at: freshDirectory)
        try? FileManager.default.removeItem(at: legacyDirectory)
    }
    try FileManager.default.createDirectory(at: freshDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)

    let freshRecorder = PairingCommandRecorder()
    let freshEnvironment = pairingCommandEnvironment(
        dnsName: "example-host.example-tailnet.ts.net",
        recorder: freshRecorder
    )
    try MapofAgentsMacPairingService.migrateLegacyBackgroundRoutesIfNeeded(
        in: freshDirectory,
        commands: freshEnvironment
    )
    #expect(freshRecorder.arguments.isEmpty)

    try MapofAgentsPrivateFile.write(
        Data("test-only-legacy-secret".utf8),
        to: legacyDirectory.appendingPathComponent("mac-lan-app-server.shared-secret")
    )
    let legacyRecorder = PairingCommandRecorder()
    let legacyEnvironment = pairingCommandEnvironment(
        dnsName: "example-host.example-tailnet.ts.net",
        recorder: legacyRecorder
    )
    try MapofAgentsMacPairingService.migrateLegacyBackgroundRoutesIfNeeded(
        in: legacyDirectory,
        commands: legacyEnvironment
    )
    #expect(legacyRecorder.arguments == MapofAgentsMacPairingService.legacyBackgroundServeDisableArguments)

    try MapofAgentsMacPairingService.migrateLegacyBackgroundRoutesIfNeeded(
        in: legacyDirectory,
        commands: legacyEnvironment
    )
    #expect(legacyRecorder.arguments == MapofAgentsMacPairingService.legacyBackgroundServeDisableArguments)
    #expect(try ownerPermissions(of: legacyDirectory.appendingPathComponent("foreground-tailscale-serve-v1")) == 0o600)
}

@Test
func credentialRegistryConsumesEnrollmentOnceAndStoresOnlyDigests() throws {
    let directory = temporaryPairingDirectory("registry-one-time")
    defer { try? FileManager.default.removeItem(at: directory) }
    let registryURL = directory.appendingPathComponent("pairing-credential-registry.json")
    let now = Date(timeIntervalSince1970: 1_000)
    let registry = try MapofAgentsCredentialRegistry(fileURL: registryURL)
    let enrollmentToken = try registry.issueEnrollment(
        expiresAt: now.addingTimeInterval(60),
        now: now,
        token: "test-only-one-time-enrollment"
    )
    let registration = try registry.registerDevice(
        enrollmentToken: enrollmentToken,
        deviceName: "Example iPhone",
        now: now,
        deviceID: "device-1",
        refreshCredential: "raw-refresh-credential"
    )

    #expect(registration.deviceID == "device-1")
    #expect(registration.refreshCredential == "raw-refresh-credential")
    do {
        _ = try registry.registerDevice(
            enrollmentToken: enrollmentToken,
            deviceName: "Replay",
            now: now,
            deviceID: "device-2",
            refreshCredential: "other-refresh"
        )
        Issue.record("Expected a consumed enrollment token to be rejected.")
    } catch let error as MapofAgentsCredentialExchangeError {
        #expect(error == .enrollmentInvalid)
    }

    let rawRegistry = try String(contentsOf: registryURL, encoding: .utf8)
    let attributes = try FileManager.default.attributesOfItem(atPath: registryURL.path)
    #expect(rawRegistry.contains("test-only-one-time-enrollment") == false)
    #expect(rawRegistry.contains("raw-refresh-credential") == false)
    #expect(rawRegistry.contains(MapofAgentsCredentialSecrets.hash("raw-refresh-credential")))
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test
func credentialRegistryIdempotentlyReturnsClientEnrollmentAfterLostResponse() throws {
    let directory = temporaryPairingDirectory("registry-idempotent-enrollment")
    defer { try? FileManager.default.removeItem(at: directory) }
    let registry = try MapofAgentsCredentialRegistry(
        fileURL: directory.appendingPathComponent("registry.json")
    )
    let now = Date(timeIntervalSince1970: 1_500)
    _ = try registry.issueEnrollment(
        expiresAt: now.addingTimeInterval(60),
        now: now,
        token: "test-only-retryable-enrollment"
    )

    let first = try registry.registerDevice(
        enrollmentToken: "test-only-retryable-enrollment",
        deviceName: "Example iPhone",
        now: now,
        deviceID: "stable-device",
        refreshCredential: "client-generated-refresh"
    )
    let retried = try registry.registerDevice(
        enrollmentToken: "test-only-retryable-enrollment",
        deviceName: "Example iPhone",
        now: now.addingTimeInterval(1),
        deviceID: "stable-device",
        refreshCredential: "client-generated-refresh"
    )

    #expect(first.deviceID == retried.deviceID)
    #expect(first.refreshCredential == retried.refreshCredential)
    #expect(registry.snapshotForTesting().devices.count == 1)
    #expect(throws: MapofAgentsCredentialExchangeError.self) {
        _ = try registry.registerDevice(
            enrollmentToken: "retryable-enrollment",
            deviceName: "Attacker",
            now: now.addingTimeInterval(2),
            deviceID: "stable-device",
            refreshCredential: "different-refresh"
        )
    }
}

@Test
func credentialRegistryRejectsASecondEnrollmentThatReusesAnActiveDeviceID() throws {
    let directory = temporaryPairingDirectory("registry-device-id-collision")
    defer { try? FileManager.default.removeItem(at: directory) }
    let registry = try MapofAgentsCredentialRegistry(
        fileURL: directory.appendingPathComponent("registry.json")
    )
    let now = Date(timeIntervalSince1970: 1_700)
    let firstEnrollment = try registry.issueEnrollment(
        expiresAt: now.addingTimeInterval(60),
        now: now,
        token: "test-only-first-enrollment"
    )
    _ = try registry.registerDevice(
        enrollmentToken: firstEnrollment,
        deviceName: "Original iPhone",
        now: now,
        deviceID: "stable-device-id",
        refreshCredential: "original-refresh-credential"
    )
    let secondEnrollment = try registry.issueEnrollment(
        expiresAt: now.addingTimeInterval(60),
        now: now,
        token: "test-only-second-enrollment"
    )

    do {
        _ = try registry.registerDevice(
            enrollmentToken: secondEnrollment,
            deviceName: "Impersonating iPhone",
            now: now,
            deviceID: "stable-device-id",
            refreshCredential: "replacement-refresh-credential"
        )
        Issue.record("A distinct enrollment must not seize an active device ID")
    } catch let error as MapofAgentsCredentialExchangeError {
        #expect(error == .enrollmentInvalid)
    }

    try registry.validateRefreshCredential(
        deviceID: "stable-device-id",
        refreshCredential: "original-refresh-credential",
        now: now.addingTimeInterval(1)
    )
    #expect(throws: MapofAgentsCredentialExchangeError.self) {
        try registry.validateRefreshCredential(
            deviceID: "stable-device-id",
            refreshCredential: "replacement-refresh-credential",
            now: now.addingTimeInterval(1)
        )
    }

    // Rejecting the collision must not consume the second one-time enrollment;
    // it remains usable for a genuinely new device identity.
    let secondRegistration = try registry.registerDevice(
        enrollmentToken: secondEnrollment,
        deviceName: "Second iPhone",
        now: now.addingTimeInterval(2),
        deviceID: "second-device-id",
        refreshCredential: "second-refresh-credential"
    )
    #expect(secondRegistration.deviceID == "second-device-id")
    #expect(Set(registry.activeDeviceSummaries().map(\.id)) == ["stable-device-id", "second-device-id"])
}

@Test
func hostProcessGenerationTrackerRejectsLateTerminationFromAnOlderProcess() {
    var tracker = MapofAgentsHostProcessGenerationTracker()
    let oldGeneration = UUID()
    let replacementGeneration = UUID()

    tracker.install(oldGeneration)
    tracker.install(replacementGeneration)

    let retiredOldGeneration = tracker.retire(oldGeneration)
    #expect(!retiredOldGeneration)
    #expect(tracker.current == replacementGeneration)
    let retiredReplacementGeneration = tracker.retire(replacementGeneration)
    #expect(retiredReplacementGeneration)
    #expect(tracker.current == nil)
}

@Test
func credentialRegistryRejectsInvalidAndExpiredEnrollment() throws {
    let directory = temporaryPairingDirectory("registry-expiration")
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date(timeIntervalSince1970: 2_000)
    let registry = try MapofAgentsCredentialRegistry(
        fileURL: directory.appendingPathComponent("registry.json")
    )
    _ = try registry.issueEnrollment(
        expiresAt: now.addingTimeInterval(1),
        now: now,
        token: "expires-once"
    )

    do {
        _ = try registry.registerDevice(
            enrollmentToken: "not-issued",
            deviceName: "Example",
            now: now
        )
        Issue.record("Expected an invalid enrollment to fail.")
    } catch let error as MapofAgentsCredentialExchangeError {
        #expect(error == .enrollmentInvalid)
    }

    do {
        _ = try registry.registerDevice(
            enrollmentToken: "expires-once",
            deviceName: "Example",
            now: now.addingTimeInterval(2)
        )
        Issue.record("Expected an expired enrollment to fail.")
    } catch let error as MapofAgentsCredentialExchangeError {
        #expect(error == .enrollmentExpired)
    }
}

@Test
func credentialRefreshRevocationAndRestartPersistence() throws {
    let directory = temporaryPairingDirectory("registry-restart")
    defer { try? FileManager.default.removeItem(at: directory) }
    let registryURL = directory.appendingPathComponent("registry.json")
    let now = Date(timeIntervalSince1970: 3_000)
    var registry = try MapofAgentsCredentialRegistry(fileURL: registryURL)
    _ = try registry.issueEnrollment(
        expiresAt: now.addingTimeInterval(60),
        now: now,
        token: "enroll-device"
    )
    _ = try registry.registerDevice(
        enrollmentToken: "enroll-device",
        deviceName: "Example",
        now: now,
        deviceID: "device-1",
        refreshCredential: "refresh-device"
    )
    try registry.validateRefreshCredential(
        deviceID: "device-1",
        refreshCredential: "refresh-device",
        now: now.addingTimeInterval(1)
    )
    try registry.revoke(
        deviceID: "device-1",
        refreshCredential: "refresh-device",
        now: now.addingTimeInterval(2)
    )

    registry = try MapofAgentsCredentialRegistry(fileURL: registryURL)
    do {
        try registry.validateRefreshCredential(
            deviceID: "device-1",
            refreshCredential: "refresh-device",
            now: now.addingTimeInterval(3)
        )
        Issue.record("Expected a revoked device to remain revoked after restart.")
    } catch let error as MapofAgentsCredentialExchangeError {
        #expect(error == .deviceRevoked)
    }
}

@Test
func credentialRegistryLetsHostOwnerListAndRevokeLostDevices() throws {
    let directory = temporaryPairingDirectory("registry-host-revoke")
    defer { try? FileManager.default.removeItem(at: directory) }
    let registryURL = directory.appendingPathComponent("registry.json")
    let now = Date(timeIntervalSince1970: 3_500)
    let registry = try MapofAgentsCredentialRegistry(fileURL: registryURL)
    _ = try registry.issueEnrollment(
        expiresAt: now.addingTimeInterval(60),
        now: now,
        token: "test-only-host-revoke-enrollment"
    )
    _ = try registry.registerDevice(
        enrollmentToken: "test-only-host-revoke-enrollment",
        deviceName: "Lost iPhone",
        now: now,
        deviceID: "lost-device",
        refreshCredential: "lost-refresh"
    )

    let devices = registry.activeDeviceSummaries()
    #expect(devices.map(\.id) == ["lost-device"])
    #expect(devices.first?.name == "Lost iPhone")

    try registry.revokeDevice(deviceID: "lost-device", now: now.addingTimeInterval(1))
    #expect(registry.activeDeviceSummaries().isEmpty)
    #expect(throws: MapofAgentsCredentialExchangeError.self) {
        try registry.validateRefreshCredential(
            deviceID: "lost-device",
            refreshCredential: "lost-refresh",
            now: now.addingTimeInterval(2)
        )
    }

    let restored = try MapofAgentsCredentialRegistry(fileURL: registryURL)
    #expect(restored.activeDeviceSummaries().isEmpty)
}

@Test
func credentialRegistryStaysWithinConfiguredBounds() throws {
    let directory = temporaryPairingDirectory("registry-bounds")
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date(timeIntervalSince1970: 4_000)
    let registry = try MapofAgentsCredentialRegistry(
        fileURL: directory.appendingPathComponent("registry.json"),
        limits: .init(pendingEnrollments: 2, devices: 2)
    )
    for token in ["pending-1", "pending-2", "pending-3"] {
        _ = try registry.issueEnrollment(
            expiresAt: now.addingTimeInterval(60),
            now: now,
            token: token
        )
    }
    #expect(registry.snapshotForTesting().pendingEnrollments.count == 2)

    _ = try registry.registerDevice(
        enrollmentToken: "pending-2",
        deviceName: "One",
        now: now,
        deviceID: "device-1",
        refreshCredential: "refresh-1"
    )
    _ = try registry.registerDevice(
        enrollmentToken: "pending-3",
        deviceName: "Two",
        now: now,
        deviceID: "device-2",
        refreshCredential: "refresh-2"
    )
    _ = try registry.issueEnrollment(
        expiresAt: now.addingTimeInterval(60),
        now: now,
        token: "pending-full"
    )
    #expect(throws: MapofAgentsCredentialExchangeError.self) {
        _ = try registry.registerDevice(
            enrollmentToken: "pending-full",
            deviceName: "Three",
            now: now,
            deviceID: "device-3",
            refreshCredential: "refresh-3"
        )
    }
    try registry.revoke(
        deviceID: "device-1",
        refreshCredential: "refresh-1",
        now: now
    )
    #expect(throws: MapofAgentsCredentialExchangeError.self) {
        _ = try registry.registerDevice(
            enrollmentToken: "pending-full",
            deviceName: "Three",
            now: now.addingTimeInterval(1),
            deviceID: "device-3",
            refreshCredential: "refresh-3"
        )
    }
    let afterTombstoneExpiry = now.addingTimeInterval(
        MapofAgentsCredentialRegistry.revokedDeviceIDRetention + 1
    )
    _ = try registry.issueEnrollment(
        expiresAt: afterTombstoneExpiry.addingTimeInterval(60),
        now: afterTombstoneExpiry,
        token: "test-only-pending-after-revocation"
    )
    _ = try registry.registerDevice(
        enrollmentToken: "test-only-pending-after-revocation",
        deviceName: "Three",
        now: afterTombstoneExpiry,
        deviceID: "device-3",
        refreshCredential: "refresh-3"
    )
    #expect(registry.snapshotForTesting().devices.count == 2)
}

@Test
func revokedDeviceIDCannotBeReusedWhileAnOlderJWTCouldRemainValid() throws {
    let directory = temporaryPairingDirectory("registry-revoked-id-reuse")
    defer { try? FileManager.default.removeItem(at: directory) }
    let registryURL = directory.appendingPathComponent("registry.json")
    let secretURL = directory.appendingPathComponent("host-secret")
    let now = Date(timeIntervalSince1970: 4_500)
    try MapofAgentsPrivateFile.write(Data("test-only-reuse-secret".utf8), to: secretURL)
    let registry = try MapofAgentsCredentialRegistry(fileURL: registryURL)

    _ = try registry.issueEnrollment(
        expiresAt: now.addingTimeInterval(60),
        now: now,
        token: "test-only-original-enrollment"
    )
    _ = try registry.registerDevice(
        enrollmentToken: "test-only-original-enrollment",
        deviceName: "Original iPhone",
        now: now,
        deviceID: "stable-device-id",
        refreshCredential: "original-refresh"
    )
    let oldToken = try MapofAgentsMacPairingService.signedBearerToken(
        secret: "test-only-reuse-secret",
        subject: "mapofagents-device:stable-device-id",
        expiresAt: now.addingTimeInterval(MapofAgentsCredentialExchangeHandler.accessTokenDuration),
        issuedAt: now
    )
    try registry.revokeDevice(deviceID: "stable-device-id", now: now.addingTimeInterval(1))

    // Registering a different device must not discard the revoked identity.
    _ = try registry.issueEnrollment(
        expiresAt: now.addingTimeInterval(60),
        now: now.addingTimeInterval(2),
        token: "test-only-other-enrollment"
    )
    _ = try registry.registerDevice(
        enrollmentToken: "test-only-other-enrollment",
        deviceName: "Other iPhone",
        now: now.addingTimeInterval(2),
        deviceID: "other-device-id",
        refreshCredential: "other-refresh"
    )
    _ = try registry.issueEnrollment(
        expiresAt: now.addingTimeInterval(60),
        now: now.addingTimeInterval(3),
        token: "test-only-reuse-enrollment"
    )
    do {
        _ = try registry.registerDevice(
            enrollmentToken: "test-only-reuse-enrollment",
            deviceName: "Replacement iPhone",
            now: now.addingTimeInterval(3),
            deviceID: "stable-device-id",
            refreshCredential: "replacement-refresh"
        )
        Issue.record("A revoked device ID must remain reserved for the JWT lifetime")
    } catch let error as MapofAgentsCredentialExchangeError {
        #expect(error == .enrollmentInvalid)
    }

    let validator = MapofAgentsPairingAccessTokenValidator(
        sharedSecretURL: secretURL,
        registryURL: registryURL
    )
    #expect(throws: MapofAgentsPairingGatewayError.deviceRevoked) {
        _ = try validator.validate(oldToken, now: now.addingTimeInterval(4))
    }
}

@Test
func exchangeHandlerIssuesShortLivedDeviceJWTAndRevokesRefresh() throws {
    let directory = temporaryPairingDirectory("exchange-handler")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let secretURL = directory.appendingPathComponent("host-secret")
    try "stable-host-secret".write(to: secretURL, atomically: true, encoding: .utf8)
    let registry = try MapofAgentsCredentialRegistry(
        fileURL: directory.appendingPathComponent("registry.json")
    )
    let now = Date(timeIntervalSince1970: 5_000)
    let endpoint = MapofAgentsPairingEndpoint(
        kind: .tailnet,
        url: try #require(URL(string: "wss://example-host.example-tailnet.ts.net")),
        label: "Example Mac"
    )
    let revocations = PairingStringRecorder()
    let registryURL = directory.appendingPathComponent("registry.json")
    let handler = MapofAgentsCredentialExchangeHandler(
        registry: registry,
        hostID: HostID(rawValue: "host-1"),
        sharedSecretURL: secretURL,
        endpoints: [endpoint],
        supportDirectory: "/Users/example/Library/Application Support/mapofagents",
        now: { now },
        onDeviceRevoked: { revocations.append($0) }
    )
    let enrollmentToken = try handler.issueEnrollment(expiresAt: now.addingTimeInterval(60))
    let enrollment = try handler.enroll(
        MapofAgentsEnrollmentRequest(
            enrollmentToken: enrollmentToken,
            deviceName: "Example iPhone"
        )
    )
    let tokenPayload = try jwtPayload(enrollment.accessToken)
    #expect(tokenPayload["sub"] as? String == "mapofagents-device:\(enrollment.deviceID)")
    #expect(enrollment.accessTokenExpiresAt == now.addingTimeInterval(5 * 60))
    let validator = MapofAgentsPairingAccessTokenValidator(
        sharedSecretURL: secretURL,
        registryURL: registryURL
    )
    #expect(
        try validator.validate(enrollment.accessToken, now: now)
            == MapofAgentsPairingAccessTokenClaims(
                deviceID: enrollment.deviceID,
                expiresAt: enrollment.accessTokenExpiresAt
            )
    )
    #expect(throws: MapofAgentsPairingGatewayError.accessTokenExpired) {
        _ = try validator.validate(
            enrollment.accessToken,
            now: enrollment.accessTokenExpiresAt
        )
    }

    let refreshRequest = MapofAgentsRefreshRequest(
        hostID: HostID(rawValue: "host-1"),
        deviceID: enrollment.deviceID,
        refreshCredential: enrollment.refreshCredential
    )
    _ = try handler.refresh(refreshRequest)
    _ = try handler.revoke(refreshRequest)
    #expect(revocations.values == [enrollment.deviceID])
    #expect(throws: MapofAgentsPairingGatewayError.deviceRevoked) {
        _ = try validator.validate(enrollment.accessToken, now: now)
    }
    #expect(throws: MapofAgentsCredentialExchangeError.self) {
        _ = try handler.refresh(refreshRequest)
    }
}

@Test
func pairingGatewayRejectsTamperedOrMalformedWebSocketCredentials() throws {
    let directory = temporaryPairingDirectory("gateway-token-validation")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let now = Date(timeIntervalSince1970: 7_000)
    let secretURL = directory.appendingPathComponent("host-secret")
    let registryURL = directory.appendingPathComponent("registry.json")
    try MapofAgentsPrivateFile.write(Data("test-only-gateway-secret".utf8), to: secretURL)
    let registry = try MapofAgentsCredentialRegistry(fileURL: registryURL)
    let enrollment = try registry.issueEnrollment(
        expiresAt: now.addingTimeInterval(60),
        now: now,
        token: "test-only-gateway-enrollment"
    )
    _ = try registry.registerDevice(
        enrollmentToken: enrollment,
        deviceName: "Example iPhone",
        now: now,
        deviceID: "device-1",
        refreshCredential: "test-only-refresh"
    )
    let token = try MapofAgentsMacPairingService.signedBearerToken(
        secret: "test-only-gateway-secret",
        subject: "mapofagents-device:device-1",
        expiresAt: now.addingTimeInterval(300),
        issuedAt: now
    )
    let validator = MapofAgentsPairingAccessTokenValidator(
        sharedSecretURL: secretURL,
        registryURL: registryURL
    )
    var tampered = token
    let signatureStart = tampered.index(after: try #require(tampered.lastIndex(of: ".")))
    let replacement = tampered[signatureStart] == "A" ? "B" : "A"
    tampered.replaceSubrange(signatureStart...signatureStart, with: replacement)
    #expect(throws: MapofAgentsPairingGatewayError.invalidAccessToken) {
        _ = try validator.validate(tampered, now: now)
    }

    let handshake = Data(
        "GET / HTTP/1.1\r\nHost: example-host\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGVzdC1vbmx5LWtleQ==\r\nAuthorization: Bearer \(token)\r\n\r\n".utf8
    )
    #expect(try MapofAgentsPairingGatewayHandshake.bearerToken(in: handshake) == token)
    let duplicate = Data(
        "GET / HTTP/1.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGVzdA==\r\nAuthorization: Bearer \(token)\r\nAuthorization: Bearer \(token)\r\n\r\n".utf8
    )
    #expect(throws: MapofAgentsPairingGatewayError.invalidHandshake) {
        _ = try MapofAgentsPairingGatewayHandshake.bearerToken(in: duplicate)
    }
}

@Test
func pairingGatewayConnectionLeaseExpiresAndCanBeCancelled() async throws {
    let expired = PairingStringRecorder()
    let lease = MapofAgentsPairingConnectionLease()
    lease.start(expiresAt: Date().addingTimeInterval(0.03)) {
        expired.append("expired")
    }
    for _ in 0..<50 where expired.values.isEmpty {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(expired.values == ["expired"])

    let cancelled = PairingStringRecorder()
    let cancelledLease = MapofAgentsPairingConnectionLease()
    cancelledLease.start(expiresAt: Date().addingTimeInterval(0.03)) {
        cancelled.append("should-not-run")
    }
    cancelledLease.cancel()
    try await Task.sleep(for: .milliseconds(120))
    #expect(cancelled.values.isEmpty)
}

@Test
func pairingHostOwnershipRejectsMissingOrUntrackedPIDFiles() throws {
    let directory = temporaryPairingDirectory("host-ownership")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    #expect(
        MapofAgentsMacPairingService.isOwnedHostServerRunning(
            port: 19_001,
            supportDirectory: directory
        ) == false
    )
    try MapofAgentsPrivateFile.write(
        Data("999999".utf8),
        to: directory.appendingPathComponent("mac-lan-app-server.pid")
    )
    #expect(
        MapofAgentsMacPairingService.isOwnedHostServerRunning(
            port: 19_001,
            supportDirectory: directory
        ) == false
    )
    #expect(MapofAgentsMacPairingService.defaultPairingGatewayPort != UInt16(MapofAgentsMacPairingService.defaultPort))
}

private func temporaryPairingDirectory(_ suffix: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-\(suffix)-\(UUID().uuidString)", isDirectory: true)
}

private func jwtPayload(_ token: String) throws -> [String: Any] {
    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    let data = try #require(parts.count == 3 ? base64URLDecodedData(String(parts[1])) : nil)
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private final class PairingCommandRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [[String]] = []

    var arguments: [[String]] {
        lock.withLock { storage }
    }

    func append(_ arguments: [String]) {
        lock.withLock { storage.append(arguments) }
    }
}

private final class PairingStringRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.withLock { storage }
    }

    func append(_ value: String) {
        lock.withLock { storage.append(value) }
    }
}

@Test
func pairedHostAccessProviderUsesInitialJWTThenSingleFlightRefreshesEachReconnect() async throws {
    let vault = TestPairingCredentialVault(credential: "refresh-secret")
    let exchange = TestCredentialExchangeClient()
    let initialExpiration = Date().addingTimeInterval(60)
    let provider = MapofAgentsPairedHostAccessTokenProvider(
        hostID: HostID(rawValue: "host-1"),
        deviceID: "device-1",
        exchangeURL: try #require(URL(string: "https://example-host.example-tailnet.ts.net:8443/v1/pairing")),
        initialAccessToken: "initial-access",
        initialAccessTokenExpiresAt: initialExpiration,
        credentialVault: vault,
        exchangeClient: exchange
    )

    #expect(
        try await provider.accessToken()
            == AppServerAccessToken(value: "initial-access", expiresAt: initialExpiration)
    )
    async let first = provider.accessToken()
    async let second = provider.accessToken()
    let concurrentTokens = try await [first, second]
    #expect(concurrentTokens.map { $0?.value } == ["access-1", "access-1"])
    #expect(concurrentTokens.allSatisfy { $0?.expiresAt != nil })
    #expect(await exchange.refreshCount == 1)

    #expect(try await provider.accessToken()?.value == "access-2")
    #expect(await exchange.refreshCount == 2)
    #expect(vault.loadedReferences == ["host-1/device-1", "host-1/device-1"])
}

@Test
func pairedHostAccessProviderRefreshesInsteadOfUsingExpiredInitialJWT() async throws {
    let vault = TestPairingCredentialVault(credential: "refresh-secret")
    let exchange = TestCredentialExchangeClient()
    let provider = MapofAgentsPairedHostAccessTokenProvider(
        hostID: HostID(rawValue: "host-1"),
        deviceID: "device-1",
        exchangeURL: try #require(URL(string: "https://example-host.example-tailnet.ts.net:8443/v1/pairing")),
        initialAccessToken: "expired-access",
        initialAccessTokenExpiresAt: Date().addingTimeInterval(-1),
        credentialVault: vault,
        exchangeClient: exchange
    )

    let token = try await provider.accessToken()
    #expect(token?.value == "access-1")
    #expect(token?.expiresAt != nil)
    #expect(await exchange.refreshCount == 1)
}

@Test
func pairedHostCredentialRetirementRevokesBeforeDeletingTheKeychainCredential() async throws {
    let operationRecorder = PairingOperationRecorder()
    let vault = TestPairingCredentialVault(
        credential: "refresh-secret",
        operationRecorder: operationRecorder
    )
    let exchange = TestCredentialExchangeClient(operationRecorder: operationRecorder)
    let host = MapofAgentsPairedHost(
        id: HostID(rawValue: "host-1"),
        name: "Example Mac",
        endpoints: [
            MapofAgentsPairingEndpoint(
                kind: .tailnet,
                url: try #require(URL(string: "wss://example-host.example-tailnet.ts.net")),
                label: "Example Mac"
            ),
        ],
        bearerToken: "",
        credentialExchangeURL: URL(
            string: "https://example-host.example-tailnet.ts.net:8443/v1/pairing"
        ),
        deviceID: "old-device"
    )

    try await MapofAgentsPairingCredentialRetirement.retire(
        host,
        credentialVault: vault,
        credentialExchange: exchange
    )

    #expect(await exchange.revokedDeviceIDs == ["old-device"])
    #expect(vault.loadedReferences == ["host-1/old-device"])
    #expect(vault.deletedReferences == ["host-1/old-device"])
    #expect(operationRecorder.operations == ["load", "revoke", "delete"])
}

@Test
func pairedHostCredentialRetirementKeepsKeychainCredentialWhenRemoteRevokeFails() async throws {
    let operationRecorder = PairingOperationRecorder()
    let vault = TestPairingCredentialVault(
        credential: "refresh-secret",
        operationRecorder: operationRecorder
    )
    let exchange = TestCredentialExchangeClient(
        operationRecorder: operationRecorder,
        revokeError: .listenerFailed("offline")
    )
    let host = MapofAgentsPairedHost(
        id: HostID(rawValue: "host-1"),
        name: "Example Mac",
        endpoints: [
            MapofAgentsPairingEndpoint(
                kind: .tailnet,
                url: try #require(URL(string: "wss://example-host.example-tailnet.ts.net")),
                label: "Example Mac"
            ),
        ],
        bearerToken: "",
        credentialExchangeURL: URL(
            string: "https://example-host.example-tailnet.ts.net:8443/v1/pairing"
        ),
        deviceID: "old-device"
    )

    await #expect(throws: MapofAgentsCredentialExchangeError.self) {
        try await MapofAgentsPairingCredentialRetirement.retire(
            host,
            credentialVault: vault,
            credentialExchange: exchange
        )
    }

    #expect(vault.deletedReferences.isEmpty)
    #expect(operationRecorder.operations == ["load", "revoke"])
}

@Test
func credentialExchangeRuntimeUsesInjectedLoopbackListenerWithoutNetworkOrTailscale() async throws {
    let directory = temporaryPairingDirectory("runtime-injection")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let secretURL = directory.appendingPathComponent("host-secret")
    try "stable-host-secret".write(to: secretURL, atomically: true, encoding: .utf8)
    let listener = TestCredentialExchangeListener()
    let runtime = MapofAgentsCredentialExchangeRuntime { port in
        #expect(port == 19_002)
        return listener
    }
    let endpoint = MapofAgentsPairingEndpoint(
        kind: .tailnet,
        url: try #require(URL(string: "wss://example-host.example-tailnet.ts.net")),
        label: "Example Mac"
    )
    try await runtime.ensureRunning(
        port: 19_002,
        registryURL: directory.appendingPathComponent("registry.json"),
        hostID: HostID(rawValue: "host-1"),
        sharedSecretURL: secretURL,
        endpoints: [endpoint],
        supportDirectory: "/Users/example/Library/Application Support/mapofagents"
    )
    try await runtime.ensureRunning(
        port: 19_002,
        registryURL: directory.appendingPathComponent("registry.json"),
        hostID: HostID(rawValue: "host-1"),
        sharedSecretURL: secretURL,
        endpoints: [endpoint],
        supportDirectory: "/Users/example/Library/Application Support/mapofagents"
    )
    let enrollmentToken = try await runtime.issueEnrollment(
        expiresAt: Date().addingTimeInterval(60)
    )
    let encoder = JSONEncoder()
    let response = try #require(listener.route(
        .init(
            method: "POST",
            path: "/v1/pairing/enroll",
            body: try encoder.encode(
                MapofAgentsEnrollmentRequest(
                    enrollmentToken: enrollmentToken,
                    deviceName: "Example iPhone"
                )
            )
        )
    ))

    #expect(listener.startCount == 1)
    #expect(response.status == 200)
    #expect(response.body.range(of: Data(enrollmentToken.utf8)) == nil)
    await runtime.stop()
}

@Test
func credentialExchangeRuntimeStopCannotBeUndoneByDelayedListenerStartup() async throws {
    let directory = temporaryPairingDirectory("runtime-stop-during-start")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let secretURL = directory.appendingPathComponent("host-secret")
    try "stable-host-secret".write(to: secretURL, atomically: true, encoding: .utf8)
    let listener = SuspendedCredentialExchangeListener()
    let runtime = MapofAgentsCredentialExchangeRuntime { _ in listener }
    let endpoint = MapofAgentsPairingEndpoint(
        kind: .tailnet,
        url: try #require(URL(string: "wss://example-host.example-tailnet.ts.net")),
        label: "Example Mac"
    )

    let startup = Task {
        try await runtime.ensureRunning(
            port: 19_012,
            registryURL: directory.appendingPathComponent("registry.json"),
            hostID: HostID(rawValue: "host-1"),
            sharedSecretURL: secretURL,
            endpoints: [endpoint],
            supportDirectory: "/Users/example/Library/Application Support/mapofagents"
        )
    }
    await listener.waitUntilStartCalled()
    #expect(listener.startCount == 1)

    await runtime.stop()
    do {
        try await startup.value
        Issue.record("A listener that completed after stop must not be promoted")
    } catch is CancellationError {
        // Expected: stop advances the runtime generation before releasing start.
    } catch {
        Issue.record("Unexpected delayed-start error: \(error)")
    }

    #expect(listener.stopCount >= 1)
    #expect(!listener.isReady)
    await #expect(throws: MapofAgentsCredentialExchangeError.self) {
        _ = try await runtime.issueEnrollment(expiresAt: Date().addingTimeInterval(30))
    }
}

@Test
func credentialExchangeRuntimeRejectsStalePromotionDuringOverlappingReplacement() async throws {
    let directory = temporaryPairingDirectory("runtime-overlapping-replacement")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let secretURL = directory.appendingPathComponent("host-secret")
    try "stable-host-secret".write(to: secretURL, atomically: true, encoding: .utf8)
    let delayed = SuspendedCredentialExchangeListener()
    let replacement = TestCredentialExchangeListener()
    let runtime = MapofAgentsCredentialExchangeRuntime { port -> any MapofAgentsCredentialExchangeListening in
        if port == 19_013 {
            return delayed
        }
        return replacement
    }
    let endpoint = MapofAgentsPairingEndpoint(
        kind: .tailnet,
        url: try #require(URL(string: "wss://example-host.example-tailnet.ts.net")),
        label: "Example Mac"
    )

    let staleStartup = Task {
        try await runtime.ensureRunning(
            port: 19_013,
            registryURL: directory.appendingPathComponent("stale-registry.json"),
            hostID: HostID(rawValue: "stale-host"),
            sharedSecretURL: secretURL,
            endpoints: [endpoint],
            supportDirectory: "/Users/example/Library/Application Support/mapofagents"
        )
    }
    await delayed.waitUntilStartCalled()
    #expect(delayed.startCount == 1)

    try await runtime.ensureRunning(
        port: 19_014,
        registryURL: directory.appendingPathComponent("replacement-registry.json"),
        hostID: HostID(rawValue: "replacement-host"),
        sharedSecretURL: secretURL,
        endpoints: [endpoint],
        supportDirectory: "/Users/example/Library/Application Support/mapofagents"
    )

    do {
        try await staleStartup.value
        Issue.record("The stale listener must not replace the newer generation")
    } catch is CancellationError {
        // Expected.
    } catch {
        Issue.record("Unexpected stale-startup error: \(error)")
    }

    #expect(!delayed.isReady)
    #expect(delayed.stopCount >= 1)
    #expect(replacement.isReady)
    #expect(replacement.startCount == 1)
    _ = try await runtime.issueEnrollment(expiresAt: Date().addingTimeInterval(30))
    await runtime.stop()
    #expect(!replacement.isReady)
    #expect(replacement.stopCount == 1)
}

private final class TestCredentialExchangeListener: MapofAgentsCredentialExchangeListening, @unchecked Sendable {
    private let lock = NSLock()
    private var ready = false
    private var starts = 0
    private var stops = 0
    private var router: MapofAgentsCredentialExchangeHTTPRouter?

    var isReady: Bool { lock.withLock { ready } }
    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }

    func start(router: MapofAgentsCredentialExchangeHTTPRouter) async throws {
        lock.withLock {
            self.router = router
            starts += 1
            ready = true
        }
    }

    func stop() async {
        lock.withLock {
            ready = false
            stops += 1
        }
    }

    func route(
        _ request: MapofAgentsCredentialExchangeHTTPRequest
    ) -> MapofAgentsCredentialExchangeHTTPResponse? {
        lock.withLock { router }?.route(request)
    }
}

private final class SuspendedCredentialExchangeListener: MapofAgentsCredentialExchangeListening, @unchecked Sendable {
    private let lock = NSLock()
    private var ready = false
    private var starts = 0
    private var stops = 0
    private var stopped = false
    private var startWaiter: CheckedContinuation<Void, Never>?

    var isReady: Bool { lock.withLock { ready } }
    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }

    func start(router _: MapofAgentsCredentialExchangeHTTPRouter) async throws {
        lock.withLock { starts += 1 }
        await withCheckedContinuation { continuation in
            let resumeImmediately = lock.withLock { () -> Bool in
                if stopped {
                    return true
                }
                startWaiter = continuation
                return false
            }
            if resumeImmediately {
                continuation.resume()
            }
        }
        guard !lock.withLock({ stopped }) else {
            throw CancellationError()
        }
        lock.withLock { ready = true }
    }

    func stop() async {
        let waiter = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            ready = false
            stopped = true
            stops += 1
            defer { startWaiter = nil }
            return startWaiter
        }
        waiter?.resume()
    }

    func waitUntilStartCalled() async {
        for _ in 0..<200 {
            if startCount > 0 { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

private final class TestPairingCredentialVault: MapofAgentsPairingCredentialVault, @unchecked Sendable {
    private let lock = NSLock()
    private let credential: String?
    private let operationRecorder: PairingOperationRecorder?
    private var references: [String] = []
    private var deleted: [String] = []

    init(credential: String?, operationRecorder: PairingOperationRecorder? = nil) {
        self.credential = credential
        self.operationRecorder = operationRecorder
    }

    var loadedReferences: [String] {
        lock.withLock { references }
    }

    var deletedReferences: [String] {
        lock.withLock { deleted }
    }

    func saveRefreshCredential(_ credential: String, hostID: HostID, deviceID: String) throws {}

    func loadRefreshCredential(hostID: HostID, deviceID: String) throws -> String? {
        lock.withLock { references.append("\(hostID.rawValue)/\(deviceID)") }
        operationRecorder?.append("load")
        return credential
    }

    func deleteRefreshCredential(hostID: HostID, deviceID: String) throws {
        lock.withLock { deleted.append("\(hostID.rawValue)/\(deviceID)") }
        operationRecorder?.append("delete")
    }
}

private actor TestCredentialExchangeClient: MapofAgentsCredentialExchanging {
    private(set) var refreshCount = 0
    private(set) var revokedDeviceIDs: [String] = []
    private let operationRecorder: PairingOperationRecorder?
    private let revokeError: MapofAgentsCredentialExchangeError?

    init(
        operationRecorder: PairingOperationRecorder? = nil,
        revokeError: MapofAgentsCredentialExchangeError? = nil
    ) {
        self.operationRecorder = operationRecorder
        self.revokeError = revokeError
    }

    func enroll(
        at exchangeURL: URL,
        enrollmentToken: String,
        deviceName: String
    ) async throws -> MapofAgentsEnrollmentResponse {
        throw MapofAgentsCredentialExchangeError.invalidRequest
    }

    func refresh(
        at exchangeURL: URL,
        request: MapofAgentsRefreshRequest
    ) async throws -> MapofAgentsRefreshResponse {
        refreshCount += 1
        let count = refreshCount
        try await Task.sleep(for: .milliseconds(30))
        return MapofAgentsRefreshResponse(
            accessToken: "access-\(count)",
            accessTokenExpiresAt: Date().addingTimeInterval(300)
        )
    }

    func revoke(
        at exchangeURL: URL,
        request: MapofAgentsRefreshRequest
    ) async throws {
        revokedDeviceIDs.append(request.deviceID)
        operationRecorder?.append("revoke")
        if let revokeError {
            throw revokeError
        }
    }
}

private final class PairingOperationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var operations: [String] {
        lock.withLock { storage }
    }

    func append(_ operation: String) {
        lock.withLock { storage.append(operation) }
    }
}

@Test
func privateFileWritesReplaceExistingEntriesWithOwnerOnlyRegularFiles() throws {
    let directory = temporaryPairingDirectory("private-file")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let fileURL = directory.appendingPathComponent("private.json")
    try Data("old".utf8).write(to: fileURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)

    let replacement = Data("replacement".utf8)
    try MapofAgentsPrivateFile.write(replacement, to: fileURL)

    #expect(try Data(contentsOf: fileURL) == replacement)
    #expect(try ownerPermissions(of: fileURL) == 0o600)

    let targetURL = directory.appendingPathComponent("outside.txt")
    let targetContents = Data("do-not-touch".utf8)
    try targetContents.write(to: targetURL)
    let symlinkURL = directory.appendingPathComponent("private-link.json")
    try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: targetURL)

    let symlinkReplacement = Data("private-link-replacement".utf8)
    try MapofAgentsPrivateFile.write(symlinkReplacement, to: symlinkURL)

    #expect(try Data(contentsOf: targetURL) == targetContents)
    #expect(try Data(contentsOf: symlinkURL) == symlinkReplacement)
    #expect(try ownerPermissions(of: symlinkURL) == 0o600)
    #expect(try symlinkURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false)

    let readSymlinkURL = directory.appendingPathComponent("private-read-link.json")
    try FileManager.default.createSymbolicLink(at: readSymlinkURL, withDestinationURL: targetURL)
    #expect(throws: POSIXError.self) {
        _ = try MapofAgentsPrivateFile.read(readSymlinkURL, maximumBytes: 1_024)
    }
}

@Test
func hostLogDrainBoundsRotatesAndRestrictsEveryRetainedLog() throws {
    let directory = temporaryPairingDirectory("host-log")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let logURL = directory.appendingPathComponent("mac-lan-app-server.log")
    try Data(repeating: 0x4C, count: 80).write(to: logURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: logURL.path)

    let drain = MapofAgentsHostLogDrain(
        pipe: Pipe(),
        fileURL: logURL,
        maximumBytes: 32,
        rotationCount: 2
    )
    try drain.start()
    drain.stop()

    #expect(try Data(contentsOf: logURL) == Data(repeating: 0x4C, count: 32))
    try drain.append(Data(repeating: 0x41, count: 16))
    try drain.append(Data(repeating: 0x42, count: 20))
    try drain.append(Data(repeating: 0x43, count: 40))

    let retainedLogs = [
        logURL,
        URL(fileURLWithPath: "\(logURL.path).1"),
        URL(fileURLWithPath: "\(logURL.path).2"),
    ]
    let expectedContents = [
        Data(repeating: 0x43, count: 32),
        Data(repeating: 0x42, count: 20),
        Data(repeating: 0x41, count: 16),
    ]

    for (url, expected) in zip(retainedLogs, expectedContents) {
        let data = try Data(contentsOf: url)
        #expect(data == expected)
        #expect(data.count <= 32)
        #expect(try ownerPermissions(of: url) == 0o600)
    }
}

@Test
func hostLogDrainRefusesToFollowExistingSymlink() throws {
    let directory = temporaryPairingDirectory("host-log-symlink")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let targetURL = directory.appendingPathComponent("target.txt")
    let targetContents = Data("sentinel".utf8)
    try targetContents.write(to: targetURL)
    let logURL = directory.appendingPathComponent("mac-lan-app-server.log")
    try FileManager.default.createSymbolicLink(at: logURL, withDestinationURL: targetURL)

    let drain = MapofAgentsHostLogDrain(pipe: Pipe(), fileURL: logURL, maximumBytes: 32)
    var didRejectSymlink = false
    do {
        try drain.start()
    } catch {
        didRejectSymlink = true
    }

    #expect(didRejectSymlink)
    #expect(try Data(contentsOf: targetURL) == targetContents)
}

@Test
func foregroundTailnetServeGuardianStopsItsBackendWithTheAppScopedRoute() throws {
    let directory = temporaryPairingDirectory("foreground-serve-guardian")
    defer {
        MapofAgentsTailnetServeRegistry.stopAll()
        try? FileManager.default.removeItem(at: directory)
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let pidURL = directory.appendingPathComponent("backend.pid")
    let backendScript = "echo $$ > '\(pidURL.path)'; trap 'exit 0' TERM INT HUP; while :; do sleep 1; done"

    try MapofAgentsTailnetServeRegistry.ensureRoute(
        key: "test-route",
        executableURL: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", backendScript],
        supportDirectory: directory
    )

    #expect(MapofAgentsTailnetServeRegistry.activeRouteCountForTesting() == 1)
    let pidText = try String(contentsOf: pidURL, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let backendPID = try #require(Int32(pidText))
    #expect(Darwin.kill(backendPID, 0) == 0)

    MapofAgentsTailnetServeRegistry.stopAll()
    for _ in 0..<50 where Darwin.kill(backendPID, 0) == 0 {
        Thread.sleep(forTimeInterval: 0.02)
    }

    #expect(MapofAgentsTailnetServeRegistry.activeRouteCountForTesting() == 0)
    #expect(Darwin.kill(backendPID, 0) != 0)
}

private func ownerPermissions(of url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
    return permissions.intValue & 0o777
}

private func pairingCommandEnvironment(
    dnsName: String,
    serveStatus: Int32 = 0,
    serveError: String = "",
    recorder: PairingCommandRecorder? = nil
) -> MapofAgentsMacPairingService.CommandEnvironment {
    let executableURL = URL(fileURLWithPath: "/usr/bin/tailscale")
    return MapofAgentsMacPairingService.CommandEnvironment(
        codexExecutableURL: { URL(fileURLWithPath: "/usr/bin/codex") },
        tailscaleExecutableURL: { executableURL },
        run: { receivedExecutableURL, arguments in
            recorder?.append(arguments)
            guard receivedExecutableURL == executableURL else {
                return pairingCommandResult(status: 2, stderr: "Unexpected executable")
            }
            if arguments == ["status", "--json"] {
                let json = """
                {"Self":{"DNSName":"\(dnsName)"}}
                """
                return pairingCommandResult(stdout: json)
            }
            if arguments.first == "serve" {
                return pairingCommandResult(status: serveStatus, stderr: serveError)
            }
            return pairingCommandResult(status: 2, stderr: "Unexpected command")
        }
    )
}

private func pairingCommandResult(
    status: Int32 = 0,
    stdout: String = "",
    stderr: String = ""
) -> BoundedProcessResult {
    BoundedProcessResult(
        terminationStatus: status,
        stdout: BoundedProcessOutput(data: Data(stdout.utf8)),
        stderr: BoundedProcessOutput(data: Data(stderr.utf8))
    )
}
#endif

@Test
func pairedHostStoresDurableMetadataWithoutAnySecret() throws {
    let endpointURL = try #require(URL(string: "wss://example-host.example-tailnet.ts.net"))
    let exchangeURL = try #require(URL(string: "https://example-host.example-tailnet.ts.net:8443/v1/pairing"))
    let supportDirectory = "/Users/test/Library/Application Support/mapofagents"
    let pairedHost = MapofAgentsPairedHost(
        id: HostID(rawValue: "paired-mac"),
        name: "Mac mini",
        endpoints: [
            MapofAgentsPairingEndpoint(kind: .tailnet, url: endpointURL, label: "Example Mac"),
        ],
        bearerToken: "short-lived-access-secret",
        credentialExchangeURL: exchangeURL,
        deviceID: "device-1",
        mapofagentsSupportDirectory: supportDirectory
    )

    let encoded = try pairedHost.encodedString()
    let decoded = try MapofAgentsPairedHost.decode(from: encoded)
    let serialized = try #require(base64URLDecodedData(encoded))
    let serializedText = try #require(String(data: serialized, encoding: .utf8))

    #expect(decoded.id == pairedHost.id)
    #expect(decoded.name == "Mac mini")
    #expect(decoded.bearerToken.isEmpty)
    #expect(decoded.deviceID == "device-1")
    #expect(decoded.credentialExchangeURL == exchangeURL)
    #expect(decoded.persistenceVersion == MapofAgentsPairedHost.currentPersistenceVersion)
    #expect(decoded.mapofagentsSupportDirectory == supportDirectory)
    #expect(decoded.preferredEndpoints.first?.url == endpointURL)
    #expect(serializedText.contains("short-lived-access-secret") == false)
    #expect(serializedText.contains("refresh") == false)
    #expect(serializedText.contains("bearerToken") == false)
}

@Test
func refreshCredentialKeychainReferenceIsScopedByStableHostAndDevice() {
    let first = KeychainMapofAgentsPairingCredentialVault.credentialReference(
        hostID: HostID(rawValue: "host-1"),
        deviceID: "device-1"
    )
    let otherDevice = KeychainMapofAgentsPairingCredentialVault.credentialReference(
        hostID: HostID(rawValue: "host-1"),
        deviceID: "device-2"
    )
    let otherHost = KeychainMapofAgentsPairingCredentialVault.credentialReference(
        hostID: HostID(rawValue: "host-2"),
        deviceID: "device-1"
    )

    #expect(first != otherDevice)
    #expect(first != otherHost)
    #expect(first.contains("host-1") == false)
}

@Test
func pairedHostDecodesLegacyRecordWithoutMetadata() throws {
    let endpointURL = try #require(URL(string: "ws://100.64.0.10:18945"))
    let legacyHost = """
    {
      "id": "paired-mac",
      "name": "Mac mini",
      "endpoints": [
        {
          "id": "tailnet",
          "kind": "tailnet",
          "url": "\(endpointURL.absoluteString)",
          "label": "100.64.0.10"
        }
      ],
      "bearerToken": "secret",
      "pairedAt": "2026-05-22T19:15:44Z"
    }
    """

    let decoded = try MapofAgentsPairedHost.decode(from: encodedHost(forJSONObject: legacyHost))
    let reencoded = try decoded.encodedString()
    let migratedText = try #require(
        base64URLDecodedData(reencoded).flatMap { String(data: $0, encoding: .utf8) }
    )

    #expect(decoded.id == HostID(rawValue: "paired-mac"))
    #expect(decoded.persistenceVersion == 1)
    #expect(decoded.mapofagentsSupportDirectory == nil)
    #expect(decoded.lastSuccessfulEndpointID == nil)
    #expect(decoded.lastSuccessfulEndpointURL == nil)
    #expect(decoded.lastConnectedAt == nil)
    #expect(decoded.endpointFailures.isEmpty)
    #expect(decoded.preferredEndpoints.first?.url == endpointURL)
    #expect(migratedText.contains("secret") == false)
    #expect(migratedText.contains("bearerToken") == false)
}

@Test
func endpointPriorityPrefersTailnetThenBonjourThenFallback() throws {
    let lanURL = try #require(URL(string: "ws://mac-host.lan:18945"))
    let manualURL = try #require(URL(string: "ws://192.168.1.25:18945"))
    let bonjourURL = try #require(URL(string: "ws://Mac.local:18945"))
    let tailnetURL = try #require(URL(string: "ws://mac-mini.tailnet.ts.net:18945"))

    let lan = MapofAgentsPairingEndpoint(id: "lan", kind: .local, url: lanURL, label: "mac-host.lan")
    let manual = MapofAgentsPairingEndpoint(id: "manual", kind: .manual, url: manualURL, label: "Manual")
    let bonjour = MapofAgentsPairingEndpoint(id: "bonjour", kind: .local, url: bonjourURL, label: "Mac.local")
    let tailnet = MapofAgentsPairingEndpoint(id: "tailnet", kind: .tailnet, url: tailnetURL, label: "mac-mini.tailnet.ts.net")
    let payload = MapofAgentsPairingPayload(
        hostID: HostID(rawValue: "paired-mac"),
        name: "Mac mini",
        endpoints: [lan, manual, bonjour, tailnet],
        bearerToken: "secret"
    )

    #expect(tailnet.connectionPriority == 0)
    #expect(bonjour.connectionPriority == 1)
    #expect(lan.connectionPriority == 2)
    #expect(manual.connectionPriority == 2)
    #expect(payload.preferredEndpoints.map(\.id) == ["tailnet", "bonjour", "lan", "manual"])
}

@Test
func pairedHostPrefersLastSuccessfulEndpoint() throws {
    let tailnetURL = try #require(URL(string: "ws://mac-mini.tailnet.ts.net:18945"))
    let manualURL = try #require(URL(string: "ws://192.168.1.25:18945"))
    let tailnet = MapofAgentsPairingEndpoint(id: "tailnet", kind: .tailnet, url: tailnetURL, label: "mac-mini.tailnet.ts.net")
    let manual = MapofAgentsPairingEndpoint(id: "manual", kind: .manual, url: manualURL, label: "Manual")
    let failureDate = Date(timeIntervalSince1970: 100)
    let successDate = Date(timeIntervalSince1970: 200)
    var pairedHost = MapofAgentsPairedHost(
        id: HostID(rawValue: "paired-mac"),
        name: "Mac mini",
        endpoints: [tailnet, manual],
        bearerToken: "secret",
        lastSuccessfulEndpointURL: manualURL
    )

    #expect(pairedHost.preferredEndpoints.first?.id == "manual")
    #expect(pairedHost.isLastSuccessfulEndpoint(manual))

    pairedHost.recordConnectionFailure(to: tailnet, message: "Timed out", at: failureDate)
    #expect(pairedHost.failure(for: tailnet)?.message == "Timed out")
    #expect(pairedHost.failure(for: tailnet)?.timestamp == failureDate)

    pairedHost.recordSuccessfulConnection(to: tailnet, at: successDate)
    #expect(pairedHost.preferredEndpoints.first?.id == "tailnet")
    #expect(pairedHost.lastSuccessfulEndpointID == "tailnet")
    #expect(pairedHost.lastSuccessfulEndpointURL == tailnetURL)
    #expect(pairedHost.lastConnectedAt == successDate)
    #expect(pairedHost.failure(for: tailnet) == nil)
}

@Test
func pairedHostPrefersLastGoodTailnetOverStaleLocalEndpoint() throws {
    let localURL = try #require(URL(string: "ws://mac-host.lan:18945"))
    let tailnetURL = try #require(URL(string: "ws://mac-mini.example.ts.net:18945"))
    let local = MapofAgentsPairingEndpoint(id: "local", kind: .local, url: localURL, label: "mac-host.lan")
    let tailnet = MapofAgentsPairingEndpoint(id: "tailnet", kind: .tailnet, url: tailnetURL, label: "mac-mini.example.ts.net")
    var pairedHost = MapofAgentsPairedHost(
        id: HostID(rawValue: "paired-mac"),
        name: "Mac mini",
        endpoints: [local, tailnet],
        bearerToken: "secret"
    )

    pairedHost.recordConnectionFailure(to: local, message: "A server with the specified hostname could not be found.")
    pairedHost.recordSuccessfulConnection(to: tailnet)

    #expect(pairedHost.preferredEndpoints.map(\.id) == ["tailnet", "local"])
    #expect(pairedHost.failure(for: local)?.message.contains("hostname") == true)
}

@Test
func macLanFailureDoesNotBlockTailnetFallbackOrdering() throws {
    let localURL = try #require(URL(string: "ws://mac-host.lan:18945"))
    let tailnetURL = try #require(URL(string: "ws://100.64.0.10:18945"))
    let local = MapofAgentsPairingEndpoint(id: "local", kind: .local, url: localURL, label: "mac-host.lan")
    let tailnet = MapofAgentsPairingEndpoint(id: "tailnet", kind: .tailnet, url: tailnetURL, label: "100.64.0.10")
    var pairedHost = MapofAgentsPairedHost(
        id: HostID(rawValue: "paired-mac"),
        name: "Mac mini",
        endpoints: [local, tailnet],
        bearerToken: "secret"
    )

    pairedHost.recordConnectionFailure(to: local, message: "Could not resolve mac-host.lan.")

    #expect(pairedHost.preferredEndpoints.first?.id == "tailnet")
}

@Test
func iPhoneCompanionRejectsCleartextIPWebSocketEndpoints() throws {
    let tailnetIPURL = try #require(URL(string: "ws://100.64.0.10:18945"))
    let magicDNSURL = try #require(URL(string: "ws://mac-mini.tailnet.ts.net:18945"))
    let secureIPURL = try #require(URL(string: "wss://100.64.0.10:18945"))
    let secureDNSURL = try #require(URL(string: "wss://mac-mini.tailnet.ts.net:18945"))

    let tailnetIP = MapofAgentsPairingEndpoint(id: "tailnet-ip", kind: .tailnet, url: tailnetIPURL, label: "100.64.0.10")
    let magicDNS = MapofAgentsPairingEndpoint(id: "magic-dns", kind: .tailnet, url: magicDNSURL, label: "mac-mini.tailnet.ts.net")
    let secureIP = MapofAgentsPairingEndpoint(id: "secure-ip", kind: .tailnet, url: secureIPURL, label: "100.64.0.10")
    let secureDNS = MapofAgentsPairingEndpoint(id: "secure-dns", kind: .tailnet, url: secureDNSURL, label: "mac-mini.tailnet.ts.net")

    #expect(tailnetIP.isIPhoneCompanionConnectable == false)
    #expect(magicDNS.isIPhoneCompanionConnectable == false)
    #expect(secureIP.isIPhoneCompanionConnectable)
    #expect(secureDNS.isIPhoneCompanionConnectable)
}

@Test
func workflowSnapshotSyncUsesExplicitSupportDirectoryFromPairingMetadata() async throws {
    let supportDirectory = "/Users/test/Library/Application Support/mapofagents"
    let endpointURL = try #require(URL(string: "ws://mac-mini.tailnet.ts.net:18945"))
    let pairedHost = MapofAgentsPairedHost(
        id: HostID(rawValue: "paired-mac"),
        name: "Mac mini",
        endpoints: [
            MapofAgentsPairingEndpoint(kind: .tailnet, url: endpointURL, label: "mac-mini.tailnet.ts.net"),
        ],
        bearerToken: "secret",
        mapofagentsSupportDirectory: supportDirectory
    )
    let date = Date(timeIntervalSince1970: 100)
    let library = WorkflowLibrarySnapshot(
        activeWorkflowID: "main",
        workflows: [
            WorkflowRecord(id: "main", name: "Main", createdAt: date, updatedAt: date),
        ]
    )
    let graph = AgentGraph(
        workspaceID: WorkspaceID(rawValue: "workspace"),
        title: "Synced",
        updatedAt: date
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let files = [
        "\(supportDirectory)/workflows/library.json": try encoder.encode(library),
        "\(supportDirectory)/workflows/main.json": try encoder.encode(graph),
    ]

    let snapshot = try await WorkflowSnapshotSyncService.loadSnapshot(pairedHost: pairedHost) { path in
        guard let data = files[path] else {
            throw TestReadError.missing(path)
        }
        return data
    }

    #expect(WorkflowSnapshotSyncService.remoteMacSupportDirectory(
        mapofagentsSupportDirectory: supportDirectory,
        codexHome: nil
    ) == supportDirectory)
    #expect(snapshot.library.activeWorkflowID == "main")
    #expect(snapshot.graphsByWorkflowID["main"]?.title == "Synced")
}

@Test
func workflowSnapshotSyncFallsBackToCodexHomeForLegacyPairingMetadata() async throws {
    let codexHome = "/Users/test/.codex"
    let supportDirectory = "/Users/test/Library/Application Support/mapofagents"
    let endpointURL = try #require(URL(string: "ws://mac-mini.tailnet.ts.net:18945"))
    let pairedHost = MapofAgentsPairedHost(
        id: HostID(rawValue: "paired-mac"),
        name: "Mac mini",
        endpoints: [
            MapofAgentsPairingEndpoint(kind: .tailnet, url: endpointURL, label: "mac-mini.tailnet.ts.net"),
        ],
        bearerToken: "secret",
        mapofagentsSupportDirectory: nil
    )
    let date = Date(timeIntervalSince1970: 100)
    let library = WorkflowLibrarySnapshot(
        activeWorkflowID: "main",
        workflows: [
            WorkflowRecord(id: "main", name: "Main", createdAt: date, updatedAt: date),
        ]
    )
    let graph = AgentGraph(
        workspaceID: WorkspaceID(rawValue: "workspace"),
        title: "Legacy Synced",
        updatedAt: date
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let files = [
        "\(supportDirectory)/workflows/library.json": try encoder.encode(library),
        "\(supportDirectory)/workflows/main.json": try encoder.encode(graph),
    ]

    let snapshot = try await WorkflowSnapshotSyncService.loadSnapshot(
        pairedHost: pairedHost,
        codexHome: codexHome
    ) { path in
        guard let data = files[path] else {
            throw TestReadError.missing(path)
        }
        return data
    }

    #expect(snapshot.library.activeWorkflowID == "main")
    #expect(snapshot.graphsByWorkflowID["main"]?.title == "Legacy Synced")
}

@Test
func workflowSnapshotSyncCanExcludeRelayEndpoints() async throws {
    let supportDirectory = "/Users/test/Library/Application Support/mapofagents"
    let endpointURL = try #require(URL(string: "wss://relay.example.test/v1"))
    let date = Date(timeIntervalSince1970: 100)
    let library = WorkflowLibrarySnapshot(
        activeWorkflowID: "main",
        workflows: [
            WorkflowRecord(id: "main", name: "Main", createdAt: date, updatedAt: date),
        ]
    )
    let graph = AgentGraph(
        workspaceID: WorkspaceID(rawValue: "workspace"),
        title: "Synced",
        updatedAt: date
    )
    let relayEndpoints = [
        AppServerRelayEndpoint(
            id: HostID(rawValue: "relay-1"),
            name: "Relay 1",
            url: endpointURL
        ),
    ]
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let files = [
        "\(supportDirectory)/workflows/library.json": try encoder.encode(library),
        "\(supportDirectory)/workflows/main.json": try encoder.encode(graph),
        "\(supportDirectory)/relay-endpoints.json": try encoder.encode(relayEndpoints),
    ]

    let snapshot = try await WorkflowSnapshotSyncService.loadSnapshot(
        supportDirectory: supportDirectory,
        includeRelayEndpoints: false
    ) { path in
        guard let data = files[path] else {
            throw TestReadError.missing(path)
        }
        return data
    }

    #expect(snapshot.relayEndpoints.isEmpty)
}

@Test
func workflowSnapshotSyncRejectsMissingNonActiveWorkflowGraph() async throws {
    let supportDirectory = "/Users/test/Library/Application Support/mapofagents"
    let date = Date(timeIntervalSince1970: 100)
    let library = WorkflowLibrarySnapshot(
        activeWorkflowID: "main",
        workflows: [
            WorkflowRecord(id: "main", name: "Main", createdAt: date, updatedAt: date),
            WorkflowRecord(id: "other", name: "Other", createdAt: date, updatedAt: date),
        ]
    )
    let graph = AgentGraph(
        workspaceID: WorkspaceID(rawValue: "workspace"),
        title: "Synced",
        updatedAt: date
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let files = [
        "\(supportDirectory)/workflows/library.json": try encoder.encode(library),
        "\(supportDirectory)/workflows/main.json": try encoder.encode(graph),
    ]

    var integrityError: WorkflowSnapshotIntegrityError?
    do {
        _ = try await WorkflowSnapshotSyncService.loadSnapshot(supportDirectory: supportDirectory) { path in
            guard let data = files[path] else {
                throw TestReadError.missing(path)
            }
            return data
        }
    } catch let error as WorkflowSnapshotIntegrityError {
        integrityError = error
    }

    #expect(integrityError == .missingWorkflowGraph("other"))
}

@Test
func workflowSnapshotSyncRejectsCorruptOptionalRemoteState() async throws {
    let supportDirectory = "/Users/test/Library/Application Support/mapofagents"
    let date = Date(timeIntervalSince1970: 100)
    let library = WorkflowLibrarySnapshot(
        activeWorkflowID: "main",
        workflows: [
            WorkflowRecord(id: "main", name: "Main", createdAt: date, updatedAt: date),
        ]
    )
    let graph = AgentGraph(
        workspaceID: WorkspaceID(rawValue: "workspace"),
        title: "Synced",
        updatedAt: date
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let corruptPath = "\(supportDirectory)/workflow-events.json"
    let files = [
        "\(supportDirectory)/workflows/library.json": try encoder.encode(library),
        "\(supportDirectory)/workflows/main.json": try encoder.encode(graph),
        corruptPath: Data("{not-json".utf8),
    ]

    var rejectedPath: String?
    do {
        _ = try await WorkflowSnapshotSyncService.loadSnapshot(supportDirectory: supportDirectory) { path in
            guard let data = files[path] else {
                throw TestReadError.missing(path)
            }
            return data
        }
    } catch WorkflowSnapshotSyncError.corruptRemoteState(let path) {
        rejectedPath = path
    }

    #expect(rejectedPath == corruptPath)
}

@Test
func workflowSnapshotSyncReadsOnlyTheAtomicallySelectedVersion() async throws {
    let supportDirectory = "/Users/test/Library/Application Support/mapofagents"
    let snapshotID = "snapshot-v1"
    let stateDirectory = "\(supportDirectory)/workflow-snapshots/\(snapshotID)"
    let date = Date(timeIntervalSince1970: 100)
    let library = WorkflowLibrarySnapshot(
        activeWorkflowID: "main",
        workflows: [WorkflowRecord(id: "main", name: "Main", createdAt: date, updatedAt: date)]
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let files = [
        "\(supportDirectory)/workflow-snapshots/current.json": try encoder.encode(
            WorkflowSnapshotPointer(activeSnapshotID: snapshotID)
        ),
        "\(stateDirectory)/metadata.json": try encoder.encode(
            WorkflowSnapshotMetadata(snapshotID: snapshotID, createdAt: date)
        ),
        "\(stateDirectory)/workflows/library.json": try encoder.encode(library),
        "\(stateDirectory)/workflows/main.json": try encoder.encode(AgentGraph(title: "Versioned")),
    ]

    let snapshot = try await WorkflowSnapshotSyncService.loadSnapshot(
        supportDirectory: supportDirectory
    ) { path in
        guard let data = files[path] else { throw TestReadError.missing(path) }
        return data
    }

    #expect(snapshot.graphsByWorkflowID["main"]?.title == "Versioned")
}

@Test
func workflowSnapshotSyncDistinguishesMissingRequiredAndOptionalFiles() async throws {
    let supportDirectory = "/Users/test/Library/Application Support/mapofagents"
    let libraryPath = "\(supportDirectory)/workflows/library.json"

    var missingPath: String?
    do {
        _ = try await WorkflowSnapshotSyncService.loadSnapshot(
            supportDirectory: supportDirectory
        ) { path in
            throw TestReadError.missing(path)
        }
    } catch WorkflowSnapshotSyncError.missingRequiredFile(let path) {
        missingPath = path
    }

    #expect(missingPath == libraryPath)

    let date = Date(timeIntervalSince1970: 100)
    let library = WorkflowLibrarySnapshot(
        activeWorkflowID: "main",
        workflows: [WorkflowRecord(id: "main", name: "Main", createdAt: date, updatedAt: date)]
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let requiredFiles = [
        libraryPath: try encoder.encode(library),
        "\(supportDirectory)/workflows/main.json": try encoder.encode(AgentGraph(title: "No Optional Files")),
    ]
    let snapshot = try await WorkflowSnapshotSyncService.loadSnapshot(
        supportDirectory: supportDirectory
    ) { path in
        guard let data = requiredFiles[path] else { throw TestReadError.missing(path) }
        return data
    }
    #expect(snapshot.workflowEvents.isEmpty)
    #expect(snapshot.relayEndpoints.isEmpty)
}

@Test
func workflowSnapshotSyncDoesNotTreatAuthorizationOrTimeoutAsMissing() async throws {
    let supportDirectory = "/Users/test/Library/Application Support/mapofagents"
    let libraryPath = "\(supportDirectory)/workflows/library.json"

    var authorizationPath: String?
    do {
        _ = try await WorkflowSnapshotSyncService.loadSnapshot(
            supportDirectory: supportDirectory
        ) { path in
            if path == libraryPath { throw TestReadError.authorizationDenied(path) }
            throw TestReadError.missing(path)
        }
    } catch WorkflowSnapshotSyncError.authorizationDenied(let path) {
        authorizationPath = path
    }
    #expect(authorizationPath == libraryPath)

    var timeoutPath: String?
    do {
        _ = try await WorkflowSnapshotSyncService.loadSnapshot(
            supportDirectory: supportDirectory
        ) { path in
            if path == libraryPath { throw TestReadError.timedOut(path) }
            throw TestReadError.missing(path)
        }
    } catch WorkflowSnapshotSyncError.timedOut(let path) {
        timeoutPath = path
    }
    #expect(timeoutPath == libraryPath)
}

@Test
func workflowSnapshotSyncRejectsCorruptRequiredGraph() async throws {
    let supportDirectory = "/Users/test/Library/Application Support/mapofagents"
    let date = Date(timeIntervalSince1970: 100)
    let library = WorkflowLibrarySnapshot(
        activeWorkflowID: "main",
        workflows: [WorkflowRecord(id: "main", name: "Main", createdAt: date, updatedAt: date)]
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let corruptPath = "\(supportDirectory)/workflows/main.json"
    let files = [
        "\(supportDirectory)/workflows/library.json": try encoder.encode(library),
        corruptPath: Data("{not-json".utf8),
    ]

    var rejectedPath: String?
    do {
        _ = try await WorkflowSnapshotSyncService.loadSnapshot(
            supportDirectory: supportDirectory
        ) { path in
            guard let data = files[path] else { throw TestReadError.missing(path) }
            return data
        }
    } catch WorkflowSnapshotSyncError.corruptRemoteState(let path) {
        rejectedPath = path
    }

    #expect(rejectedPath == corruptPath)
}

private func pairingURL(forJSONObject json: String) throws -> URL {
    let base64 = base64URL(json)
    var components = URLComponents()
    components.scheme = MapofAgentsPairingPayload.urlScheme
    components.host = MapofAgentsPairingPayload.urlHost
    components.queryItems = [
        URLQueryItem(name: "payload", value: base64),
    ]
    return try #require(components.url)
}

private func encodedHost(forJSONObject json: String) -> String {
    base64URL(json)
}

private func base64URL(_ value: String) -> String {
    Data(value.utf8)
        .base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

@Test
func pairingPayloadRejectsMissingEndpoints() throws {
    let payload = MapofAgentsPairingPayload(
        hostID: HostID(rawValue: "paired-mac"),
        name: "Mac mini",
        endpoints: [],
        bearerToken: "secret"
    )

    #expect(throws: MapofAgentsPairingError.self) {
        _ = try payload.pairingURL()
    }
}

private enum TestReadError: Error, WorkflowSnapshotReadErrorCategorizing {
    case missing(String)
    case authorizationDenied(String)
    case timedOut(String)

    var workflowSnapshotReadFailureKind: WorkflowSnapshotReadFailureKind {
        switch self {
        case .missing:
            return .notFound
        case .authorizationDenied:
            return .authorizationDenied
        case .timedOut:
            return .timedOut
        }
    }
}
