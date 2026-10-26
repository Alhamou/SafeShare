import Foundation
import CoreGraphics
import ScreenCaptureKit

/// Translates display geometry between the units used by the different APIs involved
/// in Safe View:
///
/// - `SCDisplay.width/height` are reported in **points**.
/// - `SCStreamConfiguration.width/height` are consumed in **pixels**.
///
/// Passing points where pixels are expected silently halves the capture resolution on
/// Retina displays, so every capture configuration must go through `pixelSize(for:)`.
public enum DisplayGeometry {
    /// Size of the display in points, exactly as ScreenCaptureKit reports it.
    public static func pointSize(for display: SCDisplay) -> CGSize {
        CGSize(width: display.width, height: display.height)
    }

    /// Native pixel size of the display's current mode (e.g. 3024×1964 for a 14" MacBook Pro
    /// whose point size is 1512×982). Falls back to the point size when the mode cannot be
    /// queried, which keeps the previous behaviour on 1x displays.
    public static func pixelSize(for display: SCDisplay) -> CGSize {
        pixelSize(displayID: display.displayID, fallback: pointSize(for: display))
    }

    public static func pixelSize(displayID: CGDirectDisplayID, fallback: CGSize) -> CGSize {
        guard let mode = CGDisplayCopyDisplayMode(displayID),
              mode.pixelWidth > 0, mode.pixelHeight > 0 else {
            return fallback
        }
        return CGSize(width: mode.pixelWidth, height: mode.pixelHeight)
    }

    /// Largest rectangle with the aspect ratio of `source` that fits inside `bounds`.
    /// This is the area `AVLayerVideoGravity.resizeAspect` actually paints; the rest of the
    /// bounds is letterboxing that carries no picture information.
    public static func fittedSize(of source: CGSize, in bounds: CGSize) -> CGSize {
        guard source.width > 0, source.height > 0, bounds.width > 0, bounds.height > 0 else {
            return .zero
        }
        let scale = min(bounds.width / source.width, bounds.height / source.height)
        return CGSize(
            width: (source.width * scale).rounded(),
            height: (source.height * scale).rounded()
        )
    }
}
