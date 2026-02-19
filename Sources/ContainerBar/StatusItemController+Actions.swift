import AppKit
import ContainerBarCore

// MARK: - Container Actions

extension StatusItemController {
    func handleContainerAction(_ action: ContainerAction) {
        logger.debug("Handling container action: \(action)")
        switch action {
        case .start(let id):
            logger.info("Starting container: \(id)")
            Task {
                await containerStore.startContainer(id: id)
            }
            reopenMenu()

        case .stop(let id):
            logger.info("Stopping container: \(id)")
            Task {
                await containerStore.stopContainer(id: id)
            }
            reopenMenu()

        case .restart(let id):
            logger.info("Restarting container: \(id)")
            Task {
                await containerStore.restartContainer(id: id)
            }
            reopenMenu()

        case .remove(let id):
            logger.info("Remove requested for container: \(id)")
            showRemoveConfirmation(for: id)

        case .copyId(let id):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(id, forType: .string)
            logger.info("Copied container ID to clipboard")

        case .viewLogs(let id):
            logger.info("View logs requested for container: \(id)")
            closeMenuIfOpen()
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
        logger.debug("Opening log viewer for container: \(containerId)")
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

    // MARK: - Host Management

    @objc func switchHost(_ sender: NSMenuItem) {
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

    func reopenMenu() {
        // Small delay to let the menu fully close first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.statusItem.button?.performClick(nil)
        }
    }

    @objc func addHost() {
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

    // MARK: - Menu Actions

    @objc func refreshAction() {
        logger.info("Manual refresh triggered")
        Task {
            await containerStore.refresh(force: true)
        }
    }

    @objc func openSettings() {
        logger.info("Opening settings")
        SettingsWindowController.shared.showSettings(
            settings: settingsStore,
            containerStore: containerStore
        )
    }
}
