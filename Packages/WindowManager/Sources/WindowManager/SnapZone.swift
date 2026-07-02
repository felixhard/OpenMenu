import CoreGraphics

/// The two tiling layouts the user defined: halves (sides) and quadrants (corners).
public enum SnapLayout: Equatable {
    case twoTile   // left / right halves
    case fourTile  // 2×2 quadrants

    var zones: [SnapZone] {
        switch self {
        case .twoTile:  return [.left, .right]
        case .fourTile: return [.topLeft, .topRight, .bottomLeft, .bottomRight]
        }
    }
}

/// A single target tile.
public enum SnapZone: Hashable {
    case left, right
    case topLeft, topRight, bottomLeft, bottomRight

    /// Drawing rect in unit space, top-left origin (y down) — for the overlay.
    var unitRect: CGRect {
        switch self {
        case .left:        return CGRect(x: 0,   y: 0,   width: 0.5, height: 1)
        case .right:       return CGRect(x: 0.5, y: 0,   width: 0.5, height: 1)
        case .topLeft:     return CGRect(x: 0,   y: 0,   width: 0.5, height: 0.5)
        case .topRight:    return CGRect(x: 0.5, y: 0,   width: 0.5, height: 0.5)
        case .bottomLeft:  return CGRect(x: 0,   y: 0.5, width: 0.5, height: 0.5)
        case .bottomRight: return CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
        }
    }

    /// The tile's full rect (no gap) in Cocoa screen coordinates (bottom-left origin).
    func baseCocoaFrame(in f: CGRect) -> CGRect {
        let halfW = f.width / 2
        let halfH = f.height / 2
        switch self {
        case .left:        return CGRect(x: f.minX, y: f.minY, width: halfW, height: f.height)
        case .right:       return CGRect(x: f.midX, y: f.minY, width: halfW, height: f.height)
        case .topLeft:     return CGRect(x: f.minX, y: f.midY, width: halfW, height: halfH)
        case .topRight:    return CGRect(x: f.midX, y: f.midY, width: halfW, height: halfH)
        case .bottomLeft:  return CGRect(x: f.minX, y: f.minY, width: halfW, height: halfH)
        case .bottomRight: return CGRect(x: f.midX, y: f.minY, width: halfW, height: halfH)
        }
    }

    /// Target window frame in Cocoa screen coordinates, inset by the snap gaps so
    /// tiled windows leave a uniform gap between each other and the screen edges.
    /// This is the *same* geometry the overlay previews, so they match exactly.
    func cocoaFrame(in f: CGRect,
                    edge: CGFloat = SnapGeometry.edgePadding,
                    inner: CGFloat = SnapGeometry.innerGap) -> CGRect {
        SnapGeometry.applyGap(to: baseCocoaFrame(in: f), in: f, edge: edge, inner: inner)
    }
}

public struct SnapTarget: Equatable {
    public let layout: SnapLayout
    public let zone: SnapZone
}

/// Maps a cursor location to a snap target: corners → quadrants, side-middles → halves.
public enum SnapGeometry {
    /// Unscaled distance from a corner (along both axes) that counts as "in the corner".
    public static let baseCornerSize: CGFloat = 100
    /// Unscaled distance from the left/right edge that counts as a side-middle hit.
    public static let baseEdgeSize: CGFloat = 28

    /// Distance from a corner (along both axes) that counts as "in the corner".
    public static var cornerSize: CGFloat = baseCornerSize
    /// Distance from the left/right edge that counts as a side-middle hit.
    public static var edgeSize: CGFloat = baseEdgeSize
    /// Gap (points) left between two neighbouring tiles.
    public static var innerGap: CGFloat = 8
    /// Padding (points) left between tiles and the screen edges. Tiles sit flush
    /// against the edges by default; only the inner gap is user-configurable.
    public static var edgePadding: CGFloat = 0

    /// Scales the corner/edge trigger areas from their base sizes (1 = default).
    public static func setTriggerScale(_ scale: CGFloat) {
        cornerSize = baseCornerSize * scale
        edgeSize = baseEdgeSize * scale
    }

    /// Insets `base` so it leaves `edge` against the screen edges and `inner`
    /// total between neighbours (half on each shared interior edge). Coordinate-
    /// system agnostic: pass `base` and `container` in the same space.
    public static func applyGap(to base: CGRect, in container: CGRect,
                                edge: CGFloat = SnapGeometry.edgePadding,
                                inner: CGFloat = SnapGeometry.innerGap) -> CGRect {
        let half = inner / 2
        func touches(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.5 }
        let left   = touches(base.minX, container.minX) ? edge : half
        let right  = touches(base.maxX, container.maxX) ? edge : half
        let bottom = touches(base.minY, container.minY) ? edge : half
        let top    = touches(base.maxY, container.maxY) ? edge : half
        return CGRect(x: base.minX + left,
                      y: base.minY + bottom,
                      width: max(0, base.width - left - right),
                      height: max(0, base.height - bottom - top))
    }

    public static func target(at mouse: CGPoint, in f: CGRect) -> SnapTarget? {
        let nearLeft   = mouse.x <= f.minX + cornerSize
        let nearRight  = mouse.x >= f.maxX - cornerSize
        let nearTop    = mouse.y >= f.maxY - cornerSize   // Cocoa: top = high y
        let nearBottom = mouse.y <= f.minY + cornerSize

        // Corners → quadrants.
        if nearLeft && nearTop    { return SnapTarget(layout: .fourTile, zone: .topLeft) }
        if nearRight && nearTop   { return SnapTarget(layout: .fourTile, zone: .topRight) }
        if nearLeft && nearBottom { return SnapTarget(layout: .fourTile, zone: .bottomLeft) }
        if nearRight && nearBottom { return SnapTarget(layout: .fourTile, zone: .bottomRight) }

        // Left/right edge middles → halves.
        if mouse.x <= f.minX + edgeSize { return SnapTarget(layout: .twoTile, zone: .left) }
        if mouse.x >= f.maxX - edgeSize { return SnapTarget(layout: .twoTile, zone: .right) }

        return nil
    }
}
