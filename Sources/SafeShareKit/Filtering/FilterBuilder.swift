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

        let isSelfApp: (SCRunningApplication) -> Bool = { app in
            if app.processID == selfPID { return true }
            if let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty, app.bundleIdentifier == bundleID { return true }
            if app.bundleIdentifier == "com.safeshare.app" { return true }
            return false
        }

        // 1. Mandatory Self-Exclusion: Exclude SafeShare to prevent recursive mirroring
        var selfApp = snapshot.applications.first(where: { isSelfApp($0) })
        if selfApp == nil {
            selfApp = snapshot.windows.compactMap { $0.owningApplication }.first(where: { isSelfApp($0) })
        }
        if let selfApp = selfApp {
            excludingApps.append(selfApp)
            print("[FilterBuilder] Successfully excluded SafeShare (PID: \(selfApp.processID), Bundle: \(selfApp.bundleIdentifier)) from capture stream.")
        } else {
            print("[FilterBuilder] CRITICAL WARNING: SafeShare self-app not found in snapshot (Total apps: \(snapshot.applications.count), Total windows: \(snapshot.windows.count))")
        }

        // 1b. Exclude Notification Center if configured to prevent message leaks
        if rules.config.streamSettings.excludeNotificationCenter,
           let notifApp = snapshot.applications.first(where: { $0.bundleIdentifier == "com.apple.notificationcenterui" }) {
            excludingApps.append(notifApp)
        }

        // 2. Resolve rules for all other applications
        for app in snapshot.applications where !isSelfApp(app) {
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

        // 3. Construct unified SCContentFilter. An app can be collected twice (e.g. Notification
        //    Center via the toggle *and* via a rule), so de-duplicate before handing over.
        var seenPIDs = Set<pid_t>()
        let uniqueApps = excludingApps.filter { seenPIDs.insert($0.processID).inserted }
        var seenWindows = Set<CGWindowID>()
        let uniqueWindows = exceptingWindows.filter { seenWindows.insert($0.windowID).inserted }

        return SCContentFilter(
            display: display,
            excludingApplications: uniqueApps,
            exceptingWindows: uniqueWindows
        )
    }
}
