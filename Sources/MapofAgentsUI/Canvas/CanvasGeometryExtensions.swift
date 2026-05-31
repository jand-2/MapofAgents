import MapofAgentsCore
import CoreGraphics
import Foundation

extension CGPoint {
    init(_ point: CanvasPoint) {
        self.init(x: point.x, y: point.y)
    }
}

extension CGSize {
    init(_ size: CanvasSize) {
        self.init(width: size.width, height: size.height)
    }
}

extension CanvasPoint {
    init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
    }

    func translated(by size: CGSize) -> CanvasPoint {
        CanvasPoint(x: x + size.width, y: y + size.height)
    }
}
