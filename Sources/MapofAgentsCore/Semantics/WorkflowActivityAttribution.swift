import Foundation

public struct WorkflowTurnOrigin: Hashable, Sendable {
    public var nodeID: NodeID
    public var threadID: String
    public var title: String
    public var hostID: HostID?

    public init(nodeID: NodeID, threadID: String, title: String, hostID: HostID?) {
        self.nodeID = nodeID
        self.threadID = threadID
        self.title = title
        self.hostID = hostID
    }
}

public enum WorkflowActivityAttribution {
    public static func origin(
        for event: WorkflowEvent,
        in graph: AgentGraph,
        events: [WorkflowEvent],
        window: TimeInterval = 10 * 60
    ) -> WorkflowTurnOrigin? {
        guard event.kind == .turnStarted || event.kind == .turnCompleted,
              let targetThreadID = event.threadID,
              let targetNode = node(forHostID: event.hostID, threadID: targetThreadID, in: graph) else {
            return nil
        }

        let basisEvent = basisStartEvent(for: event, events: events) ?? event
        if let routedSource = routeEvidenceSource(
            for: event,
            basisEvent: basisEvent,
            targetNode: targetNode,
            in: graph,
            window: window
        ) {
            return origin(from: routedSource)
        }

        let candidates = incomingThreadMessageSources(to: targetNode, in: graph)
        guard !candidates.isEmpty else { return nil }

        let candidatesWithRecentActivity = candidates.compactMap { node -> (CanvasNode, WorkflowEvent)? in
            guard let sourceThreadID = node.metadata.threadRef?.threadID,
                  let sourceHostID = node.metadata.threadRef?.hostID,
                  let lastEvent = mostRecentEvent(
                    forHostID: sourceHostID,
                    forThreadID: sourceThreadID,
                    before: basisEvent.createdAt,
                    in: events
                  ),
                  basisEvent.createdAt.timeIntervalSince(lastEvent.createdAt) <= window else {
                return nil
            }
            return (node, lastEvent)
        }

        guard let selected = candidatesWithRecentActivity.max(by: {
            $0.1.createdAt < $1.1.createdAt
        })?.0 else {
            return nil
        }

        return origin(from: selected)
    }

    private static func node(forHostID hostID: HostID?, threadID: String, in graph: AgentGraph) -> CanvasNode? {
        graph.nodes.values.first {
            $0.kind == .codexThread
                && $0.metadata.threadRef?.matches(hostID: hostID, threadID: threadID) == true
        }
    }

    private static func incomingThreadMessageSources(to targetNode: CanvasNode, in graph: AgentGraph) -> [CanvasNode] {
        graph.manualEdges.values
            .filter { edge in
                edge.kind == .threadMessage && edge.target == targetNode.id
            }
            .compactMap { edge in
                graph.nodes[edge.source]
            }
            .filter { node in
                node.kind == .codexThread && node.metadata.threadRef != nil
            }
    }

    private static func routeEvidenceSource(
        for event: WorkflowEvent,
        basisEvent: WorkflowEvent,
        targetNode: CanvasNode,
        in graph: AgentGraph,
        window: TimeInterval
    ) -> CanvasNode? {
        guard let targetThreadRef = targetNode.metadata.threadRef else {
            return nil
        }

        return graph.messageRoutes.values
            .compactMap { route -> RouteEvidenceCandidate? in
                guard
                    let strength = routeEvidenceStrength(
                        route,
                        event: event,
                        basisEvent: basisEvent,
                        targetThreadRef: targetThreadRef,
                        window: window
                    ),
                    let sourceNode = node(
                        forHostID: route.sourceHostID,
                        threadID: route.sourceThreadID,
                        in: graph
                    )
                else {
                    return nil
                }

                return RouteEvidenceCandidate(node: sourceNode, route: route, strength: strength)
            }
            .sorted { lhs, rhs in
                if lhs.strength != rhs.strength {
                    return lhs.strength > rhs.strength
                }
                let lhsDeliveryRank = deliveryRank(lhs.route.deliveryState)
                let rhsDeliveryRank = deliveryRank(rhs.route.deliveryState)
                if lhsDeliveryRank != rhsDeliveryRank {
                    return lhsDeliveryRank > rhsDeliveryRank
                }
                if lhs.route.timestamp != rhs.route.timestamp {
                    return lhs.route.timestamp > rhs.route.timestamp
                }
                return lhs.route.id < rhs.route.id
            }
            .first?
            .node
    }

    private static func routeEvidenceStrength(
        _ route: MessageRoute,
        event: WorkflowEvent,
        basisEvent: WorkflowEvent,
        targetThreadRef: ThreadRef,
        window: TimeInterval
    ) -> Int? {
        guard
            route.deliveryState == .delivered || route.deliveryState == .pending,
            route.targetHostID == targetThreadRef.hostID,
            route.targetThreadID == targetThreadRef.threadID
        else {
            return nil
        }

        if route.eventIDs.contains(event.id) || route.eventIDs.contains(basisEvent.id) {
            return 3
        }

        if let targetTurnID = route.targetTurnID {
            guard let eventTurnID = event.turnID ?? basisEvent.turnID, targetTurnID == eventTurnID else {
                return nil
            }
            return 2
        }

        guard route.eventIDs.isEmpty else {
            return nil
        }

        let age = basisEvent.createdAt.timeIntervalSince(route.timestamp)
        guard age >= 0, age <= window else {
            return nil
        }
        return 1
    }

    private static func deliveryRank(_ deliveryState: MessageRouteDeliveryState) -> Int {
        switch deliveryState {
        case .delivered:
            return 2
        case .pending:
            return 1
        case .failed, .unknown:
            return 0
        }
    }

    private static func basisStartEvent(for event: WorkflowEvent, events: [WorkflowEvent]) -> WorkflowEvent? {
        guard event.kind == .turnCompleted else {
            return event.kind == .turnStarted ? event : nil
        }

        return events
            .filter { candidate in
                candidate.kind == .turnStarted
                    && candidate.threadID == event.threadID
                    && (event.hostID == nil || candidate.hostID == nil || candidate.hostID == event.hostID)
                    && (event.turnID == nil || candidate.turnID == event.turnID)
                    && candidate.createdAt <= event.createdAt
            }
            .max { $0.createdAt < $1.createdAt }
    }

    private static func mostRecentEvent(
        forHostID hostID: HostID,
        forThreadID threadID: String,
        before date: Date,
        in events: [WorkflowEvent]
    ) -> WorkflowEvent? {
        events
            .filter { event in
                event.threadID == threadID
                    && (event.hostID == nil || event.hostID == hostID)
                    && event.createdAt <= date
                    && (event.kind == .turnStarted || event.kind == .turnCompleted)
            }
            .max { $0.createdAt < $1.createdAt }
    }

    private static func origin(from node: CanvasNode) -> WorkflowTurnOrigin? {
        guard let threadRef = node.metadata.threadRef else {
            return nil
        }

        return WorkflowTurnOrigin(
            nodeID: node.id,
            threadID: threadRef.threadID,
            title: node.title,
            hostID: threadRef.hostID
        )
    }

    private struct RouteEvidenceCandidate {
        var node: CanvasNode
        var route: MessageRoute
        var strength: Int
    }
}
