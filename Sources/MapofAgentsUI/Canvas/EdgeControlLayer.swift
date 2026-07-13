import MapofAgentsCore
import SwiftUI

struct EdgeControlLayer: View {
    var nodes: [NodeID: CanvasNode]
    var edges: [CanvasEdge]
    var selectedEdge: EdgeID?
    var onSelect: (EdgeID) -> Void

    var body: some View {
        let visualOffsets = CanvasEdgeGeometryResolver.parallelWorkflowEdgeOffsets(for: edges)
        ForEach(edges) { edge in
            if let position = labelPosition(for: edge, visualOffset: visualOffsets[edge.id] ?? 0) {
                let style = labelStyle(for: edge)

                Button {
                    onSelect(edge.id)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: style.icon)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(selectedEdge == edge.id ? .white : style.tint)
                        Text(label(for: edge))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minWidth: 44, minHeight: 28)
                    .minimumAccessibleHitTarget()
                    .background {
                        Capsule()
                            .fill(selectedEdge == edge.id ? style.tint.opacity(0.92) : Color.black.opacity(0.72))
                    }
                    .overlay {
                        Capsule()
                            .stroke(style.tint.opacity(selectedEdge == edge.id ? 1 : 0.76), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.28), radius: 5, x: 0, y: 2)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .position(position)
                .help(style.help)
                .accessibilityLabel(accessibilityLabel(for: edge))
                .accessibilityValue(selectedEdge == edge.id ? "Selected" : "Not selected")
                .accessibilityAddTraits(selectedEdge == edge.id ? [.isSelected] : [])
            }
        }
    }

    private func labelPosition(for edge: CanvasEdge, visualOffset: CGFloat) -> CGPoint? {
        guard let geometry = CanvasEdgeGeometryResolver.geometry(for: edge, nodes: nodes, visualOffset: visualOffset) else {
            return nil
        }

        let midpoint = geometry.point(at: 0.5)
        let perpendicular = geometry.normal(at: 0.5)
        let offset = labelOffset(for: edge.kind)

        return CGPoint(
            x: midpoint.x + perpendicular.x * offset,
            y: midpoint.y + perpendicular.y * offset
        )
    }

    private func label(for edge: CanvasEdge) -> String {
        let customLabel = edge.label?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let customLabel, !customLabel.isEmpty {
            switch (edge.kind, customLabel.lowercased()) {
            case (.createdBy, "created by"):
                return "created"
            default:
                return customLabel
            }
        }

        switch edge.kind {
        case .machineFolder:
            return "folder"
        case .folderThread:
            return "thread"
        case .machineThread:
            return "thread"
        case .manualNote:
            return "note"
        case .threadMessage:
            return "message"
        case .createdBy:
            return "created"
        }
    }

    private func accessibilityLabel(for edge: CanvasEdge) -> String {
        "\(label(for: edge)) line"
    }

    private func labelStyle(for edge: CanvasEdge) -> EdgeLabelStyle {
        switch edge.kind {
        case .machineFolder:
            return EdgeLabelStyle(icon: "folder.fill", tint: .secondary, help: "Edit folder link")
        case .folderThread, .machineThread:
            return EdgeLabelStyle(icon: "bubble.left.fill", tint: .secondary, help: "Edit thread link")
        case .manualNote:
            return EdgeLabelStyle(icon: "note.text", tint: .green, help: "Edit note link")
        case .threadMessage:
            return EdgeLabelStyle(icon: "bubble.left.and.bubble.right.fill", tint: .blue, help: "Edit message link")
        case .createdBy:
            return EdgeLabelStyle(icon: "plus.circle.fill", tint: .orange, help: "Edit created thread link")
        }
    }

    private func labelOffset(for kind: EdgeKind) -> CGFloat {
        switch kind {
        case .threadMessage:
            return -16
        case .createdBy:
            return 16
        case .manualNote:
            return 14
        case .machineFolder, .folderThread, .machineThread:
            return 12
        }
    }
}

private struct EdgeLabelStyle {
    var icon: String
    var tint: Color
    var help: String
}
