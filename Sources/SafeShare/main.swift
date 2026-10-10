import AppKit
import SwiftUI
import SafeShareKit

@main
@MainActor
final class SafeShareAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var coordinator: AppStateCoordinator?
    private var globalEventMonitor: Any?
    private var isClosingPopover: Bool = false

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

        // Show popover cleanly without manually overriding key-window state
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Install global monitor: dismiss cleanly when user clicks anywhere outside
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.closePopover()
            }
        }
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
