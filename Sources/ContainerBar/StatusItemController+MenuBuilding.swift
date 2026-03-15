import AppKit
import SwiftUI
import ContainerBarCore

// MARK: - Menu Building

extension StatusItemController {
    func rebuildMenu() {
        guard let menu = statusItem.menu else { return }

        menu.removeAllItems()

        // Main content card (SwiftUI)
        let cardItem = createCardMenuItem()
        menu.addItem(cardItem)
    }

    func createCardMenuItem() -> NSMenuItem {
        let item = NSMenuItem()

        let dashboardView = DashboardMenuView(
            onAction: { [weak self] action in
                self?.handleContainerAction(action)
            },
            onSettings: { [weak self] in
                self?.openSettings()
            },
            onQuit: {
                NSApp.terminate(nil)
            },
            onHostChanged: { [weak self] in
                guard let self else { return }
                self.logger.info("Host changed, reinitializing fetcher")
                self.containerStore.reinitializeFetcher()
                Task {
                    await self.containerStore.refresh(force: true)
                }
            }
        )
        .environment(containerStore)
        .environment(settingsStore)

        let hostingView = NSHostingView(rootView: dashboardView)

        // Let SwiftUI compute the actual content height, clamped to a reasonable range
        let fittingHeight = min(max(hostingView.fittingSize.height, 300), 700)
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: fittingHeight)

        item.view = hostingView
        return item
    }

    func addContainerActionsSubmenu(to menu: NSMenu) {
        let containersItem = NSMenuItem(title: "Container Actions", action: nil, keyEquivalent: "")
        let containersSubmenu = NSMenu()

        // Sort containers: running first, then alphabetically by name
        // Also filter based on showStoppedContainers setting
        let sortedContainers = containerStore.containers
            .sorted { lhs, rhs in
                if lhs.state == .running && rhs.state != .running { return true }
                if lhs.state != .running && rhs.state == .running { return false }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
            .filter { container in
                settingsStore.showStoppedContainers || container.state.isActive
            }

        for container in sortedContainers {
            let containerItem = NSMenuItem(title: container.displayName, action: nil, keyEquivalent: "")

            // Set icon based on state
            if container.state == .running {
                containerItem.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Running")
                containerItem.image?.isTemplate = false
            } else {
                containerItem.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "Stopped")
            }

            // Create submenu for this container
            let actionSubmenu = NSMenu()

            // View Logs
            let logsItem = NSMenuItem(title: "View Logs...", action: #selector(viewLogsAction(_:)), keyEquivalent: "")
            logsItem.target = self
            logsItem.representedObject = container.id
            logsItem.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "Logs")
            actionSubmenu.addItem(logsItem)

            actionSubmenu.addItem(NSMenuItem.separator())

            // Start/Stop/Restart
            if container.state == .running {
                let stopItem = NSMenuItem(title: "Stop", action: #selector(stopContainerAction(_:)), keyEquivalent: "")
                stopItem.target = self
                stopItem.representedObject = container.id
                stopItem.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "Stop")
                actionSubmenu.addItem(stopItem)

                let restartItem = NSMenuItem(title: "Restart", action: #selector(restartContainerAction(_:)), keyEquivalent: "")
                restartItem.target = self
                restartItem.representedObject = container.id
                restartItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Restart")
                actionSubmenu.addItem(restartItem)
            } else {
                let startItem = NSMenuItem(title: "Start", action: #selector(startContainerAction(_:)), keyEquivalent: "")
                startItem.target = self
                startItem.representedObject = container.id
                startItem.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Start")
                actionSubmenu.addItem(startItem)
            }

            actionSubmenu.addItem(NSMenuItem.separator())

            // Copy ID
            let copyIdItem = NSMenuItem(title: "Copy Container ID", action: #selector(copyIdAction(_:)), keyEquivalent: "")
            copyIdItem.target = self
            copyIdItem.representedObject = container.id
            copyIdItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")
            actionSubmenu.addItem(copyIdItem)

            actionSubmenu.addItem(NSMenuItem.separator())

            // Remove
            let removeItem = NSMenuItem(title: "Remove...", action: #selector(removeContainerAction(_:)), keyEquivalent: "")
            removeItem.target = self
            removeItem.representedObject = container.id
            removeItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Remove")
            actionSubmenu.addItem(removeItem)

            containerItem.submenu = actionSubmenu
            containersSubmenu.addItem(containerItem)
        }

        containersItem.submenu = containersSubmenu
        menu.addItem(containersItem)
    }

    @objc func viewLogsAction(_ sender: NSMenuItem) {
        guard let containerId = sender.representedObject as? String else { return }
        logger.info("View logs action for: \(containerId)")
        handleContainerAction(.viewLogs(containerId))
    }

    @objc func startContainerAction(_ sender: NSMenuItem) {
        guard let containerId = sender.representedObject as? String else { return }
        logger.info("Start action for: \(containerId)")
        handleContainerAction(.start(containerId))
    }

    @objc func stopContainerAction(_ sender: NSMenuItem) {
        guard let containerId = sender.representedObject as? String else { return }
        logger.info("Stop action for: \(containerId)")
        handleContainerAction(.stop(containerId))
    }

    @objc func restartContainerAction(_ sender: NSMenuItem) {
        guard let containerId = sender.representedObject as? String else { return }
        logger.info("Restart action for: \(containerId)")
        handleContainerAction(.restart(containerId))
    }

    @objc func copyIdAction(_ sender: NSMenuItem) {
        guard let containerId = sender.representedObject as? String else { return }
        logger.info("Copy ID action for: \(containerId)")
        handleContainerAction(.copyId(containerId))
    }

    @objc func removeContainerAction(_ sender: NSMenuItem) {
        guard let containerId = sender.representedObject as? String else { return }
        logger.info("Remove action for: \(containerId)")
        handleContainerAction(.remove(containerId))
    }

    func addActionItems(to menu: NSMenu) {
        // Refresh
        let refreshItem = NSMenuItem(
            title: "Refresh Now",
            action: #selector(refreshAction),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        refreshItem.isEnabled = !containerStore.isRefreshing
        menu.addItem(refreshItem)

        // Hosts submenu
        let hostsItem = NSMenuItem(title: "Hosts", action: nil, keyEquivalent: "")
        let hostsSubmenu = NSMenu()

        // Add each configured host
        for host in settingsStore.hosts {
            let hostItem = NSMenuItem(
                title: host.name,
                action: #selector(switchHost(_:)),
                keyEquivalent: ""
            )
            hostItem.target = self
            hostItem.representedObject = host.id

            // Show checkmark for selected host
            if settingsStore.selectedHostId == host.id {
                hostItem.state = .on
            }

            // Show connection type indicator
            switch host.connectionType {
            case .unixSocket:
                hostItem.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "Local")
            case .ssh:
                hostItem.image = NSImage(systemSymbolName: "network", accessibilityDescription: "SSH")
            case .tcpTLS:
                hostItem.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "TLS")
            }

            hostsSubmenu.addItem(hostItem)
        }

        hostsSubmenu.addItem(NSMenuItem.separator())

        // Add new host option
        let addHostItem = NSMenuItem(
            title: "Add Host...",
            action: #selector(addHost),
            keyEquivalent: ""
        )
        addHostItem.target = self
        addHostItem.image = NSImage(systemSymbolName: "plus.circle", accessibilityDescription: "Add")
        hostsSubmenu.addItem(addHostItem)

        hostsItem.submenu = hostsSubmenu
        menu.addItem(hostsItem)

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
            title: "Quit ContainerBar",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
    }
}

// MARK: - NSMenuDelegate

extension StatusItemController: NSMenuDelegate {
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            // Rebuild menu with fresh content
            self.rebuildMenu()

            // Allow AppKit to finish menu layout and SwiftUI to complete
            // its initial render pass before mutating @Observable state.
            // Task.yield() alone is best-effort; a short sleep guarantees
            // at least one full run loop cycle completes.
            try? await Task.sleep(for: .milliseconds(50))

            // Refresh data when menu opens (now a safe incremental update)
            await self.containerStore.refresh()
        }
    }
}
