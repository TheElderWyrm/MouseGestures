# Changelog

All notable user-facing changes to MouseGestures are documented here, in
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) style. Version numbers
follow the app's `MARKETING_VERSION` (`Info.plist` / Xcode project settings).

For the full engineering history (every internal refactor, bugfix, and
plugin-architecture change), see `MouseGestures_changelog.txt` at the repo
root — this file is the curated, user-facing subset of that log.

## [Unreleased]

Nothing queued yet.

## [1.0.0] — 2026-07-20

Initial release. MouseGestures is a macOS menu-bar utility that maps mouse
gestures — plus keyboard and mouse-button triggers — to system, window, media,
and automation actions.

### Added

- **Gesture detection** from 8 screen corners/edges, combinable with modifier
  keys (⌘ ⌥ ⌃ ⇧) and mouse buttons, with click *or* drag activation.
- **Core actions** — close/minimize/fullscreen/hide/quit windows, Mission
  Control, Show Desktop, App Exposé, cycle windows/spaces, lock screen, sleep
  display, empty trash, switch profile.
- **Window management** — snap to one of 11 screen regions, resize by percent
  or pixels, tile, cascade, save/restore window position and named layouts.
- **Media & system control** — playback, volume, display/keyboard brightness,
  dark mode, Do Not Disturb, screenshots, restart/shutdown/logout.
- **Automation actions** — run Shortcuts, AppleScript/shell/JS/Python scripts,
  open an app/file/URL, clipboard actions, keyboard-shortcut synthesis.
- **Bundles** — sequence or parallelize actions, conditional (if/else) logic,
  repeat, and timed delays, so one gesture can drive a multi-step routine.
- **App-specific profiles** — gesture sets switch automatically with the
  frontmost application; multiple profiles for Pro, one for Free.
- **Plugin architecture** — Detection, Action, UI, and Service plugins share a
  single registration path; built-in capabilities are ordinary plugins, and
  external `.plugin`/`.bundle` files can be installed the same way.
- **Guided onboarding** — an interactive tour that opens Settings, highlights
  relevant controls, and walks through creating a first gesture.
- **Licensing** — a 30-day full-feature trial, then Free (single profile, core
  actions) or Pro (multi-profile, advanced actions), unlocked with an offline,
  HMAC-validated license key. No account, no StoreKit/App Store dependency.
- **Auto-update check** — polls a public `version.json` for new releases.

### Distribution notes

- Built for **macOS 13.0+**, Apple silicon (arm64).
- Signed with a **Developer ID Application** certificate (team `2RZ7SBH74J`)
  and hardened-runtime enabled. **Notarization is pending** a credential — see
  `README.md` → Deployment and `DEPLOYMENT.md` for current status and the
  release runbook. Until a notarized build is posted, installers must
  right-click → Open (or clear the quarantine attribute) on first launch.
- Requires the **Accessibility** and **Automation/Apple Events** permissions
  at first run for gesture detection and system actions to work.
