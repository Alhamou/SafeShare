import Foundation
import AppKit
import CoreGraphics
import Combine

@MainActor
public protocol PermissionsCoordinating: AnyObject {
    var hasScreenRecordingPermission: Bool { get }
    func requestScreenRecordingPermission() -> Bool
    func refreshPermissionStatus()
}

@MainActor
public final class PermissionsCoordinator: ObservableObject, PermissionsCoordinating {
    @Published public private(set) var hasScreenRecordingPermission: Bool = false

    private var pollTimer: AnyCancellable?

    public init() {
        refreshPermissionStatus()
        startPeriodicCheck()
    }

    public func refreshPermissionStatus() {
        let granted = CGPreflightScreenCaptureAccess()
        if granted != hasScreenRecordingPermission {
            print("[PermissionsCoordinator] Permission status changed from \(hasScreenRecordingPermission) to \(granted)")
            hasScreenRecordingPermission = granted
        }
    }

    @discardableResult
    public func requestScreenRecordingPermission() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        hasScreenRecordingPermission = granted
        if !granted {
            openSystemSettingsScreenRecording()
        }
        return granted
    }

    public func openSystemSettingsScreenRecording() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startPeriodicCheck() {
        // Poll every 1.5 seconds if permission is not yet granted so UI auto-unlocks when user enables in Settings
        pollTimer = Timer.publish(every: 1.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if !self.hasScreenRecordingPermission {
                    self.refreshPermissionStatus()
                }
            }
    }

    deinit {
        pollTimer?.cancel()
    }
}
