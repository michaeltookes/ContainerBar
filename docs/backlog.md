# ContainerBar Backlog

Prioritized list of planned features, improvements, and technical debt for ContainerBar - macOS menu bar Docker/Podman monitoring app.

Item ids are stable `CB-NNN` numbers and are never reused. Completed items move to [`docs/resolved.md`](resolved.md).

## Low Priority

### CB-058: Automate the console-side smoke launch on the Mac mini
**Priority**: Low
**Description**: Filed during CB-048. `scripts/smoke-launch-mini.sh` verifies the distributed zip's codesign/Gatekeeper/staple over SSH, but the actual menu-bar app launch cannot be automated over a plain SSH connection (no window server; GUI automation over SSH is a standing no-go on the mini). Today the helper only launches when a GUI session happens to be present and otherwise prints a manual `open -a` command to run from the mini's console. Follow-up: wire the real launch into a console session on the mini — e.g. drive it through the existing Prowl QA runner (which already holds an Accessibility grant and a console/launchd context) against the notarized artifact, so the clean-machine smoke launch is fully automated at release time rather than a documented manual step. Coordinates with the CB-042 Prowl QA setup.
