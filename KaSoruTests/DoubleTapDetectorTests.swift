import XCTest
@testable import KaSoru

final class DoubleTapDetectorTests: XCTestCase {
    func testSingleTapDoesNotFire() {
        let d = DoubleTapDetector(window: 0.3)
        XCTAssertFalse(d.register(at: 0))
    }

    func testTwoFastTapsFire() {
        let d = DoubleTapDetector(window: 0.3)
        XCTAssertFalse(d.register(at: 0))
        XCTAssertTrue(d.register(at: 0.150))
    }

    func testTwoSlowTapsDoNotFire() {
        let d = DoubleTapDetector(window: 0.3)
        XCTAssertFalse(d.register(at: 0))
        XCTAssertFalse(d.register(at: 0.5))
    }

    func testThreeTapsOnlyFireOnce() {
        let d = DoubleTapDetector(window: 0.3)
        XCTAssertFalse(d.register(at: 0))
        XCTAssertTrue(d.register(at: 0.1))
        XCTAssertFalse(d.register(at: 0.2))
    }

    func testResetAfterFire() {
        let d = DoubleTapDetector(window: 0.3)
        _ = d.register(at: 0)
        _ = d.register(at: 0.1)
        XCTAssertFalse(d.register(at: 0.2))
        XCTAssertTrue(d.register(at: 0.3))
    }
}
