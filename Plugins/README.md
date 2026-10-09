# MouseGestures Plugin Library

The optional plugins you can install from **Settings ▸ Plugins** (browsing is free; installing needs Pro). The library
lives in this folder of the app's repository and the app connects to it automatically. Format details:
`docs/PLUGIN_LIBRARIES.md`. Ideas for new triggers and where they belong: `docs/TRIGGER_IDEAS.md`.

## What ships inside the app (not in this folder)

The everyday features are built into MouseGestures itself, free for everyone, in `MouseGesturesCodeBase`:

| Built-in plugin | Kind | Includes |
|---|---|---|
| Text | action | Change case, clean up, edit lines, wrap, Markdown, encode/decode, JSON, calculate, convert units and timestamps, word count, insert dates / UUIDs / snippets |
| Timers & Alarms | action | Timers, Pomodoro, alarms, stopwatch, spoken clock; each can run another action when it goes off |
| Pointer Gestures | detection | Shake, circles, rest in a corner |
| Browser Actions | action | Navigation, tabs, zoom **plus** web search, dictionary lookup, open selected link, copy page URL / Markdown link |
| System Control | action | Display, power, lock **plus** Dock auto-hide, Stage Manager, keep awake, Wi-Fi, microphone mute, screen saver |
| Media Control | action | Playback, volume **plus** next sound output / input |

## In this library

| Plugin | Kind | What it does | Permissions |
|---|---|---|---|
| Scheduler | detection | Run actions at times you write: `weekdays 8:30`, `every 30 min 9:00-17:00`, `sunset -30m`, `monthly 1 9:00` | — |
| Clipboard & Capture | action | Clipboard history menu at the pointer, paste previous, collect selections, plain text; send the selection to an inbox file, note file, Reminders or Apple Notes | keystrokes, notifications |
| System Events | detection | Triggers: sleep/wake, lock, power, battery low, disks, network, sound device changes, clipboard changes, appearance, idle, app launch/quit | — |
| Finder Helpers | action | Copy paths, Terminal here, new window, hidden files, desktop icons, eject all disks | keystrokes, notifications |
| Screen Tools | action | Pick a colour, copy text from anywhere on screen (OCR), scan QR codes, find the pointer | notifications (+ Screen Recording for OCR/QR) |

Detection plugins appear in the gesture editor as a **Plugin** trigger with a picker for their triggers.

## Building

```
python3 build.py [--sdk <Products/Release dir with MouseGestures.swiftmodule>] [--only slug ...]
```

Compiles each `plugins/<slug>/Sources` (plus any files named in `plugin.json` `"shared"`, taken from `shared/`),
wraps it as `<id>.plugin`, ad-hoc signs it, zips it into `dist/` and rewrites `library.json` (SHA-256 included).
Plugins import the app's own module and resolve its symbols at load time, so rebuild against the app version you
target (`minAppVersion`). Commit `dist/` and `library.json` together.

## Writing a plugin

Action plugin: subclass `NSObject`, conform to `GestureActionPlugin`, `@objc(Name)`.
Detection plugin: subclass `NSObject`, conform to `ExternalTriggerPlugin`, call `host.fire(triggerId:)`;
`triggers` is read each time the gesture editor opens, so a plugin can offer triggers the user defines.
Conform to `PluginExtension` to add a settings form, a background service and a custom settings view.
Pure logic belongs in its own file with no app types so it can be unit-tested (see `plugins/clipboard/Sources/ClipHistory.swift`).
A good plugin is a theme: if a feature fits a built-in plugin (browser, system, media, text, time), it belongs there instead.
