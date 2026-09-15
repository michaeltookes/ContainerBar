# Releasing ContainerBar

This is the repo-specific release runbook. The step-by-step orchestration lives
in the `/release-prep` skill; all project-specific paths, scripts, and formats
come from the **Release Configuration** table in [`CLAUDE.md`](../CLAUDE.md).
This document records the details that skill defers to the project: the
Apple Silicon constraint, the two script fixes from the 2.0.4 release, the
`gh` account requirement, and the clean-machine smoke launch.

## Distribution facts

- **Apple Silicon only.** The app ships as an arm64-only binary. Intel Macs are
  not supported. The Homebrew cask enforces this with `depends_on arch: :arm64`
  (that cask edit lives in the separate `homebrew-tap` repo). `validate-release.py`
  asserts the cask carries that line.
- Users install via the Homebrew cask or the GitHub release `ContainerBar.zip` /
  `ContainerBar.dmg`. Both artifacts are signed, notarized, and stapled.

## `gh` must run as the `michaeltookes` account

Release uploads to this repo must be authenticated as **`michaeltookes`**. The
`prowltools` login does not have write access to publish releases here. Before
any `gh release create` / `gh release upload` step, export a token scoped to the
right account:

```bash
export GH_TOKEN="$(gh auth token -u michaeltookes)"
```

If a release step fails with a 403 / permission error, this is the first thing
to check.

## Notarizing the DMG (non-interactive safe)

`scripts/notarize.sh` notarizes the zip, then handles the DMG:

- `--dmg` — always build, sign, notarize, and staple the DMG (no prompt).
- `--no-dmg` — skip the DMG.
- default — an interactive terminal still gets the legacy y/n prompt; a
  **non-interactive** run (`/release-prep`, CI) builds and notarizes the DMG by
  default. This closes the 2.0.4 snag where a headless run shipped an
  un-notarized DMG.

For a scripted release, prefer `./scripts/notarize.sh --dmg`.

## Generating the Sparkle appcast with both artifacts in `dist/`

`scripts/generate-appcast.sh` stages **only the zip** in a temp dir before
running Sparkle's `generate_appcast`, then merges the result back into
`docs/appcast.xml`. This avoids the duplicate-update error `generate_appcast`
raises when it sees both `ContainerBar.zip` and `ContainerBar.dmg` (two archives
for one version) in `dist/`. Both artifacts can therefore coexist in `dist/` for
the GitHub release.

## Post-release validation

Run the validator with the released version:

```bash
python3 scripts/validate-release.py X.Y.Z
```

Alongside the version/tag/changelog checks it now verifies the distribution
artifacts:

- Gatekeeper accepts the app extracted from the uploaded GitHub release
  `ContainerBar.zip` (`spctl --assess --type execute`).
- The uploaded GitHub release `ContainerBar.dmg` mounts and contains
  `ContainerBar.app`, and that mounted bundle has the release version, passes
  strict codesign verification, and passes Gatekeeper.
- The published Homebrew cask version and `sha256` match the GitHub release.
- The published Homebrew cask declares `depends_on arch: :arm64`.
- The deployed appcast entry for the release has the canonical GitHub release
  zip enclosure URL, a `sparkle:edSignature` that verifies against the archive
  fetched from that URL, and a `length` attribute matching that archive's byte
  size.

Missing or unreadable uploaded release assets, published cask content, deployed
appcast metadata, or appcast enclosure archives fail because those are the
bytes users, Homebrew, and Sparkle consume.

The appcast signature check uses Sparkle's `sign_update --verify`. Set
`SPARKLE_SIGN_UPDATE` if the tool is installed somewhere other than the
standard project, Homebrew, or `~/Library/Developer/Sparkle/bin` locations.

## Clean-machine smoke launch (required release step)

Before announcing a release, smoke-launch the **distributed** build on a machine
that has no source checkout, to catch failures that only surface off the build
machine (the class of bug behind CB-041). Run the notarized artifact, not the
repo build.

The Lucius Mac mini serves as the no-checkout machine. It has `~/qa/ContainerBar`
for CI, but the smoke test must run the **distributed zip**, copied to a
throwaway location, not that checkout.

```bash
# after dist/ContainerBar.zip is notarized and stapled. The target machine is
# never hardcoded (this repo is public): pass --host or export SMOKE_HOST.
SMOKE_HOST=user@clean-machine ./scripts/smoke-launch-mini.sh --zip dist/ContainerBar.zip
```

The helper copies the zip to a temp dir on the mini, extracts it, and verifies
`codesign --verify --deep --strict`, `spctl --assess --type execute`, and
`xcrun stapler validate` against the distributed app. Because a menu-bar (Aqua)
app needs a console GUI session — and GUI automation over SSH is not supported
on the mini — the automated launch runs only when a GUI session is present. In
that case the helper fails if `open` fails or if the app is not still running
after launch, then quits it. Over plain SSH the helper prints the exact console
command to run from the mini:

```
open -a "<extracted>/ContainerBar.app"
# confirm the menu-bar icon appears, open Settings, then quit.
```

Do not skip the manual console launch: the signature/Gatekeeper/staple checks
prove the artifact is trusted, but only a real launch proves it runs.
