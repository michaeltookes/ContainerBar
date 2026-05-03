import AppKit
import ContainerBarCore

// MARK: - Container Actions

extension StatusItemController {
    func showRemoveConfirmation(for containerId: String) {
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

    func showLogViewer(for containerId: String) {
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

    func reopenMenu() {
        // Small delay to let the menu fully close first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.statusItem.button?.performClick(nil)
        }
    }

    func openSettings() {
        logger.info("Opening settings")
        SettingsWindowController.shared.showSettings(
            settings: settingsStore,
            containerStore: containerStore
        )
    }
}
