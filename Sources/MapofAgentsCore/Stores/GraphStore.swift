import Foundation
import Observation

public enum CanvasSelection: Hashable, Sendable {
    case none
    case node(NodeID)
    case edge(EdgeID)
}

@MainActor
@Observable
public final class GraphStore {
    public private(set) var graph: AgentGraph
    public private(set) var semanticEdges: [CanvasEdge] = []
    public var selection: CanvasSelection = .none
    public var pendingManualEdgeSource: NodeID?
    public var errorMessage: String?

    private let repository: any ControlRoomStore
    private let semanticResolver: any SemanticEdgeResolving

    public init(
        repository: any ControlRoomStore,
        semanticResolver: any SemanticEdgeResolving = DefaultSemanticEdgeResolver()
    ) {
        self.repository = repository
        self.semanticResolver = semanticResolver
        self.graph = AgentGraph()
    }

    public var allEdges: [CanvasEdge] {
        semanticEdges + graph.manualEdges.values.sorted { $0.id.rawValue < $1.id.rawValue }
    }

    public var selectedNode: CanvasNode? {
        guard case .node(let id) = selection else {
            return nil
        }
        return graph.nodes[id]
    }

    public var workflowThreadRefs: [ThreadRef] {
        graph.sortedNodes.compactMap { node in
            guard node.kind == .codexThread else { return nil }
            return node.metadata.threadRef
        }
    }

    public func workflowThreadMentionCandidates(excluding excludedThreadRef: ThreadRef? = nil) -> [MentionCandidate] {
        graph.sortedNodes.compactMap { node in
            guard
                node.kind == .codexThread,
                let threadRef = node.metadata.threadRef,
                threadRef != excludedThreadRef
            else {
                return nil
            }

            let encodedHost = Self.percentEncoded(threadRef.hostID.rawValue)
            let encodedThreadID = Self.percentEncoded(threadRef.threadID)
            let safeTitle = Self.escapedMentionLabel(node.title)
            let shortID = threadRef.threadID.prefix(8)

            return MentionCandidate(
                id: "thread-\(threadRef.hostID.rawValue)-\(threadRef.threadID)",
                kind: .thread,
                trigger: "@",
                label: node.title,
                title: node.title,
                subtitle: "\(threadRef.cwd) - \(shortID)",
                insertionText: "[@\"\(safeTitle)\" chat](codex-thread://\(encodedHost)/\(encodedThreadID))"
            )
        }
    }

    public func workflowFolderMentionCandidates() -> [MentionCandidate] {
        graph.sortedNodes.compactMap { node in
            guard
                node.kind == .folder,
                let hostID = node.metadata.hostID,
                let folderPath = node.metadata.folderPath
            else {
                return nil
            }

            let encodedHost = Self.percentEncoded(hostID.rawValue)
            let encodedNodeID = Self.percentEncoded(node.id.rawValue)
            let safeTitle = Self.escapedMentionLabel(node.title)
            let machineName = graph.nodes.values.first {
                $0.kind == .machine && $0.metadata.hostID == hostID
            }?.title

            return MentionCandidate(
                id: "folder-\(node.id.rawValue)",
                kind: .folder,
                trigger: "@",
                label: node.title,
                title: node.title,
                subtitle: [machineName, folderPath].compactMap(\.self).joined(separator: " - "),
                insertionText: "[@\"\(safeTitle)\" folder](mapofagents-folder://\(encodedHost)/\(encodedNodeID))"
            )
        }
    }

    public func load() async {
        do {
            let loadedGraph = try await repository.loadCanvas()
            let normalizedGraph = Self.graphByNormalizingLoadedGraph(loadedGraph)
            graph = normalizedGraph
            if normalizedGraph != loadedGraph {
                graph = try await repository.applyCanvasPatch(.replace(normalizedGraph))
            }
            selection = .none
            pendingManualEdgeSource = nil
            recalculateSemanticEdges()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func addFolder(
        path: String,
        hostID: HostID = HostID(rawValue: "local"),
        platform: HostPlatform = .macOS
    ) async {
        let title = Self.folderTitle(for: path)
        let node = CanvasNode(
            kind: .folder,
            title: title,
            subtitle: path,
            position: nextFolderPosition(hostID: hostID),
            size: .folder,
            metadata: NodeMetadata(
                hostID: hostID,
                platform: platform,
                folderPath: path,
                hasManualPosition: false
            ),
            zIndex: nextZIndex()
        )
        await apply(.upsertNode(node))
        selection = .node(node.id)
    }

    public func addThreadNode(
        threadRef: ThreadRef,
        model: String,
        reasoningEffort: String,
        title: String? = nil,
        anchorFolderID: NodeID? = nil,
        platform: HostPlatform = .macOS,
        permissions: CodexThreadPermissions? = nil,
        threadKind: CodexThreadNodeKind = .thread
    ) async {
        let node = CanvasNode(
            kind: .codexThread,
            title: Self.preferredDisplayName(title, threadRef.name) ?? "Codex thread",
            subtitle: threadRef.cwd,
            position: nextThreadPosition(anchorFolderID: anchorFolderID),
            size: .thread,
            metadata: NodeMetadata(
                hostID: threadRef.hostID,
                platform: platform,
                threadRef: threadRef,
                model: model,
                reasoningEffort: reasoningEffort,
                threadPermissions: permissions,
                threadKind: threadKind,
                runStatus: .idle,
                hasManualPosition: false
            ),
            zIndex: nextZIndex()
        )
        await apply(.upsertNode(node))
        selection = .node(node.id)
    }

    public func applyHost(_ host: AgentHost) async {
        await applySupervisorMachine(SupervisorMachine(host: host))
    }

    public func applySupervisorMachine(_ machine: SupervisorMachine) async {
        if let existingID = graph.nodes.values.first(where: { $0.kind == .machine && $0.metadata.hostID == machine.id })?.id,
           var node = graph.nodes[existingID] {
            node.title = machine.name
            node.subtitle = machine.subtitle
            node.metadata.platform = machine.platform
            node.metadata.hostStatus = HostStatus(machine.status)
            node.metadata.codexHome = machine.codexHome
            await apply(.upsertNode(node))
            return
        }

        let node = CanvasNode(
            id: machine.id.rawValue == "local" ? NodeID(rawValue: "local-machine") : .fresh(),
            kind: .machine,
            title: machine.name,
            subtitle: machine.subtitle,
            position: nextMachinePosition(),
            size: .machine,
            metadata: NodeMetadata(
                hostID: machine.id,
                platform: machine.platform,
                hostStatus: HostStatus(machine.status),
                codexHome: machine.codexHome,
                hasManualPosition: false
            ),
            zIndex: nextZIndex()
        )
        await apply(.upsertNode(node))
    }

    public func applySupervisorMachines(_ machines: [SupervisorMachine]) async {
        var nextGraph = graph
        let connectedMachineIDs = Set(machines.map(\.id))

        for machine in machines where machine.id != Self.localHostID {
            if let existingID = nextGraph.nodes.values.first(where: { $0.kind == .machine && $0.metadata.hostID == machine.id })?.id,
               var node = nextGraph.nodes[existingID] {
                node.title = machine.name
                node.subtitle = machine.subtitle
                node.metadata.platform = machine.platform
                node.metadata.hostStatus = HostStatus(machine.status)
                node.metadata.codexHome = machine.codexHome
                nextGraph.upsertNode(node)
            } else {
                nextGraph.upsertNode(
                    CanvasNode(
                        id: machine.id.rawValue == "local" ? NodeID(rawValue: "local-machine") : .fresh(),
                        kind: .machine,
                        title: machine.name,
                        subtitle: machine.subtitle,
                        position: nextMachinePosition(in: nextGraph),
                        size: .machine,
                        metadata: NodeMetadata(
                            hostID: machine.id,
                            platform: machine.platform,
                            hostStatus: HostStatus(machine.status),
                            codexHome: machine.codexHome,
                            hasManualPosition: false
                        ),
                        zIndex: nextZIndex(in: nextGraph)
                    )
                )
            }
        }

        for (_, node) in nextGraph.nodes where node.kind == .machine {
            guard let hostID = node.metadata.hostID, !connectedMachineIDs.contains(hostID) else {
                continue
            }
            guard hostID != Self.localHostID else {
                continue
            }
            var disconnectedNode = node
            disconnectedNode.metadata.hostStatus = .disconnected
            nextGraph.upsertNode(disconnectedNode)
        }

        await apply(.replace(nextGraph))
    }

    public func moveNode(id: NodeID, to position: CanvasPoint) async {
        await apply(.moveNode(id, position))
    }

    public func updateViewport(_ viewport: CanvasViewport) async {
        await apply(.updateViewport(Self.clamped(viewport)))
    }

    public func panViewport(dx: Double, dy: Double) async {
        let viewport = graph.viewport
        await updateViewport(
            CanvasViewport(
                scale: viewport.scale,
                offset: viewport.offset.offsetBy(dx: dx, dy: dy)
            )
        )
    }

    public func zoomViewport(by factor: Double) async {
        let viewport = graph.viewport
        await updateViewport(
            CanvasViewport(
                scale: viewport.scale * factor,
                offset: viewport.offset
            )
        )
    }

    public func resetViewport() async {
        await updateViewport(.standard)
    }

    public func autoArrange(availableWidth: Double? = nil) async {
        var arrangedGraph = graph
        let machines = graph.sortedNodes.filter { $0.kind == .machine }
        let folders = graph.sortedNodes.filter { $0.kind == .folder }
        let threads = graph.sortedNodes.filter { $0.kind == .codexThread }

        let machineTopY = 130.0
        let folderTopY = 330.0
        let threadTopY = 560.0
        let machineStartX = 140.0
        let threadColumns = 3
        let visibleWidth = max(0, availableWidth ?? 1_280.0)
        let layoutWidth = max(760.0, visibleWidth - 640.0)
        let minimumThreadSpacing = CanvasSize.thread.width + 90.0
        let maximumThreadSpacing = CanvasSize.thread.width + 230.0
        let rawThreadSpacing = (layoutWidth - CanvasSize.thread.width) / Double(threadColumns - 1)
        let threadSpacing = min(maximumThreadSpacing, max(minimumThreadSpacing, rawThreadSpacing))
        let threadBandWidth = CanvasSize.thread.width + Double(threadColumns - 1) * threadSpacing
        let machineSpacing = min(420.0, max(280.0, threadBandWidth / 2.0 + 80.0))
        let folderSpacing = threadBandWidth + 170.0
        let threadRowSpacing = CanvasSize.thread.height + 64.0
        let subagentSectionSpacing = 96.0
        var placedThreadIDs = Set<NodeID>()
        var folderGridIndex = 0

        func placeThreadRows(_ rows: [CanvasNode], baseX: Double, baseY: Double) {
            let regularThreads = rows.filter { $0.metadata.threadKind != .subagent }
            let subagents = rows.filter { $0.metadata.threadKind == .subagent }

            for (threadIndex, thread) in regularThreads.enumerated() {
                arrangedGraph.updateNodePosition(
                    id: thread.id,
                    position: CanvasPoint(
                        x: baseX + Double(threadIndex % threadColumns) * threadSpacing,
                        y: baseY + Double(threadIndex / threadColumns) * threadRowSpacing
                    )
                )
                placedThreadIDs.insert(thread.id)
            }

            let regularRowCount = max(regularThreads.isEmpty ? 0 : 1, Int(ceil(Double(regularThreads.count) / Double(threadColumns))))
            let subagentBaseY = baseY + Double(regularRowCount) * threadRowSpacing + (regularThreads.isEmpty ? 0 : subagentSectionSpacing)
            for (threadIndex, thread) in subagents.enumerated() {
                arrangedGraph.updateNodePosition(
                    id: thread.id,
                    position: CanvasPoint(
                        x: baseX + Double(threadIndex % threadColumns) * threadSpacing,
                        y: subagentBaseY + Double(threadIndex / threadColumns) * threadRowSpacing
                    )
                )
                placedThreadIDs.insert(thread.id)
            }
        }

        for (machineIndex, machine) in machines.enumerated() {
            let machineX = machineStartX + Double(machineIndex) * machineSpacing
            arrangedGraph.updateNodePosition(id: machine.id, position: CanvasPoint(x: machineX, y: machineTopY))

            let hostID = machine.metadata.hostID
            let hostFolders = folders.filter { $0.metadata.hostID == hostID }

            for folder in hostFolders {
                let folderPosition = CanvasPoint(
                    x: machineStartX + 90 + Double(folderGridIndex) * folderSpacing,
                    y: folderTopY
                )
                folderGridIndex += 1
                arrangedGraph.updateNodePosition(id: folder.id, position: folderPosition)

                let projectThreads = threads.filter { thread in
                    guard !placedThreadIDs.contains(thread.id) else { return false }
                    guard
                        let folderPath = folder.metadata.folderPath,
                        let threadRef = thread.metadata.threadRef,
                        threadRef.hostID == hostID
                    else { return false }

                    return Self.path(threadRef.cwd, isInsideOrEqualTo: folderPath)
                }

                placeThreadRows(projectThreads, baseX: folderPosition.x, baseY: threadTopY)
            }

            let nonProjectThreads = threads.filter {
                $0.metadata.threadRef?.hostID == hostID && !placedThreadIDs.contains($0.id)
            }
            let scratchY = threadTopY + max(1.0, Double(hostFolders.count)) * 190
            placeThreadRows(nonProjectThreads, baseX: machineX, baseY: scratchY)
        }

        await apply(.replace(arrangedGraph))
    }

    public func updateNodeTitle(id: NodeID, title: String) async {
        guard var node = graph.nodes[id] else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        node.title = trimmed
        await apply(.upsertNode(node))
        selection = .node(id)
    }

    public func updateFolderPath(id: NodeID, path: String) async {
        guard var node = graph.nodes[id], node.kind == .folder else { return }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        node.subtitle = trimmed
        node.metadata.folderPath = trimmed
        await apply(.upsertNode(node))
        selection = .node(id)
    }

    public func updateNodePopoverOffset(id: NodeID, offset: CanvasPoint) async {
        guard var node = graph.nodes[id] else { return }
        node.metadata.popoverOffset = offset
        await apply(.upsertNode(node))
        selection = .node(id)
    }

    public func markThreadRead(_ id: NodeID) async {
        await setThreadUnread(id, isUnread: false)
    }

    public func markThreadUnread(_ id: NodeID) async {
        await setThreadUnread(id, isUnread: true)
    }

    public func setThreadUnread(_ id: NodeID, isUnread: Bool) async {
        guard var node = graph.nodes[id], node.kind == .codexThread else { return }
        node.metadata.isUnread = isUnread
        await apply(.upsertNode(node))
        if selectedNode?.id == id {
            selection = .node(id)
        }
    }

    public func updateThreadRunStatus(for threadRef: ThreadRef, status: ThreadRunStatus) async {
        guard let nodeID = matchingThreadNodeID(hostID: threadRef.hostID, threadID: threadRef.threadID),
              var node = graph.nodes[nodeID],
              node.kind == .codexThread,
              node.metadata.runStatus != status
        else {
            return
        }

        node.metadata.runStatus = status
        await apply(.upsertNode(node))
        if selectedNode?.id == nodeID {
            selection = .node(nodeID)
        }
    }

    public func updateManualEdgeLabel(id: EdgeID, label: String) async {
        guard var edge = graph.manualEdges[id] else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        edge.label = trimmed.isEmpty ? nil : trimmed
        await apply(.upsertManualEdge(edge))
        selection = .edge(id)
    }

    public func deleteSelection() async {
        switch selection {
        case .node(let id):
            await deleteNode(id)
        case .edge(let id):
            await deleteManualEdge(id)
        case .none:
            return
        }
    }

    public func deleteNode(_ id: NodeID) async {
        await apply(.removeNode(id))
        selection = .none
    }

    public func deleteManualEdge(_ id: EdgeID) async {
        await apply(.removeManualEdge(id))
        selection = .none
    }

    public func selectNode(_ id: NodeID) {
        pendingManualEdgeSource = nil
        selection = .node(id)
    }

    public func selectEdge(_ id: EdgeID) {
        pendingManualEdgeSource = nil
        selection = .edge(id)
    }

    public func selectThread(hostID: HostID?, threadID: String) {
        guard let nodeID = graph.nodes.values.first(where: {
            $0.metadata.threadRef?.matches(hostID: hostID, threadID: threadID) == true
        })?.id else {
            return
        }
        selectNode(nodeID)
    }

    public func selectThread(_ threadRef: ThreadRef) {
        selectThread(hostID: threadRef.hostID, threadID: threadRef.threadID)
    }

    public func clearSelection() {
        pendingManualEdgeSource = nil
        selection = .none
    }

    public func beginManualEdge(from nodeID: NodeID) {
        if pendingManualEdgeSource == nodeID {
            pendingManualEdgeSource = nil
            return
        }

        pendingManualEdgeSource = nodeID
    }

    public func completeManualEdge(to nodeID: NodeID) async {
        guard let source = pendingManualEdgeSource, source != nodeID else {
            pendingManualEdgeSource = nil
            return
        }

        let edge = CanvasEdge(
            source: source,
            target: nodeID,
            kind: .manualNote,
            isManual: true,
            label: "note"
        )
        pendingManualEdgeSource = nil
        await apply(.upsertManualEdge(edge))
        selection = .edge(edge.id)
    }

    public func createMessageEdge(
        from source: NodeID,
        to target: NodeID,
        snippet: String = "",
        deliveryState: MessageRouteDeliveryState = .delivered,
        eventIDs: [String] = []
    ) async {
        let sourceThreadRef = graph.nodes[source]?.metadata.threadRef
        let targetThreadRef = graph.nodes[target]?.metadata.threadRef
        let edgeID: EdgeID

        if let existing = graph.manualEdges.values.first(where: {
            $0.source == source && $0.target == target && $0.kind == .threadMessage
        }) {
            var edge = existing
            edge.label = "message"
            await apply(.upsertManualEdge(edge))
            edgeID = edge.id
        } else {
            let edge = CanvasEdge(
                source: source,
                target: target,
                kind: .threadMessage,
                isManual: true,
                label: "message"
            )
            await apply(.upsertManualEdge(edge))
            edgeID = edge.id
        }

        guard let sourceThreadRef, let targetThreadRef else {
            return
        }

        let route = MessageRoute(
            sourceHostID: sourceThreadRef.hostID,
            sourceThreadID: sourceThreadRef.threadID,
            targetHostID: targetThreadRef.hostID,
            targetThreadID: targetThreadRef.threadID,
            snippet: snippet,
            deliveryState: deliveryState,
            eventIDs: eventIDs,
            canvasEdgeID: edgeID
        )
        await apply(.upsertMessageRoute(route))
    }

    public func materializeCreatedThread(
        threadRef: ThreadRef,
        model: String?,
        reasoningEffort: String?,
        title: String?,
        createdBy sourceID: NodeID,
        threadKind: CodexThreadNodeKind = .thread
    ) async {
        guard !graph.isAutoMaterializationSuppressed(for: threadRef) else {
            return
        }

        let targetID: NodeID

        if let existingID = graph.nodes.values.first(where: { node in
            guard node.kind == .codexThread,
                  let existingThreadRef = node.metadata.threadRef
            else {
                return false
            }
            return existingThreadRef.hostID == threadRef.hostID
                && existingThreadRef.threadID.caseInsensitiveCompare(threadRef.threadID) == .orderedSame
        })?.id {
            targetID = existingID
            await updateExistingCreatedThreadNode(id: existingID, with: threadRef, title: title, threadKind: threadKind)
        } else if let existingID = likelyDuplicateSubagentNodeID(
            for: threadRef,
            title: title,
            createdBy: sourceID,
            threadKind: threadKind
        ) {
            targetID = existingID
            await updateExistingCreatedThreadNode(id: existingID, with: threadRef, title: title, threadKind: threadKind)
        } else {
            let source = graph.nodes[sourceID]
            let platform = graph.nodes.values.first {
                $0.metadata.hostID == threadRef.hostID && $0.metadata.platform != nil
            }?.metadata.platform ?? source?.metadata.platform ?? .macOS
            let displayTitle = createdThreadDisplayTitle(
                for: threadRef,
                title: title,
                createdBy: sourceID,
                threadKind: threadKind
            )
            let node = CanvasNode(
                kind: .codexThread,
                title: displayTitle,
                subtitle: threadRef.cwd,
                position: createdThreadPosition(near: source),
                size: .thread,
                metadata: NodeMetadata(
                    hostID: threadRef.hostID,
                    platform: platform,
                    threadRef: threadRef,
                    model: model,
                    reasoningEffort: reasoningEffort,
                    threadKind: threadKind,
                    runStatus: .idle,
                    hasManualPosition: false
                ),
                zIndex: nextZIndex()
            )
            targetID = node.id
            await apply(.upsertNode(node))
        }

        await createCreatedByEdge(from: sourceID, to: targetID)
    }

    private func createdThreadDisplayTitle(
        for threadRef: ThreadRef,
        title: String?,
        createdBy sourceID: NodeID,
        threadKind: CodexThreadNodeKind
    ) -> String {
        let preferredTitle = Self.preferredDisplayName(title, threadRef.name) ?? "Created thread"
        guard threadKind == .subagent,
              let incomingTitle = Self.subagentDuplicateTitle(title: preferredTitle, threadRef: threadRef)
        else {
            return preferredTitle
        }

        let incomingCWD = Self.subagentDuplicateCWD(threadRef.cwd)
        let matchingNodes = graph.nodes.values.filter { node in
            guard node.kind == .codexThread,
                  node.metadata.threadKind == .subagent,
                  let existingThreadRef = node.metadata.threadRef,
                  existingThreadRef.hostID == threadRef.hostID,
                  existingThreadRef.threadID.caseInsensitiveCompare(threadRef.threadID) != .orderedSame,
                  Self.subagentDuplicateCWD(existingThreadRef.cwd) == incomingCWD,
                  Self.subagentDuplicateTitle(title: node.title, threadRef: existingThreadRef) == incomingTitle
            else {
                return false
            }
            return true
        }

        guard !matchingNodes.isEmpty else {
            return preferredTitle
        }

        let sameParent = matchingNodes.contains { node in
            graph.manualEdges.values.contains { edge in
                edge.kind == .createdBy && edge.source == sourceID && edge.target == node.id
            }
        }
        let suffix = sameParent ? "retry" : "fork"
        return "\(preferredTitle) \(suffix)"
    }

    private func updateExistingCreatedThreadNode(
        id: NodeID,
        with threadRef: ThreadRef,
        title: String?,
        threadKind: CodexThreadNodeKind
    ) async {
        guard var existingNode = graph.nodes[id],
              let existingThreadRef = existingNode.metadata.threadRef
        else {
            return
        }

        let merged = Self.mergedThreadRef(existingThreadRef, with: threadRef)
        let preferredTitle = Self.preferredDisplayName(existingNode.title, title ?? merged.name)
        if merged != existingThreadRef {
            existingNode.metadata.threadRef = merged
            existingNode.metadata.hostID = merged.hostID
            existingNode.metadata.threadKind = Self.mergedThreadKind(existingNode.metadata.threadKind, incoming: threadKind)
            if let preferredTitle, preferredTitle != existingNode.title {
                existingNode.title = preferredTitle
            }
            if !merged.cwd.isEmpty {
                existingNode.subtitle = merged.cwd
            }
            await apply(.upsertNode(existingNode))
        } else if let preferredTitle, preferredTitle != existingNode.title {
            existingNode.title = preferredTitle
            existingNode.metadata.threadKind = Self.mergedThreadKind(existingNode.metadata.threadKind, incoming: threadKind)
            await apply(.upsertNode(existingNode))
        } else if Self.mergedThreadKind(existingNode.metadata.threadKind, incoming: threadKind) != existingNode.metadata.threadKind {
            existingNode.metadata.threadKind = Self.mergedThreadKind(existingNode.metadata.threadKind, incoming: threadKind)
            await apply(.upsertNode(existingNode))
        }
    }

    private func likelyDuplicateSubagentNodeID(
        for threadRef: ThreadRef,
        title: String?,
        createdBy sourceID: NodeID,
        threadKind: CodexThreadNodeKind
    ) -> NodeID? {
        guard threadKind == .subagent,
              let incomingTitle = Self.subagentDuplicateTitle(title: title, threadRef: threadRef)
        else {
            return nil
        }

        let incomingCWD = Self.subagentDuplicateCWD(threadRef.cwd)
        let edgeCounts = Self.manualEdgeCounts(in: graph)
        let createdTargetIDs = Set(graph.manualEdges.values.compactMap { edge -> NodeID? in
            guard edge.kind == .createdBy, edge.source == sourceID else { return nil }
            return edge.target
        })

        return graph.nodes.values
            .filter { node in
                guard createdTargetIDs.contains(node.id),
                      node.kind == .codexThread,
                      node.metadata.threadKind == .subagent,
                      let existingThreadRef = node.metadata.threadRef,
                      existingThreadRef.hostID == threadRef.hostID,
                      existingThreadRef.threadID.caseInsensitiveCompare(threadRef.threadID) != .orderedSame,
                      Self.subagentDuplicateCWD(existingThreadRef.cwd) == incomingCWD,
                      Self.subagentDuplicateTitle(title: node.title, threadRef: existingThreadRef) == incomingTitle
                else {
                    return false
                }
                return true
            }
            .max {
                Self.duplicateThreadNodeRankIsLess($0, $1, edgeCounts: edgeCounts)
            }?
            .id
    }

    private static func subagentDuplicateTitle(title: String?, threadRef: ThreadRef) -> String? {
        guard let displayName = preferredDisplayName(title, threadRef.name),
              let normalized = normalizedDisplayName(displayName)
        else {
            return nil
        }
        return normalizedDedupeText(normalized)
    }

    private static func subagentDuplicateCWD(_ cwd: String) -> String {
        let trimmed = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return standardizePath(trimmed)
    }

    private static func normalizedDedupeText(_ value: String) -> String {
        value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func mergedThreadRef(_ existing: ThreadRef, with incoming: ThreadRef) -> ThreadRef {
        ThreadRef(
            hostID: existing.hostID,
            threadID: existing.threadID,
            cwd: incoming.cwd.isEmpty ? existing.cwd : incoming.cwd,
            name: preferredDisplayName(existing.name, incoming.name)
        )
    }

    private static func mergedThreadKind(
        _ existing: CodexThreadNodeKind?,
        incoming: CodexThreadNodeKind
    ) -> CodexThreadNodeKind {
        if existing == .subagent || incoming == .subagent {
            return .subagent
        }
        return existing ?? incoming
    }

    public func applyWorkflowEvent(_ event: WorkflowEvent, markUnread: Bool = false) async {
        guard
            let threadID = event.threadID,
            let nodeID = matchingThreadNodeID(hostID: event.hostID, threadID: threadID),
            var node = graph.nodes[nodeID]
        else {
            return
        }

        node.metadata.runStatus = Self.runStatus(for: event.kind)
        if markUnread, event.kind == .turnCompleted {
            node.metadata.isUnread = true
        }
        await apply(.upsertNode(node))
    }

    private func createCreatedByEdge(from source: NodeID, to target: NodeID) async {
        if let existing = graph.manualEdges.values.first(where: {
            $0.source == source && $0.target == target && $0.kind == .createdBy
        }) {
            var edge = existing
            edge.label = "created by"
            await apply(.upsertManualEdge(edge))
            return
        }

        let edge = CanvasEdge(
            source: source,
            target: target,
            kind: .createdBy,
            isManual: true,
            label: "created by"
        )
        await apply(.upsertManualEdge(edge))
    }

    private static func runStatus(for eventKind: WorkflowEventKind) -> ThreadRunStatus {
        switch eventKind {
        case .turnStarted:
            return .running
        case .turnCompleted:
            return .complete
        case .threadCreated:
            return .complete
        case .needsInput:
            return .needsInput
        case .failed:
            return .failed
        }
    }

    private func apply(_ patch: CanvasPatch) async {
        do {
            graph = try await repository.applyCanvasPatch(patch)
            recalculateSemanticEdges()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func recalculateSemanticEdges() {
        semanticEdges = semanticResolver.resolveEdges(in: graph)
    }

    private static func graphByNormalizingLoadedGraph(_ graph: AgentGraph) -> AgentGraph {
        graphByNormalizingThreadDisplayNames(
            graphByRemovingOrphansAndDuplicateThreadNodes(
                graphByMarkingLegacySavedPositions(
                    graphByResettingTransientRunStatuses(graph)
                )
            )
        )
    }

    private static func graphByMarkingLegacySavedPositions(_ graph: AgentGraph) -> AgentGraph {
        var graph = graph
        var changed = false
        for (id, var node) in graph.nodes where node.metadata.hasManualPosition == nil {
            node.metadata.hasManualPosition = true
            graph.nodes[id] = node
            changed = true
        }
        if changed {
            graph.updatedAt = Date()
        }
        return graph
    }

    private static func graphByResettingTransientRunStatuses(_ graph: AgentGraph) -> AgentGraph {
        var graph = graph
        for (id, var node) in graph.nodes where node.kind == .codexThread && node.metadata.runStatus == .running {
            node.metadata.runStatus = .idle
            graph.nodes[id] = node
        }
        return graph
    }

    private static func graphByRemovingOrphansAndDuplicateThreadNodes(_ graph: AgentGraph) -> AgentGraph {
        var graph = graph
        var changed = false
        var replacementNodeIDs: [NodeID: NodeID] = [:]
        let edgeCounts = manualEdgeCounts(in: graph)
        let groupedThreadNodes = Dictionary(grouping: graph.nodes.values.compactMap { node -> (String, CanvasNode)? in
            guard let key = threadIdentityKey(for: node) else { return nil }
            return (key, node)
        }, by: \.0)

        for (_, keyedNodes) in groupedThreadNodes where keyedNodes.count > 1 {
            let duplicates = keyedNodes.map(\.1)
            guard var canonical = duplicates.max(by: { lhs, rhs in
                duplicateThreadNodeRankIsLess(lhs, rhs, edgeCounts: edgeCounts)
            }) else {
                continue
            }

            for duplicate in duplicates where duplicate.id != canonical.id {
                canonical = mergedThreadNode(canonical, with: duplicate)
                replacementNodeIDs[duplicate.id] = canonical.id
                graph.nodes[duplicate.id] = nil
                changed = true
            }
            if graph.nodes[canonical.id] != canonical {
                graph.nodes[canonical.id] = canonical
                changed = true
            }
        }

        var nextManualEdges: [EdgeID: CanvasEdge] = [:]
        var seenEdgeKeys = Set<String>()
        for edge in graph.manualEdges.values.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            var remapped = edge
            remapped.source = replacementNodeIDs[edge.source] ?? edge.source
            remapped.target = replacementNodeIDs[edge.target] ?? edge.target

            guard graph.nodes[remapped.source] != nil,
                  graph.nodes[remapped.target] != nil
            else {
                changed = true
                continue
            }

            let edgeKey = "\(remapped.kind.rawValue)::\(remapped.source.rawValue)::\(remapped.target.rawValue)"
            guard seenEdgeKeys.insert(edgeKey).inserted else {
                changed = true
                continue
            }
            nextManualEdges[remapped.id] = remapped
            if remapped != edge {
                changed = true
            }
        }
        if graph.manualEdges != nextManualEdges {
            graph.manualEdges = nextManualEdges
            changed = true
        }

        let keptEdgeIDs = Set(nextManualEdges.keys)
        let nextMessageRoutes = graph.messageRoutes.filter { _, route in
            guard let canvasEdgeID = route.canvasEdgeID else { return true }
            return keptEdgeIDs.contains(canvasEdgeID)
        }
        if graph.messageRoutes != nextMessageRoutes {
            graph.messageRoutes = nextMessageRoutes
            changed = true
        }

        if changed {
            graph.updatedAt = Date()
        }
        return graph
    }

    private static func graphByNormalizingThreadDisplayNames(_ graph: AgentGraph) -> AgentGraph {
        var graph = graph
        var changed = false

        for (id, var node) in graph.nodes where node.kind == .codexThread {
            let normalizedTitle: String?
            if displayNameScore(node.title) <= 1 {
                normalizedTitle = preferredDisplayName(node.title, node.metadata.threadRef?.name)
            } else {
                normalizedTitle = normalizedDisplayName(node.title)
            }
            if let normalizedTitle, normalizedTitle != node.title {
                node.title = normalizedTitle
                changed = true
            }

            if var threadRef = node.metadata.threadRef {
                let normalizedName = normalizedDisplayName(threadRef.name)
                if normalizedName != threadRef.name {
                    threadRef.name = normalizedName
                    node.metadata.threadRef = threadRef
                    changed = true
                }
            }

            if graph.nodes[id] != node {
                graph.nodes[id] = node
                changed = true
            }
        }

        if changed {
            graph.updatedAt = Date()
        }
        return graph
    }

    private static func threadIdentityKey(for node: CanvasNode) -> String? {
        guard node.kind == .codexThread,
              let threadRef = node.metadata.threadRef
        else {
            return nil
        }
        return "\(threadRef.hostID.rawValue)::\(threadRef.threadID.lowercased())"
    }

    private static func manualEdgeCounts(in graph: AgentGraph) -> [NodeID: Int] {
        var counts: [NodeID: Int] = [:]
        for edge in graph.manualEdges.values {
            counts[edge.source, default: 0] += 1
            counts[edge.target, default: 0] += 1
        }
        return counts
    }

    private static func duplicateThreadNodeRank(_ node: CanvasNode, edgeCounts: [NodeID: Int]) -> (Int, Int, Int) {
        (
            edgeCounts[node.id, default: 0],
            displayNameScore(node.title),
            node.zIndex
        )
    }

    private static func duplicateThreadNodeRankIsLess(
        _ lhs: CanvasNode,
        _ rhs: CanvasNode,
        edgeCounts: [NodeID: Int]
    ) -> Bool {
        let lhsRank = duplicateThreadNodeRank(lhs, edgeCounts: edgeCounts)
        let rhsRank = duplicateThreadNodeRank(rhs, edgeCounts: edgeCounts)
        if lhsRank.0 != rhsRank.0 {
            return lhsRank.0 < rhsRank.0
        }
        if lhsRank.1 != rhsRank.1 {
            return lhsRank.1 < rhsRank.1
        }
        return lhsRank.2 < rhsRank.2
    }

    private static func mergedThreadNode(_ canonical: CanvasNode, with duplicate: CanvasNode) -> CanvasNode {
        var merged = canonical
        if let duplicateThreadRef = duplicate.metadata.threadRef {
            if let currentThreadRef = merged.metadata.threadRef {
                merged.metadata.threadRef = mergedThreadRef(currentThreadRef, with: duplicateThreadRef)
            } else {
                merged.metadata.threadRef = duplicateThreadRef
            }
        }
        merged.metadata.hostID = merged.metadata.hostID ?? duplicate.metadata.hostID
        merged.metadata.platform = merged.metadata.platform ?? duplicate.metadata.platform
        merged.metadata.model = merged.metadata.model ?? duplicate.metadata.model
        merged.metadata.reasoningEffort = merged.metadata.reasoningEffort ?? duplicate.metadata.reasoningEffort
        merged.metadata.threadPermissions = merged.metadata.threadPermissions ?? duplicate.metadata.threadPermissions
        merged.metadata.popoverOffset = merged.metadata.popoverOffset ?? duplicate.metadata.popoverOffset
        merged.metadata.isUnread = (merged.metadata.isUnread == true || duplicate.metadata.isUnread == true)
        merged.metadata.hasManualPosition = (merged.metadata.hasManualPosition == true || duplicate.metadata.hasManualPosition == true)
        merged.metadata.runStatus = preferredRunStatus(merged.metadata.runStatus, duplicate.metadata.runStatus)

        if let preferredTitle = preferredDisplayName(merged.title, duplicate.title) {
            merged.title = preferredTitle
        }
        if merged.subtitle.isEmpty, !duplicate.subtitle.isEmpty {
            merged.subtitle = duplicate.subtitle
        }
        merged.zIndex = max(merged.zIndex, duplicate.zIndex)
        return merged
    }

    private static func preferredRunStatus(_ lhs: ThreadRunStatus?, _ rhs: ThreadRunStatus?) -> ThreadRunStatus? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        return runStatusRank(rhs) > runStatusRank(lhs) ? rhs : lhs
    }

    private static func runStatusRank(_ status: ThreadRunStatus) -> Int {
        switch status {
        case .running:
            return 5
        case .needsInput:
            return 4
        case .failed:
            return 3
        case .complete:
            return 2
        case .idle:
            return 1
        case .unknown:
            return 0
        }
    }

    private static func preferredDisplayName(_ current: String?, _ incoming: String?) -> String? {
        let current = normalizedDisplayName(current)
        let incoming = normalizedDisplayName(incoming)
        guard let current else { return incoming }
        guard let incoming else { return current }

        let currentScore = displayNameScore(current)
        let incomingScore = displayNameScore(incoming)
        if incomingScore > currentScore {
            return incoming
        }
        return current
    }

    private static func normalizedDisplayName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let firstLine = trimmed
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let firstLine, !firstLine.isEmpty else {
            return trimmed
        }

        if firstLine.localizedCaseInsensitiveContains("thread name:") {
            let pieces = firstLine.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            if pieces.count == 2 {
                let named = String(pieces[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !named.isEmpty {
                    return named
                }
            }
        }

        return trimmed
    }

    private static func displayNameScore(_ value: String) -> Int {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        if trimmed == "Created thread" || trimmed == "Codex thread" {
            return 1
        }
        if trimmed.localizedCaseInsensitiveContains("thread name:") || trimmed.contains("\n") || trimmed.count > 80 {
            return 2
        }
        if trimmed.lowercased().hasPrefix("worker ") {
            return 3
        }
        return 4
    }

    private func nextOpenPosition() -> CanvasPoint {
        nextOpenPosition(in: graph)
    }

    private func nextOpenPosition(in graph: AgentGraph) -> CanvasPoint {
        let index = Double(graph.nodes.count)
        return CanvasPoint(x: 180 + index * 52, y: 520 + index * 36)
    }

    private func nextMachinePosition() -> CanvasPoint {
        nextMachinePosition(in: graph)
    }

    private func nextMachinePosition(in graph: AgentGraph) -> CanvasPoint {
        let index = Double(graph.nodes.values.filter { $0.kind == .machine }.count)
        return avoidCollisions(
            startingAt: CanvasPoint(x: 140 + index * 280, y: 130),
            in: graph
        )
    }

    private func nextFolderPosition(hostID: HostID) -> CanvasPoint {
        let machine = graph.nodes.values.first {
            $0.kind == .machine && $0.metadata.hostID == hostID
        }
        let existingFolderCount = graph.nodes.values.filter {
            $0.kind == .folder && $0.metadata.hostID == hostID
        }.count
        let origin = CanvasPoint(
            x: (machine?.position.x ?? 180) + 220 + Double(existingFolderCount) * 300,
            y: max(330, (machine?.position.y ?? 130) + 200)
        )
        return avoidCollisions(startingAt: origin)
    }

    private func nextThreadPosition(anchorFolderID: NodeID?) -> CanvasPoint {
        if let anchorFolderID, let folder = graph.nodes[anchorFolderID] {
            let candidate = CanvasPoint(
                x: folder.position.x,
                y: folder.position.y + folder.size.height + 150
            )
            return avoidCollisions(startingAt: candidate)
        }

        return avoidCollisions(startingAt: nextOpenPosition())
    }

    private func avoidCollisions(startingAt point: CanvasPoint) -> CanvasPoint {
        avoidCollisions(startingAt: point, in: graph)
    }

    private func avoidCollisions(startingAt point: CanvasPoint, in graph: AgentGraph) -> CanvasPoint {
        var candidate = point
        var attempts = 0

        while graph.nodes.values.contains(where: { overlaps(candidate, with: $0) }), attempts < 80 {
            attempts += 1
            let column = attempts % 5
            let row = attempts / 5
            candidate = point.offsetBy(
                dx: Double(column) * 240 + Double(row % 2) * 72,
                dy: Double(row) * 150
            )
        }

        return candidate
    }

    private func createdThreadPosition(near source: CanvasNode?) -> CanvasPoint {
        guard let source else {
            return avoidCollisions(startingAt: nextOpenPosition())
        }

        let origin = CanvasPoint(
            x: source.position.x + source.size.width + 170,
            y: source.position.y + 120
        )
        return avoidCreatedThreadCollisions(startingAt: origin)
    }

    private func avoidCreatedThreadCollisions(startingAt point: CanvasPoint) -> CanvasPoint {
        let offsets: [CanvasPoint] = [
            CanvasPoint(x: 0, y: 0),
            CanvasPoint(x: 0, y: 160),
            CanvasPoint(x: 0, y: -160),
            CanvasPoint(x: 250, y: 0),
            CanvasPoint(x: 250, y: 160),
            CanvasPoint(x: 250, y: -160),
            CanvasPoint(x: -110, y: 220),
            CanvasPoint(x: -110, y: -220),
            CanvasPoint(x: 500, y: 0),
            CanvasPoint(x: 500, y: 160),
            CanvasPoint(x: 500, y: -160),
        ]

        for offset in offsets {
            let candidate = point.offsetBy(dx: offset.x, dy: offset.y)
            if !graph.nodes.values.contains(where: { overlaps(candidate, with: $0) }) {
                return candidate
            }
        }

        return avoidCollisions(startingAt: point.offsetBy(dx: 500, dy: 260))
    }

    private func overlaps(_ point: CanvasPoint, with node: CanvasNode) -> Bool {
        let horizontalDistance = abs(point.x - node.position.x)
        let verticalDistance = abs(point.y - node.position.y)
        return horizontalDistance < (node.size.width / 2 + CanvasSize.thread.width / 2 + 24)
            && verticalDistance < (node.size.height / 2 + CanvasSize.thread.height / 2 + 24)
    }

    private func nextZIndex() -> Int {
        nextZIndex(in: graph)
    }

    private func nextZIndex(in graph: AgentGraph) -> Int {
        (graph.nodes.values.map(\.zIndex).max() ?? 0) + 1
    }

    private func matchingThreadNodeID(hostID: HostID?, threadID: String) -> NodeID? {
        let matches = graph.nodes.values.filter {
            $0.metadata.threadRef?.matches(hostID: hostID, threadID: threadID) == true
        }
        guard hostID == nil, matches.count > 1 else {
            return matches.first?.id
        }

        let hostIDs = matches.compactMap(\.metadata.threadRef?.hostID.rawValue).sorted().joined(separator: ", ")
        errorMessage = "Ambiguous hostless workflow event for thread '\(threadID)' matched hosts: \(hostIDs)"
        return nil
    }

    private static func clamped(_ viewport: CanvasViewport) -> CanvasViewport {
        CanvasViewport(
            scale: min(1.8, max(0.45, viewport.scale)),
            offset: viewport.offset
        )
    }

    private static func path(_ path: String, isInsideOrEqualTo root: String) -> Bool {
        let normalizedRoot = standardizePath(root)
        let normalizedPath = standardizePath(path)

        if normalizedPath == normalizedRoot {
            return true
        }

        let rootWithSlash = normalizedRoot.hasSuffix("/") ? normalizedRoot : normalizedRoot + "/"
        return normalizedPath.hasPrefix(rootWithSlash)
    }

    private static func percentEncoded(_ value: String) -> String {
        let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? value
    }

    private static func folderTitle(for path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let separators = CharacterSet(charactersIn: "/\\")
        let components = trimmed
            .trimmingCharacters(in: separators)
            .components(separatedBy: separators)
            .filter { !$0.isEmpty }
        return components.last ?? trimmed
    }

    private static func standardizePath(_ path: String) -> String {
        let slashNormalized = path.replacingOccurrences(of: "\\", with: "/")
        if slashNormalized.range(of: #"^[A-Za-z]:"#, options: .regularExpression) != nil {
            return slashNormalized.lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return NSString(string: slashNormalized).standardizingPath
    }

    private static func escapedMentionLabel(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\", "\"", "[", "]":
                escaped.append("\\")
                escaped.append(Character(scalar))
            case "\n", "\r", "\t":
                escaped.append(" ")
            default:
                if CharacterSet.controlCharacters.contains(scalar) {
                    escaped.append(" ")
                } else {
                    escaped.append(Character(scalar))
                }
            }
        }
        return escaped
    }

    private static let localHostID = HostID(rawValue: "local")
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension SupervisorMachine {
    var subtitle: String {
        if let lastError, !lastError.isEmpty {
            return lastError
        }

        let platformLabel = platform == .unknown ? "machine" : platform.rawValue
        return "\(platformLabel) - \(endpointDescription)"
    }
}

private extension HostStatus {
    init(_ supervisorStatus: SupervisorMachineStatus) {
        switch supervisorStatus {
        case .connected:
            self = .connected
        case .connecting:
            self = .connecting
        case .disconnected:
            self = .disconnected
        case .failed:
            self = .unavailable
        }
    }
}
