#if os(iOS)
import MapofAgentsCore
import MapofAgentsUI
import SwiftUI

private enum IPhoneSheet: String, Identifiable {
    case machines
    case activity
    case threads

    var id: String { rawValue }
}

struct IPhoneRootView: View {
    private let repository: LocalControlRoomStore

    @State private var graphStore: GraphStore
    @State private var runtimeStore: CodexRuntimeStore
    @State private var supervisorStore: WorkflowSupervisorStore
    @State private var threadCatalogStore = ThreadCatalogStore()
    @State private var workflowLibrary: WorkflowLibraryCoordinator
    @State private var workflowMemberships: [String: [ThreadWorkflowMembership]] = [:]
    @State private var threadCreation = ThreadCreationCoordinator()
    @State private var pairingCoordinator = IPhonePairingCoordinator()
    @State private var activeSheet: IPhoneSheet?
    @State private var isShowingNewThread = false
    @State private var isRefreshingWorkflowConnections = false
    @State private var errorMessage: String?
    @State private var bootstrapErrorMessage: String?
    @AppStorage("workflow.notify.completed") private var notifyOnCompleted = false
    @AppStorage("workflow.notify.needsInput") private var notifyOnNeedsInput = true
    @AppStorage("workflow.notify.failed") private var notifyOnFailed = true

    init() {
        let paths: ApplicationPaths
        let bootstrapErrorMessage: String?
        do {
            paths = try ApplicationPaths.defaultPaths()
            bootstrapErrorMessage = nil
        } catch {
            paths = ApplicationPaths(applicationSupportDirectory: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(ApplicationPaths.supportDirectoryName, isDirectory: true))
            bootstrapErrorMessage = "Using temporary app storage because the normal Application Support folder could not be prepared: \(error.localizedDescription)"
        }
        let repository = LocalControlRoomStore(paths: paths)
        self.repository = repository
        _graphStore = State(initialValue: GraphStore(repository: repository))
        _runtimeStore = State(initialValue: CodexRuntimeStore())
        _supervisorStore = State(initialValue: WorkflowSupervisorStore())
        _workflowLibrary = State(initialValue: WorkflowLibraryCoordinator(repository: repository))
        _bootstrapErrorMessage = State(initialValue: bootstrapErrorMessage)
    }

    var body: some View {
        ZStack {
            GraphCanvasView(
                graphStore: graphStore,
                runtimeStore: runtimeStore,
                supervisorStore: supervisorStore,
                threadCatalogStore: threadCatalogStore,
                workflowEvents: mergedWorkflowEvents,
                activeWorkflowID: workflowLibrary.activeWorkflowID,
                activeWorkflowName: workflowLibrary.activeWorkflowName,
                workflowMemberships: workflowMemberships,
                notificationPreferences: notificationPreferencesBinding,
                onPickLocalMachineFolder: { _ in },
                mentionCandidatesForThread: mentionCandidates(for:),
                onThreadMentionCatalogNeeded: refreshMentionCatalog(for:),
                showsDesktopRails: false,
                showsStatusStrip: false
            )
            .ignoresSafeArea(.container, edges: isThreadChatPresented ? [] : .all)

            VStack(spacing: 0) {
                if !isThreadChatPresented {
                    topBar
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }

                Spacer()

                if !isThreadChatPresented {
                    bottomDock
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
            }
        }
        .background(Color.black)
        .overlay(alignment: .top) {
            if !isThreadChatPresented {
                VStack(spacing: 8) {
                    if let message = visibleErrorMessage {
                        Text(message)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                    }

                    if let syncMessage = pairingCoordinator.syncMessage {
                        Text(syncMessage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                    }
                }
                .padding(.top, 62)
                .allowsHitTesting(false)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .machines:
                IPhoneMachinesSheet(
                    supervisorStore: supervisorStore,
                    machines: supervisorStore.machines,
                    pairedHost: pairingCoordinator.pairedHost,
                    activeEndpoint: pairingCoordinator.pairedHost.flatMap { supervisorStore.activeRelayEndpoint(for: $0.id) },
                    isConnectingPairedHost: pairingCoordinator.isConnectingPairedHost,
                    onConnect: connectRemote,
                    onPair: connectPairingCode,
                    onReconnectPairedHost: reconnectPairedHost,
                    onForgetPairing: forgetPairing,
                    onLoadWorkflow: loadWorkflowFromMachine,
                    onAddFolder: addRemoteFolder,
                    onDisconnect: disconnect
                )
                .presentationDetents([.medium, .large])
            case .activity:
                IPhoneActivitySheet(
                    events: supervisorStore.workflowEvents,
                    attentionRequests: runtimeStore.pendingAttentionRequests + supervisorStore.pendingAttentionRequests,
                    machines: supervisorStore.machines,
                    diagnostics: supervisorStore.codexRemoteDiagnostics,
                    relayAttempts: supervisorStore.relayEndpointAttempts,
                    preferences: notificationPreferencesBinding,
                    titleForThread: titleForThread,
                    onRespondToAttention: { request, allow in
                        Task { await respondToAttentionRequest(request, allow: allow) }
                    },
                    onRespondToAttentionWithText: { request, text in
                        Task { await respondToAttentionRequest(request, text: text) }
                    },
                    onDeclineTypedAttention: { request in
                        Task { await declineTypedAttentionRequest(request) }
                    },
                    onSelect: focusThread
                )
                .presentationDetents([.medium, .large])
            case .threads:
                IPhoneThreadNavigatorSheet(
                    threads: threadNavigatorItems,
                    events: supervisorStore.workflowEvents,
                    machines: supervisorStore.machines,
                    onSelect: focusThread
                )
                .presentationDetents([.medium, .large])
            }
        }
        .fullScreenCover(isPresented: $isShowingNewThread) {
            NewThreadPopoverView(
                graphStore: graphStore,
                runtimeStore: runtimeStore,
                isFolderAvailable: isFolderAvailable,
                modelOptionsForFolder: modelOptions(for:),
                mentionCandidatesForFolder: mentionCandidates(for:),
                onSelectedFolderChanged: refreshThreadFormCatalog(for:),
                onCreate: createThread,
                onCancel: { isShowingNewThread = false },
                isFullScreen: true,
                catalogRevision: threadCreation.catalogRevision
            )
        }
        .alert(
            workflowLibrary.editorMode?.title ?? "Workflow",
            isPresented: Binding(
                get: { workflowLibrary.editorMode != nil },
                set: { isPresented in
                    if !isPresented {
                        workflowLibrary.editorMode = nil
                    }
                }
            )
        ) {
            TextField(
                "Workflow name",
                text: Binding(
                    get: { workflowLibrary.nameDraft },
                    set: { workflowLibrary.nameDraft = $0 }
                )
            )
            Button(workflowLibrary.editorMode?.actionTitle ?? "Save", action: submitWorkflowName)
            Button("Cancel", role: .cancel) {
                workflowLibrary.editorMode = nil
            }
        }
        .confirmationDialog(
            "Delete Workflow",
            isPresented: Binding(
                get: { workflowLibrary.workflowToDelete != nil },
                set: { isPresented in
                    if !isPresented {
                        workflowLibrary.workflowToDelete = nil
                    }
                }
            ),
            presenting: workflowLibrary.workflowToDelete
        ) { workflow in
            Button("Delete Saved Layout \(workflow.name)", role: .destructive) {
                deleteWorkflow(workflow)
            }
            Button("Cancel", role: .cancel) {
                workflowLibrary.workflowToDelete = nil
            }
        } message: { workflow in
            Text("This permanently removes the saved workflow layout for \(workflow.name). Codex threads on connected machines are not deleted.")
        }
        .confirmationDialog(
            "Approve Pairing Import",
            isPresented: Binding(
                get: { pairingCoordinator.pendingPairingApproval != nil },
                set: { isPresented in
                    if !isPresented {
                        pairingCoordinator.cancelPendingPairingApproval()
                    }
                }
            ),
            presenting: pairingCoordinator.pendingPairingApproval
        ) { pending in
            Button("Connect to \(pending.title)") {
                pairingCoordinator.approvePendingPairingURL(
                    graphStore: graphStore,
                    supervisorStore: supervisorStore,
                    syncWorkflowFromMac: syncWorkflowFromMac
                )
            }
            Button("Cancel", role: .cancel) {
                pairingCoordinator.cancelPendingPairingApproval()
            }
        } message: { pending in
            Text("This pairing link will connect this iPhone to \(pending.title) and save it only after a successful connection.\n\nEndpoints:\n\(pending.endpointSummary)")
        }
        .task {
            await bootstrapRemoteControl()
        }
        .onOpenURL { url in
            pairingCoordinator.preparePairingURL(url)
        }
        .onChange(of: graphStore.graph) { _, _ in
            Task {
                await supervisorStore.updateWorkflowThreads(graphStore.workflowThreadRefs)
            }
        }
        .onChange(of: supervisorStore.machines) { _, machines in
            Task {
                await graphStore.applySupervisorMachines(machines)
            }
        }
        .onChange(of: supervisorStore.workflowEvents) { _, events in
            Task {
                do {
                    try await repository.saveWorkflowEvents(events)
                } catch {
                    errorMessage = "Could not save workflow activity: \(error.localizedDescription)"
                }
            }
        }
        .onChange(of: supervisorStore.relayEndpoints) { _, endpoints in
            Task {
                do {
                    try await repository.saveRelayEndpoints(endpoints)
                } catch {
                    errorMessage = "Could not save relay routes: \(error.localizedDescription)"
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            workflowMenu

            Spacer(minLength: 8)

            Text(statusSummary)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            FeedbackButton(
                unavailableReason: newThreadUnavailableReason,
                action: {
                    isShowingNewThread = true
                }
            ) {
                Image(systemName: "plus.bubble")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.borderedProminent)
            .help(newThreadUnavailableReason ?? "Create Codex thread")
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var bottomDock: some View {
        HStack(spacing: 8) {
            dockButton("Machines", systemImage: "server.rack") {
                activeSheet = .machines
            }

            dockButton("Threads", systemImage: "list.bullet.rectangle") {
                activeSheet = .threads
            }

            dockButton("Activity", systemImage: "waveform.path.ecg") {
                activeSheet = .activity
            }

            Divider()
                .frame(height: 24)

            iconButton("Arrange", systemImage: "rectangle.3.group") {
                Task { await graphStore.autoArrange() }
            }

            iconButton("Zoom out", systemImage: "minus.magnifyingglass") {
                Task { await graphStore.zoomViewport(by: 0.86) }
            }

            iconButton("Zoom in", systemImage: "plus.magnifyingglass") {
                Task { await graphStore.zoomViewport(by: 1.16) }
            }

            FeedbackButton(
                unavailableReason: isRefreshingWorkflowConnections ? "Connection refresh is already running." : nil,
                action: refreshWorkflowConnections
            ) {
                Image(systemName: isRefreshingWorkflowConnections ? "arrow.triangle.2.circlepath" : "antenna.radiowaves.left.and.right")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh connections")
        }
        .font(.caption.weight(.semibold))
        .padding(8)
        .background(.regularMaterial, in: Capsule())
    }

    private var workflowMenu: some View {
        Menu {
            if workflowLibrary.workflows.isEmpty {
                Text("No Workflows")
            } else {
                Section("Workflows") {
                    ForEach(workflowLibrary.workflows) { workflow in
                        Button {
                            selectWorkflow(workflow.id)
                        } label: {
                            Label(workflow.name, systemImage: workflow.id == workflowLibrary.activeWorkflowID ? "checkmark" : "circle")
                        }
                    }
                }
            }

            Divider()

            Button {
                beginCreateWorkflow()
            } label: {
                Label("New Workflow", systemImage: "plus")
            }

            Button {
                if workflowLibrary.activeWorkflowID == nil {
                    pairingCoordinator.syncMessage = "Create or select a workflow before renaming it."
                } else {
                    beginRenameWorkflow()
                }
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button {
                beginDuplicateWorkflow()
            } label: {
                Label("Save Copy", systemImage: "doc.on.doc")
            }

            Button(role: .destructive) {
                if workflowLibrary.activeWorkflowID == nil {
                    pairingCoordinator.syncMessage = "Create or select a workflow before deleting it."
                } else if workflowLibrary.workflows.count <= 1 {
                    pairingCoordinator.syncMessage = "Keep at least one workflow."
                } else {
                    beginDeleteActiveWorkflow()
                }
            } label: {
                Label("Delete Workflow", systemImage: "trash")
            }
        } label: {
            Label(workflowLibrary.activeWorkflowName, systemImage: "rectangle.3.group")
                .font(.headline)
                .lineLimit(1)
        }
    }

    private var notificationPreferencesBinding: Binding<WorkflowNotificationPreferences> {
        Binding(
            get: {
                WorkflowNotificationPreferences(
                    notifyOnCompleted: notifyOnCompleted,
                    notifyOnNeedsInput: notifyOnNeedsInput,
                    notifyOnFailed: notifyOnFailed
                )
            },
            set: { preferences in
                notifyOnCompleted = preferences.notifyOnCompleted
                notifyOnNeedsInput = preferences.notifyOnNeedsInput
                notifyOnFailed = preferences.notifyOnFailed
            }
        )
    }

    private var mergedWorkflowEvents: [WorkflowEvent] {
        (runtimeStore.workflowEvents + supervisorStore.workflowEvents)
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var visibleErrorMessage: String? {
        errorMessage
            ?? pairingCoordinator.errorMessage
            ?? workflowLibrary.errorMessage
            ?? threadCreation.errorMessage
            ?? bootstrapErrorMessage
    }

    private var statusSummary: String {
        let connected = supervisorStore.machines.filter { $0.status == .connected }.count
        return "\(connected) online - \(graphStore.graph.nodes.count) nodes"
    }

    private var hasAvailableThreadTarget: Bool {
        graphStore.graph.sortedNodes.contains { node in
            (node.kind == .folder || node.kind == .machine) && isFolderAvailable(node)
        }
    }

    private var newThreadUnavailableReason: String? {
        if hasAvailableThreadTarget {
            return nil
        }

        let hasThreadTarget = graphStore.graph.sortedNodes.contains { $0.kind == .folder || $0.kind == .machine }
        if hasThreadTarget {
            return "Connect a machine on this workflow before creating a thread."
        }

        return "Pair or connect a machine before creating a thread."
    }

    private var isThreadChatPresented: Bool {
        graphStore.selectedNode?.kind == .codexThread
    }

    private var threadNavigatorItems: [CanvasNode] {
        graphStore.graph.sortedNodes.filter { $0.kind == .codexThread }
    }

    private func dockButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func iconButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func bootstrapRemoteControl() async {
        supervisorStore.start()
        pairingCoordinator.loadStoredPairedHost()
        await workflowLibrary.refreshState()
        await graphStore.load()
        await refreshWorkflowMemberships()
        await workflowLibrary.refreshState()
        await supervisorStore.updateWorkflowThreads(graphStore.workflowThreadRefs)

        do {
            let events = try await repository.loadWorkflowEvents()
            await supervisorStore.restoreWorkflowEvents(events)
        } catch {
            errorMessage = "Could not restore workflow activity: \(error.localizedDescription)"
        }

        do {
            let endpoints = try await repository.loadRelayEndpoints()
            await supervisorStore.restoreRelayEndpoints(endpoints)
            do {
                try await repository.saveRelayEndpoints(supervisorStore.relayEndpoints)
            } catch {
                errorMessage = "Could not save relay routes: \(error.localizedDescription)"
            }
        } catch {
            errorMessage = "Could not restore relay routes: \(error.localizedDescription)"
        }

        await supervisorStore.updateWorkflowThreads(graphStore.workflowThreadRefs)
        await supervisorStore.refreshConnections(for: workflowMapHostIDs)
        await graphStore.applySupervisorMachines(supervisorStore.machines)
        await supervisorStore.updateWorkflowThreads(graphStore.workflowThreadRefs)
        await pairingCoordinator.connectLaunchConfiguredRemoteIfNeeded(
            graphStore: graphStore,
            supervisorStore: supervisorStore,
            syncWorkflowFromMac: syncWorkflowFromMac
        )
    }

    private func loadActiveWorkflow() async {
        await workflowLibrary.refreshState()
        await graphStore.load()
        await refreshWorkflowMemberships()
        await supervisorStore.updateWorkflowThreads(graphStore.workflowThreadRefs)
        await graphStore.applySupervisorMachines(supervisorStore.machines)
        refreshWorkflowConnections()
    }

    private func refreshWorkflowMemberships() async {
        do {
            let snapshot = try await repository.loadWorkflowSnapshot()
            workflowMemberships = ThreadWorkflowMembership.map(
                workflows: snapshot.library.workflows,
                graphsByWorkflowID: snapshot.graphsByWorkflowID,
                activeWorkflowID: workflowLibrary.activeWorkflowID ?? snapshot.library.activeWorkflowID
            )
        } catch {
            workflowMemberships = [:]
            errorMessage = "Could not refresh workflow memberships: \(error.localizedDescription)"
        }
    }

    private func beginCreateWorkflow() {
        workflowLibrary.beginCreateWorkflow()
    }

    private func beginDuplicateWorkflow() {
        workflowLibrary.beginDuplicateWorkflow()
    }

    private func beginRenameWorkflow() {
        workflowLibrary.beginRenameWorkflow()
    }

    private func beginDeleteActiveWorkflow() {
        workflowLibrary.beginDeleteActiveWorkflow()
    }

    private func submitWorkflowName() {
        Task {
            if await workflowLibrary.submitWorkflowName() {
                await loadActiveWorkflow()
            }
        }
    }

    private func selectWorkflow(_ workflowID: String) {
        Task {
            if await workflowLibrary.selectWorkflow(workflowID) {
                await loadActiveWorkflow()
            }
        }
    }

    private func deleteWorkflow(_ workflow: WorkflowRecord) {
        Task {
            if await workflowLibrary.deleteWorkflow(workflow) {
                await loadActiveWorkflow()
            }
        }
    }

    private func connectRemote(name: String, endpoint: String, bearerToken: String?) {
        pairingCoordinator.connectRemote(
            name: name,
            endpoint: endpoint,
            bearerToken: bearerToken,
            graphStore: graphStore,
            supervisorStore: supervisorStore,
            syncWorkflowFromMac: syncWorkflowFromMac
        )
    }

    private func loadWorkflowFromMachine(_ machine: SupervisorMachine) {
        Task {
            await syncWorkflowFromMac(
                hostID: machine.id,
                pairedHost: machine.id == pairingCoordinator.pairedHost?.id ? pairingCoordinator.pairedHost : nil
            )
        }
    }

    private func connectPairingCode(_ code: String) {
        pairingCoordinator.connectPairingCode(
            code,
            graphStore: graphStore,
            supervisorStore: supervisorStore,
            syncWorkflowFromMac: syncWorkflowFromMac
        )
    }

    @discardableResult
    private func syncWorkflowFromMac(hostID: HostID, pairedHost: MapofAgentsPairedHost? = nil) async -> Bool {
        let machine = supervisorStore.machines.first { $0.id == hostID }
        pairingCoordinator.syncMessage = "Loading layout from \(machine?.name ?? "Mac")..."

        do {
            let snapshot = try await supervisorStore
                .loadMapofAgentsWorkflowSnapshot(
                    from: hostID,
                    pairedHost: pairedHost,
                    includeRelayEndpoints: false
                )
                .replacingLocalHost(with: hostID, machineName: machine?.name)
            try await repository.replaceWorkflowSnapshot(snapshot)

            await supervisorStore.restoreWorkflowEvents(snapshot.workflowEvents)
            await loadActiveWorkflow()

            pairingCoordinator.syncMessage = "Loaded \(snapshot.library.workflows.count) workflows from \(machine?.name ?? "Mac")."
            pairingCoordinator.errorMessage = nil
            errorMessage = nil
            return true
        } catch {
            pairingCoordinator.syncMessage = nil
            pairingCoordinator.errorMessage = "Could not load Mac layout: \(error.localizedDescription)"
            return false
        }
    }

    private func reconnectPairedHost() {
        pairingCoordinator.reconnectPairedHost(
            graphStore: graphStore,
            supervisorStore: supervisorStore,
            syncWorkflowFromMac: syncWorkflowFromMac
        )
    }

    private func forgetPairing() {
        pairingCoordinator.forgetPairing(disconnect: disconnect)
    }

    private func disconnect(_ machineID: HostID) {
        Task {
            await supervisorStore.disconnect(machineID)
            await graphStore.applySupervisorMachines(supervisorStore.machines)
        }
    }

    private func addRemoteFolder(machine: SupervisorMachine, path: String) {
        Task {
            await graphStore.addFolder(path: path, hostID: machine.id, platform: machine.platform)
        }
    }

    private func refreshWorkflowConnections() {
        guard !isRefreshingWorkflowConnections else { return }

        isRefreshingWorkflowConnections = true
        let pairedHost = pairingCoordinator.pairedHost
        let hostIDs = workflowMapHostIDs.filter { $0 != pairedHost?.id }

        Task {
            if pairedHost != nil {
                await pairingCoordinator.refreshPairedConnectionIfNeeded(
                    graphStore: graphStore,
                    supervisorStore: supervisorStore
                )
            }
            await supervisorStore.refreshConnections(for: hostIDs)
            await graphStore.applySupervisorMachines(supervisorStore.machines)
            await supervisorStore.updateWorkflowThreads(graphStore.workflowThreadRefs)
            isRefreshingWorkflowConnections = false
        }
    }

    private func modelOptions(for folder: CanvasNode?) -> [CodexModelOption]? {
        threadCreation.modelOptions(for: folder, localHostID: runtimeStore.localHost.id)
    }

    private func mentionCandidates(for folder: CanvasNode?) -> [MentionCandidate] {
        threadCreation.mentionCandidates(for: folder, localHostID: runtimeStore.localHost.id)
    }

    private func mentionCandidates(for threadRef: ThreadRef?) -> [MentionCandidate] {
        threadCreation.mentionCandidates(for: threadRef, localHostID: runtimeStore.localHost.id)
    }

    private func refreshThreadFormCatalog(for folder: CanvasNode?) {
        threadCreation.refreshThreadFormCatalog(
            for: folder,
            localHostID: runtimeStore.localHost.id,
            supervisorStore: supervisorStore
        )
    }

    private func refreshMentionCatalog(for threadRef: ThreadRef?) {
        threadCreation.refreshMentionCatalog(
            for: threadRef,
            localHostID: runtimeStore.localHost.id,
            supervisorStore: supervisorStore
        )
    }

    private var workflowMapHostIDs: Set<HostID> {
        threadCreation.workflowMapHostIDs(in: graphStore.graph, excludingLocalHostID: runtimeStore.localHost.id)
    }

    private func createThread(_ request: NewThreadRequest) async -> Bool {
        let didCreate = await threadCreation.createThread(
            request,
            graphStore: graphStore,
            runtimeStore: runtimeStore,
            supervisorStore: supervisorStore,
            allowsLocalRuntime: false,
            localDefaultDirectory: "/",
            localRuntimeUnavailableMessage: "iPhone creates Codex threads on connected machines, not locally."
        )

        if didCreate {
            isShowingNewThread = false
            errorMessage = nil
        }

        return didCreate
    }

    private func isFolderAvailable(_ target: CanvasNode) -> Bool {
        threadCreation.isTargetAvailable(
            target,
            localHostID: runtimeStore.localHost.id,
            localConnectionState: runtimeStore.connectionState,
            supervisorStore: supervisorStore,
            allowsLocalRuntime: false
        )
    }

    private func titleForThread(_ event: WorkflowEvent) -> String {
        guard let threadID = event.threadID else { return "Codex thread" }
        return graphStore.graph.nodes.values.first {
            $0.metadata.threadRef?.matches(hostID: event.hostID, threadID: threadID) == true
        }?.title
            ?? "Codex thread"
    }

    private func focusThread(_ event: WorkflowEvent) {
        guard let threadID = event.threadID else { return }
        graphStore.selectThread(hostID: event.hostID, threadID: threadID)
        activeSheet = nil
    }

    private func focusThread(_ node: CanvasNode) {
        graphStore.selectNode(node.id)
        activeSheet = nil
    }

    private func respondToAttentionRequest(_ request: RuntimeAttentionRequest, allow: Bool) async {
        do {
            if request.hostID == runtimeStore.localHost.id || request.hostID == nil {
                try await runtimeStore.respondToAttentionRequest(request, allow: allow)
            } else {
                try await supervisorStore.respondToAttentionRequest(request, allow: allow)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func respondToAttentionRequest(_ request: RuntimeAttentionRequest, text: String) async {
        do {
            if request.hostID == runtimeStore.localHost.id || request.hostID == nil {
                try await runtimeStore.respondToAttentionRequest(request, text: text)
            } else {
                try await supervisorStore.respondToAttentionRequest(request, text: text)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func declineTypedAttentionRequest(_ request: RuntimeAttentionRequest) async {
        do {
            if request.hostID == runtimeStore.localHost.id || request.hostID == nil {
                try await runtimeStore.declineTypedAttentionRequest(request)
            } else {
                try await supervisorStore.declineTypedAttentionRequest(request)
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct IPhoneMachinesSheet: View {
    private enum PendingDestructiveAction: Identifiable {
        case forgetPairing(MapofAgentsPairedHost)
        case loadWorkflow(SupervisorMachine)
        case removeMachine(SupervisorMachine)

        var id: String {
            switch self {
            case .forgetPairing(let host):
                return "forget-\(host.id.rawValue)"
            case .loadWorkflow(let machine):
                return "load-workflow-\(machine.id.rawValue)"
            case .removeMachine(let machine):
                return "remove-\(machine.id.rawValue)"
            }
        }

        var title: String {
            switch self {
            case .forgetPairing:
                return "Forget Paired Mac?"
            case .loadWorkflow:
                return "Load Mac Layout?"
            case .removeMachine:
                return "Remove Machine?"
            }
        }

        var buttonTitle: String {
            switch self {
            case .forgetPairing(let host):
                return "Forget \(host.name)"
            case .loadWorkflow:
                return "Replace iPhone Layouts"
            case .removeMachine(let machine):
                return "Remove \(machine.name)"
            }
        }

        var message: String {
            switch self {
            case .forgetPairing(let host):
                return "This removes the saved pairing for \(host.name) from this iPhone. You will need a new pairing code from the Mac to sync workflows again."
            case .loadWorkflow(let machine):
                return "This replaces the workflow library and saved layouts on this iPhone with the current snapshot from \(machine.name). Local iPhone-only layouts are not backed up by this import."
            case .removeMachine(let machine):
                return "This removes the saved route for \(machine.name). Existing workflow nodes stay on the map and can be reconnected later."
            }
        }
    }

    @Bindable var supervisorStore: WorkflowSupervisorStore
    var machines: [SupervisorMachine]
    var pairedHost: MapofAgentsPairedHost?
    var activeEndpoint: AppServerRelayEndpoint?
    var isConnectingPairedHost: Bool
    var onConnect: (String, String, String?) -> Void
    var onPair: (String) -> Void
    var onReconnectPairedHost: () -> Void
    var onForgetPairing: () -> Void
    var onLoadWorkflow: (SupervisorMachine) -> Void
    var onAddFolder: (SupervisorMachine, String) -> Void
    var onDisconnect: (HostID) -> Void

    @State private var remoteName = "mac-host.lan"
    @State private var remoteEndpoint = "ws://mac-host.lan:18945"
    @State private var remoteToken = ""
    @State private var pairingCode = ""
    @State private var folderPaths: [HostID: String] = [:]
    @State private var isCodexRemotesExpanded = true
    @State private var isTailnetExpanded = true
    @State private var pendingDestructiveAction: PendingDestructiveAction?

    var body: some View {
        NavigationStack {
            List {
                if let pairedHost {
                    Section("Paired Mac") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Image(systemName: "macbook")
                                    .foregroundStyle(statusColor(for: pairedHost))
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pairedHost.name)
                                        .font(.headline)
                                    Text(activeEndpointText(for: pairedHost))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                Spacer()

                                Text(statusText(for: pairedHost))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(statusColor(for: pairedHost))
                            }

                            if let endpoint = selectedEndpoint(for: pairedHost) {
                                LabeledContent("Endpoint", value: endpoint.url.absoluteString)
                                LabeledContent("Kind", value: endpoint.kind.rawValue.capitalized)
                            }

                            if let lastConnectedAt = pairedHost.lastConnectedAt {
                                HStack {
                                    Text("Last connected")
                                    Spacer()
                                    Text(lastConnectedAt, style: .relative)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if let failure = lastFailure(for: pairedHost) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Last failure")
                                    Text(failure.message)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                    Text(failure.timestamp, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            HStack {
                                FeedbackButton(
                                    unavailableReason: isConnectingPairedHost ? "Already reconnecting to this paired Mac." : nil,
                                    action: onReconnectPairedHost
                                ) {
                                    Label("Reconnect", systemImage: "arrow.triangle.2.circlepath")
                                }
                                .buttonStyle(.borderedProminent)

                                Button {
                                    pairingCode = ""
                                } label: {
                                    Label("Repair Pairing", systemImage: "qrcode.viewfinder")
                                }
                                .buttonStyle(.bordered)

                                Button(role: .destructive) {
                                    pendingDestructiveAction = .forgetPairing(pairedHost)
                                } label: {
                                    Label("Forget", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                            }
                            .font(.caption.weight(.semibold))
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Pair") {
                    TextField("mapofagents://pair?payload=...", text: $pairingCode, axis: .vertical)
                        .lineLimit(2...4)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    FeedbackButton(
                        unavailableReason: pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Paste or scan a pairing code before connecting." : nil,
                        action: {
                        let code = pairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
                        onPair(code)
                        pairingCode = ""
                        }
                    ) {
                        Label("Pair with Mac", systemImage: "qrcode")
                    }
                }

                Section("Connect") {
                    TextField("Machine name", text: $remoteName)
                        .textInputAutocapitalization(.words)
                    TextField("ws://mac-mini.tailnet:18945", text: $remoteEndpoint)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Capability token", text: $remoteToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    FeedbackButton(
                        unavailableReason: remoteEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Enter a remote App Server endpoint before connecting." : nil,
                        action: {
                        let token = remoteToken.trimmingCharacters(in: .whitespacesAndNewlines)
                        onConnect(remoteName, remoteEndpoint, token.isEmpty ? nil : token)
                        remoteName = "mac-host.lan"
                        remoteEndpoint = "ws://mac-host.lan:18945"
                        remoteToken = ""
                        }
                    ) {
                        Label("Connect Remote App Server", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }

                Section("Discovery") {
                    FeedbackButton(
                        unavailableReason: supervisorStore.isDiscoveringCodexRemotes || supervisorStore.isDiscoveringTailnet ? "Discovery is already running." : nil,
                        action: {
                            Task {
                            async let codex: Void = supervisorStore.discoverCodexRemotes()
                            async let tailnet: Void = supervisorStore.discoverTailnetMachines()
                            _ = await (codex, tailnet)
                            }
                        }
                    ) {
                        Label("Refresh Discovery", systemImage: "antenna.radiowaves.left.and.right")
                    }

                    if supervisorStore.isDiscoveringCodexRemotes || supervisorStore.isDiscoveringTailnet {
                        HStack {
                            ProgressView()
                            Text("Looking for Codex remotes and Tailnet machines...")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if supervisorStore.isDiscoveringCodexRemotes
                    || !supervisorStore.codexRemotes.isEmpty
                    || supervisorStore.codexRemoteDiscoveryMessage != nil {
                    Section {
                        disclosureHeader(
                            title: "Codex Remotes",
                            systemImage: "terminal",
                            isExpanded: $isCodexRemotesExpanded
                        )

                        if isCodexRemotesExpanded {
                            if let message = supervisorStore.codexRemoteDiscoveryMessage,
                               supervisorStore.codexRemotes.isEmpty,
                               !supervisorStore.isDiscoveringCodexRemotes {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(supervisorStore.codexRemotes) { remote in
                                codexRemoteRow(remote)
                            }
                        }
                    }
                }

                if supervisorStore.isDiscoveringTailnet
                    || !supervisorStore.tailnetMachines.isEmpty
                    || supervisorStore.tailnetDiscoveryMessage != nil {
                    Section {
                        disclosureHeader(
                            title: "Tailnet",
                            systemImage: "point.3.connected.trianglepath.dotted",
                            isExpanded: $isTailnetExpanded
                        )

                        if isTailnetExpanded {
                            if let message = supervisorStore.tailnetDiscoveryMessage,
                               supervisorStore.tailnetMachines.isEmpty,
                               !supervisorStore.isDiscoveringTailnet {
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(supervisorStore.tailnetMachines) { machine in
                                tailnetMachineRow(machine)
                            }
                        }
                    }
                }

                if !supervisorStore.relayEndpoints.isEmpty || !supervisorStore.relayEndpointAttempts.isEmpty {
                    Section("Relay Routes") {
                        ForEach(supervisorStore.relayEndpoints) { endpoint in
                            relayEndpointRow(endpoint)
                        }
                    }
                }

                Section("Machines") {
                    if machines.isEmpty {
                        Text("No remote machines connected.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(machines) { machine in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    Image(systemName: icon(for: machine.platform))
                                        .foregroundStyle(color(for: machine.status))
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(machine.name)
                                            .font(.headline)
                                        Text(machine.endpointDescription)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Text(machine.status.rawValue)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(color(for: machine.status))
                                }

                                if machine.status == .connected {
                                    if machine.platform == .macOS || machine.name.localizedCaseInsensitiveContains("mac") {
                                        Button {
                                            pendingDestructiveAction = .loadWorkflow(machine)
                                        } label: {
                                            Label("Load Mac Layout", systemImage: "rectangle.3.group")
                                        }
                                        .buttonStyle(.bordered)
                                    }

                                    HStack(spacing: 8) {
                                        TextField(defaultFolderPlaceholder(for: machine.platform), text: folderPathBinding(for: machine.id))
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                        Button {
                                            let path = folderPaths[machine.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                                            guard !path.isEmpty else { return }
                                            onAddFolder(machine, path)
                                            folderPaths[machine.id] = ""
                                        } label: {
                                            Image(systemName: "folder.badge.plus")
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }

                                if let lastError = machine.lastError, !lastError.isEmpty {
                                    Label(lastError, systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .lineLimit(3)
                                }

                                let diagnostics = supervisorStore.codexRemoteDiagnostics[machine.id] ?? []
                                if !diagnostics.isEmpty {
                                    ForEach(diagnostics) { step in
                                        diagnosticRow(step)
                                    }
                                }

                                if machine.status != .connected {
                                    Button(role: .destructive) {
                                        pendingDestructiveAction = .removeMachine(machine)
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                    .font(.caption)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Machines")
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
            Button(action.buttonTitle, role: .destructive) {
                switch action {
                case .forgetPairing:
                    onForgetPairing()
                case .loadWorkflow(let machine):
                    onLoadWorkflow(machine)
                case .removeMachine(let machine):
                    onDisconnect(machine.id)
                }
                pendingDestructiveAction = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDestructiveAction = nil
            }
        } message: { action in
            Text(action.message)
        }
    }

    private func disclosureHeader(title: String, systemImage: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.snappy) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                Spacer()
                Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func codexRemoteRow(_ remote: CodexDesktopRemote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: remote.isConnectable ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(remote.isConnectable ? .green : .secondary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(remote.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(codexRemoteDetail(remote))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Text(remote.isConnectable ? "ssh" : "setup")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(remote.isConnectable ? .green : .secondary)
            }

            if let notice = CodexRemoteIdentityStore.importNotice(for: remote) {
                Label("Key prep required on the Mac host", systemImage: "key.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            HStack {
                FeedbackButton(
                    unavailableReason: remote.isConnectable ? nil : "This Codex remote needs SSH setup before it can be diagnosed.",
                    action: {
                        Task { await supervisorStore.diagnoseCodexRemote(remote) }
                    }
                ) {
                    Label("Diagnose", systemImage: "stethoscope")
                }
                .buttonStyle(.bordered)

                FeedbackButton(
                    unavailableReason: remote.isConnectable ? nil : "This Codex remote needs SSH setup before it can connect.",
                    action: {
                        Task { await supervisorStore.connectCodexRemote(remote) }
                    }
                ) {
                    Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(.borderedProminent)
            }
            .font(.caption.weight(.semibold))

            ForEach(supervisorStore.codexRemoteDiagnostics[remote.id] ?? []) { step in
                diagnosticRow(step, remote: remote)
            }
        }
        .padding(.vertical, 4)
    }

    private func tailnetMachineRow(_ machine: TailnetMachine) -> some View {
        HStack(spacing: 10) {
            Image(systemName: machine.isOnline ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(machine.isOnline ? .green : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(machine.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(machine.platform.rawValue) - \(machine.displayAddress)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let endpoint = machine.suggestedWebSocketEndpoint() {
                Button {
                    remoteName = machine.name
                    remoteEndpoint = endpoint
                } label: {
                    Image(systemName: "square.and.pencil")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    private func relayEndpointRow(_ endpoint: AppServerRelayEndpoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(endpoint.name, systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if let attempt = supervisorStore.relayEndpointAttempts[endpoint.id],
                   let nextAttemptAt = attempt.nextAttemptAt,
                   nextAttemptAt > Date() {
                    Text("backoff")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            Text(endpoint.url.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let attempt = supervisorStore.relayEndpointAttempts[endpoint.id] {
                if let lastError = attempt.lastError, !lastError.isEmpty {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                if let nextAttemptAt = attempt.nextAttemptAt, nextAttemptAt > Date() {
                    Text("Retry \(nextAttemptAt, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func diagnosticRow(_ step: RuntimeDiagnosticStep, remote: CodexDesktopRemote? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: diagnosticIcon(for: step.status))
                .foregroundStyle(diagnosticColor(for: step.status))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .font(.caption.weight(.semibold))
                if !step.detail.isEmpty {
                    Text(step.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            Spacer()

            if let action = step.action, let remote {
                Button(actionLabel(for: action)) {
                    Task { await supervisorStore.performCodexRemoteAction(action, for: remote) }
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
            }
        }
    }

    private func folderPathBinding(for hostID: HostID) -> Binding<String> {
        Binding(
            get: { folderPaths[hostID, default: ""] },
            set: { folderPaths[hostID] = $0 }
        )
    }

    private func defaultFolderPlaceholder(for platform: HostPlatform) -> String {
        switch platform {
        case .windows:
            return #"C:\Users\User\Desktop"#
        case .macOS, .linux:
            return "/Users/name/project"
        case .iOS, .iPadOS, .unknown:
            return "Project path"
        }
    }

    private func codexRemoteDetail(_ remote: CodexDesktopRemote) -> String {
        let platform = remote.platform == .unknown ? "codex remote" : remote.platform.rawValue
        return "\(platform) - \(remote.hostname ?? remote.hostID)"
    }

    private func actionLabel(for action: RuntimeDiagnosticAction) -> String {
        switch action {
        case .installCodexCLI:
            return "Install"
        case .updateCodexCLI:
            return "Update"
        case .startAppServer:
            return "Start"
        case .restartAppServer:
            return "Restart"
        }
    }

    private func diagnosticIcon(for status: RuntimeDiagnosticStatus) -> String {
        switch status {
        case .pending:
            return "circle"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .passed:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    private func diagnosticColor(for status: RuntimeDiagnosticStatus) -> Color {
        switch status {
        case .pending:
            return .secondary
        case .running:
            return .blue
        case .passed:
            return .green
        case .warning:
            return .orange
        case .failed:
            return .red
        }
    }

    private func pairedMachine(for host: MapofAgentsPairedHost) -> SupervisorMachine? {
        machines.first { $0.id == host.id }
    }

    private func statusText(for host: MapofAgentsPairedHost) -> String {
        if isConnectingPairedHost {
            return "connecting"
        }
        return pairedMachine(for: host)?.status.rawValue ?? "paired"
    }

    private func statusColor(for host: MapofAgentsPairedHost) -> Color {
        if isConnectingPairedHost {
            return .blue
        }
        guard let machine = pairedMachine(for: host) else {
            return .secondary
        }
        return color(for: machine.status)
    }

    private func selectedEndpoint(for host: MapofAgentsPairedHost) -> MapofAgentsPairingEndpoint? {
        if let activeEndpoint {
            return host.endpoints.first { $0.url.absoluteString == activeEndpoint.url.absoluteString }
        }
        if let lastID = host.lastSuccessfulEndpointID,
           let endpoint = host.endpoints.first(where: { $0.id == lastID }) {
            return endpoint
        }
        if let lastURL = host.lastSuccessfulEndpointURL,
           let endpoint = host.endpoints.first(where: { $0.url.absoluteString == lastURL.absoluteString }) {
            return endpoint
        }
        return host.preferredEndpoints.first
    }

    private func activeEndpointText(for host: MapofAgentsPairedHost) -> String {
        if let activeEndpoint {
            return activeEndpoint.url.absoluteString
        }
        return selectedEndpoint(for: host)?.url.absoluteString ?? "No endpoint"
    }

    private func lastFailure(for host: MapofAgentsPairedHost) -> MapofAgentsPairingEndpointFailure? {
        host.endpointFailures.values
            .sorted { $0.timestamp > $1.timestamp }
            .first
    }

    private func icon(for platform: HostPlatform) -> String {
        switch platform {
        case .macOS:
            return "macbook"
        case .windows:
            return "desktopcomputer"
        case .linux:
            return "terminal"
        case .iOS:
            return "iphone"
        case .iPadOS:
            return "ipad"
        case .unknown:
            return "server.rack"
        }
    }

    private func color(for status: SupervisorMachineStatus) -> Color {
        switch status {
        case .connected:
            return .green
        case .connecting:
            return .blue
        case .disconnected:
            return .secondary
        case .failed:
            return .orange
        }
    }
}

private enum IPhoneActivityFilter: String, CaseIterable, Identifiable {
    case attention = "Attention"
    case diagnostics = "Diagnostics"
    case recent = "Recent"

    var id: String { rawValue }
}

private struct IPhoneActivitySheet: View {
    var events: [WorkflowEvent]
    var attentionRequests: [RuntimeAttentionRequest]
    var machines: [SupervisorMachine]
    var diagnostics: [HostID: [RuntimeDiagnosticStep]]
    var relayAttempts: [HostID: RelayEndpointAttemptState]
    @Binding var preferences: WorkflowNotificationPreferences
    var titleForThread: (WorkflowEvent) -> String
    var onRespondToAttention: (RuntimeAttentionRequest, Bool) -> Void
    var onRespondToAttentionWithText: (RuntimeAttentionRequest, String) -> Void
    var onDeclineTypedAttention: (RuntimeAttentionRequest) -> Void
    var onSelect: (WorkflowEvent) -> Void

    @State private var filter: IPhoneActivityFilter = .attention

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Activity view", selection: $filter) {
                        ForEach(IPhoneActivityFilter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Notifications") {
                    Toggle("Needs Input", isOn: $preferences.notifyOnNeedsInput)
                    Toggle("Failed", isOn: $preferences.notifyOnFailed)
                    Toggle("Completed", isOn: $preferences.notifyOnCompleted)
                }

                switch filter {
                case .attention:
                    attentionContent
                case .diagnostics:
                    diagnosticsContent
                case .recent:
                    recentContent(events.prefix(80).map { $0 })
                }
            }
            .navigationTitle("Activity")
        }
    }

    @ViewBuilder
    private var attentionContent: some View {
        let attentionEvents = events.filter { $0.kind == .needsInput || $0.kind == .failed }
        let failedMachines = machines.filter { $0.status == .failed || $0.status == .disconnected }
        let problemDiagnostics = diagnosticEntries.filter { $0.step.status == .failed || $0.step.status == .warning }
        let failedRelayAttempts = relayAttempts.values
            .filter { $0.lastError?.isEmpty == false }
            .sorted { ($0.lastAttemptAt ?? .distantPast) > ($1.lastAttemptAt ?? .distantPast) }

        Section("Needs Attention") {
            if attentionRequests.isEmpty,
               attentionEvents.isEmpty,
               failedMachines.isEmpty,
               problemDiagnostics.isEmpty,
               failedRelayAttempts.isEmpty {
                Text("No active attention items.")
                    .foregroundStyle(.secondary)
            }

            ForEach(attentionRequests.prefix(20)) { request in
                attentionRequestRow(request)
            }

            ForEach(attentionEvents.prefix(40)) { event in
                eventRow(event)
            }

            ForEach(failedMachines) { machine in
                machineDiagnosticRow(machine)
            }

            ForEach(problemDiagnostics) { entry in
                diagnosticRow(entry)
            }

            ForEach(failedRelayAttempts, id: \.hostID) { attempt in
                relayAttemptRow(attempt)
            }
        }
    }

    private func attentionRequestRow(_ request: RuntimeAttentionRequest) -> some View {
        IPhoneAttentionRequestRow(
            request: request,
            onRespond: onRespondToAttention,
            onRespondWithText: onRespondToAttentionWithText,
            onDeclineTyped: onDeclineTypedAttention
        )
    }

    @ViewBuilder
    private var diagnosticsContent: some View {
        Section("Machines") {
            if machines.isEmpty {
                Text("No machine diagnostics yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(machines) { machine in
                    machineDiagnosticRow(machine)
                }
            }
        }

        Section("Remote Checks") {
            if diagnosticEntries.isEmpty && relayAttempts.isEmpty {
                Text("No remote checks have run yet.")
                    .foregroundStyle(.secondary)
            }

            ForEach(diagnosticEntries) { entry in
                diagnosticRow(entry)
            }

            ForEach(
                relayAttempts.values.sorted { ($0.lastAttemptAt ?? .distantPast) > ($1.lastAttemptAt ?? .distantPast) },
                id: \.hostID
            ) { attempt in
                relayAttemptRow(attempt)
            }
        }
    }

    @ViewBuilder
    private func recentContent(_ visibleEvents: [WorkflowEvent]) -> some View {
        Section("Recent") {
            if visibleEvents.isEmpty {
                Text("No workflow activity yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleEvents) { event in
                    eventRow(event)
                }
            }
        }
    }

    private func eventRow(_ event: WorkflowEvent) -> some View {
        FeedbackButton(
            unavailableReason: event.threadID == nil ? "This activity item is not tied to a thread on the workflow." : nil,
            action: {
                onSelect(event)
            }
        ) {
            HStack(spacing: 10) {
                Image(systemName: icon(for: event.kind))
                    .foregroundStyle(color(for: event.kind))
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(titleForThread(event)) \(verb(for: event.kind))")
                        .font(.headline)
                        .lineLimit(1)

                    Text(eventSubtitle(event))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func machineDiagnosticRow(_ machine: SupervisorMachine) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: machineIcon(for: machine.platform))
                .foregroundStyle(machineColor(for: machine.status))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(machine.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(machine.status.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(machineColor(for: machine.status))
                }

                Text(machine.endpointDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let lastError = machine.lastError, !lastError.isEmpty {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(3)
                } else if let lastEventAt = machine.lastEventAt {
                    Text("Last event \(lastEventAt, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func diagnosticRow(_ entry: IPhoneDiagnosticEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: diagnosticIcon(for: entry.step.status))
                .foregroundStyle(diagnosticColor(for: entry.step.status))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.step.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(entry.step.detail.isEmpty ? entry.hostID.rawValue : entry.step.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 2)
    }

    private func relayAttemptRow(_ attempt: RelayEndpointAttemptState) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(attempt.lastError == nil ? Color.secondary : Color.orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(attempt.endpointName)
                    .font(.headline)
                    .lineLimit(1)
                Text(attempt.endpointURL.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let lastError = attempt.lastError {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(3)
                }
                if let nextAttemptAt = attempt.nextAttemptAt, nextAttemptAt > Date() {
                    Text("Retry \(nextAttemptAt, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var diagnosticEntries: [IPhoneDiagnosticEntry] {
        diagnostics
            .flatMap { hostID, steps in
                steps.map { IPhoneDiagnosticEntry(hostID: hostID, step: $0) }
            }
            .sorted { lhs, rhs in
                if lhs.hostID == rhs.hostID {
                    return lhs.step.title.localizedStandardCompare(rhs.step.title) == .orderedAscending
                }
                return lhs.hostID.rawValue.localizedStandardCompare(rhs.hostID.rawValue) == .orderedAscending
            }
    }

    private func eventSubtitle(_ event: WorkflowEvent) -> String {
        let time = event.createdAt.formatted(date: .omitted, time: .shortened)
        if event.summary.isEmpty {
            return "\(time) - \(event.method)"
        }
        return "\(time) - \(event.summary)"
    }

    private func icon(for kind: WorkflowEventKind) -> String {
        switch kind {
        case .turnStarted:
            return "arrow.triangle.2.circlepath"
        case .turnCompleted:
            return "checkmark.circle.fill"
        case .threadCreated:
            return "plus.circle.fill"
        case .needsInput:
            return "exclamationmark.bubble.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    private func color(for kind: WorkflowEventKind) -> Color {
        switch kind {
        case .turnStarted:
            return .blue
        case .turnCompleted:
            return .green
        case .threadCreated:
            return .orange
        case .needsInput:
            return .orange
        case .failed:
            return .red
        }
    }

    private func verb(for kind: WorkflowEventKind) -> String {
        switch kind {
        case .turnStarted:
            return "started"
        case .turnCompleted:
            return "finished"
        case .threadCreated:
            return "created"
        case .needsInput:
            return "needs input"
        case .failed:
            return "failed"
        }
    }

    private func machineIcon(for platform: HostPlatform) -> String {
        switch platform {
        case .macOS:
            return "macbook"
        case .windows:
            return "desktopcomputer"
        case .linux:
            return "terminal"
        case .iOS:
            return "iphone"
        case .iPadOS:
            return "ipad"
        case .unknown:
            return "server.rack"
        }
    }

    private func machineColor(for status: SupervisorMachineStatus) -> Color {
        switch status {
        case .connected:
            return .green
        case .connecting:
            return .blue
        case .disconnected:
            return .secondary
        case .failed:
            return .orange
        }
    }

    private func diagnosticIcon(for status: RuntimeDiagnosticStatus) -> String {
        switch status {
        case .pending:
            return "circle"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .passed:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    private func diagnosticColor(for status: RuntimeDiagnosticStatus) -> Color {
        switch status {
        case .pending:
            return .secondary
        case .running:
            return .blue
        case .passed:
            return .green
        case .warning:
            return .orange
        case .failed:
            return .red
        }
    }
}

private struct IPhoneAttentionRequestRow: View {
    var request: RuntimeAttentionRequest
    var onRespond: (RuntimeAttentionRequest, Bool) -> Void
    var onRespondWithText: (RuntimeAttentionRequest, String) -> Void
    var onDeclineTyped: (RuntimeAttentionRequest) -> Void

    @State private var responseText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(request.method, systemImage: "exclamationmark.bubble")
                .font(.headline)
                .lineLimit(1)

            Text(request.promptText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)

            if request.supportsApprovalDecision {
                HStack(spacing: 10) {
                    Button("Deny") {
                        onRespond(request, false)
                    }
                    .buttonStyle(.bordered)

                    Button("Allow") {
                        onRespond(request, true)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if request.supportsTypedResponse {
                let choices = request.typedResponseChoices
                if !choices.isEmpty {
                    Picker("Response", selection: $responseText) {
                        ForEach(choices) { option in
                            Text(option.label).tag(option.value)
                        }
                    }
                    .pickerStyle(.menu)
                    .onAppear {
                        if responseText.isEmpty {
                            responseText = request.initialTypedResponseValue
                        }
                    }
                } else {
                    TextField("Response", text: $responseText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...5)
                }

                HStack(spacing: 10) {
                    Button("Decline") {
                        onDeclineTyped(request)
                    }
                    .buttonStyle(.bordered)

                    Button("Send") {
                        onRespondWithText(request, responseText)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct IPhoneDiagnosticEntry: Identifiable {
    var hostID: HostID
    var step: RuntimeDiagnosticStep

    var id: String {
        "\(hostID.rawValue)-\(step.id)"
    }
}

private struct IPhoneThreadNavigatorSheet: View {
    var threads: [CanvasNode]
    var events: [WorkflowEvent]
    var machines: [SupervisorMachine]
    var onSelect: (CanvasNode) -> Void

    @State private var query = ""
    @State private var filter: IPhoneThreadFilter = .all

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Threads", selection: $filter) {
                        ForEach(IPhoneThreadFilter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Search threads", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Threads") {
                    if visibleThreads.isEmpty {
                        Text("No matching threads in this workflow.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(visibleThreads) { thread in
                            Button {
                                onSelect(thread)
                            } label: {
                                threadRow(thread)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Threads")
        }
    }

    private var visibleThreads: [CanvasNode] {
        threads.filter { thread in
            guard matchesFilter(thread) else { return false }
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return true }
            return [
                thread.title,
                thread.subtitle,
                thread.metadata.threadRef?.threadID ?? "",
                thread.metadata.threadRef?.cwd ?? "",
                machineName(for: thread),
            ]
                .contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }
    }

    private func matchesFilter(_ thread: CanvasNode) -> Bool {
        switch filter {
        case .all:
            return true
        case .running:
            return thread.metadata.runStatus == .running
        case .attention:
            return thread.metadata.runStatus == .needsInput
                || thread.metadata.runStatus == .failed
                || latestEvent(for: thread).map { $0.kind == .needsInput || $0.kind == .failed } == true
        }
    }

    private func threadRow(_ thread: CanvasNode) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bubble.left.and.bubble.right")
                .foregroundStyle(statusColor(for: thread))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(thread.title)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    Text(statusText(for: thread))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(statusColor(for: thread))
                }

                Text(thread.metadata.threadRef?.cwd ?? thread.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(machineName(for: thread))
                    if let model = thread.metadata.model {
                        Text(model)
                    }
                    if let effort = thread.metadata.reasoningEffort {
                        Text(effort)
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

                if let event = latestEvent(for: thread) {
                    Text("\(event.createdAt, style: .time) - \(event.summary.isEmpty ? event.method : event.summary)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func latestEvent(for thread: CanvasNode) -> WorkflowEvent? {
        guard let threadRef = thread.metadata.threadRef else { return nil }
        return events.first {
            $0.threadID == threadRef.threadID && ($0.hostID == nil || $0.hostID == threadRef.hostID)
        }
    }

    private func machineName(for thread: CanvasNode) -> String {
        guard let hostID = thread.metadata.threadRef?.hostID ?? thread.metadata.hostID else {
            return "Unknown host"
        }
        return machines.first { $0.id == hostID }?.name ?? hostID.rawValue
    }

    private func statusText(for thread: CanvasNode) -> String {
        switch thread.metadata.runStatus ?? .idle {
        case .idle:
            return "idle"
        case .running:
            return "running"
        case .needsInput:
            return "needs input"
        case .failed:
            return "failed"
        case .complete:
            return "complete"
        case .unknown:
            return "unknown"
        }
    }

    private func statusColor(for thread: CanvasNode) -> Color {
        switch thread.metadata.runStatus ?? .idle {
        case .running:
            return .blue
        case .needsInput:
            return .orange
        case .failed:
            return .red
        case .complete:
            return .green
        case .idle, .unknown:
            return .secondary
        }
    }
}

private enum IPhoneThreadFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case running = "Running"
    case attention = "Attention"

    var id: String { rawValue }
}
#endif
