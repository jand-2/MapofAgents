import Foundation

public enum NodeKind: String, Codable, CaseIterable, Sendable {
    case machine
    case folder
    case codexThread
}

public enum HostPlatform: String, Codable, CaseIterable, Sendable {
    case macOS
    case iOS
    case iPadOS
    case windows
    case linux
    case unknown
}

public enum HostStatus: String, Codable, CaseIterable, Sendable {
    case connected
    case connecting
    case disconnected
    case unavailable
}

public enum ThreadRunStatus: String, Codable, CaseIterable, Sendable {
    case idle
    case running
    case needsInput
    case failed
    case complete
    case unknown
}

public enum CodexThreadNodeKind: String, Codable, CaseIterable, Sendable {
    case thread
    case subagent

    public var displayName: String {
        switch self {
        case .thread:
            return "Thread"
        case .subagent:
            return "Subagent"
        }
    }
}

public enum EdgeKind: String, Codable, CaseIterable, Sendable {
    case machineFolder
    case folderThread
    case machineThread
    case manualNote
    case threadMessage
    case createdBy
}

public struct ThreadRef: Codable, Hashable, Sendable {
    public let provider: AgentProvider
    public var hostID: HostID
    public var threadID: String
    public var cwd: String
    public var name: String?

    public init(
        provider: AgentProvider = .codex,
        hostID: HostID,
        threadID: String,
        cwd: String,
        name: String? = nil
    ) {
        self.provider = provider
        self.hostID = hostID
        self.threadID = threadID
        self.cwd = cwd
        self.name = name
    }

    public var qualifiedID: String {
        Self.qualifiedID(provider: provider, hostID: hostID, threadID: threadID)
    }

    public func matches(hostID: HostID?, threadID: String?) -> Bool {
        guard let threadID, self.threadID == threadID else {
            return false
        }
        guard let hostID else {
            return true
        }
        return self.hostID == hostID
    }

    public func matches(_ other: ThreadRef) -> Bool {
        provider == other.provider
            && hostID == other.hostID
            && threadID == other.threadID
    }

    public static func qualifiedID(hostID: HostID, threadID: String) -> String {
        qualifiedID(provider: .codex, hostID: hostID, threadID: threadID)
    }

    public static func qualifiedID(
        provider: AgentProvider,
        hostID: HostID,
        threadID: String
    ) -> String {
        if provider == .codex {
            return "\(hostID.rawValue)::\(threadID)"
        }
        return "\(provider.rawValue)::\(hostID.rawValue)::\(threadID)"
    }

    private enum CodingKeys: String, CodingKey {
        case provider
        case hostID
        case threadID
        case cwd
        case name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decodeIfPresent(AgentProvider.self, forKey: .provider) ?? .codex
        hostID = try container.decode(HostID.self, forKey: .hostID)
        threadID = try container.decode(String.self, forKey: .threadID)
        cwd = try container.decode(String.self, forKey: .cwd)
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }
}

public struct ThreadCreationOutcome: Equatable, Sendable {
    public var threadRef: ThreadRef
    public var warning: String?

    public init(threadRef: ThreadRef, warning: String? = nil) {
        self.threadRef = threadRef
        self.warning = warning
    }
}

public struct WorkflowThreadContentSignature: Hashable, Sendable {
    public var threadRefs: [ThreadRef]

    public init(threadRefs: [ThreadRef]) {
        self.threadRefs = threadRefs.sorted { lhs, rhs in
            if lhs.provider.rawValue != rhs.provider.rawValue {
                return lhs.provider.rawValue < rhs.provider.rawValue
            }
            if lhs.hostID.rawValue != rhs.hostID.rawValue {
                return lhs.hostID.rawValue < rhs.hostID.rawValue
            }
            if lhs.threadID != rhs.threadID {
                return lhs.threadID < rhs.threadID
            }
            if lhs.cwd != rhs.cwd {
                return lhs.cwd < rhs.cwd
            }
            return (lhs.name ?? "") < (rhs.name ?? "")
        }
    }
}

public enum LocalThreadMessageRole: String, Codable, CaseIterable, Sendable {
    case user
    case assistant
    case reasoning
    case tool
    case system
    case file
    case image
    case diff
}

public struct LocalThreadMessage: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var role: LocalThreadMessageRole
    public var text: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        role: LocalThreadMessageRole,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

public enum LocalThreadTurnItemsView: String, Codable, CaseIterable, Sendable {
    case notLoaded
    case summary
    case full
}

public struct LocalThreadTurn: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var status: ThreadRunStatus
    public var startedAt: Date
    public var completedAt: Date?
    public var error: String?
    public var itemsView: LocalThreadTurnItemsView
    public var durationMilliseconds: Int?
    public var itemMessageIds: [String]

    public init(
        id: String = UUID().uuidString,
        status: ThreadRunStatus = .unknown,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        error: String? = nil,
        itemsView: LocalThreadTurnItemsView = .full,
        durationMilliseconds: Int? = nil,
        itemMessageIds: [String] = []
    ) {
        self.id = id
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.error = error
        self.itemsView = itemsView
        self.durationMilliseconds = durationMilliseconds
        self.itemMessageIds = itemMessageIds
    }
}

public struct NodeMetadata: Codable, Hashable, Sendable {
    public var hostID: HostID?
    public var platform: HostPlatform?
    public var hostStatus: HostStatus?
    public var hostLastError: String?
    public var codexHome: String?
    public var appServerEndpointURL: String?
    public var folderPath: String?
    public var threadRef: ThreadRef?
    public var model: String?
    public var reasoningEffort: String?
    public var threadPermissions: AgentThreadPermissions?
    public var threadKind: CodexThreadNodeKind?
    public var initialPrompt: String?
    public var localTranscript: [LocalThreadMessage]
    public var localTranscriptTurns: [LocalThreadTurn]
    public var runStatus: ThreadRunStatus?
    public var popoverOffset: CanvasPoint?
    public var isUnread: Bool?
    public var isArchived: Bool?
    public var hasManualPosition: Bool?

    public init(
        hostID: HostID? = nil,
        platform: HostPlatform? = nil,
        hostStatus: HostStatus? = nil,
        hostLastError: String? = nil,
        codexHome: String? = nil,
        appServerEndpointURL: String? = nil,
        folderPath: String? = nil,
        threadRef: ThreadRef? = nil,
        model: String? = nil,
        reasoningEffort: String? = nil,
        threadPermissions: AgentThreadPermissions? = nil,
        threadKind: CodexThreadNodeKind? = nil,
        initialPrompt: String? = nil,
        localTranscript: [LocalThreadMessage] = [],
        localTranscriptTurns: [LocalThreadTurn] = [],
        runStatus: ThreadRunStatus? = nil,
        popoverOffset: CanvasPoint? = nil,
        isUnread: Bool? = nil,
        isArchived: Bool? = nil,
        hasManualPosition: Bool? = nil
    ) {
        self.hostID = hostID
        self.platform = platform
        self.hostStatus = hostStatus
        self.hostLastError = hostLastError
        self.codexHome = codexHome
        self.appServerEndpointURL = appServerEndpointURL
        self.folderPath = folderPath
        self.threadRef = threadRef
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.threadPermissions = threadPermissions
        self.threadKind = threadKind
        self.initialPrompt = initialPrompt
        self.localTranscript = localTranscript
        self.localTranscriptTurns = localTranscriptTurns
        self.runStatus = runStatus
        self.popoverOffset = popoverOffset
        self.isUnread = isUnread
        self.isArchived = isArchived
        self.hasManualPosition = hasManualPosition
    }

    private enum CodingKeys: String, CodingKey {
        case hostID
        case platform
        case hostStatus
        case hostLastError
        case codexHome
        case appServerEndpointURL = "appServerEndpointUrl"
        case folderPath
        case threadRef
        case model
        case reasoningEffort
        case threadPermissions
        case threadKind
        case approvalPolicy
        case sandboxMode
        case initialPrompt
        case localTranscript
        case localTranscriptTurns
        case runStatus
        case popoverOffset
        case isUnread
        case isArchived
        case hasManualPosition
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hostID = try container.decodeIfPresent(HostID.self, forKey: .hostID)
        platform = try container.decodeIfPresent(HostPlatform.self, forKey: .platform)
        hostStatus = try container.decodeIfPresent(HostStatus.self, forKey: .hostStatus)
        hostLastError = try container.decodeIfPresent(String.self, forKey: .hostLastError)
        codexHome = try container.decodeIfPresent(String.self, forKey: .codexHome)
        appServerEndpointURL = try container.decodeIfPresent(
            String.self,
            forKey: .appServerEndpointURL
        )
        folderPath = try container.decodeIfPresent(String.self, forKey: .folderPath)
        threadRef = try container.decodeIfPresent(ThreadRef.self, forKey: .threadRef)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        reasoningEffort = try container.decodeIfPresent(String.self, forKey: .reasoningEffort)
        threadKind = try container.decodeIfPresent(CodexThreadNodeKind.self, forKey: .threadKind)
        initialPrompt = try container.decodeIfPresent(String.self, forKey: .initialPrompt)
        localTranscript = try container.decodeIfPresent(
            [LocalThreadMessage].self,
            forKey: .localTranscript
        ) ?? []
        localTranscriptTurns = try container.decodeIfPresent(
            [LocalThreadTurn].self,
            forKey: .localTranscriptTurns
        ) ?? []
        runStatus = try container.decodeIfPresent(ThreadRunStatus.self, forKey: .runStatus)
        popoverOffset = try container.decodeIfPresent(CanvasPoint.self, forKey: .popoverOffset)
        isUnread = try container.decodeIfPresent(Bool.self, forKey: .isUnread)
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived)
        hasManualPosition = try container.decodeIfPresent(Bool.self, forKey: .hasManualPosition)

        if let canonical = try container.decodeIfPresent(
            AgentThreadPermissions.self,
            forKey: .threadPermissions
        ) {
            threadPermissions = canonical
        } else {
            let legacyApprovalPolicy = try container.decodeIfPresent(
                AgentApprovalPolicy.self,
                forKey: .approvalPolicy
            )
            let legacySandboxMode = try container.decodeIfPresent(
                AgentSandboxMode.self,
                forKey: .sandboxMode
            )
            if legacyApprovalPolicy != nil || legacySandboxMode != nil {
                threadPermissions = AgentThreadPermissions(
                    approvalPolicy: legacyApprovalPolicy ?? .onRequest,
                    sandboxMode: legacySandboxMode ?? .dangerFullAccess
                )
            } else {
                threadPermissions = nil
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(hostID, forKey: .hostID)
        try container.encodeIfPresent(platform, forKey: .platform)
        try container.encodeIfPresent(hostStatus, forKey: .hostStatus)
        try container.encodeIfPresent(hostLastError, forKey: .hostLastError)
        try container.encodeIfPresent(codexHome, forKey: .codexHome)
        try container.encodeIfPresent(appServerEndpointURL, forKey: .appServerEndpointURL)
        try container.encodeIfPresent(folderPath, forKey: .folderPath)
        try container.encodeIfPresent(threadRef, forKey: .threadRef)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(reasoningEffort, forKey: .reasoningEffort)
        try container.encodeIfPresent(threadPermissions, forKey: .threadPermissions)
        try container.encodeIfPresent(threadKind, forKey: .threadKind)
        try container.encodeIfPresent(initialPrompt, forKey: .initialPrompt)
        if !localTranscript.isEmpty {
            try container.encode(localTranscript, forKey: .localTranscript)
        }
        if !localTranscriptTurns.isEmpty {
            try container.encode(localTranscriptTurns, forKey: .localTranscriptTurns)
        }
        try container.encodeIfPresent(runStatus, forKey: .runStatus)
        try container.encodeIfPresent(popoverOffset, forKey: .popoverOffset)
        try container.encodeIfPresent(isUnread, forKey: .isUnread)
        try container.encodeIfPresent(isArchived, forKey: .isArchived)
        try container.encodeIfPresent(hasManualPosition, forKey: .hasManualPosition)
    }
}

public struct CanvasNode: Codable, Identifiable, Hashable, Sendable {
    public var id: NodeID
    public var kind: NodeKind
    public var title: String
    public var subtitle: String
    public var position: CanvasPoint
    public var size: CanvasSize
    public var metadata: NodeMetadata
    public var zIndex: Int

    public init(
        id: NodeID = .fresh(),
        kind: NodeKind,
        title: String,
        subtitle: String = "",
        position: CanvasPoint,
        size: CanvasSize,
        metadata: NodeMetadata = NodeMetadata(),
        zIndex: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.position = position
        self.size = size
        self.metadata = metadata
        self.zIndex = zIndex
    }
}

public struct CanvasEdge: Codable, Identifiable, Hashable, Sendable {
    public var id: EdgeID
    public var source: NodeID
    public var target: NodeID
    public var kind: EdgeKind
    public var isManual: Bool
    public var label: String?

    public init(
        id: EdgeID = .fresh(),
        source: NodeID,
        target: NodeID,
        kind: EdgeKind,
        isManual: Bool,
        label: String? = nil
    ) {
        self.id = id
        self.source = source
        self.target = target
        self.kind = kind
        self.isManual = isManual
        self.label = label
    }
}

public struct AgentGraph: Codable, Hashable, Sendable {
    public var workspaceID: WorkspaceID
    public var title: String
    public var layoutCoordinateSpace: String
    public var nodes: [NodeID: CanvasNode]
    public var manualEdges: [EdgeID: CanvasEdge]
    public var messageRoutes: [String: MessageRoute]
    public var pendingAttentionRequests: [RuntimeAttentionRequest]
    public var runtimeDiagnostics: [RuntimeDiagnosticStep]
    public var suppressedAutoMaterializedThreadIDs: Set<String>
    public var viewport: CanvasViewport
    public var updatedAt: Date

    public init(
        workspaceID: WorkspaceID = .fresh(),
        title: String = "mapofagents",
        layoutCoordinateSpace: String = "center",
        nodes: [NodeID: CanvasNode] = [:],
        manualEdges: [EdgeID: CanvasEdge] = [:],
        messageRoutes: [String: MessageRoute] = [:],
        pendingAttentionRequests: [RuntimeAttentionRequest] = [],
        runtimeDiagnostics: [RuntimeDiagnosticStep] = [],
        suppressedAutoMaterializedThreadIDs: Set<String> = [],
        viewport: CanvasViewport = .standard,
        updatedAt: Date = Date()
    ) {
        self.workspaceID = workspaceID
        self.title = title
        self.layoutCoordinateSpace = layoutCoordinateSpace
        self.nodes = nodes
        self.manualEdges = manualEdges
        self.messageRoutes = messageRoutes
        self.pendingAttentionRequests = pendingAttentionRequests
        self.runtimeDiagnostics = runtimeDiagnostics
        self.suppressedAutoMaterializedThreadIDs = suppressedAutoMaterializedThreadIDs
        self.viewport = viewport
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case workspaceID
        case title
        case layoutCoordinateSpace
        case nodes
        case manualEdges
        case messageRoutes
        case pendingAttentionRequests
        case runtimeDiagnostics
        case suppressedAutoMaterializedThreadIDs
        case viewport
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspaceID = try container.decode(WorkspaceID.self, forKey: .workspaceID)
        title = try container.decode(String.self, forKey: .title)
        layoutCoordinateSpace = try container.decodeIfPresent(
            String.self,
            forKey: .layoutCoordinateSpace
        ) ?? "center"
        if let canonicalNodes = try? container.decode(
            [String: CanvasNode].self,
            forKey: .nodes
        ) {
            nodes = Dictionary(
                uniqueKeysWithValues: canonicalNodes.map { (NodeID(rawValue: $0.key), $0.value) }
            )
        } else {
            // Swift encoded dictionaries with strongly typed keys as alternating
            // key/value arrays before the shared object-keyed graph contract.
            nodes = try container.decode([NodeID: CanvasNode].self, forKey: .nodes)
        }
        if let canonicalEdges = try? container.decode(
            [String: CanvasEdge].self,
            forKey: .manualEdges
        ) {
            manualEdges = Dictionary(
                uniqueKeysWithValues: canonicalEdges.map { (EdgeID(rawValue: $0.key), $0.value) }
            )
        } else {
            manualEdges = try container.decode(
                [EdgeID: CanvasEdge].self,
                forKey: .manualEdges
            )
        }
        messageRoutes = try container.decodeIfPresent([String: MessageRoute].self, forKey: .messageRoutes) ?? [:]
        pendingAttentionRequests = try container.decodeIfPresent(
            [RuntimeAttentionRequest].self,
            forKey: .pendingAttentionRequests
        ) ?? []
        runtimeDiagnostics = try container.decodeIfPresent(
            [RuntimeDiagnosticStep].self,
            forKey: .runtimeDiagnostics
        ) ?? []
        suppressedAutoMaterializedThreadIDs = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .suppressedAutoMaterializedThreadIDs
        ) ?? []
        viewport = try container.decode(CanvasViewport.self, forKey: .viewport)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workspaceID, forKey: .workspaceID)
        try container.encode(title, forKey: .title)
        try container.encode(layoutCoordinateSpace, forKey: .layoutCoordinateSpace)
        try container.encode(
            Dictionary(uniqueKeysWithValues: nodes.map { ($0.key.rawValue, $0.value) }),
            forKey: .nodes
        )
        try container.encode(
            Dictionary(uniqueKeysWithValues: manualEdges.map { ($0.key.rawValue, $0.value) }),
            forKey: .manualEdges
        )
        try container.encode(messageRoutes, forKey: .messageRoutes)
        try container.encode(pendingAttentionRequests, forKey: .pendingAttentionRequests)
        try container.encode(runtimeDiagnostics, forKey: .runtimeDiagnostics)
        try container.encode(suppressedAutoMaterializedThreadIDs, forKey: .suppressedAutoMaterializedThreadIDs)
        try container.encode(viewport, forKey: .viewport)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    public var sortedNodes: [CanvasNode] {
        nodes.values.sorted {
            if $0.zIndex == $1.zIndex {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return $0.zIndex < $1.zIndex
        }
    }

    public var workflowThreadContentSignature: WorkflowThreadContentSignature {
        WorkflowThreadContentSignature(
            threadRefs: nodes.values.compactMap { node in
                guard node.kind == .codexThread else { return nil }
                return node.metadata.threadRef
            }
        )
    }

    public mutating func upsertNode(_ node: CanvasNode) {
        nodes[node.id] = node
        if let threadRef = node.metadata.threadRef {
            suppressedAutoMaterializedThreadIDs.remove(threadRef.qualifiedID)
        }
        updatedAt = Date()
    }

    public mutating func removeNode(id: NodeID) {
        let removedNode = nodes[id]
        if removedNode?.kind == .codexThread,
           let threadRef = removedNode?.metadata.threadRef,
           manualEdges.values.contains(where: { $0.target == id && $0.kind == .createdBy }) {
            suppressedAutoMaterializedThreadIDs.insert(threadRef.qualifiedID)
        }
        let removedEdgeIDs = Set(manualEdges.values.filter { edge in
            edge.source == id || edge.target == id
        }.map(\.id))
        nodes[id] = nil
        manualEdges = manualEdges.filter { _, edge in
            edge.source != id && edge.target != id
        }
        if !removedEdgeIDs.isEmpty {
            messageRoutes = messageRoutes.filter { _, route in
                guard let canvasEdgeID = route.canvasEdgeID else { return true }
                return !removedEdgeIDs.contains(canvasEdgeID)
            }
        }
        updatedAt = Date()
    }

    public func isAutoMaterializationSuppressed(for threadRef: ThreadRef) -> Bool {
        suppressedAutoMaterializedThreadIDs.contains(threadRef.qualifiedID)
    }

    public mutating func updateNodePosition(id: NodeID, position: CanvasPoint) {
        guard var node = nodes[id] else { return }
        node.position = position
        node.metadata.hasManualPosition = true
        node.zIndex = (nodes.values.map(\.zIndex).max() ?? 0) + 1
        nodes[id] = node
        updatedAt = Date()
    }

    public mutating func upsertManualEdge(_ edge: CanvasEdge) {
        manualEdges[edge.id] = edge
        updatedAt = Date()
    }

    public mutating func upsertMessageRoute(_ route: MessageRoute) {
        messageRoutes[route.id] = route
        updatedAt = Date()
    }

    public mutating func removeEdge(id: EdgeID) {
        manualEdges[id] = nil
        messageRoutes = messageRoutes.filter { _, route in
            route.canvasEdgeID != id
        }
        updatedAt = Date()
    }

    public mutating func updateViewport(_ viewport: CanvasViewport) {
        self.viewport = viewport
        updatedAt = Date()
    }

    public static func starter(localHostName: String, codexPath: String?) -> AgentGraph {
        let hostID = HostID(rawValue: "local")
        let machine = CanvasNode(
            id: NodeID(rawValue: "local-machine"),
            kind: .machine,
            title: localHostName,
            subtitle: codexPath == nil ? "Codex not found" : "macOS - local",
            position: CanvasPoint(x: 120, y: 100),
            size: .machine,
            metadata: NodeMetadata(
                hostID: hostID,
                platform: .macOS,
                hostStatus: codexPath == nil ? .unavailable : .connected
            )
        )

        var graph = AgentGraph()
        graph.upsertNode(machine)
        return graph
    }

    public func replacingLocalHost(with hostID: HostID, machineName: String? = nil) -> AgentGraph {
        let localHostID = HostID(rawValue: "local")
        var graph = self

        for (nodeID, originalNode) in nodes {
            var node = originalNode

            if node.metadata.hostID == localHostID {
                node.metadata.hostID = hostID
            }

            if var threadRef = node.metadata.threadRef, threadRef.hostID == localHostID {
                threadRef.hostID = hostID
                node.metadata.threadRef = threadRef
            }

            if node.kind == .machine, originalNode.metadata.hostID == localHostID {
                if let machineName, !machineName.isEmpty {
                    node.title = machineName
                }
                node.metadata.hostStatus = .connected
                if node.subtitle.localizedCaseInsensitiveContains("local") {
                    node.subtitle = "macOS - remote"
                }
            }

            graph.nodes[nodeID] = node
        }

        for (routeID, originalRoute) in messageRoutes {
            var route = originalRoute
            if route.sourceHostID == localHostID {
                route.sourceHostID = hostID
            }
            if route.targetHostID == localHostID {
                route.targetHostID = hostID
            }
            graph.messageRoutes[routeID] = route
        }

        graph.updatedAt = Date()
        return graph
    }
}
