import Foundation
import ScreenCaptureKit
import CoreMedia
import Combine

@MainActor
public final class AppStateCoordinator: NSObject, ObservableObject, CaptureEngineDelegate, ScreenWatchdogDelegate {
    @Published public private(set) var isCapturing: Bool = false
    @Published public private(set) var statusMessage: String = "Ready"
    @Published public private(set) var fps: Double = 0.0
    /// Total frames rendered this session. Updated together with `fps` once per second;
    /// publishing it per frame re-rendered the whole popover up to 60 times a second.
    public private(set) var frameCount: Int = 0
    @Published public private(set) var applicationGroups: [ApplicationGroup] = []
    @Published public private(set) var isSafeViewWindowOpen: Bool = false
    @Published public private(set) var hasScreenRecordingPermission: Bool = false
    /// Resolution viewers actually receive from the Safe View window (nil when not streaming).
    @Published public private(set) var outputMetrics: SafeViewOutputMetrics? = nil
    @Published public var isShowingSettings: Bool = false

    public func resetNavigationState() {
        isShowingSettings = false
    }

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
    private var blankState = PrivacyBlankState()
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
        self.outputSurface.onClose = { [weak self] in
            guard let self = self else { return }
            self.isSafeViewWindowOpen = false
            if self.isCapturing {
                Task { @MainActor [weak self] in
                    await self?.stopSafeView()
                }
            }
        }
        self.outputSurface.onOutputMetricsChange = { [weak self] metrics in
            self?.outputMetrics = metrics
        }

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

    public func setWindowOverride(windowID: CGWindowID, state: ProtectionOverride, bundleID: String? = nil) {
        ruleStore.setWindowOverride(windowID: windowID, state: state, bundleID: bundleID)
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

        // 1. Show the Safe View window first so WindowServer registers its presence.
        //    Seed it with the geometry of the display we already know about so it opens at
        //    a readable size with the right aspect ratio.
        if let knownDisplay = activeDisplay {
            applyDisplayGeometry(of: knownDisplay)
        }
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

            let pixelSize = applyDisplayGeometry(of: display)
            let config = makeCaptureConfiguration(pixelSize: pixelSize)

            try await captureEngine.startCapture(display: display, filter: filter, config: config)
            self.isCapturing = true
            // A previous failure or lock may have left the output blanked; the new stream is live.
            self.blankState.clearAll()
            self.outputSurface.unblankOutput()
            self.frameCount = 0
            self.framesSinceLastUpdate = 0
            self.fps = 0.0
            self.lastFPSUpdateTime = Date()
            self.statusMessage = "Safe View live on Display \(display.displayID) at \(config.targetFPS) FPS (\(config.width) × \(config.height) px)"
        } catch {
            self.statusMessage = "Failed to start Safe View: \(error.localizedDescription)"
        }
    }

    public func stopSafeView() async {
        do {
            try await captureEngine.stopCapture()
            self.isCapturing = false
            self.statusMessage = "Safe View stopped"
            // Stopping is deliberate: close the window outright so the meeting app drops the
            // share and nothing lingers on screen. A fresh window is created on the next start.
            outputSurface.closeSafeView()
            self.isSafeViewWindowOpen = false
            self.fps = 0.0
            self.blankState.clearAll()
        } catch {
            self.statusMessage = "Error stopping stream: \(error.localizedDescription)"
        }
    }

    public func focusSafeViewWindow() {
        outputSurface.showSafeView()
        self.isSafeViewWindowOpen = true
    }

    /// Parks the Safe View window behind all other windows without shrinking it, so the
    /// shared picture keeps its full resolution while the presenter works.
    public func sendSafeViewToBack() {
        guard isSafeViewWindowOpen else { return }
        outputSurface.sendToBack()
    }

    /// Pushes the captured display's geometry to the output window and returns the native
    /// pixel size that the capture configuration must use.
    @discardableResult
    private func applyDisplayGeometry(of display: SCDisplay) -> CGSize {
        let pointSize = DisplayGeometry.pointSize(for: display)
        let pixelSize = DisplayGeometry.pixelSize(for: display)
        outputSurface.applyDisplayGeometry(pointSize: pointSize, pixelSize: pixelSize)
        return pixelSize
    }

    private func makeCaptureConfiguration(pixelSize: CGSize) -> CaptureConfiguration {
        CaptureConfiguration(
            width: Int(pixelSize.width),
            height: Int(pixelSize.height),
            targetFPS: ruleStore.config.streamSettings.targetFPS,
            showsCursor: ruleStore.config.streamSettings.showCursor
        )
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

        let pixelSize = applyDisplayGeometry(of: display)
        let config = makeCaptureConfiguration(pixelSize: pixelSize)
        do {
            try await captureEngine.updateConfiguration(config)
            print("[AppStateCoordinator] Successfully synced stream configuration (FPS: \(config.targetFPS), Cursor: \(config.showsCursor), \(config.width) × \(config.height) px)")
        } catch {
            print("[AppStateCoordinator] Failed to sync stream configuration: \(error)")
        }
    }

    // MARK: - CaptureEngineDelegate
    public nonisolated func captureEngine(_ engine: CaptureEngining, didOutput frame: CMSampleBuffer) {
        outputSurface.render(sampleBuffer: frame)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.framesSinceLastUpdate += 1

            let now = Date()
            let elapsed = now.timeIntervalSince(self.lastFPSUpdateTime)
            if elapsed >= 1.0 {
                self.frameCount += self.framesSinceLastUpdate
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
            self.fps = 0.0
            self.statusMessage = "Capture failed: \(error.localizedDescription)"
            self.raiseBlank(.userPaused)
        }
    }

    public nonisolated func captureEngineNeedsPrivacyBlanking(_ engine: CaptureEngining) {
        DispatchQueue.main.async { [weak self] in
            self?.raiseBlank(.filterTransition)
        }
    }

    // MARK: - Privacy blanking

    /// "Fail-Closed Privacy Blanking" preference: blank on lock/sleep only when enabled.
    private var isFailClosedBlankingEnabled: Bool {
        ruleStore.config.streamSettings.failClosedBlanking
    }

    private func raiseBlank(_ reason: PrivacyBlankReason) {
        let shown = blankState.raise(reason)
        outputSurface.blankOutput(reason: shown)
    }

    /// Clears one reason; the output stays blanked while any other reason is still active
    /// (e.g. display woke up but the session is still locked).
    private func clearBlank(_ reason: PrivacyBlankReason) {
        if let remaining = blankState.clear(reason) {
            outputSurface.blankOutput(reason: remaining)
        } else {
            outputSurface.unblankOutput()
        }
    }

    // MARK: - ScreenWatchdogDelegate
    public func screenWatchdogDidDetectScreenSleep() {
        guard isCapturing, isFailClosedBlankingEnabled else { return }
        raiseBlank(.screenAsleep)
    }

    public func screenWatchdogDidDetectScreenWake() {
        guard isCapturing else { return }
        clearBlank(.screenAsleep)
    }

    public func screenWatchdogDidDetectScreenLock() {
        guard isCapturing, isFailClosedBlankingEnabled else { return }
        raiseBlank(.screenLocked)
    }

    public func screenWatchdogDidDetectScreenUnlock() {
        guard isCapturing else { return }
        clearBlank(.screenLocked)
    }

    public func screenWatchdogDidChangeScreenParameters() {
        Task {
            await self.refreshApps()
            if self.isCapturing {
                await self.syncActiveFilter()
                // A resolution/scale change alters the native pixel size of the display.
                await self.syncActiveConfiguration()
            }
        }
    }
}
