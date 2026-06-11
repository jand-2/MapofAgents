import MapofAgentsCore
import SwiftUI

public struct CanvasCommandBar: View {
    @Bindable var graphStore: GraphStore
    @Bindable var runtimeStore: CodexRuntimeStore
    @Bindable var supervisorStore: WorkflowSupervisorStore
    @Binding private var isMachinesMenuPresented: Bool
    var workflows: [WorkflowRecord]
    var activeWorkflowID: String?
    var onSelectWorkflow: (String) -> Void
    var onNewWorkflow: () -> Void
    var onRenameWorkflow: () -> Void
    var onDuplicateWorkflow: () -> Void
    var onDeleteWorkflow: () -> Void
    var onCreateFolder: () -> Void
    var onCreateThread: () -> Void
    var onAutoArrange: () -> Void
    var onSearch: () -> Void
    var onShowActivity: () -> Void
    var onZoomOut: () -> Void
    var onZoomIn: () -> Void
    var onResetView: () -> Void
    var onRefreshConnections: () -> Void
    var onShowPairing: () -> Void
    var onConnectRemote: (String, String) -> Void
    var onAddMachineFolder: (SupervisorMachine, String) -> Void
    var onDisconnectMachine: (HostID) -> Void
    var onSetupLocalMachine: () -> Void
    var onToggleReadingMode: () -> Void
    var onToggleSubagents: () -> Void
    var isRefreshingConnections: Bool
    var isReadingModePresented: Bool
    var readingThreadCount: Int
    var showsSubagents: Bool

    @State private var menuFeedbackMessage: String?
    @State private var menuFeedbackToken = UUID()

    public init(
        graphStore: GraphStore,
        runtimeStore: CodexRuntimeStore,
        supervisorStore: WorkflowSupervisorStore,
        isMachinesMenuPresented: Binding<Bool> = .constant(false),
        workflows: [WorkflowRecord] = [],
        activeWorkflowID: String? = nil,
        onSelectWorkflow: @escaping (String) -> Void = { _ in },
        onNewWorkflow: @escaping () -> Void = {},
        onRenameWorkflow: @escaping () -> Void = {},
        onDuplicateWorkflow: @escaping () -> Void = {},
        onDeleteWorkflow: @escaping () -> Void = {},
        onCreateFolder: @escaping () -> Void = {},
        onCreateThread: @escaping () -> Void,
        onAutoArrange: @escaping () -> Void,
        onSearch: @escaping () -> Void = {},
        onShowActivity: @escaping () -> Void = {},
        onZoomOut: @escaping () -> Void,
        onZoomIn: @escaping () -> Void,
        onResetView: @escaping () -> Void,
        onRefreshConnections: @escaping () -> Void,
        onShowPairing: @escaping () -> Void = {},
        onConnectRemote: @escaping (String, String) -> Void = { _, _ in },
        onAddMachineFolder: @escaping (SupervisorMachine, String) -> Void = { _, _ in },
        onDisconnectMachine: @escaping (HostID) -> Void = { _ in },
        onSetupLocalMachine: @escaping () -> Void = {},
        onToggleReadingMode: @escaping () -> Void = {},
        onToggleSubagents: @escaping () -> Void = {},
        isRefreshingConnections: Bool,
        isReadingModePresented: Bool = false,
        readingThreadCount: Int = 0,
        showsSubagents: Bool = true
    ) {
        self.graphStore = graphStore
        self.runtimeStore = runtimeStore
        self.supervisorStore = supervisorStore
        self._isMachinesMenuPresented = isMachinesMenuPresented
        self.workflows = workflows
        self.activeWorkflowID = activeWorkflowID
        self.onSelectWorkflow = onSelectWorkflow
        self.onNewWorkflow = onNewWorkflow
        self.onRenameWorkflow = onRenameWorkflow
        self.onDuplicateWorkflow = onDuplicateWorkflow
        self.onDeleteWorkflow = onDeleteWorkflow
        self.onCreateFolder = onCreateFolder
        self.onCreateThread = onCreateThread
        self.onAutoArrange = onAutoArrange
        self.onSearch = onSearch
        self.onShowActivity = onShowActivity
        self.onZoomOut = onZoomOut
        self.onZoomIn = onZoomIn
        self.onResetView = onResetView
        self.onRefreshConnections = onRefreshConnections
        self.onShowPairing = onShowPairing
        self.onConnectRemote = onConnectRemote
        self.onAddMachineFolder = onAddMachineFolder
        self.onDisconnectMachine = onDisconnectMachine
        self.onSetupLocalMachine = onSetupLocalMachine
        self.onToggleReadingMode = onToggleReadingMode
        self.onToggleSubagents = onToggleSubagents
        self.isRefreshingConnections = isRefreshingConnections
        self.isReadingModePresented = isReadingModePresented
        self.readingThreadCount = readingThreadCount
        self.showsSubagents = showsSubagents
    }

    public var body: some View {
        HStack(spacing: 10) {
            workflowMenu

            Divider()
                .frame(height: 20)

            machinesControl

            FeedbackButton(
                unavailableReason: createFolderUnavailableReason,
                action: onCreateFolder
            ) {
                Label("Folder", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.bordered)
            .help(createFolderUnavailableReason ?? "Add a folder to the workflow")

            FeedbackButton(
                unavailableReason: createThreadUnavailableReason,
                action: onCreateThread
            ) {
                Label("Thread", systemImage: "plus.bubble")
            }
            .buttonStyle(.borderedProminent)
            .help(createThreadUnavailableReason ?? "Create Codex thread")

            Button(action: onToggleReadingMode) {
                Label(readingModeTitle, systemImage: "rectangle.split.3x1")
            }
            .buttonStyle(.bordered)
            .tint(isReadingModePresented ? .accentColor : .secondary)
            .help("Open focused chat reading mode")

            Divider()
                .frame(height: 20)

            Button(action: onAutoArrange) {
                Label("Arrange", systemImage: "rectangle.3.group")
            }
            .help("Arrange machines, folders, and threads into default zones")

            Button(action: onToggleSubagents) {
                Label("Subagents", systemImage: showsSubagents ? "person.2.fill" : "person.2.slash")
            }
            .buttonStyle(.bordered)
            .tint(showsSubagents ? .purple : .secondary)
            .help(showsSubagents ? "Hide subagent nodes and lines" : "Show subagent nodes and lines")

            Button(action: onSearch) {
                Label("Search", systemImage: "magnifyingglass")
            }
            .help("Search the thread inbox")

            Button(action: onShowActivity) {
                Label("Activity", systemImage: "bell.badge")
            }
            .help("Show recent notifications")

            Divider()
                .frame(height: 20)

            Button(action: onShowPairing) {
                Label("Pair", systemImage: "qrcode")
            }
            .help("Pair an iPhone with this Mac")
        }
        .font(.callout)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .bottomLeading) {
            if let menuFeedbackMessage {
                ControlFeedbackBubble(message: menuFeedbackMessage)
                    .offset(y: 42)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
                    .allowsHitTesting(false)
                    .zIndex(20)
            }
        }
    }

    private var workflowMenu: some View {
        Menu {
            if workflows.isEmpty {
                Text("No Workflows")
            } else {
                Section("Workflows") {
                    ForEach(workflows) { workflow in
                        Button {
                            onSelectWorkflow(workflow.id)
                        } label: {
                            Label(
                                workflow.name,
                                systemImage: workflow.id == activeWorkflowID ? "checkmark" : "circle"
                            )
                        }
                    }
                }
            }

            Divider()

            Button(action: onNewWorkflow) {
                Label("New Workflow", systemImage: "plus")
            }

            Button {
                if activeWorkflowID == nil {
                    showMenuFeedback("Create or select a workflow before renaming it.")
                } else {
                    onRenameWorkflow()
                }
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button(action: onDuplicateWorkflow) {
                Label("Save Copy", systemImage: "doc.on.doc")
            }

            Button(role: .destructive) {
                if activeWorkflowID == nil {
                    showMenuFeedback("Create or select a workflow before deleting it.")
                } else if workflows.count <= 1 {
                    showMenuFeedback("Keep at least one workflow.")
                } else {
                    onDeleteWorkflow()
                }
            } label: {
                Label("Delete Workflow", systemImage: "trash")
            }
        } label: {
            Label {
                Text(activeWorkflowName)
                    .lineLimit(1)
                    .frame(maxWidth: 180, alignment: .leading)
            } icon: {
                Image(systemName: "rectangle.3.group")
            }
        }
        .help("Workflow")
    }

    private var machinesControl: some View {
        Button {
            withAnimation(.snappy) {
                isMachinesMenuPresented.toggle()
            }
        } label: {
            Label("Machines", systemImage: machinesButtonIcon)
        }
        .buttonStyle(.bordered)
        .tint(machinesNeedAttention ? .orange : .secondary)
        .help("Open machine setup and connections")
        .popover(isPresented: $isMachinesMenuPresented, arrowEdge: .top) {
            machinesPopover
        }
    }

    private var machinesPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            if shouldShowLocalSetup {
                localMachineSetupRow
            }

            if shouldShowConnectionRefresh {
                connectionRefreshRow
            }

            MachinesPanelView(
                supervisorStore: supervisorStore,
                localHostID: runtimeStore.localHost.id,
                onConnectRemote: onConnectRemote,
                onAddMachineFolder: onAddMachineFolder,
                onDisconnect: onDisconnectMachine
            )
        }
        .padding(8)
        .frame(width: 344, alignment: .topLeading)
    }

    private var connectionRefreshRow: some View {
        FeedbackButton(
            unavailableReason: refreshUnavailableReason,
            action: onRefreshConnections
        ) {
            Label(
                isRefreshingConnections ? "Refreshing Connections" : "Refresh Connections",
                systemImage: isRefreshingConnections ? "arrow.triangle.2.circlepath" : "arrow.clockwise"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 2)
    }

    private var localMachineSetupRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "desktopcomputer.and.arrow.down")
                    .foregroundStyle(localSetupTint)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Local Machine")
                        .font(.callout.weight(.semibold))
                    Text(localSetupStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }

            Button {
                onSetupLocalMachine()
            } label: {
                Label(localSetupButtonTitle, systemImage: localSetupButtonIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(runtimeStore.connectionState == .connecting)
            .help("Start the local Codex app-server and add this machine to the map")
        }
        .padding(10)
        .frame(width: 320, alignment: .leading)
        .background(.background.opacity(0.36), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var activeWorkflowName: String {
        workflows.first(where: { $0.id == activeWorkflowID })?.name ?? "Workflow"
    }

    private var hasThreadTarget: Bool {
        graphStore.graph.sortedNodes.contains { $0.kind == .folder || $0.kind == .machine }
    }

    private var hasMachineTarget: Bool {
        graphStore.graph.sortedNodes.contains { $0.kind == .machine }
    }

    private var hasLocalMachineNode: Bool {
        graphStore.graph.sortedNodes.contains { node in
            node.kind == .machine && node.metadata.hostID == runtimeStore.localHost.id
        }
    }

    private var shouldShowLocalSetup: Bool {
        runtimeStore.connectionState != .connected || !hasLocalMachineNode
    }

    private var shouldShowConnectionRefresh: Bool {
        isRefreshingConnections
            || runtimeStore.connectionState != .connected
            || supervisorStore.machines.contains { machine in
                machine.status != .connected || machine.lastError != nil
            }
            || supervisorStore.codexRemoteDiagnostics.values.contains { steps in
                steps.contains { $0.status == .failed || $0.status == .warning || $0.status == .running }
            }
    }

    private var machinesNeedAttention: Bool {
        runtimeStore.connectionState != .connected
            || !hasLocalMachineNode
            || supervisorStore.machines.contains { machine in
                machine.status == .failed
                    || machine.status == .connecting
                    || machine.lastError != nil
            }
            || supervisorStore.codexRemotes.contains { remote in
                CodexRemoteIdentityStore.requiresPreparation(for: remote)
                    || supervisorStore.codexRemoteDiagnostics[remote.id]?.contains { step in
                        step.status == .failed || step.status == .warning || step.status == .running
                    } == true
            }
    }

    private var machinesButtonIcon: String {
        if runtimeStore.connectionState == .connecting
            || supervisorStore.machines.contains(where: { $0.status == .connecting })
            || supervisorStore.codexRemoteDiagnostics.values.contains(where: { steps in
                steps.contains { $0.status == .running }
            }) {
            return "arrow.triangle.2.circlepath"
        }

        if machinesNeedAttention {
            return "exclamationmark.triangle.fill"
        }

        return "server.rack"
    }

    private var localSetupButtonTitle: String {
        if runtimeStore.connectionState == .connected {
            return hasLocalMachineNode ? "Refresh Local Machine" : "Add Local Machine"
        }

        if runtimeStore.connectionState == .connecting {
            return "Starting Local Codex"
        }

        return "Start Local Codex"
    }

    private var localSetupButtonIcon: String {
        runtimeStore.connectionState == .connecting ? "arrow.triangle.2.circlepath" : "play.circle"
    }

    private var localSetupTint: Color {
        switch runtimeStore.connectionState {
        case .connected:
            return .green
        case .connecting:
            return .blue
        case .disconnected:
            return .orange
        case .unavailable:
            return .red
        }
    }

    private var localSetupStatus: String {
        switch runtimeStore.connectionState {
        case .connected where !hasLocalMachineNode:
            return "Connected; add it to this workflow."
        case .connected:
            return runtimeStore.localHost.endpointDescription
        case .connecting:
            return runtimeStore.statusMessage
        case .disconnected:
            return "Codex is ready but not connected."
        case .unavailable:
            return runtimeStore.statusMessage
        }
    }

    private var readingModeTitle: String {
        guard readingThreadCount > 0 else {
            return "Reader"
        }
        return "Reader \(readingThreadCount)"
    }

    private var createThreadUnavailableReason: String? {
        hasThreadTarget ? nil : "Add or connect a machine, then add a folder or create a machine chat."
    }

    private var createFolderUnavailableReason: String? {
        hasMachineTarget ? nil : "Connect or add a machine before adding a folder."
    }

    private var refreshUnavailableReason: String? {
        isRefreshingConnections ? "Connection refresh is already running." : nil
    }

    private func showMenuFeedback(_ message: String) {
        let token = UUID()
        menuFeedbackToken = token

        withAnimation(.snappy) {
            menuFeedbackMessage = message
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(2200))
            guard menuFeedbackToken == token else { return }
            withAnimation(.snappy) {
                menuFeedbackMessage = nil
            }
        }
    }
}
