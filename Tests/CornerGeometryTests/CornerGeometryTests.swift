import CoreGraphics
import XCTest
@testable import CornerGeometry

final class CornerGeometryTests: XCTestCase {
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
}
