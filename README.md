# MouseGestures

MouseGestures is a macOS menu-bar utility that turns the edges and corners of
your screen into gestures. Hold a modifier key and move your mouse into a
zone — a corner, an edge — and MouseGestures fires whatever action you've
assigned there: snap a window, skip a track, adjust volume, switch Spaces,
navigate a browser tab, and more. It runs quietly in the background with no
Dock icon; everything is configured from its menu-bar icon.

## Getting started

1. **Grant permissions.** MouseGestures needs two macOS permissions to work:
   - **Accessibility** — to detect mouse/keyboard input and drive window and
     system actions.
   - **Automation** — for actions that control other apps or the system
     (volume, brightness, browser navigation, etc.).

   Grant both under **System Settings → Privacy & Security → Accessibility /
   Automation**. You can also check permission status from the menu-bar
   icon's **Check Accessibility Permissions** item.

2. **Open Settings.** Click the menu-bar icon → **Preferences…** (or press
   **⌘,** while the app is frontmost).

3. **Pick a profile.** A profile is a full set of gesture → action mappings.
   MouseGestures ships with several ready-made profiles — Window Management,
   Application Management, Media Control, Browser Navigation, System, System
   Navigation, Productivity, Minimal, and Developer — covering different
   workflows. Apply one from the **Profiles** tab, or build your own gesture
   by gesture in the **Gestures** tab. The Free tier is limited to a single
   active profile at a time; Pro unlocks switching between multiple profiles
   (including per-app profiles).

4. **Try a gesture.** Hold the modifier a profile uses (most default to
   ⌘⌃ / ⌘⌥) and move the pointer into a screen corner or edge. A brief
   highlight shows you which zones are active and what they're bound to.

## What it can do

Actions are organized by category, and every category is itself a plugin —
new action plugins can add their own categories:

- **Window Management** — close/minimize/maximize/fullscreen, snap to a
  screen region, resize, move between displays, save/restore window
  positions, named window layouts.
- **Media Control** — play/pause, skip track, seek, volume.
- **Browser Navigation** — back/forward/reload, tab management, zoom — works
  with any browser via standard keyboard shortcuts.
- **System Control** — display/keyboard brightness, Dark Mode, Do Not
  Disturb, screenshots, restart/shutdown/logout.
- **Automation** — trigger a keyboard shortcut, run a Shortcuts shortcut or a
  script, open an app/file/URL, clipboard actions.
- **Bundle** — chain actions together: sequences, conditionals, repeats,
  timed delays.

Any gesture can also be bound to a keyboard shortcut or mouse button instead
of (or in addition to) a screen zone, and most actions can be set to repeat
automatically while the gesture is held.

## Requirements

- macOS 13.0 or later, Apple silicon.

## Installing

With [Homebrew](https://brew.sh):

```sh
brew install --cask theelderwyrm/tap/mousegestures
```

The cask lives in [TheElderWyrm/homebrew-tap][tap] and tracks each GitHub
release automatically, so `brew upgrade --cask --greedy mousegestures` always
pulls the current build. (The `--greedy` is because the cask declares
`auto_updates true` — MouseGestures also updates itself from **Settings ▸
Updates**, and Homebrew steps aside for apps that do.) If you already have
MouseGestures in `/Applications` from a manual download, add `--adopt` so
Homebrew takes over that copy rather than refusing to overwrite it.

Or download `MouseGestures.dmg` straight from the [latest release][latest] —
the same signed, notarized, stapled build the cask installs.

[tap]: https://github.com/TheElderWyrm/homebrew-tap
[latest]: https://github.com/TheElderWyrm/MouseGestures/releases/latest

## Building from source

1. Open `MouseGestures.xcodeproj` in Xcode 16+.
2. Select the **MouseGestures** scheme and a **My Mac** destination.
3. Run (**⌘R**).

Or from the command line:

```sh
xcodebuild build \
  -project "MouseGestures.xcodeproj" \
  -scheme MouseGestures \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  -destination 'platform=macOS'
```

## Linting

CI runs SwiftLint against `.swiftlint-baseline.json`, which grandfathers
pre-existing violations so a run only fails on *new* ones introduced by a
change:

```sh
swiftlint lint --strict --baseline .swiftlint-baseline.json
```

When legitimate code growth (new features, new tests) accumulates enough
violations that the baseline no longer reflects reality, refresh it from a
clean working tree:

```sh
swiftlint lint --write-baseline .swiftlint-baseline.json
```

Before committing the refreshed baseline, diff it against `git diff` and
confirm every added entry traces back to a real prior commit (`git log
--since=<baseline capture date> -- <file>`) rather than to an unrelated or
unreviewed change — the baseline should absorb known debt, not mask a
regression.

## Free vs. Pro

MouseGestures is free to use with a single active profile. Pro removes that
limit (multiple profiles, per-app profile switching, advanced targeting) and
is unlocked with a license key — no account or subscription involved. A
purchased key verifies once online at activation, then works fully offline.

## More

- User-facing release notes: [`docs/CHANGELOG.md`](docs/CHANGELOG.md)
- Launch write-up: [`docs/ANNOUNCEMENT.md`](docs/ANNOUNCEMENT.md)
- Packaging and the release process: [`DEPLOYMENT.md`](DEPLOYMENT.md)
