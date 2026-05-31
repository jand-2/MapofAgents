import MapofAgentsCore
import MapofAgentsUI
import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
import CoreImage.CIFilterBuiltins

struct RootView: View {
    private let repository: LocalControlRoomStore

    @State private var graphStore: GraphStore
    @State private var runtimeStore: CodexRuntimeStore
    @State private var supervisorStore: WorkflowSupervisorStore
    @State private var threadCatalogStore = ThreadCatalogStore()
    @State private var workflowLibrary: WorkflowLibraryCoordinator
    @State private var workflowMemberships: [String: [ThreadWorkflowMembership]] = [:]
    @State private var threadCreation = ThreadCreationCoordinator()
    @State private var isImportingFolder = false
    @State private var folderImportMachine: CanvasNode?
    @State private var isShowingNewThread = false
    @State private var isReadingModePresented = false
    @State private var readingThreadCount = 0
    @State private var isMachinesPanelPresented = false
    @State private var isMachineRecoveryPresented = false
    @State private var isShowingPairing = false
    @State private var canvasSize: CGSize = .zero
    @State private var pairingPayload: MapofAgentsPairingPayload?
    @State private var pairingError: String?
    @State private var pairingStatus: PairingHostStatus = .idle
    @State private var pairingSessionGeneration = 0
    @State private var bootstrapErrorMessage: String?
    @State private var isRefreshingWorkflowConnections = false
    @State private var topNotifications: [TopNotification] = []
    @State private var topNotificationHistory: [TopNotification] = []
    @State private var isShowingNotificationHistory = false
    @State private var hookEventBridgeTask: Task<Void, Never>?
    @State private var seenTopActivityEventIDs: Set<String> = []
    @State private var hasPrimedTopActivityEvents = false
    @AppStorage("canvas.showSubagents") private var showsSubagents = true
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
            onPickLocalMachineFolder: beginLocalMachineFolderImport,
            mentionCandidatesForThread: mentionCandidates(for:),
            onThreadMentionCatalogNeeded: refreshMentionCatalog(for:),
            showsSubagents: showsSubagents,
            isReadingModePresented: $isReadingModePresented,
            readingThreadCount: $readingThreadCount,
            isMachinesPanelPresented: $isMachinesPanelPresented,
            isMachineRecoveryPresented: $isMachineRecoveryPresented,
            onCanvasSizeChange: { canvasSize = $0 }
        )
            .overlay(alignment: .topLeading) {
                if !isReadingModePresented {
                    CanvasCommandBar(
                        graphStore: graphStore,
                        runtimeStore: runtimeStore,
                        workflows: workflowLibrary.workflows,
                        activeWorkflowID: workflowLibrary.activeWorkflowID,
                        onSelectWorkflow: selectWorkflow,
                        onNewWorkflow: beginCreateWorkflow,
                        onRenameWorkflow: beginRenameWorkflow,
                        onDuplicateWorkflow: beginDuplicateWorkflow,
                        onDeleteWorkflow: beginDeleteActiveWorkflow,
                        onCreateFolder: beginTopBarFolderImport,
                        onCreateThread: {
                            workflowLibrary.editorMode = nil
                            dismissPairingPopover()
                            isShowingNewThread = true
                        },
                        onAutoArrange: { Task { await graphStore.autoArrange(availableWidth: canvasSize.width > 0 ? canvasSize.width : nil) } },
                        onSearch: showThreadSearch,
                        onHealthCheck: runHealthCheck,
                        onRunDiagnostics: runDiagnostics,
                        onViewLogs: viewLogs,
                        onToggleMachineRecovery: {
                            isMachineRecoveryPresented.toggle()
                        },
                        onShowActivity: showNotificationHistory,
                        onZoomOut: { Task { await graphStore.zoomViewport(by: 0.86) } },
                        onZoomIn: { Task { await graphStore.zoomViewport(by: 1.16) } },
                        onResetView: { Task { await graphStore.resetViewport() } },
                        onRefreshConnections: { refreshWorkflowConnections() },
                        onShowPairing: showPairing,
                        onToggleReadingMode: { isReadingModePresented.toggle() },
                        onToggleSubagents: { showsSubagents.toggle() },
                        isRefreshingConnections: isRefreshingWorkflowConnections,
                        isReadingModePresented: isReadingModePresented,
                        readingThreadCount: readingThreadCount,
                        showsSubagents: showsSubagents,
                        isMachineRecoveryPresented: isMachineRecoveryPresented
                    )
                    .padding(14)
                }
            }
            .overlay(alignment: .topLeading) {
                if isShowingNewThread {
                    NewThreadPopoverView(
                        graphStore: graphStore,
                        runtimeStore: runtimeStore,
                        isFolderAvailable: isFolderAvailable,
                        modelOptionsForFolder: modelOptions(for:),
                        mentionCandidatesForFolder: mentionCandidates(for:),
                        onSelectedFolderChanged: refreshThreadFormCatalog(for:),
                        onCreate: createThread,
                        onCancel: { isShowingNewThread = false },
                        catalogRevision: threadCreation.catalogRevision
                    )
                    .padding(.leading, 14)
                    .padding(.top, 72)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                }
            }
            .overlay(alignment: .topLeading) {
                if let workflowEditorMode = workflowLibrary.editorMode {
                    WorkflowNamePopoverView(
                        mode: workflowEditorMode,
                        name: Binding(
                            get: { workflowLibrary.nameDraft },
                            set: { workflowLibrary.nameDraft = $0 }
                        ),
                        onSubmit: submitWorkflowName,
                        onCancel: { workflowLibrary.editorMode = nil }
                    )
                    .padding(.leading, 14)
                    .padding(.top, 72)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                }
            }
            .overlay(alignment: .topLeading) {
                if isShowingPairing {
                    PairIPhonePopoverView(
                        payload: pairingPayload,
                        errorMessage: pairingError,
                        status: pairingStatus,
                        onRefresh: showPairing,
                        onCancel: dismissPairingPopover
                    )
                    .padding(.leading, 14)
                    .padding(.top, 72)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                }
            }
            .overlay(alignment: .topTrailing) {
                if isShowingNotificationHistory {
                    TopNotificationHistoryView(
                        notifications: topNotificationHistory,
                        onClose: { isShowingNotificationHistory = false },
                        onDismissAllCurrent: dismissAllTopNotifications
                    )
                    .padding(14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if !topNotifications.isEmpty {
                    TopNotificationStackView(
                        notifications: topNotifications,
                        onDismiss: dismissTopNotification,
                        onDismissAll: dismissAllTopNotifications
                    )
                    .padding(14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .task {
                if let bootstrapErrorMessage {
                    recordTopErrorNotification(
                        bootstrapErrorMessage,
                        source: .appBootstrap,
                        action: "App storage"
                    )
                }
                supervisorStore.start()
                startWorkflowHookEventBridge()
                await workflowLibrary.refreshState()
                await graphStore.load()
                await workflowLibrary.refreshState()
                await supervisorStore.updateWorkflowThreads(graphStore.workflowThreadRefs)
                do {
                    let events = try await repository.loadWorkflowEvents()
                    let localEvents = events.filter { $0.hostID == nil || $0.hostID == runtimeStore.localHost.id }
                    runtimeStore.restoreWorkflowEvents(localEvents)
                    await supervisorStore.restoreWorkflowEvents(events)
                } catch {
                    recordPersistenceError(error, action: "Restore workflow activity")
                }
                do {
                    let endpoints = try await repository.loadRelayEndpoints()
                    await supervisorStore.restoreRelayEndpoints(endpoints)
                    do {
                        try await repository.saveRelayEndpoints(supervisorStore.relayEndpoints)
                    } catch {
                        recordPersistenceError(error, action: "Save relay routes")
                    }
                } catch {
                    recordPersistenceError(error, action: "Restore relay routes")
                }
                await supervisorStore.registerLocalHost(runtimeStore.localHost)
                await graphStore.applyHost(runtimeStore.localHost)
                await runtimeStore.connect()
                await supervisorStore.registerLocalHost(runtimeStore.localHost)
                await graphStore.applyHost(runtimeStore.localHost)
                await supervisorStore.updateWorkflowThreads(graphStore.workflowThreadRefs)
                await supervisorStore.refreshConnections(for: workflowMapHostIDs)
                await graphStore.applySupervisorMachines(supervisorStore.machines)
                await graphStore.applyHost(runtimeStore.localHost)
                await supervisorStore.updateWorkflowThreads(graphStore.workflowThreadRefs)
                primeTopActivityNotifications(with: supervisorStore.workflowEvents)
            }
            .onChange(of: graphStore.graph.workflowThreadContentSignature) { _, _ in
                Task {
                    await supervisorStore.updateWorkflowThreads(graphStore.workflowThreadRefs)
                }
            }
            .onChange(of: runtimeStore.workflowEvents) { _, events in
                Task {
                    await supervisorStore.ingestLocalEvents(events, host: runtimeStore.localHost)
                }
            }
            .onChange(of: runtimeStore.localHost) { _, host in
                Task {
                    await supervisorStore.registerLocalHost(host)
                    await graphStore.applyHost(host)
                }
            }
            .onChange(of: supervisorStore.machines) { _, machines in
                Task {
                    await graphStore.applySupervisorMachines(machines)
                    await graphStore.applyHost(runtimeStore.localHost)
                }
            }
            .onChange(of: supervisorStore.workflowEvents) { _, events in
                Task {
                    do {
                        try await repository.saveWorkflowEvents(events)
                    } catch {
                        recordPersistenceError(error, action: "Save workflow activity")
                    }
                }
                recordTopActivityNotifications(from: events)
            }
            .onChange(of: supervisorStore.relayEndpoints) { _, endpoints in
                Task {
                    do {
                        try await repository.saveRelayEndpoints(endpoints)
                    } catch {
                        recordPersistenceError(error, action: "Save relay routes")
                    }
                }
            }
            .onChange(of: workflowLibrary.errorMessage) { _, error in
                recordTopErrorNotification(
                    error,
                    source: .workflowLibrary,
                    action: "Workflow library"
                )
            }
            .onChange(of: threadCreation.errorMessage) { _, error in
                recordTopErrorNotification(
                    error,
                    source: .threadCreation,
                    action: "New Codex thread"
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: .mapofagentsConnectRequested)) { _ in
                Task { await runtimeStore.connect() }
            }
            .onDisappear {
                stopWorkflowHookEventBridge()
            }
            .fileImporter(
                isPresented: $isImportingFolder,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleFolderImport(result)
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

    private func beginCreateWorkflow() {
        isShowingNewThread = false
        dismissPairingPopover()
        workflowLibrary.beginCreateWorkflow()
    }

    private func beginDuplicateWorkflow() {
        isShowingNewThread = false
        dismissPairingPopover()
        workflowLibrary.beginDuplicateWorkflow()
    }

    private func beginRenameWorkflow() {
        isShowingNewThread = false
        dismissPairingPopover()
        workflowLibrary.beginRenameWorkflow()
    }

    private func beginDeleteActiveWorkflow() {
        workflowLibrary.beginDeleteActiveWorkflow()
    }

    private func beginTopBarFolderImport() {
        workflowLibrary.editorMode = nil
        dismissPairingPopover()
        isShowingNewThread = false

        let selectedMachine: CanvasNode? = {
            guard case .node(let id) = graphStore.selection,
                  let node = graphStore.graph.nodes[id],
                  node.kind == .machine else {
                return nil
            }
            return node
        }()
        let localMachine = graphStore.graph.nodes.values.first {
            $0.kind == .machine && $0.metadata.hostID == runtimeStore.localHost.id
        }
        guard let machine = selectedMachine ?? localMachine else {
            recordTopErrorNotification(
                "Connect a machine before adding a folder.",
                source: nil,
                action: "Add folder"
            )
            return
        }

        guard machine.metadata.hostID == runtimeStore.localHost.id else {
            isMachinesPanelPresented = true
            recordTopErrorNotification(
                "Use the folder button on the remote machine row so mapofagents can use that machine's project picker.",
                source: nil,
                action: "Add remote folder"
            )
            return
        }

        beginLocalMachineFolderImport(machine)
    }

    private func showThreadSearch() {
        threadCatalogStore.selectedMode = .search
        isMachinesPanelPresented = false
        isShowingNotificationHistory = false
    }

    private func runHealthCheck() {
        refreshWorkflowConnections(showProblemsAutomatically: true)
    }

    private func runDiagnostics() {
        Task {
            await runtimeStore.runDiagnostics()
            isMachinesPanelPresented = true
        }
    }

    private func viewLogs() {
        Task { @MainActor in
            do {
                let paths = try ApplicationPaths.defaultPaths()
                NSWorkspace.shared.open(paths.applicationSupportDirectory)
            } catch {
                recordPersistenceError(error, action: "Open app logs")
            }
        }
    }

    private func showNotificationHistory() {
        withAnimation(.snappy) {
            isShowingNotificationHistory.toggle()
        }
    }

    private func submitWorkflowName() {
        Task {
            if await workflowLibrary.submitWorkflowName() {
                await loadActiveWorkflow()
            }
        }
    }

    private func selectWorkflow(_ workflowID: String) {
        isShowingNewThread = false
        dismissPairingPopover()

        Task {
            if await workflowLibrary.selectWorkflow(workflowID) {
                await loadActiveWorkflow()
            }
        }
    }

    private func deleteWorkflow(_ workflow: WorkflowRecord) {
        isShowingNewThread = false
        dismissPairingPopover()

        Task {
            if await workflowLibrary.deleteWorkflow(workflow) {
                await loadActiveWorkflow()
            }
        }
    }

    private func primeTopActivityNotifications(with events: [WorkflowEvent]) {
        guard !hasPrimedTopActivityEvents else { return }
        seenTopActivityEventIDs.formUnion(events.map(\.id))
        hasPrimedTopActivityEvents = true
    }

    private func recordTopActivityNotifications(from events: [WorkflowEvent]) {
        guard hasPrimedTopActivityEvents else {
            primeTopActivityNotifications(with: events)
            return
        }

        let newEvents = events
            .filter { seenTopActivityEventIDs.insert($0.id).inserted }
            .sorted { $0.createdAt < $1.createdAt }

        for event in newEvents {
            appendTopNotification(
                TopNotification(
                    kind: .activity(event.kind),
                    title: activityNotificationTitle(for: event),
                    message: activityNotificationMessage(for: event),
                    action: activityNotificationAction(for: event),
                    eventCreatedAt: event.createdAt
                )
            )
        }
    }

    private func recordTopErrorNotification(
        _ message: String?,
        source: TopNotificationSource?,
        action: String
    ) {
        guard let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        appendTopNotification(
            TopNotification(
                kind: .error,
                title: "Action failed",
                message: message,
                action: action,
                source: source
            )
        )
    }

    private func appendTopNotification(_ notification: TopNotification) {
        topNotifications.removeAll { existing in
            if let source = notification.source, existing.source == source {
                return true
            }
            if existing.kind == notification.kind,
               existing.title == notification.title,
               existing.message == notification.message,
               existing.action == notification.action {
                return true
            }
            return false
        }

        topNotifications.insert(notification, at: 0)
        if topNotifications.count > 5 {
            topNotifications.removeLast(topNotifications.count - 5)
        }

        topNotificationHistory.removeAll { existing in
            existing.kind == notification.kind
                && existing.title == notification.title
                && existing.message == notification.message
                && existing.action == notification.action
                && abs(existing.displayedAt.timeIntervalSince(notification.displayedAt)) < 1
        }
        topNotificationHistory.insert(notification, at: 0)
        if topNotificationHistory.count > 100 {
            topNotificationHistory.removeLast(topNotificationHistory.count - 100)
        }
    }

    private func dismissTopNotification(_ notification: TopNotification) {
        topNotifications.removeAll { $0.id == notification.id }
        clearTopNotificationSource(notification.source)
    }

    private func dismissAllTopNotifications() {
        let sources = Set(topNotifications.compactMap(\.source))
        topNotifications.removeAll()
        for source in sources {
            clearTopNotificationSource(source)
        }
    }

    private func clearTopNotificationSource(_ source: TopNotificationSource?) {
        switch source {
        case .appBootstrap:
            bootstrapErrorMessage = nil
        case .persistence:
            break
        case .workflowLibrary:
            workflowLibrary.errorMessage = nil
        case .threadCreation:
            threadCreation.errorMessage = nil
        case nil:
            break
        }
    }

    private func recordPersistenceError(_ error: Error, action: String) {
        recordTopErrorNotification(
            "Could not \(action.lowercased()): \(error.localizedDescription)",
            source: .persistence,
            action: action
        )
    }

    private func startWorkflowHookEventBridge() {
        guard hookEventBridgeTask == nil else { return }
        let bridge = WorkflowHookEventFileBridge(defaultHostID: runtimeStore.localHost.id)
        hookEventBridgeTask = bridge.start { events in
            for event in events {
                guard shouldRecordHookWorkflowEvent(event) else {
                    continue
                }
                runtimeStore.recordWorkflowEvent(event)
            }
        }
    }

    private func stopWorkflowHookEventBridge() {
        hookEventBridgeTask?.cancel()
        hookEventBridgeTask = nil
    }

    private func shouldRecordHookWorkflowEvent(_ event: WorkflowEvent) -> Bool {
        if event.kind == .threadCreated {
            let sourceMatches = event.threadID.map { threadID in
                graphStore.workflowThreadRefs.contains { threadRef in
                    threadRef.matches(hostID: event.hostID, threadID: threadID)
                }
            } ?? false
            let childMatches = event.childThreadID.map { threadID in
                graphStore.workflowThreadRefs.contains { threadRef in
                    threadRef.matches(hostID: event.childHostID, threadID: threadID)
                }
            } ?? false
            return sourceMatches || childMatches
        }

        guard let threadID = event.threadID else {
            return false
        }

        return graphStore.workflowThreadRefs.contains { threadRef in
            threadRef.matches(hostID: event.hostID, threadID: threadID)
        }
    }

    private func activityNotificationTitle(for event: WorkflowEvent) -> String {
        let name = threadTitle(for: event)
        switch event.kind {
        case .turnStarted:
            return "\(name) started"
        case .turnCompleted:
            return "\(name) finished"
        case .threadCreated:
            return "\(name) created a thread"
        case .needsInput:
            return "\(name) needs input"
        case .failed:
            return "\(name) failed"
        }
    }

    private func activityNotificationMessage(for event: WorkflowEvent) -> String {
        if let origin = WorkflowActivityAttribution.origin(for: event, in: graphStore.graph, events: supervisorStore.workflowEvents)?.title {
            switch event.kind {
            case .turnStarted:
                return "Started by \(origin)"
            case .turnCompleted:
                return "Triggered by \(origin)"
            case .threadCreated, .needsInput, .failed:
                break
            }
        }

        return event.summary.isEmpty ? event.method : event.summary
    }

    private func activityNotificationAction(for event: WorkflowEvent) -> String {
        switch event.kind {
        case .turnStarted:
            return "Turn started"
        case .turnCompleted:
            return "Turn completed"
        case .threadCreated:
            return "Thread created"
        case .needsInput:
            return "Needs input"
        case .failed:
            return "Failed"
        }
    }

    private func threadTitle(for event: WorkflowEvent) -> String {
        guard let threadID = event.threadID else {
            return "Codex thread"
        }

        return graphStore.graph.nodes.values.first {
            $0.metadata.threadRef?.matches(hostID: event.hostID, threadID: threadID) == true
        }?.title ?? "Codex thread"
    }

    private func loadActiveWorkflow() async {
        await workflowLibrary.refreshState()
        await graphStore.load()
        await refreshWorkflowMemberships()
        await supervisorStore.updateWorkflowThreads(graphStore.workflowThreadRefs)
        await graphStore.applySupervisorMachines(supervisorStore.machines)
        await graphStore.applyHost(runtimeStore.localHost)
        await supervisorStore.updateWorkflowThreads(graphStore.workflowThreadRefs)
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
            recordPersistenceError(error, action: "Refresh workflow memberships")
        }
    }

    private func handleFolderImport(_ result: Result<[URL], Error>) {
        let machine = folderImportMachine
        folderImportMachine = nil

        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                await graphStore.addFolder(
                    path: url.path,
                    hostID: machine?.metadata.hostID ?? runtimeStore.localHost.id,
                    platform: machine?.metadata.platform ?? runtimeStore.localHost.platform
                )
            }
        case .failure(let error):
            threadCreation.errorMessage = error.localizedDescription
        }
    }

    private func beginLocalMachineFolderImport(_ machine: CanvasNode) {
        folderImportMachine = machine
        workflowLibrary.editorMode = nil
        isShowingNewThread = false
        dismissPairingPopover()
        isImportingFolder = true
    }

    private func showPairing() {
        workflowLibrary.editorMode = nil
        isShowingNewThread = false
        isShowingPairing = true

        pairingPayload = nil
        pairingError = nil
        pairingStatus = .starting
        pairingSessionGeneration += 1
        let generation = pairingSessionGeneration
        Task {
            do {
                let payload = try await MapofAgentsMacPairingService.beginPairingSession()
                guard isShowingPairing, pairingSessionGeneration == generation else { return }
                pairingPayload = payload
                pairingError = nil
                pairingStatus = .ready
            } catch {
                guard isShowingPairing, pairingSessionGeneration == generation else { return }
                pairingPayload = nil
                pairingError = error.localizedDescription
                pairingStatus = .failed(error.localizedDescription)
            }
        }
    }

    private func dismissPairingPopover() {
        let wasShowingPairing = isShowingPairing
        pairingSessionGeneration += 1
        isShowingPairing = false
        pairingStatus = .idle

        guard wasShowingPairing else { return }
        Task {
            try? await MapofAgentsMacPairingService.stopPairingSession()
        }
    }

    private func refreshWorkflowConnections(showProblemsAutomatically: Bool = false) {
        guard !isRefreshingWorkflowConnections else { return }

        isRefreshingWorkflowConnections = true
        let hostIDs = workflowMapHostIDs

        Task {
            if hostIDs.contains(runtimeStore.localHost.id) {
                await runtimeStore.connect()
                await supervisorStore.registerLocalHost(runtimeStore.localHost)
                await graphStore.applyHost(runtimeStore.localHost)
            }

            await supervisorStore.refreshConnections(for: hostIDs)
            await graphStore.applySupervisorMachines(supervisorStore.machines)
            await graphStore.applyHost(runtimeStore.localHost)
            await supervisorStore.updateWorkflowThreads(graphStore.workflowThreadRefs)
            isRefreshingWorkflowConnections = false

            if showProblemsAutomatically, hasHealthProblems {
                isMachinesPanelPresented = true
                await runtimeStore.runDiagnostics()
            }
        }
    }

    private var hasHealthProblems: Bool {
        runtimeStore.connectionState != .connected
            || supervisorStore.machines.contains { machine in
                machine.status == .failed || machine.lastError != nil
            }
    }

    private var workflowMapHostIDs: Set<HostID> {
        threadCreation.workflowMapHostIDs(in: graphStore.graph)
    }

    private var mergedWorkflowEvents: [WorkflowEvent] {
        (runtimeStore.workflowEvents + supervisorStore.workflowEvents)
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func modelOptions(for target: CanvasNode?) -> [CodexModelOption]? {
        threadCreation.modelOptions(for: target, localHostID: runtimeStore.localHost.id)
    }

    private func mentionCandidates(for target: CanvasNode?) -> [MentionCandidate] {
        threadCreation.mentionCandidates(for: target, localHostID: runtimeStore.localHost.id)
    }

    private func mentionCandidates(for threadRef: ThreadRef?) -> [MentionCandidate] {
        threadCreation.mentionCandidates(for: threadRef, localHostID: runtimeStore.localHost.id)
    }

    private func refreshThreadFormCatalog(for target: CanvasNode?) {
        threadCreation.refreshThreadFormCatalog(
            for: target,
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

    private func createThread(_ request: NewThreadRequest) async -> Bool {
        let didCreate = await threadCreation.createThread(
            request,
            graphStore: graphStore,
            runtimeStore: runtimeStore,
            supervisorStore: supervisorStore,
            allowsLocalRuntime: true,
            localDefaultDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            localRuntimeUnavailableMessage: "Connect the local Codex runtime before creating a thread."
        )

        if didCreate {
            isShowingNewThread = false
        }

        return didCreate
    }

    private func isFolderAvailable(_ target: CanvasNode) -> Bool {
        threadCreation.isTargetAvailable(
            target,
            localHostID: runtimeStore.localHost.id,
            localConnectionState: runtimeStore.connectionState,
            supervisorStore: supervisorStore,
            allowsLocalRuntime: true
        )
    }
}

private enum TopNotificationSource: Hashable {
    case appBootstrap
    case persistence
    case workflowLibrary
    case threadCreation
}

private enum PairingHostStatus: Equatable {
    case idle
    case starting
    case ready
    case failed(String)

    var title: String {
        switch self {
        case .idle:
            return "Pairing host idle"
        case .starting:
            return "Starting pairing host"
        case .ready:
            return "Pairing host ready"
        case .failed:
            return "Pairing host failed"
        }
    }

    var systemImage: String {
        switch self {
        case .idle:
            return "pause.circle"
        case .starting:
            return "arrow.triangle.2.circlepath"
        case .ready:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .idle:
            return .secondary
        case .starting:
            return .blue
        case .ready:
            return .green
        case .failed:
            return .red
        }
    }
}

private enum TopNotificationKind: Hashable {
    case error
    case activity(WorkflowEventKind)

    var systemImage: String {
        switch self {
        case .error:
            return "exclamationmark.triangle.fill"
        case .activity(let kind):
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
                return "xmark.octagon.fill"
            }
        }
    }

    var tint: Color {
        switch self {
        case .error:
            return .red
        case .activity(let kind):
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
    }
}

private struct TopNotification: Identifiable, Hashable {
    var id = UUID()
    var kind: TopNotificationKind
    var title: String
    var message: String
    var action: String
    var displayedAt = Date()
    var eventCreatedAt: Date?
    var source: TopNotificationSource?
}

private struct TopNotificationStackView: View {
    var notifications: [TopNotification]
    var onDismiss: (TopNotification) -> Void
    var onDismissAll: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if notifications.count > 1 {
                Button("Dismiss All", action: onDismissAll)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
            }

            ForEach(notifications) { notification in
                TopNotificationCard(
                    notification: notification,
                    onDismiss: { onDismiss(notification) }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy, value: notifications)
    }
}

private struct TopNotificationCard: View {
    var notification: TopNotification
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notification.kind.systemImage)
                .foregroundStyle(notification.kind.tint)
                .frame(width: 18, height: 18)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                Text(notification.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(notification.message)
                    .font(.caption)
                    .foregroundStyle(notification.kind == .error ? .red : .secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Shown \(notification.displayedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute().second())) - \(notification.action)")
                    if let eventCreatedAt = notification.eventCreatedAt {
                        Text("Activity \(eventCreatedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute().second()))")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 360, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(notification.kind.tint.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 6)
    }
}

private struct TopNotificationHistoryView: View {
    var notifications: [TopNotification]
    var onClose: () -> Void
    var onDismissAllCurrent: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Activity", systemImage: "bell.badge")
                    .font(.headline)

                Spacer()

                Button("Dismiss Current", action: onDismissAllCurrent)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Close activity")
            }

            if notifications.isEmpty {
                Text("No notifications yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 10)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(notifications) { notification in
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: notification.kind.systemImage)
                                    .foregroundStyle(notification.kind.tint)
                                    .frame(width: 16)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(notification.title)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)

                                        Spacer()

                                        Text(notification.displayedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute().second()))
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }

                                    Text(notification.message)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)

                                    Text(notification.action)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(notification.kind.tint)
                                        .lineLimit(1)
                                }
                            }
                            .padding(8)
                            .background(.background.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .frame(maxHeight: 420)
                .scrollIndicators(.visible)
            }
        }
        .padding(12)
        .frame(width: 380, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 16, x: 0, y: 8)
    }
}

private struct WorkflowNamePopoverView: View {
    var mode: WorkflowEditorMode
    @Binding var name: String
    var onSubmit: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: mode.systemImage)
                    .foregroundStyle(.blue)
                    .frame(width: 26, height: 26)
                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                Text(mode.title)
                    .font(.headline)

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Close")
            }

            TextField("Workflow name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onSubmit)

            HStack {
                Spacer()

                Button("Cancel", action: onCancel)

                FeedbackButton(
                    unavailableReason: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Enter a workflow name before saving." : nil,
                    action: onSubmit
                ) {
                    Text(mode.actionTitle)
                }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
    }
}

private struct PairIPhonePopoverView: View {
    var payload: MapofAgentsPairingPayload?
    var errorMessage: String?
    var status: PairingHostStatus
    var onRefresh: () -> Void
    var onCancel: () -> Void

    private var pairingURLString: String? {
        try? payload?.pairingURL().absoluteString
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "qrcode")
                    .foregroundStyle(.blue)
                    .frame(width: 26, height: 26)
                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    Text("Pair iPhone")
                        .font(.headline)
                    if let payload {
                        Text(payload.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh")

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Close")
            }

            if let errorMessage {
                statusBadge
                Text(errorMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            } else if let payload, let pairingURLString {
                statusBadge
                HStack(alignment: .top, spacing: 14) {
                    PairingQRCodeView(text: pairingURLString)
                        .frame(width: 188, height: 188)
                        .background(.white, in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 10) {
                        endpointSummary(payload)

                        Button {
                            copy(pairingURLString)
                        } label: {
                            Label("Copy Pairing URL", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderedProminent)

                        if let expiresAt = payload.expiresAt {
                            Text("Valid until \(expiresAt.formatted(date: .omitted, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 230, alignment: .leading)
                }
            } else {
                statusBadge
                ProgressView()
                    .frame(width: 430, height: 188)
            }
        }
        .padding(14)
        .frame(width: 470)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 10)
    }

    private func endpointSummary(_ payload: MapofAgentsPairingPayload) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(payload.preferredEndpoints.prefix(4)) { endpoint in
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(endpoint.kind.rawValue.capitalized)
                            .font(.caption.weight(.semibold))
                        Text(endpoint.url.absoluteString)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } icon: {
                    Image(systemName: endpoint.kind == .tailnet ? "point.3.connected.trianglepath.dotted" : "network")
                        .foregroundStyle(endpoint.kind == .tailnet ? .green : .secondary)
                }
            }
        }
    }

    private var statusBadge: some View {
        Label(status.title, systemImage: status.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.tint)
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private struct PairingQRCodeView: View {
    var text: String

    var body: some View {
        if let image = QRCodeRenderer.image(from: text) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(10)
        } else {
            Image(systemName: "qrcode")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)
        }
    }
}

private enum QRCodeRenderer {
    static func image(from text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else {
            return nil
        }

        let representation = NSCIImageRep(ciImage: outputImage)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}

private struct RuntimeDiagnosticsView: View {
    var steps: [RuntimeDiagnosticStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Runtime Diagnostic", systemImage: "stethoscope")
                .font(.headline)

            ForEach(steps) { step in
                HStack(spacing: 8) {
                    Image(systemName: icon(for: step.status))
                        .foregroundStyle(color(for: step.status))
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(step.title)
                            .font(.caption.weight(.semibold))
                        if !step.detail.isEmpty {
                            Text(step.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 310, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func icon(for status: RuntimeDiagnosticStatus) -> String {
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

    private func color(for status: RuntimeDiagnosticStatus) -> Color {
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

private struct AttentionRequestsView: View {
    var requests: [RuntimeAttentionRequest]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Needs You", systemImage: "hand.raised")
                .font(.headline)

            ForEach(requests.prefix(3)) { request in
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.method)
                        .font(.caption.weight(.semibold))
                    Text(request.summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
#endif
