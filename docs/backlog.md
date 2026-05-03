# ContainerBar Backlog

Prioritized list of planned features, improvements, and technical debt for ContainerBar - macOS menu bar Docker/Podman monitoring app.

## High Priority

## Medium Priority

## Low Priority

1. **CB-013: Remove or consolidate duplicate add-host dialogs**
    There are two separate "Add Host" flows: the `NSAlert`-based dialog in `StatusItemController.addHost()` and the SwiftUI `HostPanelView.addHostForm`. These should be consolidated into one path to avoid maintenance burden and UX inconsistency.

2. **CB-015: Add accessibility labels to container card interactive elements**
    Container cards have hover-only quick action buttons that lack explicit accessibility labels. Screen reader users can't discover or use the stop/start buttons.

3. **CB-016: CPU percent clamping may hide multi-CPU spikes**
    `DockerRawStats` conversion clamps CPU to `100 * numCPUs`, which is correct, but the UI formatters display `"%.1f%%"` without context. Consider showing per-CPU normalized percentage or adding a tooltip.

4. **CB-017: ISO8601DateFormatter created per stats parse**
    `ContainerStats.init(from:containerId:)` creates a new `ISO8601DateFormatter()` on every call. This is a known performance anti-pattern in Apple's frameworks. Create a shared static formatter.

5. **CB-018: Evaluate replacing raw Unix socket with NIOTransportServices or URLSession**
    The custom `UnixSocketConnection` handles HTTP/1.1 manually (headers, chunked encoding). This works but is fragile. Evaluate whether SwiftNIO or Foundation's `URLSession` with Unix socket support could reduce maintenance surface.

6. **CB-019: `ServiceIcon` static cache never cleared**
    `ServiceIcon.swift` caches loaded icons in a static dictionary that grows unbounded. Add a cache size limit or clearing mechanism.

7. **CB-020: `menuWillOpen` uses 50ms `Thread.sleep` workaround**
    `StatusItemController+MenuBuilding.swift` sleeps 50ms in `menuWillOpen` to work around an AppKit/SwiftUI layout race. This should be replaced with proper event-based coordination.

8. **CB-022: Health status thresholds are hardcoded**
    `ContainerStats.swift` uses CPU >90% and memory >95% thresholds for health status. These should be configurable constants or user settings.

9. **CB-023: Build scripts hardcode signing identity**
    `build-release.sh` and `notarize.sh` hardcode the Developer ID signing identity string. Use an environment variable for portability and CI/CD.

10. **CB-028: App-level tests are still mostly smoke-level**
    `Tests/ContainerBarTests/ContainerBarTests.swift` contains a compile/link smoke test and TODO notes. Add targeted tests around menu-building behavior and controller actions to improve regression coverage.

11. **CB-030: Schedule targeted integration validation pass**
    Audit findings are based on static review and unit tests. Run a live SSH/TLS pass against a real host (latency, host key rotation, reconnect edges) and an interactive UI/accessibility pass (VoiceOver, keyboard-only, menu timing on real hardware) to close the validation gaps called out in Risks & Unknowns.

Completed items live in [`docs/resolved.md`](resolved.md).
