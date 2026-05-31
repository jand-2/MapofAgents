import Testing
@testable import MapofAgentsCore

@Test
func defaultCWDUsesCodexHomeParent() {
    let machine = CanvasNode(
        kind: .machine,
        title: "Mac",
        position: CanvasPoint(x: 0, y: 0),
        size: .machine,
        metadata: NodeMetadata(
            hostID: HostID(rawValue: "remote"),
            platform: .macOS,
            codexHome: "/Users/test/.codex"
        )
    )

    #expect(ThreadDefaultCWDResolver.defaultCWD(
        for: machine,
        localHostID: HostID(rawValue: "local"),
        localDefaultDirectory: "/Users/local"
    ) == "/Users/test")
}

@Test
func defaultCWDUsesLocalDefaultWhenLocalMachineHasNoCodexHome() {
    let localHostID = HostID(rawValue: "local")
    let machine = CanvasNode(
        kind: .machine,
        title: "Local",
        position: CanvasPoint(x: 0, y: 0),
        size: .machine,
        metadata: NodeMetadata(
            hostID: localHostID,
            platform: .macOS
        )
    )

    #expect(ThreadDefaultCWDResolver.defaultCWD(
        for: machine,
        localHostID: localHostID,
        localDefaultDirectory: "/Users/local"
    ) == "/Users/local")
}

@Test
func defaultCWDUsesPlatformFallbackForRemoteMachinesWithoutCodexHome() {
    let windows = CanvasNode(
        kind: .machine,
        title: "Windows",
        position: CanvasPoint(x: 0, y: 0),
        size: .machine,
        metadata: NodeMetadata(
            hostID: HostID(rawValue: "windows"),
            platform: .windows
        )
    )
    let linux = CanvasNode(
        kind: .machine,
        title: "Linux",
        position: CanvasPoint(x: 0, y: 0),
        size: .machine,
        metadata: NodeMetadata(
            hostID: HostID(rawValue: "linux"),
            platform: .linux
        )
    )

    #expect(ThreadDefaultCWDResolver.defaultCWD(
        for: windows,
        localHostID: HostID(rawValue: "local")
    ) == #"C:\Users\User"#)
    #expect(ThreadDefaultCWDResolver.defaultCWD(
        for: linux,
        localHostID: HostID(rawValue: "local")
    ) == nil)
}

@Test
func defaultCWDDoesNotUseRootCodexHomeParent() {
    let machine = CanvasNode(
        kind: .machine,
        title: "Remote",
        position: CanvasPoint(x: 0, y: 0),
        size: .machine,
        metadata: NodeMetadata(
            hostID: HostID(rawValue: "remote"),
            platform: .linux,
            codexHome: "/.codex"
        )
    )

    #expect(ThreadDefaultCWDResolver.defaultCWD(
        for: machine,
        localHostID: HostID(rawValue: "local")
    ) == nil)
}

@Test
func workflowThreadContentSignatureIgnoresViewportAndPlacement() {
    let threadID = NodeID(rawValue: "thread")
    let ref = ThreadRef(
        hostID: HostID(rawValue: "host"),
        threadID: "thread-1",
        cwd: "/tmp/project",
        name: "Worker"
    )
    var graph = AgentGraph()
    graph.upsertNode(
        CanvasNode(
            id: threadID,
            kind: .codexThread,
            title: "Worker",
            position: CanvasPoint(x: 100, y: 100),
            size: .thread,
            metadata: NodeMetadata(threadRef: ref)
        )
    )

    let signature = graph.workflowThreadContentSignature
    graph.updateViewport(CanvasViewport(scale: 1.4, offset: CanvasPoint(x: 40, y: 60)))
    #expect(graph.workflowThreadContentSignature == signature)

    graph.updateNodePosition(id: threadID, position: CanvasPoint(x: 240, y: 320))
    #expect(graph.workflowThreadContentSignature == signature)

    var node = graph.nodes[threadID]!
    node.metadata.threadRef = ThreadRef(
        hostID: ref.hostID,
        threadID: ref.threadID,
        cwd: "/tmp/other",
        name: ref.name
    )
    graph.nodes[threadID] = node
    #expect(graph.workflowThreadContentSignature != signature)
}
