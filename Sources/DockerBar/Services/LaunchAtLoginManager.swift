import Foundation
import ServiceManagement
import Logging

/// Manages the "Launch at Login" functionality using SMAppService (macOS 13+)
@MainActor
final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private let logger = Logger(label: "com.dockerbar.launchatlogin")

    private init() {}

    /// Whether the app is currently set to launch at login
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Sets whether the app should launch at login
    /// - Parameter enabled: true to enable launch at login, false to disable
    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                // Check current status first
                if SMAppService.mainApp.status == .enabled {
                    logger.info("Launch at login already enabled")
                    return
                }

                try SMAppService.mainApp.register()
                logger.info("Launch at login enabled successfully")
            } else {
                // Check current status first
                if SMAppService.mainApp.status != .enabled {
                    logger.info("Launch at login already disabled")
                    return
                }

                try SMAppService.mainApp.unregister()
                logger.info("Launch at login disabled successfully")
            }
        } catch {
            logger.error("Failed to \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)")
        }
    }

    /// Gets the current status as a human-readable string
    var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            return "Not registered"
        case .enabled:
            return "Enabled"
        case .requiresApproval:
            return "Requires approval in System Settings"
        case .notFound:
            return "App not found"
        @unknown default:
            return "Unknown"
        }
    }
}
