import AppKit
import XCTest
@testable import FanControllerApp

final class ProductBrandTests: XCTestCase {
    func testProductBrandUsesPenguinFanName() {
        XCTAssertEqual(ProductBrand.displayName, "PenguinFan")
        XCTAssertEqual(ProductBrand.settingsTitle, "PenguinFan 설정")
        XCTAssertEqual(ProductBrand.diagnosticsTitle, "PenguinFan 진단")
    }

    func testMenuBarIconIsAnEighteenPointTemplateImage() {
        let image = PenguinMenuBarIcon.make()

        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
        XCTAssertTrue(image.isTemplate)
        XCTAssertNotNil(image.tiffRepresentation)
    }

    func testEveryWalkingFrameIsAnEighteenPointTemplateImage() {
        for frame in 0...4 {
            let image = PenguinMenuBarIcon.make(frame: frame)

            XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
            XCTAssertTrue(image.isTemplate)
            XCTAssertNotNil(image.tiffRepresentation)
        }
    }
}
