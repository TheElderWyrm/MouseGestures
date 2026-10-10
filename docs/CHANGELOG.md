# Changelog

All notable user-facing changes to MouseGestures are documented here, in
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) style. Version numbers
follow the app's `MARKETING_VERSION` (`Info.plist` / Xcode project settings).

For the full engineering history (every internal refactor, bugfix, and
plugin-architecture change), see `MouseGestures_changelog.txt` at the repo
root — this file is the curated, user-facing subset of that log.

## [Unreleased]

_Nothing yet._

## [1.1.0] - 2026-10-09

### Added
- **New built-in plugins, free for everyone**: Timers & Alarms (timers, Pomodoro, alarms, stopwatch, can run an action when they go off), Pointer Gestures (shake, circles, corner dwell) and Text (case, cleanup, lines, Markdown, encode/decode, JSON, calculate, unit and timestamp conversion, snippets). Browser Actions gains web search, dictionary lookup and page links; System Control gains Dock, Stage Manager, keep-awake, Wi-Fi and microphone switches; Media Control gains sound output/input switching. Their options are under **Settings ▸ Actions** (or ▸ Detection for triggers).
- **Optional plugin library** (Pro to install): Scheduler (run actions on a schedule you build visually — specific dates, days of the week, every N days or weeks, monthly, yearly, intervals, sunrise and sunset; ready-made schedules included, or set a custom one right in the gesture), Clipboard & Capture (history menu at the pointer, inbox file, note files, Reminders, Notes), System Events (sleep/wake, lock, power, battery, disks, network, sound devices, clipboard, appearance, idle, app launch/quit), Finder Helpers and Screen Tools (colour picker, copy text from the screen, QR codes).
- **Settings ▸ Plugins**: browse the optional plugin library for free; installing needs Pro (the page says so). Library plugins stay inert without a Pro license, with a notice. Full plugin management stays in the Developer tab. The official library now lives in this repository's `Plugins/` folder. Trigger plugins run only while a gesture uses them, so installing them costs no battery.
- **Plugin libraries**: **Add Plugins** browses the official GitHub plugin library (connected automatically) and any extra GitHub libraries added under Developer Settings ▸ Plugin Sources, and also installs plugin files from disk. Downloads are checksum-verified, signature-checked and require confirmation. See `docs/PLUGIN_LIBRARIES.md`.
- **Per-gesture overrides**: a gesture can now set its own timer sound and speech, search engine or search URL, clipboard restore, and Pointer Gesture sensitivity and timing. Anything left unset follows the plugin-wide default in Settings.
- **A gesture can have several plugin triggers** (for example a shake or a schedule); any one of them fires it, and switching one plugin on no longer replaces another's.
- Plugin symbols in the Settings tabs and the Plugins lists, and content-sized tabs that fall back to symbols when there isn't room.
- Plugins can add their own **settings, background services and custom UI** (settings sheet per plugin), and detection plugins can provide new gesture triggers.
- Detection plugins can now be installed and uninstalled (previously only action plugins could).

### Fixed
- License activation failed on Macs whose computer name is shorter than 3 characters (e.g. "CS"): the license server rejects such names, and the app reported it as a connection problem. Short names are now padded automatically.
- Activation errors now say what actually went wrong (no connection vs. an unexpected server reply, with details) instead of always blaming the internet connection.

## [1.0.1] — 2026-08-08

The first update after launch. Existing v1.0.0 installs auto-update to this
build (see *Auto-update* below); the headline fix also lets the updater
correctly recognize that it's already on the latest version.

### Added

- **Paid Pro licenses via Lemon Squeezy.** Pro can now be unlocked with a key
  from a real purchase at
  [mousegestures.app/purchase](https://mousegestures.app/purchase). A purchased
  key verifies once online at activation, then MouseGestures works fully
  offline — no account, no subscription, no ongoing dependency. The same key
  works on every Mac you personally use, up to Lemon Squeezy's per-key
  activation limit. Manually-issued support/comp keys keep working unchanged.
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

- A **fresh install** now ships with the **Window Management** profile ready to
  use — 16 working gestures across the Main (⌘⌃) and Secondary (⌘⌥) layers —
  instead of a single empty profile, so the app works the moment you install it.
  The built-in profile templates are still available to add from the Profiles
  tab, and "Reset to defaults" now converges on this same profile from every
  entry point.
- **New app icon**, built from the same swoosh-and-cursor mark the website uses,
  so the app, the site and the installer now share one identity.
- The in-app **auto-update check** now polls GitHub's live release API directly
  (reading the DMG URL from the actual published release assets) instead of a
  hand-maintained `version.json` feed.

### Fixed

- **Auto-update no longer false-fires on the current version.** Version
  comparison treated the shipped bundle version `1.0` as older than the release
  tag `1.0.0`, so the app permanently believed an update was available and, with
  auto-update on, re-downloaded and reinstalled the same DMG in a loop. Both
  sides are now zero-padded to equal component count before comparing, so
  `1.0` and `1.0.0` compare equal while real upgrades (`1.0` vs `1.1`) still
  compare correctly.
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
- Numerous reliability fixes from internal audits: data races on
  configuration/profile state, leaked observers and timers, unsafe casts on
  OS-provided values, modifier-key feedback loops that could re-fire an action,
  and a configuration-save deadlock that could crash shortly after changing
  settings. No user-visible behavior change beyond greater stability.

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
- **Auto-update check** — polls the latest GitHub release for new versions.

### Distribution notes

- Built for **macOS 13.0+**, Apple silicon (arm64).
- Signed with a **Developer ID Application** certificate (team `2RZ7SBH74J`),
  hardened-runtime enabled, and notarized + stapled via the release pipeline.
- Requires the **Accessibility** and **Automation/Apple Events** permissions
  at first run for gesture detection and system actions to work.
