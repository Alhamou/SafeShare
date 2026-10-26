import XCTest
import CoreGraphics
@testable import SafeShareKit

final class SafeViewOutputMetricsTests: XCTestCase {
    private let fullHD = CGSize(width: 1920, height: 1080)

    func testFittedSizeLetterboxesSquareWindow() {
        // A 16:9 desktop shown in a square window only uses a 16:9 strip of it.
        let fitted = DisplayGeometry.fittedSize(of: fullHD, in: CGSize(width: 300, height: 300))
        XCTAssertEqual(fitted, CGSize(width: 300, height: 169))
    }

    func testFittedSizeMatchesWhenAspectIsIdentical() {
        let fitted = DisplayGeometry.fittedSize(of: fullHD, in: CGSize(width: 960, height: 540))
        XCTAssertEqual(fitted, CGSize(width: 960, height: 540))
    }

    func testFittedSizeIsZeroForDegenerateInput() {
        XCTAssertEqual(DisplayGeometry.fittedSize(of: .zero, in: fullHD), .zero)
        XCTAssertEqual(DisplayGeometry.fittedSize(of: fullHD, in: .zero), .zero)
    }

    func testPixelSizeFallsBackToPointsForUnknownDisplay() {
        let fallback = CGSize(width: 1512, height: 982)
        let size = DisplayGeometry.pixelSize(displayID: CGDirectDisplayID.max, fallback: fallback)
        XCTAssertEqual(size, fallback)
    }

    func testHalfSizeWindowOn1xDisplayIsDegraded() {
        // The reported real-world case: 1080p monitor, window shrunk well below the display.
        let metrics = SafeViewOutputMetrics.compute(
            viewBounds: CGSize(width: 960, height: 540),
            backingScale: 1.0,
            sourcePointSize: fullHD,
            sourcePixelSize: fullHD
        )
        XCTAssertEqual(metrics.sharedPixelSize, CGSize(width: 960, height: 540))
        XCTAssertEqual(metrics.scalePercent, 50)
        XCTAssertTrue(metrics.isDegraded)
        XCTAssertEqual(metrics.summary, "960 × 540 (50% of 1920 × 1080)")
    }

    func testTinySquareWindowIsSeverelyDegraded() {
        let metrics = SafeViewOutputMetrics.compute(
            viewBounds: CGSize(width: 300, height: 300),
            backingScale: 1.0,
            sourcePointSize: fullHD,
            sourcePixelSize: fullHD
        )
        XCTAssertEqual(metrics.sharedPixelSize, CGSize(width: 300, height: 169))
        XCTAssertEqual(metrics.scalePercent, 16)
        XCTAssertTrue(metrics.isDegraded)
    }

    func testFullSizeWindowOnRetinaDisplayIsNotDegraded() {
        // 14" MacBook Pro: 1512×982 points, 3024×1964 pixels, backing scale 2.
        let points = CGSize(width: 1512, height: 982)
        let pixels = CGSize(width: 3024, height: 1964)
        let metrics = SafeViewOutputMetrics.compute(
            viewBounds: points,
            backingScale: 2.0,
            sourcePointSize: points,
            sourcePixelSize: pixels
        )
        XCTAssertEqual(metrics.sharedPixelSize, pixels)
        XCTAssertEqual(metrics.scalePercent, 100)
        XCTAssertFalse(metrics.isDegraded)
    }

    func testNearlyFullSizeWindowIsNotFlagged() {
        // 92% of the display is comfortably above the threshold.
        let metrics = SafeViewOutputMetrics.compute(
            viewBounds: CGSize(width: 1766, height: 994),
            backingScale: 1.0,
            sourcePointSize: fullHD,
            sourcePixelSize: fullHD
        )
        XCTAssertFalse(metrics.isDegraded)
    }

    func testDefaultWindowSizeIsNotFlagged() {
        // A freshly opened window (75% of the display) must not start out with a warning.
        let fraction = SafeViewController.defaultSizeFraction
        let metrics = SafeViewOutputMetrics.compute(
            viewBounds: CGSize(width: fullHD.width * fraction, height: fullHD.height * fraction),
            backingScale: 1.0,
            sourcePointSize: fullHD,
            sourcePixelSize: fullHD
        )
        XCTAssertEqual(metrics.scalePercent, 75)
        XCTAssertFalse(metrics.isDegraded)
    }

    func testMinimumWindowFractionKeepsOutputAboveHalfResolution() {
        // The enforced minimum (50% of the display) must itself be a readable floor.
        let fraction = SafeViewController.minimumSizeFraction
        let minimumBounds = CGSize(width: fullHD.width * fraction, height: fullHD.height * fraction)
        let metrics = SafeViewOutputMetrics.compute(
            viewBounds: minimumBounds,
            backingScale: 1.0,
            sourcePointSize: fullHD,
            sourcePixelSize: fullHD
        )
        XCTAssertGreaterThanOrEqual(metrics.scale, 0.5)
    }
}
