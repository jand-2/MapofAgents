import MapofAgentsCore
import SwiftUI

struct CanvasEdgeGeometry {
    var start: CGPoint
    var control1: CGPoint
    var control2: CGPoint
    var end: CGPoint

    func point(at t: CGFloat) -> CGPoint {
        let oneMinusT = 1 - t
        let x = oneMinusT * oneMinusT * oneMinusT * start.x
            + 3 * oneMinusT * oneMinusT * t * control1.x
            + 3 * oneMinusT * t * t * control2.x
            + t * t * t * end.x
        let y = oneMinusT * oneMinusT * oneMinusT * start.y
            + 3 * oneMinusT * oneMinusT * t * control1.y
            + 3 * oneMinusT * t * t * control2.y
            + t * t * t * end.y
        return CGPoint(x: x, y: y)
    }

    func tangent(at t: CGFloat) -> CGPoint {
        let oneMinusT = 1 - t
        let x = 3 * oneMinusT * oneMinusT * (control1.x - start.x)
            + 6 * oneMinusT * t * (control2.x - control1.x)
            + 3 * t * t * (end.x - control2.x)
        let y = 3 * oneMinusT * oneMinusT * (control1.y - start.y)
            + 6 * oneMinusT * t * (control2.y - control1.y)
            + 3 * t * t * (end.y - control2.y)
        return CGPoint(x: x, y: y)
    }

    func normal(at t: CGFloat) -> CGPoint {
        let tangent = tangent(at: t)
        let length = max(0.01, hypot(tangent.x, tangent.y))
        return CGPoint(x: -tangent.y / length, y: tangent.x / length)
    }
}

enum CanvasEdgeGeometryResolver {
    private static let parallelWorkflowEdgeOffset: CGFloat = 10
    private static let visibleEndpointOutset: CGFloat = 5

    static func geometry(
        for edge: CanvasEdge,
        nodes: [NodeID: CanvasNode],
        visualOffset: CGFloat = 0
    ) -> CanvasEdgeGeometry? {
        guard let source = nodes[edge.source], let target = nodes[edge.target] else {
            return nil
        }
        return geometry(source: source, target: target, visualOffset: visualOffset)
    }

    static func parallelWorkflowEdgeOffsets(for edges: [CanvasEdge]) -> [EdgeID: CGFloat] {
        let workflowEdges = edges.filter { $0.kind == .threadMessage || $0.kind == .createdBy }
        let groups = Dictionary(grouping: workflowEdges) { edge in
            "\(edge.source.rawValue)->\(edge.target.rawValue)"
        }

        var offsets: [EdgeID: CGFloat] = [:]
        for group in groups.values where group.count > 1 {
            let ordered = group.sorted { lhs, rhs in
                let lhsRank = parallelEdgeRank(lhs)
                let rhsRank = parallelEdgeRank(rhs)
                if lhsRank == rhsRank {
                    return lhs.id.rawValue < rhs.id.rawValue
                }
                return lhsRank < rhsRank
            }
            let midpoint = CGFloat(ordered.count - 1) / 2
            for (index, edge) in ordered.enumerated() {
                offsets[edge.id] = (CGFloat(index) - midpoint) * parallelWorkflowEdgeOffset
            }
        }

        return offsets
    }

    private static func parallelEdgeRank(_ edge: CanvasEdge) -> Int {
        switch edge.kind {
        case .threadMessage:
            return 0
        case .createdBy:
            return 1
        case .machineFolder, .folderThread, .machineThread, .manualNote:
            return 2
        }
    }

    private static func geometry(source: CanvasNode, target: CanvasNode, visualOffset: CGFloat = 0) -> CanvasEdgeGeometry {
        let sourceCenter = CGPoint(source.position)
        let targetCenter = CGPoint(target.position)
        let centerDX = targetCenter.x - sourceCenter.x
        let centerDY = targetCenter.y - sourceCenter.y
        let centerLength = hypot(centerDX, centerDY)
        let normal = centerLength > 0.01
            ? CGPoint(x: -centerDY / centerLength, y: centerDX / centerLength)
            : .zero
        let sourceAim = CGPoint(
            x: targetCenter.x + normal.x * visualOffset,
            y: targetCenter.y + normal.y * visualOffset
        )
        let targetAim = CGPoint(
            x: sourceCenter.x + normal.x * visualOffset,
            y: sourceCenter.y + normal.y * visualOffset
        )
        let start = rectEdgePoint(center: sourceCenter, size: source.size, toward: sourceAim)
        let end = rectEdgePoint(center: targetCenter, size: target.size, toward: targetAim)

        let dx = end.x - start.x
        let dy = end.y - start.y
        if abs(dy) > abs(dx) * 1.25 {
            let sign: CGFloat = dy >= 0 ? 1 : -1
            let controlOffset = max(60, abs(dy) * 0.28)
            return CanvasEdgeGeometry(
                start: start,
                control1: CGPoint(x: start.x, y: start.y + sign * controlOffset),
                control2: CGPoint(x: end.x, y: end.y - sign * controlOffset),
                end: end
            )
        }

        let sign: CGFloat = dx >= 0 ? 1 : -1
        let controlOffset = max(60, abs(dx) * 0.28)
        return CanvasEdgeGeometry(
            start: start,
            control1: CGPoint(x: start.x + sign * controlOffset, y: start.y),
            control2: CGPoint(x: end.x - sign * controlOffset, y: end.y),
            end: end
        )
    }

    private static func rectEdgePoint(center: CGPoint, size: CanvasSize, toward point: CGPoint) -> CGPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        guard abs(dx) > 0.01 || abs(dy) > 0.01 else {
            return center
        }

        let halfWidth = CGFloat(size.width / 2)
        let halfHeight = CGFloat(size.height / 2)
        let scaleX = abs(dx) > 0.01 ? halfWidth / abs(dx) : CGFloat.greatestFiniteMagnitude
        let scaleY = abs(dy) > 0.01 ? halfHeight / abs(dy) : CGFloat.greatestFiniteMagnitude
        let scale = min(scaleX, scaleY)

        let length = max(0.01, hypot(dx, dy))
        return CGPoint(
            x: center.x + dx * scale + (dx / length) * visibleEndpointOutset,
            y: center.y + dy * scale + (dy / length) * visibleEndpointOutset
        )
    }
}
