# MouseGestures

A macOS menu-bar utility for mapping mouse gestures (and keyboard / mouse-button
triggers) to system, window, media, and automation actions. It runs as a
background agent (`LSUIElement`) with no Dock icon; all configuration happens in
its Settings window.

The app has a Free/Pro model: a Pro trial gates advanced actions and
multi-profile use, backed by `LicenseService` (trial/license state) and
`PaymentService` (StoreKit 2 in-app purchases).

> **Status:** the source tree compiles clean, but the project is **not yet
> configured for distribution** (placeholder bundle ID, dev-only signing, an
> unresolved App-Store-vs-direct-download decision). See
> [Deployment](#deployment) before attempting a release build.

## Requirements

- **macOS 13.0+** (deployment target; Apple silicon / arm64).
- **Xcode 16 or newer.** Verified building on **Xcode 26.6 / Swift 6.3.3**.
- No third-party package dependencies — the app builds from the checked-in
  sources only (system frameworks: SwiftUI, AppKit/Cocoa, Carbon, Accessibility,
  StoreKit, UserNotifications).

## Build & run (development)

### Option A — Xcode

1. Open `MouseGestures.xcodeproj` in Xcode.
2. Select the **MouseGestures** scheme and a **My Mac** destination.
3. Press **Run** (⌘R).

Because this is a menu-bar app (`LSUIElement=true`), running it shows a **menu
bar icon**, not a window. Open the config UI from that icon, or with **⌘,**
(Settings) once the app is frontmost.

### Option B — Command line

The following builds the app unsigned (no developer certificate needed) and is
**verified to succeed** on the toolchain above:

```sh
xcodebuild build \
  -project "MouseGestures.xcodeproj" \
  -scheme MouseGestures \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  -destination 'platform=macOS'
```

Expected result: `** BUILD SUCCEEDED **`.

## Testing

The repo ships a no-host, pure-logic unit-test target (`MouseGesturesTests`)
wired into the shared scheme. Run it unsigned from the command line:

```sh
xcodebuild test \
  -project "MouseGestures.xcodeproj" \
  -scheme MouseGestures \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

Expected result: `** TEST SUCCEEDED **` (19 tests, 0 failures). The suite covers
the dependency-free licensing/trial rules (`LicenseLogic`), screen-zone math, and
`AnyCodable` round-tripping — logic that needs no running app.

## Linting

Linting uses [SwiftLint](https://github.com/realm/SwiftLint) with the config in
`.swiftlint.yml`. Pre-existing style/structure debt is grandfathered in
`.swiftlint-baseline.json`, so the lint gate fails only on **new** violations
introduced by future changes.

```sh
# install once (Homebrew), or download the pinned portable binary as CI does
brew install swiftlint

# lint against the baseline — clean today, fails only on new violations
swiftlint lint --strict --baseline .swiftlint-baseline.json
```

To fix auto-correctable issues in new code: `swiftlint --fix`. If you
deliberately pay down grandfathered debt (or intentionally accept new debt),
refresh the baseline with
`swiftlint lint --write-baseline .swiftlint-baseline.json` and rewrite its file
paths to be project-root-relative so it stays portable across checkouts (CI runs
it on a fresh clone).

## Continuous integration

`.github/workflows/ci.yml` runs on every push and pull request: it builds
unsigned, runs the test suite, and lints against the baseline — none of which
need signing credentials. Signing, notarization, and packaging live separately in
`.github/workflows/release.yml` (tag-triggered), which is **blocked** pending the
distribution decision and credentials described under **Deployment** below.

### Granting permissions (needed for gestures to actually fire)

At runtime the app requests two macOS permissions; without them gesture
detection and most actions do nothing:

- **Accessibility** — to monitor mouse/keyboard input and drive system-wide
  actions (`NSAccessibilityUsageDescription`).
- **Automation / Apple Events** — for AppleScript-based actions such as volume,
  brightness, and controlling other apps (`NSAppleEventsUsageDescription`).

Grant these under **System Settings → Privacy & Security → Accessibility /
Automation** for the built app. When you rebuild, macOS may treat the new binary
as a different app and require re-granting Accessibility access.

## What it can do (high level)

Actions are grouped by plugin (see `MouseGestures_actions.txt` for the full,
per-action list):

- **Core** — close/minimize/fullscreen/hide/quit windows, Mission Control, Show
  Desktop, App Exposé, cycle windows/spaces, lock screen, sleep display, empty
  trash, switch profile.
- **Window Management** — snap to region, resize/adjust/set size & position,
  tile, cascade, window position memory, named window layouts.
- **Media Control** — play/pause, track skip, system volume, seek.
- **System Control** — display/keyboard brightness, dark mode, Do Not Disturb,
  screenshot, restart/shutdown/logout.
- **Automation** — keyboard shortcuts, run a Shortcuts shortcut, run a
  script (AppleScript/shell/JS/Python), open app/file/URL, clipboard actions.
- **Bundle** — sequence/parallelize actions, conditional (if/else) actions,
  repeat, and timed delays.

Gestures, actions, and app-specific behavior are organized into **profiles**
(Free is limited to a single profile; Pro unlocks multiple).

## Architecture (high level)

`MouseGesturesApp` (`@main`) is a thin SwiftUI `App` whose only scene is
`Settings { TabManager() }`. The real lifecycle lives in **`AppDelegate`**
(wired via `@NSApplicationDelegateAdaptor`), which on launch sets up the
accessibility-permission manager, the menu-bar icon, and the detection pipeline.

The codebase is organized around **four cooperating plugin subsystems**, each
with its own protocol + manager. All built-in capabilities are themselves
plugins, so the same registration path is used internally and (in principle) by
future external plugins.

| Subsystem | Protocol | Manager | Responsibility |
|---|---|---|---|
| **Detection** | — | `DetectionPluginManager` | Watch mouse/keyboard/zone/button input and recognize gestures & triggers |
| **Action** | `GestureActionPlugin` | `PluginManager` (+ `PluginSandbox`) | Provide and execute the actual actions (Core, Window, Media, System, Automation, Browser, Bundle) |
| **UI** | `UIPlugin` | `UIPluginManager` | Contribute the Settings tabs (Gestures, Saved Actions, Profiles, App Profiles, Services, Developer, Settings) |
| **Service** | `ServicePlugin` | `ServicePluginManager` | Background/system services (logging, monitoring, import/export, etc.) |

**Execution flow:** `DetectionPluginManager` recognizes an input and calls back
into `AppDelegate` (as `DetectionManagerDelegate`), which routes it to
`ActionExecutionManager.shared`. That manager resolves the gesture's configured
action against the registered action plugins and runs it. Action plugins receive
a `PluginContext` exposing sandboxed system capabilities (keyboard synthesis,
AppleScript, window/accessibility access, plugin-scoped storage, profile
control).

**State & configuration:** `Configuration` (a shared singleton) holds settings
and per-plugin configuration; `ProfileManager` and the `Profiles/` services
manage gesture profiles and import/export. Free/Pro gating is centralized in
`LicenseService`, with purchases via `PaymentService` (StoreKit 2).

**Updates:** `UpdateService` implements a custom JSON update check (not Sparkle),
polling a `version.json` hosted on GitHub.

### Repository layout

```
MouseGestures.xcodeproj/        Xcode project (single MouseGestures target)
MouseGesturesCodeBase/          App source (110 Swift files)
  App/                          Entry point, AppDelegate, menu-bar icon
  Detection/                    Input detection + detection plugins
  ActionPlugins/                Action plugin protocol, manager, sandbox, built-ins
  ServicePlugins/               Service plugin protocol, manager, built-ins
  UIPlugins/                    UI (tab) plugin protocol, manager, built-ins
  UI/                           SwiftUI views, tabs, settings, styles
  Services/                     LicenseService, PaymentService, UpdateService, etc.
  Profiles/, Configuration/, Core/, Detection/, Utilities/
Website/                        Static marketing site
exportOptions.plist             Archive export config (developer-id; see Deployment)
.github/workflows/release.yml   Tag-triggered build → DMG → GitHub Release
add_remove_files_xcode.py       Helper to add/remove file refs in the .xcodeproj
MouseGestures_actions.txt       Full catalog of available actions + status
MouseGestures_changelog.txt     Detailed change history
```

To add or remove source files from the Xcode target, use the helper script
rather than editing `project.pbxproj` by hand:

```sh
python3 add_remove_files_xcode.py add    'MouseGesturesCodeBase/.../NewFile.swift'
python3 add_remove_files_xcode.py remove 'MouseGesturesCodeBase/.../OldFile.swift'
```

## Deployment

The project is **not yet release-ready**, and the current build config is **not
notarizable / not shippable as-is**. There is also an unresolved architectural
fork that must be decided before a real release:

- **StoreKit 2 in-app purchases only work for Mac-App-Store-distributed apps**,
  but `exportOptions.plist` and `.github/workflows/release.yml` are set up for a
  Developer-ID-signed, notarized **DMG on GitHub Releases**. These two
  distribution models are mutually exclusive; one must be chosen.
- Additional config blockers include a placeholder bundle ID
  (`com.example.MouseGestures`), a dev-only signing identity (`Apple Development`),
  hardened runtime disabled, a `YOUR_TEAM_ID` placeholder in
  `exportOptions.plist`, no entitlements file, and CI that cannot sign or
  notarize.

**Current deployment status, the full blocker list, and this deploy-target
decision are tracked in [`PROJECT_NOTES.md`](PROJECT_NOTES.md).** A complete
release runbook (`DEPLOYMENT.md`) will be added once the deploy target is chosen
and signing credentials are available.
