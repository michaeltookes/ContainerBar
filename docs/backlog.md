# ContainerBar Backlog

Prioritized list of planned features, improvements, and technical debt for ContainerBar - macOS menu bar Docker/Podman monitoring app.

Item ids are stable `CB-NNN` numbers and are never reused. Completed items move to [`docs/resolved.md`](resolved.md).

## High Priority

### CB-041: Release build crashes on Settings open on every Mac except the build machine
**Priority**: High
**Description**: v2.0.3 was built with `swift build -c release`, whose generated `Bundle.module` accessor for the KeyboardShortcuts dependency looks for `KeyboardShortcuts_KeyboardShortcuts.bundle` at the app root and then at the absolute `.build/arm64-apple-macosx/release/...` path of the build machine, and calls `fatalError` otherwise. The release script copies the bundle to `Contents/Resources`, so only the dev-machine fallback ever resolves. The General settings pane renders `KeyboardShortcuts.Recorder`, whose first localized string triggers the crash. Same bug class was fixed for the app's own bundle in Feb 2026 (`AppResourceBundle.swift`) but not for the dependency. Fix: build releases with xcodebuild (its accessor checks `Bundle.main.resourceURL` first), and make `build-release.sh` and `validate-release.py` fail when a bundle is missing from `Contents/Resources` or the binary embeds the repo's `.build` path. Ship as 2.0.4.

### CB-042: Prowl QA pull-request gate on the Lucius Mac mini
**Priority**: High
**Description**: Mirror sentwise's `.github/workflows/prowl-qa.yml`: a `pull_request` gate on a self-hosted `[self-hosted, macOS]` runner registered for this repo on the Mac mini (`luciusfox@192.168.86.28`, already hosts runners for other repos), fork PRs excluded. Pin the Prowl version, build the app into `.prowl/DerivedData` via xcodebuild, run `prowl ci --junit`, upload `.prowl/runs/` as an artifact. Requires CB-043 so hunts never touch a real Docker host. First hunts: menu smoke (open menu, dashboard renders), settings window (open Settings, every tab renders without the app exiting), add-host sheet opens and cancels. Add `.prowl/config.yml` with `allowedApps` limited to the built app and `forbiddenSelectors` for anything that mutates containers.

### CB-043: Offline hunt mode with a fixture Docker client for QA
**Priority**: High
**Description**: Prowl hunts must not hit the Beelink SSH host or a real Unix socket. Add a hunt-mode runtime, activated only when the app runs from the `.prowl/DerivedData` build path or a `CONTAINERBAR_HUNT_MODE=1` environment variable, that injects a fixture `DockerAPIClient` implementation returning a fixed set of containers, stats, and system info, backed by an isolated `UserDefaults` suite so real settings and keychain entries are untouched. Container actions in hunt mode mutate only the in-memory fixture. This is the ContainerBar equivalent of sentwise's `ProwlHuntRuntime.swift`.

### CB-044: Swift 6.2 / macOS 26 compatibility audit
**Priority**: High
**Description**: The project was written against Swift 6.0 and macOS 14 SDK with Opus 4.5 in early 2026; the toolchain is now Xcode 26.2 / Swift 6.2.3 on macOS 26.5. Build with `-warnings-as-errors` once to surface deprecations, review every `@unchecked Sendable`, `nonisolated(unsafe)`, and `MainActor.assumeIsolated` for correctness under Swift 6.2's stricter inference, check the SwiftUI-in-NSMenu hosting path and `NSHostingController` sizing against macOS 26's Liquid Glass menu changes, and verify `SMAppService`, `KeyboardShortcuts`, and Sparkle behave on macOS 26. Fix or file follow-up items for anything found.

### CB-045: Dependency and toolchain refresh
**Priority**: High
**Description**: Bump `swift-tools-version` and `platforms` if a raise is justified, review `Package.swift` version floors (swift-log 1.5 → resolved 1.9, KeyboardShortcuts 2.0 → 2.4, Sparkle 2.6 → 2.8.1) and raise floors to the tested versions, commit `Package.resolved` (currently gitignored, so CI and local builds can drift), pin SwiftLint in CI to the current release, and update `ci.yml` to `macos-15` or later with Xcode selection pinned so the CI toolchain matches the release toolchain.

## Medium Priority

### CB-046: Full code-quality pass across both targets
**Priority**: Medium
**Description**: Review every file in `Sources/ContainerBar` and `Sources/ContainerBarCore` for dead code, files over 300 lines, hardcoded values that should be read dynamically, duplicated logic between the SSH, TLS, and Unix socket transports, error handling that swallows failures, and logging noise. Run `/simplify` and `/code-review` on the result. File individual items for anything that needs design work rather than a local fix.

### CB-047: Test coverage audit
**Priority**: Medium
**Description**: Inventory what `Tests/` covers versus the surface area in `ContainerBarCore` (API client, transports, models, parsers) and the stores in the app target. Add tests for the settings persistence path, the fixture client from CB-043, the container action router edge cases, and the appcast/version validation script. Report coverage per module and file items for gaps that need refactoring to be testable.

### CB-048: Release hygiene and distribution checks
**Priority**: Medium
**Description**: Users get the app via Homebrew cask or the GitHub release DMG/zip. Add to `validate-release.py`: Gatekeeper `spctl` acceptance of the zip's app, DMG mounts and contains the app, the cask `sha256` matches the uploaded zip, and the appcast entry's length and signature match. Document in README that the app is Apple Silicon only (the binary is arm64-only and the cask does not restrict architecture) and add `depends_on arch: :arm64` to the cask. Add a smoke launch of the built app on a machine without the repo checkout as a release step (the Mac mini can serve).

### CB-049: Documentation refresh
**Priority**: Medium
**Description**: `docs/GETTING_STARTED.md`, README, and the `.claude/agents/*.md` files predate the 2.0.x transport rewrite, the xcodebuild release path, and the in-repo backlog. Update install instructions (Silicon-only note, Homebrew and direct download), the architecture section, the release process description, and remove references to Mission Control and the old Desktop backlog path.

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
