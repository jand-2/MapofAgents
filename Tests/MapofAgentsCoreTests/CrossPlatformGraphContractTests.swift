import Foundation
import Testing
@testable import MapofAgentsCore

@Test
func sharedGraphFixtureRoundTripsCanonicalProviderAndPermissions() throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let encoder = JSONEncoder()
    MapofAgentsJSONCoding.configureContractDates(on: encoder)
    encoder.outputFormatting = [.sortedKeys]

    let fixtureURL = repositoryFile(
        "shared",
        "protocol",
        "fixtures",
        "sample-cross-platform-graph.json"
    )
    let fixtureData = try Data(contentsOf: fixtureURL)
    let graph = try decoder.decode(AgentGraph.self, from: fixtureData)
    let thread = try #require(graph.nodes[NodeID(rawValue: "thread-example")])
    let threadRef = try #require(thread.metadata.threadRef)
    let permissions = try #require(thread.metadata.threadPermissions)
    let machine = try #require(graph.nodes[NodeID(rawValue: "machine-example")])
    let codexThreadRef = try #require(
        graph.nodes[NodeID(rawValue: "thread-codex-example")]?.metadata.threadRef
    )
    let manualEdge = try #require(graph.manualEdges[EdgeID(rawValue: "edge-example")])
    let stringRequest = try #require(
        graph.pendingAttentionRequests.first { $0.id == "attention-1" }
    )
    let numericRequest = try #require(
        graph.pendingAttentionRequests.first { $0.id == "attention-2" }
    )
    let route = try #require(graph.messageRoutes["route-1"])
    let diagnostic = try #require(graph.runtimeDiagnostics.first)
    let firstMessage = try #require(thread.metadata.localTranscript.first)
    let attachmentMessage = try #require(thread.metadata.localTranscript.last)
    let turn = try #require(thread.metadata.localTranscriptTurns.first)

    #expect(graph.workspaceID == WorkspaceID(rawValue: "workflow-example"))
    #expect(graph.title == "Cross-platform example")
    #expect(graph.layoutCoordinateSpace == "center")
    #expect(Set(graph.nodes.keys.map(\.rawValue)) == Set([
        "machine-example",
        "thread-example",
        "thread-codex-example",
    ]))
    #expect(machine.id == NodeID(rawValue: "machine-example"))
    #expect(machine.kind == .machine)
    #expect(machine.title == "Example host")
    #expect(machine.subtitle == "Unavailable")
    #expect(machine.position == CanvasPoint(x: 80.25, y: 64.5))
    #expect(machine.size == .machine)
    #expect(machine.zIndex == 0)
    #expect(machine.metadata.hostID == HostID(rawValue: "example-host"))
    #expect(machine.metadata.platform == .windows)
    #expect(machine.metadata.hostStatus == .unavailable)
    #expect(machine.metadata.hostLastError == "Example transient connection error")
    #expect(machine.metadata.codexHome == #"C:\Users\example\.codex"#)
    #expect(machine.metadata.appServerEndpointURL == "wss://example-host.local/app-server")
    #expect(machine.metadata.folderPath == nil)
    #expect(machine.metadata.threadRef == nil)
    #expect(machine.metadata.localTranscript.isEmpty)
    #expect(machine.metadata.localTranscriptTurns.isEmpty)

    #expect(thread.id == NodeID(rawValue: "thread-example"))
    #expect(thread.kind == .codexThread)
    #expect(thread.title == "Example thread")
    #expect(thread.subtitle == "Ready")
    #expect(thread.position.x == 240.5)
    #expect(thread.position.y == 180)
    #expect(thread.size == .thread)
    #expect(thread.zIndex == 1)
    #expect(thread.metadata.hostID == HostID(rawValue: "example-host"))
    #expect(thread.metadata.platform == .windows)
    #expect(thread.metadata.hostStatus == .connected)
    #expect(threadRef.provider == .gemini)
    #expect(threadRef.hostID == HostID(rawValue: "example-host"))
    #expect(threadRef.threadID == "thread-17")
    #expect(threadRef.cwd == #"C:\Users\example\project"#)
    #expect(threadRef.name == "Example thread")
    #expect(codexThreadRef.provider == .codex)
    #expect(codexThreadRef.hostID == threadRef.hostID)
    #expect(codexThreadRef.threadID == threadRef.threadID)
    #expect(threadRef.qualifiedID != codexThreadRef.qualifiedID)
    #expect(thread.metadata.model == "example-model")
    #expect(thread.metadata.reasoningEffort == "medium")
    #expect(permissions.approvalPolicy == .onRequest)
    #expect(permissions.sandboxMode == .workspaceWrite)
    #expect(thread.metadata.threadKind == .thread)
    #expect(thread.metadata.initialPrompt == "Hello")
    #expect(thread.metadata.localTranscript.map(\.role) == [.user, .file])
    #expect(thread.metadata.localTranscriptTurns.map(\.id) == ["turn-1"])
    #expect(thread.metadata.runStatus == .idle)
    #expect(thread.metadata.isUnread == false)
    #expect(thread.metadata.isArchived == false)
    #expect(thread.metadata.hasManualPosition == true)
    #expect(firstMessage.id == "message-1")
    #expect(firstMessage.text == "Hello")
    #expect(firstMessage.createdAt == Date(timeIntervalSince1970: 1_780_358_400.125))
    #expect(attachmentMessage.id == "attachment-1")
    #expect(attachmentMessage.role == .file)
    #expect(attachmentMessage.text == "File artifact: example.txt")
    #expect(attachmentMessage.createdAt == Date(timeIntervalSince1970: 1_780_358_430))
    #expect(turn.status == .complete)
    #expect(turn.startedAt == Date(timeIntervalSince1970: 1_780_358_400))
    #expect(turn.completedAt == Date(timeIntervalSince1970: 1_780_358_430))
    #expect(turn.error == nil)
    #expect(turn.itemsView == .full)
    #expect(turn.durationMilliseconds == 30_000)
    #expect(turn.itemMessageIds == ["message-1", "attachment-1"])

    #expect(manualEdge.source == NodeID(rawValue: "thread-example"))
    #expect(manualEdge.target == NodeID(rawValue: "thread-codex-example"))
    #expect(manualEdge.kind == .manualNote)
    #expect(manualEdge.isManual)
    #expect(manualEdge.label == "Compare providers")
    #expect(route.id == "route-1")
    #expect(route.sourceHostID == HostID(rawValue: "example-host"))
    #expect(route.sourceThreadID == "thread-17")
    #expect(route.sourceTurnID == nil)
    #expect(route.sourceItemID == nil)
    #expect(route.targetHostID == HostID(rawValue: "example-host"))
    #expect(route.targetThreadID == "thread-18")
    #expect(route.targetTurnID == nil)
    #expect(route.timestamp == Date(timeIntervalSince1970: 1_780_358_460))
    #expect(route.snippet == "Example handoff")
    #expect(route.deliveryState == .delivered)
    #expect(route.eventIDs == ["event-1"])
    #expect(route.canvasEdgeID == nil)

    #expect(graph.pendingAttentionRequests.map(\.id) == ["attention-1", "attention-2"])
    #expect(stringRequest.hostID == HostID(rawValue: "example-host"))
    #expect(stringRequest.requestID == .string("approval-1"))
    #expect(stringRequest.method == "item/commandExecution/requestApproval")
    #expect(stringRequest.threadID == "thread-17")
    #expect(stringRequest.turnID == "turn-1")
    #expect(stringRequest.summary == "Approve example command")
    #expect(stringRequest.promptText == "Approve example command")
    #expect(stringRequest.typedResponseOptions == ["accept", "decline"])
    #expect(stringRequest.createdAt == Date(timeIntervalSince1970: 1_780_358_415))
    #expect(numericRequest.hostID == HostID(rawValue: "example-host"))
    #expect(numericRequest.requestID == .int(17))
    #expect(numericRequest.method == "item/tool/requestUserInput")
    #expect(numericRequest.threadID == "thread-17")
    #expect(numericRequest.turnID == "turn-1")
    #expect(numericRequest.summary == "Choose a safe mode")
    #expect(numericRequest.promptText == "Choose a safe mode")
    #expect(numericRequest.typedResponseOptions == ["workspace-write", "read-only"])
    #expect(numericRequest.createdAt == Date(timeIntervalSince1970: 1_780_358_416.5))
    #expect(numericRequest.connectionID == nil)
    #expect(numericRequest.requestParams == nil)
    #expect(graph.runtimeDiagnostics.map(\.id) == ["runtime"])
    #expect(diagnostic.title == "Runtime")
    #expect(diagnostic.status == .passed)
    #expect(diagnostic.detail == "Ready")
    #expect(diagnostic.evidence == "Fixture")
    #expect(diagnostic.action == nil)
    #expect(graph.suppressedAutoMaterializedThreadIDs.isEmpty)
    #expect(graph.viewport == .standard)
    #expect(graph.updatedAt == Date(timeIntervalSince1970: 1_780_358_520.125))
    #expect(
        try canonicalJSONSemanticFingerprint(fixtureData) ==
            "18212dbe409170c6"
    )

    let encodedData = try encoder.encode(graph)
    let encodedObject = try #require(
        JSONSerialization.jsonObject(with: encodedData) as? [String: Any]
    )
    let nodes = try #require(encodedObject["nodes"] as? [String: Any])
    let encodedThread = try #require(nodes["thread-example"] as? [String: Any])
    let metadata = try #require(encodedThread["metadata"] as? [String: Any])
    let encodedPermissions = try #require(metadata["threadPermissions"] as? [String: Any])
    let encodedThreadRef = try #require(metadata["threadRef"] as? [String: Any])
    let encodedAttention = try #require(encodedObject["pendingAttentionRequests"] as? [[String: Any]])

    #expect(encodedPermissions["approvalPolicy"] as? String == "on-request")
    #expect(encodedPermissions["sandboxMode"] as? String == "workspace-write")
    #expect(metadata["approvalPolicy"] == nil)
    #expect(metadata["sandboxMode"] == nil)
    #expect(encodedThreadRef["provider"] as? String == "gemini")
    #expect(encodedAttention.allSatisfy { $0["connectionID"] == nil })
    #expect(encodedAttention.allSatisfy { $0["requestParams"] == nil })
    #expect(encodedAttention.map { $0["requestID"] as? Int } == [nil, 17])

    let roundTripped = try decoder.decode(AgentGraph.self, from: encodedData)
    let roundTrippedMetadata = try #require(
        roundTripped.nodes[NodeID(rawValue: "thread-example")]?.metadata
    )
    #expect(roundTrippedMetadata.threadRef?.provider == .gemini)
    #expect(roundTrippedMetadata.threadPermissions == permissions)
    #expect(roundTrippedMetadata.initialPrompt == thread.metadata.initialPrompt)
    #expect(roundTrippedMetadata.localTranscript == thread.metadata.localTranscript)
    #expect(roundTrippedMetadata.localTranscriptTurns == thread.metadata.localTranscriptTurns)
    #expect(roundTripped.pendingAttentionRequests.map(\.requestID) == [
        .string("approval-1"),
        .int(17),
    ])
    #expect(roundTripped.pendingAttentionRequests.map(\.promptText) == [
        "Approve example command",
        "Choose a safe mode",
    ])
    #expect(roundTripped.runtimeDiagnostics == graph.runtimeDiagnostics)
}

@Test
func appleCanonicalGraphGoldenIsProducedBySwiftSerialization() throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let encoder = JSONEncoder()
    MapofAgentsJSONCoding.configureContractDates(on: encoder)
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

    let fixtureData = try Data(contentsOf: repositoryFile(
        "shared",
        "protocol",
        "fixtures",
        "sample-cross-platform-graph.json"
    ))
    let graph = try decoder.decode(AgentGraph.self, from: fixtureData)
    let encoded = try encoder.encode(graph)
    let goldenURL = repositoryFile(
        "shared",
        "protocol",
        "fixtures",
        "sample-cross-platform-graph.apple-golden.json"
    )

    if ProcessInfo.processInfo.environment["MAPOFAGENTS_UPDATE_CONTRACT_GOLDENS"] == "1" {
        try encoded.write(to: goldenURL, options: .atomic)
    }

    #expect(try Data(contentsOf: goldenURL) == encoded)
}

@Test
func sharedGraphSchemaDeclaresCanonicalProviderAndPermissionsShape() throws {
    let schemaURL = repositoryFile("shared", "protocol", "graph.schema.json")
    let schema = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: schemaURL)) as? [String: Any]
    )
    let definitions = try #require(schema["$defs"] as? [String: Any])
    let threadRef = try #require(definitions["threadRef"] as? [String: Any])
    let threadRefProperties = try #require(threadRef["properties"] as? [String: Any])
    let provider = try #require(threadRefProperties["provider"] as? [String: Any])
    let providerValues = try #require(provider["enum"] as? [String])
    let metadata = try #require(definitions["nodeMetadata"] as? [String: Any])
    let metadataProperties = try #require(metadata["properties"] as? [String: Any])
    let permissions = try #require(metadataProperties["threadPermissions"] as? [String: Any])
    let attention = try #require(definitions["runtimeAttentionRequest"] as? [String: Any])
    let attentionProperties = try #require(attention["properties"] as? [String: Any])

    #expect(schema["$id"] as? String == "https://mapofagents.dev/schema/graph.schema.json")
    #expect(Set(providerValues) == Set(["codex", "gemini", "grok"]))
    #expect(permissions["$ref"] as? String == "#/$defs/threadPermissions")
    #expect(attentionProperties["prompt"] != nil)
    #expect(attentionProperties["responseChoices"] != nil)
    #expect(attentionProperties["connectionID"] == nil)
    #expect(attentionProperties["requestParams"] == nil)
}

@Test
func canonicalThreadPermissionsWinRegardlessOfJSONPropertyOrder() throws {
    let canonical =
        #""threadPermissions":{"approvalPolicy":"never","sandboxMode":"read-only"}"#
    let legacy =
        #""approvalPolicy":"on-failure","sandboxMode":"danger-full-access""#

    for json in [
        "{\(legacy),\(canonical)}",
        "{\(canonical),\(legacy)}",
    ] {
        let metadata = try JSONDecoder().decode(NodeMetadata.self, from: Data(json.utf8))
        #expect(metadata.threadPermissions?.approvalPolicy == .never)
        #expect(metadata.threadPermissions?.sandboxMode == .readOnly)
    }
}

@Test
func attentionEncodingKeepsPresentationButDropsConnectionBoundPayload() throws {
    let request = RuntimeAttentionRequest(
        id: "attention",
        hostID: HostID(rawValue: "example-host"),
        requestID: .int(42),
        connectionID: AppServerConnectionID(),
        method: "item/tool/requestUserInput",
        threadID: "thread",
        summary: "Choose",
        requestParams: .object([
            "questions": .array([
                .object([
                    "id": .string("mode"),
                    "question": .string("Choose a mode"),
                    "options": .array([
                        .object([
                            "label": .string("Safe"),
                            "value": .string("safe"),
                        ]),
                    ]),
                ]),
            ]),
            "command": .string("private command payload"),
        ]),
        createdAt: Date(timeIntervalSince1970: 1_780_358_400)
    )
    let encoder = JSONEncoder()
    MapofAgentsJSONCoding.configureContractDates(on: encoder)
    let encodedData = try encoder.encode(request)
    let encoded = try #require(
        JSONSerialization.jsonObject(with: encodedData) as? [String: Any]
    )

    #expect(encoded["requestID"] as? Int == 42)
    #expect(encoded["prompt"] as? String == "Choose a mode")
    #expect(encoded["connectionID"] == nil)
    #expect(encoded["requestParams"] == nil)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(RuntimeAttentionRequest.self, from: encodedData)
    #expect(decoded.requestID == .int(42))
    #expect(decoded.connectionID == nil)
    #expect(decoded.requestParams == nil)
    #expect(decoded.promptText == "Choose a mode")
    #expect(decoded.typedResponseOptions == ["safe"])
}

@Test
func legacyFlattenedThreadPermissionsDecodeAndRewriteCanonically() throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let encoder = JSONEncoder()
    MapofAgentsJSONCoding.configureContractDates(on: encoder)

    let legacyData = Data(
        """
        {
          "workspaceID": "legacy-permissions",
          "title": "Legacy permissions",
          "nodes": {
            "thread": {
              "id": "thread",
              "kind": "codexThread",
              "title": "Thread",
              "subtitle": "",
              "position": { "x": 0, "y": 0 },
              "size": { "width": 200, "height": 132 },
              "metadata": {
                "threadRef": {
                  "hostID": "example-host",
                  "threadID": "legacy-thread",
                  "cwd": "/workspace/project"
                },
                "approvalPolicy": "on-failure",
                "sandboxMode": "read-only"
              },
              "zIndex": 0
            }
          },
          "manualEdges": {},
          "viewport": { "scale": 1, "offset": { "x": 0, "y": 0 } },
          "updatedAt": "2026-06-02T00:00:00Z"
        }
        """.utf8
    )

    let graph = try decoder.decode(AgentGraph.self, from: legacyData)
    let metadata = try #require(graph.nodes[NodeID(rawValue: "thread")]?.metadata)
    #expect(metadata.threadRef?.provider == .codex)
    #expect(metadata.threadPermissions?.approvalPolicy == .onFailure)
    #expect(metadata.threadPermissions?.sandboxMode == .readOnly)

    let encoded = try #require(
        JSONSerialization.jsonObject(with: encoder.encode(graph)) as? [String: Any]
    )
    let nodes = try #require(encoded["nodes"] as? [String: Any])
    let thread = try #require(nodes["thread"] as? [String: Any])
    let rewrittenMetadata = try #require(thread["metadata"] as? [String: Any])
    #expect(rewrittenMetadata["threadPermissions"] != nil)
    #expect(rewrittenMetadata["approvalPolicy"] == nil)
    #expect(rewrittenMetadata["sandboxMode"] == nil)
}

@Test
func partialLegacyThreadPermissionsUseHistoricalFallbacks() throws {
    let cases: [(String, AgentApprovalPolicy, AgentSandboxMode)] = [
        (
            "\"approvalPolicy\": \"on-failure\"",
            .onFailure,
            .dangerFullAccess
        ),
        (
            "\"sandboxMode\": \"read-only\"",
            .onRequest,
            .readOnly
        ),
    ]

    for (legacyField, expectedApprovalPolicy, expectedSandboxMode) in cases {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = Data(
            """
            {
              "workspaceID": "partial-legacy-permissions",
              "title": "Partial legacy permissions",
              "nodes": {
                "thread": {
                  "id": "thread",
                  "kind": "codexThread",
                  "title": "Thread",
                  "subtitle": "",
                  "position": { "x": 0, "y": 0 },
                  "size": { "width": 200, "height": 132 },
                  "metadata": { \(legacyField) },
                  "zIndex": 0
                }
              },
              "manualEdges": {},
              "viewport": { "scale": 1, "offset": { "x": 0, "y": 0 } },
              "updatedAt": "2026-06-02T00:00:00Z"
            }
            """.utf8
        )

        let graph = try decoder.decode(AgentGraph.self, from: data)
        let permissions = try #require(
            graph.nodes[NodeID(rawValue: "thread")]?.metadata.threadPermissions
        )
        #expect(permissions.approvalPolicy == expectedApprovalPolicy)
        #expect(permissions.sandboxMode == expectedSandboxMode)
    }
}

@Test
func legacySwiftTypedKeyDictionariesDecodeAndRewriteAsContractObjects() throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let encoder = JSONEncoder()
    MapofAgentsJSONCoding.configureContractDates(on: encoder)
    let data = Data(
        """
        {
          "workspaceID": "legacy-swift-dictionaries",
          "title": "Legacy Swift dictionaries",
          "nodes": [
            "thread",
            {
              "id": "thread",
              "kind": "codexThread",
              "title": "Thread",
              "subtitle": "",
              "position": { "x": 0, "y": 0 },
              "size": { "width": 200, "height": 132 },
              "metadata": {},
              "zIndex": 0
            }
          ],
          "manualEdges": [
            "edge",
            {
              "id": "edge",
              "source": "thread",
              "target": "thread",
              "kind": "manualNote",
              "isManual": true,
              "label": "Legacy"
            }
          ],
          "viewport": { "scale": 1, "offset": { "x": 0, "y": 0 } },
          "updatedAt": "2026-06-02T00:00:00Z"
        }
        """.utf8
    )

    let graph = try decoder.decode(AgentGraph.self, from: data)
    #expect(graph.nodes[NodeID(rawValue: "thread")]?.title == "Thread")
    #expect(graph.manualEdges[EdgeID(rawValue: "edge")]?.label == "Legacy")

    let encoded = try #require(
        JSONSerialization.jsonObject(with: encoder.encode(graph)) as? [String: Any]
    )
    #expect(encoded["nodes"] is [String: Any])
    #expect(encoded["manualEdges"] is [String: Any])
}

private func repositoryFile(_ components: String...) -> URL {
    var url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    for component in components {
        url.appendPathComponent(component)
    }
    return url
}

private func canonicalJSONSemanticFingerprint(_ data: Data) throws -> String {
    let value = try JSONSerialization.jsonObject(with: data)
    let canonicalData = try JSONSerialization.data(
        withJSONObject: value,
        options: [.sortedKeys, .withoutEscapingSlashes]
    )
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in canonicalData {
        hash ^= UInt64(byte)
        hash = hash &* 1_099_511_628_211
    }
    return String(format: "%016llx", hash)
}
