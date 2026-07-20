# Introducing MouseGestures 1.0

*Control macOS at the speed of thought.*

MouseGestures is a lightweight macOS menu-bar app that turns mouse gestures —
plus keyboard and mouse-button triggers — into instant actions. Flick to a
screen corner, hold a modifier, and the action fires immediately: no clicking
through menus, no reaching for the keyboard.

## Why we built it

Most window-management and automation tools on macOS ask you to memorize
keyboard shortcuts or dig through a menu bar icon's dropdown. MouseGestures
instead uses the screen's edges and corners — space you're already moving the
cursor through — as the trigger surface, with modifier keys layered on top for
as many distinct gestures as you need.

## What's in 1.0

- **Window management** — snap to any of 11 screen regions, resize by percent
  or pixel, tile, cascade, and save/restore named window layouts.
- **System & media control** — volume, brightness, dark mode, Do Not Disturb,
  screenshots, sleep/lock/restart, playback — all without touching the
  keyboard.
- **Automation** — trigger Shortcuts, run AppleScript/shell/Python/JS scripts,
  open apps/files/URLs, or drive clipboard actions from a gesture.
- **Bundles** — chain actions into sequences, add conditional branches, repeat
  steps, or insert timed delays, so a single gesture can run a multi-step
  routine.
- **Per-app profiles** — your gesture set switches automatically with the
  frontmost app, so the same corner can mean something different in your
  browser than it does in your editor.
- **A real plugin architecture** — every built-in capability (detection,
  actions, UI, background services) is itself a plugin behind a shared
  protocol. External `.plugin`/`.bundle` files install the same way.
- **Guided onboarding** — a first-run tour that opens Settings, highlights the
  relevant controls, and walks through creating your first gesture end to end.

Free covers the core action set with a single profile. Pro unlocks multiple
profiles and the advanced action set, unlocked with an offline license key —
there's a 30-day full-feature trial to try everything first, no account or
credit card required.

## Under the hood

MouseGestures has no third-party dependencies — it's built entirely on system
frameworks (SwiftUI, AppKit, Carbon, Accessibility) — and ships with a 30-test
unit suite covering the licensing, screen-zone math, and codable-config logic
that don't need a running app to verify. See `README.md` for the architecture
and how to build it yourself.

## Getting it

MouseGestures is distributed as a signed **direct-download DMG** (not through
the Mac App Store), so Pro unlocks via an offline license key rather than
StoreKit. The build is signed with a Developer ID certificate and hardened
runtime; **notarization is the last step before general release** — see
`DEPLOYMENT.md` for exactly where that stands. Until a notarized DMG is
posted, you'll need to right-click → Open on first launch to get past
Gatekeeper.

Grant the **Accessibility** and **Automation** permissions macOS asks for on
first run — MouseGestures needs them to detect input and drive system actions.

---

*Questions, bug reports, or feature ideas: open an issue on the project's
GitHub repository.*
