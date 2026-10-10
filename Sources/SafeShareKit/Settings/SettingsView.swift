import SwiftUI
import ScreenCaptureKit

public struct SettingsView: View {
    @ObservedObject var coordinator: AppStateCoordinator
    @StateObject private var loginManager = LaunchAtLoginManager()
    @Environment(\.dismiss) private var dismiss

    @State private var targetFPS: Int
    @State private var showCursor: Bool
    @State private var failClosed: Bool
    @State private var excludeNotificationCenter: Bool
    @State private var selectedDisplayID: UInt32

    public init(coordinator: AppStateCoordinator) {
        self.coordinator = coordinator
        let settings = coordinator.ruleStore.config.streamSettings
        _targetFPS = State(initialValue: settings.targetFPS)
        _showCursor = State(initialValue: settings.showCursor)
        _failClosed = State(initialValue: settings.failClosedBlanking)
        _excludeNotificationCenter = State(initialValue: settings.excludeNotificationCenter)
        _selectedDisplayID = State(initialValue: settings.selectedDisplayID ?? (coordinator.activeDisplay?.displayID ?? 0))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.purple)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SafeShare Preferences")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text("Hardware filtering, stream performance, and system integration")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }

                Divider()

                // Display & Capture Target Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Display Source")
                        .font(.subheadline)
                        .bold()
                        .accessibilityAddTraits(.isHeader)

                    if coordinator.scanner.displays.isEmpty {
                        Text("No displays discovered.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if coordinator.scanner.displays.count == 1, let d = coordinator.scanner.displays.first {
                        HStack {
                            Image(systemName: "display")
                                .foregroundColor(.secondary)
                            Text("Main Display (\(d.width) × \(d.height))")
                                .font(.system(size: 13))
                            Spacer()
                            Text("Primary")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(4)
                        }
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                    } else {
                        Picker("Select Display to Capture", selection: $selectedDisplayID) {
                            ForEach(coordinator.scanner.displays, id: \.displayID) { display in
                                Text("Display \(display.displayID) (\(display.width) × \(display.height))")
                                    .tag(display.displayID)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selectedDisplayID) { _, newValue in
                            coordinator.setTargetDisplay(displayID: newValue)
                        }
                        .accessibilityLabel("Select physical display to capture")
                    }
                }

                Divider()

                // Stream Quality & Performance Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Stream Capture Performance")
                        .font(.subheadline)
                        .bold()
                        .accessibilityAddTraits(.isHeader)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Frame Rate:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("Target FPS", selection: $targetFPS) {
                            Text("15 FPS (Battery Saver)").tag(15)
                            Text("30 FPS (Standard)").tag(30)
                            Text("60 FPS (Smooth)").tag(60)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: targetFPS) { _, newValue in
                            var settings = coordinator.ruleStore.config.streamSettings
                            settings.targetFPS = newValue
                            coordinator.ruleStore.updateStreamSettings(settings)
                        }
                        .accessibilityLabel("Target frame rate")
                    }

                    Toggle("Include Mouse Pointer in Stream", isOn: $showCursor)
                        .onChange(of: showCursor) { _, newValue in
                            var settings = coordinator.ruleStore.config.streamSettings
                            settings.showCursor = newValue
                            coordinator.ruleStore.updateStreamSettings(settings)
                        }
                        .accessibilityLabel("Include mouse cursor in video stream")
                }

                Divider()

                // Privacy & Security Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Privacy & Security")
                        .font(.subheadline)
                        .bold()
                        .accessibilityAddTraits(.isHeader)

                    Toggle("Fail-Closed Privacy Blanking", isOn: $failClosed)
                        .onChange(of: failClosed) { _, newValue in
                            var settings = coordinator.ruleStore.config.streamSettings
                            settings.failClosedBlanking = newValue
                            coordinator.ruleStore.updateStreamSettings(settings)
                        }
                        .accessibilityLabel("Fail-closed privacy blanking")
                    Text("Instantly blacks out the Safe View window during filter changes, screen lock, or permission updates to prevent accidental leaks.")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Toggle("Auto-Hide System Notifications (Notification Center)", isOn: $excludeNotificationCenter)
                        .onChange(of: excludeNotificationCenter) { _, newValue in
                            var settings = coordinator.ruleStore.config.streamSettings
                            settings.excludeNotificationCenter = newValue
                            coordinator.ruleStore.updateStreamSettings(settings)
                        }
                        .accessibilityLabel("Exclude macOS Notification Center banners from capture")
                }

                Divider()

                // System Integration
                VStack(alignment: .leading, spacing: 8) {
                    Text("System Integration")
                        .font(.subheadline)
                        .bold()
                        .accessibilityAddTraits(.isHeader)

                    Toggle("Launch SafeShare Automatically at Login", isOn: Binding(
                        get: { loginManager.isEnabled },
                        set: { loginManager.setEnabled($0) }
                    ))
                    .accessibilityLabel("Launch SafeShare at login")
                }

                Divider()

                // Rule Management Section
                VStack(alignment: .leading, spacing: 6) {
                    Text("Rule Management")
                        .font(.subheadline)
                        .bold()
                        .accessibilityAddTraits(.isHeader)

                    Button(role: .destructive, action: {
                        coordinator.ruleStore.resetAllRules()
                    }) {
                        Label("Reset All Application Protection Rules", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Reset all application protection rules to default")
                }

                Divider()

                // Footer
                HStack {
                    Text("SafeShare v1.0.0 (Open Source / MIT)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Close settings panel")
                }
            }
            .padding(20)
        }
        .frame(width: 480, height: 520)
    }
}
