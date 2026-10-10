import XCTest
@testable import SafeShareKit

@MainActor
final class RuleStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var tempConfigFile: URL!
    private var persistence: FileConfigPersistence!

    override func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        tempConfigFile = tempDirectory.appendingPathComponent("test_config.json")
        persistence = FileConfigPersistence(fileURL: tempConfigFile)
    }

    override func tearDown() async throws {
        if let dir = tempDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    func testDefaultStateResolution() {
        let store = RuleStore(persistence: persistence)
        
        // No rules defined -> defaults to unprotected
        let state = store.effectiveState(for: "com.apple.Safari", pid: 1234, windowID: 55)
        XCTAssertEqual(state, .unprotected)
    }

    func testApplicationRulePersistence() throws {
        let store = RuleStore(persistence: persistence)
        store.setApplicationRule(bundleID: "com.tinyspeck.slackmacgap", state: .protected)
        
        XCTAssertTrue(store.isApplicationProtected(bundleID: "com.tinyspeck.slackmacgap"))
        XCTAssertEqual(store.effectiveState(for: "com.tinyspeck.slackmacgap"), .protected)

        // Create a new store instance with the same file to verify persistence
        let storeReloaded = RuleStore(persistence: persistence)
        XCTAssertTrue(storeReloaded.isApplicationProtected(bundleID: "com.tinyspeck.slackmacgap"))
    }

    func testWindowOverridePrecedence() {
        let store = RuleStore(persistence: persistence)
        let slackBundleID = "com.tinyspeck.slackmacgap"
        
        // App is protected
        store.setApplicationRule(bundleID: slackBundleID, state: .protected)
        XCTAssertEqual(store.effectiveState(for: slackBundleID, pid: 100, windowID: 1001), .protected)
        
        // Window 1002 is given explicit forceVisible override
        store.setWindowOverride(windowID: 1002, state: .forceVisible)
        XCTAssertEqual(store.effectiveState(for: slackBundleID, pid: 100, windowID: 1002), .unprotected)
        
        // Window 1001 still inherits protection
        XCTAssertEqual(store.effectiveState(for: slackBundleID, pid: 100, windowID: 1001), .protected)
    }

    func testInstanceOverridePrecedence() {
        let store = RuleStore(persistence: persistence)
        let appBundleID = "com.google.Chrome"
        
        // App is unprotected by default
        store.setApplicationRule(bundleID: appBundleID, state: .unprotected)
        
        // Instance PID 500 is overridden to protected
        store.setInstanceOverride(pid: 500, state: .protected)
        XCTAssertEqual(store.effectiveState(for: appBundleID, pid: 500, windowID: 200), .protected)
        
        // Instance PID 600 inherits app unprotected state
        XCTAssertEqual(store.effectiveState(for: appBundleID, pid: 600, windowID: 300), .unprotected)
        
        // Window override takes precedence over instance override
        store.setWindowOverride(windowID: 201, state: .forceVisible)
        XCTAssertEqual(store.effectiveState(for: appBundleID, pid: 500, windowID: 201), .unprotected)
    }

    func testResetAllRules() {
        let store = RuleStore(persistence: persistence)
        store.setApplicationRule(bundleID: "com.tinyspeck.slackmacgap", state: .protected)
        store.setWindowOverride(windowID: 44, state: .forceVisible)
        store.resetAllRules()
        
        XCTAssertFalse(store.isApplicationProtected(bundleID: "com.tinyspeck.slackmacgap"))
        XCTAssertEqual(store.windowOverride(for: 44), .inherit)
    }
}
