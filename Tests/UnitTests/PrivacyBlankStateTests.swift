import XCTest
@testable import SafeShareKit

final class PrivacyBlankStateTests: XCTestCase {
    func testStartsUnblanked() {
        let state = PrivacyBlankState()
        XCTAssertFalse(state.isBlanked)
        XCTAssertNil(state.displayedReason)
    }

    func testRaiseAndClearSingleReason() {
        var state = PrivacyBlankState()
        XCTAssertEqual(state.raise(.screenLocked), .screenLocked)
        XCTAssertTrue(state.isBlanked)
        XCTAssertNil(state.clear(.screenLocked), "last reason cleared → output may be unblanked")
        XCTAssertFalse(state.isBlanked)
    }

    func testWakeDoesNotUnblankWhileStillLocked() {
        // Display sleeps and the session locks. Waking the display alone must keep the
        // output blanked until the user actually unlocks.
        var state = PrivacyBlankState()
        state.raise(.screenAsleep)
        state.raise(.screenLocked)

        XCTAssertEqual(state.clear(.screenAsleep), .screenLocked)
        XCTAssertTrue(state.isBlanked)

        XCTAssertNil(state.clear(.screenLocked))
        XCTAssertFalse(state.isBlanked)
    }

    func testClearingUnknownReasonKeepsOthers() {
        var state = PrivacyBlankState()
        state.raise(.userPaused)
        XCTAssertEqual(state.clear(.screenLocked), .userPaused)
        XCTAssertTrue(state.isBlanked)
    }

    func testRaisingSameReasonTwiceIsIdempotent() {
        var state = PrivacyBlankState()
        state.raise(.screenLocked)
        state.raise(.screenLocked)
        XCTAssertEqual(state.reasons, [.screenLocked])
        XCTAssertNil(state.clear(.screenLocked))
    }

    func testClearAll() {
        var state = PrivacyBlankState()
        state.raise(.screenAsleep)
        state.raise(.userPaused)
        state.clearAll()
        XCTAssertFalse(state.isBlanked)
    }
}
