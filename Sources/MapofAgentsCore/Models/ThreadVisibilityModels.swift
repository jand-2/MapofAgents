import Foundation
import Observation

public enum ThreadActiveFlag: String, Codable, CaseIterable, Sendable {
    case running
    case waitingOnApproval
    case waitingOnUserInput
    case failed
    case unread
    case loaded
}

public enum ThreadLiveStateTone: String, Codable, CaseIterable, Sendable {
    case idle
    case working
    case waiting
    case finished
    case failed
}

public struct ThreadLiveStateSummary: Hashable, Sendable {
    public var tone: ThreadLiveStateTone
    public var title: String
    public var detail: String?
    public var updatedAt: Date

    public init(
        tone: ThreadLiveStateTone,
        title: String,
        detail: String? = nil,
        updatedAt: Date
    ) {
        self.tone = tone
        self.title = title
        self.detail = detail
        self.updatedAt = updatedAt
    }
}

public struct ThreadRuntimeState: Codable, Identifiable, Hashable, Sendable {
    public var id: String { ThreadRef.qualifiedID(hostID: hostID, threadID: threadID) }
    public var hostID: HostID
    public var threadID: String
    public var status: ThreadRunStatus
    public var activeFlags: Set<ThreadActiveFlag>
    public var activeTurnID: String?
    public var activeItemIDs: [String]
    public var pendingRequestIDs: [String]
    public var liveAssistantText: String
    public var isUnread: Bool
    public var lastActivityAt: Date
    public var lastError: String?
    public var transcriptCursor: String?
    public var currentActivitySummary: String?

    public init(
        hostID: HostID,
        threadID: String,
        status: ThreadRunStatus = .idle,
        activeFlags: Set<ThreadActiveFlag> = [],
        activeTurnID: String? = nil,
        activeItemIDs: [String] = [],
        pendingRequestIDs: [String] = [],
        liveAssistantText: String = "",
        isUnread: Bool = false,
        lastActivityAt: Date = Date(),
        lastError: String? = nil,
        transcriptCursor: String? = nil,
        currentActivitySummary: String? = nil
    ) {
        self.hostID = hostID
        self.threadID = threadID
        self.status = status
        self.activeFlags = activeFlags
        self.activeTurnID = activeTurnID
        self.activeItemIDs = activeItemIDs
        self.pendingRequestIDs = pendingRequestIDs
        self.liveAssistantText = liveAssistantText
        self.isUnread = isUnread
        self.lastActivityAt = lastActivityAt
        self.lastError = lastError
        self.transcriptCursor = transcriptCursor
        self.currentActivitySummary = currentActivitySummary
    }

    public var needsAttention: Bool {
        status == .needsInput
            || status == .failed
            || activeFlags.contains(.waitingOnApproval)
            || activeFlags.contains(.waitingOnUserInput)
            || !pendingRequestIDs.isEmpty
    }

    public var contributesToCatalogRecency: Bool {
        status == .running
            || status == .needsInput
            || status == .failed
            || activeFlags.contains(.running)
            || activeFlags.contains(.waitingOnApproval)
            || activeFlags.contains(.waitingOnUserInput)
            || activeFlags.contains(.failed)
            || !activeItemIDs.isEmpty
            || !pendingRequestIDs.isEmpty
            || !liveAssistantText.isEmpty
            || lastError != nil
    }

    public mutating func apply(event: WorkflowEvent, markUnread: Bool) {
        activeTurnID = event.turnID ?? activeTurnID
        lastActivityAt = event.createdAt
        currentActivitySummary = event.summary.nilIfEmpty ?? currentActivitySummary
        switch event.kind {
        case .turnStarted:
            status = .running
            activeFlags.insert(.running)
            liveAssistantText = ""
            lastError = nil
            currentActivitySummary = event.summary.nilIfEmpty ?? "Turn started"
        case .turnCompleted:
            status = .complete
            activeFlags.remove(.running)
            activeFlags.remove(.waitingOnApproval)
            activeFlags.remove(.waitingOnUserInput)
            liveAssistantText = ""
            activeItemIDs = []
            pendingRequestIDs = []
            currentActivitySummary = event.summary.nilIfEmpty ?? "Turn completed"
            if markUnread {
                isUnread = true
                activeFlags.insert(.unread)
            }
        case .needsInput:
            status = .needsInput
            if event.method.localizedCaseInsensitiveContains("approval") {
                activeFlags.insert(.waitingOnApproval)
            } else {
                activeFlags.insert(.waitingOnUserInput)
            }
            isUnread = true
            activeFlags.insert(.unread)
            currentActivitySummary = event.summary.nilIfEmpty ?? currentActivitySummary
        case .failed:
            status = .failed
            activeFlags.remove(.running)
            activeFlags.remove(.waitingOnApproval)
            activeFlags.remove(.waitingOnUserInput)
            activeFlags.insert(.failed)
            pendingRequestIDs = []
            isUnread = true
            activeFlags.insert(.unread)
            lastError = event.summary
            currentActivitySummary = event.summary.nilIfEmpty ?? "Turn failed"
        case .threadCreated:
            currentActivitySummary = event.summary.nilIfEmpty ?? currentActivitySummary
        }
    }

    public mutating func prepareForTranscriptRead() {
        liveAssistantText = ""
        transcriptCursor = nil
    }

    public mutating func reconcileAfterLatestTranscriptRead(_ transcript: ThreadTranscript) {
        liveAssistantText = ""
        transcriptCursor = transcript.nextCursor

        guard let latestTurn = transcript.turnTimeline?.turns.max(by: { lhs, rhs in
            let lhsDate = lhs.completedAt ?? lhs.startedAt
            let rhsDate = rhs.completedAt ?? rhs.startedAt
            if lhsDate == rhsDate {
                return lhs.id < rhs.id
            }
            return lhsDate < rhsDate
        }) else {
            return
        }

        activeTurnID = latestTurn.id
        lastActivityAt = max(lastActivityAt, latestTurn.completedAt ?? latestTurn.startedAt)

        let status = latestTurn.status == .unknown && latestTurn.completedAt != nil
            ? ThreadRunStatus.complete
            : latestTurn.status

        switch status {
        case .running:
            self.status = .running
            activeFlags.insert(.running)
            lastError = nil
            currentActivitySummary = currentActivitySummary ?? "Turn running"
        case .needsInput:
            self.status = .needsInput
            activeFlags.remove(.running)
            activeFlags.insert(.waitingOnUserInput)
            currentActivitySummary = currentActivitySummary ?? "Waiting for input"
        case .failed:
            self.status = .failed
            activeFlags.remove(.running)
            activeFlags.insert(.failed)
            lastError = latestTurn.error ?? lastError
            currentActivitySummary = latestTurn.error ?? currentActivitySummary ?? "Turn failed"
        case .complete:
            self.status = .complete
            activeFlags.remove(.running)
            activeFlags.remove(.waitingOnApproval)
            activeFlags.remove(.waitingOnUserInput)
            activeFlags.remove(.failed)
            activeItemIDs = []
            lastError = nil
            currentActivitySummary = currentActivitySummary ?? "Turn completed"
        case .idle, .unknown:
            if self.status == .running || activeFlags.contains(.running) {
                self.status = .idle
                activeFlags.remove(.running)
            }
        }
    }

    public mutating func appendAssistantDelta(_ delta: String, at date: Date = Date()) {
        guard !delta.isEmpty else { return }
        status = .running
        activeFlags.insert(.running)
        liveAssistantText += delta
        lastActivityAt = date
        currentActivitySummary = "Assistant is responding"
    }

    public mutating func applyAttentionRequest(_ request: RuntimeAttentionRequest) {
        if !pendingRequestIDs.contains(request.id) {
            pendingRequestIDs.append(request.id)
        }
        status = .needsInput
        if request.method.localizedCaseInsensitiveContains("approval") {
            activeFlags.insert(.waitingOnApproval)
        } else {
            activeFlags.insert(.waitingOnUserInput)
        }
        isUnread = true
        activeFlags.insert(.unread)
        activeTurnID = request.turnID ?? activeTurnID
        lastActivityAt = request.createdAt
        currentActivitySummary = request.summary
    }

    public mutating func resolveAttentionRequest(_ requestID: String) {
        pendingRequestIDs.removeAll { $0 == requestID || $0.hasSuffix("::\(requestID)") }
        if pendingRequestIDs.isEmpty {
            activeFlags.remove(.waitingOnApproval)
            activeFlags.remove(.waitingOnUserInput)
            if status == .needsInput {
                status = activeFlags.contains(.running) ? .running : .idle
            }
            currentActivitySummary = status == .running ? "Approval resolved; turn running" : "Approval resolved"
        }
    }

    public mutating func markRead(_ isRead: Bool = true) {
        isUnread = !isRead
        if isRead {
            activeFlags.remove(.unread)
        } else {
            activeFlags.insert(.unread)
        }
    }

    public mutating func recordItemActivity(method: String, itemID: String, at date: Date = Date()) {
        let lowercasedMethod = method.lowercased()
        if lowercasedMethod.contains("completed") || lowercasedMethod.contains("finished") {
            activeItemIDs.removeAll { $0 == itemID }
            currentActivitySummary = itemActivityCompletionSummary(for: method)
        } else if lowercasedMethod.contains("started")
            || lowercasedMethod.contains("created")
            || lowercasedMethod.contains("begin") {
            if !activeItemIDs.contains(itemID) {
                activeItemIDs.append(itemID)
            }
            status = .running
            activeFlags.insert(.running)
            currentActivitySummary = itemActivityStartSummary(for: method)
        } else {
            currentActivitySummary = itemActivityUpdateSummary(for: method)
        }
        lastActivityAt = date
    }

    public var liveStateSummary: ThreadLiveStateSummary {
        if !pendingRequestIDs.isEmpty || activeFlags.contains(.waitingOnApproval) {
            return ThreadLiveStateSummary(
                tone: .waiting,
                title: "Waiting for approval",
                detail: currentActivitySummary?.nilIfEmpty,
                updatedAt: lastActivityAt
            )
        }

        if activeFlags.contains(.waitingOnUserInput) || status == .needsInput {
            return ThreadLiveStateSummary(
                tone: .waiting,
                title: "Waiting for input",
                detail: currentActivitySummary?.nilIfEmpty,
                updatedAt: lastActivityAt
            )
        }

        if status == .failed || activeFlags.contains(.failed) {
            return ThreadLiveStateSummary(
                tone: .failed,
                title: "Failed",
                detail: lastError?.nilIfEmpty ?? currentActivitySummary?.nilIfEmpty,
                updatedAt: lastActivityAt
            )
        }

        if status == .running || activeFlags.contains(.running) || !activeItemIDs.isEmpty || !liveAssistantText.isEmpty {
            return ThreadLiveStateSummary(
                tone: .working,
                title: currentActivitySummary?.nilIfEmpty ?? (!activeItemIDs.isEmpty ? "Running tool" : "Working"),
                detail: !activeItemIDs.isEmpty ? "\(activeItemIDs.count) active item\(activeItemIDs.count == 1 ? "" : "s")" : nil,
                updatedAt: lastActivityAt
            )
        }

        if status == .complete {
            return ThreadLiveStateSummary(
                tone: .finished,
                title: "Finished",
                detail: currentActivitySummary?.nilIfEmpty,
                updatedAt: lastActivityAt
            )
        }

        return ThreadLiveStateSummary(
            tone: .idle,
            title: "Idle",
            detail: currentActivitySummary?.nilIfEmpty,
            updatedAt: lastActivityAt
        )
    }

    private func itemActivityStartSummary(for method: String) -> String {
        let normalized = method.lowercased()
        if normalized.contains("command") {
            return "Running command"
        }
        if normalized.contains("tool") {
            return "Running tool"
        }
        if normalized.contains("image") {
            return "Generating image"
        }
        if normalized.contains("file") {
            return "Working with files"
        }
        return "Running item"
    }

    private func itemActivityCompletionSummary(for method: String) -> String {
        let normalized = method.lowercased()
        if normalized.contains("command") {
            return "Command returned"
        }
        if normalized.contains("tool") {
            return "Tool returned"
        }
        if normalized.contains("image") {
            return "Image ready"
        }
        if normalized.contains("file") {
            return "File operation finished"
        }
        return "Item finished"
    }

    private func itemActivityUpdateSummary(for method: String) -> String {
        let normalized = method.lowercased()
        if normalized.contains("command") {
            return "Command updated"
        }
        if normalized.contains("tool") {
            return "Tool updated"
        }
        if normalized.contains("image") {
            return "Image generation updated"
        }
        if normalized.contains("file") {
            return "File operation updated"
        }
        return "Activity updated"
    }
}

public struct ThreadReadState: Codable, Identifiable, Hashable, Sendable {
    public var id: String { ThreadRef.qualifiedID(hostID: hostID, threadID: threadID) }
    public var hostID: HostID
    public var threadID: String
    public var lastSeenAt: Date

    public init(hostID: HostID, threadID: String, lastSeenAt: Date) {
        self.hostID = hostID
        self.threadID = threadID
        self.lastSeenAt = lastSeenAt
    }

    public init(threadRef: ThreadRef, lastSeenAt: Date) {
        self.init(hostID: threadRef.hostID, threadID: threadRef.threadID, lastSeenAt: lastSeenAt)
    }
}

public enum ThreadInboxMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case active
    case finished
    case needsYou
    case unread
    case recent
    case search
    case archived

    public var id: String { rawValue }

    public static let primaryModes: [ThreadInboxMode] = [.active, .finished]

    public var displayName: String {
        switch self {
        case .active:
            return "Active"
        case .finished:
            return "Finished"
        case .needsYou:
            return "Needs You"
        case .unread:
            return "Unread"
        case .recent:
            return "Recent"
        case .search:
            return "Search"
        case .archived:
            return "Archived"
        }
    }
}

public enum ThreadInboxWorkflowFilter: Hashable, Codable, Identifiable, Sendable {
    case all
    case onAnyWorkflow
    case notOnWorkflow
    case workflow(String)

    public var id: String {
        switch self {
        case .all:
            return "all"
        case .onAnyWorkflow:
            return "on-any-workflow"
        case .notOnWorkflow:
            return "not-on-workflow"
        case .workflow(let workflowID):
            return "workflow::\(workflowID)"
        }
    }

    public func includes(_ entry: ThreadCatalogEntry) -> Bool {
        switch self {
        case .all:
            return true
        case .onAnyWorkflow:
            return !entry.workflowMemberships.isEmpty
        case .notOnWorkflow:
            return entry.workflowMemberships.isEmpty
        case .workflow(let workflowID):
            return entry.workflowMemberships.contains { $0.workflowID == workflowID }
        }
    }
}

public struct ThreadInboxWorkflowFilterOption: Identifiable, Hashable, Sendable {
    public var workflowID: String
    public var workflowName: String
    public var count: Int
    public var isActiveWorkflow: Bool

    public var id: String { workflowID }

    public init(
        workflowID: String,
        workflowName: String,
        count: Int,
        isActiveWorkflow: Bool
    ) {
        self.workflowID = workflowID
        self.workflowName = workflowName
        self.count = count
        self.isActiveWorkflow = isActiveWorkflow
    }
}

public struct ThreadWorkflowMembership: Codable, Identifiable, Hashable, Sendable {
    public var workflowID: String
    public var workflowName: String
    public var nodeID: NodeID?
    public var isActiveWorkflow: Bool

    public var id: String {
        "\(workflowID)::\(nodeID?.rawValue ?? "unmaterialized")"
    }

    public init(
        workflowID: String,
        workflowName: String,
        nodeID: NodeID? = nil,
        isActiveWorkflow: Bool = false
    ) {
        self.workflowID = workflowID
        self.workflowName = workflowName
        self.nodeID = nodeID
        self.isActiveWorkflow = isActiveWorkflow
    }

    public static func map(
        workflows: [WorkflowRecord],
        graphsByWorkflowID: [String: AgentGraph],
        activeWorkflowID: String?
    ) -> [String: [ThreadWorkflowMembership]] {
        var namesByID: [String: String] = [:]
        for workflow in workflows where namesByID[workflow.id] == nil {
            namesByID[workflow.id] = workflow.name
        }
        var result: [String: [ThreadWorkflowMembership]] = [:]

        for (workflowID, graph) in graphsByWorkflowID {
            let workflowName = namesByID[workflowID] ?? graph.title
            namesByID[workflowID] = workflowName
            for node in graph.nodes.values where node.kind == .codexThread {
                guard let threadRef = node.metadata.threadRef else { continue }
                let membership = ThreadWorkflowMembership(
                    workflowID: workflowID,
                    workflowName: workflowName,
                    nodeID: node.id,
                    isActiveWorkflow: workflowID == activeWorkflowID
                )
                result[threadRef.qualifiedID, default: []].append(membership)
            }
        }

        return result.mapValues { memberships in
            memberships.sorted { lhs, rhs in
                if lhs.isActiveWorkflow != rhs.isActiveWorkflow {
                    return lhs.isActiveWorkflow
                }
                return lhs.workflowName.localizedCaseInsensitiveCompare(rhs.workflowName) == .orderedAscending
            }
        }
    }

    public static func activeMap(
        graph: AgentGraph,
        workflowID: String?,
        workflowName: String?
    ) -> [String: [ThreadWorkflowMembership]] {
        guard let workflowID else { return [:] }
        let name = workflowName?.nilIfEmpty ?? graph.title
        return map(
            workflows: [WorkflowRecord(id: workflowID, name: name)],
            graphsByWorkflowID: [workflowID: graph],
            activeWorkflowID: workflowID
        )
    }

    public static func merging(
        _ stored: [String: [ThreadWorkflowMembership]],
        active activeMap: [String: [ThreadWorkflowMembership]]
    ) -> [String: [ThreadWorkflowMembership]] {
        var merged = stored.mapValues { memberships in
            memberships.filter { !$0.isActiveWorkflow }
        }
        for (key, memberships) in activeMap {
            merged[key, default: []].append(contentsOf: memberships)
        }
        return merged.mapValues { memberships in
            Array(Dictionary(grouping: memberships, by: \.id).compactMap { $0.value.first })
                .sorted { lhs, rhs in
                    if lhs.isActiveWorkflow != rhs.isActiveWorkflow {
                        return lhs.isActiveWorkflow
                    }
                    return lhs.workflowName.localizedCaseInsensitiveCompare(rhs.workflowName) == .orderedAscending
                }
        }
    }
}

public struct ThreadCatalogEntry: Codable, Identifiable, Hashable, Sendable {
    public var id: String { threadRef.qualifiedID }
    public var threadRef: ThreadRef
    public var hostName: String
    public var title: String
    public var preview: String
    public var source: String?
    public var archived: Bool
    public var loadedStatus: ThreadRunStatus
    public var lastActivityAt: Date
    public var unread: Bool
    public var pendingRequestCount: Int
    public var materializedNodeID: NodeID?
    public var lastError: String?
    public var latestEventSummary: String?
    public var model: String?
    public var reasoningEffort: String?
    public var threadKind: CodexThreadNodeKind?
    public var workflowMemberships: [ThreadWorkflowMembership]

    public init(
        threadRef: ThreadRef,
        hostName: String,
        title: String? = nil,
        preview: String = "",
        source: String? = nil,
        archived: Bool = false,
        loadedStatus: ThreadRunStatus = .idle,
        lastActivityAt: Date = Date(),
        unread: Bool = false,
        pendingRequestCount: Int = 0,
        materializedNodeID: NodeID? = nil,
        lastError: String? = nil,
        latestEventSummary: String? = nil,
        model: String? = nil,
        reasoningEffort: String? = nil,
        threadKind: CodexThreadNodeKind? = .thread,
        workflowMemberships: [ThreadWorkflowMembership] = []
    ) {
        self.threadRef = threadRef
        self.hostName = hostName
        self.title = title?.nilIfEmpty ?? threadRef.name?.nilIfEmpty ?? "Codex thread"
        self.preview = preview
        self.source = source
        self.archived = archived
        self.loadedStatus = loadedStatus
        self.lastActivityAt = lastActivityAt
        self.unread = unread
        self.pendingRequestCount = pendingRequestCount
        self.materializedNodeID = materializedNodeID
        self.lastError = lastError
        self.latestEventSummary = latestEventSummary
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.threadKind = threadKind
        self.workflowMemberships = workflowMemberships
    }

    public var needsAttention: Bool {
        pendingRequestCount > 0 || loadedStatus == .needsInput || loadedStatus == .failed
    }

    public var isActive: Bool {
        loadedStatus == .running || loadedStatus == .needsInput
    }

    public var activeWorkflowMembership: ThreadWorkflowMembership? {
        workflowMemberships.first { $0.isActiveWorkflow }
    }

    public var activeWorkflowNodeID: NodeID? {
        activeWorkflowMembership?.nodeID
    }

    public var hasActiveWorkflowMembership: Bool {
        activeWorkflowMembership != nil
    }

    public var workflowContextLabel: String {
        if let active = activeWorkflowMembership {
            if workflowMemberships.count > 1 {
                return "Current workflow: \(active.workflowName) + \(workflowMemberships.count - 1) more"
            }
            return "Current workflow: \(active.workflowName)"
        }

        if workflowMemberships.count == 1, let membership = workflowMemberships.first {
            return membership.workflowName
        }

        if workflowMemberships.count > 1 {
            return "Multiple workflows"
        }

        return "Not on a workflow"
    }

    public var liveStateSummary: ThreadLiveStateSummary {
        if pendingRequestCount > 0 || loadedStatus == .needsInput {
            return ThreadLiveStateSummary(
                tone: .waiting,
                title: pendingRequestCount > 0 ? "Waiting for approval" : "Waiting for input",
                detail: latestEventSummary?.nilIfEmpty,
                updatedAt: lastActivityAt
            )
        }

        if loadedStatus == .failed {
            return ThreadLiveStateSummary(
                tone: .failed,
                title: "Failed",
                detail: lastError?.nilIfEmpty ?? latestEventSummary?.nilIfEmpty,
                updatedAt: lastActivityAt
            )
        }

        if loadedStatus == .running {
            return ThreadLiveStateSummary(
                tone: .working,
                title: latestEventSummary?.nilIfEmpty ?? "Working",
                detail: preview.nilIfEmpty,
                updatedAt: lastActivityAt
            )
        }

        if loadedStatus == .complete {
            return ThreadLiveStateSummary(
                tone: .finished,
                title: "Finished",
                detail: latestEventSummary?.nilIfEmpty,
                updatedAt: lastActivityAt
            )
        }

        return ThreadLiveStateSummary(
            tone: .idle,
            title: "Idle",
            detail: latestEventSummary?.nilIfEmpty ?? preview.nilIfEmpty,
            updatedAt: lastActivityAt
        )
    }

    public func applying(runtimeState: ThreadRuntimeState?) -> ThreadCatalogEntry {
        guard let runtimeState else { return self }
        var copy = self
        copy.loadedStatus = runtimeState.status
        copy.unread = runtimeState.isUnread
        copy.pendingRequestCount = runtimeState.pendingRequestIDs.count
        if runtimeState.contributesToCatalogRecency {
            copy.lastActivityAt = max(lastActivityAt, runtimeState.lastActivityAt)
        }
        copy.lastError = runtimeState.lastError ?? lastError
        copy.latestEventSummary = runtimeState.currentActivitySummary ?? latestEventSummary
        return copy
    }

    public func applying(readState: ThreadReadState?) -> ThreadCatalogEntry {
        guard let readState, lastActivityAt <= readState.lastSeenAt else {
            return self
        }
        var copy = self
        copy.unread = false
        return copy
    }

    public static func appServerThread(
        from value: JSONValue,
        hostID: HostID,
        hostName: String,
        materializedNodeID: NodeID? = nil
    ) -> ThreadCatalogEntry? {
        guard let threadID = value["id"]?.stringValue ?? value["threadId"]?.stringValue ?? value["threadID"]?.stringValue else {
            return nil
        }

        let cwd = value["cwd"]?.stringValue
            ?? value["workingDirectory"]?.stringValue
            ?? value["working_directory"]?.stringValue
            ?? ""
        let title = value["name"]?.stringValue
            ?? value["title"]?.stringValue
            ?? value["preview"]?.stringValue
        let preview = value["preview"]?.stringValue
            ?? value["summary"]?.stringValue
            ?? value["lastMessage"]?.stringValue
            ?? ""
        let threadRef = ThreadRef(hostID: hostID, threadID: threadID, cwd: cwd, name: title)
        let source = value["source"]?.stringValue ?? value["thread_source"]?.stringValue
        return ThreadCatalogEntry(
            threadRef: threadRef,
            hostName: hostName,
            title: title,
            preview: preview,
            source: source,
            archived: value["archived"]?.boolValue ?? false,
            loadedStatus: Self.status(from: value),
            lastActivityAt: Self.date(from: value) ?? Date(),
            unread: false,
            materializedNodeID: materializedNodeID,
            model: value["model"]?.stringValue,
            reasoningEffort: value["reasoningEffort"]?.stringValue ?? value["effort"]?.stringValue,
            threadKind: Self.threadKind(from: value)
        )
    }

    public static func appServerSearchResult(
        from value: JSONValue,
        hostID: HostID,
        hostName: String,
        materializedNodeID: NodeID? = nil
    ) -> ThreadCatalogEntry? {
        let threadValue = value["thread"] ?? value["item"] ?? value
        guard var entry = appServerThread(
            from: threadValue,
            hostID: hostID,
            hostName: hostName,
            materializedNodeID: materializedNodeID
        ) else {
            return nil
        }

        if let snippet = value["snippet"]?.stringValue?.nilIfEmpty
            ?? value["preview"]?.stringValue?.nilIfEmpty
            ?? value["summary"]?.stringValue?.nilIfEmpty {
            entry.preview = snippet
        }
        entry.source = value["source"]?.stringValue ?? entry.source ?? "search"
        return entry
    }

    public static func loadedThreadIDs(from result: JSONValue) -> [String] {
        let values = result["data"]?.arrayValue ?? result["threads"]?.arrayValue ?? []
        var seen = Set<String>()
        return values.compactMap { value in
            let threadID = value.stringValue
                ?? value["id"]?.stringValue
                ?? value["threadId"]?.stringValue
                ?? value["threadID"]?.stringValue
            guard let threadID, seen.insert(threadID.lowercased()).inserted else {
                return nil
            }
            return threadID
        }
    }

    private static func status(from value: JSONValue) -> ThreadRunStatus {
        if let status = structuredStatus(from: value["status"] ?? value["loadedStatus"] ?? value["loaded_status"]) {
            return status
        }

        let raw = value["status"]?.stringValue
            ?? value["loadedStatus"]?.stringValue
            ?? value["loaded_status"]?.stringValue
            ?? value["state"]?.stringValue
            ?? ""
        let lowercased = raw.lowercased()
        if lowercased.contains("approval") || lowercased.contains("input") || lowercased.contains("waiting") {
            return .needsInput
        }
        if lowercased.contains("running") || lowercased.contains("active") {
            return .running
        }
        if lowercased.contains("fail") || lowercased.contains("error") {
            return .failed
        }
        if lowercased.contains("complete") || lowercased.contains("done") {
            return .complete
        }
        return .idle
    }

    private static func threadKind(from value: JSONValue) -> CodexThreadNodeKind {
        let raw = value["threadKind"]?.stringValue
            ?? value["thread_kind"]?.stringValue
            ?? value["threadSource"]?.stringValue
            ?? value["thread_source"]?.stringValue
            ?? value["source"]?.stringValue
            ?? ""
        return raw.localizedCaseInsensitiveContains("subagent") ? .subagent : .thread
    }

    private static func structuredStatus(from value: JSONValue?) -> ThreadRunStatus? {
        guard let value, let object = value.objectValue else { return nil }
        let type = (object["type"]?.stringValue ?? object["status"]?.stringValue ?? "")
            .lowercased()
        let flags = (object["activeFlags"]?.arrayValue
            ?? object["active_flags"]?.arrayValue
            ?? object["flags"]?.arrayValue
            ?? [])
            .compactMap(\.stringValue)
            .map { $0.lowercased() }

        switch type {
        case "active", "running", "inprogress", "in_progress":
            if flags.contains(where: { $0.contains("approval") || $0.contains("userinput") || $0.contains("user_input") }) {
                return .needsInput
            }
            return .running
        case "idle", "notloaded", "not_loaded":
            return .idle
        case "completed", "complete", "done":
            return .complete
        case "systemerror", "system_error", "failed", "error":
            return .failed
        default:
            return nil
        }
    }

    private static func date(from value: JSONValue) -> Date? {
        for key in ["updatedAt", "updated_at", "lastActivityAt", "last_activity_at", "createdAt", "created_at"] {
            if let string = value[key]?.stringValue {
                return parsedDate(from: string)
            }
            if let seconds = value[key]?.doubleValue {
                return Date(timeIntervalSince1970: seconds)
            }
        }
        return nil
    }

    private static func parsedDate(from string: String) -> Date? {
        let fractionalFormatter = DateFormatter()
        fractionalFormatter.locale = Locale(identifier: "en_US_POSIX")
        fractionalFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        if let date = fractionalFormatter.date(from: string) {
            return date
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: string) {
            return date
        }

        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        return fallbackFormatter.date(from: string)
    }
}

public enum ThreadTurnItemKind: String, Codable, CaseIterable, Sendable {
    case userMessage
    case assistantMessage
    case reasoning
    case tool
    case artifact
    case imageArtifact
    case fileArtifact
    case diffArtifact
    case system
}

public struct ThreadTurnItem: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var kind: ThreadTurnItemKind
    public var message: ThreadMessage
    public var attachments: [ThreadMessageAttachment]

    public init(
        id: String,
        kind: ThreadTurnItemKind,
        message: ThreadMessage,
        attachments: [ThreadMessageAttachment] = []
    ) {
        self.id = id
        self.kind = kind
        self.message = message
        self.attachments = attachments
    }

    public var effectiveAttachments: [ThreadMessageAttachment] {
        attachments.isEmpty ? message.attachments : attachments
    }
}

public enum ThreadTurnItemsView: String, Codable, CaseIterable, Sendable {
    case notLoaded
    case summary
    case full
}

public struct ThreadTurn: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var status: ThreadRunStatus
    public var startedAt: Date
    public var completedAt: Date?
    public var error: String?
    public var itemsView: ThreadTurnItemsView
    public var durationMilliseconds: Int?
    public var items: [ThreadTurnItem]

    public init(
        id: String,
        status: ThreadRunStatus,
        startedAt: Date,
        completedAt: Date? = nil,
        error: String? = nil,
        itemsView: ThreadTurnItemsView = .full,
        durationMilliseconds: Int? = nil,
        items: [ThreadTurnItem]
    ) {
        self.id = id
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.error = error
        self.itemsView = itemsView
        self.durationMilliseconds = durationMilliseconds
        self.items = items
    }

    public var duration: TimeInterval? {
        if let durationMilliseconds {
            return Double(durationMilliseconds) / 1000
        }
        guard let completedAt else { return nil }
        return completedAt.timeIntervalSince(startedAt)
    }
}

public struct ThreadTurnTimeline: Codable, Hashable, Sendable {
    public var threadRef: ThreadRef
    public var turns: [ThreadTurn]

    public init(threadRef: ThreadRef, turns: [ThreadTurn]) {
        self.threadRef = threadRef
        self.turns = turns
    }

    public func reconciled(with transcript: ThreadTranscript) -> ThreadTurnTimeline {
        var messagesByID: [String: ThreadMessage] = [:]
        for message in transcript.messages {
            messagesByID[message.id] = message
        }
        var usedMessageIDs = Set<String>()
        var reconciledTurns = turns.map { turn in
            var copy = turn
            copy.items = turn.items.compactMap { item in
                let message = messagesByID[item.message.id] ?? messagesByID[item.id]
                guard let message else {
                    guard !item.effectiveAttachments.isEmpty else {
                        return nil
                    }
                    return item
                }
                usedMessageIDs.insert(message.id)
                return ThreadTurnItem(
                    id: item.effectiveAttachments.isEmpty ? message.id : item.id,
                    kind: item.effectiveAttachments.isEmpty ? ThreadTurnItemKind(message) : item.kind,
                    message: message,
                    attachments: item.effectiveAttachments
                )
            }
            copy.items = Self.sortedTurnItems(copy.items)
            if let earliest = copy.items.map(\.message.createdAt).min() {
                copy.startedAt = min(copy.startedAt, earliest)
            }
            if let latest = copy.items.map(\.message.createdAt).max() {
                copy.completedAt = copy.completedAt.map { max($0, latest) } ?? latest
            }
            return copy
        }

        let missingMessages = transcript.messages
            .filter { !usedMessageIDs.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id < rhs.id
                }
                return lhs.createdAt < rhs.createdAt
            }

        for message in missingMessages {
            let item = ThreadTurnItem(
                id: message.id,
                kind: ThreadTurnItemKind(message),
                message: message,
                attachments: message.attachments
            )
            if let index = reconciledTurns.nearestTurnIndex(containing: message.createdAt) {
                reconciledTurns[index].items.append(item)
                reconciledTurns[index].items = Self.sortedTurnItems(reconciledTurns[index].items)
                reconciledTurns[index].startedAt = min(reconciledTurns[index].startedAt, message.createdAt)
                if let completedAt = reconciledTurns[index].completedAt {
                    reconciledTurns[index].completedAt = max(completedAt, message.createdAt)
                } else {
                    reconciledTurns[index].completedAt = message.createdAt
                }
            } else {
                reconciledTurns.append(
                    ThreadTurn(
                        id: "\(transcript.threadRef.qualifiedID)-turn-\(reconciledTurns.count + 1)",
                        status: .complete,
                        startedAt: message.createdAt,
                        completedAt: message.createdAt,
                        items: [item]
                    )
                )
            }
        }

        reconciledTurns.sort { lhs, rhs in
            if lhs.startedAt == rhs.startedAt {
                return lhs.id < rhs.id
            }
            return lhs.startedAt < rhs.startedAt
        }
        return ThreadTurnTimeline(threadRef: transcript.threadRef, turns: reconciledTurns)
    }

    public static func fromTranscript(_ transcript: ThreadTranscript) -> ThreadTurnTimeline {
        var turns: [ThreadTurn] = []
        var currentItems: [ThreadTurnItem] = []
        var currentStart: Date?
        var currentIndex = 1

        func flush(status: ThreadRunStatus = .complete) {
            guard !currentItems.isEmpty else { return }
            let start = currentStart ?? currentItems.first?.message.createdAt ?? Date()
            let completed = currentItems.last?.message.createdAt
            turns.append(
                ThreadTurn(
                    id: "\(transcript.threadRef.qualifiedID)-turn-\(currentIndex)",
                    status: status,
                    startedAt: start,
                    completedAt: completed,
                    items: currentItems
                )
            )
            currentIndex += 1
            currentItems = []
            currentStart = nil
        }

        for message in transcript.messages.sorted(by: { $0.createdAt < $1.createdAt }) {
            if message.role == .user {
                flush()
                currentStart = message.createdAt
            } else if currentStart == nil {
                currentStart = message.createdAt
            }

            currentItems.append(
                ThreadTurnItem(
                    id: message.id,
                    kind: ThreadTurnItemKind(message),
                    message: message,
                    attachments: message.attachments
                )
            )
        }

        flush()
        return ThreadTurnTimeline(threadRef: transcript.threadRef, turns: turns)
    }

    public static func fromAppServerResult(
        _ result: JSONValue,
        threadRef: ThreadRef,
        messages: [ThreadMessage]
    ) -> ThreadTurnTimeline? {
        let turnValues = result["data"]?.arrayValue ?? []
        guard !turnValues.isEmpty else { return nil }

        let messagesByID = Dictionary(grouping: messages, by: \.id)
        let turns = turnValues.enumerated().compactMap { index, value -> ThreadTurn? in
            let id = value["id"]?.stringValue ?? "\(threadRef.qualifiedID)-turn-\(index + 1)"
            let items = (value["items"]?.arrayValue ?? []).enumerated().flatMap { itemIndex, itemValue -> [ThreadTurnItem] in
                let itemID = appServerItemID(from: itemValue) ?? "\(id)-item-\(itemIndex + 1)"
                let matches = messagesByID[itemID] ?? messages.filter { $0.id.hasPrefix(itemID) }
                if let explicitItem = explicitAppServerTurnItem(
                    from: itemValue,
                    itemID: itemID,
                    threadRef: threadRef,
                    fallbackDate: date(from: itemValue["createdAt"] ?? itemValue["created_at"]) ?? date(from: value["startedAt"] ?? value["started_at"]),
                    matchedMessage: matches.first
                ) {
                    return [explicitItem]
                }

                return matches.map {
                    ThreadTurnItem(
                        id: $0.id,
                        kind: ThreadTurnItemKind($0),
                        message: $0,
                        attachments: $0.attachments
                    )
                }
            }

            return ThreadTurn(
                id: id,
                status: ThreadRunStatus(appServerTurnStatus: value["status"]?.stringValue),
                startedAt: date(from: value["startedAt"] ?? value["started_at"]) ?? items.first?.message.createdAt ?? Date(),
                completedAt: date(from: value["completedAt"] ?? value["completed_at"]),
                error: value["error"]?["message"]?.stringValue ?? value["error"]?.stringValue,
                itemsView: ThreadTurnItemsView(appServerValue: value["itemsView"]?.stringValue ?? value["items_view"]?.stringValue),
                durationMilliseconds: value["durationMs"]?.intValue ?? value["duration_ms"]?.intValue,
                items: items
            )
        }

        guard !turns.isEmpty else { return nil }
        return ThreadTurnTimeline(
            threadRef: threadRef,
            turns: turns.sorted { lhs, rhs in
                if lhs.startedAt == rhs.startedAt {
                    return lhs.id < rhs.id
                }
                return lhs.startedAt < rhs.startedAt
            }
        )
    }

    private static func appServerItemID(from value: JSONValue) -> String? {
        for key in ["id", "call_id", "callId"] {
            guard let rawValue = value[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawValue.isEmpty
            else {
                continue
            }
            return rawValue
        }
        return nil
    }

    private static func explicitAppServerTurnItem(
        from value: JSONValue,
        itemID: String,
        threadRef: ThreadRef,
        fallbackDate: Date?,
        matchedMessage: ThreadMessage?
    ) -> ThreadTurnItem? {
        guard case .object(let object) = value,
              let rawType = object["type"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawType.isEmpty else {
            return nil
        }

        let createdAt = fallbackDate ?? Date()
        let lowercasedType = rawType.lowercased()

        if lowercasedType == "imagegeneration" || lowercasedType == "image_generation" || lowercasedType == "imageview" {
            let attachments = explicitImageAttachments(in: object, itemID: itemID, threadRef: threadRef, createdAt: createdAt)
            guard !attachments.isEmpty else { return nil }
            let message = matchedMessage ?? ThreadMessage(
                id: itemID,
                role: .assistant,
                text: explicitImageMessageText(for: lowercasedType, object: object, itemID: itemID),
                createdAt: createdAt
            )
            return ThreadTurnItem(id: itemID, kind: .imageArtifact, message: message, attachments: attachments)
        }

        if lowercasedType == "patch_apply_end" {
            let attachments = explicitPatchAttachments(in: object, itemID: itemID, threadRef: threadRef, createdAt: createdAt)
            guard !attachments.isEmpty else { return nil }
            let message = matchedMessage ?? ThreadMessage(
                id: itemID,
                role: .tool,
                text: "patch_apply_end",
                createdAt: createdAt
            )
            return ThreadTurnItem(id: itemID, kind: preferredArtifactKind(for: attachments), message: message, attachments: attachments)
        }

        if lowercasedType.contains("filechange") || lowercasedType.contains("file_change") || lowercasedType.contains("file change") {
            let attachments = explicitFileChangeAttachments(in: object, itemID: itemID, threadRef: threadRef, createdAt: createdAt)
            guard !attachments.isEmpty else { return nil }
            let message = matchedMessage ?? ThreadMessage(
                id: itemID,
                role: .tool,
                text: "file_change",
                createdAt: createdAt
            )
            return ThreadTurnItem(id: itemID, kind: preferredArtifactKind(for: attachments), message: message, attachments: attachments)
        }

        return nil
    }

    private static func date(from value: JSONValue?) -> Date? {
        if let seconds = value?.doubleValue {
            if seconds > 10_000_000_000 {
                return Date(timeIntervalSince1970: seconds / 1000)
            }
            return Date(timeIntervalSince1970: seconds)
        }
        if let string = value?.stringValue {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: string) {
                return date
            }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            return plain.date(from: string)
        }
        return nil
    }

    private static func sortedTurnItems(_ items: [ThreadTurnItem]) -> [ThreadTurnItem] {
        items.enumerated().sorted { lhs, rhs in
            let lhsIsUser = lhs.element.kind == .userMessage
            let rhsIsUser = rhs.element.kind == .userMessage
            if lhsIsUser != rhsIsUser {
                return lhsIsUser
            }
            if lhs.element.message.createdAt != rhs.element.message.createdAt {
                return lhs.element.message.createdAt < rhs.element.message.createdAt
            }
            let lhsPrecedence = turnItemPrecedence(lhs.element)
            let rhsPrecedence = turnItemPrecedence(rhs.element)
            if lhsPrecedence != rhsPrecedence {
                return lhsPrecedence < rhsPrecedence
            }
            return lhs.offset < rhs.offset
        }
        .map(\.element)
    }

    private static func turnItemPrecedence(_ item: ThreadTurnItem) -> Int {
        switch item.kind {
        case .userMessage:
            return 0
        case .reasoning:
            return 1
        case .tool, .artifact, .imageArtifact, .fileArtifact, .diffArtifact:
            return 2
        case .assistantMessage:
            return 3
        case .system:
            return 4
        }
    }

    private static func explicitImageAttachments(
        in object: [String: JSONValue],
        itemID: String,
        threadRef: ThreadRef,
        createdAt: Date
    ) -> [ThreadMessageAttachment] {
        let candidates = [
            object["path"]?.stringValue,
            object["savedPath"]?.stringValue,
            object["saved_path"]?.stringValue,
            object["imagePath"]?.stringValue,
            object["image_path"]?.stringValue,
            object["result"]?["path"]?.stringValue,
            object["result"]?["savedPath"]?.stringValue,
            object["result"]?["saved_path"]?.stringValue,
            object["result"]?["imagePath"]?.stringValue,
            object["result"]?["image_path"]?.stringValue,
            object["imageUrl"]?.stringValue,
            object["image_url"]?.stringValue,
            object["url"]?.stringValue,
        ]
        var seen = Set<String>()
        return candidates.compactMap { rawPath in
            guard let sourcePath = normalizedImagePath(rawPath),
                  seen.insert(sourcePath).inserted else {
                return nil
            }
            return ThreadMessageAttachment(
                id: "\(itemID)-image-\(sanitizeAttachmentID(sourcePath))",
                kind: .image,
                sourceHostID: threadRef.hostID,
                sourcePath: sourcePath,
                mimeType: imageMimeType(forPath: sourcePath),
                title: fileName(forPath: sourcePath),
                status: normalizedImageStatus(object["status"]?.stringValue, sourcePath: sourcePath),
                revisedPrompt: object["revisedPrompt"]?.stringValue ?? object["revised_prompt"]?.stringValue,
                createdAt: createdAt
            )
        }
    }

    private static func explicitFileChangeAttachments(
        in object: [String: JSONValue],
        itemID: String,
        threadRef: ThreadRef,
        createdAt: Date
    ) -> [ThreadMessageAttachment] {
        let changesValue = object["changes"]
            ?? object["files"]
            ?? object["fileChanges"]
            ?? object["file_changes"]
        let status = object["status"]?.stringValue ?? "completed"
        switch changesValue {
        case .object(let changes)?:
            return changes.compactMap { path, change in
                explicitFileAttachment(
                    path: path,
                    itemID: itemID,
                    threadRef: threadRef,
                    createdAt: createdAt,
                    status: status,
                    change: change
                )
            }
        case .array(let array)?:
            return array.compactMap { change in
                guard let path = change["path"]?.stringValue ?? change["file"]?.stringValue ?? change["filename"]?.stringValue else {
                    return nil
                }
                return explicitFileAttachment(
                    path: path,
                    itemID: itemID,
                    threadRef: threadRef,
                    createdAt: createdAt,
                    status: status,
                    change: change
                )
            }
        default:
            return []
        }
    }

    private static func explicitPatchAttachments(
        in object: [String: JSONValue],
        itemID: String,
        threadRef: ThreadRef,
        createdAt: Date
    ) -> [ThreadMessageAttachment] {
        guard case .object(let changes)? = object["changes"] else {
            return []
        }
        let status = object["success"]?.boolValue == false ? "failed" : "completed"
        return changes.compactMap { path, change in
            explicitFileAttachment(
                path: path,
                itemID: itemID,
                threadRef: threadRef,
                createdAt: createdAt,
                status: status,
                change: change
            )
        }
    }

    private static func explicitFileAttachment(
        path: String,
        itemID: String,
        threadRef: ThreadRef,
        createdAt: Date,
        status: String,
        change: JSONValue
    ) -> ThreadMessageAttachment? {
        guard let normalizedPath = normalizedArtifactPath(path) else {
            return nil
        }
        return ThreadMessageAttachment(
            id: "\(itemID)-file-\(sanitizeAttachmentID(normalizedPath))",
            kind: .file,
            sourceHostID: threadRef.hostID,
            sourcePath: normalizedPath,
            mimeType: fileMimeType(forPath: normalizedPath),
            title: fileName(forPath: normalizedPath),
            status: status,
            createdAt: createdAt,
            changeType: attachmentChangeType(from: change),
            diffText: structuredDiffText(from: change),
            language: TranscriptAssetCache.language(forPath: normalizedPath),
            isTrustedForAutoHydration: false
        )
    }

    private static func structuredDiffText(from value: JSONValue) -> String? {
        guard case .object(let object) = value else {
            return nil
        }
        let candidates = [
            object["diff"]?.stringValue,
            object["unifiedDiff"]?.stringValue,
            object["unified_diff"]?.stringValue,
            object["patch"]?.stringValue,
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func explicitImageMessageText(for type: String, object: [String: JSONValue], itemID: String) -> String {
        let sourcePath = normalizedImagePath(
            object["path"]?.stringValue
                ?? object["savedPath"]?.stringValue
                ?? object["saved_path"]?.stringValue
                ?? object["imagePath"]?.stringValue
                ?? object["image_path"]?.stringValue
                ?? object["result"]?["path"]?.stringValue
                ?? object["result"]?["savedPath"]?.stringValue
                ?? object["result"]?["saved_path"]?.stringValue
        )
        if type == "imageview" {
            guard let sourcePath else { return "Image" }
            return "Image\n\nPath:\n\(sourcePath)"
        }

        var sections = ["Generated image"]
        if let status = normalizedImageStatus(object["status"]?.stringValue, sourcePath: sourcePath) {
            sections.append("Status: \(status)")
        }
        if let revisedPrompt = object["revisedPrompt"]?.stringValue ?? object["revised_prompt"]?.stringValue,
           !revisedPrompt.isEmpty {
            sections.append("Prompt:\n\(revisedPrompt)")
        }
        if let sourcePath {
            sections.append("Saved to:\n\(sourcePath)")
        } else {
            sections.append("Image id: \(itemID)")
        }
        return sections.joined(separator: "\n\n")
    }

    private static func preferredArtifactKind(for attachments: [ThreadMessageAttachment]) -> ThreadTurnItemKind {
        if attachments.contains(where: { $0.kind == .image }) {
            return .imageArtifact
        }
        if attachments.contains(where: { $0.kind == .diff }) {
            return .diffArtifact
        }
        if attachments.contains(where: { $0.kind == .file }) {
            return .fileArtifact
        }
        return .artifact
    }

    private static func normalizedArtifactPath(_ value: String?) -> String? {
        guard let rawValue = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty else {
            return nil
        }
        if rawValue.hasPrefix("file://"),
           let url = URL(string: rawValue),
           url.isFileURL {
            return url.path
        }
        return rawValue
    }

    private static func normalizedImagePath(_ value: String?) -> String? {
        guard let path = normalizedArtifactPath(value) else {
            return nil
        }
        let lowercased = path.lowercased()
        guard !lowercased.hasPrefix("http://"),
              !lowercased.hasPrefix("https://"),
              lowercased.hasSuffix(".png")
                || lowercased.hasSuffix(".jpg")
                || lowercased.hasSuffix(".jpeg")
                || lowercased.hasSuffix(".webp")
                || lowercased.hasSuffix(".gif")
                || lowercased.hasSuffix(".heic")
        else {
            return nil
        }
        return path
    }

    private static func imageMimeType(forPath path: String) -> String? {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "webp":
            return "image/webp"
        case "gif":
            return "image/gif"
        case "heic":
            return "image/heic"
        default:
            return nil
        }
    }

    private static func fileMimeType(forPath path: String) -> String? {
        TranscriptAssetCache.mimeType(forPath: path)
    }

    private static func fileName(forPath path: String) -> String {
        path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? path
    }

    private static func sanitizeAttachmentID(_ value: String) -> String {
        let sanitized = value.map { character in
            if character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_") {
                return character
            }
            return "_"
        }
        let result = String(sanitized)
        return result.isEmpty ? "artifact" : result
    }

    private static func normalizedImageStatus(_ status: String?, sourcePath: String?) -> String? {
        if sourcePath != nil {
            return "completed"
        }
        guard let status, !status.isEmpty else {
            return status
        }
        switch status.lowercased() {
        case "generating", "in_progress", "running":
            return "generating"
        default:
            return status
        }
    }

    private static func attachmentChangeType(from value: JSONValue) -> ThreadMessageAttachmentChangeType {
        let type = value["type"]?.stringValue?.lowercased()
            ?? value["changeType"]?.stringValue?.lowercased()
            ?? value["change_type"]?.stringValue?.lowercased()
            ?? value.stringValue?.lowercased()
        switch type {
        case "add", "added", "create", "created":
            return .added
        case "modify", "modified", "update", "updated":
            return .modified
        case "delete", "deleted", "remove", "removed":
            return .deleted
        case "rename", "renamed", "move", "moved":
            return .renamed
        default:
            return .unknown
        }
    }
}

public enum MessageRouteDeliveryState: String, Codable, CaseIterable, Sendable {
    case pending
    case delivered
    case failed
    case unknown
}

public struct MessageRoute: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var sourceHostID: HostID
    public var sourceThreadID: String
    public var sourceTurnID: String?
    public var sourceItemID: String?
    public var targetHostID: HostID
    public var targetThreadID: String
    public var targetTurnID: String?
    public var timestamp: Date
    public var snippet: String
    public var deliveryState: MessageRouteDeliveryState
    public var eventIDs: [String]
    public var canvasEdgeID: EdgeID?

    public init(
        id: String = UUID().uuidString,
        sourceHostID: HostID,
        sourceThreadID: String,
        sourceTurnID: String? = nil,
        sourceItemID: String? = nil,
        targetHostID: HostID,
        targetThreadID: String,
        targetTurnID: String? = nil,
        timestamp: Date = Date(),
        snippet: String,
        deliveryState: MessageRouteDeliveryState = .unknown,
        eventIDs: [String] = [],
        canvasEdgeID: EdgeID? = nil
    ) {
        self.id = id
        self.sourceHostID = sourceHostID
        self.sourceThreadID = sourceThreadID
        self.sourceTurnID = sourceTurnID
        self.sourceItemID = sourceItemID
        self.targetHostID = targetHostID
        self.targetThreadID = targetThreadID
        self.targetTurnID = targetTurnID
        self.timestamp = timestamp
        self.snippet = snippet
        self.deliveryState = deliveryState
        self.eventIDs = eventIDs
        self.canvasEdgeID = canvasEdgeID
    }
}

struct ThreadCatalogFetchFailure: Hashable, Sendable {
    var hostName: String
    var operation: String
    var message: String
}

@MainActor
@Observable
public final class ThreadCatalogStore {
    public var selectedMode: ThreadInboxMode = .active
    public var selectedWorkflowFilter: ThreadInboxWorkflowFilter = .all
    public var searchText: String = ""
    public private(set) var entriesByID: [String: ThreadCatalogEntry] = [:]
    public private(set) var runtimeStatesByID: [String: ThreadRuntimeState] = [:]
    public private(set) var readStatesByID: [String: ThreadReadState] = [:]
    public private(set) var serverSearchQuery: String = ""
    public private(set) var serverSearchResultIDs: Set<String> = []
    public private(set) var lastRefreshAt: Date?
    public private(set) var isRefreshing = false
    public private(set) var errorMessage: String?

    public init() {}

    public var entries: [ThreadCatalogEntry] {
        entriesByID.values
            .map { $0.applying(runtimeState: runtimeStatesByID[$0.id]) }
            .map { $0.applying(readState: readStatesByID[$0.id]) }
            .sorted { lhs, rhs in
                if lhs.lastActivityAt != rhs.lastActivityAt {
                    return lhs.lastActivityAt > rhs.lastActivityAt
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
    }

    public var visibleEntries: [ThreadCatalogEntry] {
        filteredBySelectedWorkflow(modeEntries)
    }

    public var workflowFilterOptions: [ThreadInboxWorkflowFilterOption] {
        var countsByID: [String: Int] = [:]
        var namesByID: [String: String] = [:]
        var activeWorkflowIDs = Set<String>()

        for entry in entries {
            var seenForEntry = Set<String>()
            for membership in entry.workflowMemberships where seenForEntry.insert(membership.workflowID).inserted {
                countsByID[membership.workflowID, default: 0] += 1
                if namesByID[membership.workflowID] == nil {
                    namesByID[membership.workflowID] = membership.workflowName
                }
                if membership.isActiveWorkflow {
                    activeWorkflowIDs.insert(membership.workflowID)
                }
            }
        }

        return countsByID.map { workflowID, count in
            ThreadInboxWorkflowFilterOption(
                workflowID: workflowID,
                workflowName: namesByID[workflowID] ?? workflowID,
                count: count,
                isActiveWorkflow: activeWorkflowIDs.contains(workflowID)
            )
        }
        .sorted { lhs, rhs in
            if lhs.isActiveWorkflow != rhs.isActiveWorkflow {
                return lhs.isActiveWorkflow
            }
            return lhs.workflowName.localizedCaseInsensitiveCompare(rhs.workflowName) == .orderedAscending
        }
    }

    private var modeEntries: [ThreadCatalogEntry] {
        let all = entries
        switch selectedMode {
        case .active:
            return all.filter(\.isActive)
        case .finished:
            return all.filter { !$0.isActive && !$0.archived }
        case .needsYou:
            return all.filter(\.needsAttention)
        case .unread:
            return all.filter(\.unread)
        case .recent:
            return all.filter { !$0.archived }
        case .search:
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return all.filter { !$0.archived } }
            let localMatches = all.filter { entry in
                Self.entry(entry, matches: query)
            }
            guard serverSearchQuery == query else {
                return localMatches
            }
            let localIDs = Set(localMatches.map(\.id))
            let serverOnly = all.filter { serverSearchResultIDs.contains($0.id) && !localIDs.contains($0.id) }
            return (localMatches + serverOnly)
                .sorted { lhs, rhs in
                    if serverSearchResultIDs.contains(lhs.id) != serverSearchResultIDs.contains(rhs.id) {
                        return serverSearchResultIDs.contains(lhs.id)
                    }
                    return lhs.lastActivityAt > rhs.lastActivityAt
                }
        case .archived:
            return all.filter(\.archived)
        }
    }

    private func filteredBySelectedWorkflow(_ entries: [ThreadCatalogEntry]) -> [ThreadCatalogEntry] {
        entries.filter { selectedWorkflowFilter.includes($0) }
    }

    public func refresh(
        runtimeStore: CodexRuntimeStore,
        supervisorStore: WorkflowSupervisorStore,
        graph: AgentGraph,
        workflowMemberships: [String: [ThreadWorkflowMembership]] = [:],
        includeArchived: Bool = false
    ) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var refreshed: [ThreadCatalogEntry] = []
        refreshed.append(contentsOf: entries(from: graph, runtimeStore: runtimeStore, supervisorStore: supervisorStore, workflowMemberships: workflowMemberships))

        var failures: [ThreadCatalogFetchFailure] = []

        if runtimeStore.connectionState == .connected {
            await appendCatalogEntries(
                hostName: runtimeStore.localHost.name,
                operation: "threads",
                to: &refreshed,
                failures: &failures
            ) {
                try await runtimeStore.threadCatalogEntries(limit: 100, archived: false)
            }
            refreshed.append(contentsOf: await runtimeStore.loadedThreadCatalogEntries(limit: 100))
            if includeArchived {
                await appendCatalogEntries(
                    hostName: runtimeStore.localHost.name,
                    operation: "archived threads",
                    to: &refreshed,
                    failures: &failures
                ) {
                    try await runtimeStore.threadCatalogEntries(limit: 50, archived: true)
                }
            }
        }

        for machine in supervisorStore.machines where machine.status == .connected && machine.id != runtimeStore.localHost.id {
            await appendCatalogEntries(
                hostName: machine.name,
                operation: "threads",
                to: &refreshed,
                failures: &failures
            ) {
                try await supervisorStore.threadCatalogEntries(on: machine.id, limit: 100, archived: false)
            }
            refreshed.append(contentsOf: await supervisorStore.loadedThreadCatalogEntries(on: machine.id, limit: 100))
            if includeArchived {
                await appendCatalogEntries(
                    hostName: machine.name,
                    operation: "archived threads",
                    to: &refreshed,
                    failures: &failures
                ) {
                    try await supervisorStore.threadCatalogEntries(on: machine.id, limit: 50, archived: true)
                }
            }
        }
        errorMessage = Self.partialFailureMessage(for: failures)

        upsert(refreshed)
        applyWorkflowMemberships(workflowMemberships)
        apply(runtimeStates: runtimeStore.threadRuntimeStates)
        apply(runtimeStates: supervisorStore.threadRuntimeStates)
        apply(
            events: runtimeStore.workflowEvents + supervisorStore.workflowEvents,
            graph: graph,
            defaultHostID: runtimeStore.localHost.id
        )
        apply(attentionRequests: runtimeStore.pendingAttentionRequests + supervisorStore.pendingAttentionRequests)
        lastRefreshAt = Date()
    }

    public func search(
        runtimeStore: CodexRuntimeStore,
        supervisorStore: WorkflowSupervisorStore,
        graph: AgentGraph,
        workflowMemberships: [String: [ThreadWorkflowMembership]] = [:],
        limit: Int = 80
    ) async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clearSearchResults()
            await refresh(
                runtimeStore: runtimeStore,
                supervisorStore: supervisorStore,
                graph: graph,
                workflowMemberships: workflowMemberships
            )
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var refreshed = entries(from: graph, runtimeStore: runtimeStore, supervisorStore: supervisorStore, workflowMemberships: workflowMemberships)
        var serverResults: [ThreadCatalogEntry] = []

        var failures: [ThreadCatalogFetchFailure] = []

        if runtimeStore.connectionState == .connected {
            await appendCatalogEntries(
                hostName: runtimeStore.localHost.name,
                operation: "search",
                to: &serverResults,
                failures: &failures
            ) {
                try await runtimeStore.searchThreadCatalog(query: query, limit: limit)
            }
        }

        for machine in supervisorStore.machines where machine.status == .connected && machine.id != runtimeStore.localHost.id {
            await appendCatalogEntries(
                hostName: machine.name,
                operation: "search",
                to: &serverResults,
                failures: &failures
            ) {
                try await supervisorStore.searchThreadCatalog(on: machine.id, query: query, limit: limit)
            }
        }
        refreshed.append(contentsOf: serverResults)
        errorMessage = Self.partialFailureMessage(for: failures)

        upsert(refreshed)
        recordServerSearchResults(serverResults, query: query)
        applyWorkflowMemberships(workflowMemberships)
        apply(runtimeStates: runtimeStore.threadRuntimeStates)
        apply(runtimeStates: supervisorStore.threadRuntimeStates)
        apply(
            events: runtimeStore.workflowEvents + supervisorStore.workflowEvents,
            graph: graph,
            defaultHostID: runtimeStore.localHost.id
        )
        apply(attentionRequests: runtimeStore.pendingAttentionRequests + supervisorStore.pendingAttentionRequests)
        lastRefreshAt = Date()
    }

    public func recordServerSearchResults(_ entries: [ThreadCatalogEntry], query: String) {
        serverSearchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        serverSearchResultIDs = Set(entries.map(\.id))
    }

    public func clearSearchResults() {
        serverSearchQuery = ""
        serverSearchResultIDs = []
    }

    public func upsert(_ entries: [ThreadCatalogEntry]) {
        for entry in entries {
            var merged = entriesByID[entry.id] ?? entry
            merged.threadRef = entry.threadRef
            merged.hostName = entry.hostName
            merged.title = entry.title
            merged.preview = entry.preview.isEmpty ? merged.preview : entry.preview
            merged.source = entry.source ?? merged.source
            merged.archived = entry.archived
            merged.loadedStatus = entry.loadedStatus == .idle ? merged.loadedStatus : entry.loadedStatus
            merged.lastActivityAt = max(merged.lastActivityAt, entry.lastActivityAt)
            merged.materializedNodeID = entry.materializedNodeID ?? merged.materializedNodeID
            merged.model = entry.model ?? merged.model
            merged.reasoningEffort = entry.reasoningEffort ?? merged.reasoningEffort
            if entry.threadKind == .subagent || (entry.threadKind != nil && merged.threadKind != .subagent) {
                merged.threadKind = entry.threadKind
            }
            if !entry.workflowMemberships.isEmpty {
                merged.workflowMemberships = entry.workflowMemberships
            }
            entriesByID[entry.id] = merged.applying(readState: readStatesByID[entry.id])
        }
    }

    public func applyWorkflowMemberships(_ membershipsByThreadID: [String: [ThreadWorkflowMembership]]) {
        for key in entriesByID.keys {
            guard var entry = entriesByID[key] else { continue }
            let memberships = membershipsByThreadID[key] ?? []
            entry.workflowMemberships = memberships
            entry.materializedNodeID = memberships.first { $0.isActiveWorkflow }?.nodeID
            entriesByID[key] = entry
        }
    }

    public func apply(runtimeStates states: [String: ThreadRuntimeState]) {
        for (id, incomingState) in states {
            let state = applyingReadState(to: incomingState, key: id)
            runtimeStatesByID[id] = state
            if var entry = entriesByID[id] {
                entry = entry.applying(runtimeState: state)
                    .applying(readState: readStatesByID[id])
                entriesByID[id] = entry
            }
        }
    }

    public func apply(events: [WorkflowEvent], graph: AgentGraph, defaultHostID: HostID? = nil) {
        for event in events.sorted(by: { $0.createdAt < $1.createdAt }) {
            guard event.kind != .threadCreated else { continue }
            guard let threadID = event.threadID else { continue }
            let hostID = event.hostID ?? defaultHostID ?? HostID(rawValue: "local")
            let key = ThreadRef.qualifiedID(hostID: hostID, threadID: threadID)
            var state = runtimeStatesByID[key] ?? ThreadRuntimeState(hostID: hostID, threadID: threadID)
            let markUnread = event.kind != .turnStarted && eventIsAfterReadState(event, key: key)
            state.apply(event: event, markUnread: markUnread)
            state = applyingReadState(to: state, key: key)
            runtimeStatesByID[key] = state

            var entry = entriesByID[key] ?? catalogEntry(from: event, hostID: hostID, graph: graph)
            entry.loadedStatus = state.status
            entry.unread = state.isUnread
            entry.lastActivityAt = state.lastActivityAt
            entry.lastError = state.lastError ?? entry.lastError
            entry.latestEventSummary = event.summary
            entriesByID[key] = entry.applying(readState: readStatesByID[key])
        }
    }

    public func apply(attentionRequests requests: [RuntimeAttentionRequest]) {
        for request in requests {
            guard let hostID = request.hostID, let threadID = request.threadID else { continue }
            let key = ThreadRef.qualifiedID(hostID: hostID, threadID: threadID)
            var state = runtimeStatesByID[key] ?? ThreadRuntimeState(hostID: hostID, threadID: threadID)
            state.applyAttentionRequest(request)
            state = applyingReadState(to: state, key: key)
            runtimeStatesByID[key] = state

            if var entry = entriesByID[key] {
                entry.loadedStatus = .needsInput
                entry.pendingRequestCount = state.pendingRequestIDs.count
                entry.unread = state.isUnread
                entry.lastActivityAt = max(entry.lastActivityAt, request.createdAt)
                entry.latestEventSummary = request.summary
                entriesByID[key] = entry.applying(readState: readStatesByID[key])
            }
        }
    }

    public func markRead(_ threadRef: ThreadRef, isRead: Bool, at date: Date = Date()) {
        let key = threadRef.qualifiedID
        if isRead {
            let seenAt = [
                date,
                entriesByID[key]?.lastActivityAt,
                runtimeStatesByID[key]?.lastActivityAt,
            ]
                .compactMap(\.self)
                .max() ?? date
            readStatesByID[key] = ThreadReadState(threadRef: threadRef, lastSeenAt: seenAt)
        } else {
            readStatesByID[key] = nil
        }

        if var state = runtimeStatesByID[key] {
            state.markRead(isRead)
            runtimeStatesByID[key] = state
        }
        if var entry = entriesByID[key] {
            entry.unread = !isRead
            entriesByID[key] = entry
        }
    }

    public func entry(for threadRef: ThreadRef) -> ThreadCatalogEntry? {
        entriesByID[threadRef.qualifiedID]
    }

    nonisolated static func partialFailureMessage(for failures: [ThreadCatalogFetchFailure]) -> String? {
        guard !failures.isEmpty else {
            return nil
        }

        let details = failures
            .map { failure in
                let hostName = failure.hostName.trimmingCharacters(in: .whitespacesAndNewlines)
                let operation = failure.operation.trimmingCharacters(in: .whitespacesAndNewlines)
                let prefix: String
                if hostName.isEmpty {
                    prefix = operation.isEmpty ? "Catalog fetch" : operation
                } else if operation.isEmpty {
                    prefix = hostName
                } else {
                    prefix = "\(hostName) \(operation)"
                }
                return "\(prefix): \(failure.message)"
            }
            .joined(separator: "; ")
        return "Some thread catalog results could not be loaded. \(details)"
    }

    private func eventIsAfterReadState(_ event: WorkflowEvent, key: String) -> Bool {
        guard let readState = readStatesByID[key] else { return true }
        return event.createdAt > readState.lastSeenAt
    }

    private func appendCatalogEntries(
        hostName: String,
        operation: String,
        to entries: inout [ThreadCatalogEntry],
        failures: inout [ThreadCatalogFetchFailure],
        fetch: () async throws -> [ThreadCatalogEntry]
    ) async {
        do {
            entries.append(contentsOf: try await fetch())
        } catch {
            failures.append(
                ThreadCatalogFetchFailure(
                    hostName: hostName,
                    operation: operation,
                    message: error.localizedDescription
                )
            )
        }
    }

    private func applyingReadState(to state: ThreadRuntimeState, key: String) -> ThreadRuntimeState {
        guard let readState = readStatesByID[key], state.lastActivityAt <= readState.lastSeenAt else {
            return state
        }
        var copy = state
        copy.markRead(true)
        return copy
    }

    private func entries(
        from graph: AgentGraph,
        runtimeStore: CodexRuntimeStore,
        supervisorStore: WorkflowSupervisorStore,
        workflowMemberships: [String: [ThreadWorkflowMembership]]
    ) -> [ThreadCatalogEntry] {
        graph.sortedNodes.compactMap { node in
            guard node.kind == .codexThread, let threadRef = node.metadata.threadRef else {
                return nil
            }
            let hostName = graph.nodes.values.first {
                $0.kind == .machine && $0.metadata.hostID == threadRef.hostID
            }?.title
                ?? supervisorStore.machines.first { $0.id == threadRef.hostID }?.name
                ?? (threadRef.hostID == runtimeStore.localHost.id ? runtimeStore.localHost.name : threadRef.hostID.rawValue)

            return ThreadCatalogEntry(
                threadRef: threadRef,
                hostName: hostName,
                title: node.title,
                preview: node.subtitle,
                source: "canvas",
                archived: false,
                loadedStatus: node.metadata.runStatus ?? .idle,
                lastActivityAt: graph.updatedAt,
                unread: node.metadata.isUnread == true,
                materializedNodeID: node.id,
                model: node.metadata.model,
                reasoningEffort: node.metadata.reasoningEffort,
                threadKind: node.metadata.threadKind ?? .thread,
                workflowMemberships: workflowMemberships[threadRef.qualifiedID] ?? []
            )
        }
    }

    private func catalogEntry(from event: WorkflowEvent, hostID: HostID, graph: AgentGraph) -> ThreadCatalogEntry {
        let threadID = event.threadID ?? "unknown"
        if let node = graph.nodes.values.first(where: {
            $0.metadata.threadRef?.matches(hostID: hostID, threadID: threadID) == true
        }), let threadRef = node.metadata.threadRef {
            return ThreadCatalogEntry(
                threadRef: threadRef,
                hostName: graph.nodes.values.first { $0.kind == .machine && $0.metadata.hostID == hostID }?.title ?? hostID.rawValue,
                title: node.title,
                preview: node.subtitle,
                source: "canvas",
                loadedStatus: node.metadata.runStatus ?? .idle,
                lastActivityAt: event.createdAt,
                unread: node.metadata.isUnread == true,
                materializedNodeID: node.id,
                latestEventSummary: event.summary,
                model: node.metadata.model,
                reasoningEffort: node.metadata.reasoningEffort,
                threadKind: node.metadata.threadKind ?? .thread
            )
        }

        let threadRef = ThreadRef(hostID: hostID, threadID: threadID, cwd: "", name: nil)
        return ThreadCatalogEntry(
            threadRef: threadRef,
            hostName: hostID.rawValue,
            title: "Codex thread",
            preview: event.summary,
            source: event.method,
            loadedStatus: ThreadRunStatus(event.kind),
            lastActivityAt: event.createdAt,
            unread: event.kind != .turnStarted,
            latestEventSummary: event.summary
        )
    }

    private static func entry(_ entry: ThreadCatalogEntry, matches query: String) -> Bool {
        entry.title.localizedCaseInsensitiveContains(query)
            || entry.preview.localizedCaseInsensitiveContains(query)
            || entry.threadRef.threadID.localizedCaseInsensitiveContains(query)
            || entry.threadRef.cwd.localizedCaseInsensitiveContains(query)
    }
}

private extension ThreadTurnItemKind {
    init(_ message: ThreadMessage) {
        if let attachment = message.attachments.first {
            switch attachment.kind {
            case .image:
                self = .imageArtifact
            case .file:
                self = .fileArtifact
            case .diff:
                self = .diffArtifact
            }
            return
        }

        switch message.role {
        case .user:
            self = .userMessage
        case .assistant:
            self = .assistantMessage
        case .reasoning:
            self = .reasoning
        case .tool:
            self = .tool
        case .system:
            self = .system
        }
    }
}

private extension ThreadRunStatus {
    init(appServerTurnStatus: String?) {
        switch appServerTurnStatus?.lowercased() {
        case "inprogress", "in_progress", "running", "active":
            self = .running
        case "failed", "error":
            self = .failed
        case "interrupted", "needsinput", "needs_input":
            self = .needsInput
        case "completed", "complete", "done":
            self = .complete
        default:
            self = .unknown
        }
    }

    init(_ eventKind: WorkflowEventKind) {
        switch eventKind {
        case .turnStarted:
            self = .running
        case .turnCompleted:
            self = .complete
        case .threadCreated:
            self = .complete
        case .needsInput:
            self = .needsInput
        case .failed:
            self = .failed
        }
    }
}

private extension ThreadTurnItemsView {
    init(appServerValue: String?) {
        switch appServerValue?.lowercased() {
        case "notloaded", "not_loaded":
            self = .notLoaded
        case "summary":
            self = .summary
        case "full":
            self = .full
        default:
            self = .full
        }
    }
}

private extension Array where Element == ThreadTurn {
    func nearestTurnIndex(containing date: Date) -> Int? {
        guard !isEmpty else {
            return nil
        }

        if let containingIndex = firstIndex(where: { turn in
            let end = turn.completedAt ?? turn.startedAt
            return turn.startedAt <= date && date <= end
        }) {
            return containingIndex
        }

        return indices.min { lhs, rhs in
            let lhsDistance = abs(self[lhs].startedAt.timeIntervalSince(date))
            let rhsDistance = abs(self[rhs].startedAt.timeIntervalSince(date))
            return lhsDistance < rhsDistance
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
