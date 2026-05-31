import Foundation
import Testing
@testable import MapofAgentsCore

@Test
func threadRuntimeStateReducesEventsAndAttention() {
    let hostID = HostID(rawValue: "local")
    let startedAt = Date(timeIntervalSince1970: 100)
    let completedAt = Date(timeIntervalSince1970: 120)
    var state = ThreadRuntimeState(hostID: hostID, threadID: "thread-1")

    state.apply(
        event: WorkflowEvent(
            kind: .turnStarted,
            hostID: hostID,
            threadID: "thread-1",
            turnID: "turn-1",
            method: "turn/started",
            summary: "Turn started",
            createdAt: startedAt
        ),
        markUnread: false
    )

    #expect(state.status == .running)
    #expect(state.activeFlags.contains(.running))
    #expect(state.activeTurnID == "turn-1")

    state.applyAttentionRequest(
        RuntimeAttentionRequest(
            id: "request-1",
            hostID: hostID,
            method: "item/commandExecution/requestApproval",
            threadID: "thread-1",
            turnID: "turn-1",
            summary: "Run command",
            createdAt: Date(timeIntervalSince1970: 110)
        )
    )

    #expect(state.status == .needsInput)
    #expect(state.needsAttention)
    #expect(state.pendingRequestIDs == ["request-1"])
    #expect(state.isUnread)

    state.resolveAttentionRequest("request-1")
    #expect(state.pendingRequestIDs.isEmpty)
    #expect(!state.activeFlags.contains(.waitingOnApproval))

    state.apply(
        event: WorkflowEvent(
            kind: .turnCompleted,
            hostID: hostID,
            threadID: "thread-1",
            turnID: "turn-1",
            method: "turn/completed",
            summary: "Turn completed",
            createdAt: completedAt
        ),
        markUnread: true
    )

    #expect(state.status == .complete)
    #expect(!state.activeFlags.contains(.running))
    #expect(state.isUnread)
}

@Test
func threadRuntimeStatePublishesLiveStateSummary() {
    let hostID = HostID(rawValue: "local")
    var state = ThreadRuntimeState(
        hostID: hostID,
        threadID: "thread-live",
        lastActivityAt: Date(timeIntervalSince1970: 100)
    )

    state.recordItemActivity(
        method: "item/commandExecution/started",
        itemID: "command-1",
        at: Date(timeIntervalSince1970: 110)
    )

    #expect(state.status == .running)
    #expect(state.liveStateSummary.tone == .working)
    #expect(state.liveStateSummary.title == "Running command")
    #expect(state.liveStateSummary.detail == "1 active item")

    let request = RuntimeAttentionRequest(
        id: "request-1",
        hostID: hostID,
        method: "item/commandExecution/requestApproval",
        threadID: "thread-live",
        turnID: "turn-1",
        summary: "Approve command",
        createdAt: Date(timeIntervalSince1970: 120)
    )
    state.applyAttentionRequest(request)

    #expect(state.liveStateSummary.tone == .waiting)
    #expect(state.liveStateSummary.title == "Waiting for approval")
    #expect(state.liveStateSummary.detail == "Approve command")

    state.apply(
        event: WorkflowEvent(
            kind: .turnCompleted,
            hostID: hostID,
            threadID: "thread-live",
            turnID: "turn-1",
            method: "turn/completed",
            summary: "Turn completed",
            createdAt: Date(timeIntervalSince1970: 140)
        ),
        markUnread: true
    )

    #expect(state.liveStateSummary.tone == .finished)
    #expect(state.liveStateSummary.title == "Finished")
    #expect(state.activeItemIDs.isEmpty)
}

@Test
func catalogEntryAppliesRuntimeLiveStateSummary() {
    let hostID = HostID(rawValue: "local")
    let threadRef = ThreadRef(hostID: hostID, threadID: "thread-live", cwd: "/tmp")
    let entry = ThreadCatalogEntry(
        threadRef: threadRef,
        hostName: "Mac",
        title: "Live Thread",
        loadedStatus: .idle,
        lastActivityAt: Date(timeIntervalSince1970: 50)
    )
    let state = ThreadRuntimeState(
        hostID: hostID,
        threadID: threadRef.threadID,
        status: .running,
        activeFlags: [.running],
        activeItemIDs: ["tool-1"],
        lastActivityAt: Date(timeIntervalSince1970: 80),
        currentActivitySummary: "Running tool"
    )

    let applied = entry.applying(runtimeState: state)

    #expect(applied.loadedStatus == .running)
    #expect(applied.latestEventSummary == "Running tool")
    #expect(applied.lastActivityAt == Date(timeIntervalSince1970: 80))
    #expect(applied.liveStateSummary.tone == .working)
    #expect(applied.liveStateSummary.title == "Running tool")
}

@Test
@MainActor
func codexRuntimeStoreCompletesLocalAttentionStateSynchronously() {
    let store = CodexRuntimeStore()
    let request = RuntimeAttentionRequest(
        id: "local::42",
        hostID: HostID(rawValue: "local"),
        requestID: .int(42),
        method: "item/commandExecution/requestApproval",
        threadID: "thread-1",
        turnID: "turn-1",
        summary: "Run command"
    )

    store.applyAttentionRequest(request)

    #expect(store.pendingAttentionRequests.map(\.id) == ["local::42"])
    #expect(store.threadRuntimeStates["local::thread-1"]?.status == .needsInput)
    #expect(store.threadRuntimeStates["local::thread-1"]?.pendingRequestIDs == ["local::42"])

    store.completeAttentionRequest(request)

    #expect(store.pendingAttentionRequests.isEmpty)
    #expect(store.threadRuntimeStates["local::thread-1"]?.pendingRequestIDs.isEmpty == true)
    #expect(store.threadRuntimeStates["local::thread-1"]?.status == .idle)

    store.completeAttentionRequest(id: "42")

    #expect(store.pendingAttentionRequests.isEmpty)
    #expect(store.threadRuntimeStates["local::thread-1"]?.pendingRequestIDs.isEmpty == true)
}

@Test
func threadTurnTimelineGroupsMessagesByUserTurns() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "local"), threadID: "thread-1", cwd: "/tmp")
    let transcript = ThreadTranscript(
        threadRef: threadRef,
        messages: [
            ThreadMessage(id: "system", role: .system, text: "Ready", createdAt: Date(timeIntervalSince1970: 1)),
            ThreadMessage(id: "user-1", role: .user, text: "ping", createdAt: Date(timeIntervalSince1970: 2)),
            ThreadMessage(id: "assistant-1", role: .assistant, text: "pong", createdAt: Date(timeIntervalSince1970: 3)),
            ThreadMessage(id: "tool-1", role: .tool, text: "exec_command", createdAt: Date(timeIntervalSince1970: 4)),
            ThreadMessage(id: "user-2", role: .user, text: "date", createdAt: Date(timeIntervalSince1970: 5)),
            ThreadMessage(id: "assistant-2", role: .assistant, text: "today", createdAt: Date(timeIntervalSince1970: 6)),
        ]
    )

    let timeline = ThreadTurnTimeline.fromTranscript(transcript)

    #expect(timeline.turns.count == 3)
    #expect(timeline.turns[0].items.map(\.id) == ["system"])
    #expect(timeline.turns[1].items.map(\.id) == ["user-1", "assistant-1", "tool-1"])
    #expect(timeline.turns[2].items.map(\.id) == ["user-2", "assistant-2"])
    #expect(timeline.turns[1].items.last?.kind == .tool)
}

@Test
func appServerSearchUsesSearchTermPayload() {
    let params = CodexRuntimeStore.threadSearchParams(query: "  invoice worker  ", limit: 25)

    #expect(params["searchTerm"] == .string("invoice worker"))
    #expect(params["query"] == nil)
    #expect(params["limit"] == .number(25))
}

@Test
func loadedThreadIDsParseStringResponses() {
    let result: JSONValue = .object([
        "data": .array([
            .string("thread-a"),
            .string("thread-b"),
            .object(["id": .string("thread-c")]),
            .string("thread-a"),
        ]),
    ])

    #expect(ThreadCatalogEntry.loadedThreadIDs(from: result) == ["thread-a", "thread-b", "thread-c"])
}

@Test
func appServerThreadParsesStructuredActiveStatusFlags() {
    let entry = ThreadCatalogEntry.appServerThread(
        from: .object([
            "id": .string("thread-1"),
            "cwd": .string("/tmp/project"),
            "status": .object([
                "type": .string("active"),
                "activeFlags": .array([.string("waitingOnUserInput")]),
            ]),
        ]),
        hostID: HostID(rawValue: "host"),
        hostName: "Host"
    )

    #expect(entry?.loadedStatus == .needsInput)
}

@Test
func appServerThreadParsesSubagentThreadKind() {
    let entry = ThreadCatalogEntry.appServerThread(
        from: .object([
            "id": .string("thread-1"),
            "cwd": .string("/tmp/project"),
            "thread_source": .string("subagent"),
            "name": .string("PDF reader"),
        ]),
        hostID: HostID(rawValue: "host"),
        hostName: "Host"
    )

    #expect(entry?.threadKind == .subagent)
    #expect(entry?.source == "subagent")
}

@Test
func appServerSearchResultUsesThreadWrapperAndSnippet() {
    let entry = ThreadCatalogEntry.appServerSearchResult(
        from: .object([
            "snippet": .string("matched text"),
            "thread": .object([
                "id": .string("thread-1"),
                "cwd": .string("/tmp/project"),
                "name": .string("Worker"),
            ]),
        ]),
        hostID: HostID(rawValue: "host"),
        hostName: "Host"
    )

    #expect(entry?.threadRef.threadID == "thread-1")
    #expect(entry?.title == "Worker")
    #expect(entry?.preview == "matched text")
}

@Test
@MainActor
func serverSearchResultsRemainVisibleWhenLocalFieldsDoNotMatchQuery() {
    let store = ThreadCatalogStore()
    let query = "invoice clues only in server index"
    let entry = ThreadCatalogEntry(
        threadRef: ThreadRef(hostID: HostID(rawValue: "host"), threadID: "thread-1", cwd: "/tmp/project", name: "Worker"),
        hostName: "Host",
        title: "Worker",
        preview: "Ordinary preview",
        lastActivityAt: Date(timeIntervalSince1970: 100)
    )

    store.selectedMode = .search
    store.searchText = query
    store.upsert([entry])
    #expect(store.visibleEntries.isEmpty)

    store.recordServerSearchResults([entry], query: query)
    #expect(store.visibleEntries.map(\.id) == [entry.id])
}

@Test
@MainActor
func changingSearchQueryHidesStaleServerOnlyHitsButKeepsLocalMatches() {
    let store = ThreadCatalogStore()
    let stale = ThreadCatalogEntry(
        threadRef: ThreadRef(hostID: HostID(rawValue: "host"), threadID: "thread-1", cwd: "/tmp/project", name: "Worker"),
        hostName: "Host",
        title: "Worker",
        preview: "Ordinary preview"
    )
    let local = ThreadCatalogEntry(
        threadRef: ThreadRef(hostID: HostID(rawValue: "host"), threadID: "thread-2", cwd: "/tmp/project", name: "Seattle helper"),
        hostName: "Host",
        title: "Seattle helper",
        preview: ""
    )

    store.selectedMode = .search
    store.searchText = "invoice"
    store.upsert([stale, local])
    store.recordServerSearchResults([stale], query: "invoice")
    #expect(store.visibleEntries.map(\.id) == [stale.id])

    store.searchText = "Seattle"
    #expect(store.visibleEntries.map(\.id) == [local.id])
}

@Test
func threadCatalogPartialFailureMessageKeepsPerHostContext() {
    let message = ThreadCatalogStore.partialFailureMessage(for: [
        ThreadCatalogFetchFailure(hostName: "Local Mac", operation: "threads", message: "boom"),
        ThreadCatalogFetchFailure(hostName: "Windows Lab", operation: "search", message: "offline"),
    ])

    #expect(message?.contains("Some thread catalog results could not be loaded.") == true)
    #expect(message?.contains("Local Mac threads: boom") == true)
    #expect(message?.contains("Windows Lab search: offline") == true)
}

@Test
@MainActor
func threadCatalogMarkReadSurvivesWorkflowEventReplay() {
    let hostID = HostID(rawValue: "local")
    let threadRef = ThreadRef(hostID: hostID, threadID: "thread-1", cwd: "/tmp")
    let store = ThreadCatalogStore()
    let oldCompleted = WorkflowEvent(
        kind: .turnCompleted,
        hostID: hostID,
        threadID: threadRef.threadID,
        method: "turn/completed",
        summary: "Old completion",
        createdAt: Date(timeIntervalSince1970: 100)
    )
    let newCompleted = WorkflowEvent(
        kind: .turnCompleted,
        hostID: hostID,
        threadID: threadRef.threadID,
        method: "turn/completed",
        summary: "New completion",
        createdAt: Date(timeIntervalSince1970: 300)
    )

    store.apply(events: [oldCompleted], graph: AgentGraph())
    #expect(store.entry(for: threadRef)?.unread == true)

    store.markRead(threadRef, isRead: true, at: Date(timeIntervalSince1970: 200))
    #expect(store.entry(for: threadRef)?.unread == false)
    #expect(store.readStatesByID[threadRef.qualifiedID]?.lastSeenAt == Date(timeIntervalSince1970: 200))

    store.apply(events: [oldCompleted], graph: AgentGraph())
    #expect(store.entry(for: threadRef)?.unread == false)

    store.apply(events: [newCompleted], graph: AgentGraph())
    #expect(store.entry(for: threadRef)?.unread == true)
}

@Test
@MainActor
func idleRuntimeStateDoesNotPromoteCatalogRecency() {
    let hostID = HostID(rawValue: "local")
    let threadRef = ThreadRef(hostID: hostID, threadID: "thread-1", cwd: "/tmp")
    let store = ThreadCatalogStore()
    let originalActivity = Date(timeIntervalSince1970: 100)
    store.upsert([
        ThreadCatalogEntry(
            threadRef: threadRef,
            hostName: "Mac",
            title: "Worker",
            lastActivityAt: originalActivity
        ),
    ])

    store.apply(runtimeStates: [
        threadRef.qualifiedID: ThreadRuntimeState(
            hostID: hostID,
            threadID: threadRef.threadID,
            status: .complete,
            lastActivityAt: Date(timeIntervalSince1970: 500)
        ),
    ])

    #expect(store.entry(for: threadRef)?.lastActivityAt == originalActivity)

    store.apply(runtimeStates: [
        threadRef.qualifiedID: ThreadRuntimeState(
            hostID: hostID,
            threadID: threadRef.threadID,
            status: .running,
            activeFlags: [.running],
            lastActivityAt: Date(timeIntervalSince1970: 600)
        ),
    ])

    #expect(store.entry(for: threadRef)?.lastActivityAt == Date(timeIntervalSince1970: 600))
}

@Test
func transcriptReadPreparationDoesNotChangeRuntimeActivity() {
    let activityDate = Date(timeIntervalSince1970: 100)
    var state = ThreadRuntimeState(
        hostID: HostID(rawValue: "local"),
        threadID: "thread-1",
        status: .failed,
        liveAssistantText: "partial answer",
        lastActivityAt: activityDate,
        transcriptCursor: "older"
    )

    state.prepareForTranscriptRead()

    #expect(state.liveAssistantText == "")
    #expect(state.transcriptCursor == nil)
    #expect(state.lastActivityAt == activityDate)
    #expect(state.status == .failed)
}

@Test
func latestTranscriptReadClearsStaleRunningStateAfterMissedCompletion() {
    let hostID = HostID(rawValue: "local")
    let threadRef = ThreadRef(hostID: hostID, threadID: "thread-1", cwd: "/tmp/project")
    let startedAt = Date(timeIntervalSince1970: 110)
    let completedAt = Date(timeIntervalSince1970: 130)
    let message = ThreadMessage(
        id: "assistant-1",
        role: .assistant,
        text: "done",
        createdAt: completedAt
    )
    let transcript = ThreadTranscript(
        threadRef: threadRef,
        messages: [message],
        nextCursor: "older-cursor",
        lastUpdatedAt: completedAt,
        turnTimeline: ThreadTurnTimeline(
            threadRef: threadRef,
            turns: [
                ThreadTurn(
                    id: "turn-1",
                    status: .complete,
                    startedAt: startedAt,
                    completedAt: completedAt,
                    items: [
                        ThreadTurnItem(id: message.id, kind: .assistantMessage, message: message),
                    ]
                ),
            ]
        )
    )
    var state = ThreadRuntimeState(
        hostID: hostID,
        threadID: threadRef.threadID,
        status: .running,
        activeFlags: [.running],
        activeTurnID: "turn-1",
        liveAssistantText: "partial",
        lastActivityAt: Date(timeIntervalSince1970: 120),
        transcriptCursor: nil
    )

    state.reconcileAfterLatestTranscriptRead(transcript)

    #expect(state.status == .complete)
    #expect(!state.activeFlags.contains(.running))
    #expect(state.liveAssistantText == "")
    #expect(state.activeTurnID == "turn-1")
    #expect(state.transcriptCursor == "older-cursor")
    #expect(state.lastActivityAt == completedAt)
}

@Test
func workflowMembershipMapCapturesActiveOtherMultipleAndMissingThreads() {
    let hostID = HostID(rawValue: "local")
    let sharedRef = ThreadRef(hostID: hostID, threadID: "shared", cwd: "/tmp/shared")
    let currentOnlyRef = ThreadRef(hostID: hostID, threadID: "current", cwd: "/tmp/current")
    let otherOnlyRef = ThreadRef(hostID: hostID, threadID: "other", cwd: "/tmp/other")
    let activeWorkflow = WorkflowRecord(id: "active", name: "Current")
    let otherWorkflow = WorkflowRecord(id: "other-workflow", name: "Other")
    let currentNodeID = NodeID(rawValue: "current-node")
    let sharedCurrentNodeID = NodeID(rawValue: "shared-current-node")
    let sharedOtherNodeID = NodeID(rawValue: "shared-other-node")
    let otherNodeID = NodeID(rawValue: "other-node")
    let activeGraph = AgentGraph(nodes: [
        currentNodeID: catalogTestThreadNode(id: currentNodeID, title: "Current", threadRef: currentOnlyRef),
        sharedCurrentNodeID: catalogTestThreadNode(id: sharedCurrentNodeID, title: "Shared", threadRef: sharedRef),
    ])
    let otherGraph = AgentGraph(nodes: [
        sharedOtherNodeID: catalogTestThreadNode(id: sharedOtherNodeID, title: "Shared Copy", threadRef: sharedRef),
        otherNodeID: catalogTestThreadNode(id: otherNodeID, title: "Other", threadRef: otherOnlyRef),
    ])

    let map = ThreadWorkflowMembership.map(
        workflows: [activeWorkflow, otherWorkflow],
        graphsByWorkflowID: [
            activeWorkflow.id: activeGraph,
            otherWorkflow.id: otherGraph,
        ],
        activeWorkflowID: activeWorkflow.id
    )

    #expect(map[currentOnlyRef.qualifiedID]?.first?.workflowName == "Current")
    #expect(map[currentOnlyRef.qualifiedID]?.first?.isActiveWorkflow == true)
    #expect(map[otherOnlyRef.qualifiedID]?.first?.workflowName == "Other")
    #expect(map[otherOnlyRef.qualifiedID]?.first?.isActiveWorkflow == false)
    #expect(map[sharedRef.qualifiedID]?.count == 2)
    #expect(map["local::missing"] == nil)
}

@Test
func workflowMembershipMapDoesNotTrapOnDuplicateWorkflowIDs() {
    let hostID = HostID(rawValue: "local")
    let threadRef = ThreadRef(hostID: hostID, threadID: "thread", cwd: "/tmp")
    let nodeID = NodeID(rawValue: "thread-node")
    let graph = AgentGraph(nodes: [
        nodeID: catalogTestThreadNode(id: nodeID, title: "Thread", threadRef: threadRef),
    ])

    let map = ThreadWorkflowMembership.map(
        workflows: [
            WorkflowRecord(id: "duplicate", name: "First"),
            WorkflowRecord(id: "duplicate", name: "Second"),
        ],
        graphsByWorkflowID: ["duplicate": graph],
        activeWorkflowID: "duplicate"
    )

    #expect(map[threadRef.qualifiedID]?.first?.workflowName == "First")
    #expect(map[threadRef.qualifiedID]?.first?.isActiveWorkflow == true)
}

@Test
func threadCatalogEntryShowsWorkflowContextLabels() {
    let hostID = HostID(rawValue: "local")
    let threadRef = ThreadRef(hostID: hostID, threadID: "thread", cwd: "/tmp")
    let current = ThreadWorkflowMembership(
        workflowID: "current",
        workflowName: "Current",
        nodeID: NodeID(rawValue: "node-current"),
        isActiveWorkflow: true
    )
    let other = ThreadWorkflowMembership(
        workflowID: "other",
        workflowName: "Other",
        nodeID: NodeID(rawValue: "node-other"),
        isActiveWorkflow: false
    )

    var entry = ThreadCatalogEntry(
        threadRef: threadRef,
        hostName: "Mac",
        workflowMemberships: [current]
    )
    #expect(entry.workflowContextLabel == "Current workflow: Current")
    #expect(entry.activeWorkflowNodeID == NodeID(rawValue: "node-current"))

    entry.workflowMemberships = [other]
    #expect(entry.workflowContextLabel == "Other")
    #expect(entry.activeWorkflowNodeID == nil)

    entry.workflowMemberships = [current, other]
    #expect(entry.workflowContextLabel == "Current workflow: Current + 1 more")

    entry.workflowMemberships = []
    #expect(entry.workflowContextLabel == "Not on a workflow")
}

@Test
@MainActor
func threadCatalogStoreAppliesWorkflowMembershipsWithoutMaterializingOtherWorkflows() {
    let hostID = HostID(rawValue: "local")
    let currentRef = ThreadRef(hostID: hostID, threadID: "current", cwd: "/tmp/current")
    let otherRef = ThreadRef(hostID: hostID, threadID: "other", cwd: "/tmp/other")
    let searchRef = ThreadRef(hostID: hostID, threadID: "search-only", cwd: "/tmp/search")
    let currentNodeID = NodeID(rawValue: "current-node")
    let store = ThreadCatalogStore()
    store.upsert([
        ThreadCatalogEntry(threadRef: currentRef, hostName: "Mac", title: "Current"),
        ThreadCatalogEntry(threadRef: otherRef, hostName: "Mac", title: "Other"),
        ThreadCatalogEntry(threadRef: searchRef, hostName: "Mac", title: "Search"),
    ])

    store.applyWorkflowMemberships([
        currentRef.qualifiedID: [
            ThreadWorkflowMembership(
                workflowID: "active",
                workflowName: "Current Workflow",
                nodeID: currentNodeID,
                isActiveWorkflow: true
            ),
        ],
        otherRef.qualifiedID: [
            ThreadWorkflowMembership(
                workflowID: "other",
                workflowName: "Other Workflow",
                nodeID: NodeID(rawValue: "other-node"),
                isActiveWorkflow: false
            ),
        ],
    ])

    #expect(store.entry(for: currentRef)?.materializedNodeID == currentNodeID)
    #expect(store.entry(for: currentRef)?.workflowContextLabel == "Current workflow: Current Workflow")
    #expect(store.entry(for: otherRef)?.materializedNodeID == nil)
    #expect(store.entry(for: otherRef)?.workflowContextLabel == "Other Workflow")
    #expect(store.entry(for: searchRef)?.materializedNodeID == nil)
    #expect(store.entry(for: searchRef)?.workflowContextLabel == "Not on a workflow")
}

@Test
@MainActor
func threadCatalogStorePrimaryModesShowActiveAndFinishedNewestFirst() {
    let hostID = HostID(rawValue: "local")
    let activeOldRef = ThreadRef(hostID: hostID, threadID: "active-old", cwd: "/tmp/active-old")
    let activeNewRef = ThreadRef(hostID: hostID, threadID: "active-new", cwd: "/tmp/active-new")
    let completeRef = ThreadRef(hostID: hostID, threadID: "complete", cwd: "/tmp/complete")
    let failedRef = ThreadRef(hostID: hostID, threadID: "failed", cwd: "/tmp/failed")
    let archivedRef = ThreadRef(hostID: hostID, threadID: "archived", cwd: "/tmp/archived")
    let store = ThreadCatalogStore()

    #expect(ThreadInboxMode.primaryModes == [.active, .finished])

    store.upsert([
        ThreadCatalogEntry(threadRef: activeOldRef, hostName: "Mac", title: "Active Old", loadedStatus: .running, lastActivityAt: Date(timeIntervalSince1970: 10)),
        ThreadCatalogEntry(threadRef: activeNewRef, hostName: "Mac", title: "Active New", loadedStatus: .needsInput, lastActivityAt: Date(timeIntervalSince1970: 40)),
        ThreadCatalogEntry(threadRef: completeRef, hostName: "Mac", title: "Complete", loadedStatus: .complete, lastActivityAt: Date(timeIntervalSince1970: 30)),
        ThreadCatalogEntry(threadRef: failedRef, hostName: "Mac", title: "Failed", loadedStatus: .failed, lastActivityAt: Date(timeIntervalSince1970: 50)),
        ThreadCatalogEntry(threadRef: archivedRef, hostName: "Mac", title: "Archived", archived: true, loadedStatus: .complete, lastActivityAt: Date(timeIntervalSince1970: 60)),
    ])

    store.selectedMode = .active
    #expect(store.visibleEntries.map(\.id) == [activeNewRef.qualifiedID, activeOldRef.qualifiedID])

    store.selectedMode = .finished
    #expect(store.visibleEntries.map(\.id) == [failedRef.qualifiedID, completeRef.qualifiedID])
}

@Test
@MainActor
func threadCatalogStoreFiltersByWorkflowMembership() {
    let hostID = HostID(rawValue: "local")
    let activeRef = ThreadRef(hostID: hostID, threadID: "active", cwd: "/tmp/active")
    let otherRef = ThreadRef(hostID: hostID, threadID: "other", cwd: "/tmp/other")
    let offWorkflowRef = ThreadRef(hostID: hostID, threadID: "loose", cwd: "/tmp/loose")
    let store = ThreadCatalogStore()
    store.selectedMode = .recent
    store.upsert([
        ThreadCatalogEntry(threadRef: activeRef, hostName: "Mac", title: "Active", lastActivityAt: Date(timeIntervalSince1970: 30)),
        ThreadCatalogEntry(threadRef: otherRef, hostName: "Mac", title: "Other", lastActivityAt: Date(timeIntervalSince1970: 20)),
        ThreadCatalogEntry(threadRef: offWorkflowRef, hostName: "Mac", title: "Loose", lastActivityAt: Date(timeIntervalSince1970: 10)),
    ])
    store.applyWorkflowMemberships([
        activeRef.qualifiedID: [
            ThreadWorkflowMembership(
                workflowID: "active-workflow",
                workflowName: "Active Workflow",
                nodeID: NodeID(rawValue: "active-node"),
                isActiveWorkflow: true
            ),
        ],
        otherRef.qualifiedID: [
            ThreadWorkflowMembership(
                workflowID: "other-workflow",
                workflowName: "Other Workflow",
                nodeID: NodeID(rawValue: "other-node"),
                isActiveWorkflow: false
            ),
        ],
    ])

    #expect(store.visibleEntries.map(\.id) == [activeRef.qualifiedID, otherRef.qualifiedID, offWorkflowRef.qualifiedID])
    #expect(store.workflowFilterOptions.map(\.workflowID) == ["active-workflow", "other-workflow"])

    store.selectedWorkflowFilter = .onAnyWorkflow
    #expect(store.visibleEntries.map(\.id) == [activeRef.qualifiedID, otherRef.qualifiedID])

    store.selectedWorkflowFilter = .notOnWorkflow
    #expect(store.visibleEntries.map(\.id) == [offWorkflowRef.qualifiedID])

    store.selectedWorkflowFilter = .workflow("other-workflow")
    #expect(store.visibleEntries.map(\.id) == [otherRef.qualifiedID])
}

@Test
func appServerTurnTimelinePreservesTurnMetadata() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "host"), threadID: "thread-1", cwd: "/tmp")
    let messages = [
        ThreadMessage(id: "user-1", role: .user, text: "ping", createdAt: Date(timeIntervalSince1970: 10)),
        ThreadMessage(id: "assistant-1", role: .assistant, text: "pong", createdAt: Date(timeIntervalSince1970: 11)),
    ]
    let result: JSONValue = .object([
        "data": .array([
            .object([
                "id": .string("turn-1"),
                "status": .string("completed"),
                "itemsView": .string("full"),
                "startedAt": .number(10),
                "completedAt": .number(12),
                "durationMs": .number(2000),
                "items": .array([
                    .object(["id": .string("user-1")]),
                    .object(["id": .string("assistant-1")]),
                ]),
            ]),
        ]),
    ])

    let timeline = ThreadTurnTimeline.fromAppServerResult(result, threadRef: threadRef, messages: messages)

    #expect(timeline?.turns.first?.id == "turn-1")
    #expect(timeline?.turns.first?.status == .complete)
    #expect(timeline?.turns.first?.itemsView == .full)
    #expect(timeline?.turns.first?.durationMilliseconds == 2000)
    #expect(timeline?.turns.first?.items.map(\.id) == ["user-1", "assistant-1"])
}

@Test
func appServerTurnTimelineKeepsEmptyFailedAndRunningTurns() {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "host"), threadID: "thread-1", cwd: "/tmp")
    let result: JSONValue = .object([
        "data": .array([
            .object([
                "id": .string("failed-turn"),
                "status": .string("failed"),
                "itemsView": .string("notLoaded"),
                "startedAt": .number(10),
                "error": .object(["message": .string("boom")]),
                "items": .array([]),
            ]),
            .object([
                "id": .string("running-turn"),
                "status": .string("inProgress"),
                "itemsView": .string("summary"),
                "startedAt": .number(20),
                "items": .array([]),
            ]),
        ]),
    ])

    let timeline = ThreadTurnTimeline.fromAppServerResult(result, threadRef: threadRef, messages: [])

    #expect(timeline?.turns.count == 2)
    #expect(timeline?.turns[0].id == "failed-turn")
    #expect(timeline?.turns[0].status == .failed)
    #expect(timeline?.turns[0].itemsView == .notLoaded)
    #expect(timeline?.turns[0].error == "boom")
    #expect(timeline?.turns[0].items.isEmpty == true)
    #expect(timeline?.turns[1].status == .running)
    #expect(timeline?.turns[1].itemsView == .summary)
}

@Test
func appServerTurnTimelineBuildsExplicitImageArtifactItems() throws {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "host"), threadID: "thread-1", cwd: "/tmp")
    let result: JSONValue = .object([
        "data": .array([
            .object([
                "id": .string("turn-1"),
                "status": .string("completed"),
                "startedAt": .number(10),
                "items": .array([
                    .object([
                        "id": .string("img-1"),
                        "type": .string("imageGeneration"),
                        "status": .string("completed"),
                        "path": .string("/tmp/.codex/generated_images/thread-1/output.png"),
                        "revisedPrompt": .string("A lighthouse at dusk"),
                    ]),
                ]),
            ]),
        ]),
    ])

    let timeline = ThreadTurnTimeline.fromAppServerResult(result, threadRef: threadRef, messages: [])
    let item = try #require(timeline?.turns.first?.items.first)

    #expect(item.kind == .imageArtifact)
    #expect(item.message.role == .assistant)
    #expect(item.message.text.contains("Generated image"))
    #expect(item.effectiveAttachments.count == 1)
    #expect(item.effectiveAttachments.first?.kind == .image)
    #expect(item.effectiveAttachments.first?.sourcePath == "/tmp/.codex/generated_images/thread-1/output.png")
}

@Test
func appServerTurnTimelineBuildsExplicitFileArtifactItems() throws {
    let threadRef = ThreadRef(hostID: HostID(rawValue: "host"), threadID: "thread-1", cwd: "/tmp/project")
    let result: JSONValue = .object([
        "data": .array([
            .object([
                "id": .string("turn-1"),
                "status": .string("completed"),
                "startedAt": .number(10),
                "items": .array([
                    .object([
                        "id": .string("file-1"),
                        "type": .string("fileChange"),
                        "status": .string("completed"),
                        "changes": .object([
                            "Sources/App.swift": .object([
                                "type": .string("modified"),
                                "diff": .string("""
                                diff --git a/Sources/App.swift b/Sources/App.swift
                                --- a/Sources/App.swift
                                +++ b/Sources/App.swift
                                @@ -1 +1 @@
                                -let title = "Old"
                                +let title = "New"
                                """),
                            ]),
                        ]),
                    ]),
                ]),
            ]),
        ]),
    ])

    let timeline = ThreadTurnTimeline.fromAppServerResult(result, threadRef: threadRef, messages: [])
    let item = try #require(timeline?.turns.first?.items.first)

    #expect(item.kind == .fileArtifact)
    #expect(item.message.role == .tool)
    #expect(item.effectiveAttachments.count == 1)
    #expect(item.effectiveAttachments.first?.kind == .file)
    #expect(item.effectiveAttachments.first?.sourcePath == "Sources/App.swift")
    #expect(item.effectiveAttachments.first?.changeType == .modified)
    #expect(item.effectiveAttachments.first?.diffText?.contains("+let title") == true)
    #expect(item.effectiveAttachments.first?.isTrustedForAutoHydration == false)
}

private func catalogTestThreadNode(id: NodeID, title: String, threadRef: ThreadRef) -> CanvasNode {
    CanvasNode(
        id: id,
        kind: .codexThread,
        title: title,
        position: .zero,
        size: .thread,
        metadata: NodeMetadata(threadRef: threadRef)
    )
}
