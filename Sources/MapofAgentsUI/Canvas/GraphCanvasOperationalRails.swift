import MapofAgentsCore
import SwiftUI

struct GraphCanvasOperationalRails: View {
    @Bindable var runtimeStore: CodexRuntimeStore
    @Bindable var supervisorStore: WorkflowSupervisorStore
    @Bindable var threadCatalogStore: ThreadCatalogStore
    var workflowEvents: [WorkflowEvent]
    var maxHeight: CGFloat = 760
    @Binding var notificationPreferences: WorkflowNotificationPreferences
    var threadTitle: (WorkflowEvent) -> String
    var turnOriginTitle: (WorkflowEvent) -> String?
    var onSelectEvent: (WorkflowEvent) -> Void
    var onConnectRemote: (String, String) -> Void
    var onAddMachineFolder: (SupervisorMachine, String) -> Void
    var onDisconnect: (HostID) -> Void
    var onRefreshThreadInbox: () -> Void
    var onSearchThreadInbox: () -> Void
    var onOpenInboxThread: (ThreadCatalogEntry) -> Void
    var onAddInboxThreadToCanvas: (ThreadCatalogEntry) -> Void
    var onArchiveInboxThread: (ThreadCatalogEntry) -> Void
    var onMarkInboxThreadRead: (ThreadCatalogEntry, Bool) -> Void
    var onHoverInboxNode: (NodeID?) -> Void = { _ in }
    var onFocusAttention: (RuntimeAttentionRequest) -> Void
    var onRespondToAttention: (RuntimeAttentionRequest, Bool) -> Void
    var onRespondToAttentionWithText: (RuntimeAttentionRequest, String) -> Void
    var onDeclineTypedAttention: (RuntimeAttentionRequest) -> Void
    var showsThreadInbox: Bool = true
    @Binding var isMachinesPanelPresented: Bool
    @Binding var isMachineRecoveryPresented: Bool

    var body: some View {
        let attentionRequests = runtimeStore.pendingAttentionRequests + supervisorStore.pendingAttentionRequests
        let hasMachineIssue = supervisorStore.machines.contains { machine in
            machine.status == .failed
                || machine.status == .connecting
                || machine.lastError != nil
                || (
                    machine.status == .disconnected
                        && supervisorStore.relayEndpoints.contains { $0.id == machine.id }
                )
        } || supervisorStore.codexRemotes.contains { remote in
            CodexRemoteIdentityStore.requiresPreparation(for: remote)
                || supervisorStore.codexRemoteDiagnostics[remote.id]?.contains {
                    $0.status == .failed || $0.status == .warning || $0.status == .running
                } == true
        }
        ScrollView {
            VStack(alignment: .trailing, spacing: 10) {
                if isMachineRecoveryPresented {
                    MachineRecoveryChecklistRailView(
                        supervisorStore: supervisorStore,
                        localHostID: runtimeStore.localHost.id,
                        onDisconnect: onDisconnect
                    )
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }

                if isMachinesPanelPresented || hasMachineIssue {
                    MachinesPanelView(
                        supervisorStore: supervisorStore,
                        localHostID: runtimeStore.localHost.id,
                        onConnectRemote: onConnectRemote,
                        onAddMachineFolder: onAddMachineFolder,
                        onDisconnect: onDisconnect
                    )
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }

                if showsThreadInbox {
                    ThreadInboxPanelView(
                        catalogStore: threadCatalogStore,
                        onRefresh: onRefreshThreadInbox,
                        onSearch: onSearchThreadInbox,
                        onOpen: onOpenInboxThread,
                        onAddToCanvas: onAddInboxThreadToCanvas,
                        onArchive: onArchiveInboxThread,
                        onMarkRead: onMarkInboxThreadRead,
                        onHoverNode: onHoverInboxNode,
                        attentionRequests: attentionRequests,
                        onFocusAttention: onFocusAttention,
                        onRespondToAttention: onRespondToAttention,
                        onRespondToAttentionWithText: onRespondToAttentionWithText,
                        onDeclineTypedAttention: onDeclineTypedAttention
                    )
                }

                if !attentionRequests.isEmpty {
                    AttentionRequestsRailView(
                        requests: attentionRequests,
                        onFocus: onFocusAttention,
                        onRespond: onRespondToAttention,
                        onRespondWithText: onRespondToAttentionWithText,
                        onDeclineTyped: onDeclineTypedAttention
                    )
                }

                if !runtimeStore.runtimeDiagnostics.isEmpty {
                    RuntimeDiagnosticsRailView(steps: runtimeStore.runtimeDiagnostics)
                }
            }
        }
        .frame(maxHeight: maxHeight)
        .scrollIndicators(.visible)
    }
}

private struct MachineRecoveryChecklistRailView: View {
    @Bindable var supervisorStore: WorkflowSupervisorStore
    var localHostID: HostID
    var onDisconnect: (HostID) -> Void

    @State private var pendingIdentityRecovery: PendingIdentityRecovery?
    @State private var pendingRouteRemoval: MachineRecoveryTarget?

    var body: some View {
        Group {
            if !targets.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Label("Machine Recovery", systemImage: "cross.case")
                            .font(.headline)

                        Spacer()

                        Text("\(targets.count) action\(targets.count == 1 ? "" : "s")")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    ForEach(targets) { target in
                        MachineRecoveryChecklistCardView(
                            target: target,
                            onRemoteAction: requestRemoteAction,
                            onDiagnosticAction: performDiagnosticAction,
                            onReconnect: reconnect,
                            onRemoveRoute: { pendingRouteRemoval = $0 }
                        )
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
            }
        }
        .alert("Prepare SSH Key", isPresented: identityNoticeBinding) {
            Button("Cancel", role: .cancel) {
                pendingIdentityRecovery = nil
            }
            Button("Continue") {
                guard let recovery = pendingIdentityRecovery else { return }
                pendingIdentityRecovery = nil
                performRemoteAction(recovery.action, for: recovery.remote)
            }
        } message: {
            Text(pendingIdentityRecovery.flatMap { CodexRemoteIdentityStore.importNotice(for: $0.remote) } ?? "")
        }
        .confirmationDialog(
            pendingRouteRemoval.map { "Remove \($0.name)?" } ?? "Remove stale route?",
            isPresented: routeRemovalBinding,
            titleVisibility: .visible,
            presenting: pendingRouteRemoval
        ) { target in
            Button("Remove Stale Route", role: .destructive) {
                onDisconnect(target.id)
                pendingRouteRemoval = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRouteRemoval = nil
            }
        } message: { target in
            Text("This removes the saved route for \(target.name). Existing workflow nodes stay on the map and can be reconnected later.")
        }
    }

    private var targets: [MachineRecoveryTarget] {
        let savedRouteIDs = Set(supervisorStore.relayEndpoints.map(\.id))
        var targetsByID: [HostID: MachineRecoveryTarget] = [:]

        for machine in supervisorStore.machines where machine.id != localHostID {
            let remote = supervisorStore.codexRemotes.first { $0.id == machine.id }
            let target = MachineRecoveryTarget(
                id: machine.id,
                machine: machine,
                remote: remote,
                attempt: supervisorStore.relayEndpointAttempts[machine.id],
                diagnostics: supervisorStore.codexRemoteDiagnostics[machine.id] ?? [],
                hasSavedRoute: savedRouteIDs.contains(machine.id)
            )
            if isRecoveryCandidate(target) {
                targetsByID[machine.id] = target
            }
        }

        for remote in supervisorStore.codexRemotes where remote.id != localHostID {
            let machine = supervisorStore.machines.first { $0.id == remote.id }
            let target = MachineRecoveryTarget(
                id: remote.id,
                machine: machine,
                remote: remote,
                attempt: supervisorStore.relayEndpointAttempts[remote.id],
                diagnostics: supervisorStore.codexRemoteDiagnostics[remote.id] ?? [],
                hasSavedRoute: savedRouteIDs.contains(remote.id)
            )
            if isRecoveryCandidate(target) {
                targetsByID[remote.id] = target
            }
        }

        return targetsByID.values.sorted { lhs, rhs in
            if priority(for: lhs) != priority(for: rhs) {
                return priority(for: lhs) < priority(for: rhs)
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private var identityNoticeBinding: Binding<Bool> {
        Binding(
            get: { pendingIdentityRecovery != nil },
            set: { isPresented in
                if !isPresented {
                    pendingIdentityRecovery = nil
                }
            }
        )
    }

    private var routeRemovalBinding: Binding<Bool> {
        Binding(
            get: { pendingRouteRemoval != nil },
            set: { isPresented in
                if !isPresented {
                    pendingRouteRemoval = nil
                }
            }
        )
    }

    private func isRecoveryCandidate(_ target: MachineRecoveryTarget) -> Bool {
        if target.needsIdentityPreparation {
            return true
        }
        if target.diagnostics.contains(where: { $0.status == .failed || $0.status == .warning || $0.status == .running }) {
            return true
        }
        if let attempt = target.attempt,
           attempt.consecutiveFailures > 0 || attempt.nextAttemptAt != nil {
            return true
        }
        guard let machine = target.machine else {
            return false
        }

        switch machine.status {
        case .failed, .connecting:
            return true
        case .disconnected:
            return target.hasSavedRoute
        case .connected:
            return machine.lastError?.isEmpty == false
        }
    }

    private func priority(for target: MachineRecoveryTarget) -> Int {
        if target.isBusy {
            return 0
        }
        if target.needsIdentityPreparation {
            return 1
        }
        if target.diagnostics.contains(where: { $0.status == .failed }) || target.machine?.status == .failed {
            return 2
        }
        if target.machine?.status == .disconnected && target.hasSavedRoute {
            return 3
        }
        return 4
    }

    private func requestRemoteAction(_ action: RecoveryRemoteAction, for remote: CodexDesktopRemote) {
        if CodexRemoteIdentityStore.requiresPreparation(for: remote),
           CodexRemoteIdentityStore.importNotice(for: remote) != nil {
            pendingIdentityRecovery = PendingIdentityRecovery(remote: remote, action: action)
            return
        }

        performRemoteAction(action, for: remote)
    }

    private func performRemoteAction(_ action: RecoveryRemoteAction, for remote: CodexDesktopRemote) {
        switch action {
        case .diagnose:
            Task { await supervisorStore.diagnoseCodexRemote(remote) }
        case .connect:
            Task { await supervisorStore.connectCodexRemote(remote) }
        }
    }

    private func performDiagnosticAction(_ action: RuntimeDiagnosticAction, for remote: CodexDesktopRemote) {
        Task { await supervisorStore.performCodexRemoteAction(action, for: remote) }
    }

    private func reconnect(_ hostID: HostID) {
        Task { await supervisorStore.reconnect(hostID) }
    }
}

private struct MachineRecoveryChecklistCardView: View {
    var target: MachineRecoveryTarget
    var onRemoteAction: (RecoveryRemoteAction, CodexDesktopRemote) -> Void
    var onDiagnosticAction: (RuntimeDiagnosticAction, CodexDesktopRemote) -> Void
    var onReconnect: (HostID) -> Void
    var onRemoveRoute: (MachineRecoveryTarget) -> Void

    var body: some View {
        let steps = recoverySteps
        let recommendedID = recommendedStepID(in: steps)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: target.machine?.status == .failed ? "exclamationmark.triangle.fill" : "server.rack")
                    .foregroundStyle(target.machine?.status == .failed ? .orange : .secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(target.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)

                    Text(target.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 6)

                Text(target.statusLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(target.statusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(target.statusColor.opacity(0.12), in: Capsule())
            }

            if let recommended = steps.first(where: { $0.id == recommendedID }) {
                Label("Next: \(recommended.summary)", systemImage: "arrow.right.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(spacing: 5) {
                ForEach(steps) { step in
                    MachineRecoveryStepRowView(
                        step: step,
                        isRecommended: step.id == recommendedID
                    )
                }
            }
        }
        .padding(9)
        .background(.background.opacity(0.30), in: RoundedRectangle(cornerRadius: 8))
    }

    private var recoverySteps: [MachineRecoveryStep] {
        var steps = [
            verifyEndpointStep,
        ]

        if let keyPreparationStep {
            steps.append(keyPreparationStep)
        }

        steps.append(appServerStep)
        steps.append(reconnectStep)

        if let removeRouteStep {
            steps.append(removeRouteStep)
        }

        return steps
    }

    private func recommendedStepID(in steps: [MachineRecoveryStep]) -> String? {
        if let running = steps.first(where: { $0.status == .running }) {
            return running.id
        }
        if target.needsIdentityPreparation,
           let prepareKey = steps.first(where: { $0.id == "prepare-key" }) {
            return prepareKey.id
        }
        if target.diagnostics.isEmpty,
           let verify = steps.first(where: { $0.id == "verify-endpoint" && $0.status != .passed }) {
            return verify.id
        }
        if let repair = steps.first(where: { $0.id == "app-server" && $0.status != .passed && $0.actionTitle != nil }) {
            return repair.id
        }
        if let reconnect = steps.first(where: { $0.id == "reconnect" && $0.status != .passed }) {
            return reconnect.id
        }
        if let remove = steps.first(where: { $0.id == "remove-route" && $0.status != .passed }) {
            return remove.id
        }
        return steps.first(where: { $0.status != .passed })?.id
    }

    private var verifyEndpointStep: MachineRecoveryStep {
        if let remote = target.remote {
            let sshStep = diagnosticStep(ids: ["ssh"])
            let status = sshStep?.status ?? (target.isBusy ? .running : .pending)
            return MachineRecoveryStep(
                id: "verify-endpoint",
                title: "Verify endpoint",
                detail: sshStep?.detail.nilIfBlank ?? "Check SSH and remote endpoint reachability.",
                status: status,
                actionTitle: "Diagnose",
                actionIcon: "stethoscope",
                unavailableReason: remoteActionUnavailableReason(for: remote),
                action: { onRemoteAction(.diagnose, remote) }
            )
        }

        let status: RuntimeDiagnosticStatus
        if target.machine?.status == .connected {
            status = .passed
        } else if target.machine?.status == .connecting {
            status = .running
        } else if target.machine?.status == .failed || target.attempt?.lastError?.isEmpty == false {
            status = .failed
        } else {
            status = .warning
        }

        return MachineRecoveryStep(
            id: "verify-endpoint",
            title: "Verify endpoint",
            detail: target.attempt?.lastError?.nilIfBlank ?? target.machine?.lastError?.nilIfBlank ?? "Probe the saved app-server WebSocket route.",
            status: status,
            actionTitle: "Probe",
            actionIcon: "network",
            unavailableReason: genericReconnectUnavailableReason,
            action: { onReconnect(target.id) }
        )
    }

    private var keyPreparationStep: MachineRecoveryStep? {
        guard let remote = target.remote,
              CodexRemoteIdentityStore.importNotice(for: remote) != nil else {
            return nil
        }

        let needsPreparation = CodexRemoteIdentityStore.requiresPreparation(for: remote)
        let status: RuntimeDiagnosticStatus
        let detail: String
        if needsPreparation {
            if target.isBusy {
                status = .running
                detail = "Key access was approved; waiting for the SSH operation to finish."
            } else if target.diagnostics.contains(where: { $0.status == .failed }) {
                status = .failed
                detail = "Key preparation or SSH access still needs attention."
            } else {
                status = .warning
                detail = "Permission is needed before this SSH key can be copied locally."
            }
        } else {
            status = .passed
            detail = CodexRemoteIdentityStore.routeIdentityPath(for: remote) == nil
                ? "SSH identity is ready; no local copy is required."
                : "SSH key copy is ready in Application Support."
        }

        return MachineRecoveryStep(
            id: "prepare-key",
            title: "Prepare SSH key",
            detail: detail,
            status: status,
            actionTitle: needsPreparation ? "Prepare & Connect" : nil,
            actionIcon: "key.fill",
            unavailableReason: remoteActionUnavailableReason(for: remote),
            action: { onRemoteAction(.connect, remote) }
        )
    }

    private var appServerStep: MachineRecoveryStep {
        if let remote = target.remote {
            if let actionableStep = target.diagnostics.first(where: { $0.action != nil }),
               let action = actionableStep.action {
                return MachineRecoveryStep(
                    id: "app-server",
                    title: appServerTitle(for: action),
                    detail: actionableStep.detail.nilIfBlank ?? actionableStep.title,
                    status: actionableStep.status,
                    actionTitle: action.label,
                    actionIcon: action.icon,
                    unavailableReason: target.isBusy ? "Wait for the current remote operation to finish." : nil,
                    action: { onDiagnosticAction(action, remote) }
                )
            }

            if let listenerStep = diagnosticStep(ids: ["listener", "app-server", "connect"]) {
                let canDiagnoseAgain = listenerStep.status != .passed
                return MachineRecoveryStep(
                    id: "app-server",
                    title: "Restart/probe app-server",
                    detail: listenerStep.detail.nilIfBlank ?? listenerStep.title,
                    status: listenerStep.status,
                    actionTitle: canDiagnoseAgain ? "Diagnose" : nil,
                    actionIcon: "stethoscope",
                    unavailableReason: remoteActionUnavailableReason(for: remote),
                    action: { onRemoteAction(.diagnose, remote) }
                )
            }

            return MachineRecoveryStep(
                id: "app-server",
                title: "Restart/probe app-server",
                detail: "Run diagnostics to check whether the remote app-server is listening.",
                status: .pending,
                actionTitle: "Diagnose",
                actionIcon: "stethoscope",
                unavailableReason: remoteActionUnavailableReason(for: remote),
                action: { onRemoteAction(.diagnose, remote) }
            )
        }

        return MachineRecoveryStep(
            id: "app-server",
            title: "Restart/probe app-server",
            detail: "No SSH restart action is configured for this saved WebSocket route.",
            status: target.machine?.status == .connected ? .passed : .warning,
            actionTitle: target.machine?.status == .connected ? nil : "Restart",
            actionIcon: "restart",
            unavailableReason: "No remote SSH restart callback exists for this machine.",
            action: {}
        )
    }

    private var reconnectStep: MachineRecoveryStep {
        let status: RuntimeDiagnosticStatus
        if target.machine?.status == .connected {
            status = .passed
        } else if target.machine?.status == .connecting || target.isBusy {
            status = .running
        } else if target.machine?.status == .failed {
            status = .failed
        } else {
            status = .pending
        }

        if let remote = target.remote {
            return MachineRecoveryStep(
                id: "reconnect",
                title: "Reconnect",
                detail: reconnectDetail,
                status: status,
                actionTitle: status == .passed ? nil : "Connect",
                actionIcon: "antenna.radiowaves.left.and.right",
                unavailableReason: status == .passed ? nil : remoteActionUnavailableReason(for: remote),
                action: { onRemoteAction(.connect, remote) }
            )
        }

        return MachineRecoveryStep(
            id: "reconnect",
            title: "Reconnect",
            detail: reconnectDetail,
            status: status,
            actionTitle: status == .passed ? nil : "Reconnect",
            actionIcon: "antenna.radiowaves.left.and.right",
            unavailableReason: status == .passed ? nil : genericReconnectUnavailableReason,
            action: { onReconnect(target.id) }
        )
    }

    private var removeRouteStep: MachineRecoveryStep? {
        guard target.machine != nil || target.hasSavedRoute else {
            return nil
        }
        guard target.machine?.status != .connected else {
            return nil
        }

        return MachineRecoveryStep(
            id: "remove-route",
            title: "Remove stale route",
            detail: "Use this only when the endpoint is no longer valid.",
            status: target.machine?.status == .connected ? .pending : .warning,
            actionTitle: "Remove",
            actionIcon: "trash",
            unavailableReason: nil,
            action: { onRemoveRoute(target) }
        )
    }

    private var reconnectDetail: String {
        if let nextAttemptAt = target.attempt?.nextAttemptAt,
           nextAttemptAt > Date() {
            return "Retry is cooling down until \(nextAttemptAt.formatted(date: .omitted, time: .shortened))."
        }
        if let lastError = target.attempt?.lastError?.nilIfBlank ?? target.machine?.lastError?.nilIfBlank {
            return lastError
        }
        if target.machine?.status == .connected {
            return "App-server relay is connected."
        }
        return "Open a fresh relay to the machine."
    }

    private var genericReconnectUnavailableReason: String? {
        if let attempt = target.attempt,
           !attempt.canAttempt() {
            return "Retry is cooling down until \(attempt.nextAttemptAt?.formatted(date: .omitted, time: .shortened) ?? "later")."
        }
        if target.hasSavedRoute {
            return nil
        }
        return "No saved endpoint exists for this machine."
    }

    private func remoteActionUnavailableReason(for remote: CodexDesktopRemote) -> String? {
        if target.isBusy {
            return "Remote recovery is already running."
        }
        if !remote.isConnectable {
            return "This Codex remote needs SSH setup before it can be recovered."
        }
        return nil
    }

    private func diagnosticStep(ids: Set<String>) -> RuntimeDiagnosticStep? {
        target.diagnostics.first { ids.contains($0.id) }
    }

    private func appServerTitle(for action: RuntimeDiagnosticAction) -> String {
        switch action {
        case .installCodexCLI, .updateCodexCLI:
            return "Repair remote runtime"
        case .startAppServer, .restartAppServer:
            return "Restart/probe app-server"
        }
    }
}

private struct MachineRecoveryStepRowView: View {
    var step: MachineRecoveryStep
    var isRecommended: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            Image(systemName: step.status.icon)
                .foregroundStyle(step.status.color)
                .frame(width: 15)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(step.title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)

                    if isRecommended {
                        Text("Next")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }

                Text(step.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            if let actionTitle = step.actionTitle {
                if isRecommended {
                    FeedbackButton(
                        unavailableReason: step.unavailableReason,
                        action: step.action
                    ) {
                        Label(actionTitle, systemImage: step.actionIcon)
                            .labelStyle(.titleAndIcon)
                    }
                    .controlSize(.mini)
                    .buttonStyle(.borderedProminent)
                    .help(step.unavailableReason ?? step.summary)
                } else {
                    FeedbackButton(
                        unavailableReason: step.unavailableReason,
                        action: step.action
                    ) {
                        Label(actionTitle, systemImage: step.actionIcon)
                            .labelStyle(.titleAndIcon)
                    }
                    .controlSize(.mini)
                    .buttonStyle(.bordered)
                    .help(step.unavailableReason ?? step.summary)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(
            isRecommended ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isRecommended ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
        }
    }
}

private struct MachineRecoveryTarget: Identifiable {
    var id: HostID
    var machine: SupervisorMachine?
    var remote: CodexDesktopRemote?
    var attempt: RelayEndpointAttemptState?
    var diagnostics: [RuntimeDiagnosticStep]
    var hasSavedRoute: Bool

    var name: String {
        machine?.name ?? remote?.displayName ?? attempt?.endpointName ?? id.rawValue
    }

    var subtitle: String {
        let endpoint = machine?.endpointDescription
            ?? remote?.hostname
            ?? attempt?.endpointURL.absoluteString
            ?? "No endpoint"
        let platform = machine?.platform ?? remote?.platform ?? .unknown
        return "\(platform.rawValue) - \(endpoint)"
    }

    var statusLabel: String {
        if isBusy {
            return "running"
        }
        if needsIdentityPreparation {
            return "key prep"
        }
        if let status = machine?.status {
            return status.rawValue
        }
        if diagnostics.contains(where: { $0.status == .failed }) {
            return "failed"
        }
        return "setup"
    }

    var statusColor: Color {
        if isBusy {
            return .blue
        }
        if needsIdentityPreparation {
            return .orange
        }
        switch machine?.status {
        case .connected:
            return .green
        case .connecting:
            return .blue
        case .failed:
            return .orange
        case .disconnected, .none:
            return .secondary
        }
    }

    var isBusy: Bool {
        machine?.status == .connecting || diagnostics.contains { $0.status == .running }
    }

    var needsIdentityPreparation: Bool {
        guard let remote else { return false }
        return CodexRemoteIdentityStore.requiresPreparation(for: remote)
    }
}

private struct MachineRecoveryStep: Identifiable {
    var id: String
    var title: String
    var detail: String
    var status: RuntimeDiagnosticStatus
    var actionTitle: String?
    var actionIcon: String
    var unavailableReason: String?
    var action: () -> Void

    var summary: String {
        switch id {
        case "prepare-key":
            return "Prepare SSH key and connect"
        case "remove-route":
            return "Remove stale route"
        default:
            return title
        }
    }
}

private struct PendingIdentityRecovery {
    var remote: CodexDesktopRemote
    var action: RecoveryRemoteAction
}

private enum RecoveryRemoteAction {
    case diagnose
    case connect
}

private extension RuntimeDiagnosticStatus {
    var icon: String {
        switch self {
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

    var color: Color {
        switch self {
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
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct GraphCanvasSelectionInspectorLayer: View {
    @Bindable var graphStore: GraphStore
    var isVisible: Bool

    var body: some View {
        if isVisible {
            SelectionInspectorView(graphStore: graphStore)
                .padding(14)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
        }
    }
}
