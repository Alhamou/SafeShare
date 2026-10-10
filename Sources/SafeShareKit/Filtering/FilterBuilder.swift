import Foundation
import ScreenCaptureKit

public protocol FilterBuilding: Sendable {
    @MainActor
    func buildFilter(
        for display: SCDisplay,
        snapshot: ShareableSnapshot,
        rules: RuleStoring,
        selfPID: pid_t
    ) throws -> SCContentFilter
}

public final class FilterBuilder: FilterBuilding {
    public init() {}

    @MainActor
    public func buildFilter(
        for display: SCDisplay,
        snapshot: ShareableSnapshot,
        rules: RuleStoring,
        selfPID: pid_t
    ) throws -> SCContentFilter {
        var excludingApps: [SCRunningApplication] = []
        var exceptingWindows: [SCWindow] = []

        // 1. Mandatory Self-Exclusion: Exclude SafeShare to prevent recursive mirroring
        if let selfApp = snapshot.applications.first(where: { $0.processID == selfPID }) {
            excludingApps.append(selfApp)
        }

        // 1b. Exclude Notification Center if configured to prevent message leaks
        if rules.config.streamSettings.excludeNotificationCenter,
           let notifApp = snapshot.applications.first(where: { $0.bundleIdentifier == "com.apple.notificationcenterui" }) {
            excludingApps.append(notifApp)
        }

        // 2. Resolve rules for all other applications
        for app in snapshot.applications where app.processID != selfPID {
            let bundleID = app.bundleIdentifier
            let appState = rules.effectiveState(for: bundleID, pid: app.processID, windowID: nil)
            let appWindows = snapshot.windows.filter { $0.owningApplication?.processID == app.processID }

            if appState == .protected {
                excludingApps.append(app)
                // App is protected: check if any window has an explicit visible override (.forceVisible)
                for window in appWindows {
                    let winState = rules.effectiveState(for: bundleID, pid: app.processID, windowID: window.windowID)
                    if winState == .unprotected {
                        exceptingWindows.append(window)
                    }
                }
            } else {
                // App is unprotected: check if any specific window is protected (.forceProtect)
                let protectedWindows = appWindows.filter {
                    rules.effectiveState(for: bundleID, pid: app.processID, windowID: $0.windowID) == .protected
                }
                if !protectedWindows.isEmpty {
                    // Exclude the application, but except (keep visible) all its other windows
                    excludingApps.append(app)
                    for window in appWindows where !protectedWindows.contains(where: { $0.windowID == window.windowID }) {
                        exceptingWindows.append(window)
                    }
                }
            }
        }

        // 3. Construct unified SCContentFilter
        return SCContentFilter(
            display: display,
            excludingApplications: excludingApps,
            exceptingWindows: exceptingWindows
        )
    }
}
