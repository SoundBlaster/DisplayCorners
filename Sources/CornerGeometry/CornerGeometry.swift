import CoreGraphics

public enum Corner: CaseIterable, Sendable {
    case bottomLeft, bottomRight, topLeft, topRight

    public var isTop: Bool { self == .topLeft || self == .topRight }
    public var isRight: Bool { self == .bottomRight || self == .topRight }

    public func frame(on screen: CGRect, radius: CGFloat) -> CGRect {
        let size = max(0, min(radius, screen.width / 2, screen.height / 2))
        return CGRect(
            x: isRight ? screen.maxX - size : screen.minX,
            y: isTop ? screen.maxY - size : screen.minY,
            width: size, height: size
        )
    }
}
