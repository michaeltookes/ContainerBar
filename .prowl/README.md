# Prowl hunts for ContainerBar (macOS target)

End-to-end QA hunts that drive the real ContainerBar menu bar app through macOS
Accessibility using Prowl's `macos` target. They run as a pull-request gate on
the self-hosted Mac mini runner (`.github/workflows/prowl-qa.yml`) and can be
run locally.

## Hunt mode

`scripts/build-hunt-app.sh` builds a Debug bundle at
`.prowl/DerivedData/Build/Products/Debug/ContainerBar.app`. Prowl launches that
fresh bundle path directly while the bundle is also registered as
`com.tookes.ContainerBar.hunt`. The path switches the app into hunt mode
(`Sources/ContainerBar/Services/HuntMode.swift`):

- `FixtureDockerAPIClient` serves six fixed containers from memory. No socket,
  SSH tunnel, or TLS connection is ever opened.
- Preferences live in the `com.tookes.ContainerBar.hunt.defaults` defaults
  suite, wiped on every launch. The user's real hosts, sections, and keychain
  items are never read or written.
- The only host is "Fixture Docker". Sparkle, login-item status reads, and
  global hotkey registration are skipped so Prowl can attach to a quiet
  menu-bar process.
- The bundle identifier is rewritten to `com.tookes.ContainerBar.hunt` during
  assembly and re-registered with Launch Services so Prowl cannot activate an
  installed production app.

Hunt mode can also be forced with `CONTAINERBAR_HUNT_MODE=1`, and
`CONTAINERBAR_OPEN_SETTINGS_ON_LAUNCH=1` opens Settings immediately for
headless checks.

## One-time local setup

1. **CLI**: clone `prowl-tools/prowl` at the tag pinned in the workflow, then
   `npm install && npm run build && npm link`.
2. **Helper**: in that clone, `cd macdriver && swift build -c release`. Set
   `PROWL_MACDRIVER_BIN` if the CLI cannot find it.
3. **Permissions** (System Settings → Privacy & Security), granted to the
   terminal you run `prowl` from: **Accessibility** (required) and **Screen
   Recording** (failure screenshots only).
4. **Build the app under test**: `./scripts/build-hunt-app.sh`.

## Running

```bash
prowl list
prowl run menu-smoke            # status-item menu opens; header controls render
prowl run settings-window       # CB-041 guard: Settings opens, General pane renders
prowl run settings-window-tabs  # every Settings tab renders; fixture host listed
prowl run settings-add-host-sheet # Add Host sheet opens, cancels, and reopens
prowl ci --junit                # full suite, as CI runs it
```

Artifacts land in `.prowl/runs/` (gitignored). In CI the workflow deletes
every `screenshots/` folder before uploading, on purpose: this repo is public,
run artifacts are downloadable by any logged-in GitHub user, and the macOS
target captures the runner's whole screen whenever the app has no frontmost
window. Do not upload screenshots without a dedicated QA login on the runner.

## Selector dialect

- `statusItem` — press the app's menu bar status item (leaves the menu open)
- `id=<axIdentifier>` — accessibility identifier; the header buttons expose
  `openSettings`, `refreshContainers`, `toggleSearch`, `quitApp`; the settings
  window exposes `settingsWindow`; pane contents expose
  `refreshIntervalPicker`, `sectionsIntro`,
  `hostRow-<name-slug>-<host-uuid>` in the host list (for example
  `hostRow-fixture-docker-f1a7e000-0000-4000-8000-000000000001`),
  `openAddHostSheet`, `addHostSheet`, `cancelAddHost`,
  `host-<name-slug>-<host-uuid>` in the host detail form,
  `containerCard-<name-slug>` in the dashboard, and `aboutVersion`
- `label="…"` — exact accessibility label, **click steps only**. Assertions
  are rewritten to `text=` internally, which `config.yml` forbids, so every
  `assert` must use `id=`. Settings toolbar tabs are native `NSToolbarItem`s,
  and sheet action buttons may expose labels more reliably than identifiers, so
  they are clicked by label (`General`, `Sections`, `Connections`, `About`,
  `Cancel`)
- `menu=` and `text=` are forbidden by `config.yml`

Step kinds: `click`, `assert` (`visible:`), `waitForSelector` (`selector`,
`timeout`), `fill`, `scrollTo`.

## Writing hunts

Hunts are open-and-assert. `config.yml` forbids selectors that would start,
stop, restart, or remove containers, save or remove hosts, toggle login items
or update checks, record shortcuts, or quit the app. Opening and canceling the
Add Host sheet is allowed; the sheet hunt reopens it after canceling to prove
the first sheet dismissed. Add a new identifier to the view for assertions
rather than matching on visible text.

## Runner requirements (Mac mini)

- macOS with Xcode; a logged-in GUI session
- **Accessibility** granted to the process hosting the runner agent, plus
  **Screen Recording** for failure screenshots
- Registered with labels `self-hosted, macOS`; one runner directory per repo
