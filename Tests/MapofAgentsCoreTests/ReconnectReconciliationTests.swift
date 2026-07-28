import Foundation
import Testing
@testable import MapofAgentsCore

@Test
func relayReconnectReconciliationReadsDesiredAndLoadedThreadsAuthoritatively() async throws {
    let hostID = HostID(rawValue: "remote-reconcile")
    let endpoint = AppServerRelayEndpoint(
        id: hostID,
        name: "Remote",
        url: try #require(URL(string: "ws://127.0.0.1:18945"))
    )
    let desired = ThreadRef(
        hostID: hostID,
        threadID: "desired-thread",
        cwd: "/workspace/desired"
    )
    let relay = AppServerWebSocketWorkflowRelay(
        endpoint: endpoint,
        supervisor: WorkflowSupervisor()
    )
    let stub = ReconnectRequestStub()
    await relay.updateWorkflowThreads([desired])

    let reconciliation = await relay.reconcileAuthoritativeThreadsUsingRequest { method, params in
        try await stub.response(method: method, params: params)
    }

    #expect(reconciliation.targetThreadIDs == ["desired-thread", "loaded-thread"])
    #expect(reconciliation.loadedThreadIDs == ["loaded-thread"])
    #expect(reconciliation.catalogEntries.map(\.threadRef.threadID) == ["desired-thread", "loaded-thread"])
    #expect(reconciliation.transcriptsByThreadID["desired-thread"]?.turnTimeline?.turns.first?.id == "turn-desired-thread")
    #expect(reconciliation.transcriptsByThreadID["loaded-thread"]?.turnTimeline?.turns.first?.id == "turn-loaded-thread")
    #expect(reconciliation.failuresByThreadID.isEmpty)
    #expect(reconciliation.loadedThreadListError == nil)
    #expect(
        reconciliation.authoritativeCatalogStatusThreadIDs
            == ["desired-thread", "loaded-thread"]
    )

    let calls = await stub.recordedCalls
    #expect(calls.filter { $0.method == .listLoadedThreads }.count == 1)
    #expect(calls.filter { $0.method == .readThread }.count == 2)
    #expect(calls.filter { $0.method == .listTurns }.count == 2)
    #expect(calls.compactMap { $0.params["threadId"]?.stringValue }.sorted() == [
        "desired-thread",
        "desired-thread",
        "loaded-thread",
        "loaded-thread",
    ])
    #expect(calls.filter { $0.method == .listTurns }.allSatisfy {
        $0.params["limit"]?.intValue == 1
            && $0.params["itemsView"]?.stringValue == "summary"
    })
}

@Test
@MainActor
func supervisorPreservesLastKnownStateUntilReconnectReconciliationCompletes() async {
    let hostID = HostID(rawValue: "remote-reconcile")
    let threadID = "thread-1"
    let threadRef = ThreadRef(
        hostID: hostID,
        threadID: threadID,
        cwd: "/workspace/project"
    )
    let store = WorkflowSupervisorStore()
    await store.restoreWorkflowEvents([
        WorkflowEvent(
            kind: .turnStarted,
            hostID: hostID,
            threadID: threadID,
            turnID: "turn-old",
            method: "turn/started",
            summary: "Working"
        ),
    ])

    store.markHostRuntimeStatesReconciling(hostID: hostID)

    let staleState = store.threadRuntimeStates[threadRef.qualifiedID]
    #expect(staleState?.status == .running)
    #expect(staleState?.activeTurnID == "turn-old")
    #expect(staleState?.currentActivitySummary == "Reconnecting — showing last known state")

    let completedAt = Date(timeIntervalSince1970: 200)
    let transcript = ThreadTranscript(
        threadRef: threadRef,
        turnTimeline: ThreadTurnTimeline(
            threadRef: threadRef,
            turns: [
                ThreadTurn(
                    id: "turn-current",
                    status: .complete,
                    startedAt: Date(timeIntervalSince1970: 100),
                    completedAt: completedAt,
                    items: []
                ),
            ]
        )
    )
    store.applyReconnectReconciliation(
        AppServerReconnectReconciliation(
            hostID: hostID,
            targetThreadIDs: [threadID],
            loadedThreadIDs: [threadID],
            catalogEntries: [
                ThreadCatalogEntry(
                    threadRef: threadRef,
                    hostName: "Remote",
                    loadedStatus: .complete,
                    lastActivityAt: completedAt
                ),
            ],
            transcriptsByThreadID: [threadID: transcript]
        )
    )

    let currentState = store.threadRuntimeStates[threadRef.qualifiedID]
    #expect(currentState?.status == .complete)
    #expect(currentState?.activeTurnID == "turn-current")
    #expect(currentState?.currentActivitySummary == "Turn completed")
    #expect(store.reconciledThreadCatalogEntries[threadRef.qualifiedID]?.loadedStatus == .complete)
}

@Test
@MainActor
func failedReconnectReadKeepsLastKnownThreadStateMarkedUnverified() async {
    let hostID = HostID(rawValue: "remote-reconcile")
    let threadID = "thread-unverified"
    let threadRef = ThreadRef(
        hostID: hostID,
        threadID: threadID,
        cwd: "/workspace/project"
    )
    let store = WorkflowSupervisorStore()
    await store.restoreWorkflowEvents([
        WorkflowEvent(
            kind: .turnStarted,
            hostID: hostID,
            threadID: threadID,
            turnID: "turn-last-known",
            method: "turn/started",
            summary: "Working"
        ),
    ])
    store.markHostRuntimeStatesReconciling(hostID: hostID)

    store.applyReconnectReconciliation(
        AppServerReconnectReconciliation(
            hostID: hostID,
            targetThreadIDs: [threadID],
            loadedThreadIDs: [threadID],
            failuresByThreadID: [
                threadID: "The authoritative read timed out.",
            ]
        )
    )

    let state = store.threadRuntimeStates[threadRef.qualifiedID]
    #expect(state?.status == .running)
    #expect(state?.activeTurnID == "turn-last-known")
    #expect(state?.currentActivitySummary == "Could not fully verify after reconnect — last known state")
    #expect(state?.lastError == "The authoritative read timed out.")
}

@Test
func reconnectPlanNeverDropsExplicitlyDesiredThreads() {
    let desired = Set((0..<40).map { "desired-\($0)" })
    let loaded = Set((0..<40).map { "loaded-\($0)" })

    let plan = AppServerReconnectPlan.make(
        desiredThreadIDs: desired,
        loadedThreadIDs: loaded,
        maximumTargetThreadCount: 32
    )

    #expect(Set(plan.targetThreadIDs).isSuperset(of: desired))
    #expect(plan.targetThreadIDs.count == 40)
    #expect(plan.omittedThreadIDs == loaded)
}

@Test
func reconnectReconciliationUsesProtocolTimeoutOverride() async {
    let session = AppServerSession()
    let connectionID = AppServerConnectionID()
    let clock = ContinuousClock()
    let startedAt = clock.now

    let reconciliation = await AppServerReconnectReconciler.reconcile(
        hostID: HostID(rawValue: "timeout-host"),
        hostName: "Timeout Host",
        desiredThreads: [:],
        policy: AppServerReconnectPolicy(
            loadedThreadLimit: 1,
            maximumTargetThreadCount: 0,
            maximumConcurrentThreadReads: 1,
            requestTimeout: .milliseconds(40)
        )
    ) { method, params, timeout in
        try await session.request(
            AppServerCall(method, params: params),
            connectionID: connectionID,
            timeoutContext: .remote("Timeout Host"),
            timeoutOverride: timeout
        ) { _, _ in
            // Deliberately never produce a response.
        }
    }

    let elapsed = startedAt.duration(to: clock.now)
    #expect(reconciliation.loadedThreadListError != nil)
    #expect(elapsed >= .milliseconds(20))
    #expect(elapsed < .seconds(1))
}

@Test
func activeThreadReadWinsOverPriorCompletedTurnWithoutReusingCompletedID() {
    let hostID = HostID(rawValue: "remote-conflict")
    let threadRef = ThreadRef(
        hostID: hostID,
        threadID: "thread-conflict",
        cwd: "/workspace/project"
    )
    var state = ThreadRuntimeState(
        hostID: hostID,
        threadID: threadRef.threadID,
        status: .running,
        activeFlags: [.running],
        activeTurnID: "turn-live"
    )
    let completedTurn = ThreadTurn(
        id: "turn-prior",
        status: .complete,
        startedAt: Date(timeIntervalSince1970: 10),
        completedAt: Date(timeIntervalSince1970: 20),
        items: []
    )

    AppServerReconnectStateReducer.apply(
        catalogEntry: ThreadCatalogEntry(
            threadRef: threadRef,
            hostName: "Remote",
            loadedStatus: .running,
            lastActivityAt: Date(timeIntervalSince1970: 30)
        ),
        transcript: ThreadTranscript(
            threadRef: threadRef,
            turnTimeline: ThreadTurnTimeline(
                threadRef: threadRef,
                turns: [completedTurn]
            )
        ),
        catalogStatusIsAuthoritative: true,
        to: &state
    )

    #expect(state.status == .running)
    #expect(state.activeFlags.contains(.running))
    #expect(state.activeTurnID == "turn-live")

    state.activeTurnID = "turn-prior"
    AppServerReconnectStateReducer.apply(
        catalogEntry: ThreadCatalogEntry(
            threadRef: threadRef,
            hostName: "Remote",
            loadedStatus: .running
        ),
        transcript: ThreadTranscript(
            threadRef: threadRef,
            turnTimeline: ThreadTurnTimeline(
                threadRef: threadRef,
                turns: [completedTurn]
            )
        ),
        catalogStatusIsAuthoritative: true,
        to: &state
    )
    #expect(state.activeTurnID == nil)
}

@Test
func emptyTurnObservationFallsBackToThreadReadStatus() {
    let hostID = HostID(rawValue: "remote-empty")
    let threadRef = ThreadRef(
        hostID: hostID,
        threadID: "thread-empty",
        cwd: "/workspace/project"
    )
    var state = ThreadRuntimeState(
        hostID: hostID,
        threadID: threadRef.threadID,
        status: .running,
        activeFlags: [.running]
    )

    AppServerReconnectStateReducer.apply(
        catalogEntry: ThreadCatalogEntry(
            threadRef: threadRef,
            hostName: "Remote",
            loadedStatus: .complete
        ),
        transcript: ThreadTranscript(
            threadRef: threadRef,
            turnTimeline: ThreadTurnTimeline(threadRef: threadRef, turns: [])
        ),
        catalogStatusIsAuthoritative: true,
        to: &state
    )

    #expect(state.status == .complete)
    #expect(!state.activeFlags.contains(.running))
}

@Test
@MainActor
func supervisorRejectsReconnectSnapshotFromStaleConnectionEpoch() async {
    let hostID = HostID(rawValue: "remote-epoch")
    let threadID = "thread-epoch"
    let store = WorkflowSupervisorStore()
    await store.restoreWorkflowEvents([
        WorkflowEvent(
            kind: .turnStarted,
            hostID: hostID,
            threadID: threadID,
            turnID: "turn-live",
            method: "turn/started",
            summary: "Working"
        ),
    ])
    store.markHostRuntimeStatesReconciling(hostID: hostID)

    let staleConnectionID = AppServerConnectionID()
    let currentConnectionID = AppServerConnectionID()
    store.recordRelayConnectionReady(
        hostID: hostID,
        connectionID: currentConnectionID
    )
    store.applyReconnectReconciliation(
        AppServerReconnectReconciliation(
            hostID: hostID,
            connectionID: staleConnectionID,
            targetThreadIDs: [threadID],
            loadedThreadIDs: [threadID],
            catalogEntries: [
                ThreadCatalogEntry(
                    threadRef: ThreadRef(
                        hostID: hostID,
                        threadID: threadID,
                        cwd: "/workspace/project"
                    ),
                    hostName: "Remote",
                    loadedStatus: .complete
                ),
            ],
            authoritativeCatalogStatusThreadIDs: [threadID]
        )
    )

    let key = ThreadRef.qualifiedID(hostID: hostID, threadID: threadID)
    #expect(store.threadRuntimeStates[key]?.status == .running)
    #expect(
        store.threadRuntimeStates[key]?.currentActivitySummary
            == "Reconnecting — showing last known state"
    )
}

@Test
@MainActor
func disconnectInvalidatesSnapshotWhileReconnectCallbackIsSuspended() async {
    let hostID = HostID(rawValue: "remote-suspended-callback")
    let threadID = "thread-suspended"
    let connectionID = AppServerConnectionID()
    let gate = AppServerConnectionEpochGate()
    let store = WorkflowSupervisorStore()
    await store.restoreWorkflowEvents([
        WorkflowEvent(
            kind: .turnStarted,
            hostID: hostID,
            threadID: threadID,
            turnID: "turn-live",
            method: "turn/started",
            summary: "Working"
        ),
    ])
    store.markHostRuntimeStatesReconciling(hostID: hostID)
    store.recordRelayConnectionReady(hostID: hostID, connectionID: connectionID)
    gate.activate(connectionID)

    var delayedSnapshot = AppServerReconnectReconciliation(
        hostID: hostID,
        connectionID: connectionID,
        targetThreadIDs: [threadID],
        loadedThreadIDs: [threadID],
        catalogEntries: [
            ThreadCatalogEntry(
                threadRef: ThreadRef(
                    hostID: hostID,
                    threadID: threadID,
                    cwd: "/workspace/project"
                ),
                hostName: "Remote",
                loadedStatus: .complete
            ),
        ],
        authoritativeCatalogStatusThreadIDs: [threadID]
    )
    delayedSnapshot.connectionEpochGate = gate

    // Models the relay invalidating its connection synchronously while the
    // already-issued callback is waiting to enter MainActor.
    gate.invalidate(connectionID)
    store.applyReconnectReconciliation(delayedSnapshot)

    let key = ThreadRef.qualifiedID(hostID: hostID, threadID: threadID)
    #expect(store.threadRuntimeStates[key]?.status == .running)
    #expect(
        store.threadRuntimeStates[key]?.currentActivitySummary
            == "Reconnecting — showing last known state"
    )
}

@Test
@MainActor
func liveUpdateMarkerPreventsDelayedReconnectSnapshotOverwrite() async {
    let hostID = HostID(rawValue: "remote-live-gate")
    let threadID = "thread-live"
    let store = WorkflowSupervisorStore()
    await store.restoreWorkflowEvents([
        WorkflowEvent(
            kind: .turnCompleted,
            hostID: hostID,
            threadID: threadID,
            turnID: "turn-old",
            method: "turn/completed",
            summary: "Done"
        ),
    ])
    store.markHostRuntimeStatesReconciling(hostID: hostID)
    await store.restoreWorkflowEvents([
        WorkflowEvent(
            kind: .turnStarted,
            hostID: hostID,
            threadID: threadID,
            turnID: "turn-new",
            method: "turn/started",
            summary: "New command running"
        ),
    ])

    store.applyReconnectReconciliation(
        AppServerReconnectReconciliation(
            hostID: hostID,
            targetThreadIDs: [threadID],
            loadedThreadIDs: [threadID],
            catalogEntries: [
                ThreadCatalogEntry(
                    threadRef: ThreadRef(
                        hostID: hostID,
                        threadID: threadID,
                        cwd: "/workspace/project"
                    ),
                    hostName: "Remote",
                    loadedStatus: .complete
                ),
            ],
            authoritativeCatalogStatusThreadIDs: [threadID]
        )
    )

    let key = ThreadRef.qualifiedID(hostID: hostID, threadID: threadID)
    #expect(store.threadRuntimeStates[key]?.status == .running)
    #expect(store.threadRuntimeStates[key]?.activeTurnID == "turn-new")
    #expect(store.reconciledThreadCatalogEntries[key] == nil)
}

@Test
@MainActor
func localReconnectUsesSameLiveUpdateGateAndReducer() async {
    let store = CodexRuntimeStore()
    let hostID = store.localHost.id
    let threadID = "local-thread"
    store.recordWorkflowEvent(
        WorkflowEvent(
            kind: .turnCompleted,
            hostID: hostID,
            threadID: threadID,
            turnID: "turn-old",
            method: "turn/completed",
            summary: "Done"
        )
    )
    let generation = store.markLocalRuntimeStatesReconciling()
    let baseline = store.localRuntimeRevisionSnapshot()
    store.recordWorkflowEvent(
        WorkflowEvent(
            kind: .turnStarted,
            hostID: hostID,
            threadID: threadID,
            turnID: "turn-new",
            method: "turn/started",
            summary: "Running locally"
        )
    )

    store.applyLocalReconnectReconciliation(
        AppServerReconnectReconciliation(
            hostID: hostID,
            targetThreadIDs: [threadID],
            loadedThreadIDs: [threadID],
            catalogEntries: [
                ThreadCatalogEntry(
                    threadRef: ThreadRef(
                        hostID: hostID,
                        threadID: threadID,
                        cwd: "/workspace/project"
                    ),
                    hostName: "Local",
                    loadedStatus: .complete
                ),
            ],
            authoritativeCatalogStatusThreadIDs: [threadID]
        ),
        expectedGeneration: generation,
        baselineRevisions: baseline
    )

    let key = ThreadRef.qualifiedID(hostID: hostID, threadID: threadID)
    #expect(store.threadRuntimeStates[key]?.status == .running)
    #expect(store.threadRuntimeStates[key]?.activeTurnID == "turn-new")
}

private actor ReconnectRequestStub {
    private(set) var recordedCalls: [AppServerCall] = []

    func response(method: AppServerMethod, params: JSONValue) throws -> JSONValue {
        recordedCalls.append(AppServerCall(method, params: params))

        switch method {
        case .listLoadedThreads:
            return .object([
                "data": .array([.string("loaded-thread")]),
            ])
        case .readThread:
            guard let threadID = params["threadId"]?.stringValue else {
                throw CodexAppServerError.invalidResponse
            }
            return .object([
                "thread": .object([
                    "id": .string(threadID),
                    "cwd": .string("/workspace/\(threadID)"),
                    "name": .string(threadID),
                    "status": .string("running"),
                ]),
            ])
        case .listTurns:
            guard let threadID = params["threadId"]?.stringValue else {
                throw CodexAppServerError.invalidResponse
            }
            return .object([
                "data": .array([
                    .object([
                        "id": .string("turn-\(threadID)"),
                        "status": .string("inProgress"),
                        "itemsView": .string("summary"),
                        "startedAt": .number(100),
                        "items": .array([]),
                    ]),
                ]),
            ])
        default:
            throw CodexAppServerError.server("Unexpected reconciliation call: \(method.rawValue)")
        }
    }
}
