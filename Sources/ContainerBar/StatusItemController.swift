import AppKit
import SwiftUI
import ContainerBarCore
import Logging
import KeyboardShortcuts

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
    private let logger = Logger(label: "com.containerbar.statusitem")

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
        setupGlobalHotkey()

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

        // Use SF Symbol for menu bar icon
        if let image = NSImage(systemSymbolName: "shippingbox.fill", accessibilityDescription: "Docker") {
            image.isTemplate = true
            button.image = image
        }

        // Set accessibility
        button.toolTip = "ContainerBar - Docker Container Monitor"
        button.setAccessibilityLabel("ContainerBar")
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

    // MARK: - Global Hotkey

    private func setupGlobalHotkey() {
        KeyboardShortcuts.onKeyUp(for: .toggleMenu) { [weak self] in
            Task { @MainActor in
                self?.toggleMenu()
            }
        }
        logger.info("Global hotkey registered")
    }

    /// Toggle the menu bar dropdown open/closed
    func toggleMenu() {
        guard let button = statusItem.button else { return }

        // Check if menu is currently open
        if let menu = statusItem.menu, menu.highlightedItem != nil {
            // Menu is open, close it
            menu.cancelTracking()
        } else {
            // Menu is closed, open it
            button.performClick(nil)
        }
    }

    // MARK: - Icon Updates

    private func updateIcon() {
        guard let button = statusItem.button else { return }

        let runningCount = containerStore.containers.filter { $0.state == .running }.count
        let totalCount = containerStore.containers.count

        // Calculate CPU and memory percentages from metrics
        let cpuPercent = containerStore.metricsSnapshot?.totalCPUPercent ?? 0
        let memoryPercent: Double
        if let metrics = containerStore.metricsSnapshot,
           metrics.totalMemoryLimitBytes > 0 {
            memoryPercent = Double(metrics.totalMemoryUsedBytes) / Double(metrics.totalMemoryLimitBytes) * 100
        } else {
            memoryPercent = 0
        }

        // Build renderer config
        let config = DockerIconRenderer.Config(
            style: settingsStore.iconStyle,
            runningCount: runningCount,
            totalCount: totalCount,
            cpuPercent: cpuPercent,
            memoryPercent: memoryPercent,
            isRefreshing: containerStore.isRefreshing,
            isConnected: containerStore.isConnected,
            hasError: containerStore.connectionError != nil
        )

        // Render the icon
        let image = DockerIconRenderer.render(config: config)
        button.image = image

        // Show running count as title (for container count style only)
        if settingsStore.iconStyle == .containerCount && totalCount > 0 && containerStore.isConnected {
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

        // Container actions submenu
        addContainerActionsSubmenu(to: menu)

        menu.addItem(NSMenuItem.separator())

        // Actions section
        addActionItems(to: menu)
    }

    private func addContainerActionsSubmenu(to menu: NSMenu) {
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

    @objc private func viewLogsAction(_ sender: NSMenuItem) {
        guard let containerId = sender.representedObject as? String else { return }
        logger.info("View logs action for: \(containerId)")
        handleContainerAction(.viewLogs(containerId))
    }

    @objc private func startContainerAction(_ sender: NSMenuItem) {
        guard let containerId = sender.representedObject as? String else { return }
        logger.info("Start action for: \(containerId)")
        handleContainerAction(.start(containerId))
    }

    @objc private func stopContainerAction(_ sender: NSMenuItem) {
        guard let containerId = sender.representedObject as? String else { return }
        logger.info("Stop action for: \(containerId)")
        handleContainerAction(.stop(containerId))
    }

    @objc private func restartContainerAction(_ sender: NSMenuItem) {
        guard let containerId = sender.representedObject as? String else { return }
        logger.info("Restart action for: \(containerId)")
        handleContainerAction(.restart(containerId))
    }

    @objc private func copyIdAction(_ sender: NSMenuItem) {
        guard let containerId = sender.representedObject as? String else { return }
        logger.info("Copy ID action for: \(containerId)")
        handleContainerAction(.copyId(containerId))
    }

    @objc private func removeContainerAction(_ sender: NSMenuItem) {
        guard let containerId = sender.representedObject as? String else { return }
        logger.info("Remove action for: \(containerId)")
        handleContainerAction(.remove(containerId))
    }

    private func createCardMenuItem() -> NSMenuItem {
        let item = NSMenuItem()

        let dashboardView = DashboardMenuView(
            onAction: { [weak self] action in
                self?.handleContainerAction(action)
            },
            onSettings: { [weak self] in
                self?.openSettings()
            },
            onHosts: { [weak self] in
                // Open hosts submenu - for now just reopen menu
                self?.reopenMenu()
            }
        )
        .environment(containerStore)
        .environment(settingsStore)

        let hostingView = NSHostingView(rootView: dashboardView)

        // Calculate height based on content
        // Base: header(~50) + status bar(~50) + stats grid(~140) + container section(~200) + action bar(~50)
        let baseHeight: CGFloat = 490
        // Adjust based on container count (max 400pt for scroll area)
        let containerCount = containerStore.containers.count
        let adjustedHeight = containerCount == 0 ? 350 : min(baseHeight, 550)

        hostingView.frame = NSRect(x: 0, y: 0, width: 380, height: adjustedHeight)

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

    @objc private func switchHost(_ sender: NSMenuItem) {
        guard let hostId = sender.representedObject as? UUID else { return }
        logger.info("Switching to host: \(hostId)")
        settingsStore.selectedHostId = hostId
        containerStore.reinitializeFetcher()

        // Reopen menu immediately with loading state
        reopenMenu()

        // Fetch data in background - UI will update reactively
        Task {
            await containerStore.refresh(force: true)
        }
    }

    private func reopenMenu() {
        // Small delay to let the menu fully close first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.statusItem.button?.performClick(nil)
        }
    }

    @objc private func addHost() {
        logger.info("Opening add host dialog")

        let alert = NSAlert()
        alert.messageText = "Add Remote Host"
        alert.informativeText = "Enter the SSH connection details for your remote Docker host."
        alert.alertStyle = .informational

        // Helper to create properly styled editable text field
        func makeTextField(placeholder: String) -> NSTextField {
            let field = NSTextField()
            field.placeholderString = placeholder
            field.isEditable = true
            field.isSelectable = true
            field.isBordered = true
            field.isBezeled = true
            field.bezelStyle = .roundedBezel
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 250).isActive = true
            return field
        }

        // Create fields
        let nameLabel = NSTextField(labelWithString: "Name:")
        let nameField = makeTextField(placeholder: "My Server")

        let hostLabel = NSTextField(labelWithString: "Host (IP or hostname):")
        let hostField = makeTextField(placeholder: "192.168.1.100 or myserver.local")

        let userLabel = NSTextField(labelWithString: "SSH User:")
        let userField = makeTextField(placeholder: "root")

        // Create stack view
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false

        stackView.addArrangedSubview(nameLabel)
        stackView.addArrangedSubview(nameField)
        stackView.addArrangedSubview(hostLabel)
        stackView.addArrangedSubview(hostField)
        stackView.addArrangedSubview(userLabel)
        stackView.addArrangedSubview(userField)

        // Set stack view size
        stackView.setFrameSize(stackView.fittingSize)

        alert.accessoryView = stackView
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let name = nameField.stringValue.isEmpty ? "Remote Host" : nameField.stringValue
            let host = hostField.stringValue
            let user = userField.stringValue.isEmpty ? "root" : userField.stringValue

            guard !host.isEmpty else {
                logger.warning("Host field is empty")
                return
            }

            let newHost = DockerHost(
                name: name,
                connectionType: .ssh,
                isDefault: false,
                host: host,
                sshUser: user,
                sshPort: 22
            )

            settingsStore.addHost(newHost)
            logger.info("Added new host: \(name) (\(host))")
        }
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
            showLogViewer(for: id)
        }
    }

    private func showRemoveConfirmation(for containerId: String) {
        guard let container = containerStore.containers.first(where: { $0.id == containerId }) else {
            return
        }

        let isRunning = container.state == .running

        let alert = NSAlert()
        alert.messageText = "Remove Container?"

        if isRunning {
            alert.informativeText = "'\(container.displayName)' is currently running. It will be force-stopped and removed. This action cannot be undone."
        } else {
            alert.informativeText = "Are you sure you want to remove '\(container.displayName)'? This action cannot be undone."
        }

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
            Task {
                await containerStore.removeContainer(id: containerId, force: isRunning)
            }
        }
    }

    private func showLogViewer(for containerId: String) {
        guard let container = containerStore.containers.first(where: { $0.id == containerId }) else {
            logger.warning("Container not found for log viewer: \(containerId)")
            return
        }

        do {
            let fetcher: ContainerFetcher
            if let host = settingsStore.selectedHost {
                fetcher = try ContainerFetcher.forHost(host)
            } else {
                fetcher = try ContainerFetcher.local()
            }

            LogViewerWindowController.shared.showLogs(
                containerId: containerId,
                containerName: container.displayName,
                fetcher: fetcher
            )
        } catch {
            logger.error("Failed to create fetcher for log viewer: \(error)")
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
        SettingsWindowController.shared.showSettings(
            settings: settingsStore,
            containerStore: containerStore
        )
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
