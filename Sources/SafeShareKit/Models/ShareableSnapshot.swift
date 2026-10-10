import Foundation
import ScreenCaptureKit
import CoreGraphics

public struct WindowDescriptor: Identifiable, Sendable, Equatable {
    public var id: CGWindowID { windowID }
    public let windowID: CGWindowID
    public let title: String
    public let frame: CGRect
    public let isOnScreen: Bool
    public let owningPID: pid_t
    public let owningBundleID: String

    public init(
        windowID: CGWindowID,
        title: String,
        frame: CGRect,
        isOnScreen: Bool,
        owningPID: pid_t,
        owningBundleID: String
    ) {
        self.windowID = windowID
        self.title = title
        self.frame = frame
        self.isOnScreen = isOnScreen
        self.owningPID = owningPID
        self.owningBundleID = owningBundleID
    }
}

public struct ShareableSnapshot: @unchecked Sendable {
    public let displays: [SCDisplay]
    public let applications: [SCRunningApplication]
    public let windows: [SCWindow]
    public let timestamp: Date

    public init(
        displays: [SCDisplay],
        applications: [SCRunningApplication],
        windows: [SCWindow],
        timestamp: Date = Date()
    ) {
        self.displays = displays
        self.applications = applications
        self.windows = windows
        self.timestamp = timestamp
    }
}
