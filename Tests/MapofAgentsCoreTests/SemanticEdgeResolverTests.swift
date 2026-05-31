import Testing
@testable import MapofAgentsCore

@Test
func resolvesMachineFolderAndFolderThreadEdges() {
    let hostID = HostID(rawValue: "host-a")
    let machine = CanvasNode(
        id: NodeID(rawValue: "machine"),
        kind: .machine,
        title: "Machine",
        position: CanvasPoint(x: 0, y: 0),
        size: .machine,
        metadata: NodeMetadata(hostID: hostID, platform: .macOS, hostStatus: .connected)
    )
    let folder = CanvasNode(
        id: NodeID(rawValue: "folder"),
        kind: .folder,
        title: "Project",
        position: CanvasPoint(x: 120, y: 0),
        size: .folder,
        metadata: NodeMetadata(hostID: hostID, folderPath: "/Users/example/project")
    )
    let thread = CanvasNode(
        id: NodeID(rawValue: "thread"),
        kind: .codexThread,
        title: "Thread",
        position: CanvasPoint(x: 240, y: 0),
        size: .thread,
        metadata: NodeMetadata(
            hostID: hostID,
            threadRef: ThreadRef(
                hostID: hostID,
                threadID: "thread-1",
                cwd: "/Users/example/project/Sources"
            )
        )
    )

    var graph = AgentGraph()
    graph.upsertNode(machine)
    graph.upsertNode(folder)
    graph.upsertNode(thread)

    let edges = DefaultSemanticEdgeResolver().resolveEdges(in: graph)
    #expect(edges.contains { $0.kind == .machineFolder && $0.source == machine.id && $0.target == folder.id })
    #expect(edges.contains { $0.kind == .folderThread && $0.source == folder.id && $0.target == thread.id })
    #expect(!edges.contains { $0.kind == .machineThread && $0.source == machine.id && $0.target == thread.id })
}

@Test
func resolvesWindowsFolderAndThreadEdges() {
    let hostID = HostID(rawValue: "windows-a")
    let machine = CanvasNode(
        id: NodeID(rawValue: "machine"),
        kind: .machine,
        title: "Windows",
        position: CanvasPoint(x: 0, y: 0),
        size: .machine,
        metadata: NodeMetadata(hostID: hostID, platform: .windows, hostStatus: .connected)
    )
    let folder = CanvasNode(
        id: NodeID(rawValue: "folder"),
        kind: .folder,
        title: "mapofagents",
        position: CanvasPoint(x: 120, y: 0),
        size: .folder,
        metadata: NodeMetadata(hostID: hostID, platform: .windows, folderPath: #"C:\Users\User\mapofagents"#)
    )
    let thread = CanvasNode(
        id: NodeID(rawValue: "thread"),
        kind: .codexThread,
        title: "Thread",
        position: CanvasPoint(x: 240, y: 0),
        size: .thread,
        metadata: NodeMetadata(
            hostID: hostID,
            platform: .windows,
            threadRef: ThreadRef(
                hostID: hostID,
                threadID: "thread-1",
                cwd: #"C:\Users\User\mapofagents\src"#
            )
        )
    )

    var graph = AgentGraph()
    graph.upsertNode(machine)
    graph.upsertNode(folder)
    graph.upsertNode(thread)

    let edges = DefaultSemanticEdgeResolver().resolveEdges(in: graph)
    #expect(edges.contains { $0.kind == .machineFolder && $0.source == machine.id && $0.target == folder.id })
    #expect(edges.contains { $0.kind == .folderThread && $0.source == folder.id && $0.target == thread.id })
    #expect(!edges.contains { $0.kind == .machineThread && $0.source == machine.id && $0.target == thread.id })
}

@Test
func resolvesMachineThreadEdgeOnlyWhenNoFolderOwnsThread() {
    let hostID = HostID(rawValue: "host-a")
    let machine = CanvasNode(
        id: NodeID(rawValue: "machine"),
        kind: .machine,
        title: "Machine",
        position: CanvasPoint(x: 0, y: 0),
        size: .machine,
        metadata: NodeMetadata(hostID: hostID, platform: .macOS, hostStatus: .connected)
    )
    let folder = CanvasNode(
        id: NodeID(rawValue: "folder"),
        kind: .folder,
        title: "Project",
        position: CanvasPoint(x: 120, y: 0),
        size: .folder,
        metadata: NodeMetadata(hostID: hostID, folderPath: "/Users/example/project")
    )
    let nonProjectThread = CanvasNode(
        id: NodeID(rawValue: "thread"),
        kind: .codexThread,
        title: "Scratch Thread",
        position: CanvasPoint(x: 240, y: 0),
        size: .thread,
        metadata: NodeMetadata(
            hostID: hostID,
            threadRef: ThreadRef(
                hostID: hostID,
                threadID: "thread-1",
                cwd: "/Users/example/Downloads"
            )
        )
    )

    var graph = AgentGraph()
    graph.upsertNode(machine)
    graph.upsertNode(folder)
    graph.upsertNode(nonProjectThread)

    let edges = DefaultSemanticEdgeResolver().resolveEdges(in: graph)
    #expect(edges.contains { $0.kind == .machineFolder && $0.source == machine.id && $0.target == folder.id })
    #expect(edges.contains { $0.kind == .machineThread && $0.source == machine.id && $0.target == nonProjectThread.id })
    #expect(!edges.contains { $0.kind == .folderThread && $0.source == folder.id && $0.target == nonProjectThread.id })
}

@Test
func subagentThreadsDoNotReceiveSemanticParentEdges() {
    let hostID = HostID(rawValue: "host-a")
    let machine = semanticTestMachine(hostID: hostID)
    let folder = semanticTestFolder(
        id: NodeID(rawValue: "folder"),
        hostID: hostID,
        path: "/Users/example/project"
    )
    let subagent = semanticTestThread(
        id: NodeID(rawValue: "subagent"),
        hostID: hostID,
        threadID: "subagent-1",
        cwd: "/Users/example/project/worker",
        threadKind: .subagent
    )

    var graph = AgentGraph()
    graph.upsertNode(machine)
    graph.upsertNode(folder)
    graph.upsertNode(subagent)

    let edges = DefaultSemanticEdgeResolver().resolveEdges(in: graph)

    #expect(edges.contains { $0.kind == .machineFolder && $0.source == machine.id && $0.target == folder.id })
    #expect(!edges.contains { $0.kind == .folderThread && $0.target == subagent.id })
    #expect(!edges.contains { $0.kind == .machineThread && $0.target == subagent.id })
}

@Test
func resolvesOnlyNearestFolderThreadEdgeForNestedFolders() {
    let hostID = HostID(rawValue: "host-a")
    let machine = semanticTestMachine(hostID: hostID)
    let rootFolder = semanticTestFolder(
        id: NodeID(rawValue: "folder-root"),
        hostID: hostID,
        path: "/Users/example/project"
    )
    let nestedFolder = semanticTestFolder(
        id: NodeID(rawValue: "folder-nested"),
        hostID: hostID,
        path: "/Users/example/project/apps/api"
    )
    let thread = semanticTestThread(
        id: NodeID(rawValue: "thread"),
        hostID: hostID,
        threadID: "thread-1",
        cwd: "/Users/example/project/apps/api/Sources"
    )

    var graph = AgentGraph()
    graph.upsertNode(machine)
    graph.upsertNode(rootFolder)
    graph.upsertNode(nestedFolder)
    graph.upsertNode(thread)

    let edges = DefaultSemanticEdgeResolver().resolveEdges(in: graph)

    #expect(edges.contains { $0.kind == .machineFolder && $0.source == machine.id && $0.target == rootFolder.id })
    #expect(edges.contains { $0.kind == .machineFolder && $0.source == machine.id && $0.target == nestedFolder.id })
    #expect(edges.contains { $0.kind == .folderThread && $0.source == nestedFolder.id && $0.target == thread.id })
    #expect(!edges.contains { $0.kind == .folderThread && $0.source == rootFolder.id && $0.target == thread.id })
    #expect(!edges.contains { $0.kind == .machineThread && $0.source == machine.id && $0.target == thread.id })
}

@Test
func folderThreadEdgesDoNotMatchSiblingPathPrefixes() {
    let hostID = HostID(rawValue: "host-a")
    let machine = semanticTestMachine(hostID: hostID)
    let folder = semanticTestFolder(
        id: NodeID(rawValue: "folder"),
        hostID: hostID,
        path: "/Users/example/project/app"
    )
    let siblingThread = semanticTestThread(
        id: NodeID(rawValue: "thread"),
        hostID: hostID,
        threadID: "thread-1",
        cwd: "/Users/example/project/application"
    )

    var graph = AgentGraph()
    graph.upsertNode(machine)
    graph.upsertNode(folder)
    graph.upsertNode(siblingThread)

    let edges = DefaultSemanticEdgeResolver().resolveEdges(in: graph)

    #expect(!edges.contains { $0.kind == .folderThread && $0.source == folder.id && $0.target == siblingThread.id })
    #expect(edges.contains { $0.kind == .machineThread && $0.source == machine.id && $0.target == siblingThread.id })
}

@Test
func resolvesUncFolderThreadEdgesCaseInsensitivelyWithoutSiblingPrefixMatches() {
    let hostID = HostID(rawValue: "windows-a")
    let machine = semanticTestMachine(hostID: hostID, platform: .windows)
    let folder = semanticTestFolder(
        id: NodeID(rawValue: "folder"),
        hostID: hostID,
        platform: .windows,
        path: #"\\Server\Share\Project"#
    )
    let matchingThread = semanticTestThread(
        id: NodeID(rawValue: "matching-thread"),
        hostID: hostID,
        platform: .windows,
        threadID: "matching-thread",
        cwd: #"\\server\share\project\src"#
    )
    let siblingThread = semanticTestThread(
        id: NodeID(rawValue: "sibling-thread"),
        hostID: hostID,
        platform: .windows,
        threadID: "sibling-thread",
        cwd: #"\\server\share\project-old\src"#
    )

    var graph = AgentGraph()
    graph.upsertNode(machine)
    graph.upsertNode(folder)
    graph.upsertNode(matchingThread)
    graph.upsertNode(siblingThread)

    let edges = DefaultSemanticEdgeResolver().resolveEdges(in: graph)

    #expect(edges.contains { $0.kind == .folderThread && $0.source == folder.id && $0.target == matchingThread.id })
    #expect(!edges.contains { $0.kind == .folderThread && $0.source == folder.id && $0.target == siblingThread.id })
    #expect(edges.contains { $0.kind == .machineThread && $0.source == machine.id && $0.target == siblingThread.id })
}

private func semanticTestMachine(
    hostID: HostID,
    platform: HostPlatform = .macOS
) -> CanvasNode {
    CanvasNode(
        id: NodeID(rawValue: "machine"),
        kind: .machine,
        title: "Machine",
        position: CanvasPoint(x: 0, y: 0),
        size: .machine,
        metadata: NodeMetadata(hostID: hostID, platform: platform, hostStatus: .connected)
    )
}

private func semanticTestFolder(
    id: NodeID,
    hostID: HostID,
    platform: HostPlatform = .macOS,
    path: String
) -> CanvasNode {
    CanvasNode(
        id: id,
        kind: .folder,
        title: "Project",
        position: CanvasPoint(x: 120, y: 0),
        size: .folder,
        metadata: NodeMetadata(hostID: hostID, platform: platform, folderPath: path)
    )
}

private func semanticTestThread(
    id: NodeID,
    hostID: HostID,
    platform: HostPlatform = .macOS,
    threadID: String,
    cwd: String,
    threadKind: CodexThreadNodeKind? = nil
) -> CanvasNode {
    CanvasNode(
        id: id,
        kind: .codexThread,
        title: "Thread",
        position: CanvasPoint(x: 240, y: 0),
        size: .thread,
        metadata: NodeMetadata(
            hostID: hostID,
            platform: platform,
            threadRef: ThreadRef(hostID: hostID, threadID: threadID, cwd: cwd),
            threadKind: threadKind
        )
    )
}
