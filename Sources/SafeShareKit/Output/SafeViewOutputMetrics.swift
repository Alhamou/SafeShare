import Foundation
import CoreGraphics

/// Describes what a meeting app (Teams, Zoom, Meet) actually receives when it shares the
/// Safe View window.
///
/// Meeting apps capture the *window* at its on-screen pixel size, not the underlying
/// ScreenCaptureKit stream. Shrinking the window therefore shrinks the resolution every
/// viewer gets, regardless of how sharp the internal stream is.
public struct SafeViewOutputMetrics: Equatable, Sendable {
    /// Pixels of real picture the viewer receives (letterboxing excluded).
    public let sharedPixelSize: CGSize
    /// Native pixel size of the captured display.
    public let sourcePixelSize: CGSize

    /// Below this fraction of the source resolution the output is considered degraded and
    /// the presenter is warned. 0.7 keeps the default window (75% of the display) quiet while
    /// flagging anything approaching the 50% floor, where small text stops being readable.
    public static let degradationThreshold: CGFloat = 0.7

    public init(sharedPixelSize: CGSize, sourcePixelSize: CGSize) {
        self.sharedPixelSize = sharedPixelSize
        self.sourcePixelSize = sourcePixelSize
    }

    /// Linear scale of the shared picture relative to the source (1.0 = pixel-for-pixel).
    public var scale: CGFloat {
        guard sourcePixelSize.width > 0 else { return 1.0 }
        return sharedPixelSize.width / sourcePixelSize.width
    }

    public var isDegraded: Bool {
        scale < Self.degradationThreshold
    }

    public var scalePercent: Int {
        Int((scale * 100).rounded())
    }

    /// Computes the metrics for a Safe View content area of `viewBounds` points drawn on a
    /// screen with `backingScale`, showing a display of `sourcePointSize` points whose
    /// native resolution is `sourcePixelSize`.
    public static func compute(
        viewBounds: CGSize,
        backingScale: CGFloat,
        sourcePointSize: CGSize,
        sourcePixelSize: CGSize
    ) -> SafeViewOutputMetrics {
        let fitted = DisplayGeometry.fittedSize(of: sourcePointSize, in: viewBounds)
        let scale = max(backingScale, 1.0)
        let shared = CGSize(
            width: (fitted.width * scale).rounded(),
            height: (fitted.height * scale).rounded()
        )
        return SafeViewOutputMetrics(sharedPixelSize: shared, sourcePixelSize: sourcePixelSize)
    }

    /// Short human readable summary, e.g. "960 × 540 (50% of 1920 × 1080)".
    public var summary: String {
        "\(Int(sharedPixelSize.width)) × \(Int(sharedPixelSize.height)) (\(scalePercent)% of \(Int(sourcePixelSize.width)) × \(Int(sourcePixelSize.height)))"
    }
}
