# ContainerBar Backlog

Prioritized list of planned features, improvements, and technical debt for ContainerBar - macOS menu bar Docker/Podman monitoring app.

Item ids are stable `CB-NNN` numbers and are never reused. Completed items move to [`docs/resolved.md`](resolved.md).

## High Priority

### CB-044: Swift 6.2 / macOS 26 compatibility audit
**Priority**: High
**Description**: The project was written against Swift 6.0 and macOS 14 SDK with Opus 4.5 in early 2026; the toolchain is now Xcode 26.2 / Swift 6.2.3 on macOS 26.5. Build with `-warnings-as-errors` once to surface deprecations, review every `@unchecked Sendable`, `nonisolated(unsafe)`, and `MainActor.assumeIsolated` for correctness under Swift 6.2's stricter inference, check the SwiftUI-in-NSMenu hosting path and `NSHostingController` sizing against macOS 26's Liquid Glass menu changes, and verify `SMAppService`, `KeyboardShortcuts`, and Sparkle behave on macOS 26. Fix or file follow-up items for anything found.

## Medium Priority

### CB-046: Full code-quality pass across both targets
**Priority**: Medium
**Description**: Review every file in `Sources/ContainerBar` and `Sources/ContainerBarCore` for dead code, files over 300 lines, hardcoded values that should be read dynamically, duplicated logic between the SSH, TLS, and Unix socket transports, error handling that swallows failures, and logging noise. Run `/simplify` and `/code-review` on the result. File individual items for anything that needs design work rather than a local fix.

### CB-047: Test coverage audit
**Priority**: Medium
**Description**: Inventory what `Tests/` covers versus the surface area in `ContainerBarCore` (API client, transports, models, parsers) and the stores in the app target. Add tests for the settings persistence path, the fixture client from CB-043, the container action router edge cases, and the appcast/version validation script. Report coverage per module and file items for gaps that need refactoring to be testable.

### CB-048: Release hygiene and distribution checks
**Priority**: Medium
**Description**: Users get the app via Homebrew cask or the GitHub release DMG/zip. Add to `validate-release.py`: Gatekeeper `spctl` acceptance of the zip's app, DMG mounts and contains the app, the cask `sha256` matches the uploaded zip, and the appcast entry's length and signature match. Document in README that the app is Apple Silicon only (the binary is arm64-only and the cask does not restrict architecture) and add `depends_on arch: :arm64` to the cask. Add a smoke launch of the built app on a machine without the repo checkout as a release step (the Mac mini can serve). Two snags from the 2.0.4 release to fix in the scripts: `notarize.sh` only builds and notarizes the DMG after an interactive y/n prompt, so a non-interactive run ships an un-notarized DMG (add a `--dmg` flag or make it the default); and `generate-appcast.sh` fails with a Sparkle duplicate-update error when both the zip and DMG are in `dist/` (point the generator at a temp dir containing only the zip). Also note `gh` must run as the `michaeltookes` account; the `prowltools` login cannot write releases to this repo.

### CB-049: Documentation refresh
**Priority**: Medium
**Description**: `docs/GETTING_STARTED.md`, README, and the `.claude/agents/*.md` files predate the 2.0.x transport rewrite, the xcodebuild release path, and the current backlog discipline. Update install instructions (Silicon-only note, Homebrew and direct download), the architecture section, the release process description, and remove stale Mission Control references.

### CB-050: CI hardening
**Priority**: Medium
**Description**: Make `Swift CI` and `Prowl QA` required status checks on `main`, add `timeout-minutes` to every job, pin third-party actions to commit SHAs, add a PR template and issue templates modeled on sentwise, and add the portable `claude-pr-description.yml` workflow.

## Low Priority

### CB-051: Universal binary or explicit Intel decision
**Priority**: Low
**Description**: Decision recorded 2026-09-11: Apple Silicon only. Revisit only if Intel users ask. If revisited, xcodebuild with `ARCHS="arm64 x86_64"` produces a universal binary from the same release script.

### CB-052: Accessibility pass for VoiceOver and keyboard-only use
**Priority**: Low
**Description**: Deferred from the Feb 2026 audit (see CB-030 in resolved). Once Prowl hunts exist, add labels and focus order checks to the menu, settings, and host panel so hunts can drive the UI by accessibility identifiers rather than text.
