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

### CB-058: Automate the console-side smoke launch on the Mac mini
**Priority**: Low
**Description**: Filed during CB-048. `scripts/smoke-launch-mini.sh` verifies the distributed zip's codesign/Gatekeeper/staple over SSH, but the actual menu-bar app launch cannot be automated over a plain SSH connection (no window server; GUI automation over SSH is a standing no-go on the mini). Today the helper only launches when a GUI session happens to be present and otherwise prints a manual `open -a` command to run from the mini's console. Follow-up: wire the real launch into a console session on the mini — e.g. drive it through the existing Prowl QA runner (which already holds an Accessibility grant and a console/launchd context) against the notarized artifact, so the clean-machine smoke launch is fully automated at release time rather than a documented manual step. Coordinates with the CB-042 Prowl QA setup.

### CB-060: View-body testing tool decision + Settings-pane coverage (follow-up to CB-056)
**Priority**: Low
**Description**: Split out from CB-056, which delivered only its pure-presentation-helper phase (branch `view-testing-harness`). The pure helpers that already have testable inputs — `ConnectionStatusPresentation` (`make` decision table + indicator colors), `MetricsRateTracker` (delta-based rate math), and `ContainerGroup`/`ContainerListSection.groupContainers` (the grouping transform, lifted to an internal static for testability) — are now unit-tested with plain Swift Testing and **no new dependency**. What remains open is the part that genuinely needs a view-body introspection tool: the `Sources/ContainerBar/Views/**` tree is still at ~0% line coverage, and asserting on view bodies (the Settings panes — `ConnectionSettingsPane`, `SectionsSettingsPane`, `GeneralSettingsPane`, `AboutPane`, `AddHostSheet` — plus the Dashboard cards/gauges) requires either ViewInspector (structural/state assertions) or a snapshot-testing library (render regressions). **Adding either is a third-party test dependency to this public repo and is an explicit owner decision that has not been made** — that is why it was deliberately deferred rather than picked here. Next step: the owner chooses ViewInspector vs snapshot testing (and accepts the added `Package.swift` dependency + `Package.resolved` churn + CI cost), then that tool is wired up starting with the Settings panes. Pair with CB-052 (accessibility) since both touch the view layer.
