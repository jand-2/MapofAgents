import MapofAgentsCore
import SwiftUI

struct NodeView: View {
    var node: CanvasNode
    var isSelected: Bool
    var isManualEdgeSource: Bool
    var hasPendingManualEdge: Bool
    var isHighlighted: Bool = false
    var defaultMachineFolderPath: String?
    var liveState: ThreadLiveStateSummary?
    var threadAutomation: CodexAutomationSummary?
    var onChooseMachineFolder: (() -> Void)?
    var onAddMachineFolder: ((String) -> Void)?
    var onOpenThreadAutomation: () -> Void = {}
    var onLinkAction: () -> Void
    var onControlTap: () -> Void = {}
    var onActivate: () -> Void = {}

    @State private var isShowingFolderPath = false
    @State private var folderPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 24, height: 24)
                    .background(accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(node.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .layoutPriority(1)

                        if node.kind == .codexThread && threadKind == .subagent {
                            Text("agent")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.purple)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.12), in: Capsule())
                                .help("Subagent thread")
                        }

                        if isUnreadThread {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 7, height: 7)
                                .accessibilityLabel("Unread")
                        }
                    }

                    if !node.subtitle.isEmpty {
                        Text(node.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 4)

                if node.kind == .codexThread,
                   let threadAutomation {
                    Button {
                        onControlTap()
                        onOpenThreadAutomation()
                    } label: {
                        Image(systemName: "alarm")
                            .symbolVariant(threadAutomation.isActive ? .fill : .none)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(threadAutomation.isActive ? .orange : .secondary)
                    .help(automationHelp(threadAutomation))
                    .accessibilityLabel("Thread automation")
                    .accessibilityValue(automationHelp(threadAutomation))
                    .minimumAccessibleHitTarget()
                }

                if shouldShowMachineFolderButton {
                    FeedbackButton(
                        unavailableReason: machineFolderUnavailableReason,
                        action: {
                            onControlTap()
                            if let onChooseMachineFolder {
                                onChooseMachineFolder()
                            } else {
                                folderPath = folderPath.isEmpty ? (defaultMachineFolderPath ?? "") : folderPath
                                isShowingFolderPath.toggle()
                            }
                        }
                    ) {
                        Image(systemName: "folder.badge.plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(machineFolderUnavailableReason ?? (onChooseMachineFolder == nil ? "Add project from this machine" : "Choose project from this machine"))
                    .accessibilityLabel(onChooseMachineFolder == nil ? "Add project from this machine" : "Choose project from this machine")
                    .accessibilityValue(machineFolderUnavailableReason ?? "")
                    .popover(isPresented: $isShowingFolderPath, arrowEdge: .trailing) {
                        machineFolderPathPopover
                    }
                    .minimumAccessibleHitTarget()
                }

                Button {
                    onControlTap()
                    onLinkAction()
                } label: {
                    Image(systemName: linkIconName)
                }
                .buttonStyle(.plain)
                .foregroundStyle(isManualEdgeSource || hasPendingManualEdge ? .green : .secondary)
                .help(linkHelp)
                .accessibilityLabel(linkHelp)
                .minimumAccessibleHitTarget()
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                statusPill

                if let liveState, node.kind == .codexThread {
                    ThreadNodeUpdatedText(summary: liveState)
                }

                Spacer(minLength: 0)

                if let model = node.metadata.model {
                    Text(model)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }

                if let effort = node.metadata.reasoningEffort {
                    Text(effort)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: isSelected || isManualEdgeSource ? 3 : 2)
        }
        .overlay {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor.opacity(0.85), lineWidth: 4)
                    .padding(-5)
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 10)
            }
        }
        .shadow(color: .black.opacity(isSelected || isHighlighted ? 0.18 : 0.08), radius: isSelected || isHighlighted ? 12 : 6, x: 0, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(nodeKindLabel): \(node.title)")
        .accessibilityValue(accessibilityStatus)
        .accessibilityAction(.default, onActivate)
        .accessibilityAction(named: Text(linkHelp), onLinkAction)
    }

    private var shouldShowMachineFolderButton: Bool {
        node.kind == .machine
    }

    private var nodeKindLabel: String {
        switch node.kind {
        case .machine:
            return "Machine"
        case .folder:
            return "Project folder"
        case .codexThread:
            return threadKind == .subagent ? "Subagent thread" : "Codex thread"
        }
    }

    private var accessibilityStatus: String {
        switch node.kind {
        case .machine:
            return statusLabel(node.metadata.hostStatus ?? .disconnected)
        case .folder:
            return node.subtitle
        case .codexThread:
            let unread = isUnreadThread ? "unread, " : ""
            return "\(unread)\((node.metadata.runStatus ?? .unknown).rawValue)"
        }
    }

    private var isUnreadThread: Bool {
        node.kind == .codexThread && node.metadata.isUnread == true
    }

    private var machineFolderUnavailableReason: String? {
        guard node.kind == .machine else { return nil }
        if onChooseMachineFolder != nil || onAddMachineFolder != nil {
            return nil
        }
        if node.metadata.hostStatus != .connected {
            return "Connect this machine before adding a project folder."
        }
        return "This app cannot add folders from this machine yet."
    }

    private var machineFolderPathPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                    .foregroundStyle(.yellow)
                Text("Add Project")
                    .font(.headline)
                Spacer()
            }

            TextField(defaultMachineFolderPath ?? "Folder path", text: $folderPath)
                .textFieldStyle(.roundedBorder)
                .onSubmit(addMachineFolder)

            HStack {
                Spacer()

                Button("Cancel") {
                    isShowingFolderPath = false
                }
                .keyboardShortcut(.cancelAction)

                FeedbackButton(
                    unavailableReason: folderPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Enter a folder path before adding it." : nil,
                    action: {
                        onControlTap()
                        addMachineFolder()
                    }
                ) {
                    Label("Add", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private func addMachineFolder() {
        let path = folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        onAddMachineFolder?(path)
        folderPath = ""
        isShowingFolderPath = false
    }

    private var iconName: String {
        switch node.kind {
        case .machine:
            return "cpu"
        case .folder:
            return "folder"
        case .codexThread:
            return threadKind == .subagent ? "person.2" : "bubble.left.and.bubble.right"
        }
    }

    private var linkIconName: String {
        if isManualEdgeSource {
            return "xmark.circle"
        }
        return hasPendingManualEdge ? "checkmark.circle" : "point.3.connected.trianglepath.dotted"
    }

    private var linkHelp: String {
        if isManualEdgeSource {
            return "Cancel connection"
        }
        return hasPendingManualEdge ? "Complete connection" : "Draw connection"
    }

    private func automationHelp(_ automation: CodexAutomationSummary) -> String {
        let state = automation.isActive ? "active" : "paused"
        return "\(automation.name) automation is \(state)"
    }

    private var accentColor: Color {
        switch node.kind {
        case .machine:
            return .green
        case .folder:
            return .yellow
        case .codexThread:
            return threadKind == .subagent ? .purple : .blue
        }
    }

    private var borderColor: Color {
        if isManualEdgeSource {
            return .green
        }

        if isSelected {
            return .accentColor
        }

        if isHighlighted {
            return .accentColor.opacity(0.9)
        }

        switch node.kind {
        case .machine:
            return .green.opacity(0.72)
        case .folder:
            return .yellow.opacity(0.82)
        case .codexThread:
            return (threadKind == .subagent ? Color.purple : Color.blue).opacity(0.78)
        }
    }

    private var threadKind: CodexThreadNodeKind {
        node.metadata.threadKind ?? .thread
    }

    @ViewBuilder
    private var statusPill: some View {
        switch node.kind {
        case .machine:
            let status = node.metadata.hostStatus ?? .disconnected
            Text(statusLabel(status))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(status == .connected ? .green : .secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background((status == .connected ? Color.green : Color.secondary).opacity(0.10), in: Capsule())
        case .folder:
            Text("folder")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        case .codexThread:
            if isUnreadThread {
                Label("unread", systemImage: "circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.10), in: Capsule())
            } else {
                let status = node.metadata.runStatus ?? .unknown
                Label(status.rawValue, systemImage: statusIcon(status))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusColor(status))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(statusColor(status).opacity(0.10), in: Capsule())
            }
        }
    }

    private func statusColor(_ status: ThreadRunStatus) -> Color {
        switch status {
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

    private func statusIcon(_ status: ThreadRunStatus) -> String {
        switch status {
        case .running:
            return "arrow.triangle.2.circlepath"
        case .needsInput:
            return "exclamationmark.bubble"
        case .failed:
            return "xmark.octagon"
        case .complete:
            return "checkmark.circle"
        case .idle, .unknown:
            return "circle"
        }
    }

    private func statusLabel(_ status: HostStatus) -> String {
        switch status {
        case .connected:
            return "connected"
        case .connecting:
            return "connecting"
        case .disconnected:
            return "offline"
        case .unavailable:
            return "runtime failed"
        }
    }
}

private struct ThreadNodeUpdatedText: View {
    var summary: ThreadLiveStateSummary

    var body: some View {
        Text(relativeUpdatedText)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
        .help(helpText)
    }

    private var relativeUpdatedText: String {
        let age = Date().timeIntervalSince(summary.updatedAt)
        if abs(age) < 5 {
            return "updated now"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "updated \(formatter.localizedString(for: summary.updatedAt, relativeTo: Date()))"
    }

    private var helpText: String {
        if let detail = summary.detail, !detail.isEmpty {
            return "\(summary.title): \(detail)"
        }
        return summary.title
    }

}
