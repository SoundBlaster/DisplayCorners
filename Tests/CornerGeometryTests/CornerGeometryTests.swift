import CoreGraphics
import XCTest
@testable import CornerGeometry

final class CornerGeometryTests: XCTestCase {
    func testMenuCornerStaysConcentricForOneRow() {
        for radius: CGFloat in [24, 38, 80, 120] {
            let menuRadius = AgentMenuGeometry.menuRadius(maskRadius: radius)
            let height = AgentMenuGeometry.height(rowCount: 1, rowHeight: 57, maskRadius: radius)
            let inset = AgentMenuGeometry.edgeInset(maskRadius: radius)
            XCTAssertEqual(menuRadius + inset, radius)
            XCTAssertLessThanOrEqual(menuRadius, 20)
            XCTAssertGreaterThanOrEqual(inset, 4)
            XCTAssertGreaterThanOrEqual(height, 2 * menuRadius)
            XCTAssertEqual(AgentMenuGeometry.height(rowCount: 2, rowHeight: 57, maskRadius: radius) - height, 57)
        }
        XCTAssertEqual(AgentMenuGeometry.height(rowCount: 1, rowHeight: 57, maskRadius: 38), 57)
        XCTAssertEqual(AgentMenuGeometry.height(rowCount: 2, rowHeight: 57, maskRadius: 38), 114)
        XCTAssertEqual(AgentMenuGeometry.edgeInset(maskRadius: 38), 18)
    }

    func testMenuUsesMaskRadiusClampedToScreen() {
        let screen = CGRect(x: 0, y: 0, width: 100, height: 80)
        XCTAssertEqual(AgentMenuGeometry.maskRadius(120, on: screen), 40)
        XCTAssertEqual(AgentMenuGeometry.menuRadius(maskRadius: 40), 20)
        XCTAssertEqual(AgentMenuGeometry.edgeInset(maskRadius: 40), 20)
    }

    func testFramesUseDisplayCoordinatesIncludingNegativeOrigins() {
        let screen = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
        XCTAssertEqual(Corner.bottomLeft.frame(on: screen, radius: 40), CGRect(x: -1920, y: 200, width: 40, height: 40))
        XCTAssertEqual(Corner.bottomRight.frame(on: screen, radius: 40), CGRect(x: -40, y: 200, width: 40, height: 40))
        XCTAssertEqual(Corner.topLeft.frame(on: screen, radius: 40), CGRect(x: -1920, y: 1240, width: 40, height: 40))
        XCTAssertEqual(Corner.topRight.frame(on: screen, radius: 40), CGRect(x: -40, y: 1240, width: 40, height: 40))
    }

    func testRadiusIsClampedToDisplaySize() {
        let screen = CGRect(x: 10, y: 20, width: 100, height: 60)
        XCTAssertEqual(Corner.topRight.frame(on: screen, radius: 100), CGRect(x: 80, y: 50, width: 30, height: 30))
        XCTAssertEqual(Corner.bottomLeft.frame(on: screen, radius: -1).size, .zero)
    }

    func testAgentHooksSetMinimumWithoutChangingSelectedRadius() {
        let selected: CGFloat = 4
        XCTAssertEqual(CornerRadius.effective(selected: selected, agentHooksInstalled: true), 24)
        XCTAssertEqual(CornerRadius.effective(selected: selected, agentHooksInstalled: false), selected)
        XCTAssertEqual(CornerRadius.effective(selected: 36, agentHooksInstalled: true), 36)
    }

    func testAgentDotFitsAndStaysNearCenterOfMask() {
        for radius: CGFloat in [24, 36, 80, 120] {
            let dot = AgentIndicatorGeometry.frame(maskRadius: radius)
            let offsetFromRight = radius - dot.midX
            let offsetFromBottom = dot.midY
            let clearanceFromCurve = hypot(radius - offsetFromRight, radius - offsetFromBottom) - radius - dot.width / 2
            XCTAssertEqual(dot.size, CGSize(width: 5, height: 5))
            XCTAssertEqual(offsetFromRight, offsetFromBottom, accuracy: 0.001)
            XCTAssertGreaterThan(offsetFromBottom, radius * 0.15)
            XCTAssertLessThan(offsetFromBottom, radius * 0.25)
            XCTAssertGreaterThan(dot.minY, 0)
            XCTAssertLessThan(dot.maxX, radius)
            XCTAssertGreaterThan(clearanceFromCurve, 0)
        }
    }
}
