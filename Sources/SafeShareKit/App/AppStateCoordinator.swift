import Foundation
import ScreenCaptureKit
import CoreMedia
import Combine

@MainActor
public final class AppStateCoordinator: NSObject, ObservableObject, CaptureEngineDelegate, ScreenWatchdogDelegate {
    @Published public private(set) var isCapturing: Bool = false
    @Published public private(set) var statusMessage: String = "Ready"
    @Published public private(set) var fps: Double = 0.0
    @Published public private(set) var frameCount: Int = 0
    @Published public private(set) var applicationGroups: [ApplicationGroup] = []
    @Published public private(set) var isSafeViewWindowOpen: Bool = false
    @Published public private(set) var hasScreenRecordingPermission: Bool = false

    public let permissions: PermissionsCoordinator
    public let scanner: AppScanner
    public let ruleStore: RuleStore
    public let resolver: InstanceResolver
    public let filterBuilder: FilterBuilder
    public let captureEngine: CaptureEngine
    public let outputSurface: SafeViewController
    public let watchdog: ScreenWatchdog

    private var cancellables = Set<AnyCancellable>()
    private var lastFPSUpdateTime = Date()
    private var framesSinceLastUpdate = 0
    private let selfPID: pid_t

    public init(
        permissions: PermissionsCoordinator? = nil,
        scanner: AppScanner? = nil,
        ruleStore: RuleStore? = nil,
        resolver: InstanceResolver? = nil,
        filterBuilder: FilterBuilder? = nil,
        captureEngine: CaptureEngine? = nil,
        outputSurface: SafeViewController? = nil,
        watchdog: ScreenWatchdog? = nil,
        selfPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) {
        let perm = permissions ?? PermissionsCoordinator()
        let scan = scanner ?? AppScanner()
        let store = ruleStore ?? RuleStore()
        let res = resolver ?? InstanceResolver()
        let fb = filterBuilder ?? FilterBuilder()
        let engine = captureEngine ?? CaptureEngine()
        let surface = outputSurface ?? SafeViewController()
        let dog = watchdog ?? ScreenWatchdog()

        self.permissions = perm
        self.scanner = scan
        self.ruleStore = store
        self.resolver = res
        self.filterBuilder = fb
        self.captureEngine = engine
        self.outputSurface = surface
        self.watchdog = dog
        self.selfPID = selfPID
        super.init()

        self.captureEngine.delegate = self
        self.watchdog.delegate = self

        // Forward RuleStore mutations to update active stream
        self.ruleStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if self.isCapturing {
                        await self.syncActiveFilter()
                        await self.syncActiveConfiguration()
                    }
                }
            }
            .store(in: &cancellables)

        self.hasScreenRecordingPermission = perm.hasScreenRecordingPermission

        // Automatically scan when Screen Recording permission is granted
        self.permissions.$hasScreenRecordingPermission
            .sink { [weak self] granted in
                guard let self = self else { return }
                self.hasScreenRecordingPermission = granted
                if granted {
                    Task { @MainActor in
                        await self.refreshApps()
                    }
                }
            }
            .store(in: &cancellables)

        // Start scanning running apps only if permission already exists
        if self.permissions.hasScreenRecordingPermission {
            Task {
                await self.refreshApps()
            }
        } else {
            self.statusMessage = "Screen Recording permission needed to discover windows."
        }

        // Start monitoring workspace changes (app launch/exit)
        self.scanner.startMonitoring { [weak self] in
            Task { @MainActor [weak self] in
                await self?.handleSystemContentChange()
            }
        }
    }

    public func refreshApps() async {
        guard permissions.hasScreenRecordingPermission else {
            statusMessage = "Screen Recording permission needed to discover windows."
            return
        }

        do {
            let snapshot = try await scanner.refresh()
            self.applicationGroups = resolver.resolve(snapshot: snapshot, selfPID: selfPID)
            statusMessage = "Discovered \(applicationGroups.count) running apps"
            print("[AppStateCoordinator] Discovered \(applicationGroups.count) apps on \(snapshot.displays.count) display(s)")
        } catch {
            statusMessage = "Scan error: \(error.localizedDescription)"
            print("[AppStateCoordinator] Scan error: \(error)")
        }
    }

    private func handleSystemContentChange() async {
        guard let snapshot = scanner.currentSnapshot else { return }
        self.applicationGroups = resolver.resolve(snapshot: snapshot, selfPID: selfPID)
        if isCapturing {
            await syncActiveFilter()
        }
    }

    public func toggleProtection(bundleID: String) {
        let isProtected = ruleStore.isApplicationProtected(bundleID: bundleID)
        let newState: ProtectionState = isProtected ? .unprotected : .protected
        ruleStore.setApplicationRule(bundleID: bundleID, state: newState)
        statusMessage = "\(bundleID) is now \(newState.rawValue.uppercased())"
    }

    public func setWindowOverride(windowID: CGWindowID, state: ProtectionOverride) {
        ruleStore.setWindowOverride(windowID: windowID, state: state)
        Task {
            await syncActiveFilter()
        }
    }

    public var activeDisplay: SCDisplay? {
        guard let snapshot = scanner.currentSnapshot else { return nil }
        if let chosenID = ruleStore.config.streamSettings.selectedDisplayID,
           let matched = snapshot.displays.first(where: { $0.displayID == chosenID }) {
            return matched
        }
        return snapshot.displays.first
    }

    public func setTargetDisplay(displayID: UInt32) {
        var settings = ruleStore.config.streamSettings
        settings.selectedDisplayID = displayID
        ruleStore.updateStreamSettings(settings)
        if isCapturing {
            Task {
                await self.syncActiveFilter()
                await self.syncActiveConfiguration()
            }
        }
    }

    public func startSafeView() async {
        guard permissions.hasScreenRecordingPermission else {
            statusMessage = "Screen Recording permission required."
            permissions.requestScreenRecordingPermission()
            return
        }

        // 1. Show the Safe View window first so WindowServer registers its presence
        outputSurface.showSafeView()
        self.isSafeViewWindowOpen = true

        // 2. Perform a fresh scan with the window open so SCShareableContent contains SafeShare
        let activeSnapshot: ShareableSnapshot
        do {
            activeSnapshot = try await scanner.refresh()
            self.applicationGroups = resolver.resolve(snapshot: activeSnapshot, selfPID: selfPID)
        } catch {
            statusMessage = "Failed to scan windows: \(error.localizedDescription)"
            return
        }

        guard let display = activeDisplay else {
            statusMessage = "No display available for capture."
            return
        }

        do {
            let filter = try filterBuilder.buildFilter(
                for: display,
                snapshot: activeSnapshot,
                rules: ruleStore,
                selfPID: selfPID
            )

            let targetFPS = ruleStore.config.streamSettings.targetFPS
            let showCursor = ruleStore.config.streamSettings.showCursor
            let config = CaptureConfiguration(
                width: display.width,
                height: display.height,
                targetFPS: targetFPS,
                showsCursor: showCursor
            )

            try await captureEngine.startCapture(display: display, filter: filter, config: config)
            self.isCapturing = true
            self.statusMessage = "Safe View live on Display \(display.displayID) at \(targetFPS) FPS"
        } catch {
            self.statusMessage = "Failed to start Safe View: \(error.localizedDescription)"
        }
    }

    public func stopSafeView() async {
        do {
            try await captureEngine.stopCapture()
            self.isCapturing = false
            self.statusMessage = "Safe View stopped"
            outputSurface.hideSafeView()
            self.isSafeViewWindowOpen = false
            self.fps = 0.0
        } catch {
            self.statusMessage = "Error stopping stream: \(error.localizedDescription)"
        }
    }

    public func focusSafeViewWindow() {
        outputSurface.showSafeView()
        self.isSafeViewWindowOpen = true
    }

    private func syncActiveFilter() async {
        guard isCapturing,
              let snapshot = scanner.currentSnapshot,
              let display = activeDisplay else { return }

        do {
            let newFilter = try filterBuilder.buildFilter(
                for: display,
                snapshot: snapshot,
                rules: ruleStore,
                selfPID: selfPID
            )
            try await captureEngine.updateFilter(newFilter)
        } catch {
            print("[AppStateCoordinator] Failed to sync filter: \(error)")
        }
    }

    public func syncActiveConfiguration() async {
        guard isCapturing,
              let display = activeDisplay else { return }

        let targetFPS = ruleStore.config.streamSettings.targetFPS
        let showCursor = ruleStore.config.streamSettings.showCursor
        let config = CaptureConfiguration(
            width: display.width,
            height: display.height,
            targetFPS: targetFPS,
            showsCursor: showCursor
        )
        do {
            try await captureEngine.updateConfiguration(config)
            print("[AppStateCoordinator] Successfully synced stream configuration (FPS: \(targetFPS), Cursor: \(showCursor))")
        } catch {
            print("[AppStateCoordinator] Failed to sync stream configuration: \(error)")
        }
    }

    // MARK: - CaptureEngineDelegate
    public nonisolated func captureEngine(_ engine: CaptureEngining, didOutput frame: CMSampleBuffer) {
        outputSurface.render(sampleBuffer: frame)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.frameCount += 1
            self.framesSinceLastUpdate += 1

            let now = Date()
            let elapsed = now.timeIntervalSince(self.lastFPSUpdateTime)
            if elapsed >= 1.0 {
                self.fps = Double(self.framesSinceLastUpdate) / elapsed
                self.framesSinceLastUpdate = 0
                self.lastFPSUpdateTime = now
            }
        }
    }

    public nonisolated func captureEngine(_ engine: CaptureEngining, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isCapturing = false
            self.statusMessage = "Capture failed: \(error.localizedDescription)"
            self.outputSurface.blankOutput(reason: .userPaused)
        }
    }

    public nonisolated func captureEngineNeedsPrivacyBlanking(_ engine: CaptureEngining) {
        DispatchQueue.main.async { [weak self] in
            self?.outputSurface.blankOutput(reason: .filterTransition)
        }
    }

    // MARK: - ScreenWatchdogDelegate
    public func screenWatchdogDidDetectScreenSleep() {
        if isCapturing {
            outputSurface.blankOutput(reason: .screenLocked)
        }
    }

    public func screenWatchdogDidDetectScreenWake() {
        if isCapturing {
            outputSurface.unblankOutput()
        }
    }

    public func screenWatchdogDidDetectScreenLock() {
        if isCapturing {
            outputSurface.blankOutput(reason: .screenLocked)
        }
    }

    public func screenWatchdogDidDetectScreenUnlock() {
        if isCapturing {
            outputSurface.unblankOutput()
        }
    }

    public func screenWatchdogDidChangeScreenParameters() {
        Task {
            await self.refreshApps()
            if self.isCapturing {
                await self.syncActiveFilter()
            }
        }
    }
}
