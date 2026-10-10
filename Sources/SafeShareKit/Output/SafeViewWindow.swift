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
}
