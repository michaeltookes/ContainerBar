# ContainerBar Backlog

Prioritized list of planned features, improvements, and technical debt for ContainerBar - macOS menu bar Docker/Podman monitoring app.

Item ids are stable `CB-NNN` numbers and are never reused. Completed items move to [`docs/resolved.md`](resolved.md).

## Low Priority

### CB-058: Automate the console-side smoke launch on the Mac mini
**Priority**: Low
**Description**: Filed during CB-048. `scripts/smoke-launch-mini.sh` verifies the distributed zip's codesign/Gatekeeper/staple over SSH, but the actual menu-bar app launch cannot be automated over a plain SSH connection (no window server; GUI automation over SSH is a standing no-go on the mini). Today the helper only launches when a GUI session happens to be present and otherwise prints a manual `open -a` command to run from the mini's console. Follow-up: wire the real launch into a console session on the mini — e.g. drive it through the existing Prowl QA runner (which already holds an Accessibility grant and a console/launchd context) against the notarized artifact, so the clean-machine smoke launch is fully automated at release time rather than a documented manual step. Coordinates with the CB-042 Prowl QA setup.

### CB-060: View-body testing tool decision + Settings-pane coverage (follow-up to CB-056)
**Priority**: Low
**Description**: Split out from CB-056, which delivered only its pure-presentation-helper phase (branch `view-testing-harness`). The pure helpers that already have testable inputs — `ConnectionStatusPresentation` (`make` decision table + indicator colors), `MetricsRateTracker` (delta-based rate math), and `ContainerGroup`/`ContainerListSection.groupContainers` (the grouping transform, lifted to an internal static for testability) — are now unit-tested with plain Swift Testing and **no new dependency**. What remains open is the part that genuinely needs a view-body introspection tool: the `Sources/ContainerBar/Views/**` tree is still at ~0% line coverage, and asserting on view bodies (the Settings panes — `ConnectionSettingsPane`, `SectionsSettingsPane`, `GeneralSettingsPane`, `AboutPane`, `AddHostSheet` — plus the Dashboard cards/gauges) requires either ViewInspector (structural/state assertions) or a snapshot-testing library (render regressions). **Adding either is a third-party test dependency to this public repo and is an explicit owner decision that has not been made** — that is why it was deliberately deferred rather than picked here. Next step: the owner chooses ViewInspector vs snapshot testing (and accepts the added `Package.swift` dependency + `Package.resolved` churn + CI cost), then that tool is wired up starting with the Settings panes. Pair with CB-052 (accessibility) since both touch the view layer.
