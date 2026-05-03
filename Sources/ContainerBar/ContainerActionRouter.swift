import Foundation
import AppKit
import ContainerBarCore
import Logging

/// Routes a `ContainerAction` produced by the menu UI into:
///
/// - direct `ContainerStore` calls for state-mutating actions, and
/// - host-supplied closures for AppKit-touching side effects (menu
///   reopen, removal-confirmation alert, log-viewer window, pasteboard
///   write).
///
/// Splitting these out of `StatusItemController` lets the routing switch
/// be unit-tested under headless `swift test` — the host wires real
/// AppKit code into the closures at runtime, while tests inject spies.
@MainActor
final class ContainerActionRouter {
    let containerStore: ContainerStore

    private let logger = Logger(label: "com.containerbar.router")

    /// Called after a state-mutating action (start/stop/restart) so the
    /// host can reopen the menu. No-op by default.
    var onMenuReopenRequested: () -> Void = {}

    /// Called when the user requests `.remove` so the host can show the
    /// destructive confirmation alert.
    var onRemoveRequested: (String) -> Void = { _ in }

    /// Called when the user requests `.viewLogs` so the host can close
    /// the menu and open the log-viewer window.
    var onViewLogsRequested: (String) -> Void = { _ in }

    /// Called when the user requests `.copyId` so the host can write the
    /// container ID to the pasteboard.
    var onCopyIdRequested: (String) -> Void = { _ in }

    init(containerStore: ContainerStore) {
        self.containerStore = containerStore
    }

    func handleContainerAction(_ action: ContainerAction) {
        logger.debug("Handling container action: \(action)")
        switch action {
        case .start(let id):
            logger.info("Starting container: \(id)")
            Task { await containerStore.startContainer(id: id) }
            onMenuReopenRequested()

        case .stop(let id):
            logger.info("Stopping container: \(id)")
            Task { await containerStore.stopContainer(id: id) }
            onMenuReopenRequested()

        case .restart(let id):
            logger.info("Restarting container: \(id)")
            Task { await containerStore.restartContainer(id: id) }
            onMenuReopenRequested()

        case .remove(let id):
            logger.info("Remove requested for container: \(id)")
            onRemoveRequested(id)

        case .copyId(let id):
            logger.info("Copy ID requested for container: \(id)")
            onCopyIdRequested(id)

        case .viewLogs(let id):
            logger.info("View logs requested for container: \(id)")
            onViewLogsRequested(id)
        }
    }
}
