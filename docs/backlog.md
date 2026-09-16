# ContainerBar Backlog

Prioritized list of planned features, improvements, and technical debt for ContainerBar - macOS menu bar Docker/Podman monitoring app.

Item ids are stable `CB-NNN` numbers and are never reused. Completed items move to [`docs/resolved.md`](resolved.md).

## Medium Priority

### CB-059: Configure required status checks on `main`
**Priority**: Medium
**Description**: Follow-up from CB-050 / PR #47. Configure GitHub branch
protection or a repository ruleset for `main` so the Swift CI jobs (`Build &
Test` and `SwiftLint`) and `Prowl QA` must pass before merge. This remains a
manual owner action because required-check enforcement lives in GitHub
repository settings rather than committed workflow files. Keep this item open
until the owner verifies the rule is active against `main`.

## Low Priority

### CB-051: Universal binary or explicit Intel decision
**Priority**: Low
**Description**: Decision recorded 2026-09-11: Apple Silicon only. Revisit only if Intel users ask. If revisited, xcodebuild with `ARCHS="arm64 x86_64"` produces a universal binary from the same release script.

### CB-052: Accessibility pass for VoiceOver and keyboard-only use
**Priority**: Low
**Description**: Deferred from the Feb 2026 audit (see CB-030 in resolved). Once Prowl hunts exist, add labels and focus order checks to the menu, settings, and host panel so hunts can drive the UI by accessibility identifiers rather than text.

### CB-054: Adopt NSHostingView.sizingOptions in AutoResizingHostingView
**Priority**: Low
**Description**: Carried over from the CB-044 audit note and reaffirmed in CB-046. `AutoResizingHostingView` (`Sources/ContainerBar/Views/Components/AutoResizingHostingView.swift`) hand-rolls menu-item sizing via `layout()` + `menu.update()`; modern `NSHostingView.sizingOptions` (`.intrinsicContentSize`) can drive this natively. Works today and is covered by the Prowl `settings-window` guard, so this is a deliberate rework rather than a bug fix: change it behind the existing Prowl hunts and verify menu/popover sizing is unchanged before merging.

### CB-056: SwiftUI view-testing harness for the Dashboard and Settings view layer
**Priority**: Low
**Description**: Filed from the CB-047 coverage audit. The entire `Sources/ContainerBar/Views/**` tree sits at 0% line coverage (dozens of files: `DashboardMenuView`, `ContainerCardView`, `HostPanelView`, `ConnectionSettingsPane`, `SectionsSettingsPane`, `AddHostSheet`, `LogViewerWindow`, the metric gauges/bars, etc.), which is what drags the app target to 8.3% line coverage overall even though the logic layer (`Stores/`, 82% line) is well covered. There is no way to assert on view bodies today. Decide on and wire up a view-testing approach — ViewInspector for structural/state assertions, or snapshot testing for render regressions — starting with the pure presentation helpers (`ConnectionStatusPresentation`, `MetricsRateTracker`, `ContainerGroupView` grouping logic) that already have testable inputs, then the Settings panes. This is an infrastructure decision, not a matter of writing more assertions against the current untestable views; the Prowl hunts (CB-042) cover end-to-end launch smoke but not per-view logic. Pair with CB-052 (accessibility) since both touch the view layer.

### CB-057: FixtureDockerAPIClient resolves reads by id-prefix but mutations only by exact id/name
**Priority**: Low
**Description**: Found during the CB-047 audit and pinned down by a test (`FixtureDockerAPIClientEdgeTests.mutationsDoNotResolveByPrefix`). In `Sources/ContainerBarCore/Services/FixtureDockerAPIClient.swift`, `find()` (used by `getContainer`/`getContainerStats`/`getContainerLogs`) matches an id by exact id, id *prefix*, or name, while `transition()` (start/stop/restart) and `removeContainer()` match only exact id or name — no prefix. So `getContainer(id: "a1f0")` succeeds but `stopContainer(id: "a1f0")` throws `notFound`. Not a production bug today because the app's `ContainerStore` actions always pass the full container id, and this is a QA-only fixture; but the asymmetry is a latent footgun for any future caller (or hunt) that addresses containers by short id. Low-priority cleanup: route both mutation paths through the same `find()`-style resolver so read and write addressing modes are identical. Behavior is currently documented by the test, so any change must update that expectation.

### CB-058: Automate the console-side smoke launch on the Mac mini
**Priority**: Low
**Description**: Filed during CB-048. `scripts/smoke-launch-mini.sh` verifies the distributed zip's codesign/Gatekeeper/staple over SSH, but the actual menu-bar app launch cannot be automated over a plain SSH connection (no window server; GUI automation over SSH is a standing no-go on the mini). Today the helper only launches when a GUI session happens to be present and otherwise prints a manual `open -a` command to run from the mini's console. Follow-up: wire the real launch into a console session on the mini — e.g. drive it through the existing Prowl QA runner (which already holds an Accessibility grant and a console/launchd context) against the notarized artifact, so the clean-machine smoke launch is fully automated at release time rather than a documented manual step. Coordinates with the CB-042 Prowl QA setup.
