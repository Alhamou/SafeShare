import XCTest
@testable import SafeShareKit

/// In-memory persistence so these tests never touch the user's real config file.
private final class MemoryPersistence: ConfigPersisting, @unchecked Sendable {
    var saved: SafeShareConfig?
    func loadConfig() throws -> SafeShareConfig? { saved }
    func saveConfig(_ config: SafeShareConfig) throws { saved = config }
}

@MainActor
final class RuleStoreOverrideScopeTests: XCTestCase {
    func testResetWindowOverridesOnlyAffectsThatBundle() {
        let store = RuleStore(persistence: MemoryPersistence())
        store.setWindowOverride(windowID: 10, state: .forceProtect, bundleID: "com.google.Chrome")
        store.setWindowOverride(windowID: 11, state: .forceVisible, bundleID: "com.google.Chrome")
        store.setWindowOverride(windowID: 20, state: .forceProtect, bundleID: "com.apple.Terminal")

        store.resetWindowOverrides(for: "com.google.Chrome")

        XCTAssertEqual(store.windowOverride(for: 10), .inherit)
        XCTAssertEqual(store.windowOverride(for: 11), .inherit)
        XCTAssertEqual(store.windowOverride(for: 20), .forceProtect, "other apps must keep their overrides")
    }

    func testResetWindowOverridesIgnoresWindowsWithUnknownOwner() {
        let store = RuleStore(persistence: MemoryPersistence())
        store.setWindowOverride(windowID: 30, state: .forceProtect) // legacy call, owner unknown
        store.resetWindowOverrides(for: "com.example.App")
        XCTAssertEqual(store.windowOverride(for: 30), .forceProtect)
    }

    func testInheritRemovesOverrideAndOwnership() {
        let store = RuleStore(persistence: MemoryPersistence())
        store.setWindowOverride(windowID: 40, state: .forceProtect, bundleID: "com.example.App")
        store.setWindowOverride(windowID: 40, state: .inherit, bundleID: "com.example.App")
        XCTAssertEqual(store.windowOverride(for: 40), .inherit)
        XCTAssertTrue(store.windowOverrides.isEmpty)
    }

    func testResetAllRulesClearsOverrides() {
        let store = RuleStore(persistence: MemoryPersistence())
        store.setWindowOverride(windowID: 50, state: .forceVisible, bundleID: "com.example.App")
        store.resetAllRules()
        XCTAssertTrue(store.windowOverrides.isEmpty)
        // Ownership map was cleared too: a later reset for the bundle has nothing to do.
        store.setWindowOverride(windowID: 50, state: .forceVisible)
        store.resetWindowOverrides(for: "com.example.App")
        XCTAssertEqual(store.windowOverride(for: 50), .forceVisible)
    }
}
