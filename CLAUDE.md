# ContainerBar

macOS menu bar app for Docker & Podman container monitoring and management. Built with Swift 6.0, SwiftUI + AppKit hybrid, targeting macOS 14+ (Sonoma). Two targets: `ContainerBar` (app) and `ContainerBarCore` (library).

## Build & Test

```bash
swift build              # development build
swift build -c release   # release build
swift test               # run test suite
swiftlint lint           # lint (config: .swiftlint.yml; CI runs it)
./scripts/build-release.sh   # full release build with signing
```

## Project Structure

- `Sources/ContainerBar/` — macOS app (views, stores, controllers, services)
- `Sources/ContainerBarCore/` — business logic library (API, models, services)
- `Tests/` — unit tests (Swift Testing): `ContainerBarTests/` (app) and `ContainerBarCoreTests/` (core)
- `Distribution/` — Info.plist, entitlements, app icon
- `scripts/` — release build, DMG, notarize, appcast, release validation (`validate-release.py` + `tests/`), Prowl hunt build (`build-hunt-app.sh`), clean-machine smoke launch (`smoke-launch-mini.sh`), QA lane tooling for the agent Mini's daily pass and hourly check (`qa-lane/`, CB-105)
- `docs/` — user guide (`GETTING_STARTED.md`), release runbook (`RELEASING.md`), backlog (`backlog.md`, `resolved.md`), images, appcast.xml (GitHub Pages)
- `.prowl/` — Prowl end-to-end hunts run against a hunt-mode Debug build (see `.prowl/README.md`)
- `.github/workflows/` — Swift CI (build, test, SwiftLint), Prowl QA gate, Claude review workflows

## Architecture

UI (SwiftUI/AppKit) -> ContainerStore (@Observable) -> ContainerFetcher (actor) -> DockerAPIClient (protocol) -> UnixSocket/SSHTunnel -> Docker/Podman

## Key Conventions

- Swift 6 strict concurrency: `@MainActor` for UI, actors for services
- `@Observable` pattern for state stores
- Protocol-based abstractions for API clients
- NSHostingView for embedding SwiftUI in AppKit menus
- Keep files under 300 lines
- Never hardcode values that can be read dynamically (versions, paths, config)

## Branch Strategy

- `main` — stable, releases are tagged here
- Feature branches off main for development
- PR-based workflow

## Dependencies

- swift-log (Logging), KeyboardShortcuts, Sparkle (auto-updates)

## Release Configuration

Referenced by the `/release-prep` skill:

| Key | Value |
|-----|-------|
| Release branch | `main` |
| Version file | `Distribution/Info.plist` |
| Version keys | `CFBundleShortVersionString`, `CFBundleVersion` |
| Changelog | `CHANGELOG.md` (Keep a Changelog format) |
| Build script | `./scripts/build-release.sh` |
| Notarize script | `./scripts/notarize.sh` (use `--dmg` for non-interactive DMG notarization) |
| Release artifacts | `dist/ContainerBar.zip`, `dist/ContainerBar.dmg` |
| Tag format | `v{VERSION}` |
| Asset naming | `ContainerBar.zip` (no version in filename) |
| GitHub repo | `michaeltookes/ContainerBar` |
| Sparkle appcast script | `./scripts/generate-appcast.sh {VERSION}` |
| Sparkle appcast URL | `https://michaeltookes.github.io/ContainerBar/appcast.xml` |
| Sparkle appcast file | `docs/appcast.xml` |
| Homebrew cask file | `containerbar.rb` (in homebrew-tap repo) |
| Homebrew tap location | `"$HOME/Desktop/Current Projects/homebrew-tap/"` |
| Homebrew cask URL template | `https://github.com/michaeltookes/ContainerBar/releases/download/v{VERSION}/ContainerBar.zip` |
| Notarization keychain profile | `ContainerBar-Notarize` |
| Validation script | `./scripts/validate-release.py` |
| Release runbook | `docs/RELEASING.md` |
| Clean-machine smoke launch | `./scripts/smoke-launch-mini.sh` (run the distributed zip on a no-checkout machine) |
| Architecture | Apple Silicon only (arm64-only binary; cask uses `depends_on arch: :arm64`) |

**`gh` account requirement:** release uploads to this repo must run as the
`michaeltookes` account — the `prowltools` login cannot write releases here.
Before any `gh release` step: `export GH_TOKEN="$(gh auth token -u michaeltookes)"`.

**Clean-machine smoke launch:** after notarization, smoke-launch the distributed
build on a machine without a source checkout (see `docs/RELEASING.md`). The
Lucius Mac mini serves as that machine, running the notarized zip — not its
`~/qa/ContainerBar` checkout.

## Backlog Management

The backlog lives in the repository:

- `docs/backlog.md` — open items, grouped under `## High Priority`, `## Medium Priority`, `## Low Priority`
- `docs/resolved.md` — completed items, newest first

Update the backlog before and after every feature or bug fix. Add missing work items, findings, risks, unknowns, and recommended next actions before editing code.

Items use stable `CB-NNN` ids that are never reused or renumbered. Open item format (`docs/backlog.md`):

```
### CB-NNN: Title
**Priority**: High | Medium | Low
**Description**: what, why, and enough detail for any agent to pick it up
```

When an item is done, remove it from `docs/backlog.md` and add it at the top of `docs/resolved.md`:

```
## ~~CB-NNN: Title~~
**Resolved**: YYYY-MM-DD (branch <branch-name>)
**Description**: what was wrong and what the fix was
```

The older copy at `~/Desktop/Backlogs/projects/containerbar-backlog.md` is no longer maintained (it stops at CB-059 and still lists it as open); do not plan from it.

Both files are public. Do not put secrets, private endpoints, key material, or credential values in them.
