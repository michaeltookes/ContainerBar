import AppKit
import SwiftUI
import DockerBarCore
import Logging

/// Controller managing the menu bar status item and dropdown menu
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

    /// Observation tracking for store changes
    private var storeObservation: Any?

    init(containerStore: ContainerStore, settingsStore: SettingsStore) {
        self.containerStore = containerStore
        self.settingsStore = settingsStore

        // Create status item with variable width
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        setupStatusItem()
        setupMenu()
        observeStoreChanges()

        logger.info("StatusItemController initialized")
    }

    // MARK: - Setup

    private func setupStatusItem() {
        guard let button = statusItem.button else {
            logger.error("Failed to get status item button")
            return
        }

        // Set the initial icon - Docker whale with container count
        updateIcon()

        // Set accessibility
        button.toolTip = "DockerBar - Docker Container Monitor"
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // Title item
        let titleItem = NSMenuItem(title: "DockerBar", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        // Connection status placeholder
        let connectionItem = NSMenuItem(title: "Not connected", action: nil, keyEquivalent: "")
        connectionItem.isEnabled = false
        connectionItem.tag = MenuItemTag.connectionStatus.rawValue
        menu.addItem(connectionItem)

        menu.addItem(NSMenuItem.separator())

        // Container list placeholder - will be populated dynamically
        let containersItem = NSMenuItem(title: "No containers", action: nil, keyEquivalent: "")
        containersItem.isEnabled = false
        containersItem.tag = MenuItemTag.containerList.rawValue
        menu.addItem(containersItem)

        menu.addItem(NSMenuItem.separator())

        // Refresh action
        let refreshItem = NSMenuItem(
            title: "Refresh Now",
            action: #selector(refreshAction),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        menu.addItem(refreshItem)

        // Settings action
        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Quit action
        let quitItem = NSMenuItem(
            title: "Quit DockerBar",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func observeStoreChanges() {
        // Observe container store changes using withObservationTracking
        Task { @MainActor [weak self] in
            while true {
                guard let self else { break }

                withObservationTracking {
                    // Access the properties we want to track
                    _ = self.containerStore.containers
                    _ = self.containerStore.isConnected
                    _ = self.containerStore.isRefreshing
                } onChange: {
                    Task { @MainActor [weak self] in
                        self?.updateIcon()
                        self?.updateMenu()
                    }
                }

                // Small delay to prevent tight loops
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    // MARK: - Updates

    private func updateIcon() {
        guard let button = statusItem.button else { return }

        let runningCount = containerStore.containers.filter { $0.state == .running }.count
        let totalCount = containerStore.containers.count

        // Use SF Symbol as base icon
        let image: NSImage
        if containerStore.isRefreshing {
            // Show refresh indicator
            image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Refreshing")?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .medium)) ?? NSImage()
        } else if !containerStore.isConnected && containerStore.connectionError != nil {
            // Show error state
            image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Error")?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .medium)) ?? NSImage()
        } else {
            // Show container icon with count
            image = NSImage(systemSymbolName: "shippingbox", accessibilityDescription: "Containers")?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .medium)) ?? NSImage()
        }

        image.isTemplate = true
        button.image = image

        // Show running count as title if we have containers
        if totalCount > 0 {
            button.title = " \(runningCount)"
        } else {
            button.title = ""
        }
    }

    private func updateMenu() {
        guard let menu = statusItem.menu else { return }

        // Update connection status
        if let statusItem = menu.item(withTag: MenuItemTag.connectionStatus.rawValue) {
            if containerStore.isConnected {
                let hostName = settingsStore.selectedHost?.name ?? "Local Docker"
                let runningCount = containerStore.containers.filter { $0.state == .running }.count
                let stoppedCount = containerStore.containers.filter { $0.state == .exited }.count
                statusItem.title = "Connected to \(hostName) (\(runningCount) running, \(stoppedCount) stopped)"
            } else if let error = containerStore.connectionError {
                statusItem.title = "Error: \(error)"
            } else {
                statusItem.title = "Connecting..."
            }
        }

        // Update container list
        if let containerItem = menu.item(withTag: MenuItemTag.containerList.rawValue) {
            // Remove old container items
            let containerIndex = menu.index(of: containerItem)
            while menu.items.count > containerIndex + 1 {
                let nextItem = menu.items[containerIndex + 1]
                if nextItem.isSeparatorItem { break }
                menu.removeItem(nextItem)
            }
            menu.removeItem(containerItem)

            // Add new container items
            if containerStore.containers.isEmpty {
                let noContainers = NSMenuItem(title: "No containers", action: nil, keyEquivalent: "")
                noContainers.isEnabled = false
                noContainers.tag = MenuItemTag.containerList.rawValue
                menu.insertItem(noContainers, at: containerIndex)
            } else {
                var insertIndex = containerIndex
                for container in containerStore.containers.prefix(20) {
                    let item = createContainerMenuItem(container)
                    if insertIndex == containerIndex {
                        item.tag = MenuItemTag.containerList.rawValue
                    }
                    menu.insertItem(item, at: insertIndex)
                    insertIndex += 1
                }

                // Show "more" item if we have many containers
                if containerStore.containers.count > 20 {
                    let moreItem = NSMenuItem(
                        title: "... and \(containerStore.containers.count - 20) more",
                        action: nil,
                        keyEquivalent: ""
                    )
                    moreItem.isEnabled = false
                    menu.insertItem(moreItem, at: insertIndex)
                }
            }
        }
    }

    private func createContainerMenuItem(_ container: DockerContainer) -> NSMenuItem {
        let stateIcon: String
        switch container.state {
        case .running: stateIcon = "●"
        case .paused: stateIcon = "❚❚"
        case .restarting: stateIcon = "↻"
        case .exited, .dead: stateIcon = "○"
        case .created, .removing: stateIcon = "◌"
        }

        let title = "\(stateIcon) \(container.displayName)"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")

        // Create submenu for container actions
        let submenu = NSMenu()

        if container.state == .running {
            let stopItem = NSMenuItem(title: "Stop", action: #selector(stopContainer(_:)), keyEquivalent: "")
            stopItem.target = self
            stopItem.representedObject = container.id
            submenu.addItem(stopItem)

            let restartItem = NSMenuItem(title: "Restart", action: #selector(restartContainer(_:)), keyEquivalent: "")
            restartItem.target = self
            restartItem.representedObject = container.id
            submenu.addItem(restartItem)
        } else {
            let startItem = NSMenuItem(title: "Start", action: #selector(startContainer(_:)), keyEquivalent: "")
            startItem.target = self
            startItem.representedObject = container.id
            submenu.addItem(startItem)
        }

        submenu.addItem(NSMenuItem.separator())

        let copyIdItem = NSMenuItem(title: "Copy Container ID", action: #selector(copyContainerId(_:)), keyEquivalent: "")
        copyIdItem.target = self
        copyIdItem.representedObject = container.id
        submenu.addItem(copyIdItem)

        item.submenu = submenu

        return item
    }

    // MARK: - Actions

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

    @objc private func startContainer(_ sender: NSMenuItem) {
        guard let containerId = sender.representedObject as? String else { return }
        logger.info("Starting container: \(containerId)")
        Task {
            await containerStore.startContainer(id: containerId)
        }
    }

    @objc private func stopContainer(_ sender: NSMenuItem) {
        guard let containerId = sender.representedObject as? String else { return }
        logger.info("Stopping container: \(containerId)")
        Task {
            await containerStore.stopContainer(id: containerId)
        }
    }

    @objc private func restartContainer(_ sender: NSMenuItem) {
        guard let containerId = sender.representedObject as? String else { return }
        logger.info("Restarting container: \(containerId)")
        Task {
            await containerStore.restartContainer(id: containerId)
        }
    }

    @objc private func copyContainerId(_ sender: NSMenuItem) {
        guard let containerId = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(containerId, forType: .string)
        logger.info("Copied container ID to clipboard")
    }
}

// MARK: - NSMenuDelegate

extension StatusItemController: NSMenuDelegate {
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor in
            // Refresh when menu opens for freshest data
            await containerStore.refresh()
        }
    }
}

// MARK: - Menu Item Tags

private enum MenuItemTag: Int {
    case connectionStatus = 100
    case containerList = 200
}
