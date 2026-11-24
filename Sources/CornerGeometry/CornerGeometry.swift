import CoreGraphics

public enum CornerRadius {
    public static let minimumForAgent: CGFloat = 24

    public static func effective(selected: CGFloat, agentHooksInstalled: Bool) -> CGFloat {
        agentHooksInstalled ? max(selected, minimumForAgent) : selected
    }
}

public enum AgentMenuGeometry {
    public static let edgeInset: CGFloat = 4
    public static let otherCornerLimit: CGFloat = 20

    public static func maskRadius(_ radius: CGFloat, on screen: CGRect) -> CGFloat {
        max(0, min(radius, screen.width / 2, screen.height / 2))
    }

    public static func menuRadius(maskRadius: CGFloat) -> CGFloat {
        max(0, maskRadius - edgeInset)
    }

    public static func otherRadius(maskRadius: CGFloat) -> CGFloat {
        min(otherCornerLimit, menuRadius(maskRadius: maskRadius))
    }

    public static func height(rowCount: Int, rowHeight: CGFloat, maskRadius: CGFloat) -> CGFloat {
        max(CGFloat(rowCount) * rowHeight,
            menuRadius(maskRadius: maskRadius) + otherRadius(maskRadius: maskRadius))
    }
}

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
