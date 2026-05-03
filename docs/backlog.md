# ContainerBar Backlog

Prioritized list of planned features, improvements, and technical debt for ContainerBar - macOS menu bar Docker/Podman monitoring app.

## High Priority

## Medium Priority

## Low Priority

1. **CB-013: Remove or consolidate duplicate add-host dialogs**
    There are two separate "Add Host" flows: the `NSAlert`-based dialog in `StatusItemController.addHost()` and the SwiftUI `HostPanelView.addHostForm`. These should be consolidated into one path to avoid maintenance burden and UX inconsistency.

2. **CB-018: Evaluate replacing raw Unix socket with NIOTransportServices or URLSession**
    The custom `UnixSocketConnection` handles HTTP/1.1 manually (headers, chunked encoding). This works but is fragile. Evaluate whether SwiftNIO or Foundation's `URLSession` with Unix socket support could reduce maintenance surface.

3. **CB-020: `menuWillOpen` uses 50ms `Thread.sleep` workaround**
    `StatusItemController+MenuBuilding.swift` sleeps 50ms in `menuWillOpen` to work around an AppKit/SwiftUI layout race. This should be replaced with proper event-based coordination.

4. **CB-030: Schedule targeted integration validation pass**
    Audit findings are based on static review and unit tests. Run a live SSH/TLS pass against a real host (latency, host key rotation, reconnect edges) and an interactive UI/accessibility pass (VoiceOver, keyboard-only, menu timing on real hardware) to close the validation gaps called out in Risks & Unknowns.

5. **CB-031: Make `StatusItemController` instantiable in tests for routing coverage**
    `StatusItemController.init` calls `NSStatusBar.system.statusItem(...)` and registers a global hotkey, which prevents headless `swift test` instantiation. As a result, the `@objc` action methods (`startContainerAction`, `stopContainerAction`, `restartContainerAction`, `removeContainerAction`, `copyIdAction`, `viewLogsAction`) and the `handleContainerAction` switch are not unit-tested — only the menu sort+filter helper from CB-028 is. Refactor for testability — either inject the status item via a protocol seam, or add a `#if DEBUG` test-only init that skips status-bar/hotkey setup — then add tests verifying each `@objc` selector extracts the right `representedObject` and dispatches the correct `ContainerAction` enum case. Follow-up to CB-028.

Completed items live in [`docs/resolved.md`](resolved.md).
