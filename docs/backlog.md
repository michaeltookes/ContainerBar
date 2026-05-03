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

4. **CB-028: App-level tests are still mostly smoke-level**
    `Tests/ContainerBarTests/ContainerBarTests.swift` contains a compile/link smoke test and TODO notes. Add targeted tests around menu-building behavior and controller actions to improve regression coverage.

5. **CB-030: Schedule targeted integration validation pass**
    Audit findings are based on static review and unit tests. Run a live SSH/TLS pass against a real host (latency, host key rotation, reconnect edges) and an interactive UI/accessibility pass (VoiceOver, keyboard-only, menu timing on real hardware) to close the validation gaps called out in Risks & Unknowns.

Completed items live in [`docs/resolved.md`](resolved.md).
