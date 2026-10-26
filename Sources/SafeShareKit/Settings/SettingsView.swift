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

    public let onBack: (() -> Void)?

    public init(coordinator: AppStateCoordinator, onBack: (() -> Void)? = nil) {
        self.coordinator = coordinator
        self.onBack = onBack
        let settings = coordinator.ruleStore.config.streamSettings
        _targetFPS = State(initialValue: settings.targetFPS)
        _showCursor = State(initialValue: settings.showCursor)
        _failClosed = State(initialValue: settings.failClosedBlanking)
        _excludeNotificationCenter = State(initialValue: settings.excludeNotificationCenter)
        _selectedDisplayID = State(initialValue: settings.selectedDisplayID ?? (coordinator.activeDisplay?.displayID ?? 0))
    }

    public var body: some View {
        ScrollView([.vertical], showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 8) {
                    if let back = onBack {
                        Button(action: back) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Back to applications list")
                    } else {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.purple)
                            .accessibilityHidden(true)
                    }

                    Text("Preferences")
                        .font(.system(size: 14, weight: .bold))
                        .accessibilityAddTraits(.isHeader)

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
                                .font(.system(size: 12))
                                .lineLimit(1)
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Active Display:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("Display", selection: $selectedDisplayID) {
                                ForEach(coordinator.scanner.displays, id: \.displayID) { display in
                                    Text("Display \(display.displayID) (\(display.width) × \(display.height))")
                                        .tag(display.displayID)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .onChange(of: selectedDisplayID) { _, newValue in
                                coordinator.setTargetDisplay(displayID: newValue)
                            }
                            .accessibilityLabel("Select physical display to capture")
                        }
                    }
                }

                Divider()

                // Stream Quality & Performance Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Stream Capture Performance")
                        .font(.subheadline)
                        .bold()
                        .accessibilityAddTraits(.isHeader)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Target Frame Rate:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("Target FPS", selection: $targetFPS) {
                            Text("15 FPS").tag(15)
                            Text("30 FPS (Standard)").tag(30)
                            Text("60 FPS").tag(60)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .onChange(of: targetFPS) { _, newValue in
                            var settings = coordinator.ruleStore.config.streamSettings
                            settings.targetFPS = newValue
                            coordinator.ruleStore.updateStreamSettings(settings)
                        }
                        .accessibilityLabel("Target frame rate")

                        Text("30 FPS is standard for meeting sharing. 15 FPS conserves battery.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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

                    Text("Instantly blacks out Safe View during screen lock, sleep, or permission updates to prevent accidental leaks.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Toggle("Hide Notification Center Banners", isOn: $excludeNotificationCenter)
                        .onChange(of: excludeNotificationCenter) { _, newValue in
                            var settings = coordinator.ruleStore.config.streamSettings
                            settings.excludeNotificationCenter = newValue
                            coordinator.ruleStore.updateStreamSettings(settings)
                        }
                        .accessibilityLabel("Exclude macOS Notification Center banners from capture")

                    Text("Prevents macOS notification banners and alerts from appearing in the video stream.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                // System Integration
                VStack(alignment: .leading, spacing: 8) {
                    Text("System Integration")
                        .font(.subheadline)
                        .bold()
                        .accessibilityAddTraits(.isHeader)

                    Toggle("Launch SafeShare at Login", isOn: Binding(
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
                        Label("Reset All Application Rules", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Reset all application protection rules to default")
                }

                Divider()

                // Footer
                HStack {
                    Text("SafeShare v1.1.0 (Open Source / MIT)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Done") {
                        if let back = onBack {
                            back()
                        } else {
                            coordinator.isShowingSettings = false
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Close settings panel")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
