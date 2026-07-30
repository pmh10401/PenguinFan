import AppKit
import XCTest
@testable import FanControllerApp

final class ProductBrandTests: XCTestCase {
    func testProductBrandUsesPenguinFanName() {
        XCTAssertEqual(ProductBrand.displayName, "PenguinFan")
        XCTAssertEqual(ProductBrand.settingsTitle, "PenguinFan 설정")
        XCTAssertEqual(ProductBrand.diagnosticsTitle, "PenguinFan 진단")
    }

    func testVersionTextIncludesReleaseVersion() {
        XCTAssertEqual(
            ProductBrand.versionText(version: "1.0.12"),
            "PenguinFan 1.0.12"
        )
    }

    func testVersionTextFallsBackToProductName() {
        XCTAssertEqual(ProductBrand.versionText(version: nil), "PenguinFan")
        XCTAssertEqual(ProductBrand.versionText(version: "  "), "PenguinFan")
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
