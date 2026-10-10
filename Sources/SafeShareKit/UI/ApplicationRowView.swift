import SwiftUI
import AppKit

public struct ApplicationRowView: View {
    public let appGroup: ApplicationGroup
    public let isProtected: Bool
    public let onToggleProtection: () -> Void
    public let onWindowOverrideChange: (CGWindowID, ProtectionOverride) -> Void
    public let getWindowOverride: (CGWindowID) -> ProtectionOverride

    @State private var isExpanded: Bool = false

    public init(
        appGroup: ApplicationGroup,
        isProtected: Bool,
        onToggleProtection: @escaping () -> Void,
        onWindowOverrideChange: @escaping (CGWindowID, ProtectionOverride) -> Void,
        getWindowOverride: @escaping (CGWindowID) -> ProtectionOverride
    ) {
        self.appGroup = appGroup
        self.isProtected = isProtected
        self.onToggleProtection = onToggleProtection
        self.onWindowOverrideChange = onWindowOverrideChange
        self.getWindowOverride = getWindowOverride
    }

    private var appIcon: NSImage {
        if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appGroup.bundleIdentifier)?.path {
            return NSWorkspace.shared.icon(forFile: path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                // Expand/collapse chevron if multiple windows or instances exist
                let isExpandable = appGroup.allWindows.count > 1 || appGroup.instances.count > 1
                if isExpandable {
                    Button(action: { isExpanded.toggle() }) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 14)
                } else {
                    Spacer().frame(width: 14)
                }

                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(appGroup.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        if appGroup.instances.count > 1 {
                            Text("(\(appGroup.instances.count) instances)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                    Text(appGroup.bundleIdentifier)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(action: onToggleProtection) {
                    HStack(spacing: 4) {
                        Image(systemName: isProtected ? "shield.fill" : "shield")
                        Text(isProtected ? "PROTECTED" : "VISIBLE")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.bordered)
                .tint(isProtected ? .purple : .secondary)
            }
            .padding(.vertical, 2)

            // Expanded Window & Instance Overrides
            if isExpanded && (appGroup.allWindows.count > 1 || appGroup.instances.count > 1) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(appGroup.instances) { instance in
                        if appGroup.instances.count > 1 {
                            HStack {
                                Text("Process (PID: \(instance.processID))")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(instance.windows.count) window(s)")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading, 26)
                        }

                        ForEach(instance.windows) { window in
                            HStack(spacing: 6) {
                                Image(systemName: "macwindow")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                Text(window.title.isEmpty ? "Untitled Window" : window.title)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)

                                Spacer()

                                let currentOverride = getWindowOverride(window.windowID)
                                Menu {
                                    Button("Inherit (\(isProtected ? "Protected" : "Visible"))") {
                                        onWindowOverrideChange(window.windowID, .inherit)
                                    }
                                    Button("Force Visible") {
                                        onWindowOverrideChange(window.windowID, .forceVisible)
                                    }
                                    Button("Force Protected") {
                                        onWindowOverrideChange(window.windowID, .forceProtect)
                                    }
                                } label: {
                                    Text(overrideLabel(currentOverride))
                                        .font(.system(size: 9))
                                }
                                .menuStyle(.borderlessButton)
                                .frame(width: 90)
                            }
                            .padding(.leading, appGroup.instances.count > 1 ? 34 : 26)
                            .padding(.vertical, 1)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func overrideLabel(_ override: ProtectionOverride) -> String {
        switch override {
        case .inherit: return "Inherited"
        case .forceVisible: return "Visible"
        case .forceProtect: return "Protected"
        }
    }
}
