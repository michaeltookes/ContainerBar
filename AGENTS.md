---
  type: agent
---

# ContainerBar Project - Master Agent Coordinator

**Version**: 2.2  
**Project**: ContainerBar - macOS Menu Bar Docker/Podman Monitor  
**Last Updated**: October 14, 2026

---

## Mission

Build and maintain a production-ready macOS menu bar app for container monitoring and management with a native UX, strong security defaults, and reliable release operations.

## Current Project State

ContainerBar is no longer in initial scaffolding. This repo is in active product/release mode.

- Architecture is implemented across `ContainerBar` (app) and `ContainerBarCore` (library)
- Shipping features include local Unix socket + remote SSH tunnel connectivity
- Sparkle update and release automation scripts are present
- Current version and build: read `Distribution/Info.plist` (`CFBundleShortVersionString`, `CFBundleVersion`); release history is in `CHANGELOG.md`
- Test suite is active via `swift test`; CI also runs SwiftLint and a Prowl end-to-end QA gate

## Canonical References

Read these first before making decisions:

1. `AGENTS.md` (this file)
2. `CLAUDE.md` (project snapshot, backlog format, and release metadata)
3. `docs/backlog.md` and `docs/resolved.md` (open and completed work)
4. `docs/RELEASING.md` (release runbook)
5. `.claude/agents/DESIGN_DOCUMENT.md` (architecture and technical intent; written for the original build, so parts are historical)
6. `.claude/agents/PROJECT_ORCHESTRATION.md` (orchestration conventions; its phase plan is from the original build)
7. Role-specific files in `.claude/agents/*.md`

---

## Backlog Discipline

- Backlog location: `docs/backlog.md` (open items) and `docs/resolved.md` (completed items). Item and resolved-entry formats are in `CLAUDE.md` under "Backlog Management".
- Update cadence: update backlog **before** starting and **after** completing every feature or bug fix.
- Required backlog updates:
  - Add missing work items under the right priority tier.
  - Add newly discovered findings, risks, unknowns, and recommended next actions.
  - Move completed items to the top of `docs/resolved.md` as `## ~~CB-NNN: Title~~` with `**Resolved**: YYYY-MM-DD (branch <name>)`.
- `CB-NNN` ids are stable: never reuse or renumber them.

---

## Sensitive Context Policy

- `AGENTS.md` must contain only non-sensitive project guidance.
- Never store secrets, private endpoints, key material, or credential values in this repository.
- Keep local-only sensitive operational context in: `~/.codex/project-private/containerbar.private.md` (not committed).
- Use placeholders in committed docs/scripts when private values are required, for example `<SIGNING_IDENTITY>`.

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
- `Tests/ContainerBarTests/` - app-level tests (Swift Testing)
- `Tests/ContainerBarCoreTests/` - core/business logic tests (Swift Testing)
- `Distribution/` - Info.plist, entitlements, app assets
- `scripts/` - build/notarize/DMG/appcast/validation automation, Prowl hunt build (`build-hunt-app.sh`), clean-machine smoke launch (`smoke-launch-mini.sh`)
- `docs/` - user guide, release runbook, backlog (`backlog.md`, `resolved.md`), images, appcast output
- `.prowl/` - Prowl end-to-end hunts against a hunt-mode Debug build (see `.prowl/README.md`)
- `.github/workflows/` - Swift CI (build, test, SwiftLint), Prowl QA, Claude review workflows
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

- Implemented: local Unix socket, SSH tunnel, and direct TCP+TLS connections
- Implemented: dashboard UI, container actions, logs viewer, host management
- Implemented: release scripts, notarization script, appcast generation scripts

---

## Release Configuration

The release configuration (version file, scripts, artifacts, tag format, appcast, Homebrew cask, `gh` account) lives in the "Release Configuration" table in `CLAUDE.md`, and the step-by-step process in `docs/RELEASING.md`. The current version is whatever `Distribution/Info.plist` says; dates for each release are in `CHANGELOG.md`.

---

## Working Agreement

All agents commit to:

1. Read current docs before making non-trivial changes.
2. Prefer the safest simple solution over speculative complexity.
3. Preserve existing user-visible behavior unless change is explicit.
4. Never trade away security for convenience.
5. Test changes and document material decisions.
