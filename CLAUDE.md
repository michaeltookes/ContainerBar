# ContainerBar

macOS menu bar app for Docker & Podman container monitoring and management. Built with Swift 6.0, SwiftUI + AppKit hybrid, targeting macOS 14+ (Sonoma). Two targets: `ContainerBar` (app) and `ContainerBarCore` (library).

## Build & Test

```bash
swift build              # development build
swift build -c release   # release build
swift test               # run test suite
./scripts/build-release.sh   # full release build with signing
```

## Project Structure

- `Sources/ContainerBar/` — macOS app (views, stores, controllers)
- `Sources/ContainerBarCore/` — business logic library (API, models, services)
- `Distribution/` — Info.plist, entitlements, app icon
- `scripts/` — build, notarize, DMG, appcast scripts
- `docs/` — user guide, appcast.xml (GitHub Pages)

## Architecture

UI (SwiftUI/AppKit) -> ContainerStore (@Observable) -> ContainerFetcher (actor) -> DockerAPIClient (protocol) -> UnixSocket/SSHTunnel -> Docker/Podman

## Key Conventions

- Swift 6 strict concurrency: `@MainActor` for UI, actors for services
- `@Observable` pattern for state stores
- Protocol-based abstractions for API clients
- NSHostingView for embedding SwiftUI in AppKit menus
- Keep files under 300 lines

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
| Notarize script | `./scripts/notarize.sh` |
| Release artifacts | `dist/ContainerBar.zip`, `dist/ContainerBar.dmg` |
| Tag format | `v{VERSION}` |
| Asset naming | `ContainerBar.zip` (no version in filename) |
| GitHub repo | `michaeltookes/ContainerBar` |
| Sparkle appcast script | `./scripts/generate-appcast.sh {VERSION}` |
| Sparkle appcast URL | `https://michaeltookes.github.io/ContainerBar/appcast.xml` |
| Sparkle appcast file | `docs/appcast.xml` |
| Homebrew cask file | `containerbar.rb` (in homebrew-tap repo) |
| Homebrew tap location | `~/Desktop/homebrew-tap/` |
| Homebrew cask URL template | `https://github.com/michaeltookes/ContainerBar/releases/download/v{VERSION}/ContainerBar.zip` |
| Notarization keychain profile | `ContainerBar-Notarize` |
| Validation script | `./scripts/validate-release.py` |
