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
                self?.router.handleContainerAction(action)
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

        // Use available screen height so the menu adapts to any display size.
        let screenHeight = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.height ?? 800
        let maxMenuHeight = screenHeight - 40

        let hostingView = AutoResizingHostingView(rootView: dashboardView, maxHeight: maxMenuHeight)
        let fittingHeight = min(max(hostingView.fittingSize.height, 300), maxMenuHeight)
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: fittingHeight)

        item.view = hostingView
        return item
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
