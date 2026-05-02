# ContainerBar Backlog

Prioritized list of planned features, improvements, and technical debt for ContainerBar - macOS menu bar Docker/Podman monitoring app.

## High Priority

## Medium Priority

1. **CB-003: Address review follow-up for redundant `Sendable` on `@MainActor` `ConnectionStatusPresentation`**
    Remove the explicit `Sendable` conformance from the main-actor-isolated dashboard presentation struct so Swift 6 does not warn about redundant sendability.

2. **CB-004: `TLSConnection.swift` is 308 lines - extract connection lifecycle or parsing helpers**
    Request I/O serialization is now in place, but lifecycle coordination still leaves `TLSConnection.swift` just over the 300-line guideline. Extract additional connection-state helpers or parsing-adjacent utilities so the transport stays easier to audit.

3. **CB-005: `ContainerMenuCardView.swift` appears to be dead code**
    The 324-line `ContainerMenuCardView` seems superseded by `DashboardMenuView`. If unused, remove it to reduce maintenance surface.

4. **CB-006: `ContainerStore.swift` is 430 lines - extract metrics logic**
    Rate calculation and metrics history updates could be extracted to a dedicated type, bringing the file under the 300-line convention.

5. **CB-007: Podman rootless socket path hardcodes UID 1000**
    `ContainerRuntime.swift` line 53 hardcodes `/run/user/1000/podman/podman.sock` for remote Podman. This fails for non-default user IDs. Consider making it configurable via `DockerHost`.

6. **CB-008: No CI build/test step in GitHub Actions**
    `claude-code-review.yml` runs code review on PRs but doesn't run `swift build` or `swift test`. PRs can pass review without compiling. Add a build+test job.

7. **CB-009: Build scripts hardcode arm64 architecture**
    `build-release.sh` (line 19) hardcodes `.build/arm64-apple-macosx/release`. Will fail on Intel Macs. Detect architecture or allow override via environment variable.

8. **CB-010: `getContainerStats(stream:)` ignores the streaming contract**
    `DockerAPIClientImpl.getContainerStats` accepts `stream`, but currently parses a single payload and finishes for all calls. Implement true streaming behavior when `stream=true`, or remove/rename the API contract.

9. **CB-011: Release validation metadata drift: Homebrew cask path mismatch**
    `CLAUDE.md` points to `~/Desktop/Current Projects/homebrew-tap/`, while `scripts/validate-release.py` checks `~/Desktop/homebrew-tap/Casks/containerbar.rb`. Align to a single canonical path.

10. **CB-012: Add scoped SwiftLint configuration to avoid linting dependencies**
    Running `swiftlint` currently scans `.build/checkouts` (Sparkle), producing external violations and hiding project-scope signal. Add `.swiftlint.yml` with includes/excludes for project sources only.

11. **CB-029: Validate and document strict SSH host-key onboarding**
    With `StrictHostKeyChecking=yes`, first-time and rotated-host connections are rejected until the host key is explicitly trusted in `known_hosts`. Document the onboarding flow in user docs and run manual tests covering new host, rotated key, and mismatch scenarios so support has a clear path.
## Low Priority

1. **CB-013: Remove or consolidate duplicate add-host dialogs**
    There are two separate "Add Host" flows: the `NSAlert`-based dialog in `StatusItemController.addHost()` and the SwiftUI `HostPanelView.addHostForm`. These should be consolidated into one path to avoid maintenance burden and UX inconsistency.

2. **CB-014: Extract `ContainerAction` enum to its own file**
    `ContainerAction` is used across multiple views and the StatusItemController but isn't in a dedicated file. Extract it for discoverability.

3. **CB-015: Add accessibility labels to container card interactive elements**
    Container cards have hover-only quick action buttons that lack explicit accessibility labels. Screen reader users can't discover or use the stop/start buttons.

4. **CB-016: CPU percent clamping may hide multi-CPU spikes**
    `DockerRawStats` conversion clamps CPU to `100 * numCPUs`, which is correct, but the UI formatters display `"%.1f%%"` without context. Consider showing per-CPU normalized percentage or adding a tooltip.

5. **CB-017: ISO8601DateFormatter created per stats parse**
    `ContainerStats.init(from:containerId:)` creates a new `ISO8601DateFormatter()` on every call. This is a known performance anti-pattern in Apple's frameworks. Create a shared static formatter.

6. **CB-018: Evaluate replacing raw Unix socket with NIOTransportServices or URLSession**
    The custom `UnixSocketConnection` handles HTTP/1.1 manually (headers, chunked encoding). This works but is fragile. Evaluate whether SwiftNIO or Foundation's `URLSession` with Unix socket support could reduce maintenance surface.

7. **CB-019: `ServiceIcon` static cache never cleared**
    `ServiceIcon.swift` caches loaded icons in a static dictionary that grows unbounded. Add a cache size limit or clearing mechanism.

8. **CB-020: `menuWillOpen` uses 50ms `Thread.sleep` workaround**
    `StatusItemController+MenuBuilding.swift` sleeps 50ms in `menuWillOpen` to work around an AppKit/SwiftUI layout race. This should be replaced with proper event-based coordination.

9. **CB-021: `ContainerFetchStrategy` protocol appears unused**
    `Strategies/ContainerFetchStrategy.swift` defines a protocol and descriptors that aren't referenced in production code. Either implement concrete strategies or remove the dead scaffolding.

10. **CB-022: Health status thresholds are hardcoded**
    `ContainerStats.swift` uses CPU >90% and memory >95% thresholds for health status. These should be configurable constants or user settings.

11. **CB-023: Build scripts hardcode signing identity**
    `build-release.sh` and `notarize.sh` hardcode the Developer ID signing identity string. Use an environment variable for portability and CI/CD.

12. **CB-024: Docs still describe a Hosts submenu flow that no longer matches the menu UI**
    `README.md` and `docs/GETTING_STARTED.md` describe adding hosts from a "Hosts" submenu, while current menu construction is dashboard-card-first. Update docs to match current UX and reduce support confusion.

13. **CB-025: Release date metadata mismatch for v2.0.0**
    `CHANGELOG.md` lists `2.0.0` on `2025-02-11`, but `docs/appcast.xml` has `Thu, 12 Feb 2026` for the same version. Reconcile public release metadata to prevent audit/release confusion.

14. **CB-026: Stale orchestration document still references DockerBar and early MVP phase**
    `.claude/agents/PROJECT_ORCHESTRATION.md` still uses old product naming and phase language. Refresh to current ContainerBar release-mode reality.

15. **CB-027: `ContainerBarCore` usage docs reference a missing `UnixSocketStrategy` type**
    `ContainerBarCore.swift` module docs include an example that does not compile against current source. Update the example to use actual public APIs.

16. **CB-028: App-level tests are still mostly smoke-level**
    `Tests/ContainerBarTests/ContainerBarTests.swift` contains a compile/link smoke test and TODO notes. Add targeted tests around menu-building behavior and controller actions to improve regression coverage.

17. **CB-030: Schedule targeted integration validation pass**
    Audit findings are based on static review and unit tests. Run a live SSH/TLS pass against a real host (latency, host key rotation, reconnect edges) and an interactive UI/accessibility pass (VoiceOver, keyboard-only, menu timing on real hardware) to close the validation gaps called out in Risks & Unknowns.
Completed items live in [`docs/resolved.md`](resolved.md).
