import Foundation
import CoreGraphics

public enum ProtectionState: String, Codable, Sendable {
    case protected
    case unprotected
}

public enum ProtectionOverride: String, Codable, Sendable {
    case inherit
    case forceProtect
    case forceVisible
}

public struct ApplicationRule: Codable, Sendable, Identifiable, Equatable {
    public var id: String { bundleIdentifier }
    public let bundleIdentifier: String
    public var state: ProtectionState
    public var customDisplayName: String?

    public init(bundleIdentifier: String, state: ProtectionState, customDisplayName: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.state = state
        self.customDisplayName = customDisplayName
    }
}

public struct StreamSettings: Codable, Sendable, Equatable {
    public var targetFPS: Int
    public var showCursor: Bool
    public var selectedDisplayID: UInt32?
    public var failClosedBlanking: Bool
    public var excludeNotificationCenter: Bool

    public init(
        targetFPS: Int = 30,
        showCursor: Bool = true,
        selectedDisplayID: UInt32? = nil,
        failClosedBlanking: Bool = true,
        excludeNotificationCenter: Bool = true
    ) {
        self.targetFPS = targetFPS
        self.showCursor = showCursor
        self.selectedDisplayID = selectedDisplayID
        self.failClosedBlanking = failClosedBlanking
        self.excludeNotificationCenter = excludeNotificationCenter
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.targetFPS = try container.decodeIfPresent(Int.self, forKey: .targetFPS) ?? 30
        self.showCursor = try container.decodeIfPresent(Bool.self, forKey: .showCursor) ?? true
        self.selectedDisplayID = try container.decodeIfPresent(UInt32.self, forKey: .selectedDisplayID)
        self.failClosedBlanking = try container.decodeIfPresent(Bool.self, forKey: .failClosedBlanking) ?? true
        self.excludeNotificationCenter = try container.decodeIfPresent(Bool.self, forKey: .excludeNotificationCenter) ?? true
    }
}

public struct UIPreferences: Codable, Sendable, Equatable {
    public var launchAtLogin: Bool
    public var theme: String

    public init(launchAtLogin: Bool = false, theme: String = "system") {
        self.launchAtLogin = launchAtLogin
        self.theme = theme
    }
}

public struct SafeShareConfig: Codable, Sendable, Equatable {
    public var version: Int
    public var globalDefaultState: ProtectionState
    public var applicationRules: [ApplicationRule]
    public var streamSettings: StreamSettings
    public var uiPreferences: UIPreferences

    public init(
        version: Int = 1,
        globalDefaultState: ProtectionState = .unprotected,
        applicationRules: [ApplicationRule] = [],
        streamSettings: StreamSettings = StreamSettings(),
        uiPreferences: UIPreferences = UIPreferences()
    ) {
        self.version = version
        self.globalDefaultState = globalDefaultState
        self.applicationRules = applicationRules
        self.streamSettings = streamSettings
        self.uiPreferences = uiPreferences
    }
}
