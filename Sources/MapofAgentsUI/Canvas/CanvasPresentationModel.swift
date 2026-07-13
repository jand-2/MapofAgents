import MapofAgentsCore

/// A render-ready projection of the graph for one filter/focus state.
///
/// Computing this projection once prevents every node from independently
/// filtering the graph and walking all edges to rediscover its focus opacity.
struct CanvasPresentationModel {
    let nodes: [CanvasNode]
    let nodesByID: [NodeID: CanvasNode]
    let edges: [CanvasEdge]
    let manualEdges: [CanvasEdge]
    let focusedNodeID: NodeID?
    let focusedNeighborhood: Set<NodeID>

    init(
        graph: AgentGraph,
        allEdges: [CanvasEdge],
        showsSubagents: Bool,
        focusedNodeID: NodeID?
    ) {
        let visibleNodes = graph.sortedNodes.filter { node in
            showsSubagents || node.kind != .codexThread || node.metadata.threadKind != .subagent
        }
        let nodesByID = Dictionary(uniqueKeysWithValues: visibleNodes.map { ($0.id, $0) })
        let visibleEdges = allEdges.filter { edge in
            nodesByID[edge.source] != nil && nodesByID[edge.target] != nil
        }
        let visibleManualEdges = graph.manualEdges.values
            .filter { edge in nodesByID[edge.source] != nil && nodesByID[edge.target] != nil }
            .sorted { $0.id.rawValue < $1.id.rawValue }

        self.nodes = visibleNodes
        self.nodesByID = nodesByID
        self.edges = visibleEdges
        self.manualEdges = visibleManualEdges
        self.focusedNodeID = focusedNodeID.flatMap { nodesByID[$0] == nil ? nil : $0 }

        guard let focusedNodeID = self.focusedNodeID else {
            focusedNeighborhood = []
            return
        }

        var neighborhood: Set<NodeID> = [focusedNodeID]
        for edge in visibleEdges where edge.source == focusedNodeID || edge.target == focusedNodeID {
            neighborhood.insert(edge.source)
            neighborhood.insert(edge.target)
        }
        focusedNeighborhood = neighborhood
    }
}
