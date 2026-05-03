# ContainerBar - Resolved Items

## ~~Implement TCP+TLS connection support~~
**Resolved**: 2026-02-18

## ~~Improve SSH tunnel reliability and error recovery~~
**Resolved**: 2026-02-18

## ~~Add error feedback to the UI for container actions~~
**Resolved**: 2026-02-18

## ~~Add test coverage for ContainerStore~~
**Resolved**: 2026-02-18

## ~~Audit `@unchecked Sendable` usage for correctness~~
**Resolved**: 2026-02-18

## ~~Replace `Thread.sleep` with async sleep in SSHTunnelConnection~~
**Resolved**: 2026-02-18

## ~~Placeholder SettingsView still in ContainerBarApp.swift~~
**Resolved**: 2026-02-18

## ~~`DockerSystemInfo.dockerVersion` CodingKey maps to wrong JSON field~~
**Resolved**: 2026-02-18

## ~~BUG: App crashes when opening menu after adding more containers (Beelink)~~
**Resolved**: 2026-02-18

## ~~Release app crashes on menu open due to SPM resource bundle lookup path mismatch~~
**Resolved**: 2026-02-22

## ~~SSH host trust uses TOFU (`StrictHostKeyChecking=accept-new`)~~
**Resolved**: 2026-02-22

## ~~`DashboardMenuView.swift` is 706 lines - split into separate files~~
**Resolved**: 2026-02-22

## ~~TLS errors use wrong error type (`.sshConnectionFailed`)~~
**Resolved**: 2026-02-22

## ~~Clarify project maturity as Beta Preview across docs and app About pane~~
**Resolved**: 2026-02-22

## ~~`DockerAPIClientImpl.swift` is 464 lines - refactor~~
**Resolved**: 2026-03-14

## ~~Resolve code-review follow-ups for host validation, transport synchronization, and test reliability~~
**Resolved**: 2026-03-14

## ~~`ConnectionSettingsPane.swift` is 492 lines - extract `AddHostSheet`~~
**Resolved**: 2026-03-15

## ~~Address follow-up review fixes for host parsing, HTTP encoding, TLS robustness, and dashboard accessibility~~
**Resolved**: 2026-03-15

## ~~Address follow-up review fixes for main-actor UI isolation, transport locking, and retry/cancellation safety~~
**Resolved**: 2026-03-15

## ~~`TLSConnection.swift` is 348 lines - extract HTTP parsing helpers~~
**Resolved**: 2026-03-15

## ~~`SSHTunnelConnection.swift` is 349 lines - extract state/process helpers~~
**Resolved**: 2026-03-15

## ~~Address follow-up review fixes for cancellation propagation and transport invalidation~~
**Resolved**: 2026-03-15

## ~~Address follow-up review fixes for add-host validation, request sanitization, and transport fail-closed behavior~~
**Resolved**: 2026-03-15

## ~~Investigate Beelink disconnect state and app launch/menu-open regression~~
**Resolved**: 2026-04-13

## ~~Address review follow-ups for release-tool preflight checks and dashboard connection-state cleanup~~
**Resolved**: 2026-04-13

## ~~Address review follow-up for `ConnectionStatusPresentation.make(...)` API cleanup and coverage~~
**Resolved**: 2026-04-13

## ~~Address review follow-up for whitespace-only `connectionError` handling in `ConnectionStatusPresentation`~~
**Resolved**: 2026-04-13

## ~~Address review follow-up for main-actor isolation on `ConnectionStatusPresentation`~~
**Resolved**: 2026-04-14

## ~~Address retry-state presentation after failed refresh~~
**Resolved**: 2026-04-14

## ~~CB-001: Cut and verify a replacement hotfix release for the broken 2.0.1 app bundle~~
**Resolved**: 2026-04-14 (shipped as v2.0.2)
**Description**: Rebuilt and shipped the hotfix as v2.0.2 with the corrected Sparkle appcast EdDSA signature and file size for the v2.0.1 update path, so users on the broken 2.0.1 bundle can update cleanly.

## ~~CB-014: Extract `ContainerAction` enum to its own file~~
**Resolved**: 2026-05-01
**Description**: Moved the `ContainerAction` enum out of `ContainerRowView.swift` into a dedicated `Sources/ContainerBar/ContainerAction.swift` so the type is discoverable to the views and `StatusItemController` extensions that consume it.

## ~~CB-021: `ContainerFetchStrategy` protocol appears unused~~
**Resolved**: 2026-05-01
**Description**: Confirmed the protocol and its descriptor types had no consumers outside the file itself. Deleted `Sources/ContainerBarCore/Strategies/ContainerFetchStrategy.swift` and removed the now-empty `Strategies/` directory.

## ~~CB-024: Docs still describe a Hosts submenu flow that no longer matches the menu UI~~
**Resolved**: 2026-05-01
**Description**: Rewrote the "Adding a Remote Host" sections in `README.md` and `docs/GETTING_STARTED.md` to route users through Settings > Connections > Add Host, matching the dashboard-card-first menu UI. Dropped the stale `images/hosts-menu.png` reference.

## ~~CB-025: Release date metadata mismatch for v2.0.0~~
**Resolved**: 2026-05-01
**Description**: Aligned the v2.0.0 entry in `CHANGELOG.md` to the actual git tag date (`2026-02-12`), matching `docs/appcast.xml`.

## ~~CB-026: Stale orchestration document still references DockerBar and early MVP phase~~
**Resolved**: 2026-05-01
**Description**: Refreshed `.claude/agents/PROJECT_ORCHESTRATION.md` to use the current ContainerBar product name throughout and updated the header phase to "Release & Maintenance (post-2.0 beta preview)".

## ~~CB-027: `ContainerBarCore` usage docs reference a missing `UnixSocketStrategy` type~~
**Resolved**: 2026-05-01
**Description**: Replaced the broken docs example in `Sources/ContainerBarCore/ContainerBarCore.swift` with the real public API: `try DockerAPIClientImpl.local()` followed by `listContainers(all:)`.

## ~~CB-008: No CI build/test step in GitHub Actions~~
**Resolved**: 2026-05-02
**Description**: Added `.github/workflows/swift-ci.yml` running `swift build`, `swift test`, and `swiftlint` on every PR and push to main. Build/test job uses macos-latest with SPM build cache; lint job runs in parallel.

## ~~CB-009: Build scripts hardcode arm64 architecture~~
**Resolved**: 2026-05-02
**Description**: Replaced the hardcoded `.build/arm64-apple-macosx/release` path in `scripts/build-release.sh` with arch detection via `uname -m`, with a `BUILD_DIR` env var override for callers that need to point elsewhere.

## ~~CB-011: Release validation metadata drift: Homebrew cask path mismatch~~
**Resolved**: 2026-04-14 (already shipped in v2.0.2)
**Description**: Backlog discovery only — `scripts/validate-release.py` was already aligned to `~/Desktop/Current Projects/homebrew-tap/Casks/containerbar.rb`, matching `CLAUDE.md`. CHANGELOG 2.0.2 records the fix as "Corrected Homebrew tap path in release validator". The backlog item just never got closed.

## ~~CB-012: Add scoped SwiftLint configuration to avoid linting dependencies~~
**Resolved**: 2026-05-02
**Description**: Added `.swiftlint.yml` scoping linting to `Sources/` and `Tests/` and excluding `.build`, `dist`, and `Distribution`. Fixed two pre-existing serious violations (force_try in a `#Preview`, an over-long line in `UnixSocketConnection.swift`) so the lint job is green from the start.

## ~~CB-004: `TLSConnection.swift` is 308 lines - extract connection lifecycle or parsing helpers~~
**Resolved**: 2026-05-02
**Description**: Extracted the HTTP-receive helpers (`receiveHTTPResponse`, `receiveChunk`) from `TLSConnection.swift` into a new `Sources/ContainerBarCore/API/TLSHTTPReceive.swift` as free functions, since they don't touch any private state on the type. `TLSConnection.swift` drops from 308 to 224 lines, comfortably under the 300-line guideline.

## ~~CB-005: `ContainerMenuCardView.swift` appears to be dead code~~
**Resolved**: 2026-05-02
**Description**: Confirmed `ContainerMenuCardView` had zero references outside its own file (superseded by `DashboardMenuView`). Deleted `Sources/ContainerBar/Views/ContainerMenuCardView.swift` to reduce maintenance surface.

## ~~CB-006: `ContainerStore.swift` is 430 lines - extract metrics logic~~
**Resolved**: 2026-05-02
**Description**: Three-pronged extraction. (1) Pulled rate-of-change calculation and its previous-snapshot state into a new `MetricsRateTracker` type (`Sources/ContainerBar/Stores/MetricsRateTracker.swift`). (2) Lifted the connection-error-to-string switch into a free `userFriendlyConnectionErrorMessage(for:)` in `ConnectionErrorMessage.swift`. (3) Deduplicated the four near-identical container-action methods (start/stop/restart/remove) behind a single `performContainerAction` helper. `ContainerStore.swift` drops from 433 to 302 lines.

## ~~CB-003: Address review follow-up for redundant `Sendable` on `@MainActor` `ConnectionStatusPresentation`~~
**Resolved**: 2026-05-02
**Description**: Removed the redundant `Sendable` conformance from the nested `enum State` in `ConnectionStatusPresentation`. Pure value enums get `Sendable` synthesized automatically; the explicit annotation was noise.

## ~~CB-007: Podman rootless socket path hardcodes UID 1000~~
**Resolved**: 2026-05-02
**Description**: Parameterized `ContainerRuntime.defaultRemoteSocketPath(podmanUID:)` and added an optional `remotePodmanUID` field to `DockerHost`. `DockerAPIClientImpl` now passes `host.remotePodmanUID ?? ContainerRuntime.defaultPodmanUID` when computing the SSH-side fallback path, so callers with non-1000 user IDs can override programmatically without supplying a full socket path. UI surfacing left for a future task.

## ~~CB-010: `getContainerStats(stream:)` ignores the streaming contract~~
**Resolved**: 2026-05-02
**Description**: Removed the unused `stream: Bool` parameter and `AsyncThrowingStream` return type from `DockerAPIClient.getContainerStats`. The method now returns a single `ContainerStats` snapshot, which is what the only caller (`ContainerFetcher`) actually used. Updated both mocks and the one direct test that exercised the old contract.

## ~~CB-029: Validate and document strict SSH host-key onboarding~~
**Resolved**: 2026-05-02
**Description**: Added a "First-Time Host Trust (SSH Host Keys)" subsection to `docs/GETTING_STARTED.md` covering new-host setup (`ssh user@host` once to populate `~/.ssh/known_hosts`), rotated-key recovery (`ssh-keygen -R host` then re-add), and the suspected-mismatch scenario as a security-incident path. The strict-key behavior in `SSHTunnelProcessLauncher` is unchanged; this just gives users a clear, supported onboarding path.

## ~~CB-015: Add accessibility labels to container card interactive elements~~
**Resolved**: 2026-05-02
**Description**: Added `.accessibilityLabel(...)` to each branch of `ContainerCardView.quickActionButton` so screen-reader users get e.g. "Stop container nginx-proxy" instead of an unlabeled icon. Existing `.help()` tooltips kept for sighted hover users.

## ~~CB-016: CPU percent clamping may hide multi-CPU spikes~~
**Resolved**: 2026-05-02
**Description**: Added a `.help(...)` tooltip on the CPU display in `ContainerCardView` showing total %, online-CPU count, and per-CPU normalized percentage (e.g. "120.0% across 4 CPUs (30.0% per CPU)"), giving readers context for values that exceed 100% on multi-core containers.

## ~~CB-017: ISO8601DateFormatter created per stats parse~~
**Resolved**: 2026-05-02
**Description**: Replaced the per-call `ISO8601DateFormatter()` construction in `ContainerStats.init(from:containerId:)` with a single shared `static let timestampFormatter`. Annotated with `nonisolated(unsafe)` since `ISO8601DateFormatter.date(from:)` is documented thread-safe under Swift 6 strict concurrency.

## ~~CB-019: `ServiceIcon` static cache never cleared~~
**Resolved**: 2026-05-02
**Description**: Added a hard cap (`iconCacheLimit = 128`) to `ServiceIcon.iconCache`. When the cache hits the ceiling we evict the dictionary's first key before inserting, so the static cache can no longer grow without bound if new icon variants get added.

## ~~CB-022: Health status thresholds are hardcoded~~
**Resolved**: 2026-05-02
**Description**: Lifted the magic numbers from `ContainerMetricsSnapshot.overallHealth` into named static constants on the type (`cpuWarningThresholdPercent = 90`, `memoryWarningThresholdFraction = 0.95`). Behavior unchanged; the thresholds are now discoverable and ready to be wired to user settings later if desired.

## ~~CB-023: Build scripts hardcode signing identity~~
**Resolved**: 2026-05-02
**Description**: `scripts/build-release.sh` now reads `SIGNING_IDENTITY` and `TEAM_ID` from the environment (with the existing values as fallback defaults), and `scripts/notarize.sh` does the same for `APPLE_ID` and `TEAM_ID`. CI and contributors with a different Apple Developer team can now run the release pipeline without editing the scripts.
