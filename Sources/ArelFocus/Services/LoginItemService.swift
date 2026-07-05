import Foundation
import ServiceManagement

enum LoginItemService {
    static var statusText: String {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled: return "Enabled"
            case .requiresApproval: return "Requires approval in System Settings"
            case .notRegistered: return "Not registered"
            case .notFound: return "Not available in this build"
            @unknown default: return "Unknown"
            }
        }

        return "Requires macOS 13+"
    }

    static func setEnabled(_ enabled: Bool) -> String {
        guard #available(macOS 13.0, *) else {
            return "Launch at login requires macOS 13+."
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return statusText
        } catch {
            return error.localizedDescription
        }
    }
}
