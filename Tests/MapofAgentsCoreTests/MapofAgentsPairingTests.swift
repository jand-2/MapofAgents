import Foundation
import Testing
@testable import MapofAgentsCore

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
    let tailnetURL = try #require(URL(string: "ws://mac-mini.tailnet.ts.net:18945"))
    let localURL = try #require(URL(string: "ws://mac-host.lan:18945"))
    let supportDirectory = "/Users/test/Library/Application Support/mapofagents"
    let payload = MapofAgentsPairingPayload(
        hostID: HostID(rawValue: "paired-mac"),
        name: "Mac mini",
        endpoints: [
            MapofAgentsPairingEndpoint(kind: .local, url: localURL, label: "mac-host.lan"),
            MapofAgentsPairingEndpoint(kind: .tailnet, url: tailnetURL, label: "mac-mini.tailnet.ts.net"),
        ],
        bearerToken: "secret",
        createdAt: Date(timeIntervalSince1970: 10),
        expiresAt: Date(timeIntervalSince1970: 1_000),
        mapofagentsSupportDirectory: supportDirectory
    )

    let url = try payload.pairingURL()
    let decoded = try MapofAgentsPairingPayload.decode(from: url)

    #expect(url.scheme == "mapofagents")
    #expect(url.host == "pair")
    #expect(decoded.hostID == payload.hostID)
    #expect(decoded.bearerToken == "secret")
    #expect(decoded.mapofagentsSupportDirectory == supportDirectory)
    #expect(decoded.preferredEndpoints.first?.kind == .tailnet)
    #expect(decoded.preferredEndpoints.first?.url == tailnetURL)
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
func pairingExpiryRemovesOnlyTheIssuedToken() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-pairing-expiry-tests-\(UUID().uuidString)", isDirectory: true)
    let tokenURL = directory.appendingPathComponent("mac-lan-app-server.token")
    let secretURL = directory.appendingPathComponent("mac-lan-app-server.shared-secret")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    try "newer-token".write(to: tokenURL, atomically: true, encoding: .utf8)
    try "newer-secret".write(to: secretURL, atomically: true, encoding: .utf8)
    MapofAgentsMacPairingService.expirePairingSessionIfCurrentToken(
        token: "older-token",
        supportDirectory: directory,
        port: 65_530
    )
    #expect(try String(contentsOf: tokenURL, encoding: .utf8) == "newer-token")
    #expect(try String(contentsOf: secretURL, encoding: .utf8) == "newer-secret")

    MapofAgentsMacPairingService.expirePairingSessionIfCurrentToken(
        token: "newer-token",
        supportDirectory: directory,
        port: 65_530
    )
    #expect(FileManager.default.fileExists(atPath: tokenURL.path) == false)
    #expect(FileManager.default.fileExists(atPath: secretURL.path) == false)
}
#endif

@Test
func pairedHostStoresWithoutPairingExpiration() throws {
    let endpointURL = try #require(URL(string: "ws://100.64.0.10:18945"))
    let supportDirectory = "/Users/test/Library/Application Support/mapofagents"
    let payload = MapofAgentsPairingPayload(
        hostID: HostID(rawValue: "paired-mac"),
        name: "Mac mini",
        endpoints: [
            MapofAgentsPairingEndpoint(kind: .tailnet, url: endpointURL, label: "100.64.0.10"),
        ],
        bearerToken: "secret",
        expiresAt: Date(timeIntervalSince1970: 1),
        mapofagentsSupportDirectory: supportDirectory
    )

    let pairedHost = MapofAgentsPairedHost(payload: payload)
    let encoded = try pairedHost.encodedString()
    let decoded = try MapofAgentsPairedHost.decode(from: encoded)

    #expect(decoded.id == payload.hostID)
    #expect(decoded.name == "Mac mini")
    #expect(decoded.bearerToken == "secret")
    #expect(decoded.persistenceVersion == MapofAgentsPairedHost.currentPersistenceVersion)
    #expect(decoded.mapofagentsSupportDirectory == supportDirectory)
    #expect(decoded.preferredEndpoints.first?.url == endpointURL)
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

    #expect(decoded.id == HostID(rawValue: "paired-mac"))
    #expect(decoded.persistenceVersion == 1)
    #expect(decoded.mapofagentsSupportDirectory == nil)
    #expect(decoded.lastSuccessfulEndpointID == nil)
    #expect(decoded.lastSuccessfulEndpointURL == nil)
    #expect(decoded.lastConnectedAt == nil)
    #expect(decoded.endpointFailures.isEmpty)
    #expect(decoded.preferredEndpoints.first?.url == endpointURL)
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

    let url = try payload.pairingURL()

    #expect(throws: MapofAgentsPairingError.self) {
        _ = try MapofAgentsPairingPayload.decode(from: url)
    }
}

private enum TestReadError: Error {
    case missing(String)
}
