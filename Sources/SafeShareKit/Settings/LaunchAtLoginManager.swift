import Foundation
import ServiceManagement

@MainActor
public final class LaunchAtLoginManager: ObservableObject {
    @Published public private(set) var isEnabled: Bool = false

    public init() {
        refresh()
    }

    public func refresh() {
        if #available(macOS 13.0, *) {
            self.isEnabled = (SMAppService.mainApp.status == .enabled)
        }
    }

    public func setEnabled(_ enable: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enable {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
                self.isEnabled = (SMAppService.mainApp.status == .enabled)
            } catch {
                print("[LaunchAtLoginManager] Failed to toggle login item: \(error.localizedDescription)")
            }
        }
    }
}
