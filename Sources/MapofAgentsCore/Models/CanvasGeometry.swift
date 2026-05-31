import Foundation

public struct CanvasPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = CanvasPoint(x: 0, y: 0)

    public func offsetBy(dx: Double, dy: Double) -> CanvasPoint {
        CanvasPoint(x: x + dx, y: y + dy)
    }
}

public struct CanvasSize: Codable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let machine = CanvasSize(width: 190, height: 90)
    public static let folder = CanvasSize(width: 210, height: 96)
    public static let thread = CanvasSize(width: 200, height: 132)
}

public struct CanvasViewport: Codable, Hashable, Sendable {
    public var scale: Double
    public var offset: CanvasPoint

    public init(scale: Double = 1, offset: CanvasPoint = .zero) {
        self.scale = scale
        self.offset = offset
    }

    public static let standard = CanvasViewport()
}
