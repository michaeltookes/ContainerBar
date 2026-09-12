import AppKit
import SwiftUI
import ContainerBarCore
import Logging
import Darwin
@preconcurrency import Sparkle

/// Application delegate managing the menu bar status item and core services
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Status bar item controller
    private var statusItemController: StatusItemController?

    /// Sparkle auto-update controller
    private var updaterController: UpdaterController?

    /// Container state management
    let containerStore: ContainerStore

    /// Settings/preferences management
    let settingsStore: SettingsStore

    /// Builds the fetcher used by app surfaces that create their own fetcher.
    private let fetcherFactory: ContainerStore.FetcherFactory

    /// Application logger
    private let logger = Logger(label: "com.containerbar.app")

    override init() {
        if HuntMode.isActive {
            do {
                let settings = SettingsStore(userDefaults: try HuntMode.makeUserDefaults())
                let fetcherFactory: ContainerStore.FetcherFactory = HuntMode.makeFetcher
                HuntMode.seed(settings)
                self.settingsStore = settings
                self.fetcherFactory = fetcherFactory
                self.containerStore = ContainerStore(settings: settings, fetcherFactory: fetcherFactory)
            } catch {
                fatalError("Hunt mode could not create isolated settings storage: \(error.localizedDescription)")
            }
        } else {
            let settings = SettingsStore()
            let fetcherFactory = ContainerStore.defaultFetcherFactory
            self.settingsStore = settings
            self.fetcherFactory = fetcherFactory
            self.containerStore = ContainerStore(settings: settings, fetcherFactory: fetcherFactory)
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("ContainerBar starting up")

        // Ignore SIGPIPE to prevent crashes when socket connections break
        // This is essential for network/socket operations
        signal(SIGPIPE, SIG_IGN)

        // Hide dock icon - we're a menu bar app
        NSApp.setActivationPolicy(.accessory)

        // Create the status bar item
        statusItemController = StatusItemController(
            containerStore: containerStore,
            settingsStore: settingsStore,
            fetcherFactory: fetcherFactory
        )

        // Prowl hunt launches only exercise local fixture UI; keep optional
        // app services out of that path so the status item is available
        // immediately on the self-hosted runner.
        if HuntMode.isActive {
            logger.info("Hunt mode active; skipping Sparkle updater initialization")
        } else {
            updaterController = UpdaterController.shared
        }

        // Start initial container fetch
        Task {
            await containerStore.refresh()
        }

        logger.info("ContainerBar ready")

        // Headless verification and QA hook: open Settings immediately so a
        // launch from a terminal or a QA runner exercises the settings panes
        // without a click on the status item (see CB-041, CB-042).
        if ProcessInfo.processInfo.environment["CONTAINERBAR_OPEN_SETTINGS_ON_LAUNCH"] == "1" {
            logger.info("CONTAINERBAR_OPEN_SETTINGS_ON_LAUNCH set, opening settings")
            statusItemController?.openSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.info("ContainerBar shutting down")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Menu bar apps should not terminate when windows close
        return false
    }
}
