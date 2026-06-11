import MapofAgentsCore
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

public struct GraphCanvasView: View {
    private struct PendingUserTurnStart: Hashable {
        var hostID: HostID
        var threadID: String
        var createdAt: Date
    }

    private enum PendingDestructiveAction: Identifiable {
        case archiveThread(CanvasNode)
        case deleteNode(CanvasNode)
        case deleteManualEdge(CanvasEdge)

        var id: String {
            switch self {
            case .archiveThread(let node):
                return "archive-\(node.id.rawValue)"
            case .deleteNode(let node):
                return "delete-node-\(node.id.rawValue)"
            case .deleteManualEdge(let edge):
                return "delete-edge-\(edge.id.rawValue)"
            }
        }

        var title: String {
            switch self {
            case .archiveThread:
                return "Archive Codex Thread?"
            case .deleteNode:
                return "Delete Canvas Node?"
            case .deleteManualEdge:
                return "Delete Line?"
            }
        }

        var confirmationTitle: String {
            switch self {
            case .archiveThread(let node):
                return "Archive \(node.title)"
            case .deleteNode(let node):
                return "Delete \(node.title)"
            case .deleteManualEdge:
                return "Delete Line"
            }
        }

        var message: String {
            switch self {
            case .archiveThread(let node):
                return "This archives the Codex thread \"\(node.title)\" on its owning machine and removes the node from this workflow map."
            case .deleteNode(let node):
                return "This removes \"\(node.title)\" and its connected lines from this workflow map. It does not delete Codex thread history from disk."
            case .deleteManualEdge:
                return "This removes the selected manual line from this workflow map."
            }
        }
    }

    private struct RemoteFolderPickerRequest: Identifiable, Hashable {
        var id: HostID { hostID }
        var remote: CodexDesktopRemote
        var hostID: HostID
        var platform: HostPlatform
        var initialPath: String
        var mode: RemoteFolderPickerView.Mode = .chooseProject
    }

    private static let userTurnMarkerLeadWindow: TimeInterval = 5
    private static let userTurnMarkerFollowWindow: TimeInterval = 5 * 60
    private static let userTurnAttributionRetention: TimeInterval = 20 * 60

    @Bindable private var graphStore: GraphStore
    @Bindable private var runtimeStore: CodexRuntimeStore
    @Bindable private var supervisorStore: WorkflowSupervisorStore
    @Bindable private var threadCatalogStore: ThreadCatalogStore
    private var workflowEvents: [WorkflowEvent]
    private var activeWorkflowID: String?
    private var activeWorkflowName: String?
    private var workflowMemberships: [String: [ThreadWorkflowMembership]]
    @Binding private var notificationPreferences: WorkflowNotificationPreferences
    private var onPickLocalMachineFolder: (CanvasNode) -> Void
    private var mentionCandidatesForThread: (ThreadRef?) -> [MentionCandidate]
    private var onThreadMentionCatalogNeeded: (ThreadRef?) -> Void
    private var showsDesktopRails: Bool
    private var showsStatusStrip: Bool
    private var showsSubagents: Bool
    @Binding private var isReadingModePresented: Bool
    @Binding private var readingThreadCount: Int
    @Binding private var isMachineRecoveryPresented: Bool
    private var onCanvasSizeChange: (CGSize) -> Void
    @State private var dragOffsets: [NodeID: CGSize] = [:]
    @State private var transcript: ThreadTranscript?
    @State private var isLoadingTranscript = false
    @State private var isLoadingOlderTranscript = false
    @State private var transcriptLoadPhase: TranscriptLoadPhase = .idle
    @State private var transcriptError: String?
    @State private var readingThreadIDs: [NodeID] = []
    @State private var readingTranscripts: [NodeID: ThreadTranscript] = [:]
    @State private var readingErrors: [NodeID: String] = [:]
    @State private var readingLoadingThreadIDs: Set<NodeID> = []
    @State private var readingLoadingOlderThreadIDs: Set<NodeID> = []
    @State private var readingLoadPhases: [NodeID: TranscriptLoadPhase] = [:]
    @State private var awaitingResponseThreadKeys: Set<String> = []
    @State private var stoppingThreadKeys: Set<String> = []
    @State private var liveRefreshThreadKeys: Set<String> = []
    @State private var viewportDragOffset: CGSize = .zero
    @State private var handledWorkflowEventIDs: Set<String> = []
    @State private var handledWorkflowEventIDOrder: [String] = []
    @State private var workflowEventStateStartedAt = Date()
    @State private var pendingUserTurnStarts: [PendingUserTurnStart] = []
    @State private var userStartedTurnKeys: [String: Date] = [:]
    @State private var pendingDestructiveAction: PendingDestructiveAction?
    @State private var transientThreadNode: CanvasNode?
    @State private var inboxSubscriptionRefs: [String: ThreadRef] = [:]
    @State private var hoveredInboxNodeID: NodeID?
    @State private var activeTranscriptLoadKey: String?
    @State private var transcriptLoadGeneration: UInt64 = 0
    @State private var transientOpenGeneration: UInt64 = 0
    @State private var suppressedNodeControlTapID: NodeID?
    @State private var transientViewport: CanvasViewport?
    @State private var viewportCommitTask: Task<Void, Never>?
    @State private var remoteFolderPickerRequest: RemoteFolderPickerRequest?
    #if os(macOS)
    @State private var codexRemoteDiagnosticsWindow: CodexRemoteDiagnosticsWindowPresenter?
    #endif

    public init(
        graphStore: GraphStore,
        runtimeStore: CodexRuntimeStore,
        supervisorStore: WorkflowSupervisorStore,
        threadCatalogStore: ThreadCatalogStore,
        workflowEvents: [WorkflowEvent],
        activeWorkflowID: String? = nil,
        activeWorkflowName: String? = nil,
        workflowMemberships: [String: [ThreadWorkflowMembership]] = [:],
        notificationPreferences: Binding<WorkflowNotificationPreferences>,
        onPickLocalMachineFolder: @escaping (CanvasNode) -> Void = { _ in },
        mentionCandidatesForThread: @escaping (ThreadRef?) -> [MentionCandidate] = { _ in [] },
        onThreadMentionCatalogNeeded: @escaping (ThreadRef?) -> Void = { _ in },
        showsDesktopRails: Bool = true,
        showsStatusStrip: Bool = true,
        showsSubagents: Bool = true,
        isReadingModePresented: Binding<Bool> = .constant(false),
        readingThreadCount: Binding<Int> = .constant(0),
        isMachineRecoveryPresented: Binding<Bool> = .constant(false),
        onCanvasSizeChange: @escaping (CGSize) -> Void = { _ in }
    ) {
        self.graphStore = graphStore
        self.runtimeStore = runtimeStore
        self.supervisorStore = supervisorStore
        self.threadCatalogStore = threadCatalogStore
        self.workflowEvents = workflowEvents
        self.activeWorkflowID = activeWorkflowID
        self.activeWorkflowName = activeWorkflowName
        self.workflowMemberships = workflowMemberships
        self._notificationPreferences = notificationPreferences
        self.onPickLocalMachineFolder = onPickLocalMachineFolder
        self.mentionCandidatesForThread = mentionCandidatesForThread
        self.onThreadMentionCatalogNeeded = onThreadMentionCatalogNeeded
        self.showsDesktopRails = showsDesktopRails
        self.showsStatusStrip = showsStatusStrip
        self.showsSubagents = showsSubagents
        self._isReadingModePresented = isReadingModePresented
        self._readingThreadCount = readingThreadCount
        self._isMachineRecoveryPresented = isMachineRecoveryPresented
        self.onCanvasSizeChange = onCanvasSizeChange
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                let activeThreadNode = isReadingModePresented ? nil : (transientThreadNode ?? selectedThreadNode)
                let showsInspector = shouldShowSelectionInspector
                let popoverSize = threadPopoverSize(in: proxy.size)
                let viewport = displayedViewport
                let popoverFrame = activeThreadNode.map {
                    currentPopoverFrame(for: $0, viewport: viewport, popoverSize: popoverSize, in: proxy.size)
                }
                let rightRailFrame = CGRect(
                    x: max(0, proxy.size.width - rightRailReservedWidth(in: proxy.size) - 14),
                    y: 0,
                    width: rightRailReservedWidth(in: proxy.size) + 14,
                    height: proxy.size.height
                )
                let ignoredScrollRects = canvasIgnoredScrollRects(
                    canvasSize: proxy.size,
                    popoverFrame: popoverFrame,
                    rightRailFrame: rightRailFrame,
                    showsInspector: showsInspector,
                    selectedEdgePopoverPosition: selectedManualEdge.flatMap { edgePopoverPosition(for: $0, viewport: viewport) }
                )

                CanvasBackground(reducedDetail: activeThreadNode != nil || selectedManualEdge != nil)
                    .contentShape(Rectangle())
                    .gesture(viewportPanGesture)
                    .onTapGesture {
                        releaseTransientThreadSubscriptionIfNeeded()
                        transientOpenGeneration &+= 1
                        transientThreadNode = nil
                        graphStore.clearSelection()
                        resetThreadPopoverData()
                    }
                    .overlay {
                        scrollWheelZoomLayer(ignoredRects: ignoredScrollRects)
                    }

                graphContentLayer(viewport: viewport)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .scaleEffect(viewport.scale, anchor: .topLeading)
                .offset(x: viewport.offset.x, y: viewport.offset.y)

                if let threadNode = activeThreadNode {
                    threadPopoverLayer(
                        for: threadNode,
                        popoverSize: popoverSize,
                        viewport: viewport,
                        canvasSize: proxy.size
                    )
                }

                #if os(macOS)
                if isReadingModePresented {
                    readingDockLayer(in: proxy.size)
                }
                #endif

                GraphCanvasSelectionInspectorLayer(
                    graphStore: graphStore,
                    isVisible: showsInspector
                )
                .padding(.top, 72)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                if !showsInspector,
                   let edge = selectedManualEdge,
                   let position = edgePopoverPosition(for: edge, viewport: viewport) {
                    edgePopoverLayer(edge: edge, position: position)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if showsStatusStrip && !isReadingModePresented {
                    StatusStrip(
                        graphStore: graphStore,
                        runtimeStore: runtimeStore,
                        supervisorStore: supervisorStore
                    )
                        .padding(14)
                }
            }
            .overlay(alignment: .topTrailing) {
                if showsDesktopRails && !isReadingModePresented {
                    operationalRailsLayer(in: proxy.size)
                        .padding(.top, 58)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showsDesktopRails && !isReadingModePresented {
                    threadInboxLayer()
                        .padding(.trailing, 14)
                        .padding(.bottom, 14)
                }
            }
            .onChange(of: selectedThreadKey) { _, _ in
                if selectedThreadKey != nil {
                    transientOpenGeneration &+= 1
                    transientThreadNode = nil
                }
                guard let selectedThreadNode else {
                    if transientThreadNode == nil {
                        resetThreadPopoverData()
                    }
                    return
                }
                resetThreadPopoverDataIfNeeded(for: selectedThreadNode.metadata.threadRef)
                startTranscriptLoad(for: selectedThreadNode, force: true, markRead: true)
            }
            .onChange(of: isReadingModePresented) { _, isPresented in
                handleReadingModeChange(isPresented)
            }
            .task {
                primeHandledWorkflowEvents(workflowEvents)
                applyThreadCatalogRuntimeState()
                await syncInboxSubscriptions()
            }
            .onChange(of: workflowEvents) { _, events in
                Task { await handleWorkflowEvents(events) }
            }
            .onChange(of: threadCatalogRefreshSignature) { _, _ in
                Task { await refreshThreadInbox() }
            }
            .onChange(of: graphStore.graph.viewport) { _, viewport in
                if transientViewport == viewport {
                    transientViewport = nil
                }
            }
            .onChange(of: showsSubagents) { _, isShowing in
                guard !isShowing else { return }
                closeHiddenSubagentSurfaces()
            }
            .onChange(of: readingThreadIDs) { _, threadIDs in
                readingThreadCount = threadIDs.count
            }
            .task {
                await refreshThreadInbox()
            }
            .confirmationDialog(
                pendingDestructiveAction?.title ?? "Confirm Action",
                isPresented: Binding(
                    get: { pendingDestructiveAction != nil },
                    set: { isPresented in
                        if !isPresented {
                            pendingDestructiveAction = nil
                        }
                    }
                ),
                titleVisibility: .visible,
                presenting: pendingDestructiveAction
            ) { action in
                Button(action.confirmationTitle, role: .destructive) {
                    performDestructiveAction(action)
                    pendingDestructiveAction = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDestructiveAction = nil
                }
            } message: { action in
                Text(action.message)
            }
            .sheet(item: $remoteFolderPickerRequest) { request in
                RemoteFolderPickerView(
                    remote: request.remote,
                    initialPath: request.initialPath,
                    mode: request.mode,
                    onCancel: {
                        remoteFolderPickerRequest = nil
                    },
                    onSelect: { path in
                        remoteFolderPickerRequest = nil
                        Task {
                            await graphStore.addFolder(
                                path: path,
                                hostID: request.hostID,
                                platform: request.platform
                            )
                        }
                    }
                )
            }
            .onAppear {
                onCanvasSizeChange(proxy.size)
            }
            .onChange(of: proxy.size) { _, size in
                onCanvasSizeChange(size)
            }
        }
    }

    private var selectedNodeID: NodeID? {
        if case .node(let id) = graphStore.selection {
            return id
        }
        return nil
    }

    private var selectedEdgeID: EdgeID? {
        if case .edge(let id) = graphStore.selection {
            return id
        }
        return nil
    }

    private var selectedManualEdge: CanvasEdge? {
        guard case .edge(let id) = graphStore.selection else {
            return nil
        }
        return graphStore.graph.manualEdges[id]
    }

    private var selectedThreadNode: CanvasNode? {
        guard
            case .node(let id) = graphStore.selection,
            let node = graphStore.graph.nodes[id],
            node.kind == .codexThread
        else {
            return nil
        }
        return node
    }

    private var selectedThreadKey: String? {
        selectedThreadNode?.metadata.threadRef?.qualifiedID ?? selectedThreadNode?.id.rawValue
    }

    private var visibleSortedNodes: [CanvasNode] {
        graphStore.graph.sortedNodes.filter(shouldShowNode)
    }

    private var visibleCanvasNodes: [NodeID: CanvasNode] {
        Dictionary(uniqueKeysWithValues: visibleSortedNodes.map { ($0.id, $0) })
    }

    private func visibleCanvasEdges(in nodes: [NodeID: CanvasNode]) -> [CanvasEdge] {
        graphStore.allEdges.filter { edge in
            nodes[edge.source] != nil && nodes[edge.target] != nil
        }
    }

    private func visibleManualEdges(in nodes: [NodeID: CanvasNode]) -> [CanvasEdge] {
        graphStore.graph.manualEdges.values
            .filter { edge in nodes[edge.source] != nil && nodes[edge.target] != nil }
            .sorted { $0.id.rawValue < $1.id.rawValue }
    }

    private func shouldShowNode(_ node: CanvasNode) -> Bool {
        showsSubagents || !isSubagentNode(node)
    }

    private func isSubagentNode(_ node: CanvasNode) -> Bool {
        node.kind == .codexThread && node.metadata.threadKind == .subagent
    }

    private func closeHiddenSubagentSurfaces() {
        let hiddenIDs = Set(graphStore.graph.sortedNodes.filter(isSubagentNode).map(\.id))
        var shouldResetTranscript = false

        if let transientThreadNode, hiddenIDs.contains(transientThreadNode.id) {
            self.transientThreadNode = nil
            shouldResetTranscript = true
        }

        if let selectedNode = graphStore.selectedNode, hiddenIDs.contains(selectedNode.id) {
            graphStore.clearSelection()
            shouldResetTranscript = true
        } else if let selectedManualEdge,
                  hiddenIDs.contains(selectedManualEdge.source) || hiddenIDs.contains(selectedManualEdge.target) {
            graphStore.clearSelection()
        }

        readingThreadIDs.removeAll { hiddenIDs.contains($0) }
        readingTranscripts = readingTranscripts.filter { !hiddenIDs.contains($0.key) }
        readingErrors = readingErrors.filter { !hiddenIDs.contains($0.key) }
        readingLoadingThreadIDs.subtract(hiddenIDs)
        readingLoadingOlderThreadIDs.subtract(hiddenIDs)
        readingLoadPhases = readingLoadPhases.filter { !hiddenIDs.contains($0.key) }

        if shouldResetTranscript {
            resetThreadPopoverData()
        }
    }

    private var shouldShowSelectionInspector: Bool {
        guard showsDesktopRails else { return false }
        if selectedThreadNode != nil {
            return false
        }
        if selectedManualEdge != nil {
            return true
        }
        guard let selectedNode = graphStore.selectedNode else {
            return false
        }
        return selectedNode.kind != .machine
    }

    private var graphContentSignature: String {
        var parts: [String] = [
            graphStore.graph.workspaceID.rawValue,
            graphStore.graph.title,
        ]

        for node in graphStore.graph.sortedNodes {
            parts.append(
                [
                    "node",
                    node.id.rawValue,
                    node.kind.rawValue,
                    node.title,
                    node.subtitle,
                    "\(node.position.x),\(node.position.y)",
                    "\(node.size.width),\(node.size.height)",
                    "\(node.zIndex)",
                    node.metadata.hostID?.rawValue ?? "",
                    node.metadata.platform?.rawValue ?? "",
                    node.metadata.hostStatus?.rawValue ?? "",
                    node.metadata.folderPath ?? "",
                    node.metadata.threadRef?.qualifiedID ?? "",
                    node.metadata.threadRef?.cwd ?? "",
                    node.metadata.model ?? "",
                    node.metadata.reasoningEffort ?? "",
                    node.metadata.runStatus?.rawValue ?? "",
                    node.metadata.isUnread.map { $0 ? "true" : "false" } ?? "",
                ].joined(separator: "|")
            )
        }

        for edge in graphStore.graph.manualEdges.values.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            parts.append(
                [
                    "edge",
                    edge.id.rawValue,
                    edge.source.rawValue,
                    edge.target.rawValue,
                    edge.kind.rawValue,
                    String(edge.isManual),
                    edge.label ?? "",
                ].joined(separator: "|")
            )
        }

        parts.append("routes:\(graphStore.graph.messageRoutes.count)")
        return parts.joined(separator: "\u{1F}")
    }

    private var threadCatalogRefreshSignature: String {
        var parts: [String] = [
            graphStore.graph.workspaceID.rawValue,
            graphStore.graph.title,
        ]

        for node in graphStore.graph.sortedNodes {
            guard node.kind == .codexThread || node.kind == .folder else { continue }
            parts.append(
                [
                    node.kind.rawValue,
                    node.id.rawValue,
                    node.metadata.hostID?.rawValue ?? "",
                    node.metadata.folderPath ?? "",
                    node.metadata.threadRef?.qualifiedID ?? "",
                    node.metadata.threadRef?.cwd ?? "",
                ].joined(separator: "|")
            )
        }

        return parts.joined(separator: "\u{1F}")
    }

    private func allMentionCandidates(for threadNode: CanvasNode) -> [MentionCandidate] {
        graphStore.workflowThreadMentionCandidates(
            excluding: threadNode.metadata.threadRef
        ) + graphStore.workflowFolderMentionCandidates()
            + mentionCandidatesForThread(threadNode.metadata.threadRef)
    }

    private func attentionRequests(for threadNode: CanvasNode) -> [RuntimeAttentionRequest] {
        guard let threadRef = threadNode.metadata.threadRef else { return [] }
        return (runtimeStore.pendingAttentionRequests + supervisorStore.pendingAttentionRequests)
            .filter { request in
                request.threadID == threadRef.threadID
                    && (request.hostID == nil || request.hostID == threadRef.hostID)
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var readingItems: [ThreadReadingItem] {
        readingThreadIDs.compactMap { nodeID in
            guard let node = graphStore.graph.nodes[nodeID], node.kind == .codexThread else {
                return nil
            }

            return ThreadReadingItem(
                node: node,
                transcript: readingTranscripts[nodeID],
                liveAssistantText: liveAssistantText(for: node),
                liveStateSummary: liveStateSummary(for: node),
                isLoading: readingLoadingThreadIDs.contains(nodeID),
                isLoadingOlder: readingLoadingOlderThreadIDs.contains(nodeID),
                loadPhase: readingLoadPhases[nodeID] ?? .idle,
                isAwaitingResponse: isAwaitingResponse(for: node),
                canStopTurn: canStopThread(node),
                isStoppingTurn: isStoppingThread(node),
                errorMessage: readingErrors[nodeID],
                threadMentionCandidates: allMentionCandidates(for: node),
                attentionRequests: attentionRequests(for: node)
            )
        }
    }

    private var readingCandidates: [ThreadReadingCandidate] {
        let openIDs = Set(readingThreadIDs)
        return graphStore.graph.sortedNodes.compactMap { node in
            guard node.kind == .codexThread else { return nil }
            guard showsSubagents || !isSubagentNode(node) else { return nil }
            return ThreadReadingCandidate(
                id: node.id,
                title: node.title,
                subtitle: node.subtitle,
                isOpen: openIDs.contains(node.id)
            )
        }
    }

    @ViewBuilder
    private func graphContentLayer(viewport: CanvasViewport) -> some View {
        let nodes = visibleCanvasNodes
        let edges = visibleCanvasEdges(in: nodes)
        let manualEdges = visibleManualEdges(in: nodes)
        ZStack(alignment: .topLeading) {
            EdgeLayer(
                nodes: nodes,
                edges: edges,
                selectedEdge: selectedEdgeID,
                focusedNodeID: focusedCanvasNodeID,
                onSelect: graphStore.selectEdge
            )

            EdgeControlLayer(
                nodes: nodes,
                edges: manualEdges,
                selectedEdge: selectedEdgeID,
                onSelect: graphStore.selectEdge
            )

            canvasNodesLayer(viewport: viewport)
        }
    }

    private func operationalRailsLayer(in size: CGSize) -> some View {
        GraphCanvasOperationalRails(
            runtimeStore: runtimeStore,
            supervisorStore: supervisorStore,
            threadCatalogStore: threadCatalogStore,
            workflowEvents: workflowEvents,
            maxHeight: max(320, size.height - 28),
            notificationPreferences: $notificationPreferences,
            threadTitle: threadTitle(for:),
            turnOriginTitle: turnOriginTitle(for:),
            onSelectEvent: focusThread(for:),
            onDisconnect: { machineID in
                Task { await supervisorStore.disconnect(machineID) }
            },
            onRefreshThreadInbox: {
                Task { await refreshThreadInbox() }
            },
            onSearchThreadInbox: {
                Task { await searchThreadInbox() }
            },
            onOpenInboxThread: { entry in
                openInboxThread(entry)
            },
            onAddInboxThreadToCanvas: { entry in
                Task { await addInboxThreadToCanvas(entry) }
            },
            onArchiveInboxThread: { entry in
                Task { await archiveInboxThread(entry) }
            },
            onMarkInboxThreadRead: { entry, isRead in
                Task { await setInboxThread(entry, read: isRead) }
            },
            onHoverInboxNode: { nodeID in
                hoveredInboxNodeID = nodeID
            },
            onFocusAttention: { request in
                focusAttentionRequest(request)
            },
            onRespondToAttention: { request, allow in
                Task { await respondToAttentionRequest(request, allow: allow) }
            },
            onRespondToAttentionWithText: { request, text in
                Task { await respondToAttentionRequest(request, text: text) }
            },
            onDeclineTypedAttention: { request in
                Task { await declineTypedAttentionRequest(request) }
            },
            showsThreadInbox: false,
            isMachineRecoveryPresented: $isMachineRecoveryPresented
        )
        .padding(14)
    }

    private func threadInboxLayer() -> some View {
        let attentionRequests = runtimeStore.pendingAttentionRequests + supervisorStore.pendingAttentionRequests
        return ThreadInboxPanelView(
            catalogStore: threadCatalogStore,
            onRefresh: {
                Task { await refreshThreadInbox() }
            },
            onSearch: {
                Task { await searchThreadInbox() }
            },
            onOpen: { entry in
                openInboxThread(entry)
            },
            onAddToCanvas: { entry in
                Task { await addInboxThreadToCanvas(entry) }
            },
            onArchive: { entry in
                Task { await archiveInboxThread(entry) }
            },
            onMarkRead: { entry, isRead in
                Task { await setInboxThread(entry, read: isRead) }
            },
            onHoverNode: { nodeID in
                hoveredInboxNodeID = nodeID
            },
            attentionRequests: attentionRequests,
            onFocusAttention: { request in
                focusAttentionRequest(request)
            },
            onRespondToAttention: { request, allow in
                Task { await respondToAttentionRequest(request, allow: allow) }
            },
            onRespondToAttentionWithText: { request, text in
                Task { await respondToAttentionRequest(request, text: text) }
            },
            onDeclineTypedAttention: { request in
                Task { await declineTypedAttentionRequest(request) }
            }
        )
    }

    @ViewBuilder
    private func canvasNodesLayer(viewport: CanvasViewport) -> some View {
        let nodes = visibleSortedNodes
        ForEach(nodes) { node in
            canvasNodeView(for: node, viewport: viewport)
        }
    }

    private var focusedCanvasNodeID: NodeID? {
        if transientThreadNode != nil || selectedThreadNode != nil {
            return (transientThreadNode ?? selectedThreadNode)?.id
        }
        return nil
    }

    private var focusedCanvasNeighborhood: Set<NodeID> {
        guard let focusedCanvasNodeID else { return [] }
        var ids: Set<NodeID> = [focusedCanvasNodeID]
        let nodes = visibleCanvasNodes
        for edge in visibleCanvasEdges(in: nodes) where edge.source == focusedCanvasNodeID || edge.target == focusedCanvasNodeID {
            ids.insert(edge.source)
            ids.insert(edge.target)
        }
        return ids
    }

    #if os(macOS)
    private func readingDockLayer(in size: CGSize) -> some View {
        ThreadReadingDockView(
            runtimeStore: runtimeStore,
            items: readingItems,
            candidates: readingCandidates,
            onCloseDock: {
                isReadingModePresented = false
            },
            onClear: clearReader,
            onAddThread: { nodeID in
                Task { await openThreadInReader(nodeID: nodeID) }
            },
            onRename: { nodeID, title in
                Task { await graphStore.updateNodeTitle(id: nodeID, title: title) }
            },
            onRefresh: { nodeID in
                Task { await loadReadingTranscript(for: nodeID, force: true) }
            },
            onLoadOlder: { nodeID in
                Task { await loadOlderReadingTranscript(for: nodeID) }
            },
            onUseCachedTranscript: { nodeID in
                readingErrors[nodeID] = nil
            },
            onSend: { nodeID, text, attachments in
                await sendReadingMessage(text, attachments: attachments, from: nodeID)
            },
            onStopTurn: { nodeID in
                Task { await stopThreadNode(nodeID: nodeID) }
            },
            onFocusAttention: focusAttentionRequest,
            onRespondToAttention: { request, allow in
                Task { await respondToAttentionRequest(request, allow: allow) }
            },
            onRespondToAttentionWithText: { request, text in
                Task { await respondToAttentionRequest(request, text: text) }
            },
            onDeclineTypedAttention: { request in
                Task { await declineTypedAttentionRequest(request) }
            },
            onCloseThread: closeThreadInReader,
            onMentionCatalogNeeded: onThreadMentionCatalogNeeded
        )
        .frame(width: size.width, height: size.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .zIndex(30)
    }
    #endif

    private func edgePopoverLayer(edge: CanvasEdge, position: CGPoint) -> some View {
        EdgeNotePopoverView(
            edge: edge,
            routes: messageRoutes(for: edge),
            onSave: { label in
                Task { await graphStore.updateManualEdgeLabel(id: edge.id, label: label) }
            },
            onDelete: {
                pendingDestructiveAction = .deleteManualEdge(edge)
            },
            onClose: {
                graphStore.clearSelection()
            }
        )
        .position(position)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    @ViewBuilder
    private func canvasNodeView(for node: CanvasNode, viewport: CanvasViewport) -> some View {
        NodeView(
            node: node,
            isSelected: selectedNodeID == node.id,
            isManualEdgeSource: graphStore.pendingManualEdgeSource == node.id,
            hasPendingManualEdge: graphStore.pendingManualEdgeSource != nil,
            isHighlighted: hoveredInboxNodeID == node.id,
            defaultMachineFolderPath: defaultFolderPath(for: node),
            liveState: liveStateSummary(for: node),
            onChooseMachineFolder: pickMachineFolderAction(for: node),
            onAddMachineFolder: addMachineFolderAction(for: node),
            onLinkAction: {
                if let pending = graphStore.pendingManualEdgeSource, pending != node.id {
                    Task { await graphStore.completeManualEdge(to: node.id) }
                } else {
                    graphStore.beginManualEdge(from: node.id)
                }
            },
            onControlTap: {
                suppressNextNodeTap(for: node.id)
            }
        )
        .frame(width: node.size.width, height: node.size.height)
        .position(node.position.translated(by: dragOffsets[node.id] ?? .zero).cgPoint)
        .opacity(nodeOpacity(for: node))
        .gesture(nodeDragGesture(for: node, scale: viewport.scale))
        .simultaneousGesture(TapGesture().onEnded {
            handleNodeTap(node)
        })
        .contextMenu {
            nodeContextMenu(for: node)
        }
    }

    private func nodeOpacity(for node: CanvasNode) -> Double {
        guard focusedCanvasNodeID != nil else { return 1 }
        return focusedCanvasNeighborhood.contains(node.id) ? 1 : 0.36
    }

    private func handleNodeTap(_ node: CanvasNode) {
        if suppressedNodeControlTapID == node.id {
            suppressedNodeControlTapID = nil
            return
        }

        graphStore.selectNode(node.id)
        Task {
            if isReadingModePresented, node.kind == .codexThread {
                await openThreadInReader(node)
            } else {
                await markThreadReadIfNeeded(node)
                await loadTranscriptIfNeeded(for: node)
            }
        }
    }

    private func suppressNextNodeTap(for nodeID: NodeID) {
        suppressedNodeControlTapID = nodeID
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            if suppressedNodeControlTapID == nodeID {
                suppressedNodeControlTapID = nil
            }
        }
    }

    private func handleReadingModeChange(_ isPresented: Bool) {
        guard isPresented, let selectedThreadNode else { return }
        Task { await openThreadInReader(selectedThreadNode) }
    }

    @ViewBuilder
    private func threadPopoverLayer(
        for threadNode: CanvasNode,
        popoverSize: CGSize,
        viewport: CanvasViewport,
        canvasSize: CGSize
    ) -> some View {
        #if os(iOS)
        FullScreenThreadPopoverLayer(
            node: threadNode,
            runtimeStore: runtimeStore,
            transcript: transcript,
            liveAssistantText: liveAssistantText(for: threadNode),
            liveStateSummary: liveStateSummary(for: threadNode),
            isLoading: isLoadingTranscript,
            isLoadingOlder: isLoadingOlderTranscript,
            loadPhase: transcriptLoadPhase,
            isAwaitingResponse: isAwaitingResponse(for: threadNode),
            canStopTurn: canStopThread(threadNode),
            isStoppingTurn: isStoppingThread(threadNode),
            errorMessage: transcriptError,
            threadMentionCandidates: allMentionCandidates(for: threadNode),
            attentionRequests: attentionRequests(for: threadNode),
            onRename: { title in
                Task { await graphStore.updateNodeTitle(id: threadNode.id, title: title) }
            },
            onRefresh: {
                Task { await loadTranscript(for: threadNode, force: true) }
            },
            onLoadOlder: {
                Task { await loadOlderTranscript(for: threadNode) }
            },
            onUseCachedTranscript: {
                transcriptError = nil
            },
            onSend: { text, attachments in
                await send(text, attachments: attachments, from: threadNode)
            },
            onStopTurn: {
                Task { await stopThreadNode(threadNode) }
            },
            onFocusAttention: focusAttentionRequest,
            onRespondToAttention: { request, allow in
                Task { await respondToAttentionRequest(request, allow: allow) }
            },
            onRespondToAttentionWithText: { request, text in
                Task { await respondToAttentionRequest(request, text: text) }
            },
            onDeclineTypedAttention: { request in
                Task { await declineTypedAttentionRequest(request) }
            },
            onClose: closeActiveThreadPopover
        )
        .task(id: threadNode.metadata.threadRef?.qualifiedID ?? threadNode.id.rawValue) {
            onThreadMentionCatalogNeeded(threadNode.metadata.threadRef)
        }
        .transition(.opacity)
        #else
        DraggableThreadPopoverLayer(
            node: threadNode,
            runtimeStore: runtimeStore,
            transcript: transcript,
            liveAssistantText: liveAssistantText(for: threadNode),
            liveStateSummary: liveStateSummary(for: threadNode),
            isLoading: isLoadingTranscript,
            isLoadingOlder: isLoadingOlderTranscript,
            loadPhase: transcriptLoadPhase,
            isAwaitingResponse: isAwaitingResponse(for: threadNode),
            canStopTurn: canStopThread(threadNode),
            isStoppingTurn: isStoppingThread(threadNode),
            errorMessage: transcriptError,
            threadMentionCandidates: allMentionCandidates(for: threadNode),
            attentionRequests: attentionRequests(for: threadNode),
            popoverSize: popoverSize,
            basePosition: popoverPosition(for: threadNode, viewport: viewport, popoverSize: popoverSize, in: canvasSize),
            canvasSize: canvasSize,
            rightInset: rightRailReservedWidth(in: canvasSize),
            onRename: { title in
                Task { await graphStore.updateNodeTitle(id: threadNode.id, title: title) }
            },
            onCommitOffset: { offset in
                Task { await graphStore.updateNodePopoverOffset(id: threadNode.id, offset: offset) }
            },
            onRefresh: {
                Task { await loadTranscript(for: threadNode, force: true) }
            },
            onLoadOlder: {
                Task { await loadOlderTranscript(for: threadNode) }
            },
            onUseCachedTranscript: {
                transcriptError = nil
            },
            onSend: { text, attachments in
                await send(text, attachments: attachments, from: threadNode)
            },
            onStopTurn: {
                Task { await stopThreadNode(threadNode) }
            },
            onFocusAttention: focusAttentionRequest,
            onRespondToAttention: { request, allow in
                Task { await respondToAttentionRequest(request, allow: allow) }
            },
            onRespondToAttentionWithText: { request, text in
                Task { await respondToAttentionRequest(request, text: text) }
            },
            onDeclineTypedAttention: { request in
                Task { await declineTypedAttentionRequest(request) }
            },
            onClose: closeActiveThreadPopover
        )
        .task(id: threadNode.metadata.threadRef?.qualifiedID ?? threadNode.id.rawValue) {
            onThreadMentionCatalogNeeded(threadNode.metadata.threadRef)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
        #endif
    }

    private var displayedViewport: CanvasViewport {
        let viewport = transientViewport ?? graphStore.graph.viewport
        return CanvasViewport(
            scale: viewport.scale,
            offset: viewport.offset.offsetBy(
                dx: viewportDragOffset.width,
                dy: viewportDragOffset.height
            )
        )
    }

    private var viewportPanGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                viewportDragOffset = value.translation
            }
            .onEnded { value in
                let baseViewport = transientViewport ?? graphStore.graph.viewport
                let committedViewport = CanvasViewport(
                    scale: baseViewport.scale,
                    offset: baseViewport.offset.offsetBy(
                        dx: value.translation.width,
                        dy: value.translation.height
                    )
                )
                viewportDragOffset = .zero
                viewportCommitTask?.cancel()
                transientViewport = nil
                Task {
                    await graphStore.updateViewport(committedViewport)
                }
            }
    }

    private func zoomWithScrollWheel(_ delta: Double) {
        let clampedDelta = min(80, max(-80, delta))
        let factor = pow(1.0028, clampedDelta)
        let baseViewport = transientViewport ?? graphStore.graph.viewport
        let nextViewport = CanvasViewport(
            scale: min(1.8, max(0.45, baseViewport.scale * factor)),
            offset: baseViewport.offset
        )
        transientViewport = nextViewport
        scheduleViewportCommit(nextViewport)
    }

    private func scheduleViewportCommit(_ viewport: CanvasViewport) {
        viewportCommitTask?.cancel()
        viewportCommitTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            await graphStore.updateViewport(viewport)
            if transientViewport == viewport {
                transientViewport = nil
            }
        }
    }

    private func scrollWheelZoomLayer(ignoredRects: [CGRect]) -> some View {
        ScrollWheelZoomMonitor(
            ignoredRects: ignoredRects,
            onScroll: zoomWithScrollWheel
        )
        .allowsHitTesting(false)
    }

    private func nodeDragGesture(for node: CanvasNode, scale: Double) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let safeScale = max(0.1, scale)
                dragOffsets[node.id] = CGSize(
                    width: value.translation.width / safeScale,
                    height: value.translation.height / safeScale
                )
            }
            .onEnded { value in
                let safeScale = max(0.1, scale)
                let target = node.position.translated(
                    by: CGSize(
                        width: value.translation.width / safeScale,
                        height: value.translation.height / safeScale
                    )
                )
                dragOffsets[node.id] = nil
                Task { await graphStore.moveNode(id: node.id, to: target) }
            }
    }

    private func threadPopoverSize(in canvasSize: CGSize) -> CGSize {
        #if os(iOS)
        return CGSize(
            width: min(430, max(320, canvasSize.width - 24)),
            height: min(620, max(420, canvasSize.height - 156))
        )
        #else
        CGSize(
            width: min(440, max(360, canvasSize.width * 0.34)),
            height: min(560, max(380, canvasSize.height - 96))
        )
        #endif
    }

    private func popoverPosition(for node: CanvasNode, viewport: CanvasViewport, popoverSize: CGSize, in size: CGSize) -> CGPoint {
        #if os(iOS)
        return CGPoint(x: size.width / 2, y: size.height / 2)
        #else
        let margin: CGFloat = 24
        let reservedRightWidth = rightRailReservedWidth(in: size)
        let effectiveWidth = max(popoverSize.width + margin * 2, size.width - reservedRightWidth)
        let nodeCenter = screenPoint(for: node.position, viewport: viewport)
        let nodeHalfWidth = CGFloat(node.size.width * viewport.scale / 2)
        let nodeHalfHeight = CGFloat(node.size.height * viewport.scale / 2)
        let rightX = nodeCenter.x + nodeHalfWidth + margin + popoverSize.width / 2
        let leftX = nodeCenter.x - nodeHalfWidth - margin - popoverSize.width / 2
        let x: CGFloat

        if rightX + popoverSize.width / 2 + margin <= effectiveWidth {
            x = rightX
        } else if leftX - popoverSize.width / 2 - margin >= 0 {
            x = leftX
        } else {
            x = min(max(rightX, popoverSize.width / 2 + margin), effectiveWidth - popoverSize.width / 2 - margin)
        }

        let preferredY = nodeCenter.y + nodeHalfHeight + margin + popoverSize.height / 2
        let y = min(max(preferredY, popoverSize.height / 2 + margin), max(popoverSize.height / 2 + margin, size.height - popoverSize.height / 2 - margin))
        return CGPoint(x: x, y: y)
        #endif
    }

    private func currentPopoverFrame(for node: CanvasNode, viewport: CanvasViewport, popoverSize: CGSize, in size: CGSize) -> CGRect {
        let basePosition = popoverPosition(for: node, viewport: viewport, popoverSize: popoverSize, in: size)
        let position = clampedThreadPopoverPosition(
            basePosition: basePosition,
            savedOffset: node.metadata.popoverOffset?.cgSize ?? .zero,
            dragOffset: .zero,
            popoverSize: popoverSize,
            canvasSize: size,
            rightInset: rightRailReservedWidth(in: size)
        )
        return CGRect(
            x: position.x - popoverSize.width / 2,
            y: position.y - popoverSize.height / 2,
            width: popoverSize.width,
            height: popoverSize.height
        ).insetBy(dx: -8, dy: -8)
    }

    private func rightRailReservedWidth(in size: CGSize) -> CGFloat {
        size.width >= 900 ? 348 : 0
    }

    private func canvasIgnoredScrollRects(
        canvasSize: CGSize,
        popoverFrame: CGRect?,
        rightRailFrame: CGRect,
        showsInspector: Bool,
        selectedEdgePopoverPosition: CGPoint?
    ) -> [CGRect] {
        var rects = [CGRect]()
        if let popoverFrame {
            rects.append(popoverFrame)
        }
        rects.append(rightRailFrame)
        rects.append(CGRect(x: 0, y: 0, width: min(canvasSize.width, 720), height: 104))
        rects.append(CGRect(x: 0, y: max(0, canvasSize.height - 80), width: min(canvasSize.width, 640), height: 80))

        if showsInspector {
            rects.append(
                CGRect(
                    x: max(0, canvasSize.width - 376),
                    y: 64,
                    width: 376,
                    height: max(0, canvasSize.height - 64)
                )
            )
        }

        if let selectedEdgePopoverPosition {
            rects.append(
                CGRect(
                    x: selectedEdgePopoverPosition.x - 156,
                    y: selectedEdgePopoverPosition.y - 130,
                    width: 312,
                    height: 260
                )
            )
        }

        return rects
    }

    private func edgePopoverPosition(for edge: CanvasEdge, viewport: CanvasViewport) -> CGPoint? {
        guard
            let source = graphStore.graph.nodes[edge.source],
            let target = graphStore.graph.nodes[edge.target]
        else {
            return nil
        }

        let midpoint = CanvasPoint(
            x: (source.position.x + target.position.x) / 2,
            y: (source.position.y + target.position.y) / 2
        )
        return screenPoint(for: midpoint, viewport: viewport)
    }

    private func screenPoint(for point: CanvasPoint, viewport: CanvasViewport) -> CGPoint {
        CGPoint(
            x: point.x * viewport.scale + viewport.offset.x,
            y: point.y * viewport.scale + viewport.offset.y
        )
    }

    private func loadTranscriptIfNeeded(for node: CanvasNode) async {
        guard node.kind == .codexThread else { return }
        await loadTranscript(for: node, force: false)
    }

    private func startTranscriptLoad(for node: CanvasNode, force: Bool, markRead: Bool = false) {
        Task {
            if markRead {
                await markThreadReadIfNeeded(node)
            }
            await loadTranscript(for: node, force: force)
        }
    }

    private func loadTranscript(for node: CanvasNode, force: Bool) async {
        guard let threadRef = node.metadata.threadRef else { return }
        if transcript?.threadRef == threadRef, !force {
            return
        }

        resetThreadPopoverDataIfNeeded(for: threadRef)
        let loadGeneration = beginTranscriptLoad(for: threadRef)
        isLoadingTranscript = true
        isLoadingOlderTranscript = false
        transcriptLoadPhase = transcript?.threadRef == threadRef && transcript?.messages.isEmpty == false ? .refreshing : .connectingHost
        transcriptError = nil
        defer {
            if isCurrentTranscriptLoad(threadRef, generation: loadGeneration) {
                isLoadingTranscript = false
                transcriptLoadPhase = .idle
            }
        }

        do {
            await materializeLocalSubagentsFromRolloutIfAvailable(for: node)
            guard isCurrentTranscriptLoad(threadRef, generation: loadGeneration) else { return }
            transcriptLoadPhase = .loadingHistory
            let loadedTranscript = try await loadTranscript(for: threadRef)
            guard isCurrentTranscriptLoad(threadRef, generation: loadGeneration) else { return }
            transcriptLoadPhase = .hydratingArtifacts
            transcript = loadedTranscript
            guard isCurrentTranscriptLoad(threadRef, generation: loadGeneration) else { return }
            reconcileAwaitingResponse(for: threadRef)
        } catch {
            guard isCurrentTranscriptLoad(threadRef, generation: loadGeneration) else { return }
            let message = displayMessage(for: error, threadRef: threadRef)
            transcriptError = message
            if transcript?.threadRef != threadRef || transcript?.messages.isEmpty != false {
                transcript = ThreadTranscript(threadRef: threadRef)
            }

            if error.isCodexThreadNotFound {
                await recordThreadFailure(
                    threadRef: threadRef,
                    method: "thread/turns/list",
                    summary: "Saved canvas thread was not found in this Codex runtime."
                )
            }
            reconcileAwaitingResponse(for: threadRef)
        }
    }

    private func resetThreadPopoverDataIfNeeded(for threadRef: ThreadRef?) {
        guard transcript?.threadRef != threadRef else {
            return
        }
        resetThreadPopoverData()
    }

    private func resetThreadPopoverData() {
        invalidateTranscriptLoad()
        transcript = nil
        transcriptError = nil
        isLoadingTranscript = false
        isLoadingOlderTranscript = false
        transcriptLoadPhase = .idle
    }

    private func beginTranscriptLoad(for threadRef: ThreadRef) -> UInt64 {
        transcriptLoadGeneration &+= 1
        activeTranscriptLoadKey = threadRef.qualifiedID
        return transcriptLoadGeneration
    }

    private func invalidateTranscriptLoad() {
        transcriptLoadGeneration &+= 1
        activeTranscriptLoadKey = nil
    }

    private func isCurrentTranscriptLoad(_ threadRef: ThreadRef, generation: UInt64) -> Bool {
        activeTranscriptLoadKey == threadRef.qualifiedID
            && transcriptLoadGeneration == generation
            && activePopoverThreadRef?.matches(hostID: threadRef.hostID, threadID: threadRef.threadID) == true
    }

    private var activePopoverThreadRef: ThreadRef? {
        (transientThreadNode ?? selectedThreadNode)?.metadata.threadRef
    }

    private func closeActiveThreadPopover() {
        releaseTransientThreadSubscriptionIfNeeded()
        transientOpenGeneration &+= 1
        transientThreadNode = nil
        resetThreadPopoverData()
        graphStore.clearSelection()
    }

    private func openThreadInReader(_ node: CanvasNode) async {
        guard node.kind == .codexThread, node.metadata.threadRef != nil else { return }

        if !readingThreadIDs.contains(node.id) {
            readingThreadIDs.append(node.id)
        }

        await graphStore.markThreadRead(node.id)
        await loadReadingTranscript(for: node.id, force: false)
    }

    private func openThreadInReader(nodeID: NodeID) async {
        guard let node = graphStore.graph.nodes[nodeID] else { return }
        await openThreadInReader(node)
    }

    private func closeThreadInReader(_ nodeID: NodeID) {
        let threadRef = graphStore.graph.nodes[nodeID]?.metadata.threadRef
        readingThreadIDs.removeAll { $0 == nodeID }
        readingTranscripts[nodeID] = nil
        readingErrors[nodeID] = nil
        readingLoadingThreadIDs.remove(nodeID)
        readingLoadingOlderThreadIDs.remove(nodeID)
        readingLoadPhases[nodeID] = nil
        if let threadRef, !isThreadOpen(hostID: threadRef.hostID, threadID: threadRef.threadID) {
            awaitingResponseThreadKeys.remove(threadRef.qualifiedID)
            liveRefreshThreadKeys.remove(threadRef.qualifiedID)
        }
    }

    private func clearReader() {
        let refs = readingThreadIDs.compactMap { graphStore.graph.nodes[$0]?.metadata.threadRef }
        readingThreadIDs.removeAll()
        readingTranscripts.removeAll()
        readingErrors.removeAll()
        readingLoadingThreadIDs.removeAll()
        readingLoadingOlderThreadIDs.removeAll()
        readingLoadPhases.removeAll()
        for threadRef in refs where !isThreadOpen(hostID: threadRef.hostID, threadID: threadRef.threadID) {
            awaitingResponseThreadKeys.remove(threadRef.qualifiedID)
            liveRefreshThreadKeys.remove(threadRef.qualifiedID)
        }
    }

    private func markThreadReadIfNeeded(_ node: CanvasNode) async {
        guard node.kind == .codexThread, node.metadata.isUnread == true else { return }
        if graphStore.graph.nodes[node.id] != nil {
            await graphStore.markThreadRead(node.id)
        }
        if let threadRef = node.metadata.threadRef {
            threadCatalogStore.markRead(threadRef, isRead: true)
        }
    }

    private func loadReadingTranscript(for nodeID: NodeID, force: Bool) async {
        guard
            let node = graphStore.graph.nodes[nodeID],
            let threadRef = node.metadata.threadRef,
            readingThreadIDs.contains(nodeID)
        else {
            return
        }

        if readingTranscripts[nodeID]?.threadRef == threadRef, !force {
            return
        }

        readingLoadingThreadIDs.insert(nodeID)
        readingLoadingOlderThreadIDs.remove(nodeID)
        readingLoadPhases[nodeID] = readingTranscripts[nodeID]?.threadRef == threadRef && readingTranscripts[nodeID]?.messages.isEmpty == false
            ? .refreshing
            : .connectingHost
        readingErrors[nodeID] = nil
        defer {
            readingLoadingThreadIDs.remove(nodeID)
            readingLoadPhases[nodeID] = .idle
        }

        do {
            await materializeLocalSubagentsFromRolloutIfAvailable(for: node)
            guard readingThreadIDs.contains(nodeID) else { return }
            readingLoadPhases[nodeID] = .loadingHistory
            let loadedTranscript = try await loadTranscript(for: threadRef)
            guard readingThreadIDs.contains(nodeID) else { return }
            readingLoadPhases[nodeID] = .hydratingArtifacts
            readingTranscripts[nodeID] = loadedTranscript
            guard readingThreadIDs.contains(nodeID) else { return }
            reconcileAwaitingResponse(for: threadRef)
        } catch {
            guard readingThreadIDs.contains(nodeID) else { return }
            let message = displayMessage(for: error, threadRef: threadRef)
            readingErrors[nodeID] = message
            if readingTranscripts[nodeID]?.threadRef != threadRef || readingTranscripts[nodeID]?.messages.isEmpty != false {
                readingTranscripts[nodeID] = ThreadTranscript(threadRef: threadRef)
            }

            if error.isCodexThreadNotFound {
                await recordThreadFailure(
                    threadRef: threadRef,
                    method: "thread/turns/list",
                    summary: "Saved canvas thread was not found in this Codex runtime."
                )
            }
            reconcileAwaitingResponse(for: threadRef)
        }
    }

    private func loadOlderReadingTranscript(for nodeID: NodeID) async {
        guard
            !readingLoadingOlderThreadIDs.contains(nodeID),
            let node = graphStore.graph.nodes[nodeID],
            let threadRef = node.metadata.threadRef,
            readingTranscripts[nodeID]?.threadRef == threadRef,
            let cursor = readingTranscripts[nodeID]?.nextCursor,
            !cursor.isEmpty
        else {
            return
        }

        readingLoadingOlderThreadIDs.insert(nodeID)
        readingLoadPhases[nodeID] = .loadingOlder
        defer {
            readingLoadingOlderThreadIDs.remove(nodeID)
            readingLoadPhases[nodeID] = .idle
        }

        do {
            let olderPage: ThreadTranscript
            if isLocalThread(threadRef) {
                olderPage = try await runtimeStore.loadOlderTranscriptPage(for: threadRef, cursor: cursor)
            } else {
                olderPage = try await supervisorStore.loadOlderTranscriptPage(for: threadRef, cursor: cursor)
            }

            guard readingThreadIDs.contains(nodeID),
                  readingTranscripts[nodeID]?.threadRef == threadRef else { return }
            readingTranscripts[nodeID] = readingTranscripts[nodeID]?.prependingOlderPage(olderPage) ?? olderPage
            readingErrors[nodeID] = nil
        } catch {
            guard readingThreadIDs.contains(nodeID) else { return }
            readingErrors[nodeID] = displayMessage(for: error, threadRef: threadRef)
        }
    }

    private func loadOlderTranscript(for node: CanvasNode) async {
        guard
            !isLoadingOlderTranscript,
            let threadRef = node.metadata.threadRef,
            transcript?.threadRef == threadRef,
            let cursor = transcript?.nextCursor,
            !cursor.isEmpty
        else {
            return
        }

        isLoadingOlderTranscript = true
        transcriptLoadPhase = .loadingOlder
        defer {
            isLoadingOlderTranscript = false
            transcriptLoadPhase = .idle
        }

        do {
            let olderPage: ThreadTranscript
            if isLocalThread(threadRef) {
                olderPage = try await runtimeStore.loadOlderTranscriptPage(for: threadRef, cursor: cursor)
            } else {
                olderPage = try await supervisorStore.loadOlderTranscriptPage(for: threadRef, cursor: cursor)
            }

            guard transcript?.threadRef == threadRef else { return }
            transcript = transcript?.prependingOlderPage(olderPage) ?? olderPage
            transcriptError = nil
        } catch {
            transcriptError = displayMessage(for: error, threadRef: threadRef)
        }
    }

    private func send(_ text: String, attachments: [ChatInputAttachment] = [], from node: CanvasNode) async -> Bool {
        guard let threadRef = node.metadata.threadRef else { return false }

        let mentionedThreads = workflowThreadMentions(in: text, excluding: threadRef)
        let mentionedFolders = workflowFolderMentions(in: text)

        let localMessageID = "local-\(UUID().uuidString)"
        var workingTranscript = transcript ?? ThreadTranscript(threadRef: threadRef)
        workingTranscript.messages.append(
            ThreadMessage(id: localMessageID, role: .user, text: localEchoText(for: text, attachments: attachments))
        )
        transcript = workingTranscript
        let previousAssistantCount = workingTranscript.messages.filter { $0.role == .assistant }.count
        markNextTurnStartedByUser(threadRef)
        awaitingResponseThreadKeys.insert(threadRef.qualifiedID)
        var didStartTurn = false

        do {
            for mention in mentionedThreads {
                await graphStore.createMessageEdge(from: node.id, to: mention.nodeID, snippet: text)
            }

            let outboundText = messageWithWorkflowThreadContext(
                text,
                mentions: mentionedThreads,
                folderMentions: mentionedFolders,
                sourceThreadRef: threadRef
            )

            try await sendMessage(
                outboundText,
                to: threadRef,
                model: node.metadata.model,
                reasoningEffort: node.metadata.reasoningEffort,
                permissions: node.metadata.threadPermissions,
                attachments: attachments
            )
            didStartTurn = true
            await refreshTranscriptUntilAssistantResponse(for: node, previousAssistantCount: previousAssistantCount)
        } catch {
            removeLocalMessage(id: localMessageID, threadRef: threadRef)
            let message = displayMessage(for: error, threadRef: threadRef)
            transcriptError = message
            await recordThreadFailure(
                threadRef: threadRef,
                method: "turn/start",
                summary: error.isCodexThreadNotFound
                    ? "Saved canvas thread was not found in this Codex runtime."
                    : message
            )
        }

        reconcileAwaitingResponse(for: threadRef)
        return didStartTurn
    }

    private func sendReadingMessage(
        _ text: String,
        attachments: [ChatInputAttachment] = [],
        from nodeID: NodeID
    ) async -> Bool {
        guard
            let node = graphStore.graph.nodes[nodeID],
            let threadRef = node.metadata.threadRef
        else {
            return false
        }

        let mentionedThreads = workflowThreadMentions(in: text, excluding: threadRef)
        let mentionedFolders = workflowFolderMentions(in: text)

        let localMessageID = "local-\(UUID().uuidString)"
        var workingTranscript = readingTranscripts[nodeID] ?? ThreadTranscript(threadRef: threadRef)
        workingTranscript.messages.append(
            ThreadMessage(id: localMessageID, role: .user, text: localEchoText(for: text, attachments: attachments))
        )
        readingTranscripts[nodeID] = workingTranscript
        let previousAssistantCount = workingTranscript.messages.filter { $0.role == .assistant }.count
        markNextTurnStartedByUser(threadRef)
        awaitingResponseThreadKeys.insert(threadRef.qualifiedID)
        var didStartTurn = false

        do {
            for mention in mentionedThreads {
                await graphStore.createMessageEdge(from: node.id, to: mention.nodeID, snippet: text)
            }

            let outboundText = messageWithWorkflowThreadContext(
                text,
                mentions: mentionedThreads,
                folderMentions: mentionedFolders,
                sourceThreadRef: threadRef
            )

            try await sendMessage(
                outboundText,
                to: threadRef,
                model: node.metadata.model,
                reasoningEffort: node.metadata.reasoningEffort,
                permissions: node.metadata.threadPermissions,
                attachments: attachments
            )
            didStartTurn = true
            await refreshReadingTranscriptUntilAssistantResponse(for: nodeID, previousAssistantCount: previousAssistantCount)
        } catch {
            removeLocalMessage(id: localMessageID, threadRef: threadRef, nodeID: nodeID)
            let message = displayMessage(for: error, threadRef: threadRef)
            readingErrors[nodeID] = message
            await recordThreadFailure(
                threadRef: threadRef,
                method: "turn/start",
                summary: error.isCodexThreadNotFound
                    ? "Saved canvas thread was not found in this Codex runtime."
                    : message
            )
        }

        reconcileAwaitingResponse(for: threadRef)
        return didStartTurn
    }

    private func localEchoText(for text: String, attachments: [ChatInputAttachment]) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !attachments.isEmpty else { return text }
        let names = attachments.map(\.name).joined(separator: ", ")
        let suffix = "Attached: \(names)"
        return trimmed.isEmpty ? suffix : "\(text)\n\n\(suffix)"
    }

    private func refreshTranscriptUntilAssistantResponse(for node: CanvasNode, previousAssistantCount: Int) async {
        guard let threadRef = node.metadata.threadRef else { return }

        for _ in 0..<240 {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled,
                  isThreadOpen(hostID: threadRef.hostID, threadID: threadRef.threadID) else { return }

            do {
                let refreshedTranscript = try await loadTranscript(for: threadRef)
                let mergedTranscript = transcriptMergedWithLocalMessages(serverTranscript: refreshedTranscript)
                if activePopoverThreadRef?.matches(hostID: threadRef.hostID, threadID: threadRef.threadID) == true {
                    transcript = mergedTranscript
                    transcriptError = nil
                }

                let assistantCount = refreshedTranscript.messages.filter { $0.role == .assistant }.count
                if assistantCount > previousAssistantCount && !isThreadActivelyRunning(threadRef) {
                    return
                }
            } catch {
                transcriptError = displayMessage(for: error, threadRef: threadRef)
                if error.isCodexThreadNotFound {
                    await recordThreadFailure(
                        threadRef: threadRef,
                        method: "thread/turns/list",
                        summary: "Saved canvas thread was not found in this Codex runtime."
                    )
                }
                return
            }
        }
    }

    private func refreshReadingTranscriptUntilAssistantResponse(for nodeID: NodeID, previousAssistantCount: Int) async {
        guard
            let node = graphStore.graph.nodes[nodeID],
            let threadRef = node.metadata.threadRef
        else {
            return
        }

        for _ in 0..<240 {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled,
                  readingThreadIDs.contains(nodeID) else { return }

            do {
                let refreshedTranscript = try await loadTranscript(for: threadRef)
                guard readingThreadIDs.contains(nodeID) else { return }
                readingTranscripts[nodeID] = transcriptMergedWithLocalMessages(
                    existing: readingTranscripts[nodeID],
                    serverTranscript: refreshedTranscript
                )
                readingErrors[nodeID] = nil

                let assistantCount = refreshedTranscript.messages.filter { $0.role == .assistant }.count
                if assistantCount > previousAssistantCount && !isThreadActivelyRunning(threadRef) {
                    return
                }
            } catch {
                guard readingThreadIDs.contains(nodeID) else { return }
                readingErrors[nodeID] = displayMessage(for: error, threadRef: threadRef)
                if error.isCodexThreadNotFound {
                    await recordThreadFailure(
                        threadRef: threadRef,
                        method: "thread/turns/list",
                        summary: "Saved canvas thread was not found in this Codex runtime."
                    )
                }
                return
            }
        }
    }

    private func displayMessage(for error: Error, threadRef: ThreadRef) -> String {
        if error.isCodexThreadNotFound {
            return "This canvas node points to a Codex thread that the current runtime cannot find. It may belong to another machine, an older Codex install, or a thread that was removed. Create a new thread for this folder or reconnect the machine that owns it."
        }

        return error.localizedDescription
    }

    private func loadTranscript(for threadRef: ThreadRef) async throws -> ThreadTranscript {
        if isLocalThread(threadRef) {
            return try await runtimeStore.loadTranscript(for: threadRef)
        }
        return try await supervisorStore.loadTranscript(for: threadRef)
    }

    private func refreshThreadInbox() async {
        await waitForThreadInboxIdle()
        if threadCatalogStore.isRefreshing {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await refreshThreadInbox()
            return
        }
        let requestedSignature = threadCatalogRefreshSignature
        await threadCatalogStore.refresh(
            runtimeStore: runtimeStore,
            supervisorStore: supervisorStore,
            graph: graphStore.graph,
            workflowMemberships: effectiveWorkflowMemberships,
            includeArchived: true
        )
        guard threadCatalogRefreshSignature == requestedSignature else {
            if threadCatalogStore.selectedMode == .search {
                await searchThreadInbox()
            } else {
                await refreshThreadInbox()
            }
            return
        }
        reconcileOpenThreadsAsRead()
        await syncInboxSubscriptions()
        if threadCatalogStore.selectedMode == .search,
           !threadCatalogStore.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           threadCatalogStore.serverSearchQuery != threadCatalogStore.searchText.trimmingCharacters(in: .whitespacesAndNewlines) {
            await searchThreadInbox()
        }
    }

    private func searchThreadInbox() async {
        await waitForThreadInboxIdle()
        if threadCatalogStore.isRefreshing {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await searchThreadInbox()
            return
        }
        let requestedQuery = threadCatalogStore.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard threadCatalogStore.selectedMode == .search else { return }
        await threadCatalogStore.search(
            runtimeStore: runtimeStore,
            supervisorStore: supervisorStore,
            graph: graphStore.graph,
            workflowMemberships: effectiveWorkflowMemberships
        )
        guard threadCatalogStore.selectedMode == .search else { return }
        let latestQuery = threadCatalogStore.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if latestQuery != requestedQuery || threadCatalogStore.serverSearchQuery != latestQuery {
            await searchThreadInbox()
            return
        }
        reconcileOpenThreadsAsRead()
        await syncInboxSubscriptions()
    }

    private func waitForThreadInboxIdle() async {
        for _ in 0..<80 where threadCatalogStore.isRefreshing {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
        }
    }

    private func retainTransientThreadSubscriptionIfNeeded(_ threadRef: ThreadRef) async {
        guard threadRef.hostID != runtimeStore.localHost.id else { return }
        await supervisorStore.retainThreadSubscription(threadRef, owner: transientSubscriptionOwner(for: threadRef))
    }

    private func releaseTransientThreadSubscriptionIfNeeded() {
        guard let threadRef = transientThreadNode?.metadata.threadRef,
              threadRef.hostID != runtimeStore.localHost.id else {
            return
        }
        Task {
            await supervisorStore.releaseThreadSubscription(threadRef, owner: transientSubscriptionOwner(for: threadRef))
        }
    }

    private func transientSubscriptionOwner(for threadRef: ThreadRef) -> String {
        "inbox-open:\(threadRef.qualifiedID)"
    }

    private func syncInboxSubscriptions() async {
        let desired = Dictionary(
            uniqueKeysWithValues: threadCatalogStore.entries
                .filter { entry in
                    entry.threadRef.hostID != runtimeStore.localHost.id
                        && (entry.isActive || entry.needsAttention)
                }
                .map { ($0.threadRef.qualifiedID, $0.threadRef) }
        )

        for (key, threadRef) in inboxSubscriptionRefs where desired[key] == nil {
            await supervisorStore.releaseThreadSubscription(threadRef, owner: "inbox-active")
        }

        for (key, threadRef) in desired where inboxSubscriptionRefs[key] == nil {
            await supervisorStore.retainThreadSubscription(threadRef, owner: "inbox-active")
        }

        inboxSubscriptionRefs = desired
    }

    private func reconcileOpenThreadsAsRead() {
        for threadRef in openThreadRefs() {
            threadCatalogStore.markRead(threadRef, isRead: true)
        }
    }

    private func openThreadRefs() -> [ThreadRef] {
        var refs: [ThreadRef] = []
        if let threadRef = transientThreadNode?.metadata.threadRef ?? selectedThreadNode?.metadata.threadRef {
            refs.append(threadRef)
        }
        refs.append(contentsOf: readingThreadIDs.compactMap { graphStore.graph.nodes[$0]?.metadata.threadRef })
        var seen = Set<String>()
        return refs.filter { seen.insert($0.qualifiedID).inserted }
    }

    private func openInboxThread(_ entry: ThreadCatalogEntry) {
        if let nodeID = entry.materializedNodeID,
           graphStore.graph.nodes[nodeID] != nil {
            releaseTransientThreadSubscriptionIfNeeded()
            transientOpenGeneration &+= 1
            transientThreadNode = nil
            graphStore.selectNode(nodeID)
            if let node = graphStore.graph.nodes[nodeID] {
                startTranscriptLoad(for: node, force: true, markRead: true)
            }
            return
        }

        transientOpenGeneration &+= 1
        let generation = transientOpenGeneration
        Task {
            var resolvedEntry = entry
            if entry.threadRef.cwd.isEmpty,
               let resolvedThread = await resolveThread(threadID: entry.threadRef.threadID, sourceThreadRef: entry.threadRef) {
                resolvedEntry.threadRef = resolvedThread
            }

            guard generation == transientOpenGeneration else { return }
            let node = transientNode(for: resolvedEntry)
            graphStore.clearSelection()
            releaseTransientThreadSubscriptionIfNeeded()
            guard generation == transientOpenGeneration else { return }
            transientThreadNode = node
            threadCatalogStore.markRead(resolvedEntry.threadRef, isRead: true)
            await retainTransientThreadSubscriptionIfNeeded(resolvedEntry.threadRef)
            guard generation == transientOpenGeneration else { return }
            resetThreadPopoverDataIfNeeded(for: node.metadata.threadRef)
            await loadTranscript(for: node, force: true)
        }
    }

    private func addInboxThreadToCanvas(_ entry: ThreadCatalogEntry) async {
        if let nodeID = entry.materializedNodeID,
           graphStore.graph.nodes[nodeID] != nil {
            transientThreadNode = nil
            graphStore.selectNode(nodeID)
            return
        }

        let platform = graphStore.graph.nodes.values.first {
            $0.kind == .machine && $0.metadata.hostID == entry.threadRef.hostID
        }?.metadata.platform ?? .macOS
        await graphStore.addThreadNode(
            threadRef: entry.threadRef,
            model: entry.model ?? "gpt-5.5",
            reasoningEffort: entry.reasoningEffort ?? "high",
            title: entry.title,
            anchorFolderID: anchorFolderID(for: entry.threadRef),
            platform: platform,
            threadKind: entry.threadKind ?? .thread
        )
        transientThreadNode = nil
        await refreshThreadInbox()
    }

    private func archiveInboxThread(_ entry: ThreadCatalogEntry) async {
        do {
            if isLocalThread(entry.threadRef) {
                try await runtimeStore.archiveThread(entry.threadRef)
            } else {
                try await supervisorStore.archiveThread(entry.threadRef)
            }
            await refreshThreadInbox()
        } catch {
            graphStore.errorMessage = error.localizedDescription
        }
    }

    private func setInboxThread(_ entry: ThreadCatalogEntry, read isRead: Bool) async {
        threadCatalogStore.markRead(entry.threadRef, isRead: isRead)
        if let nodeID = entry.materializedNodeID,
           graphStore.graph.nodes[nodeID] != nil {
            if isRead {
                await graphStore.markThreadRead(nodeID)
            } else {
                await graphStore.markThreadUnread(nodeID)
            }
        }
    }

    private func focusAttentionRequest(_ request: RuntimeAttentionRequest) {
        guard let targetRef = request.targetThreadRef(defaultHostID: runtimeStore.localHost.id) else { return }
        let hostID = targetRef.hostID
        let threadID = targetRef.threadID
        let lookupRef = ThreadRef(hostID: hostID, threadID: threadID, cwd: "", name: nil)
        if let entry = threadCatalogStore.entry(for: lookupRef) {
            openInboxThread(entry)
            return
        }

        if let node = graphStore.graph.nodes.values.first(where: {
            $0.kind == .codexThread
                && $0.metadata.threadRef?.matches(hostID: hostID, threadID: threadID) == true
        }), let threadRef = node.metadata.threadRef {
            openInboxThread(
                ThreadCatalogEntry(
                    threadRef: threadRef,
                    hostName: hostName(for: hostID),
                    title: node.title,
                    preview: request.summary,
                    source: "attention",
                    loadedStatus: .needsInput,
                    lastActivityAt: request.createdAt,
                    unread: true,
                    pendingRequestCount: 1,
                    materializedNodeID: node.id,
                    model: node.metadata.model,
                    reasoningEffort: node.metadata.reasoningEffort,
                    threadKind: node.metadata.threadKind ?? .thread
                )
            )
            return
        }

        openInboxThread(
            ThreadCatalogEntry(
                threadRef: ThreadRef(
                    hostID: hostID,
                    threadID: threadID,
                    cwd: targetRef.cwd,
                    name: nil
                ),
                hostName: hostName(for: hostID),
                title: "Codex thread",
                preview: request.summary,
                source: "attention",
                loadedStatus: .needsInput,
                lastActivityAt: request.createdAt,
                unread: true,
                pendingRequestCount: 1
            )
        )
    }

    private func hostName(for hostID: HostID) -> String {
        graphStore.graph.nodes.values.first {
            $0.kind == .machine && $0.metadata.hostID == hostID
        }?.title
            ?? supervisorStore.machines.first { $0.id == hostID }?.name
            ?? (hostID == runtimeStore.localHost.id ? runtimeStore.localHost.name : hostID.rawValue)
    }

    private func transientNode(for entry: ThreadCatalogEntry) -> CanvasNode {
        CanvasNode(
            id: NodeID(rawValue: "inbox-\(entry.threadRef.qualifiedID)"),
            kind: .codexThread,
            title: entry.title,
            subtitle: entry.threadRef.cwd.isEmpty ? entry.hostName : entry.threadRef.cwd,
            position: .zero,
            size: .thread,
            metadata: NodeMetadata(
                hostID: entry.threadRef.hostID,
                platform: graphStore.graph.nodes.values.first {
                    $0.kind == .machine && $0.metadata.hostID == entry.threadRef.hostID
                }?.metadata.platform,
                threadRef: entry.threadRef,
                model: entry.model,
                reasoningEffort: entry.reasoningEffort,
                threadKind: entry.threadKind,
                runStatus: entry.loadedStatus,
                isUnread: entry.unread
            )
        )
    }

    private func sendMessage(
        _ text: String,
        to threadRef: ThreadRef,
        model: String?,
        reasoningEffort: String?,
        permissions: CodexThreadPermissions? = nil,
        attachments: [ChatInputAttachment] = []
    ) async throws {
        if isLocalThread(threadRef) {
            try await runtimeStore.sendMessage(
                text,
                to: threadRef,
                model: model,
                reasoningEffort: reasoningEffort,
                permissions: permissions,
                attachments: attachments
            )
        } else {
            try await supervisorStore.sendMessage(
                text,
                to: threadRef,
                model: model,
                reasoningEffort: reasoningEffort,
                permissions: permissions,
                attachments: attachments
            )
        }
    }

    private func respondToAttentionRequest(_ request: RuntimeAttentionRequest, allow: Bool) async {
        do {
            if request.hostID == runtimeStore.localHost.id || request.hostID == nil {
                try await runtimeStore.respondToAttentionRequest(request, allow: allow)
            } else {
                try await supervisorStore.respondToAttentionRequest(request, allow: allow)
            }
        } catch {
            await recordThreadFailure(
                threadRef: ThreadRef(
                    hostID: request.hostID ?? runtimeStore.localHost.id,
                    threadID: request.threadID ?? "unknown",
                    cwd: "",
                    name: nil
                ),
                method: request.method,
                summary: error.localizedDescription
            )
        }
    }

    private func respondToAttentionRequest(_ request: RuntimeAttentionRequest, text: String) async {
        do {
            if request.hostID == runtimeStore.localHost.id || request.hostID == nil {
                try await runtimeStore.respondToAttentionRequest(request, text: text)
            } else {
                try await supervisorStore.respondToAttentionRequest(request, text: text)
            }
        } catch {
            await recordThreadFailure(
                threadRef: ThreadRef(
                    hostID: request.hostID ?? runtimeStore.localHost.id,
                    threadID: request.threadID ?? "unknown",
                    cwd: "",
                    name: nil
                ),
                method: request.method,
                summary: error.localizedDescription
            )
        }
    }

    private func declineTypedAttentionRequest(_ request: RuntimeAttentionRequest) async {
        do {
            if request.hostID == runtimeStore.localHost.id || request.hostID == nil {
                try await runtimeStore.declineTypedAttentionRequest(request)
            } else {
                try await supervisorStore.declineTypedAttentionRequest(request)
            }
        } catch {
            await recordThreadFailure(
                threadRef: ThreadRef(
                    hostID: request.hostID ?? runtimeStore.localHost.id,
                    threadID: request.threadID ?? "unknown",
                    cwd: "",
                    name: nil
                ),
                method: request.method,
                summary: error.localizedDescription
            )
        }
    }

    private func resolveThread(threadID: String, sourceThreadRef: ThreadRef) async -> ThreadRef? {
        for hostID in createdThreadResolutionHostIDs(sourceThreadRef: sourceThreadRef) {
            let cwdHint = hostID == sourceThreadRef.hostID ? sourceThreadRef.cwd : nil

            if hostID == runtimeStore.localHost.id {
                if let thread = await runtimeStore.resolveThread(threadID: threadID, cwdHint: cwdHint) {
                    return thread
                }
                continue
            }

            guard supervisorStore.hasRelay(for: hostID) else {
                continue
            }

            if let thread = await supervisorStore.resolveThread(
                threadID: threadID,
                hostID: hostID,
                cwdHint: cwdHint
            ) {
                return thread
            }
        }

        return nil
    }

    private func createdThreadResolutionHostIDs(sourceThreadRef: ThreadRef) -> [HostID] {
        var seen = Set<HostID>()
        var hostIDs: [HostID] = []

        func append(_ hostID: HostID?) {
            guard let hostID, seen.insert(hostID).inserted else {
                return
            }
            hostIDs.append(hostID)
        }

        append(sourceThreadRef.hostID)
        for node in graphStore.graph.sortedNodes {
            append(node.metadata.threadRef?.hostID)
            append(node.metadata.hostID)
        }
        append(runtimeStore.localHost.id)
        for machine in supervisorStore.machines {
            append(machine.id)
        }

        return hostIDs
    }

    private func recordMaterializedThreadLifecycle(threadRef: ThreadRef, sourceNode: CanvasNode) {
        recordMaterializedThreadLifecycle(threadRef: threadRef, sourceNode: sourceNode, finishedAt: Date())
    }

    private func recordMaterializedThreadLifecycle(
        threadRef: ThreadRef,
        sourceNode: CanvasNode,
        finishedAt: Date,
        method: String = "thread/materialized/discovered",
        threadKind: CodexThreadNodeKind = .thread
    ) {
        let trimmedSourceTitle = sourceNode.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceTitle = trimmedSourceTitle.isEmpty ? "another thread" : trimmedSourceTitle
        let startedAt = finishedAt.addingTimeInterval(-1)
        let started = WorkflowEvent(
            id: "materialized-start-\(threadRef.qualifiedID)",
            kind: .turnStarted,
            hostID: threadRef.hostID,
            threadID: threadRef.threadID,
            method: method,
            summary: "Started by \(sourceTitle)",
            createdAt: startedAt
        )
        let completed = WorkflowEvent(
            id: "materialized-complete-\(threadRef.qualifiedID)",
            kind: .turnCompleted,
            hostID: threadRef.hostID,
            threadID: threadRef.threadID,
            method: method,
            summary: "Created by \(sourceTitle)",
            createdAt: finishedAt
        )

        runtimeStore.recordWorkflowEvent(started)
        runtimeStore.recordWorkflowEvent(completed)
        threadCatalogStore.upsert([
            ThreadCatalogEntry(
                threadRef: threadRef,
                hostName: machineTitle(for: threadRef.hostID) ?? threadRef.hostID.rawValue,
                title: threadRef.name ?? "Created thread",
                preview: "Created by \(sourceTitle)",
                source: method,
                loadedStatus: .complete,
                lastActivityAt: finishedAt,
                unread: true,
                materializedNodeID: graphStore.graph.nodes.values.first {
                    $0.kind == .codexThread
                        && $0.metadata.threadRef?.matches(hostID: threadRef.hostID, threadID: threadRef.threadID) == true
                }?.id,
                latestEventSummary: "Created by \(sourceTitle)",
                model: sourceNode.metadata.model,
                reasoningEffort: sourceNode.metadata.reasoningEffort,
                threadKind: threadKind
            ),
        ])
    }

    private func materializeCreatedThreadRefs(
        _ threadRefs: [ThreadRef],
        sourceNode: CanvasNode,
        threadKind: CodexThreadNodeKind = .thread
    ) async {
        for threadRef in threadRefs {
            await graphStore.materializeCreatedThread(
                threadRef: threadRef,
                model: sourceNode.metadata.model,
                reasoningEffort: sourceNode.metadata.reasoningEffort,
                title: threadRef.name,
                createdBy: sourceNode.id,
                threadKind: threadKind
            )
        }
    }

    private func materializeLocalSubagentsFromRolloutIfAvailable(for node: CanvasNode) async {
        guard
            let threadRef = node.metadata.threadRef,
            isLocalThread(threadRef)
        else {
            return
        }

        let metadataChildren = await runtimeStore.localSubagentChildren(for: threadRef)
        await materializeCreatedThreadRefs(metadataChildren, sourceNode: node, threadKind: .subagent)
    }

    private func liveAssistantText(for node: CanvasNode) -> String {
        guard let threadRef = node.metadata.threadRef else {
            return ""
        }
        if isLocalThread(threadRef) {
            return runtimeStore.threadRuntimeStates[threadRef.qualifiedID]?.liveAssistantText
                ?? runtimeStore.liveAssistantTextByThreadID[threadRef.threadID]
                ?? ""
        }
        return supervisorStore.threadRuntimeStates[threadRef.qualifiedID]?.liveAssistantText ?? ""
    }

    private func liveStateSummary(for node: CanvasNode) -> ThreadLiveStateSummary? {
        guard node.kind == .codexThread,
              let threadRef = node.metadata.threadRef else {
            return nil
        }

        if let entry = threadCatalogStore.entry(for: threadRef) {
            return entry.liveStateSummary
        }

        let state = isLocalThread(threadRef)
            ? runtimeStore.threadRuntimeStates[threadRef.qualifiedID]
            : supervisorStore.threadRuntimeStates[threadRef.qualifiedID]
        if let state {
            return state.liveStateSummary
        }

        if let status = node.metadata.runStatus {
            return ThreadCatalogEntry(
                threadRef: threadRef,
                hostName: threadRef.hostID.rawValue,
                title: node.title,
                preview: node.subtitle,
                loadedStatus: status,
                lastActivityAt: graphStore.graph.updatedAt,
                unread: node.metadata.isUnread == true,
                materializedNodeID: node.id,
                model: node.metadata.model,
                reasoningEffort: node.metadata.reasoningEffort,
                threadKind: node.metadata.threadKind ?? .thread
            ).liveStateSummary
        }

        return nil
    }

    private func isLocalThread(_ threadRef: ThreadRef) -> Bool {
        threadRef.hostID == runtimeStore.localHost.id
    }

    private func recordThreadFailure(threadRef: ThreadRef, method: String, summary: String) async {
        let event = WorkflowEvent(
            kind: .failed,
            hostID: threadRef.hostID,
            threadID: threadRef.threadID,
            method: method,
            summary: summary
        )
        runtimeStore.recordWorkflowEvent(event)
        await graphStore.applyWorkflowEvent(event)
    }

    @ViewBuilder
    private func nodeContextMenu(for node: CanvasNode) -> some View {
        if node.kind == .folder {
            Button {
                showFolderContents(node)
            } label: {
                Label("Show Contents", systemImage: "folder")
            }

            Divider()
        }

        if let pickMachineFolder = pickMachineFolderAction(for: node) {
            Button {
                pickMachineFolder()
            } label: {
                Label("Choose Project", systemImage: "folder.badge.plus")
            }
        } else if let addMachineFolder = addMachineFolderAction(for: node),
           let defaultPath = defaultFolderPath(for: node),
           !defaultPath.isEmpty {
            Button {
                addMachineFolder(defaultPath)
            } label: {
                Label("Add Project", systemImage: "folder.badge.plus")
            }
        }

        #if os(macOS)
        if let remote = codexRemote(forMachineNode: node) {
            Button {
                openCodexRemoteDiagnostics(for: remote)
            } label: {
                Label("Remote Diagnostics", systemImage: "list.clipboard")
            }

            Divider()
        }
        #endif

        if node.kind == .codexThread {
            Button {
                graphStore.selectNode(node.id)
                Task {
                    await markThreadReadIfNeeded(node)
                    await loadTranscript(for: node, force: true)
                }
            } label: {
                Label("Open Chat", systemImage: "bubble.left.and.bubble.right")
            }

            #if os(macOS)
            Button {
                isReadingModePresented = true
                Task { await openThreadInReader(node) }
            } label: {
                Label("Open in Reader", systemImage: "rectangle.split.3x1")
            }
            #endif

            if node.metadata.isUnread == true {
                Button {
                    Task { await graphStore.markThreadRead(node.id) }
                } label: {
                    Label("Mark as Read", systemImage: "envelope.open")
                }
            } else {
                Button {
                    Task { await graphStore.markThreadUnread(node.id) }
                } label: {
                    Label("Mark as Unread", systemImage: "envelope.badge")
                }
            }

            if canStopThread(node) || isStoppingThread(node) {
                Button {
                    Task { await stopThreadNode(node) }
                } label: {
                    Label(isStoppingThread(node) ? "Stopping Turn" : "Stop Turn", systemImage: "stop.fill")
                }
                .disabled(isStoppingThread(node))
            }

            Button {
                if canArchiveThread(node) {
                    pendingDestructiveAction = .archiveThread(node)
                } else {
                    showUnavailableControl("Reconnect this thread's machine before archiving it.")
                }
            } label: {
                Label("Archive Codex Thread", systemImage: "archivebox")
            }

            Button {
                if canControlThread(node) {
                    Task { await forkThreadNode(node) }
                } else {
                    showUnavailableControl("Reconnect this thread's machine before duplicating it.")
                }
            } label: {
                Label("Duplicate / Fork", systemImage: "arrow.branch")
            }

            Button {
                copyThreadID(node.metadata.threadRef?.threadID)
            } label: {
                Label("Copy Thread ID", systemImage: "doc.on.doc")
            }

            Button {
                if node.metadata.threadRef != nil {
                    Task { await reconnectThreadOwner(node) }
                } else {
                    showUnavailableControl("This canvas node is missing its thread reference.")
                }
            } label: {
                Label("Reconnect Owner", systemImage: "arrow.triangle.2.circlepath")
            }

            Divider()
        }

        Button(role: .destructive) {
            pendingDestructiveAction = .deleteNode(node)
        } label: {
            Label("Delete from Canvas", systemImage: "trash")
        }
    }

    private func performDestructiveAction(_ action: PendingDestructiveAction) {
        Task {
            switch action {
            case .archiveThread(let node):
                await archiveThreadNode(node)
            case .deleteNode(let node):
                await deleteCanvasNode(node)
            case .deleteManualEdge(let edge):
                await graphStore.deleteManualEdge(edge.id)
            }
        }
    }

    #if os(macOS)
    private func codexRemote(forMachineNode node: CanvasNode) -> CodexDesktopRemote? {
        guard node.kind == .machine,
              let hostID = node.metadata.hostID else {
            return nil
        }
        return supervisorStore.codexRemote(for: hostID)
    }

    private func openCodexRemoteDiagnostics(for remote: CodexDesktopRemote) {
        let presenter = CodexRemoteDiagnosticsWindowPresenter(
            supervisorStore: supervisorStore,
            remote: remote,
            onConnect: {
                Task { await supervisorStore.connectCodexRemote(remote) }
            },
            onDiagnose: {
                Task { await supervisorStore.diagnoseCodexRemote(remote) }
            },
            onAction: { action in
                Task { await supervisorStore.performCodexRemoteAction(action, for: remote) }
            },
            onClose: {
                codexRemoteDiagnosticsWindow = nil
            }
        )
        codexRemoteDiagnosticsWindow = presenter
        presenter.show()
    }
    #endif

    private func canArchiveThread(_ node: CanvasNode) -> Bool {
        canControlThread(node)
    }

    private func canControlThread(_ node: CanvasNode) -> Bool {
        guard let threadRef = node.metadata.threadRef else {
            return false
        }
        return isLocalThread(threadRef) || supervisorStore.hasRelay(for: threadRef.hostID)
    }

    private func canStopThread(_ node: CanvasNode) -> Bool {
        guard let threadRef = node.metadata.threadRef else {
            return false
        }
        return canControlThread(node) && isThreadActivelyRunning(threadRef)
    }

    private func isStoppingThread(_ node: CanvasNode) -> Bool {
        guard let threadRef = node.metadata.threadRef else {
            return false
        }
        return stoppingThreadKeys.contains(threadRef.qualifiedID)
    }

    private func stopThreadNode(nodeID: NodeID) async {
        guard let node = graphStore.graph.nodes[nodeID] else {
            return
        }
        await stopThreadNode(node)
    }

    private func stopThreadNode(_ node: CanvasNode) async {
        guard let threadRef = node.metadata.threadRef else {
            showUnavailableControl("This canvas node is missing its thread reference.")
            return
        }
        guard canControlThread(node) else {
            showUnavailableControl("Reconnect this thread's machine before stopping it.")
            return
        }

        let key = threadRef.qualifiedID
        guard !stoppingThreadKeys.contains(key) else { return }
        stoppingThreadKeys.insert(key)
        defer {
            stoppingThreadKeys.remove(key)
        }

        do {
            let turnID: String
            if isLocalThread(threadRef) {
                turnID = try await runtimeStore.interruptThread(threadRef)
            } else {
                turnID = try await supervisorStore.interruptThread(threadRef)
            }

            awaitingResponseThreadKeys.remove(key)
            let event = WorkflowEvent(
                kind: .turnCompleted,
                hostID: threadRef.hostID,
                threadID: threadRef.threadID,
                turnID: turnID,
                method: "turn/interrupt",
                summary: "Turn stopped by you"
            )
            if isLocalThread(threadRef) {
                runtimeStore.recordWorkflowEvent(event)
            } else {
                await supervisorStore.recordWorkflowEvent(event)
            }
            await graphStore.applyWorkflowEvent(event, markUnread: false)
            await refreshOpenTranscripts(for: threadRef)
        } catch {
            let message = displayMessage(for: error, threadRef: threadRef)
            transcriptError = message
            graphStore.errorMessage = message
        }
    }

    private func archiveThreadNode(_ node: CanvasNode) async {
        guard let threadRef = node.metadata.threadRef else {
            return
        }

        do {
            if isLocalThread(threadRef) {
                try await runtimeStore.archiveThread(threadRef)
            } else {
                try await supervisorStore.archiveThread(threadRef)
            }
            await deleteCanvasNode(node)
        } catch {
            graphStore.errorMessage = error.localizedDescription
            transcriptError = error.localizedDescription
        }
    }

    private func forkThreadNode(_ node: CanvasNode) async {
        guard let threadRef = node.metadata.threadRef else {
            return
        }

        do {
            let forkedRef: ThreadRef
            if isLocalThread(threadRef) {
                forkedRef = try await runtimeStore.forkThread(threadRef, model: node.metadata.model)
            } else {
                forkedRef = try await supervisorStore.forkThread(threadRef, model: node.metadata.model)
            }

            await graphStore.addThreadNode(
                threadRef: forkedRef,
                model: node.metadata.model ?? "gpt-5.5",
                reasoningEffort: node.metadata.reasoningEffort ?? "high",
                title: "\(node.title) fork",
                anchorFolderID: anchorFolderID(for: forkedRef)
            )
        } catch {
            graphStore.errorMessage = error.localizedDescription
            transcriptError = error.localizedDescription
        }
    }

    private func reconnectThreadOwner(_ node: CanvasNode) async {
        guard let threadRef = node.metadata.threadRef else { return }
        if isLocalThread(threadRef) {
            await runtimeStore.connect()
        } else {
            await supervisorStore.reconnect(threadRef.hostID)
        }
    }

    private func anchorFolderID(for threadRef: ThreadRef) -> NodeID? {
        graphStore.graph.sortedNodes.first { node in
            guard
                node.kind == .folder,
                node.metadata.hostID == threadRef.hostID,
                let folderPath = node.metadata.folderPath
            else {
                return false
            }
            return Self.path(threadRef.cwd, isInsideOrEqualTo: folderPath)
        }?.id
    }

    private func copyThreadID(_ threadID: String?) {
        guard let threadID else { return }
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(threadID, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = threadID
        #endif
    }

    private func showUnavailableControl(_ message: String) {
        graphStore.errorMessage = message
    }

    private func deleteCanvasNode(_ node: CanvasNode) async {
        if selectedNodeID == node.id {
            transcript = nil
            transcriptError = nil
            graphStore.clearSelection()
        }

        await graphStore.deleteNode(node.id)
    }

    private func addMachineFolderAction(for node: CanvasNode) -> ((String) -> Void)? {
        guard
            node.kind == .machine,
            node.metadata.hostStatus == .connected,
            let hostID = node.metadata.hostID
        else {
            return nil
        }

        return { path in
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            Task {
                await graphStore.addFolder(
                    path: trimmed,
                    hostID: hostID,
                    platform: node.metadata.platform ?? .unknown
                )
            }
        }
    }

    private func showFolderContents(_ node: CanvasNode) {
        guard node.kind == .folder else { return }

        let folderPath = (node.metadata.folderPath ?? node.subtitle)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folderPath.isEmpty else {
            showUnavailableControl("This folder node does not have a folder path.")
            return
        }

        guard let hostID = node.metadata.hostID else {
            openLocalFolderContents(path: folderPath)
            return
        }

        if hostID == runtimeStore.localHost.id {
            openLocalFolderContents(path: folderPath)
            return
        }

        guard
            let remote = supervisorStore.codexRemote(for: hostID),
            CodexRemoteTunnelService.canBrowseRemoteFolders(for: remote)
        else {
            showUnavailableControl("Reconnect this folder's machine before showing remote contents.")
            return
        }

        remoteFolderPickerRequest = RemoteFolderPickerRequest(
            remote: remote,
            hostID: hostID,
            platform: node.metadata.platform ?? remote.platform,
            initialPath: folderPath,
            mode: .showContents
        )
    }

    private func openLocalFolderContents(path: String) {
        let expandedPath = NSString(string: path).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            showUnavailableControl("The folder does not exist on this machine.")
            return
        }

        #if os(macOS)
        let url = URL(fileURLWithPath: expandedPath, isDirectory: true)
        if !NSWorkspace.shared.open(url) {
            showUnavailableControl("Could not open the folder in Finder.")
        }
        #else
        showUnavailableControl("Showing local folder contents is only available on macOS.")
        #endif
    }

    private func pickMachineFolderAction(for node: CanvasNode) -> (() -> Void)? {
        guard
            node.kind == .machine,
            let hostID = node.metadata.hostID
        else {
            return nil
        }

        if hostID != runtimeStore.localHost.id,
           let remote = supervisorStore.codexRemote(for: hostID),
           CodexRemoteTunnelService.canBrowseRemoteFolders(for: remote) {
            return {
                remoteFolderPickerRequest = RemoteFolderPickerRequest(
                    remote: remote,
                    hostID: hostID,
                    platform: node.metadata.platform ?? remote.platform,
                    initialPath: defaultFolderPath(for: node) ?? "~"
                )
            }
        }

        guard hostID == runtimeStore.localHost.id else {
            return nil
        }

        return {
            onPickLocalMachineFolder(node)
        }
    }

    private func defaultFolderPath(for node: CanvasNode) -> String? {
        guard node.kind == .machine else {
            return nil
        }

        let platform = node.metadata.platform ?? .unknown
        let codexHome = machineCodexHome(for: node.metadata.hostID)

        switch platform {
        case .windows:
            if let codexHome, codexHome.lowercased().hasSuffix("\\.codex") {
                return "\(String(codexHome.dropLast("\\.codex".count)))\\Desktop"
            }
            return "C:\\Users\\User\\Desktop"
        case .macOS, .linux:
            if let codexHome, codexHome.hasSuffix("/.codex") {
                return String(codexHome.dropLast("/.codex".count))
            }
            return "~"
        case .iOS, .iPadOS, .unknown:
            return "~"
        }
    }

    private func machineCodexHome(for hostID: HostID?) -> String? {
        guard let hostID else {
            return nil
        }
        if hostID == runtimeStore.localHost.id {
            return runtimeStore.localHost.codexHome
        }
        return supervisorStore.machines.first { $0.id == hostID }?.codexHome
    }

    private func threadRef(matching event: WorkflowEvent) -> ThreadRef? {
        guard let threadID = event.threadID else {
            return nil
        }

        return graphStore.graph.nodes.values.first {
            $0.kind == .codexThread
                && $0.metadata.threadRef?.matches(hostID: event.hostID, threadID: threadID) == true
        }?.metadata.threadRef
    }

    private func sourceNode(for threadRef: ThreadRef) -> CanvasNode? {
        graphStore.graph.nodes.values.first {
            $0.kind == .codexThread
                && $0.metadata.threadRef?.matches(hostID: threadRef.hostID, threadID: threadRef.threadID) == true
        }
    }

    private func isThreadActivelyRunning(_ threadRef: ThreadRef) -> Bool {
        let state = isLocalThread(threadRef)
            ? runtimeStore.threadRuntimeStates[threadRef.qualifiedID]
            : supervisorStore.threadRuntimeStates[threadRef.qualifiedID]
        if let state {
            return state.status == .running || state.activeFlags.contains(.running)
        }
        return sourceNode(for: threadRef)?.metadata.runStatus == .running
    }

    private func isAwaitingResponse(for node: CanvasNode) -> Bool {
        guard let threadRef = node.metadata.threadRef else {
            return false
        }
        return awaitingResponseThreadKeys.contains(threadRef.qualifiedID)
            && (isThreadActivelyRunning(threadRef)
                || hasPendingUserTurnStart(for: threadRef))
    }

    private func reconcileAwaitingResponse(for threadRef: ThreadRef) {
        if !isThreadActivelyRunning(threadRef) {
            awaitingResponseThreadKeys.remove(threadRef.qualifiedID)
        }
    }

    private func hasPendingUserTurnStart(for threadRef: ThreadRef, now: Date = Date()) -> Bool {
        pendingUserTurnStarts.contains { marker in
            marker.threadID == threadRef.threadID
                && marker.hostID == threadRef.hostID
                && now.timeIntervalSince(marker.createdAt) <= Self.userTurnMarkerFollowWindow
        }
    }

    private func refreshVisibleTranscripts(after event: WorkflowEvent) async {
        guard let threadRef = threadRef(matching: event) else { return }
        let key = threadRef.qualifiedID

        switch event.kind {
        case .turnStarted:
            guard shouldApplyEventToRunState(event), isThreadActivelyRunning(threadRef) else {
                awaitingResponseThreadKeys.remove(key)
                return
            }
            awaitingResponseThreadKeys.insert(key)
            startLiveTranscriptRefreshIfNeeded(for: threadRef)
        case .turnCompleted, .failed, .needsInput:
            await refreshOpenTranscripts(for: threadRef)
            awaitingResponseThreadKeys.remove(key)
        case .threadCreated, .folderCreated:
            break
        }
    }

    private func startLiveTranscriptRefreshIfNeeded(for threadRef: ThreadRef) {
        let key = threadRef.qualifiedID
        guard isThreadOpen(hostID: threadRef.hostID, threadID: threadRef.threadID),
              !liveRefreshThreadKeys.contains(key) else {
            return
        }

        liveRefreshThreadKeys.insert(key)
        Task {
            await liveTranscriptRefreshLoop(for: threadRef, key: key)
        }
    }

    private func liveTranscriptRefreshLoop(for threadRef: ThreadRef, key: String) async {
        defer {
            liveRefreshThreadKeys.remove(key)
        }

        for _ in 0..<240 {
            try? await Task.sleep(for: .milliseconds(900))
            guard isThreadOpen(hostID: threadRef.hostID, threadID: threadRef.threadID) else {
                return
            }

            await refreshOpenTranscripts(for: threadRef)

            if !isThreadActivelyRunning(threadRef) {
                awaitingResponseThreadKeys.remove(key)
                return
            }
        }

        awaitingResponseThreadKeys.remove(key)
    }

    private func refreshOpenTranscripts(for threadRef: ThreadRef) async {
        guard isThreadOpen(hostID: threadRef.hostID, threadID: threadRef.threadID) else {
            return
        }

        do {
            let refreshedTranscript = try await loadTranscript(for: threadRef)
            if (transientThreadNode ?? selectedThreadNode)?.metadata.threadRef?.matches(hostID: threadRef.hostID, threadID: threadRef.threadID) == true {
                transcript = transcriptMergedWithLocalMessages(serverTranscript: refreshedTranscript)
                transcriptError = nil
            }

            for nodeID in readingThreadIDs where graphStore.graph.nodes[nodeID]?.metadata.threadRef?.matches(hostID: threadRef.hostID, threadID: threadRef.threadID) == true {
                readingTranscripts[nodeID] = transcriptMergedWithLocalMessages(
                    existing: readingTranscripts[nodeID],
                    serverTranscript: refreshedTranscript
                )
                readingErrors[nodeID] = nil
            }

            applyThreadCatalogRuntimeState()
            await reconcileGraphRunStatus(for: threadRef)
            reconcileAwaitingResponse(for: threadRef)
        } catch {
            let message = displayMessage(for: error, threadRef: threadRef)
            if (transientThreadNode ?? selectedThreadNode)?.metadata.threadRef?.matches(hostID: threadRef.hostID, threadID: threadRef.threadID) == true {
                transcriptError = message
            }
            for nodeID in readingThreadIDs where graphStore.graph.nodes[nodeID]?.metadata.threadRef?.matches(hostID: threadRef.hostID, threadID: threadRef.threadID) == true {
                readingErrors[nodeID] = message
            }
            reconcileAwaitingResponse(for: threadRef)
        }
    }

    private func reconcileGraphRunStatus(for threadRef: ThreadRef) async {
        let state = isLocalThread(threadRef)
            ? runtimeStore.threadRuntimeStates[threadRef.qualifiedID]
            : supervisorStore.threadRuntimeStates[threadRef.qualifiedID]
        guard let state else { return }
        await graphStore.updateThreadRunStatus(for: threadRef, status: state.status)
    }

    private func transcriptMergedWithLocalMessages(serverTranscript: ThreadTranscript) -> ThreadTranscript {
        transcriptMergedWithLocalMessages(existing: transcript, serverTranscript: serverTranscript)
    }

    private func removeLocalMessage(id: String, threadRef: ThreadRef, nodeID: NodeID? = nil) {
        if transcript?.threadRef == threadRef {
            transcript?.messages.removeAll { $0.id == id }
        }

        if let nodeID {
            readingTranscripts[nodeID]?.messages.removeAll { $0.id == id }
        }
    }

    private func transcriptMergedWithLocalMessages(
        existing: ThreadTranscript?,
        serverTranscript: ThreadTranscript
    ) -> ThreadTranscript {
        guard existing?.threadRef == serverTranscript.threadRef else {
            return serverTranscript
        }

        var mergedTranscript = serverTranscript
        var seenIDs = Set(serverTranscript.messages.map(\.id))
        let existingLoadedMessages = existing?.messages.filter { message in
            !message.id.hasPrefix("local-") && seenIDs.insert(message.id).inserted
        } ?? []
        let localOnlyMessages = existing?.messages.filter { message in
            message.id.hasPrefix("local-")
                && !serverTranscript.messages.contains { serverMessage in
                    serverMessageRepresentsLocalMessage(serverMessage, localMessage: message)
                }
        } ?? []
        mergedTranscript.messages = (existingLoadedMessages + serverTranscript.messages + localOnlyMessages)
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.createdAt == rhs.element.createdAt {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.createdAt < rhs.element.createdAt
            }
            .map(\.element)
        if (existing?.messages.count ?? 0) > serverTranscript.messages.count {
            mergedTranscript.nextCursor = existing?.nextCursor
        }
        return mergedTranscript
    }

    private func serverMessageRepresentsLocalMessage(_ serverMessage: ThreadMessage, localMessage: ThreadMessage) -> Bool {
        guard serverMessage.role == localMessage.role else {
            return false
        }
        if serverMessage.text == localMessage.text {
            return true
        }
        guard localMessage.role == .user,
              !localMessage.text.isEmpty,
              serverMessage.text.hasPrefix(localMessage.text),
              (
                serverMessage.text.contains("Workflow chat references:")
                    || serverMessage.text.contains("Workflow folder references:")
              )
        else {
            return false
        }
        return true
    }

    private func handleWorkflowEvents(_ events: [WorkflowEvent]) async {
        let unhandledEvents = events
            .reversed()
            .filter { !handledWorkflowEventIDs.contains($0.dedupeKey) }

        for event in unhandledEvents {
            let isLiveEvent = event.createdAt >= workflowEventStateStartedAt
            let eventKey = event.dedupeKey
            handledWorkflowEventIDs.insert(eventKey)
            handledWorkflowEventIDOrder.append(eventKey)
            captureUserStartedTurnIfNeeded(for: event)
            pruneUserTurnAttribution(now: event.createdAt)
            let threadTitle = threadTitle(for: event)
            if shouldApplyEventToRunState(event) {
                await graphStore.applyWorkflowEvent(event, markUnread: shouldMarkUnread(for: event))
            }
            if isLiveEvent {
                await materializeCreatedFolderIfNeeded(from: event)
                await materializeCreatedThreadIfNeeded(from: event)
                await refreshVisibleTranscripts(after: event)

                if shouldPostUserNotification(for: event) {
                    await WorkflowUserNotifier.post(event: event, threadTitle: threadTitle)
                }
            }
        }

        if handledWorkflowEventIDs.count > 160 {
            handledWorkflowEventIDOrder = Array(handledWorkflowEventIDOrder.suffix(80))
            handledWorkflowEventIDs = Set(handledWorkflowEventIDOrder)
        }

        applyThreadCatalogRuntimeState()
        await syncInboxSubscriptions()
    }

    private func primeHandledWorkflowEvents(_ events: [WorkflowEvent]) {
        workflowEventStateStartedAt = Date()
        let primedEvents = events.reversed()
        handledWorkflowEventIDs = Set(primedEvents.map(\.dedupeKey))
        handledWorkflowEventIDOrder = Array(primedEvents.map(\.dedupeKey).suffix(80))
    }

    private func applyThreadCatalogRuntimeState() {
        threadCatalogStore.apply(runtimeStates: runtimeStore.threadRuntimeStates)
        threadCatalogStore.apply(runtimeStates: supervisorStore.threadRuntimeStates)
        threadCatalogStore.apply(
            events: runtimeStore.workflowEvents + supervisorStore.workflowEvents,
            graph: graphStore.graph,
            defaultHostID: runtimeStore.localHost.id
        )
        threadCatalogStore.applyWorkflowMemberships(effectiveWorkflowMemberships)
        threadCatalogStore.apply(attentionRequests: runtimeStore.pendingAttentionRequests + supervisorStore.pendingAttentionRequests)
        reconcileOpenThreadsAsRead()
    }

    private var effectiveWorkflowMemberships: [String: [ThreadWorkflowMembership]] {
        let active = ThreadWorkflowMembership.activeMap(
            graph: graphStore.graph,
            workflowID: activeWorkflowID,
            workflowName: activeWorkflowName
        )
        return ThreadWorkflowMembership.merging(workflowMemberships, active: active)
    }

    private func materializeCreatedFolderIfNeeded(from event: WorkflowEvent) async {
        if event.kind == .folderCreated {
            guard let path = event.childFolderPath?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty,
                  let hostID = event.childHostID ?? event.hostID
            else {
                return
            }

            await graphStore.materializeWorkflowFolderRoot(
                path: path,
                hostID: hostID,
                title: event.childTitle
            )
            return
        }

        guard event.kind == .threadCreated,
              let childThreadRef = event.childThreadRef,
              !childThreadRef.cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }

        await graphStore.materializeWorkflowFolderRoot(
            path: childThreadRef.cwd,
            hostID: childThreadRef.hostID
        )
    }

    private func materializeCreatedThreadIfNeeded(from event: WorkflowEvent) async {
        guard event.kind == .threadCreated,
              var childThreadRef = event.childThreadRef,
              let sourceThreadID = event.threadID
        else {
            return
        }
        guard let sourceNode = graphStore.graph.nodes.values.first(where: {
            $0.kind == .codexThread
                && $0.metadata.threadRef?.matches(hostID: event.hostID, threadID: sourceThreadID) == true
        }), let sourceThreadRef = sourceNode.metadata.threadRef else {
            return
        }

        if childThreadRef.cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let resolved = await resolveThread(threadID: childThreadRef.threadID, sourceThreadRef: sourceThreadRef) {
            childThreadRef = ThreadRef(
                hostID: resolved.hostID,
                threadID: resolved.threadID,
                cwd: resolved.cwd,
                name: event.childTitle ?? resolved.name
            )
        }

        let isNewWorkflowNode = !graphStore.graph.nodes.values.contains { node in
            node.kind == .codexThread
                && node.metadata.threadRef?.matches(hostID: childThreadRef.hostID, threadID: childThreadRef.threadID) == true
        }
        let threadKind = event.childThreadKind ?? .thread

        await graphStore.materializeCreatedThread(
            threadRef: childThreadRef,
            model: sourceNode.metadata.model,
            reasoningEffort: sourceNode.metadata.reasoningEffort,
            title: event.childTitle ?? childThreadRef.name,
            createdBy: sourceNode.id,
            threadKind: threadKind
        )

        if isNewWorkflowNode {
            recordMaterializedThreadLifecycle(
                threadRef: childThreadRef,
                sourceNode: sourceNode,
                finishedAt: event.createdAt,
                method: event.method,
                threadKind: threadKind
            )
        }
    }

    private func shouldPostUserNotification(for event: WorkflowEvent) -> Bool {
        guard notificationPreferences.shouldNotify(for: event.kind) else {
            return false
        }

        guard let threadID = event.threadID else {
            return true
        }

        return !isThreadOpen(hostID: event.hostID, threadID: threadID)
    }

    private func shouldApplyEventToRunState(_ event: WorkflowEvent) -> Bool {
        guard event.kind != .threadCreated && event.kind != .folderCreated else {
            return false
        }
        return event.kind != .turnStarted || event.createdAt >= workflowEventStateStartedAt
    }

    private func shouldMarkUnread(for event: WorkflowEvent) -> Bool {
        guard
            event.kind == .turnCompleted,
            event.createdAt >= workflowEventStateStartedAt,
            let threadID = event.threadID
        else {
            return false
        }

        return !isThreadOpen(hostID: event.hostID, threadID: threadID)
    }

    private func isThreadOpen(hostID: HostID?, threadID: String) -> Bool {
        if transientThreadNode?.metadata.threadRef?.matches(hostID: hostID, threadID: threadID) == true {
            return true
        }

        if selectedThreadNode?.metadata.threadRef?.matches(hostID: hostID, threadID: threadID) == true {
            return true
        }

        guard isReadingModePresented else {
            return false
        }

        return readingThreadIDs.contains { nodeID in
            graphStore.graph.nodes[nodeID]?.metadata.threadRef?.matches(hostID: hostID, threadID: threadID) == true
        }
    }

    private func focusThread(for event: WorkflowEvent) {
        guard let threadID = event.threadID else { return }
        graphStore.selectThread(hostID: event.hostID, threadID: threadID)
        guard let selectedThreadNode else {
            Task { await focusCatalogThread(for: event) }
            return
        }
        Task {
            if isReadingModePresented {
                await openThreadInReader(selectedThreadNode)
            } else {
                await markThreadReadIfNeeded(selectedThreadNode)
            }
        }
    }

    private func focusCatalogThread(for event: WorkflowEvent) async {
        guard let threadID = event.threadID else { return }
        let hostID = event.hostID ?? runtimeStore.localHost.id
        let key = ThreadRef.qualifiedID(hostID: hostID, threadID: threadID)

        if let entry = threadCatalogStore.entriesByID[key] {
            openInboxThread(entry)
            return
        }

        let fallbackRef = ThreadRef(hostID: hostID, threadID: threadID, cwd: "", name: nil)
        let entry = ThreadCatalogEntry(
            threadRef: fallbackRef,
            hostName: machineTitle(for: hostID) ?? hostID.rawValue,
            title: threadTitle(for: event),
            preview: event.summary,
            source: event.method,
            loadedStatus: runStatus(for: event.kind),
            lastActivityAt: event.createdAt,
            unread: false,
            latestEventSummary: event.summary
        )
        threadCatalogStore.upsert([entry])
        openInboxThread(entry)
    }

    private func threadTitle(for event: WorkflowEvent) -> String {
        guard let threadID = event.threadID else {
            return "Codex thread"
        }
        return graphStore.graph.nodes.values.first {
            $0.metadata.threadRef?.matches(hostID: event.hostID, threadID: threadID) == true
        }?.title
            ?? threadCatalogStore.entriesByID[ThreadRef.qualifiedID(hostID: event.hostID ?? runtimeStore.localHost.id, threadID: threadID)]?.title
            ?? "Codex thread"
    }

    private func runStatus(for kind: WorkflowEventKind) -> ThreadRunStatus {
        switch kind {
        case .turnStarted:
            return .running
        case .turnCompleted:
            return .complete
        case .threadCreated, .folderCreated:
            return .complete
        case .needsInput:
            return .needsInput
        case .failed:
            return .failed
        }
    }

    private func messageRoutes(for edge: CanvasEdge) -> [MessageRoute] {
        graphStore.graph.messageRoutes.values
            .filter { $0.canvasEdgeID == edge.id }
            .sorted { lhs, rhs in lhs.timestamp > rhs.timestamp }
    }

    private func turnOriginTitle(for event: WorkflowEvent) -> String? {
        if isUserStartedTurn(event) {
            return "you"
        }

        return WorkflowActivityAttribution
            .origin(for: event, in: graphStore.graph, events: workflowEvents)?
            .title
    }

    private func markNextTurnStartedByUser(_ threadRef: ThreadRef) {
        pendingUserTurnStarts.removeAll { marker in
            Date().timeIntervalSince(marker.createdAt) > Self.userTurnMarkerFollowWindow
        }
        pendingUserTurnStarts.append(
            PendingUserTurnStart(
                hostID: threadRef.hostID,
                threadID: threadRef.threadID,
                createdAt: Date()
            )
        )
    }

    private func captureUserStartedTurnIfNeeded(for event: WorkflowEvent) {
        guard event.kind == .turnStarted,
              let threadID = event.threadID,
              let key = userTurnKey(for: event) else {
            return
        }

        guard let index = pendingUserTurnStarts.firstIndex(where: { marker in
            marker.threadID == threadID
                && (event.hostID == nil || marker.hostID == event.hostID)
                && event.createdAt.timeIntervalSince(marker.createdAt) >= -Self.userTurnMarkerLeadWindow
                && event.createdAt.timeIntervalSince(marker.createdAt) <= Self.userTurnMarkerFollowWindow
        }) else {
            return
        }

        pendingUserTurnStarts.remove(at: index)
        userStartedTurnKeys[key] = event.createdAt
    }

    private func isUserStartedTurn(_ event: WorkflowEvent) -> Bool {
        guard let basisEvent = userStartedBasisEvent(for: event),
              let key = userTurnKey(for: basisEvent) else {
            return false
        }
        return userStartedTurnKeys[key] != nil
    }

    private func userStartedBasisEvent(for event: WorkflowEvent) -> WorkflowEvent? {
        guard event.kind == .turnCompleted else {
            return event.kind == .turnStarted ? event : nil
        }

        return workflowEvents
            .filter { candidate in
                candidate.kind == .turnStarted
                    && candidate.threadID == event.threadID
                    && (event.hostID == nil || candidate.hostID == nil || candidate.hostID == event.hostID)
                    && (event.turnID == nil || candidate.turnID == event.turnID)
                    && candidate.createdAt <= event.createdAt
            }
            .max { $0.createdAt < $1.createdAt }
    }

    private func userTurnKey(for event: WorkflowEvent) -> String? {
        guard let threadID = event.threadID else {
            return nil
        }

        let hostID = event.hostID?.rawValue ?? "unknown"
        if let turnID = event.turnID, !turnID.isEmpty {
            return "\(hostID)::\(threadID)::\(turnID)"
        }
        return "\(hostID)::\(threadID)::\(event.dedupeKey)"
    }

    private func pruneUserTurnAttribution(now: Date = Date()) {
        pendingUserTurnStarts.removeAll { marker in
            now.timeIntervalSince(marker.createdAt) > Self.userTurnMarkerFollowWindow
        }
        userStartedTurnKeys = userStartedTurnKeys.filter { _, createdAt in
            now.timeIntervalSince(createdAt) <= Self.userTurnAttributionRetention
        }
    }

    private func workflowThreadMentions(in text: String, excluding currentThreadRef: ThreadRef?) -> [WorkflowThreadMentionContext] {
        let lowercasedText = text.lowercased()
        var seenThreadKeys = Set<String>()

        return graphStore.graph.sortedNodes.compactMap { node in
            guard
                node.kind == .codexThread,
                let threadRef = node.metadata.threadRef,
                threadRef != currentThreadRef,
                !seenThreadKeys.contains(threadRef.qualifiedID)
            else {
                return nil
            }

            let encodedHost = Self.percentEncoded(threadRef.hostID.rawValue).lowercased()
            let encodedThreadID = Self.percentEncoded(threadRef.threadID).lowercased()
            let mentionURL = "codex-thread://\(encodedHost)/\(encodedThreadID)"
            guard lowercasedText.contains(mentionURL) else { return nil }

            seenThreadKeys.insert(threadRef.qualifiedID)
            return WorkflowThreadMentionContext(
                nodeID: node.id,
                title: node.title,
                threadRef: threadRef,
                model: node.metadata.model,
                reasoningEffort: node.metadata.reasoningEffort
            )
        }
    }

    private func workflowFolderMentions(in text: String) -> [WorkflowFolderMentionContext] {
        let lowercasedText = text.lowercased()
        var seenFolderIDs = Set<NodeID>()

        return graphStore.graph.sortedNodes.compactMap { node in
            guard
                node.kind == .folder,
                let hostID = node.metadata.hostID,
                let folderPath = node.metadata.folderPath,
                !seenFolderIDs.contains(node.id)
            else {
                return nil
            }

            let encodedHost = Self.percentEncoded(hostID.rawValue).lowercased()
            let encodedNodeID = Self.percentEncoded(node.id.rawValue).lowercased()
            let mentionURL = "mapofagents-folder://\(encodedHost)/\(encodedNodeID)"
            guard lowercasedText.contains(mentionURL) else { return nil }

            seenFolderIDs.insert(node.id)
            return WorkflowFolderMentionContext(
                nodeID: node.id,
                title: node.title,
                hostID: hostID,
                platform: node.metadata.platform ?? .unknown,
                folderPath: folderPath,
                machineTitle: machineTitle(for: hostID)
            )
        }
    }

    private func messageWithWorkflowThreadContext(
        _ text: String,
        mentions: [WorkflowThreadMentionContext],
        folderMentions: [WorkflowFolderMentionContext] = [],
        sourceThreadRef: ThreadRef
    ) -> String {
        guard !mentions.isEmpty || !folderMentions.isEmpty else {
            return text
        }

        let contextLines = mentions.map { mention in
            let reachability = mention.threadRef.hostID == sourceThreadRef.hostID ? "same host" : "different host"
            return "- title=\(Self.redactedContextLabel(mention.title)); reachability=\(reachability); hostID=\(Self.contextValue(mention.threadRef.hostID.rawValue)); threadID=\(Self.contextValue(mention.threadRef.threadID)); model=\(Self.contextValue(mention.model ?? "unknown")); reasoning=\(Self.contextValue(mention.reasoningEffort ?? "unknown")); cwd=redacted"
        }
        let folderContextLines = folderMentions.map { mention in
            let reachability = mention.hostID == sourceThreadRef.hostID ? "same host" : "different host"
            return "- title=\(Self.redactedContextLabel(mention.title)); reachability=\(reachability); folderNodeID=\(Self.contextValue(mention.nodeID.rawValue)); hostID=\(Self.contextValue(mention.hostID.rawValue)); machine=\(Self.redactedContextLabel(mention.machineTitle ?? "unknown")); platform=\(Self.contextValue(mention.platform.rawValue)); folderPath=redacted"
        }
        var targetHostIDs = Set(mentions.map(\.threadRef.hostID))
        targetHostIDs.formUnion(folderMentions.map(\.hostID))
        let routeLines = workflowRouteContextLines(for: targetHostIDs, sourceThreadRef: sourceThreadRef)

        return """
        \(text)

        Workflow chat references:
        \(contextLines.isEmpty ? "- none" : contextLines.joined(separator: "\n"))

        Workflow folder references:
        \(folderContextLines.isEmpty ? "- none" : folderContextLines.joined(separator: "\n"))

        Workflow route map:
        \(routeLines.joined(separator: "\n"))

        You are running as hostID=\(Self.contextValue(sourceThreadRef.hostID.rawValue)). Only use these references because the user inserted explicit workflow mention tokens. Ask before using paths, endpoints, SSH details, or identity files; those values are intentionally not included here.
        """
    }

    private func workflowRouteContextLines(
        for mentions: [WorkflowThreadMentionContext],
        sourceThreadRef: ThreadRef
    ) -> [String] {
        workflowRouteContextLines(for: Set(mentions.map(\.threadRef.hostID)), sourceThreadRef: sourceThreadRef)
    }

    private func workflowRouteContextLines(
        for targetHostIDs: Set<HostID>,
        sourceThreadRef: ThreadRef
    ) -> [String] {
        return targetHostIDs.sorted { $0.rawValue < $1.rawValue }.map { hostID in
            workflowRouteContextLine(for: hostID, sourceHostID: sourceThreadRef.hostID)
        }
    }

    private func workflowRouteContextLine(for hostID: HostID, sourceHostID: HostID) -> String {
        let isSourceHost = hostID == sourceHostID
        let isLocalHost = hostID == runtimeStore.localHost.id
        let machine = supervisorStore.machines.first { $0.id == hostID }
        let name = isLocalHost ? runtimeStore.localHost.name : (machine?.name ?? "Unknown host")
        let platform = isLocalHost ? runtimeStore.localHost.platform.rawValue : (machine?.platform.rawValue ?? "unknown")
        let status = isLocalHost ? runtimeStore.localHost.status.rawValue : (machine?.status.rawValue ?? "unknown")
        let safeName = Self.redactedContextLabel(name)

        if isSourceHost {
            return "- hostID=\(Self.contextValue(hostID.rawValue)); name=\(safeName); platform=\(Self.contextValue(platform)); status=\(Self.contextValue(status)); route=same-host Codex App Server; currentSourceCanUse=true"
        }

        if supervisorStore.activeRelayEndpoint(for: hostID) != nil {
            let connected = supervisorStore.hasRelay(for: hostID)
            let currentSourceCanUse = sourceHostID == runtimeStore.localHost.id
                && (connected || machine?.status == .connected)
            let note = currentSourceCanUse
                ? "This is a mapofagents-managed route to the target host."
                : "This loopback endpoint is only reachable from the local mapofagents host, not from the current source host."
            return "- hostID=\(Self.contextValue(hostID.rawValue)); name=\(safeName); platform=\(Self.contextValue(platform)); status=\(Self.contextValue(status)); route=app-managed App Server WebSocket; endpointURL=redacted; reachableFromHostID=\(Self.contextValue(runtimeStore.localHost.id.rawValue)); currentSourceCanUse=\(currentSourceCanUse); note=\(Self.contextValue(note))"
        }

        if sourceHostID == runtimeStore.localHost.id,
           let remote = supervisorStore.codexRemote(for: hostID),
           remote.isConnectable {
            let identityPath = CodexRemoteIdentityStore.routeIdentityPath(for: remote) ?? "not-prepared"
            let currentSourceCanUse = identityPath != "not-prepared"
            let note = currentSourceCanUse
                ? "Use this SSH target to create a local loopback tunnel to the target host's Codex App Server."
                : "Use the Machines panel antenna once to prepare this remote's SSH key before creating a tunnel."
            return "- hostID=\(Self.contextValue(hostID.rawValue)); name=\(safeName); platform=\(Self.contextValue(platform)); status=\(Self.contextValue(status)); route=codex-remote SSH tunnel; sshFileAccess=\(currentSourceCanUse); sshTarget=redacted; sshPort=redacted; identityPath=redacted; remoteAppServerPorts=redacted; reachableFromHostID=\(Self.contextValue(runtimeStore.localHost.id.rawValue)); currentSourceCanUse=\(currentSourceCanUse); note=\(Self.contextValue(note))"
        }

        if isLocalHost {
            let currentSourceCanUse = sourceHostID == runtimeStore.localHost.id
            return "- hostID=\(Self.contextValue(hostID.rawValue)); name=\(safeName); platform=\(Self.contextValue(platform)); status=\(Self.contextValue(status)); route=local mapofagents Codex App Server; reachableFromHostID=\(Self.contextValue(runtimeStore.localHost.id.rawValue)); currentSourceCanUse=\(currentSourceCanUse); note=\"No remote-access route from the current source host is available in this workflow context.\""
        }

        return "- hostID=\(Self.contextValue(hostID.rawValue)); name=\(safeName); platform=\(Self.contextValue(platform)); status=\(Self.contextValue(status)); route=none; currentSourceCanUse=false; note=\"Reconnect this machine or configure a direct App Server or SSH tunnel route reachable from the current source host.\""
    }

    private func machineTitle(for hostID: HostID) -> String? {
        if hostID == runtimeStore.localHost.id {
            return runtimeStore.localHost.name
        }
        return supervisorStore.machines.first { $0.id == hostID }?.name
            ?? graphStore.graph.nodes.values.first {
                $0.kind == .machine && $0.metadata.hostID == hostID
            }?.title
    }

    private static func contextValue(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    private static func redactedContextLabel(_ value: String, fallback: String = "unknown") -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return contextValue(fallback)
        }
        guard !looksSensitiveForWorkflowContext(trimmed) else {
            return contextValue("redacted")
        }
        return contextValue(trimmed)
    }

    private static func looksSensitiveForWorkflowContext(_ value: String) -> Bool {
        let patterns = [
            #"^[A-Za-z][A-Za-z0-9+.-]*://"#,
            #"^[A-Za-z]:[\\/]"#,
            #"^~/"#,
            #"^/"#,
            #"^\\\\"#,
            #"(^|[\s(])/(Users|Volumes|private|tmp|var|opt|home|etc|mnt)/\S*"#,
            #"(^|[\s(])[A-Za-z]:[\\/]\S*"#,
            #"^[^\s@]+@[^\s@]+(:\d{1,5})?$"#,
            #"^([A-Za-z0-9.-]+|\d{1,3}(\.\d{1,3}){3}):\d{2,5}$"#,
        ]
        return patterns.contains { pattern in
            value.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func percentEncoded(_ value: String) -> String {
        let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? value
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

    private static func standardizePath(_ path: String) -> String {
        let slashNormalized = path.replacingOccurrences(of: "\\", with: "/")
        if slashNormalized.range(of: #"^[A-Za-z]:"#, options: .regularExpression) != nil {
            return slashNormalized.lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return NSString(string: slashNormalized).standardizingPath
    }
}

private struct WorkflowThreadMentionContext {
    var nodeID: NodeID
    var title: String
    var threadRef: ThreadRef
    var model: String?
    var reasoningEffort: String?
}

private struct WorkflowFolderMentionContext {
    var nodeID: NodeID
    var title: String
    var hostID: HostID
    var platform: HostPlatform
    var folderPath: String
    var machineTitle: String?
}

#if os(iOS)
private struct FullScreenThreadPopoverLayer: View {
    var node: CanvasNode
    @Bindable var runtimeStore: CodexRuntimeStore
    var transcript: ThreadTranscript?
    var liveAssistantText: String
    var liveStateSummary: ThreadLiveStateSummary?
    var isLoading: Bool
    var isLoadingOlder: Bool
    var loadPhase: TranscriptLoadPhase
    var isAwaitingResponse: Bool
    var canStopTurn: Bool
    var isStoppingTurn: Bool
    var errorMessage: String?
    var threadMentionCandidates: [MentionCandidate]
    var attentionRequests: [RuntimeAttentionRequest]
    var onRename: (String) -> Void
    var onRefresh: () -> Void
    var onLoadOlder: () -> Void
    var onUseCachedTranscript: () -> Void
    var onSend: (String, [ChatInputAttachment]) async -> Bool
    var onStopTurn: () -> Void
    var onFocusAttention: (RuntimeAttentionRequest) -> Void
    var onRespondToAttention: (RuntimeAttentionRequest, Bool) -> Void
    var onRespondToAttentionWithText: (RuntimeAttentionRequest, String) -> Void
    var onDeclineTypedAttention: (RuntimeAttentionRequest) -> Void
    var onClose: () -> Void

    var body: some View {
        ThreadPopoverView(
            node: node,
            runtimeStore: runtimeStore,
            transcript: transcript,
            liveAssistantText: liveAssistantText,
            liveStateSummary: liveStateSummary,
            isLoading: isLoading,
            isLoadingOlder: isLoadingOlder,
            loadPhase: loadPhase,
            isAwaitingResponse: isAwaitingResponse,
            errorMessage: errorMessage,
            threadMentionCandidates: threadMentionCandidates,
            attentionRequests: attentionRequests,
            isFullScreen: true,
            allowsMoving: false,
            canStopTurn: canStopTurn,
            isStoppingTurn: isStoppingTurn,
            onRename: onRename,
            onStopTurn: onStopTurn,
            onRefresh: onRefresh,
            onLoadOlder: onLoadOlder,
            onUseCachedTranscript: onUseCachedTranscript,
            onSend: onSend,
            onFocusAttention: onFocusAttention,
            onRespondToAttention: onRespondToAttention,
            onRespondToAttentionWithText: onRespondToAttentionWithText,
            onDeclineTypedAttention: onDeclineTypedAttention,
            onClose: onClose
        )
        .id(node.metadata.threadRef?.qualifiedID ?? node.id.rawValue)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif

private struct DraggableThreadPopoverLayer: View {
    var node: CanvasNode
    @Bindable var runtimeStore: CodexRuntimeStore
    var transcript: ThreadTranscript?
    var liveAssistantText: String
    var liveStateSummary: ThreadLiveStateSummary?
    var isLoading: Bool
    var isLoadingOlder: Bool
    var loadPhase: TranscriptLoadPhase
    var isAwaitingResponse: Bool
    var canStopTurn: Bool
    var isStoppingTurn: Bool
    var errorMessage: String?
    var threadMentionCandidates: [MentionCandidate]
    var attentionRequests: [RuntimeAttentionRequest]
    var popoverSize: CGSize
    var basePosition: CGPoint
    var canvasSize: CGSize
    var rightInset: CGFloat
    var onRename: (String) -> Void
    var onCommitOffset: (CanvasPoint) -> Void
    var onRefresh: () -> Void
    var onLoadOlder: () -> Void
    var onUseCachedTranscript: () -> Void
    var onSend: (String, [ChatInputAttachment]) async -> Bool
    var onStopTurn: () -> Void
    var onFocusAttention: (RuntimeAttentionRequest) -> Void
    var onRespondToAttention: (RuntimeAttentionRequest, Bool) -> Void
    var onRespondToAttentionWithText: (RuntimeAttentionRequest, String) -> Void
    var onDeclineTypedAttention: (RuntimeAttentionRequest) -> Void
    var onClose: () -> Void

    @State private var dragOffset: CGSize = .zero

    var body: some View {
        ThreadPopoverView(
            node: node,
            runtimeStore: runtimeStore,
            transcript: transcript,
            liveAssistantText: liveAssistantText,
            liveStateSummary: liveStateSummary,
            isLoading: isLoading,
            isLoadingOlder: isLoadingOlder,
            loadPhase: loadPhase,
            isAwaitingResponse: isAwaitingResponse,
            errorMessage: errorMessage,
            threadMentionCandidates: threadMentionCandidates,
            attentionRequests: attentionRequests,
            isMoving: dragOffset != .zero,
            allowsMoving: true,
            canStopTurn: canStopTurn,
            isStoppingTurn: isStoppingTurn,
            onRename: onRename,
            onMoveChanged: { translation in
                guard shouldApply(translation) else { return }
                dragOffset = translation
            },
            onMoveEnded: { translation in
                let savedOffset = node.metadata.popoverOffset?.cgSize ?? .zero
                let committedPosition = clampedThreadPopoverPosition(
                    basePosition: basePosition,
                    savedOffset: savedOffset,
                    dragOffset: translation,
                    popoverSize: popoverSize,
                    canvasSize: canvasSize,
                    rightInset: rightInset
                )
                dragOffset = .zero
                onCommitOffset(
                    CanvasPoint(
                        x: committedPosition.x - basePosition.x,
                        y: committedPosition.y - basePosition.y
                    )
                )
            },
            onStopTurn: onStopTurn,
            onRefresh: onRefresh,
            onLoadOlder: onLoadOlder,
            onUseCachedTranscript: onUseCachedTranscript,
            onSend: onSend,
            onFocusAttention: onFocusAttention,
            onRespondToAttention: onRespondToAttention,
            onRespondToAttentionWithText: onRespondToAttentionWithText,
            onDeclineTypedAttention: onDeclineTypedAttention,
            onClose: onClose
        )
        .id(node.metadata.threadRef?.qualifiedID ?? node.id.rawValue)
        .frame(width: popoverSize.width, height: popoverSize.height)
        .position(currentPosition)
        .transaction { transaction in
            transaction.animation = nil
        }
        .onChange(of: node.id) { _, _ in
            dragOffset = .zero
        }
    }

    private var currentPosition: CGPoint {
        let savedOffset = node.metadata.popoverOffset?.cgSize ?? .zero
        return clampedThreadPopoverPosition(
            basePosition: basePosition,
            savedOffset: savedOffset,
            dragOffset: dragOffset,
            popoverSize: popoverSize,
            canvasSize: canvasSize,
            rightInset: rightInset
        )
    }

    private func shouldApply(_ translation: CGSize) -> Bool {
        abs(translation.width - dragOffset.width) >= 0.5
            || abs(translation.height - dragOffset.height) >= 0.5
    }
}

private func clampedThreadPopoverPosition(
    basePosition: CGPoint,
    savedOffset: CGSize,
    dragOffset: CGSize,
    popoverSize: CGSize,
    canvasSize: CGSize,
    rightInset: CGFloat,
    margin: CGFloat = 24
) -> CGPoint {
    let desired = CGPoint(
        x: basePosition.x + savedOffset.width + dragOffset.width,
        y: basePosition.y + savedOffset.height + dragOffset.height
    )
    let effectiveWidth = max(popoverSize.width + margin * 2, canvasSize.width - rightInset)
    let minX = popoverSize.width / 2 + margin
    let maxX = max(minX, effectiveWidth - popoverSize.width / 2 - margin)
    let minY = popoverSize.height / 2 + margin
    let maxY = max(minY, canvasSize.height - popoverSize.height / 2 - margin)

    return CGPoint(
        x: min(max(desired.x, minX), maxX),
        y: min(max(desired.y, minY), maxY)
    )
}

private struct EdgeNotePopoverView: View {
    var edge: CanvasEdge
    var routes: [MessageRoute]
    var onSave: (String) -> Void
    var onDelete: () -> Void
    var onClose: () -> Void

    @State private var draftLabel = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: edge.kind == .threadMessage ? "paperplane" : "line.diagonal")
                    .foregroundStyle(.green)
                    .frame(width: 22, height: 22)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                Text(edge.kind == .threadMessage ? "Message Line" : "Workflow Note")
                    .font(.headline)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Close")
                .accessibilityLabel("Close line editor")
            }

            TextField("Label", text: $draftLabel)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onSave(draftLabel) }

            if !routes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent deliveries")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(Array(routes.prefix(4))) { route in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(color(for: route.deliveryState))
                                    .frame(width: 6, height: 6)
                                Text(route.deliveryState.rawValue.capitalized)
                                    .font(.caption2.weight(.semibold))
                                Spacer()
                                Text(route.timestamp, format: .dateTime.hour().minute().second())
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }

                            if !route.snippet.isEmpty {
                                Text(route.snippet)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(7)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            HStack {
                Button {
                    onSave(draftLabel)
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .padding(12)
        .frame(width: 280, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 6)
        .onAppear {
            draftLabel = edge.label ?? ""
        }
        .onChange(of: edge.id) { _, _ in
            draftLabel = edge.label ?? ""
        }
    }

    private func color(for state: MessageRouteDeliveryState) -> Color {
        switch state {
        case .pending:
            return .blue
        case .delivered:
            return .green
        case .failed:
            return .red
        case .unknown:
            return .secondary
        }
    }
}

private extension WorkflowNotificationPreferences {
    func shouldNotify(for kind: WorkflowEventKind) -> Bool {
        switch kind {
        case .turnStarted:
            return false
        case .threadCreated, .folderCreated:
            return false
        case .turnCompleted:
            return notifyOnCompleted
        case .needsInput:
            return notifyOnNeedsInput
        case .failed:
            return notifyOnFailed
        }
    }
}

private extension CanvasPoint {
    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }

    var cgSize: CGSize {
        CGSize(width: x, height: y)
    }
}
