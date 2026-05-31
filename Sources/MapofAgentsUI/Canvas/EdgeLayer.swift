import MapofAgentsCore
import SwiftUI

struct EdgeLayer: View {
    var nodes: [NodeID: CanvasNode]
    var edges: [CanvasEdge]
    var selectedEdge: EdgeID?
    var focusedNodeID: NodeID?
    var onSelect: (EdgeID) -> Void

    var body: some View {
        Canvas { context, _ in
            let visualOffsets = CanvasEdgeGeometryResolver.parallelWorkflowEdgeOffsets(for: edges)
            for edge in edges {
                guard let geometry = CanvasEdgeGeometryResolver.geometry(
                    for: edge,
                    nodes: nodes,
                    visualOffset: visualOffsets[edge.id] ?? 0
                ) else {
                    continue
                }

                var path = Path()
                path.move(to: geometry.start)
                path.addCurve(
                    to: geometry.end,
                    control1: geometry.control1,
                    control2: geometry.control2
                )

                let isSelected = selectedEdge == edge.id
                let edgeColor = color(for: edge, selected: isSelected)
                let opacity = opacity(for: edge, selected: isSelected)

                context.stroke(
                    path,
                    with: .color(edgeColor.opacity(opacity)),
                    style: StrokeStyle(
                        lineWidth: isSelected ? 4 : 3,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: dash(for: edge)
                    )
                )

                if showsArrow(for: edge) {
                    var connectorPath = Path()
                    connectorPath.move(to: geometry.point(at: 0.93))
                    connectorPath.addLine(to: geometry.end)
                    context.stroke(
                        connectorPath,
                        with: .color(edgeColor.opacity(opacity)),
                        style: StrokeStyle(
                            lineWidth: isSelected ? 4 : 3,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
                }

                if showsArrow(for: edge),
                   let arrowPath = arrowHeadPath(
                    tip: geometry.end,
                    tail: geometry.point(at: 0.9),
                    size: isSelected ? 14 : 11
                   ) {
                    context.fill(arrowPath, with: .color(edgeColor.opacity(opacity)))
                }

                if !edge.isManual, let label = edge.label, !label.isEmpty {
                    let midpoint = geometry.point(at: 0.5)
                    context.draw(
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(edgeColor),
                        at: midpoint
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func color(for edge: CanvasEdge, selected: Bool) -> Color {
        if selected {
            return .accentColor
        }

        switch edge.kind {
        case .machineFolder, .folderThread, .machineThread:
            return .secondary.opacity(0.52)
        case .manualNote:
            return .green.opacity(0.72)
        case .threadMessage:
            return .blue.opacity(0.78)
        case .createdBy:
            return .orange.opacity(0.82)
        }
    }

    private func opacity(for edge: CanvasEdge, selected: Bool) -> Double {
        guard let focusedNodeID else {
            return 1
        }
        if selected || edge.source == focusedNodeID || edge.target == focusedNodeID {
            return 1
        }
        return 0.18
    }

    private func dash(for edge: CanvasEdge) -> [CGFloat] {
        switch edge.kind {
        case .manualNote, .threadMessage, .createdBy:
            return [9, 8]
        default:
            return []
        }
    }

    private func showsArrow(for edge: CanvasEdge) -> Bool {
        switch edge.kind {
        case .threadMessage, .createdBy:
            return true
        case .machineFolder, .folderThread, .machineThread, .manualNote:
            return false
        }
    }

    private func arrowHeadPath(tip: CGPoint, tail: CGPoint, size: CGFloat) -> Path? {
        let dx = tip.x - tail.x
        let dy = tip.y - tail.y
        let length = hypot(dx, dy)
        guard length > 0.01 else {
            return nil
        }

        let unitX = dx / length
        let unitY = dy / length
        let perpendicularX = -unitY
        let perpendicularY = unitX
        let base = CGPoint(x: tip.x - unitX * size, y: tip.y - unitY * size)
        let halfWidth = size * 0.46

        var path = Path()
        path.move(to: tip)
        path.addLine(to: CGPoint(x: base.x + perpendicularX * halfWidth, y: base.y + perpendicularY * halfWidth))
        path.addLine(to: CGPoint(x: base.x - perpendicularX * halfWidth, y: base.y - perpendicularY * halfWidth))
        path.closeSubpath()
        return path
    }
}
