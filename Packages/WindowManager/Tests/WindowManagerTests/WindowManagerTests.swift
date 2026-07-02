import Testing
import CoreGraphics
@testable import WindowManager

private let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

@Test func cornerDragGivesQuadrant() {
    let target = SnapGeometry.target(at: CGPoint(x: 10, y: 790), in: screen)
    #expect(target == SnapTarget(layout: .fourTile, zone: .topLeft))
}

@Test func sideMiddleGivesHalf() {
    let target = SnapGeometry.target(at: CGPoint(x: 5, y: 400), in: screen)
    #expect(target == SnapTarget(layout: .twoTile, zone: .left))
}

@Test func centerGivesNothing() {
    #expect(SnapGeometry.target(at: CGPoint(x: 500, y: 400), in: screen) == nil)
}

@Test func leftHalfFillsLeftColumnWithZeroGaps() {
    let frame = SnapZone.left.cocoaFrame(in: screen, edge: 0, inner: 0)
    #expect(frame == CGRect(x: 0, y: 0, width: 500, height: 800))
}

@Test func leftHalfRespectsEdgeAndInnerGap() {
    // Edge padding on left/top/bottom; half the inner gap on the shared right edge.
    let frame = SnapZone.left.cocoaFrame(in: screen, edge: 10, inner: 8)
    #expect(frame == CGRect(x: 10, y: 10, width: 500 - 10 - 4, height: 800 - 20))
}

@Test func topRightQuadrantRespectsEdgeAndInnerGap() {
    // Interior left/bottom edges get half the inner gap; screen-touching
    // right/top edges get the full edge padding.
    let frame = SnapZone.topRight.cocoaFrame(in: screen, edge: 10, inner: 8)
    #expect(frame == CGRect(x: 504, y: 404, width: 486, height: 386))
}

@Test func neighbouringHalvesLeaveExactlyInnerGapBetweenThem() {
    let left = SnapZone.left.cocoaFrame(in: screen, edge: 0, inner: 12)
    let right = SnapZone.right.cocoaFrame(in: screen, edge: 0, inner: 12)
    #expect(right.minX - left.maxX == 12)
}

@Test func triggerScaleScalesBothHitAreas() {
    SnapGeometry.setTriggerScale(2)
    #expect(SnapGeometry.cornerSize == SnapGeometry.baseCornerSize * 2)
    #expect(SnapGeometry.edgeSize == SnapGeometry.baseEdgeSize * 2)
    SnapGeometry.setTriggerScale(1)
}
