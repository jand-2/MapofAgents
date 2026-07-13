import Foundation
import MapofAgentsCore
import Testing
@testable import MapofAgentsUI

@MainActor
@Test
func transcriptSessionStoreSingleFlightsMatchingLoads() async {
    let store = TranscriptSessionStore()
    let threadRef = ThreadRef(
        hostID: HostID(rawValue: "example-host"),
        threadID: "thread-1",
        cwd: "/Users/example/project"
    )
    let probe = TranscriptLoaderProbe(
        transcript: ThreadTranscript(
            threadRef: threadRef,
            messages: [ThreadMessage(id: "message-1", role: .assistant, text: "Done")]
        )
    )

    let first = store.load(
        .popover,
        threadRef: threadRef,
        force: false,
        loader: { await probe.load() },
        errorMessage: { $0.localizedDescription }
    )
    let second = store.load(
        .popover,
        threadRef: threadRef,
        force: false,
        loader: { await probe.load() },
        errorMessage: { $0.localizedDescription }
    )

    await Task.yield()
    #expect(probe.callCount == 1)
    probe.finish()
    await first.value
    await second.value

    #expect(store.popover.transcript?.messages.map(\.id) == ["message-1"])
    #expect(store.popover.loadPhase == .idle)
    #expect(!store.popover.isLoading)
}

@MainActor
@Test
func transcriptSessionStoreRunsOnlyOneLiveRefreshPerThread() async {
    let store = TranscriptSessionStore()
    let threadRef = ThreadRef(
        hostID: HostID(rawValue: "example-host"),
        threadID: "thread-1",
        cwd: "/Users/example/project"
    )
    var refreshCount = 0
    var finishCount = 0

    let firstStarted = store.startLiveRefresh(
        for: threadRef,
        interval: .milliseconds(1),
        maximumIterations: 3,
        isOpen: { true },
        refresh: { refreshCount += 1 },
        shouldContinue: { false },
        onFinished: { finishCount += 1 }
    )
    let secondStarted = store.startLiveRefresh(
        for: threadRef,
        interval: .milliseconds(1),
        maximumIterations: 3,
        isOpen: { true },
        refresh: { refreshCount += 1 },
        shouldContinue: { false },
        onFinished: { finishCount += 1 }
    )

    #expect(firstStarted)
    #expect(!secondStarted)
    await store.waitForLiveRefresh(for: threadRef)
    #expect(refreshCount == 1)
    #expect(finishCount == 1)
    #expect(store.liveRefreshCount == 0)
}

@MainActor
@Test
func transcriptSessionStoreSerializesPrimaryOlderAndLiveLoads() async {
    let store = TranscriptSessionStore()
    let threadRef = ThreadRef(
        hostID: HostID(rawValue: "example-host"),
        threadID: "thread-serial",
        cwd: "/Users/example/project"
    )
    let current = ThreadTranscript(
        threadRef: threadRef,
        messages: [ThreadMessage(id: "current", role: .assistant, text: "Current")],
        nextCursor: "older-cursor"
    )
    store.merge(current, into: .popover)

    let primaryProbe = TranscriptLoaderProbe(transcript: current)
    let primary = store.load(
        .popover,
        threadRef: threadRef,
        force: true,
        loader: { await primaryProbe.load() },
        errorMessage: { $0.localizedDescription }
    )
    await Task.yield()
    var olderCallCount = 0
    let blockedOlder = store.loadOlder(
        .popover,
        threadRef: threadRef,
        loader: { _ in
            olderCallCount += 1
            return current
        },
        errorMessage: { $0.localizedDescription }
    )

    #expect(blockedOlder == nil)
    #expect(olderCallCount == 0)
    primaryProbe.finish()
    await primary.value

    let olderProbe = TranscriptLoaderProbe(
        transcript: ThreadTranscript(
            threadRef: threadRef,
            messages: [ThreadMessage(id: "older", role: .assistant, text: "Older")]
        )
    )
    let olderTask = store.loadOlder(
        .popover,
        threadRef: threadRef,
        loader: { _ in await olderProbe.load() },
        errorMessage: { $0.localizedDescription }
    )
    guard let older = olderTask else {
        Issue.record("Expected the older-page load to start")
        return
    }
    await Task.yield()
    #expect(store.popover.isLoadingOlder)

    let replacement = store.load(
        .popover,
        threadRef: threadRef,
        force: true,
        loader: { current },
        errorMessage: { $0.localizedDescription }
    )
    await replacement.value
    olderProbe.finish()
    await older.value

    #expect(store.popover.transcript?.messages.map(\.id) == ["current"])
    #expect(!store.popover.isLoading)
    #expect(!store.popover.isLoadingOlder)
    #expect(store.popover.loadPhase == .idle)
}

@Test
func canvasPresentationFiltersOnceAndBuildsFocusedNeighborhood() {
    let machineID = NodeID(rawValue: "machine")
    let threadID = NodeID(rawValue: "thread")
    let subagentID = NodeID(rawValue: "subagent")
    let size = CanvasSize(width: 200, height: 100)
    let machine = CanvasNode(
        id: machineID,
        kind: .machine,
        title: "Machine",
        position: .zero,
        size: size
    )
    let thread = CanvasNode(
        id: threadID,
        kind: .codexThread,
        title: "Thread",
        position: CanvasPoint(x: 250, y: 0),
        size: size
    )
    let subagent = CanvasNode(
        id: subagentID,
        kind: .codexThread,
        title: "Subagent",
        position: CanvasPoint(x: 500, y: 0),
        size: size,
        metadata: NodeMetadata(threadKind: .subagent)
    )
    let visibleEdge = CanvasEdge(
        id: EdgeID(rawValue: "visible"),
        source: machineID,
        target: threadID,
        kind: .machineThread,
        isManual: false
    )
    let hiddenEdge = CanvasEdge(
        id: EdgeID(rawValue: "hidden"),
        source: threadID,
        target: subagentID,
        kind: .createdBy,
        isManual: false
    )
    let graph = AgentGraph(nodes: [
        machineID: machine,
        threadID: thread,
        subagentID: subagent,
    ])

    let presentation = CanvasPresentationModel(
        graph: graph,
        allEdges: [visibleEdge, hiddenEdge],
        showsSubagents: false,
        focusedNodeID: threadID
    )

    #expect(presentation.nodes.map(\.id) == [machineID, threadID])
    #expect(presentation.edges.map(\.id) == [visibleEdge.id])
    #expect(presentation.focusedNeighborhood == [machineID, threadID])
}

@Test
func touchCanvasProjectionPreservesFortyFourPointTargetsAtMinimumZoom() {
    let node = CanvasNode(
        id: NodeID(rawValue: "compact-node"),
        kind: .codexThread,
        title: "Compact",
        position: CanvasPoint(x: 200, y: 100),
        size: CanvasSize(width: 32, height: 20)
    )
    let viewport = CanvasViewport(
        scale: 0.45,
        offset: CanvasPoint(x: 10, y: -5)
    )

    let projected = CanvasScreenSpaceProjection.node(node, viewport: viewport)

    #expect(projected.position == CanvasPoint(x: 100, y: 40))
    #expect(projected.size.width == 44)
    #expect(projected.size.height == 44)
    #expect(AccessibleHitTarget.minimumDimension == 44)
}

@Test
func artifactServiceReadsOnlyBoundedTextPreview() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-artifact-service-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("example.txt")
    try Data("abcdefghij".utf8).write(to: file)

    let preview = await ArtifactService.shared.textPreview(at: file.path, maximumBytes: 5)

    #expect(preview == "abcde\n\n... file truncated for preview ...")
    #expect(ArtifactService.fileName(#"C:\Users\example\example.txt"#) == "example.txt")
    #expect(ArtifactService.pathExtension(file.path) == "txt")
}

@MainActor
@Test
func canvasViewportInteractionCoalescesPersistenceAndScalesNodeDrag() async {
    let model = CanvasViewportInteractionModel()
    let base = CanvasViewport(scale: 0.5, offset: CanvasPoint(x: 10, y: 20))
    let node = CanvasNode(
        id: NodeID(rawValue: "thread"),
        kind: .codexThread,
        title: "Thread",
        position: CanvasPoint(x: 100, y: 200),
        size: CanvasSize(width: 200, height: 100)
    )

    model.updatePan(translation: CGSize(width: 8, height: -4))
    #expect(model.displayedViewport(base: base).offset == CanvasPoint(x: 18, y: 16))
    #expect(
        model.finishNodeDrag(
            node,
            translation: CGSize(width: 20, height: -10),
            scale: 0.5
        ) == CanvasPoint(x: 140, y: 180)
    )

    var persisted: [CanvasViewport] = []
    let first = CanvasViewport(scale: 0.7, offset: .zero)
    let second = CanvasViewport(scale: 0.9, offset: CanvasPoint(x: 3, y: 4))
    model.scheduleCommit(first, delay: .milliseconds(1)) { persisted.append($0) }
    model.scheduleCommit(second, delay: .milliseconds(1)) { persisted.append($0) }
    let deadline = ContinuousClock.now + .seconds(1)
    while persisted != [second], ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }

    #expect(persisted == [second])
    #expect(model.transientViewport == nil)
}

@MainActor
@Test
func canvasWorkflowEventLedgerDeduplicatesAndAttributesUserTurns() {
    let hostID = HostID(rawValue: "example-host")
    let threadRef = ThreadRef(hostID: hostID, threadID: "thread-1", cwd: "/Users/example/project")
    let old = WorkflowEvent(
        kind: .turnCompleted,
        hostID: hostID,
        threadID: threadRef.threadID,
        turnID: "old-turn",
        method: "turn/completed",
        summary: "Old",
        createdAt: Date(timeIntervalSince1970: 5)
    )
    let started = WorkflowEvent(
        kind: .turnStarted,
        hostID: hostID,
        threadID: threadRef.threadID,
        turnID: "new-turn",
        method: "turn/started",
        summary: "Started",
        createdAt: Date(timeIntervalSince1970: 12)
    )
    let completed = WorkflowEvent(
        kind: .turnCompleted,
        hostID: hostID,
        threadID: threadRef.threadID,
        turnID: "new-turn",
        method: "turn/completed",
        summary: "Completed",
        createdAt: Date(timeIntervalSince1970: 13)
    )
    let ledger = CanvasWorkflowEventLedger(now: Date(timeIntervalSince1970: 10))
    ledger.prime([old], now: Date(timeIntervalSince1970: 10))
    ledger.markNextTurnStartedByUser(threadRef, now: Date(timeIntervalSince1970: 11))

    let deliveries = ledger.deliveries(for: [started, old])
    ledger.markAwaiting(threadRef)

    #expect(deliveries.map(\.event) == [started])
    #expect(deliveries.first?.isLive == true)
    #expect(ledger.deliveries(for: [started, old]).isEmpty)
    #expect(ledger.isUserStartedTurn(completed, in: [completed, started]))
    #expect(ledger.isAwaiting(threadRef, isRunning: true, now: Date(timeIntervalSince1970: 14)))
}

@MainActor
@Test
func threadComposerSessionRestoresFailedSubmissionAndRejectsStaleCompletion() throws {
    let attachment = ChatInputAttachment(
        id: "attachment-1",
        kind: .file,
        name: "notes.txt",
        data: Data("notes".utf8)
    )
    let session = ThreadComposerSession(threadIdentity: "thread-a")
    session.draft = " Send this "
    session.pendingAttachments = [attachment]

    let submission = try #require(session.beginSubmission(isAwaitingResponse: false))
    #expect(submission.text == "Send this")
    #expect(session.draft.isEmpty)
    #expect(session.pendingAttachments.isEmpty)
    #expect(session.isSubmitting)

    session.complete(submission, didSend: false)
    #expect(session.draft == "Send this")
    #expect(session.pendingAttachments == [attachment])
    #expect(!session.isSubmitting)

    let stale = try #require(session.beginSubmission(isAwaitingResponse: false))
    session.reset(for: "thread-b")
    session.complete(stale, didSend: false)
    #expect(session.threadIdentity == "thread-b")
    #expect(session.draft.isEmpty)
    #expect(session.pendingAttachments.isEmpty)
}

@MainActor
private final class TranscriptLoaderProbe {
    private let transcript: ThreadTranscript
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var callCount = 0

    init(transcript: ThreadTranscript) {
        self.transcript = transcript
    }

    func load() async -> ThreadTranscript {
        callCount += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return transcript
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}
