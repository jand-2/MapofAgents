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
    var remote: CodexDesktopRemote
    var diagnostics: [RuntimeDiagnosticStep]
    var onConnect: () -> Void
    var onDiagnose: () -> Void
    var onAction: (RuntimeDiagnosticAction) -> Void

    @State private var pendingIdentityAction: IdentityAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: remote.isConnectable ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(remote.isConnectable ? .green : .secondary)
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
                        performOrExplainIdentityAccess(.diagnose)
                    }
                ) {
                    Image(systemName: "stethoscope")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(actionUnavailableReason ?? "Diagnose remote Codex over SSH")

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

            if !diagnostics.isEmpty {
                VStack(spacing: 5) {
                    ForEach(diagnostics) { step in
                        CodexRemoteDiagnosticStepView(
                            step: step,
                            isBusy: isBusy,
                            onAction: onAction
                        )
                    }
                }
                .padding(.leading, 24)
            }

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

    private enum IdentityAction {
        case diagnose
        case connect
    }
}

private struct CodexRemoteDiagnosticStepView: View {
    var step: RuntimeDiagnosticStep
    var isBusy: Bool
    var onAction: (RuntimeDiagnosticAction) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(step.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)

                if !step.detail.isEmpty {
                    Text(step.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            if let action = step.action {
                FeedbackButton(
                    unavailableReason: isBusy ? "Wait for the current remote operation to finish." : nil,
                    action: {
                        onAction(action)
                    }
                ) {
                    Label(action.label, systemImage: action.icon)
                        .labelStyle(.titleAndIcon)
                }
                .controlSize(.mini)
                .buttonStyle(.bordered)
                .help(action.help)
            }
        }
    }

    private var icon: String {
        switch step.status {
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

    private var color: Color {
        switch step.status {
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

private extension RuntimeDiagnosticAction {
    var label: String {
        switch self {
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

    var icon: String {
        switch self {
        case .installCodexCLI:
            return "square.and.arrow.down"
        case .updateCodexCLI:
            return "arrow.triangle.2.circlepath"
        case .startAppServer:
            return "play.fill"
        case .restartAppServer:
            return "restart"
        }
    }

    var help: String {
        switch self {
        case .installCodexCLI:
            return "Install Codex CLI on the remote machine over SSH"
        case .updateCodexCLI:
            return "Update Codex CLI on the remote machine over SSH"
        case .startAppServer:
            return "Start the remote Codex App Server"
        case .restartAppServer:
            return "Restart the remote Codex App Server"
        }
    }
}

private struct MachineRowView: View {
    var machine: SupervisorMachine
    var isLocal: Bool
    var isExpanded: Bool
    var onToggleExpanded: () -> Void
    var onAddFolder: (String) -> Void
    var onDisconnect: () -> Void

    @State private var isAddingFolder = false
    @State private var folderPath = ""

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
                            folderPath = folderPath.isEmpty ? defaultFolderPath : folderPath
                            withAnimation(.snappy) {
                                isAddingFolder.toggle()
                            }
                        }
                    ) {
                        Image(systemName: isAddingFolder ? "xmark" : "folder.badge.plus")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(folderActionUnavailableReason ?? (isAddingFolder ? "Cancel folder" : "Add folder"))

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
