import Foundation
import ScreenCaptureKit
import AppKit
import Combine

@MainActor
public protocol AppScanning: AnyObject {
    var currentSnapshot: ShareableSnapshot? { get }
    var runningApplications: [SCRunningApplication] { get }
    var displays: [SCDisplay] { get }
    func refresh() async throws -> ShareableSnapshot
    func startMonitoring(onChange: @escaping @MainActor () -> Void)
    func stopMonitoring()
}

@MainActor
public final class AppScanner: ObservableObject, AppScanning {
    @Published public private(set) var currentSnapshot: ShareableSnapshot?
    @Published public private(set) var runningApplications: [SCRunningApplication] = []
    @Published public private(set) var displays: [SCDisplay] = []
    
    private var workspaceObservers: [NSObjectProtocol] = []
    private var changeHandler: (@MainActor () -> Void)?
    private var debounceTask: Task<Void, Never>?
    private let selfPID: pid_t

    public init(selfPID: pid_t = ProcessInfo.processInfo.processIdentifier) {
        self.selfPID = selfPID
    }

    @discardableResult
    public func refresh() async throws -> ShareableSnapshot {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        
        let validApps = content.applications
            .filter { $0.processID != selfPID && !$0.applicationName.isEmpty && !$0.bundleIdentifier.isEmpty }
            .sorted { $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName) == .orderedAscending }

        let snapshot = ShareableSnapshot(
            displays: content.displays,
            applications: content.applications,
            windows: content.windows,
            timestamp: Date()
        )

        self.currentSnapshot = snapshot
        self.displays = content.displays
        self.runningApplications = validApps
        return snapshot
    }

    public func startMonitoring(onChange: @escaping @MainActor () -> Void) {
        self.changeHandler = onChange
        stopMonitoring()

        let center = NSWorkspace.shared.notificationCenter
        let notifications: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification
        ]

        for name in notifications {
            let observer = center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.handleWorkspaceChange()
                }
            }
            workspaceObservers.append(observer)
        }
    }

    public func stopMonitoring() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            center.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func handleWorkspaceChange() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            // Coalesce events with 250ms debounce
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled, let self = self else { return }
            do {
                _ = try await self.refresh()
                self.changeHandler?()
            } catch {
                print("[AppScanner] Workspace change refresh failed: \(error)")
            }
        }
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            center.removeObserver(observer)
        }
    }
}
