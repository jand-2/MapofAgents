import MapofAgentsCore
import SwiftUI

public struct UpdateCenterPopoverView: View {
    var updatePhase: CodexRuntimeUpdatePhase
    var installedCodexVersion: String?
    var runningCodexVersion: String?
    var updateMessage: String?
    var updateUnavailableReason: String?
    var onRefreshUpdateStatus: () -> Void
    var onUpdateCodexRuntime: () -> Void
    var onClose: () -> Void

    @State private var isConfirmingCodexUpdate = false

    public init(
        updatePhase: CodexRuntimeUpdatePhase,
        installedCodexVersion: String? = nil,
        runningCodexVersion: String? = nil,
        updateMessage: String? = nil,
        updateUnavailableReason: String? = nil,
        onRefreshUpdateStatus: @escaping () -> Void = {},
        onUpdateCodexRuntime: @escaping () -> Void = {},
        onClose: @escaping () -> Void = {}
    ) {
        self.updatePhase = updatePhase
        self.installedCodexVersion = installedCodexVersion
        self.runningCodexVersion = runningCodexVersion
        self.updateMessage = updateMessage
        self.updateUnavailableReason = updateUnavailableReason
        self.onRefreshUpdateStatus = onRefreshUpdateStatus
        self.onUpdateCodexRuntime = onUpdateCodexRuntime
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()

            codexRuntimeSection

            Divider()

            mapofAgentsSection
        }
        .padding(16)
        .frame(width: 390, alignment: .topLeading)
        .confirmationDialog(
            "Update Codex Runtime?",
            isPresented: $isConfirmingCodexUpdate,
            titleVisibility: .visible
        ) {
            Button("Update and Restart Runtime") {
                onUpdateCodexRuntime()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(runtimeRestartWarning)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Updates", systemImage: "arrow.down.circle")
                .font(.headline)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close updates")
            .accessibilityLabel("Close updates")
            .minimumAccessibleHitTarget()
        }
    }

    private var codexRuntimeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "terminal")
                    .font(.title3)
                    .foregroundStyle(codexStatusTint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Standalone Codex Runtime")
                        .font(.callout.weight(.semibold))

                    Text(updateMessage ?? updatePhase.updateDefaultMessage)
                        .font(.caption)
                        .foregroundStyle(updatePhase == .failed ? .red : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if updatePhase.isUpdateOperationBusy {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(updatePhase.updateAccessibilityDescription)
                } else {
                    Image(systemName: updatePhase.statusIcon)
                        .foregroundStyle(codexStatusTint)
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                versionRow("Installed", value: installedCodexVersion)
                versionRow("Running", value: runningCodexVersion)
            }
            .padding(10)
            .background(.background.opacity(0.34), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary, lineWidth: 1)
            }

            Label(runtimeRestartWarning, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(action: onRefreshUpdateStatus) {
                    Label("Check Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(updatePhase.isUpdateOperationBusy)
                .help(updatePhase.isUpdateOperationBusy ? "An update operation is already running" : "Refresh standalone Codex runtime status")

                Spacer()

                Button {
                    isConfirmingCodexUpdate = true
                } label: {
                    Label(updateActionTitle, systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(effectiveUpdateUnavailableReason != nil)
                .help(effectiveUpdateUnavailableReason ?? "Run the standalone Codex runtime's official updater")
                .accessibilityHint(effectiveUpdateUnavailableReason ?? runtimeRestartWarning)
            }

            if let effectiveUpdateUnavailableReason {
                Text(effectiveUpdateUnavailableReason)
                    .font(.caption2)
                    .foregroundStyle(updatePhase == .failed ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Update unavailable: \(effectiveUpdateUnavailableReason)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Standalone Codex Runtime updates")
    }

    private var mapofAgentsSection: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "app.badge")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("MapofAgents App")
                        .font(.callout.weight(.semibold))

                    Text("Coming Later")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }

                Text("MapofAgents app updates will appear here in a future release.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func versionRow(_ label: String, value: String?) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text((value?.isEmpty == false ? value : nil) ?? "Not detected")
                .fontDesign(.monospaced)
                .textSelection(.enabled)
        }
        .font(.caption)
    }

    private var codexStatusTint: Color {
        switch updatePhase {
        case .succeeded:
            return .green
        case .failed:
            return .red
        case .checking, .updating, .restarting, .reconnecting:
            return .blue
        case .idle:
            return .secondary
        }
    }

    private var updateActionTitle: String {
        switch updatePhase {
        case .updating:
            return "Updating"
        case .restarting:
            return "Restarting"
        case .reconnecting:
            return "Reconnecting"
        default:
            return "Update Codex"
        }
    }

    private var effectiveUpdateUnavailableReason: String? {
        if updatePhase.isUpdateOperationBusy {
            return "The Codex runtime update is already in progress."
        }
        return updateUnavailableReason
    }

    private var runtimeRestartWarning: String {
        "This runs the standalone Codex updater, then restarts only the local runtime. MapofAgents and other local clients may disconnect briefly; paired and remote runtimes are left running."
    }
}

extension CodexRuntimeUpdatePhase {
    var isUpdateOperationBusy: Bool {
        switch self {
        case .checking, .updating, .restarting, .reconnecting:
            return true
        case .idle, .succeeded, .failed:
            return false
        }
    }

    var updateDefaultMessage: String {
        switch self {
        case .idle:
            return "Check the installed and running standalone Codex versions."
        case .checking:
            return "Checking the Codex runtime version."
        case .updating:
            return "Installing the standalone Codex runtime update."
        case .restarting:
            return "Restarting the local Codex runtime."
        case .reconnecting:
            return "Reconnecting MapofAgents to Codex."
        case .succeeded:
            return "The standalone Codex runtime is up to date and connected."
        case .failed:
            return "The Codex runtime update did not complete."
        }
    }

    var updateAccessibilityDescription: String {
        switch self {
        case .idle:
            return "Ready to check for updates"
        case .checking:
            return "Checking for updates"
        case .updating:
            return "Updating Codex runtime"
        case .restarting:
            return "Restarting Codex runtime"
        case .reconnecting:
            return "Reconnecting to Codex runtime"
        case .succeeded:
            return "Codex runtime update succeeded"
        case .failed:
            return "Codex runtime update failed"
        }
    }

    var statusIcon: String {
        switch self {
        case .succeeded:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .idle:
            return "arrow.down.circle"
        case .checking, .updating, .restarting, .reconnecting:
            return "arrow.triangle.2.circlepath"
        }
    }
}
