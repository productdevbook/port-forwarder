import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private init() {}

    var isEnabled: Bool {
        get {
            SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                    logInfo("Launch at Login enabled", source: "system")
                } else {
                    try SMAppService.mainApp.unregister()
                    logInfo("Launch at Login disabled", source: "system")
                }
            } catch {
                logError("Failed to set Launch at Login: \(error.localizedDescription)", source: "system")
            }
        }
    }
}
