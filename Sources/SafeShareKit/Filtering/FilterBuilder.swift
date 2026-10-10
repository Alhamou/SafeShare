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
        var excludingSpecificWindows: [SCWindow] = []

        // 1. Mandatory Self-Exclusion: Exclude SafeShare to prevent recursive mirroring
        if let selfApp = snapshot.applications.first(where: { $0.processID == selfPID }) {
            excludingApps.append(selfApp)
        }

        // 2. Resolve rules for all other applications
        for app in snapshot.applications where app.processID != selfPID {
            let bundleID = app.bundleIdentifier
            let appState = rules.effectiveState(for: bundleID, pid: app.processID, windowID: nil)
            let appWindows = snapshot.windows.filter { $0.owningApplication?.processID == app.processID }

            if appState == .protected {
                excludingApps.append(app)
                // Check if any window has an explicit visible override (.forceVisible)
                for window in appWindows {
                    let winState = rules.effectiveState(for: bundleID, pid: app.processID, windowID: window.windowID)
                    if winState == .unprotected {
                        exceptingWindows.append(window)
                    }
                }
            } else {
                // Application is unprotected, check if any specific window is protected
                for window in appWindows {
                    let winState = rules.effectiveState(for: bundleID, pid: app.processID, windowID: window.windowID)
                    if winState == .protected {
                        excludingSpecificWindows.append(window)
                    }
                }
            }
        }

        // 3. Construct filter
        if #available(macOS 14.0, *), !excludingSpecificWindows.isEmpty, excludingApps.isEmpty {
            // When only individual windows are excluded and no full applications are excluded
            return SCContentFilter(display: display, excludingWindows: excludingSpecificWindows)
        } else {
            return SCContentFilter(
                display: display,
                excludingApplications: excludingApps,
                exceptingWindows: exceptingWindows
            )
        }
    }
}
