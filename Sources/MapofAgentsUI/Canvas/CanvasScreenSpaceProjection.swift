import CoreGraphics
import MapofAgentsCore

/// Projects graph coordinates while keeping interactive canvas content at a
/// readable, tappable screen-space size on touch devices.
enum CanvasScreenSpaceProjection {
    static func nodes(
        _ nodes: [NodeID: CanvasNode],
        viewport: CanvasViewport
    ) -> [NodeID: CanvasNode] {
        nodes.mapValues { node($0, viewport: viewport) }
    }

    static func node(
        _ node: CanvasNode,
        viewport: CanvasViewport
    ) -> CanvasNode {
        var projected = node
        projected.position = point(node.position, viewport: viewport)
        projected.size = CanvasSize(
            width: max(node.size.width, Double(AccessibleHitTarget.minimumDimension)),
            height: max(node.size.height, Double(AccessibleHitTarget.minimumDimension))
        )
        return projected
    }

    static func point(
        _ point: CanvasPoint,
        viewport: CanvasViewport
    ) -> CanvasPoint {
        CanvasPoint(
            x: point.x * viewport.scale + viewport.offset.x,
            y: point.y * viewport.scale + viewport.offset.y
        )
    }
}
