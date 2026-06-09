import Foundation
import Testing
@testable import MapofAgentsCore

@Test
func localStorePersistsWorkflowEvents() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-workflow-store-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let event = WorkflowEvent(
        kind: .turnCompleted,
        hostID: HostID(rawValue: "local"),
        threadID: "thread-1",
        turnID: "turn-1",
        method: "turn/completed",
        summary: "Turn completed",
        createdAt: Date(timeIntervalSince1970: 1_234)
    )

    try await store.saveWorkflowEvents([event])
    let restoredEvents = try await store.loadWorkflowEvents()

    #expect(restoredEvents == [event])

    try? FileManager.default.removeItem(at: directory)
}

@Test
func localStorePersistsRelayEndpoints() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-relay-store-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let endpoint = AppServerRelayEndpoint(
        id: HostID(rawValue: "relay-a"),
        name: "Relay A",
        url: try #require(URL(string: "ws://127.0.0.1:18949")),
        bearerToken: "secret"
    )

    try await store.saveRelayEndpoints([endpoint])
    let restoredEndpoints = try await store.loadRelayEndpoints()
    let raw = try String(
        contentsOf: directory.appendingPathComponent("relay-endpoints.json"),
        encoding: .utf8
    )

    #expect(raw.contains("secret") == false)
    #expect(raw.contains("__redacted__"))
    #expect(restoredEndpoints.first?.id == endpoint.id)
    #expect(restoredEndpoints.first?.bearerToken == nil)

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func workflowSupervisorStoreSkipsTailnetDirectRelayEndpointsOnRestore() async throws {
    let store = WorkflowSupervisorStore()
    let endpoint = AppServerRelayEndpoint(
        id: HostID(rawValue: "relay-ws-desktop-example-tailnet"),
        name: "Tailnet direct",
        url: try #require(URL(string: "ws://desktop.example.ts.net:18945"))
    )

    await store.restoreRelayEndpoints([endpoint])

    #expect(store.relayEndpoints.isEmpty)
    #expect(store.machines.isEmpty)
}

@Test
@MainActor
func workflowSupervisorStoreSkipsCodexRemoteTunnelEndpointsOnRestore() async throws {
    let store = WorkflowSupervisorStore()
    let endpoint = AppServerRelayEndpoint(
        id: HostID(rawValue: "codex-remote-windows-desktop"),
        name: "Windows Desktop",
        url: try #require(URL(string: "ws://127.0.0.1:51234"))
    )

    await store.restoreRelayEndpoints([endpoint])

    #expect(store.relayEndpoints.isEmpty)
    #expect(store.machines.isEmpty)
}

@Test
@MainActor
func workflowSupervisorStoreSkipsUnauthenticatedRemoteRelayEndpointsOnRestore() async throws {
    let store = WorkflowSupervisorStore()
    let endpoint = AppServerRelayEndpoint(
        id: HostID(rawValue: "relay-remote"),
        name: "Remote",
        url: try #require(URL(string: "wss://mac.example.test:18945"))
    )

    await store.restoreRelayEndpoints([endpoint])

    #expect(store.relayEndpoints.isEmpty)
    #expect(store.machines.isEmpty)
}

@Test
@MainActor
func workflowSupervisorStoreRejectsCleartextBearerRelayEndpoint() async throws {
    let store = WorkflowSupervisorStore()

    let hostID = await store.connectRemote(
        name: "Remote",
        endpoint: "ws://mac.lan:18945",
        bearerToken: "secret"
    )

    #expect(hostID == nil)
    #expect(store.machines.first?.status == .failed)
    #expect(store.machines.first?.lastError?.contains("wss://") == true)
}

@Test
@MainActor
func workflowSupervisorStoreStagesEndpointAttemptsByStableHostID() async throws {
    let store = WorkflowSupervisorStore()
    let hostID = HostID(rawValue: "paired-mac")
    let firstEndpoint = AppServerRelayEndpoint(
        id: hostID,
        name: "Paired Mac",
        url: try #require(URL(string: "ws://10.0.0.4:18945"))
    )
    let secondEndpoint = AppServerRelayEndpoint(
        id: hostID,
        name: "Paired Mac",
        url: try #require(URL(string: "ws://192.168.1.42:18945"))
    )

    let firstState = await store.stageRelayEndpointAttempt(
        firstEndpoint,
        at: Date(timeIntervalSince1970: 1_000)
    )
    let secondState = await store.stageRelayEndpointAttempt(
        secondEndpoint,
        at: Date(timeIntervalSince1970: 1_001)
    )

    #expect(firstState.attemptCount == 1)
    #expect(secondState.attemptCount == 2)
    #expect(store.relayEndpoints == [secondEndpoint])
    #expect(store.activeRelayEndpoint(for: hostID) == secondEndpoint)
    #expect(store.machines.filter { $0.id == hostID }.count == 1)

    let machine = try #require(store.machines.first { $0.id == hostID })
    #expect(machine.name == "Paired Mac")
    #expect(machine.endpointDescription == secondEndpoint.url.absoluteString)
    #expect(machine.status == .connecting)
}

@Test
@MainActor
func workflowSupervisorStoreBacksOffEndpointAttemptsByStableHostID() async throws {
    let store = WorkflowSupervisorStore()
    let hostID = HostID(rawValue: "paired-mac")
    let endpoint = AppServerRelayEndpoint(
        id: hostID,
        name: "Paired Mac",
        url: try #require(URL(string: "ws://10.0.0.4:18945"))
    )
    let startedAt = Date(timeIntervalSince1970: 2_000)

    await store.stageRelayEndpointAttempt(endpoint, at: startedAt)
    let firstFailure = try #require(
        await store.recordRelayEndpointAttemptFailure(
            hostID: hostID,
            message: "Timed out",
            at: startedAt
        )
    )

    #expect(firstFailure.consecutiveFailures == 1)
    #expect(firstFailure.nextAttemptAt == startedAt.addingTimeInterval(2))
    #expect(store.canAttemptRelayEndpoint(for: hostID, at: startedAt.addingTimeInterval(1)) == false)
    #expect(store.canAttemptRelayEndpoint(for: hostID, at: startedAt.addingTimeInterval(2)) == true)

    let failedMachine = try #require(store.machines.first { $0.id == hostID })
    #expect(failedMachine.status == .failed)
    #expect(failedMachine.lastError == "Timed out")

    await store.stageRelayEndpointAttempt(endpoint, at: startedAt.addingTimeInterval(2))
    let secondFailure = try #require(
        await store.recordRelayEndpointAttemptFailure(
            hostID: hostID,
            message: "Still offline",
            at: startedAt.addingTimeInterval(3)
        )
    )

    #expect(secondFailure.consecutiveFailures == 2)
    #expect(secondFailure.nextAttemptAt == startedAt.addingTimeInterval(7))

    let success = try #require(await store.recordRelayEndpointAttemptSuccess(hostID: hostID))
    #expect(success.consecutiveFailures == 0)
    #expect(success.nextAttemptAt == nil)
    #expect(success.lastError == nil)
    #expect(store.machines.first { $0.id == hostID }?.status == .connected)
}

@Test
@MainActor
func workflowSupervisorReconnectRespectsRelayBackoff() async throws {
    let store = WorkflowSupervisorStore()
    let hostID = HostID(rawValue: "paired-mac")
    let endpoint = AppServerRelayEndpoint(
        id: hostID,
        name: "Paired Mac",
        url: try #require(URL(string: "ws://127.0.0.1:9"))
    )
    let startedAt = Date()

    await store.stageRelayEndpointAttempt(endpoint, at: startedAt)
    await store.recordRelayEndpointAttemptFailure(
        hostID: hostID,
        message: "Connection refused",
        at: startedAt
    )

    await store.reconnect(hostID)

    #expect(store.relayEndpointAttempts[hostID]?.attemptCount == 1)
}

@Test
func workflowSupervisorDeduplicatesEventsAndTracksMachines() async throws {
    let supervisor = WorkflowSupervisor()
    let machineID = HostID(rawValue: "machine-a")
    await supervisor.upsertMachine(
        SupervisorMachine(
            id: machineID,
            name: "Machine A",
            endpointDescription: "daemon proxy"
        )
    )

    let event = WorkflowEvent(
        id: "event-1",
        kind: .turnStarted,
        threadID: "thread-1",
        method: "turn/started",
        summary: "Turn started"
    )

    let firstEnvelope = await supervisor.ingest(event, from: machineID)
    let duplicateEnvelope = await supervisor.ingest(event, from: machineID)
    let machines = await supervisor.machineSnapshot()
    let events = await supervisor.recentEvents()

    #expect(firstEnvelope != nil)
    #expect(duplicateEnvelope == nil)
    #expect(events.count == 1)
    #expect(events.first?.event.hostID == machineID)
    #expect(machines.first?.status == .connected)
    #expect(machines.first?.lastEventAt != nil)
}

@Test
func workflowEventParsesAppServerNotifications() async throws {
    let notification = CodexServerNotification(
        method: "turn/completed",
        params: .object([
            "threadId": .string("thread-1"),
            "turn": .object([
                "id": .string("turn-1"),
            ]),
        ])
    )

    let event = WorkflowEvent.appServerEvent(
        from: notification,
        hostID: HostID(rawValue: "remote-a")
    )

    #expect(event?.kind == .turnCompleted)
    #expect(event?.hostID == HostID(rawValue: "remote-a"))
    #expect(event?.threadID == "thread-1")
    #expect(event?.turnID == "turn-1")
    #expect(event?.summary == "Turn completed")
}

@Test
func workflowHookEventParserMapsTurnCompletion() async throws {
    let line = """
    {"kind":"turnCompleted","threadID":"thread-1","turnID":"turn-1","createdAt":"2026-05-28T10:15:30Z"}
    """

    let event = try #require(
        WorkflowHookEventParser.workflowEvent(
            from: line,
            defaultHostID: HostID(rawValue: "local")
        )
    )

    #expect(event.kind == .turnCompleted)
    #expect(event.hostID == HostID(rawValue: "local"))
    #expect(event.threadID == "thread-1")
    #expect(event.turnID == "turn-1")
    #expect(event.method == "turn/completed")
    #expect(event.summary == "Turn completed")
    #expect(event.createdAt == ISO8601DateFormatter().date(from: "2026-05-28T10:15:30Z"))
}

@Test
func workflowHookEventParserAcceptsNotifyAliasesAndSessionID() async throws {
    let line = """
    {"event":"turn-ended","session_id":"session-1","timestamp":1779989000,"summary":"Hook completed"}
    """

    let event = try #require(
        WorkflowHookEventParser.workflowEvent(
            from: line,
            defaultHostID: HostID(rawValue: "local")
        )
    )

    #expect(event.kind == .turnCompleted)
    #expect(event.threadID == "session-1")
    #expect(event.turnID == nil)
    #expect(event.summary == "Hook completed")
    #expect(event.id.hasPrefix("hook-turnCompleted-local-session-1-turn/completed-"))
}

@Test
func workflowHookEventParserMapsThreadCreatedBridgeEvent() async throws {
    let line = """
    {
      "type": "thread.created",
      "sourceHostID": "local",
      "sourceThreadID": "source-thread",
      "sourceTurnID": "turn-1",
      "childHostID": "remote",
      "childThreadID": "child-thread",
      "cwd": "/Users/example/project",
      "title": "Mock Expense Policy",
      "kind": "thread",
      "createdAt": "2026-05-28T10:16:30Z"
    }
    """

    let event = try #require(
        WorkflowHookEventParser.workflowEvent(
            from: line,
            defaultHostID: HostID(rawValue: "fallback")
        )
    )

    #expect(event.kind == .threadCreated)
    #expect(event.hostID == HostID(rawValue: "local"))
    #expect(event.threadID == "source-thread")
    #expect(event.turnID == "turn-1")
    #expect(event.childHostID == HostID(rawValue: "remote"))
    #expect(event.childThreadID == "child-thread")
    #expect(event.childCWD == "/Users/example/project")
    #expect(event.childTitle == "Mock Expense Policy")
    #expect(event.childThreadKind == .thread)
    #expect(event.childThreadRef == ThreadRef(
        hostID: HostID(rawValue: "remote"),
        threadID: "child-thread",
        cwd: "/Users/example/project",
        name: "Mock Expense Policy"
    ))
    #expect(event.method == "thread/created")
    #expect(event.summary == "Created Mock Expense Policy")
    #expect(event.dedupeKey.contains("child-thread"))
}

@Test
func workflowHookEventParserMapsFolderCreatedBridgeEvent() async throws {
    let line = """
    {
      "type": "folder.created",
      "sourceHostID": "local",
      "sourceThreadID": "source-thread",
      "sourceTurnID": "turn-1",
      "childHostID": "remote",
      "folderPath": "/Users/example/projects/new-workspace",
      "title": "new-workspace",
      "createdAt": "2026-05-28T10:17:30Z"
    }
    """

    let event = try #require(
        WorkflowHookEventParser.workflowEvent(
            from: line,
            defaultHostID: HostID(rawValue: "fallback")
        )
    )

    #expect(event.kind == .folderCreated)
    #expect(event.hostID == HostID(rawValue: "local"))
    #expect(event.threadID == "source-thread")
    #expect(event.turnID == "turn-1")
    #expect(event.childHostID == HostID(rawValue: "remote"))
    #expect(event.childFolderPath == "/Users/example/projects/new-workspace")
    #expect(event.childTitle == "new-workspace")
    #expect(event.method == "folder/created")
    #expect(event.summary == "Created folder new-workspace")
    #expect(event.dedupeKey == WorkflowEvent.folderCreatedID(
        sourceHostID: HostID(rawValue: "local"),
        sourceThreadID: "source-thread",
        childHostID: HostID(rawValue: "remote"),
        childFolderPath: "/Users/example/projects/new-workspace"
    ))
}

@Test
func workflowHookEventParserIgnoresUnknownLines() async throws {
    #expect(WorkflowHookEventParser.workflowEvent(from: "not json", defaultHostID: HostID(rawValue: "local")) == nil)
    #expect(WorkflowHookEventParser.workflowEvent(from: "{\"event\":\"noise\"}", defaultHostID: HostID(rawValue: "local")) == nil)
}

@Test
func workflowEventIDsAreStableForTheSameServerEvent() async throws {
    let notification = CodexServerNotification(
        method: "turn/started",
        params: .object([
            "threadId": .string("thread-1"),
            "turnId": .string("turn-1"),
        ])
    )
    let hostID = HostID(rawValue: "remote-a")

    let first = try #require(WorkflowEvent.appServerEvent(from: notification, hostID: hostID))
    let second = try #require(WorkflowEvent.appServerEvent(from: notification, hostID: hostID))

    #expect(first.id == second.id)
    #expect(first.dedupeKey == second.dedupeKey)
}

@Test
func workflowSupervisorDedupesReplayedServerEventsBySemanticKey() async throws {
    let supervisor = WorkflowSupervisor()
    let hostID = HostID(rawValue: "remote-a")
    await supervisor.upsertMachine(
        SupervisorMachine(
            id: hostID,
            name: "Remote",
            endpointDescription: "ws://127.0.0.1:18945",
            status: .connected
        )
    )
    let first = WorkflowEvent(
        id: "fresh-1",
        kind: .turnCompleted,
        hostID: hostID,
        threadID: "thread-1",
        turnID: "turn-1",
        method: "turn/completed",
        summary: "Turn completed"
    )
    let replay = WorkflowEvent(
        id: "fresh-2",
        kind: .turnCompleted,
        hostID: hostID,
        threadID: "thread-1",
        turnID: "turn-1",
        method: "turn/completed",
        summary: "Turn completed"
    )

    #expect(await supervisor.ingest(first, from: hostID) != nil)
    #expect(await supervisor.ingest(replay, from: hostID) == nil)
    #expect(await supervisor.recentEvents().map(\.event.id) == ["fresh-1"])
}

@Test
func workflowSupervisorDoesNotDedupeGeneratedEventsWithoutStableIdentifiers() async throws {
    let supervisor = WorkflowSupervisor()
    let hostID = HostID(rawValue: "remote-a")
    await supervisor.upsertMachine(
        SupervisorMachine(
            id: hostID,
            name: "Remote",
            endpointDescription: "ws://127.0.0.1:18945",
            status: .connected
        )
    )
    let notification = CodexServerNotification(
        method: "item/commandExecution/requestApproval",
        params: .object([
            "threadId": .string("thread-1"),
            "command": .string("date"),
        ])
    )
    let first = try #require(WorkflowEvent.appServerEvent(from: notification, hostID: hostID))
    let second = try #require(WorkflowEvent.appServerEvent(from: notification, hostID: hostID))

    #expect(first.semanticDedupeKey == nil)
    #expect(await supervisor.ingest(first, from: hostID) != nil)
    #expect(await supervisor.ingest(second, from: hostID) != nil)
    #expect(await supervisor.recentEvents().count == 2)
}

@Test
func workflowEventUsesServerTimestampWhenPresent() throws {
    let notification = CodexServerNotification(
        method: "turn/completed",
        params: .object([
            "threadId": .string("thread-1"),
            "turnId": .string("turn-1"),
            "completedAt": .string("2026-05-27T17:42:26.802Z"),
        ])
    )

    let event = try #require(WorkflowEvent.appServerEvent(from: notification, hostID: HostID(rawValue: "remote-a")))

    #expect(abs(event.createdAt.timeIntervalSince1970 - 1_779_903_746.802) < 0.001)
}

@Test
func workflowSupervisorDoesNotMarkDisconnectedMachineConnectedFromLateEvent() async throws {
    let supervisor = WorkflowSupervisor()
    let hostID = HostID(rawValue: "remote-a")
    await supervisor.upsertMachine(
        SupervisorMachine(
            id: hostID,
            name: "Remote",
            endpointDescription: "ws://127.0.0.1:18945",
            status: .connected
        )
    )
    await supervisor.updateMachineStatus(hostID, status: .disconnected)

    _ = await supervisor.ingest(
        WorkflowEvent(
            kind: .turnCompleted,
            hostID: hostID,
            threadID: "thread-1",
            turnID: "turn-1",
            method: "turn/completed",
            summary: "Turn completed"
        ),
        from: hostID
    )

    #expect(await supervisor.machineSnapshot().first { $0.id == hostID }?.status == .disconnected)
}

@Test
@MainActor
func workflowSupervisorStoreDisconnectClearsHostRuntimeState() async throws {
    let store = WorkflowSupervisorStore()
    let hostID = HostID(rawValue: "remote-a")
    await store.restoreWorkflowEvents([
        WorkflowEvent(
            kind: .needsInput,
            hostID: hostID,
            threadID: "thread-1",
            turnID: "turn-1",
            method: "item/commandExecution/requestApproval",
            summary: "date"
        ),
    ])

    #expect(store.threadRuntimeStates.isEmpty == false)

    await store.disconnect(hostID)

    #expect(store.threadRuntimeStates.isEmpty)
}

@Test
@MainActor
func workflowSupervisorStoreIngestsLocalEvents() async throws {
    let store = WorkflowSupervisorStore()
    let host = AgentHost(
        id: HostID(rawValue: "local"),
        name: "Local",
        platform: .macOS,
        endpointDescription: "daemon proxy",
        status: .connected
    )
    let event = WorkflowEvent(
        id: "event-store-1",
        kind: .turnStarted,
        hostID: host.id,
        threadID: "thread-1",
        method: "turn/started",
        summary: "Turn started"
    )

    await store.ingestLocalEvents([event], host: host)

    #expect(store.machines.first?.id == host.id)
    #expect(store.workflowEvents == [event])
}

@Test
@MainActor
func workflowSupervisorStoreRestoresNewestEventsFirst() async throws {
    let store = WorkflowSupervisorStore()
    let started = WorkflowEvent(
        id: "started",
        kind: .turnStarted,
        hostID: HostID(rawValue: "local"),
        threadID: "thread-1",
        method: "turn/started",
        summary: "Turn started",
        createdAt: Date(timeIntervalSince1970: 10)
    )
    let completed = WorkflowEvent(
        id: "completed",
        kind: .turnCompleted,
        hostID: HostID(rawValue: "local"),
        threadID: "thread-1",
        method: "turn/completed",
        summary: "Turn completed",
        createdAt: Date(timeIntervalSince1970: 20)
    )

    await store.restoreWorkflowEvents([completed, started])

    #expect(store.workflowEvents.map(\.id) == ["completed", "started"])
}

@Test
func workflowActivityAttributionFindsRecentThreadMessageSource() {
    let sourceNode = CanvasNode(
        id: NodeID(rawValue: "source-node"),
        kind: .codexThread,
        title: "mapofagents mac to windows test",
        position: CanvasPoint(x: 0, y: 0),
        size: .thread,
        metadata: NodeMetadata(
            threadRef: ThreadRef(
                hostID: HostID(rawValue: "local"),
                threadID: "source-thread",
                cwd: "/tmp/source"
            )
        )
    )
    let targetNode = CanvasNode(
        id: NodeID(rawValue: "target-node"),
        kind: .codexThread,
        title: "test windows",
        position: CanvasPoint(x: 200, y: 0),
        size: .thread,
        metadata: NodeMetadata(
            threadRef: ThreadRef(
                hostID: HostID(rawValue: "windows"),
                threadID: "target-thread",
                cwd: "C:\\Users\\User\\Desktop"
            )
        )
    )
    var graph = AgentGraph()
    graph.upsertNode(sourceNode)
    graph.upsertNode(targetNode)
    let edge = CanvasEdge(
        id: EdgeID(rawValue: "message-edge"),
        source: sourceNode.id,
        target: targetNode.id,
        kind: .threadMessage,
        isManual: true,
        label: "message"
    )
    graph.manualEdges[edge.id] = edge

    let sourceCompleted = WorkflowEvent(
        id: "source-completed",
        kind: .turnCompleted,
        threadID: "source-thread",
        method: "turn/completed",
        summary: "Turn completed",
        createdAt: Date(timeIntervalSince1970: 100)
    )
    let targetStarted = WorkflowEvent(
        id: "target-started",
        kind: .turnStarted,
        threadID: "target-thread",
        method: "turn/started",
        summary: "Turn started",
        createdAt: Date(timeIntervalSince1970: 120)
    )

    let origin = WorkflowActivityAttribution.origin(
        for: targetStarted,
        in: graph,
        events: [targetStarted, sourceCompleted]
    )

    #expect(origin?.threadID == "source-thread")
    #expect(origin?.title == "mapofagents mac to windows test")
}

@Test
func workflowActivityAttributionPrefersMessageRouteEvidenceOverNewestManualEdgeSource() {
    let sourceHostID = HostID(rawValue: "local")
    let targetHostID = HostID(rawValue: "windows")
    let routedSourceNode = CanvasNode(
        id: NodeID(rawValue: "routed-source-node"),
        kind: .codexThread,
        title: "routed source",
        position: CanvasPoint(x: 0, y: 0),
        size: .thread,
        metadata: NodeMetadata(
            threadRef: ThreadRef(
                hostID: sourceHostID,
                threadID: "routed-source-thread",
                cwd: "/tmp/routed"
            )
        )
    )
    let newerManualSourceNode = CanvasNode(
        id: NodeID(rawValue: "newer-source-node"),
        kind: .codexThread,
        title: "newer source",
        position: CanvasPoint(x: 0, y: 120),
        size: .thread,
        metadata: NodeMetadata(
            threadRef: ThreadRef(
                hostID: sourceHostID,
                threadID: "newer-source-thread",
                cwd: "/tmp/newer"
            )
        )
    )
    let targetNode = CanvasNode(
        id: NodeID(rawValue: "target-node"),
        kind: .codexThread,
        title: "target",
        position: CanvasPoint(x: 200, y: 0),
        size: .thread,
        metadata: NodeMetadata(
            threadRef: ThreadRef(
                hostID: targetHostID,
                threadID: "target-thread",
                cwd: "C:\\Users\\User\\Desktop"
            )
        )
    )
    var graph = AgentGraph()
    graph.upsertNode(routedSourceNode)
    graph.upsertNode(newerManualSourceNode)
    graph.upsertNode(targetNode)
    let routedEdge = CanvasEdge(
        id: EdgeID(rawValue: "routed-edge"),
        source: routedSourceNode.id,
        target: targetNode.id,
        kind: .threadMessage,
        isManual: true
    )
    let newerEdge = CanvasEdge(
        id: EdgeID(rawValue: "newer-edge"),
        source: newerManualSourceNode.id,
        target: targetNode.id,
        kind: .threadMessage,
        isManual: true
    )
    graph.manualEdges[routedEdge.id] = routedEdge
    graph.manualEdges[newerEdge.id] = newerEdge

    let routedSourceCompleted = WorkflowEvent(
        id: "routed-source-completed",
        kind: .turnCompleted,
        hostID: sourceHostID,
        threadID: "routed-source-thread",
        method: "turn/completed",
        summary: "Turn completed",
        createdAt: Date(timeIntervalSince1970: 100)
    )
    let newerSourceCompleted = WorkflowEvent(
        id: "newer-source-completed",
        kind: .turnCompleted,
        hostID: sourceHostID,
        threadID: "newer-source-thread",
        method: "turn/completed",
        summary: "Turn completed",
        createdAt: Date(timeIntervalSince1970: 119)
    )
    let targetStarted = WorkflowEvent(
        id: "target-started",
        kind: .turnStarted,
        hostID: targetHostID,
        threadID: "target-thread",
        turnID: "target-turn",
        method: "turn/started",
        summary: "Turn started",
        createdAt: Date(timeIntervalSince1970: 120)
    )
    graph.messageRoutes["route-1"] = MessageRoute(
        id: "route-1",
        sourceHostID: sourceHostID,
        sourceThreadID: "routed-source-thread",
        targetHostID: targetHostID,
        targetThreadID: "target-thread",
        targetTurnID: "target-turn",
        timestamp: Date(timeIntervalSince1970: 118),
        snippet: "handoff",
        deliveryState: .pending,
        eventIDs: ["target-started"],
        canvasEdgeID: routedEdge.id
    )

    let origin = WorkflowActivityAttribution.origin(
        for: targetStarted,
        in: graph,
        events: [targetStarted, routedSourceCompleted, newerSourceCompleted]
    )

    #expect(origin?.threadID == "routed-source-thread")
    #expect(origin?.title == "routed source")
}

@Test
func workflowActivityAttributionIgnoresStaleMessageEdges() {
    let sourceNode = CanvasNode(
        id: NodeID(rawValue: "source-node"),
        kind: .codexThread,
        title: "old source",
        position: CanvasPoint(x: 0, y: 0),
        size: .thread,
        metadata: NodeMetadata(
            threadRef: ThreadRef(
                hostID: HostID(rawValue: "local"),
                threadID: "source-thread",
                cwd: "/tmp/source"
            )
        )
    )
    let targetNode = CanvasNode(
        id: NodeID(rawValue: "target-node"),
        kind: .codexThread,
        title: "test windows",
        position: CanvasPoint(x: 200, y: 0),
        size: .thread,
        metadata: NodeMetadata(
            threadRef: ThreadRef(
                hostID: HostID(rawValue: "windows"),
                threadID: "target-thread",
                cwd: "C:\\Users\\User\\Desktop"
            )
        )
    )
    var graph = AgentGraph()
    graph.upsertNode(sourceNode)
    graph.upsertNode(targetNode)
    let edge = CanvasEdge(
        id: EdgeID(rawValue: "message-edge"),
        source: sourceNode.id,
        target: targetNode.id,
        kind: .threadMessage,
        isManual: true
    )
    graph.manualEdges[edge.id] = edge

    let staleSourceEvent = WorkflowEvent(
        id: "source-completed",
        kind: .turnCompleted,
        threadID: "source-thread",
        method: "turn/completed",
        summary: "Turn completed",
        createdAt: Date(timeIntervalSince1970: 100)
    )
    let targetStarted = WorkflowEvent(
        id: "target-started",
        kind: .turnStarted,
        threadID: "target-thread",
        method: "turn/started",
        summary: "Turn started",
        createdAt: Date(timeIntervalSince1970: 2_000)
    )

    let origin = WorkflowActivityAttribution.origin(
        for: targetStarted,
        in: graph,
        events: [targetStarted, staleSourceEvent]
    )

    #expect(origin == nil)
}
