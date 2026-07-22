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

public struct NodeMetadata: Codable, Hashable, Sendable {
    public var hostID: HostID?
    public var platform: HostPlatform?
    public var hostStatus: HostStatus?
    public var codexHome: String?
    public var folderPath: String?
    public var threadRef: ThreadRef?
    public var model: String?
    public var reasoningEffort: String?
    public var threadPermissions: AgentThreadPermissions?
    public var threadKind: CodexThreadNodeKind?
    public var runStatus: ThreadRunStatus?
    public var popoverOffset: CanvasPoint?
    public var isUnread: Bool?
    public var hasManualPosition: Bool?

    public init(
        hostID: HostID? = nil,
        platform: HostPlatform? = nil,
        hostStatus: HostStatus? = nil,
        codexHome: String? = nil,
        folderPath: String? = nil,
        threadRef: ThreadRef? = nil,
        model: String? = nil,
        reasoningEffort: String? = nil,
        threadPermissions: AgentThreadPermissions? = nil,
        threadKind: CodexThreadNodeKind? = nil,
        runStatus: ThreadRunStatus? = nil,
        popoverOffset: CanvasPoint? = nil,
        isUnread: Bool? = nil,
        hasManualPosition: Bool? = nil
    ) {
        self.hostID = hostID
        self.platform = platform
        self.hostStatus = hostStatus
        self.codexHome = codexHome
        self.folderPath = folderPath
        self.threadRef = threadRef
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.threadPermissions = threadPermissions
        self.threadKind = threadKind
        self.runStatus = runStatus
        self.popoverOffset = popoverOffset
        self.isUnread = isUnread
        self.hasManualPosition = hasManualPosition
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
    public var nodes: [NodeID: CanvasNode]
    public var manualEdges: [EdgeID: CanvasEdge]
    public var messageRoutes: [String: MessageRoute]
    public var suppressedAutoMaterializedThreadIDs: Set<String>
    public var viewport: CanvasViewport
    public var updatedAt: Date

    public init(
        workspaceID: WorkspaceID = .fresh(),
        title: String = "mapofagents",
        nodes: [NodeID: CanvasNode] = [:],
        manualEdges: [EdgeID: CanvasEdge] = [:],
        messageRoutes: [String: MessageRoute] = [:],
        suppressedAutoMaterializedThreadIDs: Set<String> = [],
        viewport: CanvasViewport = .standard,
        updatedAt: Date = Date()
    ) {
        self.workspaceID = workspaceID
        self.title = title
        self.nodes = nodes
        self.manualEdges = manualEdges
        self.messageRoutes = messageRoutes
        self.suppressedAutoMaterializedThreadIDs = suppressedAutoMaterializedThreadIDs
        self.viewport = viewport
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case workspaceID
        case title
        case nodes
        case manualEdges
        case messageRoutes
        case suppressedAutoMaterializedThreadIDs
        case viewport
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspaceID = try container.decode(WorkspaceID.self, forKey: .workspaceID)
        title = try container.decode(String.self, forKey: .title)
        nodes = try container.decode([NodeID: CanvasNode].self, forKey: .nodes)
        manualEdges = try container.decode([EdgeID: CanvasEdge].self, forKey: .manualEdges)
        messageRoutes = try container.decodeIfPresent([String: MessageRoute].self, forKey: .messageRoutes) ?? [:]
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
        try container.encode(nodes, forKey: .nodes)
        try container.encode(manualEdges, forKey: .manualEdges)
        try container.encode(messageRoutes, forKey: .messageRoutes)
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
