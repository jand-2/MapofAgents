import MapofAgentsCore
import SwiftUI

#if os(macOS)
import AppKit
#endif

struct CodexRemoteDiagnosticsPopoutView: View {
    @Bindable var supervisorStore: WorkflowSupervisorStore
    var remote: CodexDesktopRemote
    var onConnect: () -> Void
    var onDiagnose: () -> Void
    var onAction: (RuntimeDiagnosticAction) -> Void
    var onClose: () -> Void

    @State private var copiedReportAt: Date?

    private var steps: [RuntimeDiagnosticStep] {
        supervisorStore.codexRemoteDiagnostics[remote.id] ?? []
    }

    private var isBusy: Bool {
        steps.contains { $0.status == .running }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            summaryStrip
            stepList
        }
        .padding(18)
        .frame(minWidth: 720, idealWidth: 820, minHeight: 520, idealHeight: 640)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "stethoscope")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(remote.displayName)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)

                Text(remote.hostname ?? remote.hostID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            Button {
                onDiagnose()
            } label: {
                Label("Re-run", systemImage: "arrow.clockwise")
            }
            .disabled(isBusy || !remote.isConnectable)
            .help(remote.isConnectable ? "Run the full remote diagnostic again" : "This remote needs SSH setup before diagnostics can run")

            Button {
                onConnect()
            } label: {
                Label("Connect", systemImage: "antenna.radiowaves.left.and.right")
            }
            .disabled(isBusy || !remote.isConnectable)
            .help(remote.isConnectable ? "Start the remote App Server and attach the workflow relay" : "This remote needs SSH setup before it can connect")

            Button {
                copyReport()
            } label: {
                Label(copiedReportAt == nil ? "Copy Report" : "Copied", systemImage: copiedReportAt == nil ? "doc.on.doc" : "checkmark")
            }
            .help("Copy a token-redacted diagnostic report")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Close")
        }
    }

    private var summaryStrip: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                summaryCell("Platform", remote.platform.rawValue, systemImage: "desktopcomputer")
                summaryCell("SSH", remote.hostname ?? "Missing", systemImage: "terminal")
                summaryCell("Port", remote.sshPort.map(String.init) ?? "Default", systemImage: "number")
            }
            GridRow {
                summaryCell("Identity", remote.identityPath?.isEmpty == false ? "Configured" : "SSH config/default", systemImage: "key")
                summaryCell(
                    "App Server Ports",
                    CodexRemoteTunnelService.remoteAppServerPortCandidates(for: remote).map(String.init).joined(separator: ", "),
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
                summaryCell("Steps", "\(completedStepCount)/\(steps.count)", systemImage: "checklist")
            }
        }
        .padding(10)
        .background(.background.opacity(0.34), in: RoundedRectangle(cornerRadius: 8))
    }

    private func summaryCell(_ title: String, _ value: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Diagnostic Steps")
                    .font(.headline)
                Spacer()
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if steps.isEmpty {
                ContentUnavailableView(
                    "No diagnostics yet",
                    systemImage: "stethoscope",
                    description: Text("Run diagnostics or connect this remote to collect SSH, App Server, tunnel, and relay evidence.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(steps) { step in
                            CodexRemoteDiagnosticsPopoutStepView(
                                step: step,
                                isBusy: isBusy,
                                onAction: onAction
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var completedStepCount: Int {
        steps.filter { $0.status == .passed || $0.status == .warning }.count
    }

    private func copyReport() {
        let report = CodexRemoteTunnelService.debugReport(for: remote, steps: steps)
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        #endif
        copiedReportAt = Date()
    }
}

private struct CodexRemoteDiagnosticsPopoutStepView: View {
    var step: RuntimeDiagnosticStep
    var isBusy: Bool
    var onAction: (RuntimeDiagnosticAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 18)

                Text(step.title)
                    .font(.callout.weight(.semibold))

                Text(step.status.rawValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.12), in: Capsule())

                Spacer()

                if let action = step.action {
                    FeedbackButton(
                        unavailableReason: isBusy ? "Wait for the current remote operation to finish." : nil,
                        action: {
                            onAction(action)
                        }
                    ) {
                        Label(action.label, systemImage: action.icon)
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .help(action.help)
                }
            }

            if !step.detail.isEmpty {
                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if !step.evidence.isEmpty {
                Text(step.evidence)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(10)
        .background(.background.opacity(0.30), in: RoundedRectangle(cornerRadius: 8))
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

#if os(macOS)
@MainActor
final class CodexRemoteDiagnosticsWindowPresenter: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var onClose: (() -> Void)?

    init(
        supervisorStore: WorkflowSupervisorStore,
        remote: CodexDesktopRemote,
        onConnect: @escaping () -> Void,
        onDiagnose: @escaping () -> Void,
        onAction: @escaping (RuntimeDiagnosticAction) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose
        super.init()

        let content = CodexRemoteDiagnosticsPopoutView(
            supervisorStore: supervisorStore,
            remote: remote,
            onConnect: onConnect,
            onDiagnose: onDiagnose,
            onAction: onAction,
            onClose: { [weak self] in
                self?.window?.close()
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Remote Diagnostics"
        window.contentView = NSHostingView(rootView: content)
        window.delegate = self
        window.isReleasedWhenClosed = false
        self.window = window
    }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
        onClose = nil
        window = nil
    }
}
#endif
