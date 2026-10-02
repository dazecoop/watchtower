import Foundation
import ServiceManagement

/// Registers Watchtower as a login item through `SMAppService`, which is the
/// supported route on macOS 13 and later: no helper bundle, no deprecated
/// `LSSharedFileList`, and the entry shows up in System Settings → General →
/// Login Items where the user can remove it without us.
enum LoginItem {
    /// Only meaningful inside a real app bundle. Run straight out of `.build`
    /// there is nothing for the system to register, so the toggle stays off.
    static var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    static var isEnabled: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Returns a description of what went wrong, or nil on success.
    static func set(_ enabled: Bool) -> String? {
        guard isAvailable else { return "Only available when Watchtower is run as an app" }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            // The most common failure: the user has denied the app in Login
            // Items, which register() cannot override.
            if SMAppService.mainApp.status == .requiresApproval {
                return "Approve Watchtower in System Settings → General → Login Items"
            }
            return error.localizedDescription
        }
    }
}
