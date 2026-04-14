# ContainerBar Backlog

Prioritized list of planned features, improvements, and technical debt for ContainerBar - macOS menu bar Docker/Podman monitoring app.

## High Priority

1. **Cut and verify a replacement hotfix release for the broken 2.0.1 app bundle**
    The release tooling is now patched in source, but users with the already-built 2.0.1 app can still hit the Sparkle loader failure until a rebuilt hotfix is packaged, validated, and redistributed.
## Medium Priority

1. **`TLSConnection.swift` is 308 lines - extract connection lifecycle or parsing helpers**
    Request I/O serialization is now in place, but lifecycle coordination still leaves `TLSConnection.swift` just over the 300-line guideline. Extract additional connection-state helpers or parsing-adjacent utilities so the transport stays easier to audit.

2. **`ContainerMenuCardView.swift` appears to be dead code**
    The 324-line `ContainerMenuCardView` seems superseded by `DashboardMenuView`. If unused, remove it to reduce maintenance surface.

3. **`ContainerStore.swift` is 430 lines - extract metrics logic**
    Rate calculation and metrics history updates could be extracted to a dedicated type, bringing the file under the 300-line convention.

4. **Podman rootless socket path hardcodes UID 1000**
    `ContainerRuntime.swift` line 53 hardcodes `/run/user/1000/podman/podman.sock` for remote Podman. This fails for non-default user IDs. Consider making it configurable via `DockerHost`.

5. **No CI build/test step in GitHub Actions**
    `claude-code-review.yml` runs code review on PRs but doesn't run `swift build` or `swift test`. PRs can pass review without compiling. Add a build+test job.

6. **Build scripts hardcode arm64 architecture**
    `build-release.sh` (line 19) hardcodes `.build/arm64-apple-macosx/release`. Will fail on Intel Macs. Detect architecture or allow override via environment variable.

7. **`getContainerStats(stream:)` ignores the streaming contract**
    `DockerAPIClientImpl.getContainerStats` accepts `stream`, but currently parses a single payload and finishes for all calls. Implement true streaming behavior when `stream=true`, or remove/rename the API contract.

8. **Release validation metadata drift: Homebrew cask path mismatch**
    `CLAUDE.md` points to `~/Desktop/Current Projects/homebrew-tap/`, while `scripts/validate-release.py` checks `~/Desktop/homebrew-tap/Casks/containerbar.rb`. Align to a single canonical path.

9. **Add scoped SwiftLint configuration to avoid linting dependencies**
    Running `swiftlint` currently scans `.build/checkouts` (Sparkle), producing external violations and hiding project-scope signal. Add `.swiftlint.yml` with includes/excludes for project sources only.
## Low Priority

1. **Remove or consolidate duplicate add-host dialogs**
    There are two separate "Add Host" flows: the `NSAlert`-based dialog in `StatusItemController.addHost()` and the SwiftUI `HostPanelView.addHostForm`. These should be consolidated into one path to avoid maintenance burden and UX inconsistency.

2. **Extract `ContainerAction` enum to its own file**
    `ContainerAction` is used across multiple views and the StatusItemController but isn't in a dedicated file. Extract it for discoverability.

3. **Add accessibility labels to container card interactive elements**
    Container cards have hover-only quick action buttons that lack explicit accessibility labels. Screen reader users can't discover or use the stop/start buttons.

4. **CPU percent clamping may hide multi-CPU spikes**
    `DockerRawStats` conversion clamps CPU to `100 * numCPUs`, which is correct, but the UI formatters display `"%.1f%%"` without context. Consider showing per-CPU normalized percentage or adding a tooltip.

5. **ISO8601DateFormatter created per stats parse**
    `ContainerStats.init(from:containerId:)` creates a new `ISO8601DateFormatter()` on every call. This is a known performance anti-pattern in Apple's frameworks. Create a shared static formatter.

6. **Evaluate replacing raw Unix socket with NIOTransportServices or URLSession**
    The custom `UnixSocketConnection` handles HTTP/1.1 manually (headers, chunked encoding). This works but is fragile. Evaluate whether SwiftNIO or Foundation's `URLSession` with Unix socket support could reduce maintenance surface.

7. **`ServiceIcon` static cache never cleared**
    `ServiceIcon.swift` caches loaded icons in a static dictionary that grows unbounded. Add a cache size limit or clearing mechanism.

8. **`menuWillOpen` uses 50ms `Thread.sleep` workaround**
    `StatusItemController+MenuBuilding.swift` sleeps 50ms in `menuWillOpen` to work around an AppKit/SwiftUI layout race. This should be replaced with proper event-based coordination.

9. **`ContainerFetchStrategy` protocol appears unused**
    `Strategies/ContainerFetchStrategy.swift` defines a protocol and descriptors that aren't referenced in production code. Either implement concrete strategies or remove the dead scaffolding.

10. **Health status thresholds are hardcoded**
    `ContainerStats.swift` uses CPU >90% and memory >95% thresholds for health status. These should be configurable constants or user settings.

11. **Build scripts hardcode signing identity**
    `build-release.sh` and `notarize.sh` hardcode the Developer ID signing identity string. Use an environment variable for portability and CI/CD.

12. **Docs still describe a Hosts submenu flow that no longer matches the menu UI**
    `README.md` and `docs/GETTING_STARTED.md` describe adding hosts from a "Hosts" submenu, while current menu construction is dashboard-card-first. Update docs to match current UX and reduce support confusion.

13. **Release date metadata mismatch for v2.0.0**
    `CHANGELOG.md` lists `2.0.0` on `2025-02-11`, but `docs/appcast.xml` has `Thu, 12 Feb 2026` for the same version. Reconcile public release metadata to prevent audit/release confusion.

14. **Stale orchestration document still references DockerBar and early MVP phase**
    `.claude/agents/PROJECT_ORCHESTRATION.md` still uses old product naming and phase language. Refresh to current ContainerBar release-mode reality.

15. **`ContainerBarCore` usage docs reference a missing `UnixSocketStrategy` type**
    `ContainerBarCore.swift` module docs include an example that does not compile against current source. Update the example to use actual public APIs.

16. **App-level tests are still mostly smoke-level**
    `Tests/ContainerBarTests/ContainerBarTests.swift` contains a compile/link smoke test and TODO notes. Add targeted tests around menu-building behavior and controller actions to improve regression coverage.
## Risks & Unknowns

1. **Notarization/appcast release pipeline not validated in this audit run**
    The full release path (`build-release.sh`, `notarize.sh`, appcast publication) requires signing credentials and external services that were not executed in this pass.

2. **Remote SSH/TLS integration behavior was not validated against live hosts**
    Audit conclusions are based on static review and unit tests. End-to-end behavior under real network conditions (latency, host key rotation, reconnect edge cases) remains a validation gap.

3. **`StrictHostKeyChecking=yes` requires explicit `known_hosts` onboarding for new or rotated SSH hosts**
    With `StrictHostKeyChecking=yes`, first-time or rotated-host connections are rejected until the host key is explicitly verified and added to `known_hosts`, so document the onboarding steps for trusting new or changed host keys.

4. **Interactive UI/accessibility behavior was not runtime-verified in this pass**
    UI findings are code-based. Live interaction checks (VoiceOver navigation, keyboard-only flows, menu timing behavior on real hardware) remain outstanding.
## Recommended Next Actions

1. **Validate and document strict SSH host-key onboarding**
    Add/update docs for first-time host trust setup (`known_hosts` flow), and run manual tests for new host, rotated key, and mismatch scenarios.

2. **Cut and smoke-test a replacement hotfix app build**
    Rebuild the release bundle with the fixed framework rpath, run `scripts/validate-release.py`, and confirm the packaged app launches from `/Applications` before publishing the replacement release.

3. **Align transport API contracts with behavior**
    Resolve the stats streaming contract mismatch (`getContainerStats(stream:)`) either by implementing true streaming or simplifying the API.

4. **Fix release metadata and validation drift**
    Align Homebrew tap paths, appcast/changelog dates, and stale docs to keep release operations auditable and reproducible.

5. **Add real CI quality gates plus scoped linting**
    Add `swift build`/`swift test` to PR workflows and scope SwiftLint to project sources so failures are actionable.

6. **Schedule targeted integration validation**
    Run live SSH/TLS host tests and an interactive UI/accessibility pass to close current unknowns.
## Completed

- **Address review follow-up for main-actor isolation on `ConnectionStatusPresentation`** (completed: 2026-04-14)
- **Address review follow-up for whitespace-only `connectionError` handling in `ConnectionStatusPresentation`** (completed: 2026-04-13)
- **Address review follow-up for `ConnectionStatusPresentation.make(...)` API cleanup and coverage** (completed: 2026-04-13)
- **Address review follow-ups for release-tool preflight checks and dashboard connection-state cleanup** (completed: 2026-04-13)
- **Investigate Beelink disconnect state and app launch/menu-open regression** (completed: 2026-04-13)
- **Address follow-up review fixes for add-host validation, request sanitization, and transport fail-closed behavior** (completed: 2026-03-15)
- **Address follow-up review fixes for cancellation propagation and transport invalidation** (completed: 2026-03-15)
- **`SSHTunnelConnection.swift` is 349 lines - extract state/process helpers** (completed: 2026-03-15)
- **`TLSConnection.swift` is 348 lines - extract HTTP parsing helpers** (completed: 2026-03-15)
- **Address follow-up review fixes for main-actor UI isolation, transport locking, and retry/cancellation safety** (completed: 2026-03-15)
- **Address follow-up review fixes for host parsing, HTTP encoding, TLS robustness, and dashboard accessibility** (completed: 2026-03-15)
- **`ConnectionSettingsPane.swift` is 492 lines - extract `AddHostSheet`** (completed: 2026-03-15)
- **Resolve code-review follow-ups for host validation, transport synchronization, and test reliability** (completed: 2026-03-14)
- **`DockerAPIClientImpl.swift` is 464 lines - refactor** (completed: 2026-03-14)
- **Clarify project maturity as Beta Preview across docs and app About pane** (completed: 2026-02-22)
- **TLS errors use wrong error type (`.sshConnectionFailed`)** (completed: 2026-02-22)
- **`DashboardMenuView.swift` is 706 lines - split into separate files** (completed: 2026-02-22)
- **SSH host trust uses TOFU (`StrictHostKeyChecking=accept-new`)** (completed: 2026-02-22)
- **Release app crashes on menu open due to SPM resource bundle lookup path mismatch** (completed: 2026-02-22)
- **BUG: App crashes when opening menu after adding more containers (Beelink)** (completed: 2026-02-18)
- **`DockerSystemInfo.dockerVersion` CodingKey maps to wrong JSON field** (completed: 2026-02-18)
- **Placeholder SettingsView still in ContainerBarApp.swift** (completed: 2026-02-18)
- **Replace `Thread.sleep` with async sleep in SSHTunnelConnection** (completed: 2026-02-18)
- **Audit `@unchecked Sendable` usage for correctness** (completed: 2026-02-18)
- **Add test coverage for ContainerStore** (completed: 2026-02-18)
- **Add error feedback to the UI for container actions** (completed: 2026-02-18)
- **Improve SSH tunnel reliability and error recovery** (completed: 2026-02-18)
- **Implement TCP+TLS connection support** (completed: 2026-02-18)
