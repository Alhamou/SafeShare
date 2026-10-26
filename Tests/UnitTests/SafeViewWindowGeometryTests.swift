import XCTest
import AppKit
@testable import SafeShareKit

/// Integration test against a real AppKit window: the Safe View window must lock its aspect
/// ratio, refuse to shrink below the readable minimum and report what viewers receive.
final class SafeViewWindowGeometryTests: XCTestCase {
    @MainActor
    func testWindowLocksAspectRatioEnforcesMinimumAndReportsMetrics() throws {
        guard let screen = NSScreen.main else {
            throw XCTSkip("No display attached; AppKit windows cannot be created headlessly.")
        }
        _ = NSApplication.shared

        let controller = SafeViewController()
        var reported: [SafeViewOutputMetrics?] = []
        controller.onOutputMetricsChange = { reported.append($0) }

        // Pretend the captured display has the same backing scale as the screen hosting the
        // window, so a full-size window would be pixel-for-pixel.
        let pointSize = CGSize(width: 1920, height: 1080)
        let scale = screen.backingScaleFactor
        let pixelSize = CGSize(width: pointSize.width * scale, height: pointSize.height * scale)

        controller.applyDisplayGeometry(pointSize: pointSize, pixelSize: pixelSize)
        controller.showSafeView()
        defer { controller.closeSafeView() }

        let window = try XCTUnwrap(controller.window)

        // 1. Aspect ratio is locked to the captured display.
        XCTAssertEqual(window.contentAspectRatio, NSSize(width: 1920, height: 1080))

        // 2. Minimum size is 50% of the display (capped only by a smaller host screen) and 16:9.
        let minSize = window.contentMinSize
        XCTAssertGreaterThan(minSize.width, 0)
        XCTAssertLessThanOrEqual(minSize.width, 960)
        XCTAssertEqual(minSize.width / minSize.height, 16.0 / 9.0, accuracy: 0.02)

        // 3. A freshly opened window is at or above the minimum and already reports metrics.
        let opened = window.contentRect(forFrameRect: window.frame).size
        XCTAssertGreaterThanOrEqual(opened.width, minSize.width)
        let initial = try XCTUnwrap(controller.outputMetrics)
        XCTAssertEqual(initial.sourcePixelSize, pixelSize)
        XCTAssertFalse(initial.isDegraded, "default window size must not trigger the warning")

        // 4. Shrinking the window (as the user did) is detected and flagged as degraded.
        window.setContentSize(NSSize(width: 300, height: 300))
        let shrunk = try XCTUnwrap(controller.outputMetrics)
        XCTAssertTrue(shrunk.isDegraded)
        let expectedWidth = (300 * window.backingScaleFactor).rounded()
        XCTAssertEqual(shrunk.sharedPixelSize.width, expectedWidth)
        XCTAssertTrue(reported.contains { $0?.isDegraded == true })

        // 5. Re-applying the geometry (display sync) grows it back to the readable minimum.
        controller.applyDisplayGeometry(pointSize: pointSize, pixelSize: pixelSize)
        let restored = window.contentRect(forFrameRect: window.frame).size
        XCTAssertGreaterThanOrEqual(restored.width, minSize.width - 1)
        XCTAssertGreaterThanOrEqual(restored.height, minSize.height - 1)

        // 6. Closing the window clears the metrics.
        controller.closeSafeView()
        XCTAssertNil(controller.outputMetrics)
        let lastReport = try XCTUnwrap(reported.last)
        XCTAssertNil(lastReport)
    }
}
