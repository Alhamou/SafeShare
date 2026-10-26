import AppKit
import CoreMedia

@MainActor
public final class SafeViewController: NSObject, NSWindowDelegate, OutputSurfacing {
    /// The window can never be resized below this fraction of the captured display's point
    /// size. Meeting apps share the window at its on-screen size, so anything smaller makes
    /// text unreadable for viewers.
    public nonisolated static let minimumSizeFraction: CGFloat = 0.5
    /// Size of a freshly created window relative to the captured display.
    public nonisolated static let defaultSizeFraction: CGFloat = 0.75

    private(set) var window: NSWindow?
    private let layerWrapper = SafeViewDisplayLayerWrapper()
    private var hostingView: SafeViewHostingNSView?
    private var displayPointSize: CGSize?
    private var displayPixelSize: CGSize?

    public var onClose: (@MainActor () -> Void)?
    /// Fired whenever the resolution viewers receive changes (resize, backing scale change,
    /// display change) and with `nil` when the window goes away.
    public var onOutputMetricsChange: (@MainActor (SafeViewOutputMetrics?) -> Void)?
    public private(set) var outputMetrics: SafeViewOutputMetrics?

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

        let contentSize = initialContentSize()
        let newWindow = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: contentSize.width, height: contentSize.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.isReleasedWhenClosed = false
        newWindow.animationBehavior = .none
        newWindow.title = "SafeShare — Safe View (Share this window in Teams)"
        newWindow.sharingType = .readOnly
        newWindow.collectionBehavior = [.fullScreenAuxiliary, .participatesInCycle]
        newWindow.contentView = view
        newWindow.delegate = self
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
        applyGeometryToWindow()
        refreshOutputMetrics()
    }

    public func hideSafeView() {
        window?.orderOut(nil)
        layerWrapper.flush()
        publishMetrics(nil)
    }

    public func closeSafeView() {
        if let win = window {
            win.close()
        }
        window = nil
        hostingView = nil
        layerWrapper.flush()
        publishMetrics(nil)
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

    // MARK: - Display geometry

    public func applyDisplayGeometry(pointSize: CGSize, pixelSize: CGSize) {
        guard pointSize.width > 0, pointSize.height > 0 else { return }
        displayPointSize = pointSize
        displayPixelSize = pixelSize.width > 0 && pixelSize.height > 0 ? pixelSize : pointSize
        applyGeometryToWindow()
        refreshOutputMetrics()
    }

    public func sendToBack() {
        guard let window = window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.orderBack(nil)
        // Hand focus back to whatever the presenter was working in; the popover closes on
        // resignActive, so a single click parks the window and returns to work.
        NSApp.deactivate()
    }

    private func initialContentSize() -> NSSize {
        guard let point = displayPointSize else {
            return NSSize(width: 1024, height: 640)
        }
        return NSSize(
            width: (point.width * Self.defaultSizeFraction).rounded(),
            height: (point.height * Self.defaultSizeFraction).rounded()
        )
    }

    /// Locks the aspect ratio to the captured display and enforces the minimum size,
    /// growing the window right away if it is currently below that minimum.
    private func applyGeometryToWindow() {
        guard let window = window, let point = displayPointSize else { return }

        window.contentAspectRatio = NSSize(width: point.width, height: point.height)

        var minSize = NSSize(
            width: (point.width * Self.minimumSizeFraction).rounded(),
            height: (point.height * Self.minimumSizeFraction).rounded()
        )

        // Never demand more than fits on the screen that hosts the window (the Safe View
        // window may live on a smaller monitor than the one being captured).
        if let screen = window.screen ?? NSScreen.main {
            let chrome = window.frame.height - window.contentRect(forFrameRect: window.frame).height
            let available = CGSize(
                width: screen.visibleFrame.width * 0.95,
                height: max(screen.visibleFrame.height * 0.95 - chrome, 1)
            )
            let fitted = DisplayGeometry.fittedSize(of: point, in: available)
            if fitted.width < minSize.width {
                minSize = NSSize(width: fitted.width, height: fitted.height)
            }
        }

        window.contentMinSize = minSize

        let current = window.contentRect(forFrameRect: window.frame).size
        if current.width < minSize.width || current.height < minSize.height {
            window.setContentSize(minSize)
            if let screen = window.screen ?? NSScreen.main {
                window.setFrame(window.constrainFrameRect(window.frame, to: screen), display: true)
            }
            print("[SafeViewController] Safe View window was below the readable minimum; resized to \(Int(minSize.width)) × \(Int(minSize.height)) pt.")
        }
    }

    private func refreshOutputMetrics() {
        guard let window = window, let view = hostingView,
              let point = displayPointSize, let pixel = displayPixelSize else {
            publishMetrics(nil)
            return
        }
        let metrics = SafeViewOutputMetrics.compute(
            viewBounds: view.bounds.size,
            backingScale: window.backingScaleFactor,
            sourcePointSize: point,
            sourcePixelSize: pixel
        )
        publishMetrics(metrics)
    }

    private func publishMetrics(_ metrics: SafeViewOutputMetrics?) {
        guard metrics != outputMetrics else { return }
        outputMetrics = metrics
        hostingView?.updateOutputHint(metrics)
        onOutputMetricsChange?(metrics)
    }

    // MARK: - NSWindowDelegate
    public func windowWillClose(_ notification: Notification) {
        onClose?()
        publishMetrics(nil)
        DispatchQueue.main.async { [weak self] in
            self?.window = nil
            self?.hostingView = nil
            self?.layerWrapper.flush()
        }
    }

    public func windowDidResize(_ notification: Notification) {
        refreshOutputMetrics()
    }

    public func windowDidEndLiveResize(_ notification: Notification) {
        refreshOutputMetrics()
    }

    public func windowDidChangeBackingProperties(_ notification: Notification) {
        refreshOutputMetrics()
    }

    public func windowDidChangeScreen(_ notification: Notification) {
        applyGeometryToWindow()
        refreshOutputMetrics()
    }

    public func windowDidMiniaturize(_ notification: Notification) {
        print("[SafeViewController] Warning: Safe View window minimized. Meeting apps like Teams may pause capturing minimized windows.")
    }

    public func windowDidDeminiaturize(_ notification: Notification) {
        print("[SafeViewController] Safe View window restored from minimization.")
    }
}
