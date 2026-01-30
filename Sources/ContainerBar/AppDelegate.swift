import AppKit
import SwiftUI
import ContainerBarCore
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
    private let logger = Logger(label: "com.containerbar.app")

    override init() {
        self.settingsStore = SettingsStore()
        self.containerStore = ContainerStore(settings: settingsStore)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("ContainerBar starting up")

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

        logger.info("ContainerBar ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("ContainerBar shutting down")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu bar apps should not terminate when windows close
        return false
    }
}
