import Foundation
import ServiceManagement

/// Owns the per-user macOS login-item registration for the main app bundle.
/// This uses SMAppService.mainApp (macOS 13+) and does not install a system-wide
/// daemon or require administrator privileges.
enum LoginItemManager {
    private static var service: SMAppService { .mainApp }

    static var isEnabledOrPendingApproval: Bool {
        switch service.status {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        @unknown default:
            return false
        }
    }

    static var requiresApproval: Bool {
        if case .requiresApproval = service.status { return true }
        return false
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            switch service.status {
            case .enabled:
                return
            case .requiresApproval:
                openSystemSettings()
                return
            case .notRegistered:
                try service.register()
                if requiresApproval {
                    openSystemSettings()
                }
            case .notFound:
                throw LoginItemError.mainAppServiceNotFound
            @unknown default:
                try service.register()
            }
        } else {
            switch service.status {
            case .notRegistered, .notFound:
                return
            case .enabled, .requiresApproval:
                try service.unregister()
            @unknown default:
                try service.unregister()
            }
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

enum LoginItemError: LocalizedError {
    case mainAppServiceNotFound

    var errorDescription: String? {
        switch self {
        case .mainAppServiceNotFound:
            return "macOS kann das WindowSwitcher-App-Bundle nicht als Anmeldeobjekt finden. Bitte verschiebe WindowSwitcher in einen dauerhaften Ordner (zum Beispiel Programme oder ~/Applications) und starte es von dort erneut."
        }
    }
}
