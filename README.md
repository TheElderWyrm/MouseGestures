# MouseGestures

A macOS menu-bar utility for mapping mouse gestures (and keyboard / mouse-button
triggers) to system, window, media, and automation actions. It runs as a
background agent (`LSUIElement`) with no Dock icon; all configuration happens in
its Settings window.

The app has a Free/Pro model: a Pro trial gates advanced actions and
multi-profile use, backed by `LicenseService` (trial/license state). Pro is
unlocked with an offline, HMAC-validated license key (`LicenseKey` /
`LicenseLogic`) — no in-app-purchase / StoreKit dependency.

> **Status:** the source tree compiles clean, builds/tests/lints green, and is
> configured for direct distribution (real bundle ID, hardened runtime,
> entitlements, `developer-id` export). A **verified unsigned DMG** can be
> produced today; the only thing blocking a shippable release is the Apple
> Developer ID cert + notarization credentials. See [Deployment](#deployment).

## Requirements

- **macOS 13.0+** (deployment target; Apple silicon / arm64).
- **Xcode 16 or newer.** Verified building on **Xcode 26.6 / Swift 6.3.3**.
- No third-party package dependencies — the app builds from the checked-in
  sources only (system frameworks: SwiftUI, AppKit/Cocoa, Carbon, Accessibility,
  UserNotifications).

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

Expected result: `** TEST SUCCEEDED **` (30 tests, 0 failures). The suite covers
the dependency-free licensing/trial rules (`LicenseLogic`), the offline
license-key validation (`LicenseKey`), screen-zone math, and `AnyCodable`
round-tripping — logic that needs no running app.

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
`LicenseService`; Pro is unlocked by an offline, HMAC-validated license key
(`LicenseKey` / `LicenseLogic`) — no StoreKit / in-app purchases.

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
  Services/                     LicenseService, LicenseKey/LicenseLogic, UpdateService, etc.
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

**Distribution model:** direct distribution — a Developer-ID-signed, notarized
**DMG** (decided 2026-07-13). The StoreKit 2 in-app-purchase Pro path is being
replaced with an offline license mechanism (StoreKit IAP only works for
Mac-App-Store apps); that refactor is the last fork-driven code task.

**Config status:** bundle id (`com.mousegestures.MouseGestures`), publishing team
(`2RZ7SBH74J` — the paid Developer Program team), hardened runtime (Release), the
entitlements file, and the `Developer ID Application` certificate are all in
place. A signed, hardened, notarization-ready DMG builds today
(`./scripts/package_dmg.sh --identity "Developer ID Application: … (2RZ7SBH74J)"`).
The only remaining gap to a shippable release is a **notarization credential**
(App Store Connect API key or Apple-ID app-specific password); notarize + staple
is already wired in CI and in the packaging script.

### Package an (unsigned) DMG locally

```sh
./scripts/package_dmg.sh
# -> dist/MouseGestures-<version>-unsigned.dmg
```

This produces a real, installable disk image today. It is **unsigned and
un-notarized**, so Gatekeeper blocks it on other machines (right-click → Open, or
strip the quarantine attribute, to run it elsewhere) — it's for local
verification, not end-user distribution. The signed + notarized release DMG is cut
by CI on a version tag.

**The full release runbook — signing config, the required GitHub Actions secrets,
notarization, and how to cut a release — is in [`DEPLOYMENT.md`](DEPLOYMENT.md).**
Current deployment status and history are tracked in
[`PROJECT_NOTES.md`](PROJECT_NOTES.md).
