---
  type: agent
---

# ContainerBar Project - Master Agent Coordinator

**Version**: 2.1  
**Project**: ContainerBar - macOS Menu Bar Docker/Podman Monitor  
**Last Updated**: February 12, 2026

---

## Mission

Build and maintain a production-ready macOS menu bar app for container monitoring and management with a native UX, strong security defaults, and reliable release operations.

## Current Project State

ContainerBar is no longer in initial scaffolding. This repo is in active product/release mode.

- Architecture is implemented across `ContainerBar` (app) and `ContainerBarCore` (library)
- Shipping features include local Unix socket + remote SSH tunnel connectivity
- Sparkle update and release automation scripts are present
- Current stable release baseline: `2.0.0` (build `3`)
- `CHANGELOG.md` shows public releases through `2.0.0`
- Test suite is active via `swift test`

## Canonical References

Read these first before making decisions:

1. `AGENTS.md` (this file)
2. `CLAUDE.md` (project snapshot and release metadata)
3. `.claude/agents/DESIGN_DOCUMENT.md` (architecture and technical intent)
4. `.claude/agents/PROJECT_ORCHESTRATION.md` (orchestration conventions)
5. Role-specific files in `.claude/agents/*.md`

---

## Technical Baseline

- Language: Swift 6.0+
- UI: SwiftUI + AppKit hybrid
- Platforms: macOS 14+
- Targets:
  - `ContainerBar` (executable app)
  - `ContainerBarCore` (business logic library)
- Core flow:
  - UI -> `ContainerStore` (`@Observable`) -> `ContainerFetcher` (actor) -> `DockerAPIClient` (protocol) -> Unix socket / SSH tunnel -> Docker/Podman
- Dependencies:
  - `swift-log`
  - `KeyboardShortcuts`
  - `Sparkle`

---

## Repository Structure

- `Sources/ContainerBar/` - app UI, controllers, stores, services
- `Sources/ContainerBarCore/` - models, API, services, strategies
- `Tests/ContainerBarTests/` - app-level tests
- `Tests/ContainerBarCoreTests/` - core/business logic tests
- `Distribution/` - Info.plist, entitlements, app assets
- `scripts/` - build/notarize/DMG/appcast/validation automation
- `docs/` - user docs + appcast output
- `.claude/agents/` - agent role docs and communications

---

## Agent Team & Authority

### Roles

- `BUILD_LEAD`: Implementation ownership, architecture and delivery decisions
- `SWIFT_EXPERT`: Swift 6 concurrency, SwiftUI/AppKit correctness
- `API_INTEGRATION`: Docker/Podman transport, request/response behavior
- `UI_UX`: UX quality, macOS HIG, accessibility
- `SECURITY_COMPLIANCE`: Security decisions, credential handling, hardening (**veto power**)
- `TEST_AGENT`: Test strategy, regression gates
- `REVIEW_AGENT`: Code quality and maintainability
- `DOC_AGENT`: Documentation and release notes quality

### Decision Protocol

1. BUILD_LEAD makes day-to-day technical decisions.
2. SECURITY_COMPLIANCE can veto insecure approaches.
3. TEST_AGENT/REVIEW_AGENT can block completion if quality gates fail.
4. Disputes are documented in `.claude/agents/communications/open-questions.md`.

---

## Communication Protocol

Use `.claude/agents/communications/`:

- `daily-standup.md` - work log and current status
- `decisions.md` - architectural or process decisions
- `open-questions.md` - unresolved tradeoffs/blockers

If needed for a task, create additional logs in this folder (for example `security-reviews.md` or `ui-feedback.md`) rather than blocking on missing files.

---

## Quality Gates (Definition of Done)

1. Implementation correctness
- Feature/bugfix behaves as intended
- No obvious regressions in related behavior

2. Build and test health
- `swift build` succeeds
- `swift test` succeeds
- New warnings are understood and intentional

3. Security review (required for networking/credentials/actions)
- No credential leakage in logs/errors
- Input validation and safe failure modes are present
- Host trust and transport assumptions are explicit

4. Documentation
- User-facing behavior changes are reflected in docs when applicable
- Release-impacting changes update `CHANGELOG.md`

---

## Coding Standards (Active)

- Swift 6 strict concurrency by default
- UI state on `@MainActor`; background work in actors/tasks
- Prefer protocol abstractions at API boundaries
- Keep responsibilities narrow and code readable
- Keep files reasonably small (target: under ~300 lines unless justified)
- Comments explain intent/why, not obvious mechanics
- Do not hard-code values when they can be sourced dynamically from configuration, metadata, environment, or system APIs

---

## Current Capability Notes

- Implemented: local Unix socket + SSH tunnel support
- Implemented: dashboard UI, container actions, logs viewer, host management
- Implemented: release scripts, notarization script, appcast generation scripts
- Not fully implemented: direct TCP+TLS client path is still a planned capability

---

## Release Configuration (from CLAUDE.md)

- Release branch: `main`
- Version source: `Distribution/Info.plist`
- Version keys:
  - `CFBundleShortVersionString`
  - `CFBundleVersion`
- Changelog file: `CHANGELOG.md`
- Build script: `./scripts/build-release.sh`
- Notarize script: `./scripts/notarize.sh`
- Artifacts:
  - `dist/ContainerBar.zip`
  - `dist/ContainerBar.dmg`
- Tag format: `v{VERSION}`
- GitHub repo: `michaeltookes/ContainerBar`
- Appcast script: `./scripts/generate-appcast.sh {VERSION}`
- Appcast URL: `https://michaeltookes.github.io/ContainerBar/appcast.xml`
- Appcast file: `docs/appcast.xml`
- Validation script: `./scripts/validate-release.py`

### Current Release Baseline

- Latest released version: `2.0.0`
- Release date: `2025-02-11`
- Current bundle build number: `3`

---

## Working Agreement

All agents commit to:

1. Read current docs before making non-trivial changes.
2. Prefer the safest simple solution over speculative complexity.
3. Preserve existing user-visible behavior unless change is explicit.
4. Never trade away security for convenience.
5. Test changes and document material decisions.
