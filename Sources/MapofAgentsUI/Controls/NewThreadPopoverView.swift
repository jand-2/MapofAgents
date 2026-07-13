import MapofAgentsCore
import SwiftUI

public enum NewThreadTargetKind: String, Hashable, Sendable {
    case folder
    case machine
}

public struct NewThreadRequest: Sendable {
    public var targetNodeID: NodeID
    public var targetKind: NewThreadTargetKind
    public var name: String
    public var model: String
    public var reasoningEffort: String
    public var permissions: CodexThreadPermissions
    public var initialPrompt: String

    public var folderNodeID: NodeID {
        targetNodeID
    }

    public init(
        targetNodeID: NodeID,
        targetKind: NewThreadTargetKind,
        name: String,
        model: String,
        reasoningEffort: String,
        permissions: CodexThreadPermissions = .default,
        initialPrompt: String
    ) {
        self.targetNodeID = targetNodeID
        self.targetKind = targetKind
        self.name = name
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.permissions = permissions
        self.initialPrompt = initialPrompt
    }

    public init(
        folderNodeID: NodeID,
        name: String,
        model: String,
        reasoningEffort: String,
        permissions: CodexThreadPermissions = .default,
        initialPrompt: String
    ) {
        self.init(
            targetNodeID: folderNodeID,
            targetKind: .folder,
            name: name,
            model: model,
            reasoningEffort: reasoningEffort,
            permissions: permissions,
            initialPrompt: initialPrompt
        )
    }
}

public struct NewThreadPopoverView: View {
    @Bindable var graphStore: GraphStore
    @Bindable var runtimeStore: CodexRuntimeStore
    var isFolderAvailable: (CanvasNode) -> Bool
    var modelOptionsForFolder: (CanvasNode?) -> [CodexModelOption]?
    var mentionCandidatesForFolder: (CanvasNode?) -> [MentionCandidate]
    var onSelectedFolderChanged: (CanvasNode?) -> Void
    var onCreate: (NewThreadRequest) async -> Bool
    var onCancel: () -> Void
    var isFullScreen: Bool
    var catalogRevision: Int

    @State private var selectedFolderID: NodeID?
    @State private var selectedMachineID: NodeID?
    @State private var selectedTargetKind: NewThreadTargetKind = .folder
    @State private var selectedModelID = ""
    @State private var selectedEffort = "high"
    @State private var selectedApprovalPolicy = CodexThreadPermissions.default.approvalPolicy
    @State private var selectedSandboxMode = CodexThreadPermissions.default.sandboxMode
    @State private var threadName = ""
    @State private var initialPrompt = ""
    @State private var isConfirmingDangerFullAccess = false
    @State private var isCreating = false

    public init(
        graphStore: GraphStore,
        runtimeStore: CodexRuntimeStore,
        isFolderAvailable: @escaping (CanvasNode) -> Bool = { _ in true },
        modelOptionsForFolder: @escaping (CanvasNode?) -> [CodexModelOption]? = { _ in nil },
        mentionCandidatesForFolder: @escaping (CanvasNode?) -> [MentionCandidate] = { _ in [] },
        onSelectedFolderChanged: @escaping (CanvasNode?) -> Void = { _ in },
        onCreate: @escaping (NewThreadRequest) async -> Bool,
        onCancel: @escaping () -> Void,
        isFullScreen: Bool = false,
        catalogRevision: Int = 0
    ) {
        self.graphStore = graphStore
        self.runtimeStore = runtimeStore
        self.isFolderAvailable = isFolderAvailable
        self.modelOptionsForFolder = modelOptionsForFolder
        self.mentionCandidatesForFolder = mentionCandidatesForFolder
        self.onSelectedFolderChanged = onSelectedFolderChanged
        self.onCreate = onCreate
        self.onCancel = onCancel
        self.isFullScreen = isFullScreen
        self.catalogRevision = catalogRevision
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    setupMessage
                    configurationPanel
                }
                .padding(14)
            }
            .disabled(isCreating)

            Divider()

            composer
        }
        #if os(iOS)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        .frame(width: 470, height: 620)
        #endif
        .background(popoverBackground)
        .overlay {
            if !isFullScreen {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary, lineWidth: 1)
            }
        }
        .shadow(color: .black.opacity(isFullScreen ? 0 : 0.18), radius: 18, x: 0, y: 10)
        .confirmationDialog(
            "Use Full Access on Remote Machine?",
            isPresented: $isConfirmingDangerFullAccess,
            titleVisibility: .visible
        ) {
            Button("Create With Full Access", role: .destructive) {
                performCreate()
            }
            .disabled(isCreating)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This lets Codex run without filesystem sandboxing on the selected remote target. Continue only if you trust the machine, workspace, and prompt context.")
        }
        .onAppear(perform: syncDefaults)
        .onChange(of: runtimeStore.models) { _, _ in syncDefaults() }
        .onChange(of: catalogRevision) { _, _ in syncDefaults() }
        .onChange(of: selectedFolderID) { _, _ in onSelectedFolderChanged(selectedTargetNode) }
        .onChange(of: selectedMachineID) { _, _ in onSelectedFolderChanged(selectedTargetNode) }
        .onChange(of: selectedTargetKind) { _, _ in onSelectedFolderChanged(selectedTargetNode) }
        .onChange(of: selectedModelID) { _, _ in syncReasoningDefault() }
        .task(id: selectedFolderPath ?? "") {
            onSelectedFolderChanged(selectedTargetNode)
        }
    }

    private var popoverBackground: some View {
        Group {
            if isFullScreen {
                #if os(iOS)
                Color(uiColor: .systemBackground)
                #else
                Color.clear.background(.regularMaterial)
                #endif
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.regularMaterial)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.bubble")
                .foregroundStyle(.blue)
                .frame(width: 26, height: 26)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text("New Codex Thread")
                    .font(.headline)

                Text(selectedTargetTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onCancel) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Close")
            .accessibilityLabel("Close new thread")
            .minimumAccessibleHitTarget()
        }
        .padding(14)
    }

    private var setupMessage: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Codex")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)

                Text(isCreating ? "Creating the new thread..." : "Ready for a new thread.")
                    .font(.callout)
            }
            .padding(10)
            .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))

            Spacer(minLength: 40)
        }
    }

    private var configurationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                settingCell("Type") {
                    Picker("Type", selection: $selectedTargetKind) {
                        Text("Project").tag(NewThreadTargetKind.folder)
                        Text("Machine Chat").tag(NewThreadTargetKind.machine)
                    }
                    .labelsHidden()
                }

                if selectedTargetKind == .folder {
                    settingCell("Folder") {
                        Picker("Folder", selection: folderSelection) {
                            ForEach(folderNodes) { folder in
                                Text(folder.title).tag(Optional(folder.id))
                            }
                        }
                        .labelsHidden()
                    }
                } else {
                    settingCell("Machine") {
                        Picker("Machine", selection: machineSelection) {
                            ForEach(machineNodes) { machine in
                                Text(machine.title).tag(Optional(machine.id))
                            }
                        }
                        .labelsHidden()
                    }
                }
            }

            HStack(alignment: .top, spacing: 10) {
                settingCell("Model") {
                    Picker("Model", selection: $selectedModelID) {
                        ForEach(models) { model in
                            Text(model.displayName).tag(model.id)
                        }
                    }
                    .labelsHidden()
                }

                settingCell("Reasoning") {
                    Picker("Reasoning", selection: $selectedEffort) {
                        ForEach(currentModel.supportedReasoningEfforts, id: \.self) { effort in
                            Text(effort).tag(effort)
                        }
                    }
                    .labelsHidden()
                }
            }

            HStack(alignment: .top, spacing: 10) {
                settingCell("Approval") {
                    Picker("Approval", selection: $selectedApprovalPolicy) {
                        ForEach(CodexApprovalPolicy.allCases) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .labelsHidden()
                }

                settingCell("Sandbox") {
                    Picker("Sandbox", selection: $selectedSandboxMode) {
                        ForEach(CodexSandboxMode.allCases) { sandbox in
                            Text(sandbox.displayName).tag(sandbox)
                        }
                    }
                    .labelsHidden()
                }
            }

            if selectedSandboxMode == .dangerFullAccess {
                dangerFullAccessNotice
            }

            TextField("Thread name", text: $threadName)
                .textFieldStyle(.roundedBorder)
        }
        .padding(12)
        .background(.background.opacity(0.48), in: RoundedRectangle(cornerRadius: 8))
    }

    private var dangerFullAccessNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            Text(dangerFullAccessWarningText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .help(dangerFullAccessWarningText)
    }

    private func settingCell<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var composer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Label(currentModel.displayName, systemImage: "cpu")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Label(selectedEffort, systemImage: "dial.medium")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            HStack(alignment: .bottom, spacing: 10) {
                MentionComposerView(
                    text: $initialPrompt,
                    runtimeStore: runtimeStore,
                    placeholder: "Start this thread",
                    fileRoot: selectedFolderPath,
                    extraCandidates: graphStore.workflowFolderMentionCandidates()
                        + mentionCandidatesForFolder(selectedTargetNode),
                    minLines: 4,
                    maxLines: 9,
                    usesLocalMentionCatalog: selectedTargetUsesLocalCatalog,
                    initiallyFocused: true
                )
                .disabled(isCreating)

                FeedbackButton(
                    unavailableReason: createUnavailableReason,
                    action: create
                ) {
                    ZStack {
                        Image(systemName: "paperplane.fill")
                            .opacity(isCreating ? 0 : 1)

                        if isCreating {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .help(createUnavailableReason ?? "Create thread")
                .accessibilityLabel("Create thread")
                .minimumAccessibleHitTarget()
            }
        }
        .padding(14)
    }

    private var folderSelection: Binding<NodeID?> {
        Binding(
            get: { selectedFolderID },
            set: { selectedFolderID = $0 }
        )
    }

    private var machineSelection: Binding<NodeID?> {
        Binding(
            get: { selectedMachineID },
            set: { selectedMachineID = $0 }
        )
    }

    private var folderNodes: [CanvasNode] {
        graphStore.graph.sortedNodes.filter { $0.kind == .folder }
    }

    private var machineNodes: [CanvasNode] {
        graphStore.graph.sortedNodes.filter { $0.kind == .machine }
    }

    private var selectedFolderNode: CanvasNode? {
        guard let selectedFolderID else { return nil }
        return graphStore.graph.nodes[selectedFolderID]
    }

    private var selectedMachineNode: CanvasNode? {
        guard let selectedMachineID else { return nil }
        return graphStore.graph.nodes[selectedMachineID]
    }

    private var selectedTargetNode: CanvasNode? {
        switch selectedTargetKind {
        case .folder:
            return selectedFolderNode
        case .machine:
            return selectedMachineNode
        }
    }

    private var models: [CodexModelOption] {
        if let remoteModels = modelOptionsForFolder(selectedTargetNode), !remoteModels.isEmpty {
            return remoteModels
        }
        return runtimeStore.models.isEmpty ? [runtimeStore.defaultModel] : runtimeStore.models
    }

    private var currentModel: CodexModelOption {
        models.first(where: { $0.id == selectedModelID })
            ?? models.first(where: \.isDefault)
            ?? models.first
            ?? runtimeStore.defaultModel
    }

    private var resolvedThreadName: String {
        let trimmed = threadName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if let selectedFolderID, let folder = graphStore.graph.nodes[selectedFolderID] {
            return "\(folder.title) agent"
        }
        if let selectedMachineID, let machine = graphStore.graph.nodes[selectedMachineID] {
            return "\(machine.title) chat"
        }
        return "Codex thread"
    }

    private var selectedTargetTitle: String {
        switch selectedTargetKind {
        case .folder:
            guard let selectedFolderID, let folder = graphStore.graph.nodes[selectedFolderID] else {
                return "No folder selected"
            }
            return folder.title
        case .machine:
            guard let selectedMachineID, let machine = graphStore.graph.nodes[selectedMachineID] else {
                return "No machine selected"
            }
            return machine.title
        }
    }

    private var selectedFolderPath: String? {
        switch selectedTargetKind {
        case .folder:
            guard let selectedFolderID, let folder = graphStore.graph.nodes[selectedFolderID] else {
                return nil
            }
            return folder.metadata.folderPath
        case .machine:
            guard let selectedMachineID, let machine = graphStore.graph.nodes[selectedMachineID] else {
                return nil
            }
            return ThreadDefaultCWDResolver.defaultCWD(
                for: machine,
                localHostID: runtimeStore.localHost.id,
                localDefaultDirectory: NSHomeDirectory()
            )
        }
    }

    private var selectedTargetUsesLocalCatalog: Bool {
        guard let hostID = selectedTargetNode?.metadata.hostID else {
            return true
        }
        return hostID == runtimeStore.localHost.id
    }

    private var selectedFolderIsAvailable: Bool {
        guard let target = selectedTargetNode else {
            return false
        }
        return isFolderAvailable(target)
    }

    private var selectedTargetIsRemote: Bool {
        guard let hostID = selectedTargetNode?.metadata.hostID else {
            return selectedTargetKind == .machine
        }
        return hostID != runtimeStore.localHost.id
    }

    private var shouldConfirmDangerFullAccess: Bool {
        selectedSandboxMode == .dangerFullAccess && selectedTargetIsRemote
    }

    private var dangerFullAccessWarningText: String {
        if selectedTargetIsRemote {
            return "Full Access disables filesystem sandboxing on the remote target and can read or change files outside the selected folder."
        }
        return "Full Access disables filesystem sandboxing and can read or change files outside the selected folder."
    }

    private var createUnavailableReason: String? {
        if isCreating {
            return "Creating this thread now."
        }

        guard let target = selectedTargetNode else {
            return "Select a machine or folder before creating a thread."
        }

        guard isFolderAvailable(target) else {
            switch selectedTargetKind {
            case .folder:
                return "Connect the machine that owns this folder before creating a thread."
            case .machine:
                return "Connect this machine before creating a chat."
            }
        }

        return nil
    }

    private func create() {
        guard !isCreating else { return }
        guard selectedTargetNode != nil else { return }
        if shouldConfirmDangerFullAccess {
            isConfirmingDangerFullAccess = true
            return
        }
        performCreate()
    }

    private func performCreate() {
        guard !isCreating else { return }
        guard let target = selectedTargetNode else { return }
        let resolvedEffort = currentModel.supportedReasoningEfforts.contains(selectedEffort)
            ? selectedEffort
            : currentModel.defaultReasoningEffort
        let request = NewThreadRequest(
            targetNodeID: target.id,
            targetKind: selectedTargetKind,
            name: resolvedThreadName,
            model: currentModel.id,
            reasoningEffort: resolvedEffort,
            permissions: CodexThreadPermissions(
                approvalPolicy: selectedApprovalPolicy,
                sandboxMode: selectedSandboxMode
            ),
            initialPrompt: initialPrompt
        )

        isCreating = true
        Task {
            let didCreate = await onCreate(request)
            if !didCreate {
                await MainActor.run {
                    isCreating = false
                }
            }
        }
    }

    private func syncDefaults() {
        if selectedFolderID == nil && selectedMachineID == nil {
            switch graphStore.selectedNode?.kind {
            case .folder:
                selectedTargetKind = .folder
                selectedFolderID = graphStore.selectedNode?.id
            case .machine:
                selectedTargetKind = .machine
                selectedMachineID = graphStore.selectedNode?.id
            case .codexThread, .none:
                if let folder = folderNodes.first {
                    selectedTargetKind = .folder
                    selectedFolderID = folder.id
                } else if let machine = machineNodes.first {
                    selectedTargetKind = .machine
                    selectedMachineID = machine.id
                }
            }
        }

        if selectedTargetKind == .folder, selectedFolderID == nil {
            selectedFolderID = folderNodes.first?.id
        }

        if selectedTargetKind == .machine, selectedMachineID == nil {
            selectedMachineID = machineNodes.first?.id
        }

        if selectedModelID.isEmpty || !models.contains(where: { $0.id == selectedModelID }) {
            selectedModelID = currentModel.id
        }

        syncReasoningDefault()
    }

    private func syncReasoningDefault() {
        if !currentModel.supportedReasoningEfforts.contains(selectedEffort) {
            selectedEffort = currentModel.defaultReasoningEffort
        }
    }

}
