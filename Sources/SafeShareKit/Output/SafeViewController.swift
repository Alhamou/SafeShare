import AppKit
import CoreMedia

@MainActor
public final class SafeViewController: NSObject, NSWindowDelegate, OutputSurfacing {
    private var window: NSWindow?
    private let layerWrapper = SafeViewDisplayLayerWrapper()
    private var hostingView: SafeViewHostingNSView?
    private var onClose: (@MainActor () -> Void)?

    public var isVisible: Bool {
        window?.isVisible ?? false
    }

    public init(onClose: (@MainActor () -> Void)? = nil) {
        self.onClose = onClose
        super.init()
    }

    public func showSafeView() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SafeViewHostingNSView(layerWrapper: layerWrapper)
        self.hostingView = view

        let newWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1024, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "SafeShare — Safe View (Share this window in Teams)"
        newWindow.sharingType = .readOnly
        newWindow.collectionBehavior = [.fullScreenAuxiliary, .participatesInCycle]
        newWindow.contentView = view
        newWindow.delegate = self
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
    }

    public func hideSafeView() {
        window?.orderOut(nil)
        layerWrapper.flush()
    }

    public func closeSafeView() {
        window?.close()
        window = nil
        hostingView = nil
        layerWrapper.flush()
    }

    public nonisolated func render(sampleBuffer: CMSampleBuffer) {
        layerWrapper.enqueue(sampleBuffer)
    }

    public func blankOutput(reason: PrivacyBlankReason) {
        hostingView?.showPrivacyBlank(reason: reason)
    }

    public func unblankOutput() {
        hostingView?.hidePrivacyBlank()
    }

    // MARK: - NSWindowDelegate
    public func windowWillClose(_ notification: Notification) {
        window = nil
        hostingView = nil
        layerWrapper.flush()
        onClose?()
    }

    public func windowDidMiniaturize(_ notification: Notification) {
        print("[SafeViewController] Warning: Safe View window minimized. Meeting apps like Teams may pause capturing minimized windows.")
    }

    public func windowDidDeminiaturize(_ notification: Notification) {
        print("[SafeViewController] Safe View window restored from minimization.")
    }
}
