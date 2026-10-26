import Foundation
import CoreGraphics
import Combine

@MainActor
public protocol RuleStoring: AnyObject {
    var config: SafeShareConfig { get }
    func effectiveState(for bundleID: String, pid: pid_t?, windowID: CGWindowID?) -> ProtectionState
    func setApplicationRule(bundleID: String, state: ProtectionState, customDisplayName: String?)
    func setWindowOverride(windowID: CGWindowID, state: ProtectionOverride)
    func resetWindowOverrides(for bundleID: String)
    func isApplicationProtected(bundleID: String) -> Bool
    func windowOverride(for windowID: CGWindowID) -> ProtectionOverride
}

@MainActor
public final class RuleStore: ObservableObject, RuleStoring {
    @Published public private(set) var config: SafeShareConfig
    
    // In-memory runtime overrides (Session-only, not persisted to disk)
    @Published public private(set) var windowOverrides: [CGWindowID: ProtectionOverride] = [:]
    @Published public private(set) var instanceOverrides: [pid_t: ProtectionState] = [:]
    /// Which bundle each overridden window belongs to, so overrides can be reset per app.
    private var windowOverrideOwners: [CGWindowID: String] = [:]

    private let persistence: ConfigPersisting
    private var cancellables = Set<AnyCancellable>()

    public init(persistence: ConfigPersisting = FileConfigPersistence()) {
        self.persistence = persistence
        do {
            if let saved = try persistence.loadConfig() {
                self.config = saved
            } else {
                self.config = SafeShareConfig()
            }
        } catch {
            print("[RuleStore] Warning: Failed to load config, initializing with defaults: \(error)")
            self.config = SafeShareConfig()
        }
    }

    public func effectiveState(for bundleID: String, pid: pid_t? = nil, windowID: CGWindowID? = nil) -> ProtectionState {
        // 1. Explicit window override
        if let winID = windowID, let winOverride = windowOverrides[winID], winOverride != .inherit {
            switch winOverride {
            case .forceProtect:
                return .protected
            case .forceVisible:
                return .unprotected
            case .inherit:
                break
            }
        }

        // 2. Explicit instance/PID override
        if let p = pid, let instOverride = instanceOverrides[p] {
            return instOverride
        }

        // 3. Application-level rule
        if let appRule = config.applicationRules.first(where: { $0.bundleIdentifier == bundleID }) {
            return appRule.state
        }

        // 4. Global default policy
        return config.globalDefaultState
    }

    public func isApplicationProtected(bundleID: String) -> Bool {
        if let rule = config.applicationRules.first(where: { $0.bundleIdentifier == bundleID }) {
            return rule.state == .protected
        }
        return config.globalDefaultState == .protected
    }

    public func windowOverride(for windowID: CGWindowID) -> ProtectionOverride {
        return windowOverrides[windowID] ?? .inherit
    }

    public func setApplicationRule(bundleID: String, state: ProtectionState, customDisplayName: String? = nil) {
        if let index = config.applicationRules.firstIndex(where: { $0.bundleIdentifier == bundleID }) {
            config.applicationRules[index].state = state
            if let name = customDisplayName {
                config.applicationRules[index].customDisplayName = name
            }
        } else {
            config.applicationRules.append(ApplicationRule(
                bundleIdentifier: bundleID,
                state: state,
                customDisplayName: customDisplayName
            ))
        }
        save()
    }

    public func setWindowOverride(windowID: CGWindowID, state: ProtectionOverride) {
        setWindowOverride(windowID: windowID, state: state, bundleID: nil)
    }

    /// Sets a window override and records the owning bundle (when known) so that
    /// `resetWindowOverrides(for:)` can later remove exactly this app's overrides.
    public func setWindowOverride(windowID: CGWindowID, state: ProtectionOverride, bundleID: String?) {
        if state == .inherit {
            windowOverrides.removeValue(forKey: windowID)
            windowOverrideOwners.removeValue(forKey: windowID)
        } else {
            windowOverrides[windowID] = state
            if let bundleID = bundleID {
                windowOverrideOwners[windowID] = bundleID
            }
        }
    }

    public func setInstanceOverride(pid: pid_t, state: ProtectionState?) {
        if let st = state {
            instanceOverrides[pid] = st
        } else {
            instanceOverrides.removeValue(forKey: pid)
        }
    }

    public func resetWindowOverrides(for bundleID: String) {
        // Purge only the overrides recorded for this bundle's windows; other apps keep theirs.
        let owned = windowOverrideOwners.filter { $0.value == bundleID }.map(\.key)
        for windowID in owned {
            windowOverrides.removeValue(forKey: windowID)
            windowOverrideOwners.removeValue(forKey: windowID)
        }
    }

    public func updateStreamSettings(_ settings: StreamSettings) {
        config.streamSettings = settings
        save()
    }

    public func updateUIPreferences(_ prefs: UIPreferences) {
        config.uiPreferences = prefs
        save()
    }

    public func resetAllRules() {
        config.applicationRules.removeAll()
        windowOverrides.removeAll()
        windowOverrideOwners.removeAll()
        instanceOverrides.removeAll()
        save()
    }

    private func save() {
        do {
            try persistence.saveConfig(config)
        } catch {
            print("[RuleStore] Error saving config: \(error)")
        }
    }
}
