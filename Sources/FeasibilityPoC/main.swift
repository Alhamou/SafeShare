import AppKit
import ScreenCaptureKit
import CoreMedia
import AVFoundation
import SwiftUI
import Combine

// MARK: - App Delegate & Entry Point

@main
final class PoCApplication: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var coordinator: PoCCoordinator?

    static func main() {
        let app = NSApplication.shared
        let delegate = PoCApplication()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        
        let coordinator = PoCCoordinator()
        self.coordinator = coordinator
        
        let contentView = PoCMainView(coordinator: coordinator)
        let hostingView = NSHostingView(rootView: contentView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1200, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SafeShare PoC — Safe View [Hardware Filter Testbed]"
        window.contentView = hostingView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

// MARK: - Safe Buffer Renderer Wrapper for Strict Concurrency

final class SafeBufferRenderer: @unchecked Sendable {
    let layer = AVSampleBufferDisplayLayer()

    init() {
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = CGColor(gray: 0.1, alpha: 1.0)
    }

    func enqueue(_ sampleBuffer: CMSampleBuffer) {
        layer.enqueue(sampleBuffer)
    }

    func flush() {
        layer.flushAndRemoveImage()
    }
}

// MARK: - PoC Coordinator & Capture Pipeline

@MainActor
final class PoCCoordinator: NSObject, ObservableObject, SCStreamOutput, SCStreamDelegate {
    @Published var permissionGranted: Bool = false
    @Published var isCapturing: Bool = false
    @Published var statusMessage: String = "Initializing..."
    @Published var runningApps: [SCRunningApplication] = []
    @Published var excludedBundleIDs: Set<String> = []
    @Published var frameCount: Int = 0
    @Published var currentFPS: Double = 0.0
    @Published var captureResolution: CGSize = .zero
    
    let renderer = SafeBufferRenderer()
    
    private var stream: SCStream?
    private var currentDisplay: SCDisplay?
    private var allWindows: [SCWindow] = []
    private var allApps: [SCRunningApplication] = []
    
    private let sampleQueue = DispatchQueue(label: "com.safeshare.poc.sampleQueue", qos: .userInteractive)
    private var lastFPSUpdateTime = Date()
    private var framesSinceLastFPSUpdate = 0

    override init() {
        super.init()
        checkPermissions()
    }

    func checkPermissions() {
        if #available(macOS 14.0, *) {
            permissionGranted = CGPreflightScreenCaptureAccess()
        } else {
            permissionGranted = CGPreflightScreenCaptureAccess()
        }
        
        if !permissionGranted {
            statusMessage = "Screen Recording permission needed. Click 'Request Permission'."
        } else {
            statusMessage = "Permission granted. Ready to inspect shareable content."
            Task {
                await refreshContent()
            }
        }
    }

    func requestPermission() {
        let granted = CGRequestScreenCaptureAccess()
        permissionGranted = granted
        if granted {
            statusMessage = "Permission granted!"
            Task {
                await refreshContent()
            }
        } else {
            statusMessage = "Please grant Screen Recording permission in System Settings > Privacy & Security."
        }
    }

    func refreshContent() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            self.currentDisplay = content.displays.first
            self.allWindows = content.windows
            self.allApps = content.applications
            
            // Filter apps that have windows or are ordinary GUI apps
            let currentPID = ProcessInfo.processInfo.processIdentifier
            let validApps = content.applications
                .filter { $0.processID != currentPID && !$0.applicationName.isEmpty && $0.bundleIdentifier != "" }
                .sorted { $0.applicationName.localizedCaseInsensitiveCompare($1.applicationName) == .orderedAscending }
            
            self.runningApps = validApps
            statusMessage = "Discovered \(content.displays.count) display(s), \(validApps.count) running apps, \(content.windows.count) windows."
        } catch {
            statusMessage = "Error fetching shareable content: \(error.localizedDescription)"
        }
    }

    func toggleAppExclusion(bundleID: String) {
        if excludedBundleIDs.contains(bundleID) {
            excludedBundleIDs.remove(bundleID)
        } else {
            excludedBundleIDs.insert(bundleID)
        }
        
        if isCapturing {
            Task {
                await updateActiveFilter()
            }
        }
    }

    func startCapture() async {
        guard let display = currentDisplay else {
            statusMessage = "No display detected."
            return
        }

        do {
            // Build filter
            let filter = try buildFilter(for: display)
            
            // Stream configuration
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30) // 30 FPS
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = true
            config.queueDepth = 3
            
            self.captureResolution = CGSize(width: display.width, height: display.height)
            
            let newStream = SCStream(filter: filter, configuration: config, delegate: self)
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            
            try await newStream.startCapture()
            self.stream = newStream
            self.isCapturing = true
            self.statusMessage = "Safe View stream capturing at 30 FPS. Filter active!"
        } catch {
            self.statusMessage = "Failed to start capture: \(error.localizedDescription)"
        }
    }

    func stopCapture() async {
        guard let stream = stream else { return }
        do {
            try await stream.stopCapture()
            self.stream = nil
            self.isCapturing = false
            self.statusMessage = "Capture stopped."
            renderer.flush()
        } catch {
            self.statusMessage = "Error stopping capture: \(error.localizedDescription)"
        }
    }

    private func buildFilter(for display: SCDisplay) throws -> SCContentFilter {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        
        // 1. Mandatory Self-Exclusion: Exclude SafeShare itself to prevent recursive capture
        var appsToExclude: [SCRunningApplication] = []
        if let selfApp = allApps.first(where: { $0.processID == currentPID }) {
            appsToExclude.append(selfApp)
        }
        
        // 2. Add user-selected excluded applications
        for app in allApps {
            if excludedBundleIDs.contains(app.bundleIdentifier) {
                if !appsToExclude.contains(where: { $0.processID == app.processID }) {
                    appsToExclude.append(app)
                }
            }
        }
        
        return SCContentFilter(display: display, excludingApplications: appsToExclude, exceptingWindows: [])
    }

    func updateActiveFilter() async {
        guard let stream = stream, let display = currentDisplay else { return }
        do {
            let filter = try buildFilter(for: display)
            try await stream.updateContentFilter(filter)
            self.statusMessage = "Filter updated dynamically (\(excludedBundleIDs.count) apps excluded)."
        } catch {
            self.statusMessage = "Filter update failed: \(error.localizedDescription)"
        }
    }

    // MARK: - SCStreamOutput
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        
        // Renderer safely enqueues buffer on sampleQueue directly
        renderer.enqueue(sampleBuffer)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.frameCount += 1
            self.framesSinceLastFPSUpdate += 1
            
            let now = Date()
            let elapsed = now.timeIntervalSince(self.lastFPSUpdateTime)
            if elapsed >= 1.0 {
                self.currentFPS = Double(self.framesSinceLastFPSUpdate) / elapsed
                self.framesSinceLastFPSUpdate = 0
                self.lastFPSUpdateTime = now
            }
        }
    }

    // MARK: - SCStreamDelegate
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.isCapturing = false
            self?.statusMessage = "Stream stopped with error: \(error.localizedDescription)"
        }
    }
}

// MARK: - SwiftUI Views

struct PoCMainView: View {
    @ObservedObject var coordinator: PoCCoordinator
    @State private var searchText = ""

    var filteredApps: [SCRunningApplication] {
        if searchText.isEmpty {
            return coordinator.runningApps
        } else {
            return coordinator.runningApps.filter {
                $0.applicationName.localizedCaseInsensitiveContains(searchText) ||
                $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        HSplitView {
            // Left Controls Sidebar
            VStack(alignment: .leading, spacing: 12) {
                Text("SafeShare Feasibility PoC")
                    .font(.headline)
                
                Text(coordinator.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .frame(minHeight: 36, alignment: .topLeading)

                // Permissions Section
                if !coordinator.permissionGranted {
                    Button(action: { coordinator.requestPermission() }) {
                        Label("Request Screen Recording Permission", systemImage: "lock.shield")
                    }
                    .buttonStyle(.borderedProminent)
                }

                // Capture Controls
                HStack {
                    if !coordinator.isCapturing {
                        Button(action: {
                            Task { await coordinator.startCapture() }
                        }) {
                            Label("Start Safe View", systemImage: "play.fill")
                        }
                        .disabled(!coordinator.permissionGranted)
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    } else {
                        Button(action: {
                            Task { await coordinator.stopCapture() }
                        }) {
                            Label("Stop Safe View", systemImage: "stop.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }

                    Button(action: {
                        Task { await coordinator.refreshContent() }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh running applications")
                }

                Divider()

                // Performance & Stream Metrics
                VStack(alignment: .leading, spacing: 4) {
                    Text("Capture Metrics")
                        .font(.subheadline)
                        .bold()
                    Text("FPS: \(String(format: "%.1f", coordinator.currentFPS)) | Frames: \(coordinator.frameCount)")
                        .font(.caption)
                    if coordinator.captureResolution != .zero {
                        Text("Res: \(Int(coordinator.captureResolution.width)) × \(Int(coordinator.captureResolution.height))")
                            .font(.caption)
                    }
                    Text("Self-Exclusion: Active (No Mirroring)")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)

                Divider()

                // Application Protection List
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Running Apps (\(coordinator.runningApps.count))")
                            .font(.subheadline)
                            .bold()
                        Spacer()
                        Text("\(coordinator.excludedBundleIDs.count) Protected")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }

                    TextField("Search applications...", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    List(filteredApps, id: \.processID) { app in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(app.applicationName)
                                    .font(.system(size: 13, weight: .medium))
                                Text(app.bundleIdentifier)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            let isExcluded = coordinator.excludedBundleIDs.contains(app.bundleIdentifier)
                            Button(action: {
                                coordinator.toggleAppExclusion(bundleID: app.bundleIdentifier)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: isExcluded ? "shield.fill" : "shield")
                                    Text(isExcluded ? "PROTECTED" : "VISIBLE")
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                            }
                            .buttonStyle(.bordered)
                            .tint(isExcluded ? .purple : .secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(minHeight: 250)
                }
            }
            .padding(14)
            .frame(minWidth: 340, maxWidth: 420)

            // Right Safe View Preview Area
            VStack(spacing: 0) {
                HStack {
                    Label("Safe View Output (Select this window in Teams to share)", systemImage: "display")
                        .font(.headline)
                    Spacer()
                    if coordinator.isCapturing {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                            Text("LIVE FILTERED")
                                .font(.caption2)
                                .bold()
                                .foregroundColor(.green)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                ZStack {
                    Color.black

                    SafeViewPreviewRepresentable(renderer: coordinator.renderer)

                    if !coordinator.isCapturing {
                        VStack(spacing: 8) {
                            Image(systemName: "shield.slash")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("Safe View is Inactive")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            Text("Click 'Start Safe View' to begin hardware-filtered capture.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .frame(minWidth: 500)
        }
    }
}

// MARK: - NSViewRepresentable for Hardware Accelerated Preview

struct SafeViewPreviewRepresentable: NSViewRepresentable {
    let renderer: SafeBufferRenderer

    func makeNSView(context: Context) -> NSView {
        let view = SafeViewHostingNSView(displayLayer: renderer.layer)
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.layer?.setNeedsLayout()
    }
}

final class SafeViewHostingNSView: NSView {
    private let displayLayer: AVSampleBufferDisplayLayer

    init(displayLayer: AVSampleBufferDisplayLayer) {
        self.displayLayer = displayLayer
        super.init(frame: .zero)
        self.wantsLayer = true
        self.layer?.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = self.bounds
        CATransaction.commit()
    }
}
