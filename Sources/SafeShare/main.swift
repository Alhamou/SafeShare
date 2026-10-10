import AppKit
import SwiftUI
import SafeShareKit

@main
final class SafeShareAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var coordinator: AppStateCoordinator?

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
        popover.contentSize = NSSize(width: 360, height: 500)
        popover.behavior = .transient
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
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button, let popover = popover else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
