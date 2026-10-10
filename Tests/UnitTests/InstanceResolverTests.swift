import XCTest
import ScreenCaptureKit
@testable import SafeShareKit

final class InstanceResolverTests: XCTestCase {
    func testInstanceGrouping() {
        let resolver = InstanceResolver()
        let selfPID: pid_t = 9999

        // Test with empty snapshot
        let emptySnapshot = ShareableSnapshot(
            displays: [],
            applications: [],
            windows: []
        )
        let resolved = resolver.resolve(snapshot: emptySnapshot, selfPID: selfPID)
        XCTAssertTrue(resolved.isEmpty)
    }

    func testCaptureConfigurationDefaults() {
        let config = CaptureConfiguration(width: 1920, height: 1080)
        XCTAssertEqual(config.targetFPS, 30)
        XCTAssertTrue(config.showsCursor)
        XCTAssertEqual(config.queueDepth, 3)

        let scConfig = config.makeSCStreamConfiguration()
        XCTAssertEqual(scConfig.width, 1920)
        XCTAssertEqual(scConfig.height, 1080)
        XCTAssertTrue(scConfig.showsCursor)
    }
}
