import MapofAgentsCore
import SwiftUI

struct StatusStrip: View {
    @Bindable var graphStore: GraphStore
    @Bindable var runtimeStore: CodexRuntimeStore
    @Bindable var supervisorStore: WorkflowSupervisorStore

    var body: some View {
        HStack(spacing: 12) {
            Label("Local: \(runtimeStore.statusMessage)", systemImage: runtimeIcon)
                .foregroundStyle(runtimeColor)
                .help(runtimeStore.statusMessage)

            Divider()
                .frame(height: 16)

            Label(remoteSummaryText, systemImage: remoteIcon)
                .foregroundStyle(remoteColor)
                .help(remoteHelpText)

            Divider()
                .frame(height: 16)

            Text("\(graphStore.graph.nodes.count) nodes")
            Text("\(graphStore.allEdges.count) lines")

            if let message = graphStore.errorMessage {
                Divider()
                    .frame(height: 16)
                Text(message)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .help(message)
                    .accessibilityLabel("Canvas error")
                    .accessibilityValue(message)
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var runtimeIcon: String {
        switch runtimeStore.connectionState {
        case .connected:
            return "checkmark.circle.fill"
        case .connecting:
            return "arrow.triangle.2.circlepath"
        case .disconnected:
            return "circle"
        case .unavailable:
            return "exclamationmark.triangle.fill"
        }
    }

    private var runtimeColor: Color {
        switch runtimeStore.connectionState {
        case .connected:
            return .green
        case .connecting:
            return .blue
        case .disconnected:
            return .secondary
        case .unavailable:
            return .orange
        }
    }

    private var remoteSummaryText: String {
        let connected = supervisorStore.machines.filter { $0.status == .connected }.count
        let failed = supervisorStore.machines.filter { $0.status == .failed }.count
        if failed > 0 {
            return "\(connected) connected, \(failed) host issue\(failed == 1 ? "" : "s")"
        }
        return "\(connected) remote\(connected == 1 ? "" : "s") connected"
    }

    private var remoteHelpText: String {
        let failed = supervisorStore.machines
            .filter { $0.status == .failed }
            .map { "\($0.name): \($0.lastError ?? "failed")" }
        if failed.isEmpty {
            return "Remote App Server and tunnel status looks stable."
        }
        return failed.joined(separator: "\n")
    }

    private var remoteIcon: String {
        supervisorStore.machines.contains { $0.status == .failed }
            ? "exclamationmark.triangle.fill"
            : "antenna.radiowaves.left.and.right"
    }

    private var remoteColor: Color {
        supervisorStore.machines.contains { $0.status == .failed } ? .orange : .secondary
    }
}
