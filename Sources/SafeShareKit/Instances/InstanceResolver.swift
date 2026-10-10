import Foundation
import ScreenCaptureKit
import AppKit

public struct ProcessInstance: Identifiable, Sendable {
    public var id: pid_t { processID }
    public let processID: pid_t
    public let windows: [WindowDescriptor]

    public init(processID: pid_t, windows: [WindowDescriptor]) {
        self.processID = processID
        self.windows = windows
    }
}

public struct ApplicationGroup: Identifiable, Sendable {
    public var id: String { bundleIdentifier }
    public let bundleIdentifier: String
    public let displayName: String
    public let instances: [ProcessInstance]
    public var allWindows: [WindowDescriptor] {
        instances.flatMap { $0.windows }
    }

    public init(bundleIdentifier: String, displayName: String, instances: [ProcessInstance]) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.instances = instances
    }
}

public protocol InstanceResolving: Sendable {
    func resolve(snapshot: ShareableSnapshot, selfPID: pid_t) -> [ApplicationGroup]
}

public final class InstanceResolver: InstanceResolving {
    public init() {}

    public func resolve(snapshot: ShareableSnapshot, selfPID: pid_t) -> [ApplicationGroup] {
        // Exclude SafeShare self
        let foreignApps = snapshot.applications.filter {
            $0.processID != selfPID && !$0.bundleIdentifier.isEmpty && !$0.applicationName.isEmpty
        }

        // Group by bundle identifier
        let grouped = Dictionary(grouping: foreignApps, by: { $0.bundleIdentifier })

        var result: [ApplicationGroup] = []

        for (bundleID, apps) in grouped {
            let displayName = apps.first?.applicationName ?? bundleID
            
            var instances: [ProcessInstance] = []
            for app in apps {
                let pid = app.processID
                let appWindows = snapshot.windows
                    .filter { $0.owningApplication?.processID == pid }
                    .map { win in
                        WindowDescriptor(
                            windowID: win.windowID,
                            title: win.title ?? "Untitled Window",
                            frame: win.frame,
                            isOnScreen: win.isOnScreen,
                            owningPID: pid,
                            owningBundleID: bundleID
                        )
                    }
                instances.append(ProcessInstance(processID: pid, windows: appWindows))
            }

            result.append(ApplicationGroup(
                bundleIdentifier: bundleID,
                displayName: displayName,
                instances: instances
            ))
        }

        return result.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }
}
