import Foundation
import Testing
@testable import MapofAgentsCore

@Test
@MainActor
func manualEdgeModeTogglesAndCancels() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-graph-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)

    await graphStore.addFolder(path: "/tmp/project")
    let folderID = try #require(graphStore.selectedNode?.id)

    graphStore.beginManualEdge(from: folderID)
    #expect(graphStore.pendingManualEdgeSource == folderID)

    graphStore.beginManualEdge(from: folderID)
    #expect(graphStore.pendingManualEdgeSource == nil)

    graphStore.beginManualEdge(from: folderID)
    graphStore.selectNode(folderID)
    #expect(graphStore.pendingManualEdgeSource == nil)

    graphStore.beginManualEdge(from: folderID)
    graphStore.clearSelection()
    #expect(graphStore.pendingManualEdgeSource == nil)

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func deletingNodeRemovesConnectedManualEdges() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-delete-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)

    let source = CanvasNode(
        id: NodeID(rawValue: "source"),
        kind: .folder,
        title: "Source",
        position: CanvasPoint(x: 0, y: 0),
        size: .folder
    )
    let target = CanvasNode(
        id: NodeID(rawValue: "target"),
        kind: .codexThread,
        title: "Target",
        position: CanvasPoint(x: 240, y: 0),
        size: .thread
    )
    let edge = CanvasEdge(
        id: EdgeID(rawValue: "edge"),
        source: source.id,
        target: target.id,
        kind: .manualNote,
        isManual: true,
        label: "note"
    )

    var graph = AgentGraph()
    graph.upsertNode(source)
    graph.upsertNode(target)
    graph.upsertManualEdge(edge)
    _ = try await store.applyCanvasPatch(.replace(graph))
    await graphStore.load()

    graphStore.selectNode(source.id)
    await graphStore.deleteSelection()

    #expect(graphStore.graph.nodes[source.id] == nil)
    #expect(graphStore.graph.nodes[target.id] != nil)
    #expect(graphStore.graph.manualEdges.isEmpty)

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func messageEdgesReuseExistingThreadMessageLine() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-message-edge-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)

    let source = CanvasNode(
        id: NodeID(rawValue: "source"),
        kind: .codexThread,
        title: "Source",
        position: CanvasPoint(x: 0, y: 0),
        size: .thread
    )
    let target = CanvasNode(
        id: NodeID(rawValue: "target"),
        kind: .codexThread,
        title: "Target",
        position: CanvasPoint(x: 240, y: 0),
        size: .thread
    )

    var graph = AgentGraph()
    graph.upsertNode(source)
    graph.upsertNode(target)
    _ = try await store.applyCanvasPatch(.replace(graph))
    await graphStore.load()

    await graphStore.createMessageEdge(from: source.id, to: target.id)
    await graphStore.createMessageEdge(from: source.id, to: target.id)

    let edges = Array(graphStore.graph.manualEdges.values)
    #expect(edges.count == 1)
    #expect(edges.first?.kind == .threadMessage)
    #expect(edges.first?.label == "message")

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func messageEdgesPersistRouteMetadataAndDeleteWithEdge() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-message-route-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)

    let hostID = HostID(rawValue: "local")
    let sourceRef = ThreadRef(hostID: hostID, threadID: "source-thread", cwd: "/tmp/project")
    let targetRef = ThreadRef(hostID: hostID, threadID: "target-thread", cwd: "/tmp/project")
    let source = CanvasNode(
        id: NodeID(rawValue: "source"),
        kind: .codexThread,
        title: "Source",
        position: CanvasPoint(x: 0, y: 0),
        size: .thread,
        metadata: NodeMetadata(hostID: hostID, threadRef: sourceRef)
    )
    let target = CanvasNode(
        id: NodeID(rawValue: "target"),
        kind: .codexThread,
        title: "Target",
        position: CanvasPoint(x: 240, y: 0),
        size: .thread,
        metadata: NodeMetadata(hostID: hostID, threadRef: targetRef)
    )

    var graph = AgentGraph()
    graph.upsertNode(source)
    graph.upsertNode(target)
    _ = try await store.applyCanvasPatch(.replace(graph))
    await graphStore.load()

    await graphStore.createMessageEdge(
        from: source.id,
        to: target.id,
        snippet: "please check this",
        deliveryState: .pending,
        eventIDs: ["event-1"]
    )

    let route = try #require(graphStore.graph.messageRoutes.values.first)
    let edge = try #require(graphStore.graph.manualEdges.values.first)
    #expect(route.sourceThreadID == sourceRef.threadID)
    #expect(route.targetThreadID == targetRef.threadID)
    #expect(route.snippet == "please check this")
    #expect(route.deliveryState == .pending)
    #expect(route.eventIDs == ["event-1"])
    #expect(route.canvasEdgeID == edge.id)

    await graphStore.deleteManualEdge(edge.id)
    #expect(graphStore.graph.manualEdges.isEmpty)
    #expect(graphStore.graph.messageRoutes.isEmpty)

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func createdThreadsMaterializeWithCreatedByEdge() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-created-thread-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)

    let sourceRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "source-thread", cwd: "/tmp/project")
    let source = CanvasNode(
        id: NodeID(rawValue: "source"),
        kind: .codexThread,
        title: "Source",
        position: CanvasPoint(x: 0, y: 0),
        size: .thread,
        metadata: NodeMetadata(
            hostID: sourceRef.hostID,
            threadRef: sourceRef,
            model: "gpt-5.5",
            reasoningEffort: "low"
        )
    )

    var graph = AgentGraph()
    graph.upsertNode(source)
    _ = try await store.applyCanvasPatch(.replace(graph))
    await graphStore.load()

    let childRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "019e4c6a-9fe3-7383-82e5-4aca4c1888f4", cwd: "/tmp/project/child", name: "Child")
    await graphStore.materializeCreatedThread(
        threadRef: childRef,
        model: source.metadata.model,
        reasoningEffort: source.metadata.reasoningEffort,
        title: childRef.name,
        createdBy: source.id
    )
    await graphStore.materializeCreatedThread(
        threadRef: childRef,
        model: source.metadata.model,
        reasoningEffort: source.metadata.reasoningEffort,
        title: childRef.name,
        createdBy: source.id
    )

    let child = try #require(graphStore.graph.nodes.values.first { $0.metadata.threadRef == childRef })
    #expect(child.title == "Child")
    #expect(child.metadata.model == "gpt-5.5")
    #expect(child.metadata.reasoningEffort == "low")
    #expect(child.metadata.threadKind == .thread)

    let createdByEdges = graphStore.graph.manualEdges.values.filter {
        $0.source == source.id && $0.target == child.id && $0.kind == .createdBy
    }
    #expect(createdByEdges.count == 1)
    #expect(createdByEdges.first?.label == "created by")

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func deletedMaterializedCreatedThreadsDoNotRespawnFromTranscriptRefresh() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-created-thread-tombstone-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)

    let hostID = HostID(rawValue: "local")
    let source = CanvasNode(
        id: NodeID(rawValue: "source"),
        kind: .codexThread,
        title: "Supervisor",
        position: CanvasPoint(x: 0, y: 0),
        size: .thread,
        metadata: NodeMetadata(
            hostID: hostID,
            threadRef: ThreadRef(hostID: hostID, threadID: "parent", cwd: "/tmp/project")
        )
    )

    var graph = AgentGraph()
    graph.upsertNode(source)
    _ = try await store.applyCanvasPatch(.replace(graph))
    await graphStore.load()

    let childRef = ThreadRef(hostID: hostID, threadID: "child", cwd: "/tmp/project/child", name: "Child")
    await graphStore.materializeCreatedThread(
        threadRef: childRef,
        model: "gpt-5.5",
        reasoningEffort: "low",
        title: childRef.name,
        createdBy: source.id
    )

    let child = try #require(graphStore.graph.nodes.values.first {
        $0.metadata.threadRef?.qualifiedID == childRef.qualifiedID
    })
    await graphStore.deleteNode(child.id)

    #expect(graphStore.graph.nodes.values.contains {
        $0.metadata.threadRef?.qualifiedID == childRef.qualifiedID
    } == false)
    #expect(graphStore.graph.isAutoMaterializationSuppressed(for: childRef))

    await graphStore.materializeCreatedThread(
        threadRef: childRef,
        model: "gpt-5.5",
        reasoningEffort: "low",
        title: childRef.name,
        createdBy: source.id
    )

    #expect(graphStore.graph.nodes.values.contains {
        $0.metadata.threadRef?.qualifiedID == childRef.qualifiedID
    } == false)
    #expect(graphStore.graph.manualEdges.values.contains { $0.kind == .createdBy && $0.target == child.id } == false)

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func manuallyAddingDeletedCreatedThreadAllowsCreatedByEdgeAgain() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-created-thread-manual-restore-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)

    let hostID = HostID(rawValue: "local")
    let source = CanvasNode(
        id: NodeID(rawValue: "source"),
        kind: .codexThread,
        title: "Supervisor",
        position: CanvasPoint(x: 0, y: 0),
        size: .thread,
        metadata: NodeMetadata(
            hostID: hostID,
            threadRef: ThreadRef(hostID: hostID, threadID: "parent", cwd: "/tmp/project")
        )
    )

    var graph = AgentGraph()
    graph.upsertNode(source)
    _ = try await store.applyCanvasPatch(.replace(graph))
    await graphStore.load()

    let childRef = ThreadRef(hostID: hostID, threadID: "child", cwd: "/tmp/project/child", name: "Child")
    await graphStore.materializeCreatedThread(
        threadRef: childRef,
        model: "gpt-5.5",
        reasoningEffort: "low",
        title: childRef.name,
        createdBy: source.id
    )

    let child = try #require(graphStore.graph.nodes.values.first {
        $0.metadata.threadRef?.qualifiedID == childRef.qualifiedID
    })
    await graphStore.deleteNode(child.id)
    #expect(graphStore.graph.isAutoMaterializationSuppressed(for: childRef))

    await graphStore.addThreadNode(
        threadRef: childRef,
        model: "gpt-5.5",
        reasoningEffort: "low",
        title: childRef.name
    )
    #expect(graphStore.graph.isAutoMaterializationSuppressed(for: childRef) == false)

    await graphStore.materializeCreatedThread(
        threadRef: childRef,
        model: "gpt-5.5",
        reasoningEffort: "low",
        title: childRef.name,
        createdBy: source.id
    )

    let restored = try #require(graphStore.graph.nodes.values.first {
        $0.metadata.threadRef?.qualifiedID == childRef.qualifiedID
    })
    let createdByEdges = graphStore.graph.manualEdges.values.filter {
        $0.source == source.id && $0.target == restored.id && $0.kind == .createdBy
    }
    #expect(createdByEdges.count == 1)

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func materializedSubagentsKeepSubagentKindOnCanvas() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-subagent-kind-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)

    let hostID = HostID(rawValue: "local")
    let source = CanvasNode(
        id: NodeID(rawValue: "source"),
        kind: .codexThread,
        title: "Supervisor",
        position: CanvasPoint(x: 0, y: 0),
        size: .thread,
        metadata: NodeMetadata(hostID: hostID, threadRef: ThreadRef(hostID: hostID, threadID: "parent", cwd: "/tmp/project"))
    )

    var graph = AgentGraph()
    graph.upsertNode(source)
    _ = try await store.applyCanvasPatch(.replace(graph))
    await graphStore.load()

    let subagentRef = ThreadRef(hostID: hostID, threadID: "child", cwd: "/tmp/project", name: "PDF reader")
    await graphStore.materializeCreatedThread(
        threadRef: subagentRef,
        model: "gpt-5.5",
        reasoningEffort: "xhigh",
        title: subagentRef.name,
        createdBy: source.id,
        threadKind: .subagent
    )

    let subagentNode = try #require(graphStore.graph.nodes.values.first {
        $0.metadata.threadRef?.threadID == subagentRef.threadID
    })
    #expect(subagentNode.metadata.threadKind == .subagent)

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func replayedSubagentWithDifferentThreadIDReusesExistingNodeAndEdge() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-subagent-replay-dedupe-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)

    let hostID = HostID(rawValue: "local")
    let source = CanvasNode(
        id: NodeID(rawValue: "source"),
        kind: .codexThread,
        title: "Supervisor",
        position: CanvasPoint(x: 0, y: 0),
        size: .thread,
        metadata: NodeMetadata(hostID: hostID, threadRef: ThreadRef(hostID: hostID, threadID: "parent", cwd: "/tmp/project"))
    )

    var graph = AgentGraph()
    graph.upsertNode(source)
    _ = try await store.applyCanvasPatch(.replace(graph))
    await graphStore.load()

    let firstSubagentRef = ThreadRef(
        hostID: hostID,
        threadID: "child-thread-a",
        cwd: "/tmp/project",
        name: "Thread name: PDF reader"
    )
    let replayedSubagentRef = ThreadRef(
        hostID: hostID,
        threadID: "child-thread-b",
        cwd: "/tmp/project",
        name: "PDF reader"
    )

    await graphStore.materializeCreatedThread(
        threadRef: firstSubagentRef,
        model: "gpt-5.5",
        reasoningEffort: "xhigh",
        title: firstSubagentRef.name,
        createdBy: source.id,
        threadKind: .subagent
    )
    await graphStore.materializeCreatedThread(
        threadRef: replayedSubagentRef,
        model: "gpt-5.5",
        reasoningEffort: "xhigh",
        title: replayedSubagentRef.name,
        createdBy: source.id,
        threadKind: .subagent
    )

    let subagentNodes = graphStore.graph.nodes.values.filter {
        $0.metadata.threadKind == .subagent
    }
    #expect(subagentNodes.count == 1)

    let subagent = try #require(subagentNodes.first)
    #expect(subagent.title == "PDF reader")
    #expect(subagent.metadata.threadRef?.threadID == firstSubagentRef.threadID)
    #expect(graphStore.graph.nodes.values.contains {
        $0.metadata.threadRef?.threadID == replayedSubagentRef.threadID
    } == false)

    let createdByEdges = graphStore.graph.manualEdges.values.filter {
        $0.source == source.id && $0.target == subagent.id && $0.kind == .createdBy
    }
    #expect(createdByEdges.count == 1)

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func sameRoleSubagentFromDifferentParentGetsForkLabel() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-subagent-fork-label-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)

    let hostID = HostID(rawValue: "local")
    let firstSource = CanvasNode(
        id: NodeID(rawValue: "source-a"),
        kind: .codexThread,
        title: "Supervisor A",
        position: CanvasPoint(x: 0, y: 0),
        size: .thread,
        metadata: NodeMetadata(hostID: hostID, threadRef: ThreadRef(hostID: hostID, threadID: "parent-a", cwd: "/tmp/project"))
    )
    let secondSource = CanvasNode(
        id: NodeID(rawValue: "source-b"),
        kind: .codexThread,
        title: "Supervisor B",
        position: CanvasPoint(x: 0, y: 240),
        size: .thread,
        metadata: NodeMetadata(hostID: hostID, threadRef: ThreadRef(hostID: hostID, threadID: "parent-b", cwd: "/tmp/project"))
    )

    var graph = AgentGraph()
    graph.upsertNode(firstSource)
    graph.upsertNode(secondSource)
    _ = try await store.applyCanvasPatch(.replace(graph))
    await graphStore.load()

    let firstSubagentRef = ThreadRef(hostID: hostID, threadID: "child-a", cwd: "/tmp/project", name: "PDF reader")
    let forkedSubagentRef = ThreadRef(hostID: hostID, threadID: "child-b", cwd: "/tmp/project", name: "PDF reader")

    await graphStore.materializeCreatedThread(
        threadRef: firstSubagentRef,
        model: "gpt-5.5",
        reasoningEffort: "xhigh",
        title: firstSubagentRef.name,
        createdBy: firstSource.id,
        threadKind: .subagent
    )
    await graphStore.materializeCreatedThread(
        threadRef: forkedSubagentRef,
        model: "gpt-5.5",
        reasoningEffort: "xhigh",
        title: forkedSubagentRef.name,
        createdBy: secondSource.id,
        threadKind: .subagent
    )

    let subagentNodes = graphStore.graph.nodes.values.filter {
        $0.metadata.threadKind == .subagent
    }
    #expect(subagentNodes.count == 2)
    #expect(subagentNodes.contains { $0.title == "PDF reader" })
    #expect(subagentNodes.contains { $0.title == "PDF reader fork" })

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func loadingGraphNormalizesDuplicateCreatedThreadsAndOrphanEdges() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-created-thread-normalize-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)

    let hostID = HostID(rawValue: "local")
    let sourceRef = ThreadRef(hostID: hostID, threadID: "source-thread", cwd: "/tmp/project", name: "Supervisor")
    let childRef = ThreadRef(hostID: hostID, threadID: "child-thread", cwd: "/tmp/project", name: "Thread name: worker docx reader with a very long prompt that should not be the display title")
    let betterChildRef = ThreadRef(hostID: hostID, threadID: "child-thread", cwd: "/tmp/project", name: "Ohm")

    let source = CanvasNode(
        id: NodeID(rawValue: "source"),
        kind: .codexThread,
        title: "Supervisor",
        position: CanvasPoint(x: 0, y: 0),
        size: .thread,
        metadata: NodeMetadata(hostID: hostID, threadRef: sourceRef)
    )
    let verboseDuplicate = CanvasNode(
        id: NodeID(rawValue: "child-a"),
        kind: .codexThread,
        title: "Thread name: worker docx reader with a very long prompt that should not be the display title",
        subtitle: "/tmp/project",
        position: CanvasPoint(x: 200, y: 0),
        size: .thread,
        metadata: NodeMetadata(hostID: hostID, threadRef: childRef, model: "gpt-5.5", runStatus: .idle),
        zIndex: 1
    )
    let namedDuplicate = CanvasNode(
        id: NodeID(rawValue: "child-b"),
        kind: .codexThread,
        title: "Ohm",
        subtitle: "/tmp/project",
        position: CanvasPoint(x: 260, y: 60),
        size: .thread,
        metadata: NodeMetadata(hostID: hostID, threadRef: betterChildRef, reasoningEffort: "xhigh", runStatus: .complete),
        zIndex: 2
    )
    let edgeA = CanvasEdge(
        id: EdgeID(rawValue: "created-a"),
        source: source.id,
        target: verboseDuplicate.id,
        kind: .createdBy,
        isManual: true,
        label: "created by"
    )
    let edgeB = CanvasEdge(
        id: EdgeID(rawValue: "created-b"),
        source: source.id,
        target: namedDuplicate.id,
        kind: .createdBy,
        isManual: true,
        label: "created by"
    )
    let orphanEdge = CanvasEdge(
        id: EdgeID(rawValue: "orphan"),
        source: source.id,
        target: NodeID(rawValue: "missing"),
        kind: .createdBy,
        isManual: true,
        label: "created by"
    )
    let orphanRoute = MessageRoute(
        id: "route-orphan",
        sourceHostID: hostID,
        sourceThreadID: sourceRef.threadID,
        targetHostID: hostID,
        targetThreadID: childRef.threadID,
        snippet: "orphan",
        canvasEdgeID: orphanEdge.id
    )

    var graph = AgentGraph()
    graph.upsertNode(source)
    graph.upsertNode(verboseDuplicate)
    graph.upsertNode(namedDuplicate)
    graph.upsertManualEdge(edgeA)
    graph.upsertManualEdge(edgeB)
    graph.upsertManualEdge(orphanEdge)
    graph.upsertMessageRoute(orphanRoute)
    _ = try await store.applyCanvasPatch(.replace(graph))

    await graphStore.load()

    let childNodes = graphStore.graph.nodes.values.filter {
        $0.metadata.threadRef?.threadID == childRef.threadID
    }
    #expect(childNodes.count == 1)

    let child = try #require(childNodes.first)
    #expect(child.title == "Ohm")
    #expect(child.metadata.threadRef?.name == "Ohm")
    #expect(child.metadata.model == "gpt-5.5")
    #expect(child.metadata.reasoningEffort == "xhigh")
    #expect(child.metadata.runStatus == .complete)

    let createdByEdges = graphStore.graph.manualEdges.values.filter { $0.kind == .createdBy }
    #expect(createdByEdges.count == 1)
    #expect(createdByEdges.first?.source == source.id)
    #expect(createdByEdges.first?.target == child.id)
    #expect(graphStore.graph.messageRoutes[orphanRoute.id] == nil)

    let persistedGraph = try await store.loadCanvas()
    #expect(persistedGraph.nodes.values.filter { $0.metadata.threadRef?.threadID == childRef.threadID }.count == 1)
    #expect(persistedGraph.manualEdges.values.filter { $0.kind == .createdBy }.count == 1)

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func materializingCreatedThreadUpdatesVerboseExistingTitleWithNickname() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-created-thread-title-repair-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)

    let hostID = HostID(rawValue: "local")
    let sourceRef = ThreadRef(hostID: hostID, threadID: "source-thread", cwd: "/tmp/project", name: "Supervisor")
    let existingRef = ThreadRef(
        hostID: hostID,
        threadID: "child-thread",
        cwd: "/tmp/project",
        name: "Thread name: worker html reader with a very long prompt that should be replaced"
    )
    let source = CanvasNode(
        id: NodeID(rawValue: "source"),
        kind: .codexThread,
        title: "Supervisor",
        position: CanvasPoint(x: 0, y: 0),
        size: .thread,
        metadata: NodeMetadata(hostID: hostID, threadRef: sourceRef)
    )
    let existing = CanvasNode(
        id: NodeID(rawValue: "child"),
        kind: .codexThread,
        title: "Thread name: worker html reader with a very long prompt that should be replaced",
        subtitle: "/tmp/project",
        position: CanvasPoint(x: 240, y: 0),
        size: .thread,
        metadata: NodeMetadata(hostID: hostID, threadRef: existingRef)
    )

    var graph = AgentGraph()
    graph.upsertNode(source)
    graph.upsertNode(existing)
    _ = try await store.applyCanvasPatch(.replace(graph))
    await graphStore.load()

    await graphStore.materializeCreatedThread(
        threadRef: ThreadRef(hostID: hostID, threadID: existingRef.threadID, cwd: existingRef.cwd, name: "Singer"),
        model: "gpt-5.5",
        reasoningEffort: "xhigh",
        title: "Singer",
        createdBy: source.id
    )

    let childNodes = graphStore.graph.nodes.values.filter {
        $0.metadata.threadRef?.threadID == existingRef.threadID
    }
    #expect(childNodes.count == 1)
    let child = try #require(childNodes.first)
    #expect(child.id == existing.id)
    #expect(child.title == "Singer")
    #expect(child.metadata.threadRef?.name == "Singer")

    let createdByEdges = graphStore.graph.manualEdges.values.filter {
        $0.source == source.id && $0.target == existing.id && $0.kind == .createdBy
    }
    #expect(createdByEdges.count == 1)

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func loadingGraphNormalizesVerboseThreadPromptTitle() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-created-thread-title-normalize-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)

    let hostID = HostID(rawValue: "local")
    let verboseTitle = """
    Thread name: worker docx

    Use /Users/example/.codex/skills/codex-app-server-patterns/SKILL.md as the orchestration context.
    """
    let threadRef = ThreadRef(hostID: hostID, threadID: "worker-thread", cwd: "/tmp/project", name: verboseTitle)
    let node = CanvasNode(
        id: NodeID(rawValue: "worker"),
        kind: .codexThread,
        title: verboseTitle,
        subtitle: "/tmp/project",
        position: CanvasPoint(x: 0, y: 0),
        size: .thread,
        metadata: NodeMetadata(hostID: hostID, threadRef: threadRef)
    )

    var graph = AgentGraph()
    graph.upsertNode(node)
    _ = try await store.applyCanvasPatch(.replace(graph))

    await graphStore.load()

    let loaded = try #require(graphStore.graph.nodes[node.id])
    #expect(loaded.title == "worker docx")
    #expect(loaded.metadata.threadRef?.name == "worker docx")

    let persisted = try await store.loadCanvas()
    #expect(persisted.nodes[node.id]?.title == "worker docx")

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func workflowTurnCompletionCanMarkThreadUnread() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-unread-event-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)

    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-a", cwd: "/tmp/project")
    let thread = CanvasNode(
        id: NodeID(rawValue: "thread"),
        kind: .codexThread,
        title: "Thread",
        position: CanvasPoint(x: 0, y: 0),
        size: .thread,
        metadata: NodeMetadata(hostID: threadRef.hostID, threadRef: threadRef)
    )

    var graph = AgentGraph()
    graph.upsertNode(thread)
    _ = try await store.applyCanvasPatch(.replace(graph))
    await graphStore.load()

    await graphStore.applyWorkflowEvent(
        WorkflowEvent(
            kind: .turnCompleted,
            hostID: threadRef.hostID,
            threadID: threadRef.threadID,
            method: "turn/completed",
            summary: "Turn completed"
        ),
        markUnread: true
    )

    #expect(graphStore.graph.nodes[thread.id]?.metadata.runStatus == .complete)
    #expect(graphStore.graph.nodes[thread.id]?.metadata.isUnread == true)

    await graphStore.markThreadRead(thread.id)
    #expect(graphStore.graph.nodes[thread.id]?.metadata.isUnread == false)

    await graphStore.markThreadUnread(thread.id)
    #expect(graphStore.graph.nodes[thread.id]?.metadata.isUnread == true)

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func workflowEventDoesNotMarkUnreadUnlessRequested() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-unread-default-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)

    let threadRef = ThreadRef(hostID: HostID(rawValue: "remote"), threadID: "thread-b", cwd: "/tmp/project")
    let thread = CanvasNode(
        id: NodeID(rawValue: "thread"),
        kind: .codexThread,
        title: "Thread",
        position: CanvasPoint(x: 0, y: 0),
        size: .thread,
        metadata: NodeMetadata(hostID: threadRef.hostID, threadRef: threadRef)
    )

    var graph = AgentGraph()
    graph.upsertNode(thread)
    _ = try await store.applyCanvasPatch(.replace(graph))
    await graphStore.load()

    await graphStore.applyWorkflowEvent(
        WorkflowEvent(
            kind: .turnCompleted,
            hostID: threadRef.hostID,
            threadID: threadRef.threadID,
            method: "turn/completed",
            summary: "Turn completed"
        )
    )

    #expect(graphStore.graph.nodes[thread.id]?.metadata.runStatus == .complete)
    #expect(graphStore.graph.nodes[thread.id]?.metadata.isUnread != true)

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func materializeWorkflowFolderRootCreatesFolderUnderMachine() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-folder-created-root-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)

    let hostID = HostID(rawValue: "remote-windows")
    await graphStore.applySupervisorMachine(
        SupervisorMachine(
            id: hostID,
            name: "Windows Desktop",
            endpointDescription: "example-host.local",
            status: .connected,
            platform: .windows
        )
    )

    let folderID = try #require(
        await graphStore.materializeWorkflowFolderRoot(
            path: #"C:\Users\User\Desktop"#,
            hostID: hostID,
            title: "Desktop"
        )
    )
    let folder = try #require(graphStore.graph.nodes[folderID])

    #expect(folder.kind == .folder)
    #expect(folder.title == "Desktop")
    #expect(folder.subtitle == #"C:\Users\User\Desktop"#)
    #expect(folder.metadata.hostID == hostID)
    #expect(folder.metadata.platform == .windows)
    #expect(folder.metadata.folderPath == #"C:\Users\User\Desktop"#)
    #expect(graphStore.semanticEdges.contains { edge in
        edge.kind == .machineFolder
            && edge.target == folderID
            && graphStore.graph.nodes[edge.source]?.metadata.hostID == hostID
    })

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func materializeWorkflowFolderRootIgnoresDescendantFolders() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-folder-created-descendant-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)

    let hostID = HostID(rawValue: "local")
    let rootID = try #require(
        await graphStore.materializeWorkflowFolderRoot(
            path: "/Users/example/projects/root",
            hostID: hostID,
            title: "root"
        )
    )
    let descendantID = await graphStore.materializeWorkflowFolderRoot(
        path: "/Users/example/projects/root/subproject",
        hostID: hostID,
        title: "subproject"
    )

    let folders = graphStore.graph.nodes.values.filter {
        $0.kind == .folder && $0.metadata.hostID == hostID
    }
    #expect(descendantID == nil)
    #expect(folders.count == 1)
    #expect(folders.first?.id == rootID)
    #expect(folders.first?.metadata.folderPath == "/Users/example/projects/root")

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func materializeWorkflowFolderRootFromEventRequiresMappedSourceThread() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-folder-created-source-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)

    let ignoredID = await graphStore.materializeWorkflowFolderRoot(
        from: WorkflowEvent(
            kind: .folderCreated,
            hostID: HostID(rawValue: "local"),
            threadID: "unmapped-thread",
            method: "folder/created",
            summary: "Created folder",
            childHostID: HostID(rawValue: "local"),
            childFolderPath: "/Users/example/projects/unmapped",
            childTitle: "unmapped"
        )
    )
    #expect(ignoredID == nil)
    #expect(graphStore.graph.nodes.values.contains { $0.kind == .folder } == false)

    let sourceRef = ThreadRef(
        hostID: HostID(rawValue: "local"),
        threadID: "source-thread",
        cwd: "/Users/example/projects/current",
        name: "Source"
    )
    await graphStore.addThreadNode(
        threadRef: sourceRef,
        model: "gpt-5.5",
        reasoningEffort: "low",
        title: "Source"
    )

    let folderID = try #require(
        await graphStore.materializeWorkflowFolderRoot(
            from: WorkflowEvent(
                kind: .folderCreated,
                hostID: sourceRef.hostID,
                threadID: sourceRef.threadID,
                method: "folder/created",
                summary: "Created folder",
                childHostID: sourceRef.hostID,
                childFolderPath: "/Users/example/projects/mapped",
                childTitle: "mapped"
            )
        )
    )
    let folder = try #require(graphStore.graph.nodes[folderID])
    #expect(folder.kind == .folder)
    #expect(folder.title == "mapped")
    #expect(folder.metadata.folderPath == "/Users/example/projects/mapped")
    #expect(folder.metadata.hostID == sourceRef.hostID)

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func autoArrangePlacesProjectThreadsAfterFoldersAndScratchThreadsAfterMachine() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-arrange-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)

    let hostID = HostID(rawValue: "host-a")
    let machine = CanvasNode(
        id: NodeID(rawValue: "machine"),
        kind: .machine,
        title: "Machine",
        position: CanvasPoint(x: 900, y: 900),
        size: .machine,
        metadata: NodeMetadata(hostID: hostID)
    )
    let folder = CanvasNode(
        id: NodeID(rawValue: "folder"),
        kind: .folder,
        title: "Project",
        position: CanvasPoint(x: 20, y: 20),
        size: .folder,
        metadata: NodeMetadata(hostID: hostID, folderPath: "/tmp/project")
    )
    let projectThread = CanvasNode(
        id: NodeID(rawValue: "project-thread"),
        kind: .codexThread,
        title: "Project Thread",
        position: CanvasPoint(x: 30, y: 30),
        size: .thread,
        metadata: NodeMetadata(threadRef: ThreadRef(hostID: hostID, threadID: "project", cwd: "/tmp/project/Sources"))
    )
    let scratchThread = CanvasNode(
        id: NodeID(rawValue: "scratch-thread"),
        kind: .codexThread,
        title: "Scratch Thread",
        position: CanvasPoint(x: 40, y: 40),
        size: .thread,
        metadata: NodeMetadata(threadRef: ThreadRef(hostID: hostID, threadID: "scratch", cwd: "/tmp/scratch"))
    )

    var graph = AgentGraph()
    graph.upsertNode(machine)
    graph.upsertNode(folder)
    graph.upsertNode(projectThread)
    graph.upsertNode(scratchThread)
    _ = try await store.applyCanvasPatch(.replace(graph))
    await graphStore.load()
    await graphStore.autoArrange()

    let arrangedMachine = try #require(graphStore.graph.nodes[machine.id])
    let arrangedFolder = try #require(graphStore.graph.nodes[folder.id])
    let arrangedProjectThread = try #require(graphStore.graph.nodes[projectThread.id])
    let arrangedScratchThread = try #require(graphStore.graph.nodes[scratchThread.id])

    #expect(arrangedFolder.position.y > arrangedMachine.position.y)
    #expect(arrangedProjectThread.position.y > arrangedFolder.position.y)
    #expect(arrangedScratchThread.position.y > arrangedFolder.position.y)
    #expect(arrangedMachine.metadata.hasManualPosition == true)
    #expect(arrangedFolder.metadata.hasManualPosition == true)
    #expect(arrangedProjectThread.metadata.hasManualPosition == true)

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func autoArrangePlacesProjectThreadsInThreeColumnsWithSubagentsBelow() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-arrange-thread-columns-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)
    let hostID = HostID(rawValue: "host-a")
    let folderPath = "/tmp/project"
    let machine = CanvasNode(
        id: NodeID(rawValue: "machine"),
        kind: .machine,
        title: "Machine",
        position: CanvasPoint(x: 0, y: 0),
        size: .machine,
        metadata: NodeMetadata(hostID: hostID)
    )
    let folder = CanvasNode(
        id: NodeID(rawValue: "folder"),
        kind: .folder,
        title: "Project",
        position: CanvasPoint(x: 0, y: 0),
        size: .folder,
        metadata: NodeMetadata(hostID: hostID, folderPath: folderPath)
    )
    let regularThreads = (0..<4).map { index in
        CanvasNode(
            id: NodeID(rawValue: "thread-\(index)"),
            kind: .codexThread,
            title: "Thread \(index)",
            position: CanvasPoint(x: 0, y: 0),
            size: .thread,
            metadata: NodeMetadata(
                threadRef: ThreadRef(hostID: hostID, threadID: "thread-\(index)", cwd: "\(folderPath)/worker-\(index)"),
                threadKind: .thread
            )
        )
    }
    let subagents = (0..<2).map { index in
        CanvasNode(
            id: NodeID(rawValue: "subagent-\(index)"),
            kind: .codexThread,
            title: "Subagent \(index)",
            position: CanvasPoint(x: 0, y: 0),
            size: .thread,
            metadata: NodeMetadata(
                threadRef: ThreadRef(hostID: hostID, threadID: "subagent-\(index)", cwd: "\(folderPath)/agent-\(index)"),
                threadKind: .subagent
            )
        )
    }

    var graph = AgentGraph()
    graph.upsertNode(machine)
    graph.upsertNode(folder)
    for node in regularThreads + subagents {
        graph.upsertNode(node)
    }
    _ = try await store.applyCanvasPatch(.replace(graph))
    await graphStore.load()
    await graphStore.autoArrange()

    let arrangedRegulars = try regularThreads.map { thread in
        try #require(graphStore.graph.nodes[thread.id])
    }
    let arrangedSubagents = try subagents.map { thread in
        try #require(graphStore.graph.nodes[thread.id])
    }

    #expect(Set(arrangedRegulars.prefix(3).map(\.position.y)).count == 1)
    #expect(Set(arrangedRegulars.prefix(3).map(\.position.x)).count == 3)
    #expect(arrangedRegulars[3].position.x == arrangedRegulars[0].position.x)
    #expect(arrangedRegulars[3].position.y > arrangedRegulars[0].position.y)
    #expect(arrangedSubagents.allSatisfy { $0.position.y > arrangedRegulars[3].position.y })
    #expect(Set(arrangedSubagents.map(\.position.y)).count == 1)

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func autoArrangeScalesThreadColumnSpacingWithAvailableWidth() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-arrange-width-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)
    let hostID = HostID(rawValue: "host-a")
    let folderPath = "/tmp/project"
    let machine = CanvasNode(
        id: NodeID(rawValue: "machine"),
        kind: .machine,
        title: "Machine",
        position: CanvasPoint(x: 0, y: 0),
        size: .machine,
        metadata: NodeMetadata(hostID: hostID)
    )
    let folder = CanvasNode(
        id: NodeID(rawValue: "folder"),
        kind: .folder,
        title: "Project",
        position: CanvasPoint(x: 0, y: 0),
        size: .folder,
        metadata: NodeMetadata(hostID: hostID, folderPath: folderPath)
    )
    let threads = (0..<3).map { index in
        CanvasNode(
            id: NodeID(rawValue: "thread-\(index)"),
            kind: .codexThread,
            title: "Thread \(index)",
            position: CanvasPoint(x: 0, y: 0),
            size: .thread,
            metadata: NodeMetadata(
                threadRef: ThreadRef(hostID: hostID, threadID: "thread-\(index)", cwd: "\(folderPath)/worker-\(index)"),
                threadKind: .thread
            )
        )
    }

    var graph = AgentGraph()
    graph.upsertNode(machine)
    graph.upsertNode(folder)
    for node in threads {
        graph.upsertNode(node)
    }
    _ = try await store.applyCanvasPatch(.replace(graph))
    await graphStore.load()

    await graphStore.autoArrange(availableWidth: 980)
    let narrowThreads = try threads.map { thread in
        try #require(graphStore.graph.nodes[thread.id])
    }
    let narrowSpacing = narrowThreads[1].position.x - narrowThreads[0].position.x

    await graphStore.autoArrange(availableWidth: 1_900)
    let wideThreads = try threads.map { thread in
        try #require(graphStore.graph.nodes[thread.id])
    }
    let wideSpacing = wideThreads[1].position.x - wideThreads[0].position.x

    #expect(wideSpacing > narrowSpacing)
    #expect(wideThreads[2].position.x - wideThreads[0].position.x > narrowThreads[2].position.x - narrowThreads[0].position.x)

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func newFoldersAndThreadsSpawnInZoneNearCurrentMachineAndFolderPositions() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-zone-placement-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)
    let hostID = HostID(rawValue: "host-a")
    let machine = CanvasNode(
        id: NodeID(rawValue: "machine"),
        kind: .machine,
        title: "Machine",
        position: CanvasPoint(x: 90, y: 80),
        size: .machine,
        metadata: NodeMetadata(hostID: hostID)
    )

    var graph = AgentGraph()
    graph.upsertNode(machine)
    _ = try await store.applyCanvasPatch(.replace(graph))
    await graphStore.load()
    await graphStore.moveNode(id: machine.id, to: CanvasPoint(x: 500, y: 180))
    await graphStore.addFolder(path: "/tmp/project", hostID: hostID)

    let folder = try #require(graphStore.graph.nodes.values.first { $0.kind == .folder })
    #expect(folder.position.y > 300)
    #expect(folder.position.x > 650)
    #expect(folder.metadata.hasManualPosition == false)

    await graphStore.moveNode(id: folder.id, to: CanvasPoint(x: 260, y: 420))
    await graphStore.addThreadNode(
        threadRef: ThreadRef(hostID: hostID, threadID: "thread-a", cwd: "/tmp/project"),
        model: "gpt-5.5",
        reasoningEffort: "high",
        anchorFolderID: folder.id
    )

    let thread = try #require(graphStore.graph.nodes.values.first { $0.kind == .codexThread })
    #expect(thread.position.y > 600)
    #expect(abs(thread.position.x - 260) < 260)
    #expect(thread.metadata.hasManualPosition == false)

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func viewportUpdatesClampScaleAndPersistOffset() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-viewport-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)

    await graphStore.load()
    await graphStore.updateViewport(CanvasViewport(scale: 9, offset: CanvasPoint(x: 12, y: 18)))
    #expect(graphStore.graph.viewport.scale == 1.8)
    #expect(graphStore.graph.viewport.offset == CanvasPoint(x: 12, y: 18))

    await graphStore.panViewport(dx: 8, dy: -3)
    #expect(graphStore.graph.viewport.offset == CanvasPoint(x: 20, y: 15))

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func supervisorMachinesCreateAndUpdateMachineNodes() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-machine-node-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)
    let machine = SupervisorMachine(
        id: HostID(rawValue: "remote-a"),
        name: "Remote A",
        endpointDescription: "ws://127.0.0.1:18945",
        status: .connecting,
        platform: .linux
    )

    await graphStore.applySupervisorMachine(machine)
    let node = try #require(graphStore.graph.nodes.values.first { $0.metadata.hostID == machine.id })

    #expect(node.kind == .machine)
    #expect(node.title == "Remote A")
    #expect(node.metadata.hostStatus == .connecting)
    #expect(node.metadata.platform == .linux)

    await graphStore.applySupervisorMachine(
        SupervisorMachine(
            id: machine.id,
            name: "Remote A",
            endpointDescription: "ws://127.0.0.1:18945",
            status: .connected,
            platform: .linux
        )
    )

    #expect(graphStore.graph.nodes.values.filter { $0.metadata.hostID == machine.id }.count == 1)
    #expect(graphStore.graph.nodes[node.id]?.metadata.hostStatus == .connected)

    await graphStore.applySupervisorMachines([])
    #expect(graphStore.graph.nodes[node.id]?.metadata.hostStatus == .disconnected)

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func supervisorMachineSnapshotsDoNotDowngradeLocalHost() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-local-host-snapshot-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)
    let localHost = AgentHost(
        id: HostID(rawValue: "local"),
        name: "This Mac",
        platform: .macOS,
        endpointDescription: "daemon proxy",
        status: .connected
    )

    await graphStore.applyHost(localHost)
    let localNodeID = try #require(graphStore.graph.nodes.values.first { $0.metadata.hostID == localHost.id }?.id)

    await graphStore.applySupervisorMachines([
        SupervisorMachine(
            id: localHost.id,
            name: "This Mac",
            endpointDescription: "stale failure",
            status: .failed,
            platform: .macOS,
            lastError: "stale failure"
        ),
    ])

    #expect(graphStore.graph.nodes[localNodeID]?.metadata.hostStatus == .connected)
    #expect(graphStore.graph.nodes[localNodeID]?.subtitle == "macOS - daemon proxy")

    await graphStore.applySupervisorMachines([])
    #expect(graphStore.graph.nodes[localNodeID]?.metadata.hostStatus == .connected)

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func supervisorMachineSnapshotsPlaceNewMachinesFromInProgressGraph() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-machine-batch-layout-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)
    let first = SupervisorMachine(
        id: HostID(rawValue: "remote-a"),
        name: "Remote A",
        endpointDescription: "ws://remote-a:18945",
        status: .connected,
        platform: .linux
    )
    let second = SupervisorMachine(
        id: HostID(rawValue: "remote-b"),
        name: "Remote B",
        endpointDescription: "ws://remote-b:18945",
        status: .connected,
        platform: .linux
    )

    await graphStore.applySupervisorMachines([first, second])

    let nodes = [first.id, second.id].compactMap { hostID in
        graphStore.graph.nodes.values.first { $0.metadata.hostID == hostID }
    }
    #expect(nodes.count == 2)
    #expect(Set(nodes.map(\.position)).count == 2)
    #expect(Set(nodes.map(\.zIndex)).count == 2)

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func addFolderSupportsRemoteWindowsPaths() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-windows-folder-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)
    let hostID = HostID(rawValue: "windows-a")

    await graphStore.addFolder(path: #"C:\Users\User\mapofagents"#, hostID: hostID, platform: .windows)

    let folder = try #require(graphStore.graph.nodes.values.first { $0.kind == .folder })
    #expect(folder.title == "mapofagents")
    #expect(folder.subtitle == #"C:\Users\User\mapofagents"#)
    #expect(folder.metadata.hostID == hostID)
    #expect(folder.metadata.platform == .windows)

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func graphStoreResetsRunningThreadStatusOnLoad() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-running-status-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)

    let runningThread = CanvasNode(
        id: NodeID(rawValue: "running"),
        kind: .codexThread,
        title: "Running",
        position: CanvasPoint(x: 0, y: 0),
        size: .thread,
        metadata: NodeMetadata(runStatus: .running)
    )
    let failedThread = CanvasNode(
        id: NodeID(rawValue: "failed"),
        kind: .codexThread,
        title: "Failed",
        position: CanvasPoint(x: 220, y: 0),
        size: .thread,
        metadata: NodeMetadata(runStatus: .failed)
    )

    var graph = AgentGraph()
    graph.upsertNode(runningThread)
    graph.upsertNode(failedThread)
    _ = try await store.applyCanvasPatch(.replace(graph))

    await graphStore.load()

    #expect(graphStore.graph.nodes[NodeID(rawValue: "running")]?.metadata.runStatus == .idle)
    #expect(graphStore.graph.nodes[NodeID(rawValue: "failed")]?.metadata.runStatus == .failed)

    let persistedGraph = try await store.loadCanvas()
    #expect(persistedGraph.nodes[NodeID(rawValue: "running")]?.metadata.runStatus == .idle)

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func workflowEventsUpdateThreadNodeStatus() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-workflow-event-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)
    let threadRef = ThreadRef(
        hostID: HostID(rawValue: "local"),
        threadID: "thread-1",
        cwd: "/tmp/project",
        name: "Worker"
    )

    await graphStore.addThreadNode(
        threadRef: threadRef,
        model: "gpt-5.5",
        reasoningEffort: "high"
    )
    let threadNodeID = try #require(graphStore.selectedNode?.id)

    await graphStore.applyWorkflowEvent(
        WorkflowEvent(
            kind: .turnStarted,
            threadID: threadRef.threadID,
            method: "turn/started",
            summary: "Turn started"
        )
    )
    #expect(graphStore.graph.nodes[threadNodeID]?.metadata.runStatus == .running)

    await graphStore.applyWorkflowEvent(
        WorkflowEvent(
            kind: .turnCompleted,
            threadID: threadRef.threadID,
            method: "turn/completed",
            summary: "Turn completed"
        )
    )
    #expect(graphStore.graph.nodes[threadNodeID]?.metadata.runStatus == .complete)

    await graphStore.applyWorkflowEvent(
        WorkflowEvent(
            kind: .needsInput,
            threadID: threadRef.threadID,
            method: "requestApproval",
            summary: "Needs approval"
        )
    )
    #expect(graphStore.graph.nodes[threadNodeID]?.metadata.runStatus == .needsInput)

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func workflowEventsMatchThreadByHostAndThreadID() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-host-qualified-event-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)
    let localRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp/local")
    let remoteRef = ThreadRef(hostID: HostID(rawValue: "remote"), threadID: "thread-1", cwd: "/tmp/remote")

    await graphStore.addThreadNode(threadRef: localRef, model: "gpt-5.5", reasoningEffort: "low")
    let localNodeID = try #require(graphStore.selectedNode?.id)
    await graphStore.addThreadNode(threadRef: remoteRef, model: "gpt-5.5", reasoningEffort: "low")
    let remoteNodeID = try #require(graphStore.selectedNode?.id)

    await graphStore.applyWorkflowEvent(
        WorkflowEvent(
            kind: .turnStarted,
            hostID: remoteRef.hostID,
            threadID: remoteRef.threadID,
            method: "turn/started",
            summary: "Turn started"
        )
    )

    #expect(graphStore.graph.nodes[localNodeID]?.metadata.runStatus == .idle)
    #expect(graphStore.graph.nodes[remoteNodeID]?.metadata.runStatus == .running)

    graphStore.selectThread(remoteRef)
    #expect(graphStore.selectedNode?.id == remoteNodeID)

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func hostlessWorkflowEventsSkipAmbiguousDuplicateThreadIDs() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-hostless-duplicate-event-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)
    let localRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "shared-thread", cwd: "/tmp/local")
    let remoteRef = ThreadRef(hostID: HostID(rawValue: "remote"), threadID: "shared-thread", cwd: "/tmp/remote")

    await graphStore.addThreadNode(threadRef: localRef, model: "gpt-5.5", reasoningEffort: "low")
    let localNodeID = try #require(graphStore.selectedNode?.id)
    await graphStore.addThreadNode(threadRef: remoteRef, model: "gpt-5.5", reasoningEffort: "low")
    let remoteNodeID = try #require(graphStore.selectedNode?.id)

    await graphStore.applyWorkflowEvent(
        WorkflowEvent(
            kind: .turnStarted,
            threadID: "shared-thread",
            method: "turn/started",
            summary: "Turn started"
        )
    )

    #expect(graphStore.graph.nodes[localNodeID]?.metadata.runStatus == .idle)
    #expect(graphStore.graph.nodes[remoteNodeID]?.metadata.runStatus == .idle)
    #expect(graphStore.errorMessage?.contains("Ambiguous hostless workflow event") == true)

    await graphStore.applyWorkflowEvent(
        WorkflowEvent(
            kind: .turnStarted,
            hostID: remoteRef.hostID,
            threadID: remoteRef.threadID,
            method: "turn/started",
            summary: "Turn started"
        )
    )

    #expect(graphStore.graph.nodes[localNodeID]?.metadata.runStatus == .idle)
    #expect(graphStore.graph.nodes[remoteNodeID]?.metadata.runStatus == .running)

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func graphStoreExposesWorkflowThreadRefs() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-thread-ref-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)
    let hostID = HostID(rawValue: "remote-a")
    let threadRef = ThreadRef(
        hostID: hostID,
        threadID: "thread-1",
        cwd: "/tmp/project",
        name: "Worker"
    )

    var graph = AgentGraph()
    graph.upsertNode(
        CanvasNode(
            id: NodeID(rawValue: "folder"),
            kind: .folder,
            title: "Project",
            position: CanvasPoint(x: 0, y: 0),
            size: .folder,
            metadata: NodeMetadata(hostID: hostID, folderPath: "/tmp/project")
        )
    )
    graph.upsertNode(
        CanvasNode(
            id: NodeID(rawValue: "thread"),
            kind: .codexThread,
            title: "Worker",
            position: CanvasPoint(x: 200, y: 0),
            size: .thread,
            metadata: NodeMetadata(threadRef: threadRef)
        )
    )

    _ = try await store.applyCanvasPatch(.replace(graph))
    await graphStore.load()

    #expect(graphStore.workflowThreadRefs == [threadRef])

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func graphStoreExposesWorkflowThreadMentionCandidates() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-thread-mention-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)
    let firstRef = ThreadRef(
        hostID: HostID(rawValue: "local host"),
        threadID: "thread/one",
        cwd: "/tmp/project",
        name: "Placement"
    )
    let secondRef = ThreadRef(
        hostID: HostID(rawValue: "local host"),
        threadID: "thread-two",
        cwd: "/tmp/project",
        name: "Tester"
    )

    var graph = AgentGraph()
    graph.upsertNode(
        CanvasNode(
            id: NodeID(rawValue: "first"),
            kind: .codexThread,
            title: "placement test",
            position: CanvasPoint(x: 0, y: 0),
            size: .thread,
            metadata: NodeMetadata(threadRef: firstRef)
        )
    )
    graph.upsertNode(
        CanvasNode(
            id: NodeID(rawValue: "second"),
            kind: .codexThread,
            title: "testertest",
            position: CanvasPoint(x: 0, y: 0),
            size: .thread,
            metadata: NodeMetadata(threadRef: secondRef)
        )
    )

    _ = try await store.applyCanvasPatch(.replace(graph))
    await graphStore.load()

    let candidates = graphStore.workflowThreadMentionCandidates(excluding: firstRef)
    let candidate = try #require(candidates.first)

    #expect(candidates.count == 1)
    #expect(candidate.kind == .thread)
    #expect(candidate.trigger == "@")
    #expect(candidate.title == "testertest")
    #expect(candidate.insertionText == "[@\"testertest\" chat](codex-thread://local%20host/thread-two)")

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func graphStoreEscapesWorkflowMentionLabels() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-thread-mention-escape-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)
    let threadRef = ThreadRef(
        hostID: HostID(rawValue: "local"),
        threadID: "thread",
        cwd: "/tmp/project",
        name: "Worker"
    )

    var graph = AgentGraph()
    graph.upsertNode(
        CanvasNode(
            id: NodeID(rawValue: "thread"),
            kind: .codexThread,
            title: "x](codex-thread://other)\n[bad\"",
            position: CanvasPoint(x: 0, y: 0),
            size: .thread,
            metadata: NodeMetadata(threadRef: threadRef)
        )
    )

    _ = try await store.applyCanvasPatch(.replace(graph))
    await graphStore.load()

    let insertionText = try #require(graphStore.workflowThreadMentionCandidates().first?.insertionText)
    #expect(insertionText.contains("x\\](codex-thread://other) \\[bad\\\""))
    #expect(!insertionText.contains("\n"))

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func graphStoreExposesWorkflowFolderMentionCandidates() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-folder-mention-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let graphStore = GraphStore(repository: store)
    let hostID = HostID(rawValue: "windows host")

    var graph = AgentGraph()
    graph.upsertNode(
        CanvasNode(
            id: NodeID(rawValue: "windows-machine"),
            kind: .machine,
            title: "Windows Desktop",
            position: CanvasPoint(x: 0, y: 0),
            size: .machine,
            metadata: NodeMetadata(hostID: hostID, platform: .windows)
        )
    )
    graph.upsertNode(
        CanvasNode(
            id: NodeID(rawValue: "desktop-folder"),
            kind: .folder,
            title: "Desktop",
            subtitle: "C:\\Users\\User\\Desktop",
            position: CanvasPoint(x: 0, y: 0),
            size: .folder,
            metadata: NodeMetadata(
                hostID: hostID,
                platform: .windows,
                folderPath: "C:\\Users\\User\\Desktop"
            )
        )
    )

    _ = try await store.applyCanvasPatch(.replace(graph))
    await graphStore.load()

    let candidate = try #require(graphStore.workflowFolderMentionCandidates().first)

    #expect(candidate.kind == .folder)
    #expect(candidate.trigger == "@")
    #expect(candidate.title == "Desktop")
    #expect(candidate.subtitle.contains("Windows Desktop"))
    #expect(candidate.insertionText == "[@\"Desktop\" folder](mapofagents-folder://windows%20host/desktop-folder)")

    try? FileManager.default.removeItem(at: directory)
}

@Test
@MainActor
func graphStoreRecordsAndPropagatesPersistenceFailures() async {
    let repository = FailingGraphControlRoomStore()
    let graphStore = GraphStore(repository: repository)
    let node = CanvasNode(
        id: NodeID(rawValue: "unsaved"),
        kind: .folder,
        title: "Unsaved",
        position: CanvasPoint(x: 0, y: 0),
        size: .folder
    )

    var propagatedFailure = false
    do {
        _ = try await graphStore.applyCanvasPatch(.upsertNode(node))
    } catch GraphStorePersistenceTestError.writeFailed {
        propagatedFailure = true
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(propagatedFailure)
    #expect(graphStore.lastPersistenceFailure?.operation == "save node")
    #expect(graphStore.persistenceFailureRevision == 1)
    #expect(graphStore.errorMessage?.isEmpty == false)

    await graphStore.addFolder(path: "/tmp/also-unsaved")
    #expect(graphStore.persistenceFailureRevision == 2)
    #expect(graphStore.lastPersistenceFailure?.operation == "save node")
}

private enum GraphStorePersistenceTestError: Error {
    case writeFailed
}

private actor FailingGraphControlRoomStore: ControlRoomStore {
    func loadCanvas() async throws -> AgentGraph { AgentGraph() }

    func applyCanvasPatch(_ patch: CanvasPatch) async throws -> AgentGraph {
        throw GraphStorePersistenceTestError.writeFailed
    }

    func loadWorkflowEvents() async throws -> [WorkflowEvent] { [] }
    func saveWorkflowEvents(_ events: [WorkflowEvent]) async throws {}
    func loadRelayEndpoints() async throws -> [AppServerRelayEndpoint] { [] }
    func saveRelayEndpoints(_ endpoints: [AppServerRelayEndpoint]) async throws {}
    func loadTranscript(for threadRef: ThreadRef) async throws -> ThreadTranscript? { nil }
    func saveTranscript(_ transcript: ThreadTranscript) async throws {}
}
