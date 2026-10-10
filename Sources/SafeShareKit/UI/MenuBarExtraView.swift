import SwiftUI

public struct MenuBarExtraView: View {
    @ObservedObject public var coordinator: AppStateCoordinator
    @State private var searchText: String = ""
    @State private var isShowingSettings: Bool = false

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
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.purple)
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

                Button(action: { isShowingSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Stream Controls
            VStack(spacing: 8) {
                if !coordinator.permissions.hasScreenRecordingPermission {
                    Button(action: { coordinator.permissions.requestScreenRecordingPermission() }) {
                        Label("Grant Screen Recording Permission", systemImage: "lock.shield")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
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
                        } else {
                            Button(action: {
                                Task { await coordinator.stopSafeView() }
                            }) {
                                Label("Stop Safe View", systemImage: "stop.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)

                            Button(action: {
                                coordinator.focusSafeViewWindow()
                            }) {
                                Image(systemName: "macwindow.badge.plus")
                            }
                            .buttonStyle(.bordered)
                            .help("Bring Safe View window to front")
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
            .frame(height: 320)

            Divider()

            // Footer / Instructions
            HStack {
                Text("Select 'Safe View' window in Teams to share")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 360)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(ruleStore: coordinator.ruleStore)
        }
    }
}
