import SwiftUI

public struct MenuBarExtraView: View {
    @ObservedObject public var coordinator: AppStateCoordinator
    @State private var searchText: String = ""

    public init(coordinator: AppStateCoordinator) {
        self.coordinator = coordinator
    }

    private var filteredGroups: [ApplicationGroup] {
        if searchText.isEmpty {
            return coordinator.applicationGroups
        }
        return coordinator.applicationGroups.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.bundleIdentifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var protectedGroups: [ApplicationGroup] {
        filteredGroups.filter { coordinator.ruleStore.isApplicationProtected(bundleID: $0.bundleIdentifier) }
    }

    private var unprotectedGroups: [ApplicationGroup] {
        filteredGroups.filter { !coordinator.ruleStore.isApplicationProtected(bundleID: $0.bundleIdentifier) }
    }

    public var body: some View {
        Group {
            if coordinator.isShowingSettings {
                SettingsView(coordinator: coordinator, onBack: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        coordinator.isShowingSettings = false
                    }
                })
            } else {
                mainContentView
            }
        }
        .frame(width: 380, height: 520)
    }

    private var mainContentView: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.purple)

                    if coordinator.isCapturing {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .overlay(
                                Circle()
                                    .stroke(Color(NSColor.windowBackgroundColor), lineWidth: 1.5)
                            )
                            .offset(x: 2, y: 2)
                    }
                }
                Text("SafeShare")
                    .font(.system(size: 14, weight: .bold))

                Spacer()

                if coordinator.isCapturing {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                        Text("\(String(format: "%.0f", coordinator.fps)) FPS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(4)
                }

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        coordinator.isShowingSettings = true
                    }
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: [.command])
                .help("Settings (⌘,)")
                .accessibilityLabel("Open Preferences")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Stream Controls
            VStack(spacing: 8) {
                if !coordinator.hasScreenRecordingPermission {
                    VStack(spacing: 6) {
                        Button(action: { coordinator.permissions.requestScreenRecordingPermission() }) {
                            Label("Open Screen Recording Settings", systemImage: "lock.shield")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)

                        HStack(spacing: 8) {
                            Button(action: {
                                coordinator.permissions.refreshPermissionStatus()
                                Task { await coordinator.refreshApps() }
                            }) {
                                Label("Check Again", systemImage: "arrow.clockwise")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.bordered)

                            Button(action: {
                                relaunchApp()
                            }) {
                                Label("Relaunch SafeShare", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        if !coordinator.isCapturing {
                            Button(action: {
                                Task { await coordinator.startSafeView() }
                            }) {
                                Label("Start Safe View", systemImage: "play.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .keyboardShortcut("s", modifiers: [.command, .shift])
                            .accessibilityLabel("Start Safe View streaming")
                            .accessibilityHint("Starts hardware-filtered screen capture in a dedicated window. Shortcut: Command Shift S")
                        } else {
                            Button(action: {
                                Task { await coordinator.stopSafeView() }
                            }) {
                                Label("Stop Safe View", systemImage: "stop.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .keyboardShortcut("s", modifiers: [.command, .shift])
                            .accessibilityLabel("Stop Safe View streaming")
                            .accessibilityHint("Stops active screen capture. Shortcut: Command Shift S")

                            Button(action: {
                                coordinator.focusSafeViewWindow()
                            }) {
                                Image(systemName: "macwindow.badge.plus")
                            }
                            .buttonStyle(.bordered)
                            .help("Bring Safe View window to front")
                            .accessibilityLabel("Focus Safe View window")
                        }
                    }
                }

                Text(coordinator.statusMessage)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(12)

            Divider()

            // Search Bar & App Count
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                TextField("Filter running applications...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }

                Button(action: {
                    Task { await coordinator.refreshApps() }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("Refresh running applications")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Applications Scroll List
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    // Protected Apps Section
                    if !protectedGroups.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("PROTECTED APPLICATIONS (\(protectedGroups.count))")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.purple)
                                .padding(.horizontal, 12)
                                .padding(.top, 6)

                            ForEach(protectedGroups) { group in
                                ApplicationRowView(
                                    appGroup: group,
                                    isProtected: true,
                                    onToggleProtection: {
                                        coordinator.toggleProtection(bundleID: group.bundleIdentifier)
                                    },
                                    onWindowOverrideChange: { winID, override in
                                        coordinator.setWindowOverride(windowID: winID, state: override)
                                    },
                                    getWindowOverride: { winID in
                                        coordinator.ruleStore.windowOverride(for: winID)
                                    }
                                )
                                .padding(.horizontal, 10)
                            }
                        }
                    }

                    // Visible Apps Section
                    VStack(alignment: .leading, spacing: 4) {
                        Text("VISIBLE APPLICATIONS (\(unprotectedGroups.count))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 4)

                        ForEach(unprotectedGroups) { group in
                            ApplicationRowView(
                                appGroup: group,
                                isProtected: false,
                                onToggleProtection: {
                                    coordinator.toggleProtection(bundleID: group.bundleIdentifier)
                                },
                                onWindowOverrideChange: { winID, override in
                                    coordinator.setWindowOverride(windowID: winID, state: override)
                                },
                                getWindowOverride: { winID in
                                    coordinator.ruleStore.windowOverride(for: winID)
                                }
                            )
                            .padding(.horizontal, 10)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(height: 340)

            Divider()

            // Footer / Instructions
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Select 'Safe View' window in Teams to share")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    if let d = coordinator.activeDisplay {
                        Text("Display \(d.displayID): \(d.width)×\(d.height)")
                            .font(.system(size: 8))
                            .foregroundColor(.purple)
                    }
                }
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .keyboardShortcut("q", modifiers: [.command])
                .accessibilityLabel("Quit SafeShare")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }

    private func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", bundleURL.path]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }
}
