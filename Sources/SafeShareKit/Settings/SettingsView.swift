import SwiftUI

public struct SettingsView: View {
    @ObservedObject var ruleStore: RuleStore
    @Environment(\.dismiss) private var dismiss

    @State private var targetFPS: Int
    @State private var showCursor: Bool
    @State private var failClosed: Bool
    @State private var excludeNotificationCenter: Bool

    public init(ruleStore: RuleStore) {
        self.ruleStore = ruleStore
        _targetFPS = State(initialValue: ruleStore.config.streamSettings.targetFPS)
        _showCursor = State(initialValue: ruleStore.config.streamSettings.showCursor)
        _failClosed = State(initialValue: ruleStore.config.streamSettings.failClosedBlanking)
        _excludeNotificationCenter = State(initialValue: ruleStore.config.streamSettings.excludeNotificationCenter)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 24))
                    .foregroundColor(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SafeShare Preferences")
                        .font(.headline)
                    Text("Configure hardware filtering and stream behavior")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            // Stream Quality Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Stream Capture Performance")
                    .font(.subheadline)
                    .bold()

                Picker("Frame Rate (FPS)", selection: $targetFPS) {
                    Text("15 FPS (Battery Saver)").tag(15)
                    Text("30 FPS (Recommended)").tag(30)
                    Text("60 FPS (Ultra Smooth)").tag(60)
                }
                .pickerStyle(.segmented)
                .onChange(of: targetFPS) { _, newValue in
                    var settings = ruleStore.config.streamSettings
                    settings.targetFPS = newValue
                    ruleStore.updateStreamSettings(settings)
                }

                Toggle("Include Mouse Cursor in Stream", isOn: $showCursor)
                    .onChange(of: showCursor) { _, newValue in
                        var settings = ruleStore.config.streamSettings
                        settings.showCursor = newValue
                        ruleStore.updateStreamSettings(settings)
                    }
            }

            Divider()

            // Privacy Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Privacy & Security")
                    .font(.subheadline)
                    .bold()

                Toggle("Fail-Closed Privacy Blanking", isOn: $failClosed)
                    .onChange(of: failClosed) { _, newValue in
                        var settings = ruleStore.config.streamSettings
                        settings.failClosedBlanking = newValue
                        ruleStore.updateStreamSettings(settings)
                    }
                Text("Automatically blanks the Safe View window during filter changes, screen lock, or permission updates to prevent accidental leaks.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Toggle("Auto-Hide System Notifications (Notification Center)", isOn: $excludeNotificationCenter)
                    .onChange(of: excludeNotificationCenter) { _, newValue in
                        var settings = ruleStore.config.streamSettings
                        settings.excludeNotificationCenter = newValue
                        ruleStore.updateStreamSettings(settings)
                    }
            }

            Divider()

            // Reset Rules Section
            VStack(alignment: .leading, spacing: 6) {
                Text("Rule Management")
                    .font(.subheadline)
                    .bold()

                Button(role: .destructive, action: {
                    ruleStore.resetAllRules()
                }) {
                    Label("Reset All Application Protection Rules", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            HStack {
                Text("SafeShare v1.0.0 (Open Source / MIT)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440, height: 420)
    }
}
