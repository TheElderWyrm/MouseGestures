# Changelog

All notable user-facing changes to MouseGestures are documented here, in
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) style. Version numbers
follow the app's `MARKETING_VERSION` (`Info.plist` / Xcode project settings).

For the full engineering history (every internal refactor, bugfix, and
plugin-architecture change), see `MouseGestures_changelog.txt` at the repo
root — this file is the curated, user-facing subset of that log.

## [Unreleased]

### Added

- **Report an Issue** — a built-in way to file a bug without a GitHub account,
  from the menu bar (*Report an Issue...*) or Settings ▸ About ▸ Support & Help.
  Describe the problem, review the *exact* text that will be sent, then open a
  prefilled email to support@mousegestures.app, copy it, or save it to a file.
  The attached diagnostics cover app version and build, macOS version, Mac model
  and architecture, Accessibility permission, license state (Free/Trial/Pro —
  never the key itself), the active profile, gesture and profile counts, enabled
  plugins, and a bounded tail of the app's own log. Your home folder path, user
  name, license keys, email addresses and anything key-shaped are stripped out
  before you ever see the report.

### Changed

- **New app icon**, built from the same swoosh-and-cursor mark the website uses,
  so the app, the site and the installer now share one identity.

### Fixed

- MouseGestures no longer leaves empty placeholder windows in **Mission
  Control**. The app parks one hidden window on each desktop Space so it can
  switch to any Space instantly; those windows were being laid out as blank
  tiles alongside your real ones. They are now hidden from Mission Control and
  Exposé except for the moment a Space switch actually needs them.
- Those hidden windows also accumulated over time — entering and leaving
  full screen created a new Space each time, and the old ones were never
  cleaned up. They are now cleared whenever a Space goes away. As a side
  effect, "switch to Space N" could occasionally jump to the *wrong* Space
  after a Space had been closed; it now falls back to the standard switch
  instead.

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
