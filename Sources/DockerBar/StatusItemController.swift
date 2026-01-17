import AppKit
import SwiftUI
import DockerBarCore
import Logging

/// Controller managing the menu bar status item and dropdown menu
///
/// Uses NSHostingView to embed SwiftUI content in NSMenu items,
/// following the SWIFT_EXPERT pattern for hybrid AppKit/SwiftUI.
@MainActor
final class StatusItemController: NSObject {
    /// The system status item in the menu bar
    private let statusItem: NSStatusItem

    /// Reference to the container store
    private let containerStore: ContainerStore

    /// Reference to settings store
    private let settingsStore: SettingsStore

    /// Logger for status item operations
    private let logger = Logger(label: "com.dockerbar.statusitem")

    /// Task for observing store changes
    private var observationTask: Task<Void, Never>?

    init(containerStore: ContainerStore, settingsStore: SettingsStore) {
        self.containerStore = containerStore
        self.settingsStore = settingsStore

        // Create status item with variable width
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        setupStatusItem()
        setupMenu()
        startObservation()

        logger.info("StatusItemController initialized")
    }

    deinit {
        observationTask?.cancel()
    }

    // MARK: - Setup

    private func setupStatusItem() {
        guard let button = statusItem.button else {
            logger.error("Failed to get status item button")
            return
        }

        // Set the initial icon
        updateIcon()

        // Set accessibility
        button.toolTip = "DockerBar - Docker Container Monitor"
        button.setAccessibilityLabel("DockerBar")
        button.setAccessibilityHelp("Click to view Docker containers")
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    private func startObservation() {
        observationTask?.cancel()

        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }

                withObservationTracking {
                    // Track relevant properties
                    _ = self.containerStore.containers
                    _ = self.containerStore.isConnected
                    _ = self.containerStore.isRefreshing
                    _ = self.containerStore.connectionError
                    _ = self.settingsStore.iconStyle
                } onChange: {
                    Task { @MainActor [weak self] in
                        self?.updateIcon()
                    }
                }

                // Small delay to batch updates
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    // MARK: - Icon Updates

    private func updateIcon() {
        guard let button = statusItem.button else { return }

        let runningCount = containerStore.containers.filter { $0.state == .running }.count
        let totalCount = containerStore.containers.count

        // Build icon configuration
        let config = DockerIconRenderer.Config(
            style: settingsStore.iconStyle,
            runningCount: runningCount,
            totalCount: totalCount,
            cpuPercent: containerStore.metricsSnapshot?.totalCPUPercent ?? 0,
            memoryPercent: containerStore.metricsSnapshot?.memoryUsagePercent ?? 0,
            isRefreshing: containerStore.isRefreshing,
            isConnected: containerStore.isConnected,
            hasError: containerStore.connectionError != nil
        )

        // Render and set icon
        let icon = DockerIconRenderer.render(config: config)
        button.image = icon

        // Show running count as title (for container count style)
        if settingsStore.iconStyle == .containerCount && totalCount > 0 {
            button.title = " \(runningCount)"
        } else {
            button.title = ""
        }

        // Update accessibility
        let stateDescription: String
        if containerStore.connectionError != nil {
            stateDescription = "Error connecting to Docker"
        } else if containerStore.isRefreshing {
            stateDescription = "Refreshing"
        } else if containerStore.isConnected {
            stateDescription = "\(runningCount) of \(totalCount) containers running"
        } else {
            stateDescription = "Connecting to Docker"
        }
        button.setAccessibilityValue(stateDescription)
    }

    // MARK: - Menu Building

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }

        menu.removeAllItems()

        // Main content card (SwiftUI)
        let cardItem = createCardMenuItem()
        menu.addItem(cardItem)

        menu.addItem(NSMenuItem.separator())

        // Actions section
        addActionItems(to: menu)
    }

    private func createCardMenuItem() -> NSMenuItem {
        let item = NSMenuItem()

        let cardView = ContainerMenuCardView { [weak self] action in
            self?.handleContainerAction(action)
        }
        .environment(containerStore)
        .environment(settingsStore)

        let hostingView = NSHostingView(rootView: cardView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        // Size to fit content
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: fittingSize)

        item.view = hostingView
        return item
    }

    private func addActionItems(to menu: NSMenu) {
        // Refresh
        let refreshItem = NSMenuItem(
            title: "Refresh Now",
            action: #selector(refreshAction),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        refreshItem.isEnabled = !containerStore.isRefreshing
        menu.addItem(refreshItem)

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit DockerBar",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
    }

    // MARK: - Container Actions

    private func handleContainerAction(_ action: ContainerAction) {
        switch action {
        case .start(let id):
            logger.info("Starting container: \(id)")
            Task {
                await containerStore.startContainer(id: id)
            }

        case .stop(let id):
            logger.info("Stopping container: \(id)")
            Task {
                await containerStore.stopContainer(id: id)
            }

        case .restart(let id):
            logger.info("Restarting container: \(id)")
            Task {
                await containerStore.restartContainer(id: id)
            }

        case .remove(let id):
            logger.info("Remove requested for container: \(id)")
            showRemoveConfirmation(for: id)

        case .copyId(let id):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(id, forType: .string)
            logger.info("Copied container ID to clipboard")

        case .viewLogs(let id):
            logger.info("View logs requested for container: \(id)")
            // TODO: Implement log viewer in future phase
        }
    }

    private func showRemoveConfirmation(for containerId: String) {
        guard let container = containerStore.containers.first(where: { $0.id == containerId }) else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Remove Container?"
        alert.informativeText = "Are you sure you want to remove '\(container.displayName)'? This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")

        // Mark remove button as destructive
        if let removeButton = alert.buttons.first {
            removeButton.hasDestructiveAction = true
        }

        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            logger.info("Confirmed removal of container: \(containerId)")
            // TODO: Implement remove in ContainerStore
        }
    }

    // MARK: - Menu Actions

    @objc private func refreshAction() {
        logger.info("Manual refresh triggered")
        Task {
            await containerStore.refresh(force: true)
        }
    }

    @objc private func openSettings() {
        logger.info("Opening settings")
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - NSMenuDelegate

extension StatusItemController: NSMenuDelegate {
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            // Rebuild menu with fresh content
            self.rebuildMenu()

            // Refresh data when menu opens
            await self.containerStore.refresh()
        }
    }

}
