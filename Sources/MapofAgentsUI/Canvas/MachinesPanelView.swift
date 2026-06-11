import MapofAgentsCore
import SwiftUI

struct MachinesPanelView: View {
    @Bindable var supervisorStore: WorkflowSupervisorStore
    var localHostID: HostID
    var onConnectRemote: (String, String) -> Void
    var onAddMachineFolder: (SupervisorMachine, String) -> Void
    var onDisconnect: (HostID) -> Void

    @State private var isShowingAddRemote = false
    @State private var remoteName = ""
    @State private var remoteEndpoint = ""
    @State private var expandedMachineID: HostID?
    @State private var pendingDisconnectMachine: SupervisorMachine?
    @AppStorage("mapofagents.panel.machines.collapsed") private var isCollapsed = false
    @AppStorage("mapofagents.panel.codexRemotes.collapsed") private var isCodexRemotesCollapsed = false
    @AppStorage("mapofagents.panel.tailnet.collapsed") private var isTailnetCollapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Machines", systemImage: "server.rack")
                    .font(.headline)

                Spacer()

                Button {
                    withAnimation(.snappy) {
                        isCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(isCollapsed ? "Expand" : "Minimize")
                .accessibilityLabel(isCollapsed ? "Expand machines" : "Minimize machines")

                FeedbackButton(
                    unavailableReason: isDiscoveringMachines ? "Machine discovery is already running." : nil,
                    action: {
                        Task {
                            async let codex: Void = supervisorStore.discoverCodexRemotes()
                            async let tailnet: Void = supervisorStore.discoverTailnetMachines()
                            _ = await (codex, tailnet)
                        }
                    }
                ) {
                    Image(systemName: isDiscoveringMachines ? "arrow.triangle.2.circlepath" : "point.3.connected.trianglepath.dotted")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(isDiscoveringMachines ? "Machine discovery is already running." : "Discover Codex remotes and tailnet machines")
                .accessibilityLabel("Discover machines")

                Button {
                    withAnimation(.snappy) {
                        isShowingAddRemote.toggle()
                    }
                } label: {
                    Image(systemName: isShowingAddRemote ? "xmark" : "plus")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(isShowingAddRemote ? "Close" : "Add remote")
                .accessibilityLabel(isShowingAddRemote ? "Close add remote form" : "Add remote")
            }

            if !isCollapsed {
                if isShowingAddRemote {
                    remoteForm
                }

                codexRemotesSection
                tailnetSection

                VStack(spacing: 6) {
                    ForEach(supervisorStore.machines) { machine in
                        MachineRowView(
                            machine: machine,
                            isLocal: machine.id == localHostID,
                            remote: browsableCodexRemote(for: machine),
                            isExpanded: expandedMachineID == machine.id,
                            onToggleExpanded: {
                                withAnimation(.snappy) {
                                    expandedMachineID = expandedMachineID == machine.id ? nil : machine.id
                                }
                            },
                            onAddFolder: { path in
                                onAddMachineFolder(machine, path)
                            },
                            onDisconnect: { pendingDisconnectMachine = machine }
                        )
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
        .task {
            async let codex: Void = supervisorStore.discoverCodexRemotesIfNeeded()
            async let tailnet: Void = supervisorStore.discoverTailnetMachinesIfNeeded()
            _ = await (codex, tailnet)
        }
        .onAppear {
            isCollapsed = false
        }
        .confirmationDialog(
            pendingDisconnectMachine.map { disconnectDialogTitle(for: $0) } ?? "Disconnect Machine?",
            isPresented: Binding(
                get: { pendingDisconnectMachine != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDisconnectMachine = nil
                    }
                }
            ),
            titleVisibility: .visible,
            presenting: pendingDisconnectMachine
        ) { machine in
            Button(disconnectButtonTitle(for: machine), role: .destructive) {
                onDisconnect(machine.id)
                pendingDisconnectMachine = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDisconnectMachine = nil
            }
        } message: { machine in
            Text(disconnectMessage(for: machine))
        }
    }

    private var isDiscoveringMachines: Bool {
        supervisorStore.isDiscoveringTailnet || supervisorStore.isDiscoveringCodexRemotes
    }

    private var remoteForm: some View {
        VStack(spacing: 8) {
            TextField("Name", text: $remoteName)
                .textFieldStyle(.roundedBorder)

            TextField("ws://127.0.0.1:18945", text: $remoteEndpoint)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                FeedbackButton(
                    unavailableReason: remoteEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Enter a WebSocket endpoint before connecting." : nil,
                    action: connectRemote
                ) {
                    Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(10)
        .background(.background.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var codexRemotesSection: some View {
        if supervisorStore.isDiscoveringCodexRemotes
            || !supervisorStore.codexRemotes.isEmpty
            || supervisorStore.codexRemoteDiscoveryMessage != nil {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Text("Codex Remotes")
                        .font(.caption.weight(.semibold))

                    Spacer()

                    if supervisorStore.isDiscoveringCodexRemotes {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button {
                        withAnimation(.snappy) {
                            isCodexRemotesCollapsed.toggle()
                        }
                    } label: {
                        Image(systemName: isCodexRemotesCollapsed ? "chevron.down" : "chevron.up")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help(isCodexRemotesCollapsed ? "Expand Codex Remotes" : "Collapse Codex Remotes")
                    .accessibilityLabel(isCodexRemotesCollapsed ? "Expand Codex Remotes" : "Collapse Codex Remotes")
                }

                if !isCodexRemotesCollapsed {
                    if let message = supervisorStore.codexRemoteDiscoveryMessage,
                       supervisorStore.codexRemotes.isEmpty,
                       !supervisorStore.isDiscoveringCodexRemotes {
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.background.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
                    }

                    if !supervisorStore.codexRemotes.isEmpty {
                        Text("\(supervisorStore.codexRemotes.count) remote\(supervisorStore.codexRemotes.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        ScrollView {
                            LazyVStack(spacing: 7) {
                                ForEach(supervisorStore.codexRemotes) { remote in
                                    CodexRemoteRowView(
                                        supervisorStore: supervisorStore,
                                        remote: remote,
                                        diagnostics: supervisorStore.codexRemoteDiagnostics[remote.id] ?? [],
                                        onConnect: {
                                            Task { await supervisorStore.connectCodexRemote(remote) }
                                        },
                                        onDiagnose: {
                                            Task { await supervisorStore.diagnoseCodexRemote(remote) }
                                        },
                                        onAction: { action in
                                            Task { await supervisorStore.performCodexRemoteAction(action, for: remote) }
                                        }
                                    )
                                }
                            }
                        }
                        .frame(maxHeight: 260)
                        .scrollIndicators(.visible)
                    }
                }
            }
            .padding(10)
            .background(.background.opacity(0.30), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var tailnetSection: some View {
        if supervisorStore.isDiscoveringTailnet
            || !supervisorStore.tailnetMachines.isEmpty
            || supervisorStore.tailnetDiscoveryMessage != nil {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    Text("Tailnet")
                        .font(.caption.weight(.semibold))

                    Spacer()

                    if supervisorStore.isDiscoveringTailnet {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button {
                        withAnimation(.snappy) {
                            isTailnetCollapsed.toggle()
                        }
                    } label: {
                        Image(systemName: isTailnetCollapsed ? "chevron.down" : "chevron.up")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help(isTailnetCollapsed ? "Expand Tailnet" : "Collapse Tailnet")
                    .accessibilityLabel(isTailnetCollapsed ? "Expand Tailnet" : "Collapse Tailnet")
                }

                if !isTailnetCollapsed {
                    if let message = supervisorStore.tailnetDiscoveryMessage,
                       supervisorStore.tailnetMachines.isEmpty,
                       !supervisorStore.isDiscoveringTailnet {
                        Text(message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.background.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
                    }

                    if !supervisorStore.tailnetMachines.isEmpty {
                        Text("\(supervisorStore.tailnetMachines.count) machine\(supervisorStore.tailnetMachines.count == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        ScrollView {
                            LazyVStack(spacing: 7) {
                                ForEach(supervisorStore.tailnetMachines) { machine in
                                    TailnetMachineRowView(
                                        machine: machine,
                                        onFill: { fillRemote(from: machine) }
                                    )
                                }
                            }
                        }
                        .frame(maxHeight: 260)
                        .scrollIndicators(.visible)
                    }
                }
            }
            .padding(10)
            .background(.background.opacity(0.30), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func connectRemote() {
        let name = remoteName
        let endpoint = remoteEndpoint
        remoteName = ""
        remoteEndpoint = ""
        withAnimation(.snappy) {
            isShowingAddRemote = false
        }
        onConnectRemote(name, endpoint)
    }

    private func fillRemote(from machine: TailnetMachine) {
        guard let endpoint = machine.suggestedWebSocketEndpoint() else {
            return
        }

        remoteName = machine.name
        remoteEndpoint = endpoint
        withAnimation(.snappy) {
            isShowingAddRemote = true
        }
    }

    private func browsableCodexRemote(for machine: SupervisorMachine) -> CodexDesktopRemote? {
        guard let remote = supervisorStore.codexRemote(for: machine.id),
              CodexRemoteTunnelService.canBrowseRemoteFolders(for: remote) else {
            return nil
        }
        return remote
    }

    private func disconnectDialogTitle(for machine: SupervisorMachine) -> String {
        machine.status == .connected ? "Disconnect Machine?" : "Remove Machine?"
    }

    private func disconnectButtonTitle(for machine: SupervisorMachine) -> String {
        machine.status == .connected ? "Disconnect \(machine.name)" : "Remove \(machine.name)"
    }

    private func disconnectMessage(for machine: SupervisorMachine) -> String {
        if machine.status == .connected {
            return "This closes the active relay for \(machine.name). Existing workflow nodes stay on the map, but remote folders and threads will be unavailable until you reconnect."
        }
        return "This removes the saved route for \(machine.name). Existing workflow nodes stay on the map and can be reconnected later."
    }
}

private struct CodexRemoteRowView: View {
    @Bindable var supervisorStore: WorkflowSupervisorStore
    var remote: CodexDesktopRemote
    var diagnostics: [RuntimeDiagnosticStep]
    var onConnect: () -> Void
    var onDiagnose: () -> Void
    var onAction: (RuntimeDiagnosticAction) -> Void

    @State private var pendingIdentityAction: IdentityAction?
    #if os(macOS)
    @State private var diagnosticsWindow: CodexRemoteDiagnosticsWindowPresenter?
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: remote.isConnectable ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(statusColor)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(remote.displayName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)

                        Text(remote.isConnectable ? "ssh" : "setup")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(remote.isConnectable ? .green : .secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background((remote.isConnectable ? Color.green : Color.secondary).opacity(0.12), in: Capsule())
                    }

                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                FeedbackButton(
                    unavailableReason: actionUnavailableReason,
                    action: {
                        performOrExplainIdentityAccess(.connect)
                    }
                ) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(actionUnavailableReason ?? "Start remote App Server and connect through SSH")
            }

            #if os(macOS)
            if diagnosticsSummary != nil || shouldShowDiagnosticsButton {
                HStack(spacing: 6) {
                    if let diagnosticsSummary {
                        Image(systemName: diagnosticsSummary.icon)
                            .foregroundStyle(diagnosticsSummary.color)
                            .frame(width: 16)
                        Text(diagnosticsSummary.text)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    if shouldShowDiagnosticsButton {
                        Button {
                            openDiagnosticsWindow()
                        } label: {
                            Label("Remote Diagnostics", systemImage: "list.clipboard")
                        }
                        .labelStyle(.titleAndIcon)
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .help("Open remote diagnostics")
                        .accessibilityLabel("Open diagnostics for \(remote.displayName)")
                    }
                }
                .padding(.leading, 24)
            }
            #else
            if let diagnosticsSummary {
                HStack(spacing: 6) {
                    Image(systemName: diagnosticsSummary.icon)
                        .foregroundStyle(diagnosticsSummary.color)
                        .frame(width: 16)
                    Text(diagnosticsSummary.text)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.leading, 24)
            }
            #endif

        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(.background.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
        .alert("Prepare SSH Key", isPresented: identityNoticeBinding) {
            Button("Cancel", role: .cancel) {
                pendingIdentityAction = nil
            }
            Button("Continue") {
                guard let action = pendingIdentityAction else { return }
                pendingIdentityAction = nil
                perform(action)
            }
        } message: {
            Text(CodexRemoteIdentityStore.importNotice(for: remote) ?? "")
        }
    }

    private var detail: String {
        let platform = remote.platform == .unknown ? "codex remote" : remote.platform.rawValue
        return "\(platform) - \(remote.hostname ?? remote.hostID)"
    }

    private var isBusy: Bool {
        diagnostics.contains { $0.status == .running }
    }

    private var statusColor: Color {
        if diagnostics.contains(where: { $0.status == .failed }) {
            return .orange
        }
        if diagnostics.contains(where: { $0.status == .warning }) {
            return .orange
        }
        if isBusy {
            return .blue
        }
        return remote.isConnectable ? .green : .secondary
    }

    private var diagnosticsSummary: (icon: String, color: Color, text: String)? {
        guard !diagnostics.isEmpty else { return nil }
        if isBusy {
            return ("arrow.triangle.2.circlepath", .blue, "Remote diagnostics running")
        }
        if let failed = diagnostics.first(where: { $0.status == .failed }) {
            return ("exclamationmark.triangle.fill", .orange, failed.title)
        }
        if let warning = diagnostics.first(where: { $0.status == .warning }) {
            return ("exclamationmark.triangle.fill", .orange, warning.title)
        }
        return nil
    }

    private var shouldShowDiagnosticsButton: Bool {
        diagnostics.contains { $0.status == .failed || $0.status == .warning }
    }

    private var actionUnavailableReason: String? {
        if isBusy {
            return "Remote diagnostics are already running."
        }
        if !remote.isConnectable {
            return "This Codex remote needs SSH setup before it can connect."
        }
        return nil
    }

    private var identityNoticeBinding: Binding<Bool> {
        Binding(
            get: { pendingIdentityAction != nil },
            set: { isPresented in
                if !isPresented {
                    pendingIdentityAction = nil
                }
            }
        )
    }

    private func performOrExplainIdentityAccess(_ action: IdentityAction) {
        if CodexRemoteIdentityStore.importNotice(for: remote) != nil {
            pendingIdentityAction = action
        } else {
            perform(action)
        }
    }

    private func perform(_ action: IdentityAction) {
        switch action {
        case .diagnose:
            onDiagnose()
        case .connect:
            onConnect()
        }
    }

    #if os(macOS)
    private func openDiagnosticsWindow() {
        let presenter = CodexRemoteDiagnosticsWindowPresenter(
            supervisorStore: supervisorStore,
            remote: remote,
            onConnect: onConnect,
            onDiagnose: onDiagnose,
            onAction: onAction,
            onClose: {
                diagnosticsWindow = nil
            }
        )
        diagnosticsWindow = presenter
        presenter.show()
    }
    #endif

    private enum IdentityAction {
        case diagnose
        case connect
    }
}

private struct TailnetMachineRowView: View {
    var machine: TailnetMachine
    var onFill: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: machine.isOnline ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(machine.isOnline ? .green : .secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(machine.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)

                    Text(machine.isOnline ? "online" : "offline")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(machine.isOnline ? .green : .secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background((machine.isOnline ? Color.green : Color.secondary).opacity(0.12), in: Capsule())
                }

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            FeedbackButton(
                unavailableReason: machine.suggestedWebSocketEndpoint() == nil ? "This tailnet entry does not expose a usable App Server endpoint." : nil,
                action: onFill
            ) {
                Image(systemName: "square.and.pencil")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("Fill a manual WebSocket endpoint")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(.background.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
    }

    private var detail: String {
        let platform = machine.platform == .unknown ? "tailnet" : machine.platform.rawValue
        return "\(platform) - \(machine.displayAddress)"
    }
}

private struct MachineRowView: View {
    var machine: SupervisorMachine
    var isLocal: Bool
    var remote: CodexDesktopRemote?
    var isExpanded: Bool
    var onToggleExpanded: () -> Void
    var onAddFolder: (String) -> Void
    var onDisconnect: () -> Void

    @State private var isAddingFolder = false
    @State private var folderPath = ""
    @State private var folderPickerRemote: CodexDesktopRemote?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(machine.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)

                        Text(machine.status.rawValue)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(color.opacity(0.12), in: Capsule())
                    }

                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button(action: onToggleExpanded) {
                    Image(systemName: isExpanded ? "chevron.up" : "info.circle")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Hide details" : "Show machine details")

                if !isLocal {
                    FeedbackButton(
                        unavailableReason: folderActionUnavailableReason,
                        action: {
                            if let remote {
                                folderPickerRemote = remote
                            } else {
                                folderPath = folderPath.isEmpty ? defaultFolderPath : folderPath
                                withAnimation(.snappy) {
                                    isAddingFolder.toggle()
                                }
                            }
                        }
                    ) {
                        Image(systemName: folderButtonIcon)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(folderHelp)

                    Button(action: onDisconnect) {
                        Image(systemName: "stop.circle")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("Disconnect")
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 5) {
                    detailRow("Endpoint", machine.endpointDescription)
                    detailRow("Platform", machine.platform.rawValue)
                    if let codexHome = machine.codexHome, !codexHome.isEmpty {
                        detailRow("Codex", codexHome)
                    }
                    if let lastEventAt = machine.lastEventAt {
                        detailRow("Last event", lastEventAt.formatted(date: .omitted, time: .standard))
                    }
                    if let lastError = machine.lastError, !lastError.isEmpty {
                        detailRow("Error", lastError, color: .orange)
                    }
                }
                .padding(.leading, 27)
            }

            if isAddingFolder {
                HStack(spacing: 6) {
                    TextField(defaultFolderPath, text: $folderPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onSubmit(addFolder)

                    FeedbackButton(
                        unavailableReason: folderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Enter a folder path before adding it." : nil,
                        action: addFolder
                    ) {
                        Image(systemName: "checkmark")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .help("Add folder node")
                }
                .padding(.leading, 27)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(.background.opacity(0.30), in: RoundedRectangle(cornerRadius: 8))
        .sheet(item: $folderPickerRemote) { remote in
            RemoteFolderPickerView(
                remote: remote,
                initialPath: folderPath.isEmpty ? defaultFolderPath : folderPath,
                onCancel: {
                    folderPickerRemote = nil
                },
                onSelect: { path in
                    onAddFolder(path)
                    folderPath = ""
                    folderPickerRemote = nil
                    withAnimation(.snappy) {
                        isAddingFolder = false
                    }
                }
            )
        }
    }

    private var detail: String {
        if let lastError = machine.lastError, !lastError.isEmpty {
            return lastError
        }
        if let lastEventAt = machine.lastEventAt {
            return "\(machine.endpointDescription) - \(lastEventAt.formatted(date: .omitted, time: .shortened))"
        }
        return machine.endpointDescription
    }

    private var defaultFolderPath: String {
        switch machine.platform {
        case .windows:
            if let userHome = windowsUserHome {
                return "\(userHome)\\Desktop"
            }
            return "C:\\Users\\User\\Desktop"
        case .macOS, .linux:
            if let codexHome = machine.codexHome, codexHome.hasSuffix("/.codex") {
                return String(codexHome.dropLast("/.codex".count))
            }
            return "~"
        case .iOS, .iPadOS, .unknown:
            return "~"
        }
    }

    private var folderActionUnavailableReason: String? {
        machine.status == .connected ? nil : "Connect this machine before adding a folder."
    }

    private var folderButtonIcon: String {
        if remote != nil {
            return "folder"
        }
        return isAddingFolder ? "xmark" : "folder.badge.plus"
    }

    private var folderHelp: String {
        if let folderActionUnavailableReason {
            return folderActionUnavailableReason
        }
        if remote != nil {
            return "Browse project folders"
        }
        return isAddingFolder ? "Cancel folder" : "Add folder"
    }

    private var windowsUserHome: String? {
        guard let codexHome = machine.codexHome else { return nil }
        let lowercased = codexHome.lowercased()
        guard lowercased.hasSuffix("\\.codex") else { return nil }
        return String(codexHome.dropLast("\\.codex".count))
    }

    private func addFolder() {
        let path = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        onAddFolder(path)
        folderPath = ""
        withAnimation(.snappy) {
            isAddingFolder = false
        }
    }

    private func detailRow(_ label: String, _ value: String, color: Color = .secondary) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)
            Text(value)
                .font(.caption2)
                .foregroundStyle(color)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    private var icon: String {
        switch machine.status {
        case .connected:
            return "checkmark.circle.fill"
        case .connecting:
            return "arrow.triangle.2.circlepath"
        case .disconnected:
            return "circle"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch machine.status {
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
