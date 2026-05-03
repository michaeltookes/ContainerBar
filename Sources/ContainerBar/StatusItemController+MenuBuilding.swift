import AppKit
import SwiftUI
import ContainerBarCore

// MARK: - Menu Building

extension StatusItemController {
    func rebuildMenu(onFirstAppear: (() -> Void)? = nil) {
        guard let menu = statusItem.menu else { return }

        menu.removeAllItems()

        // Main content card (SwiftUI)
        let cardItem = createCardMenuItem(onFirstAppear: onFirstAppear)
        menu.addItem(cardItem)
    }

    func createCardMenuItem(onFirstAppear: (() -> Void)? = nil) -> NSMenuItem {
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
            },
            onFirstAppear: onFirstAppear
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

            // Rebuild and wait for SwiftUI's initial render to land before
            // mutating @Observable state — otherwise the refresh can race
            // the first body pass. The signal is `.onAppear` on the
            // dashboard root; the safety timeout exists only to unwedge
            // the refresh if `.onAppear` never fires (e.g. menu dismissed
            // before display).
            await self.rebuildAndAwaitFirstAppear(timeout: .milliseconds(250))

            await self.containerStore.refresh()
        }
    }

    @MainActor
    private func rebuildAndAwaitFirstAppear(timeout: Duration) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let gate = MenuOpenGate { cont.resume() }
            self.rebuildMenu(onFirstAppear: { gate.fire() })
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                gate.fire()
            }
        }
    }
}

/// One-shot main-actor gate that resumes a continuation on the first
/// `fire()` and ignores subsequent calls. Used to race SwiftUI's
/// `.onAppear` against a safety timeout without leaking continuations.
@MainActor
private final class MenuOpenGate {
    private var fired = false
    private let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }

    func fire() {
        guard !fired else { return }
        fired = true
        action()
    }
}
