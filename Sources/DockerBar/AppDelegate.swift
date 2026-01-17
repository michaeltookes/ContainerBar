import AppKit
import SwiftUI
import DockerBarCore
import Logging

/// Application delegate managing the menu bar status item and core services
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Status bar item controller
    private var statusItemController: StatusItemController?

    /// Container state management
    let containerStore: ContainerStore

    /// Settings/preferences management
    let settingsStore: SettingsStore

    /// Application logger
    private let logger = Logger(label: "com.dockerbar.app")

    override init() {
        self.settingsStore = SettingsStore()
        self.containerStore = ContainerStore(settings: settingsStore)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("DockerBar starting up")

        // Hide dock icon - we're a menu bar app
        NSApp.setActivationPolicy(.accessory)

        // Create the status bar item
        statusItemController = StatusItemController(
            containerStore: containerStore,
            settingsStore: settingsStore
        )

        // Start initial container fetch
        Task {
            await containerStore.refresh()
        }

        logger.info("DockerBar ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("DockerBar shutting down")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu bar apps should not terminate when windows close
        return false
    }
}
