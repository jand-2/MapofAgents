import MapofAgentsCore
import SwiftUI

public struct CanvasCommandBar: View {
    @Bindable var graphStore: GraphStore
    @Bindable var runtimeStore: CodexRuntimeStore
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
    var onHealthCheck: () -> Void
    var onRunDiagnostics: () -> Void
    var onViewLogs: () -> Void
    var onToggleMachineRecovery: () -> Void
    var onShowActivity: () -> Void
    var onZoomOut: () -> Void
    var onZoomIn: () -> Void
    var onResetView: () -> Void
    var onRefreshConnections: () -> Void
    var onShowPairing: () -> Void
    var onToggleReadingMode: () -> Void
    var onToggleSubagents: () -> Void
    var isRefreshingConnections: Bool
    var isReadingModePresented: Bool
    var readingThreadCount: Int
    var showsSubagents: Bool
    var isMachineRecoveryPresented: Bool

    @State private var menuFeedbackMessage: String?
    @State private var menuFeedbackToken = UUID()

    public init(
        graphStore: GraphStore,
        runtimeStore: CodexRuntimeStore,
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
        onHealthCheck: @escaping () -> Void = {},
        onRunDiagnostics: @escaping () -> Void = {},
        onViewLogs: @escaping () -> Void = {},
        onToggleMachineRecovery: @escaping () -> Void = {},
        onShowActivity: @escaping () -> Void = {},
        onZoomOut: @escaping () -> Void,
        onZoomIn: @escaping () -> Void,
        onResetView: @escaping () -> Void,
        onRefreshConnections: @escaping () -> Void,
        onShowPairing: @escaping () -> Void = {},
        onToggleReadingMode: @escaping () -> Void = {},
        onToggleSubagents: @escaping () -> Void = {},
        isRefreshingConnections: Bool,
        isReadingModePresented: Bool = false,
        readingThreadCount: Int = 0,
        showsSubagents: Bool = true,
        isMachineRecoveryPresented: Bool = false
    ) {
        self.graphStore = graphStore
        self.runtimeStore = runtimeStore
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
        self.onHealthCheck = onHealthCheck
        self.onRunDiagnostics = onRunDiagnostics
        self.onViewLogs = onViewLogs
        self.onToggleMachineRecovery = onToggleMachineRecovery
        self.onShowActivity = onShowActivity
        self.onZoomOut = onZoomOut
        self.onZoomIn = onZoomIn
        self.onResetView = onResetView
        self.onRefreshConnections = onRefreshConnections
        self.onShowPairing = onShowPairing
        self.onToggleReadingMode = onToggleReadingMode
        self.onToggleSubagents = onToggleSubagents
        self.isRefreshingConnections = isRefreshingConnections
        self.isReadingModePresented = isReadingModePresented
        self.readingThreadCount = readingThreadCount
        self.showsSubagents = showsSubagents
        self.isMachineRecoveryPresented = isMachineRecoveryPresented
    }

    public var body: some View {
        HStack(spacing: 10) {
            workflowMenu

            Divider()
                .frame(height: 20)

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

            healthControl

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

    private var healthControl: some View {
        Menu {
            Button(action: onRefreshConnections) {
                Label("Refresh Now", systemImage: "arrow.clockwise")
            }

            Button(action: onRunDiagnostics) {
                Label("Run Diagnostics", systemImage: "stethoscope")
            }

            Button(action: onToggleMachineRecovery) {
                Label(
                    isMachineRecoveryPresented ? "Hide Machine Recovery" : "Show Machine Recovery",
                    systemImage: "cross.case"
                )
            }

            Button(action: onViewLogs) {
                Label("View Logs", systemImage: "doc.text.magnifyingglass")
            }
        } label: {
            Label(
                "Health",
                systemImage: isRefreshingConnections
                    ? "arrow.triangle.2.circlepath"
                    : "heart.text.square"
            )
        } primaryAction: {
            onHealthCheck()
        }
        .help(refreshUnavailableReason ?? "Refresh machine and runtime health")
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
