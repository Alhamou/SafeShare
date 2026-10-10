import AppKit
import SwiftUI
import Combine
import SafeShareKit

@main
@MainActor
final class SafeShareAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var coordinator: AppStateCoordinator?
    private var globalEventMonitor: Any?
    private var isClosingPopover: Bool = false
    private var cancellables = Set<AnyCancellable>()

    static func main() {
        let app = NSApplication.shared
        let delegate = SafeShareAppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as a menu bar accessory (no dock icon by default)
        NSApp.setActivationPolicy(.accessory)

        let coordinator = AppStateCoordinator()
        self.coordinator = coordinator

        // Setup NSPopover hosting MenuBarExtraView
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 520)
        popover.behavior = .transient
        // Disable internal AppKit window transform animations to prevent use-after-free
        // crashes (_NSWindowTransformAnimation dealloc) when clicking other windows.
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: MenuBarExtraView(coordinator: coordinator)
        )
        self.popover = popover

        // Setup NSStatusItem in macOS Menu Bar
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "shield.checkered", accessibilityDescription: "SafeShare")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        self.statusItem = statusItem

        // Dynamically update menu bar icon with green indicator when stream is active
        coordinator.$isCapturing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isCapturing in
                self?.updateStatusIcon(isCapturing: isCapturing)
            }
            .store(in: &cancellables)

        // Automatically close popover when application resigns active
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.closePopover()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep the menu bar app running even if the Safe View window is closed
        return false
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button, let popover = popover else { return }

        if popover.isShown {
            closePopover()
        } else {
            showPopover(button)
        }
    }

    private func showPopover(_ button: NSStatusBarButton) {
        guard let popover = popover else { return }

        // Remove any previous monitor
        removeGlobalMonitor()

        // Activate the application so the popover opens in active focused mode
        NSApp.activate(ignoringOtherApps: true)

        // Show popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Ensure the popover window is key so controls and buttons are active immediately
        if let window = popover.contentViewController?.view.window {
            window.makeKey()
        }

        // Install global monitor: dismiss cleanly when user clicks anywhere outside
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.closePopover()
            }
        }
    }

    private func updateStatusIcon(isCapturing: Bool) {
        guard let button = statusItem?.button else { return }
        guard let base = NSImage(systemSymbolName: "shield.checkered", accessibilityDescription: isCapturing ? "SafeShare (Streaming)" : "SafeShare") else { return }

        if !isCapturing {
            base.isTemplate = true
            button.image = base
            return
        }

        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { [weak button] rect in
            let isDark = button?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let shieldColor = isDark ? NSColor.white : NSColor(white: 0.15, alpha: 1.0)
            let config = NSImage.SymbolConfiguration(paletteColors: [shieldColor])
            let tinted = base.withSymbolConfiguration(config) ?? base

            tinted.draw(in: NSRect(x: 0, y: 1.5, width: 15, height: 15))

            // Contrast knockout border around dot
            let dotRect = NSRect(x: 11, y: 0.5, width: 6, height: 6)
            let knockoutRect = dotRect.insetBy(dx: -0.75, dy: -0.75)
            (isDark ? NSColor(white: 0.05, alpha: 1.0) : NSColor.white).setFill()
            NSBezierPath(ovalIn: knockoutRect).fill()

            // Bright green live indicator dot
            NSColor.systemGreen.setFill()
            let path = NSBezierPath(ovalIn: dotRect)
            path.fill()

            return true
        }
        image.isTemplate = false
        button.image = image
    }

    private func closePopover() {
        guard let popover = popover, popover.isShown, !isClosingPopover else { return }
        isClosingPopover = true
        defer { isClosingPopover = false }

        removeGlobalMonitor()
        coordinator?.resetNavigationState()
        popover.close()
    }

    private func removeGlobalMonitor() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
    }

    // MARK: - NSPopoverDelegate
    func popoverDidClose(_ notification: Notification) {
        removeGlobalMonitor()
        coordinator?.resetNavigationState()
    }
}
