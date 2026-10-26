import XCTest
@testable import LedgerCore

final class AppLockPolicyTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testDisabledNeverLocks() {
        XCTAssertFalse(AppLockPolicy.shouldLockOnLaunch(enabled: false))
        XCTAssertFalse(AppLockPolicy.shouldLockOnReturn(enabled: false, backgroundedAt: t0, now: t0 + 3600))
    }

    func testLaunchLocksWhenEnabled() {
        XCTAssertTrue(AppLockPolicy.shouldLockOnLaunch(enabled: true))
    }

    func testShortTripDoesNotLock() {
        XCTAssertFalse(AppLockPolicy.shouldLockOnReturn(enabled: true, backgroundedAt: t0, now: t0 + 29.9))
    }

    func testThirtySecondsAndMoreLocks() {
        XCTAssertTrue(AppLockPolicy.shouldLockOnReturn(enabled: true, backgroundedAt: t0, now: t0 + 30))
        XCTAssertTrue(AppLockPolicy.shouldLockOnReturn(enabled: true, backgroundedAt: t0, now: t0 + 600))
    }

    func testNoBackgroundNoLock() {
        XCTAssertFalse(AppLockPolicy.shouldLockOnReturn(enabled: true, backgroundedAt: nil, now: t0))
    }

    func testClockMovedBackLocks() {
        XCTAssertTrue(AppLockPolicy.shouldLockOnReturn(enabled: true, backgroundedAt: t0, now: t0 - 5))
    }

    func testCustomGrace() {
        XCTAssertFalse(AppLockPolicy.shouldLockOnReturn(enabled: true, backgroundedAt: t0, now: t0 + 50, grace: 60))
        XCTAssertTrue(AppLockPolicy.shouldLockOnReturn(enabled: true, backgroundedAt: t0, now: t0 + 60, grace: 60))
    }
}
