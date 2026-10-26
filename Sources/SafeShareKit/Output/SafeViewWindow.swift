import AppKit
import AVFoundation
import CoreMedia

public enum PrivacyBlankReason: String, Sendable {
    case filterTransition = "Updating Filter Rules..."
    case screenLocked = "Display Locked"
    case permissionRevoked = "Permission Revoked"
    case userPaused = "Stream Paused"
}

public protocol OutputSurfacing: AnyObject {
    @MainActor func showSafeView()
    @MainActor func hideSafeView()
    func render(sampleBuffer: CMSampleBuffer)
    @MainActor func blankOutput(reason: PrivacyBlankReason)
    @MainActor func unblankOutput()
    @MainActor var isVisible: Bool { get }
    /// Tells the surface which display it mirrors so it can lock the aspect ratio, enforce a
    /// readable minimum size and report the resolution viewers actually receive.
    @MainActor func applyDisplayGeometry(pointSize: CGSize, pixelSize: CGSize)
    /// Parks the window behind every other window at its current size. Meeting apps keep
    /// capturing a covered window, so this is the safe way to get it "out of the way".
    @MainActor func sendToBack()
}

public final class SafeViewDisplayLayerWrapper: @unchecked Sendable {
    public let displayLayer = AVSampleBufferDisplayLayer()

    public init() {
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = CGColor(gray: 0.08, alpha: 1.0)
    }

    public func enqueue(_ sampleBuffer: CMSampleBuffer) {
        displayLayer.enqueue(sampleBuffer)
    }

    public func flush() {
        displayLayer.flushAndRemoveImage()
    }
}

public final class SafeViewHostingNSView: NSView {
    public let layerWrapper: SafeViewDisplayLayerWrapper
    private let privacyOverlay = NSTextField(labelWithString: "")
    private let outputHint = NSTextField(labelWithString: "")

    private static let outputHintHeight: CGFloat = 24
    private static let outputHintInset: CGFloat = 10

    public init(layerWrapper: SafeViewDisplayLayerWrapper) {
        self.layerWrapper = layerWrapper
        super.init(frame: .zero)
        self.wantsLayer = true
        self.layer?.backgroundColor = CGColor(gray: 0.05, alpha: 1.0)
        self.layer?.addSublayer(layerWrapper.displayLayer)

        privacyOverlay.isEditable = false
        privacyOverlay.isSelectable = false
        privacyOverlay.alignment = .center
        privacyOverlay.font = NSFont.systemFont(ofSize: 18, weight: .bold)
        privacyOverlay.textColor = .white
        privacyOverlay.isHidden = true
        self.addSubview(privacyOverlay)

        // Banner shown (to the presenter *and* to viewers) whenever the window is small
        // enough that the shared picture is noticeably downscaled.
        outputHint.isEditable = false
        outputHint.isSelectable = false
        outputHint.alignment = .center
        outputHint.lineBreakMode = .byTruncatingTail
        outputHint.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        outputHint.textColor = .white
        outputHint.wantsLayer = true
        outputHint.layer?.backgroundColor = NSColor(calibratedRed: 0.85, green: 0.45, blue: 0.05, alpha: 0.92).cgColor
        outputHint.layer?.cornerRadius = 6
        outputHint.isHidden = true
        self.addSubview(outputHint)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layerWrapper.displayLayer.frame = self.bounds
        privacyOverlay.frame = NSRect(x: 20, y: self.bounds.midY - 20, width: self.bounds.width - 40, height: 40)
        let inset = Self.outputHintInset
        outputHint.frame = NSRect(
            x: inset,
            y: self.bounds.height - Self.outputHintHeight - inset,
            width: max(self.bounds.width - inset * 2, 0),
            height: Self.outputHintHeight
        )
        CATransaction.commit()
    }

    public func showPrivacyBlank(reason: PrivacyBlankReason) {
        layerWrapper.flush()
        privacyOverlay.stringValue = "🛡️ SafeShare Privacy Blank: \(reason.rawValue)"
        privacyOverlay.isHidden = false
        self.layer?.backgroundColor = NSColor(calibratedRed: 0.04, green: 0.08, blue: 0.18, alpha: 1.0).cgColor
    }

    public func hidePrivacyBlank() {
        privacyOverlay.isHidden = true
        self.layer?.backgroundColor = CGColor(gray: 0.05, alpha: 1.0)
    }

    /// Shows or hides the low-resolution banner based on the latest output metrics.
    public func updateOutputHint(_ metrics: SafeViewOutputMetrics?) {
        guard let metrics = metrics, metrics.isDegraded else {
            outputHint.isHidden = true
            return
        }
        outputHint.stringValue = "⚠️ Viewers receive \(metrics.summary) — enlarge this window for sharper text"
        outputHint.isHidden = false
    }
}
