import XCTest

@testable import FanControllerApp

@MainActor
final class PopoverPresentationCoordinatorTests: XCTestCase {
    func testInitialLaunchPresentsExactlyOnce() {
        var presentationCount = 0
        let coordinator = PopoverPresentationCoordinator {
            presentationCount += 1
        }

        coordinator.requestPresentation(for: .initialLaunch)
        coordinator.requestPresentation(for: .initialLaunch)

        XCTAssertEqual(presentationCount, 1)
    }

    func testEachReopenPresentsThePopoverAgain() {
        var presentationCount = 0
        let coordinator = PopoverPresentationCoordinator {
            presentationCount += 1
        }

        coordinator.requestPresentation(for: .initialLaunch)
        coordinator.requestPresentation(for: .reopen)
        coordinator.requestPresentation(for: .reopen)

        XCTAssertEqual(presentationCount, 3)
    }
}
