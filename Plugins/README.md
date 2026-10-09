# MouseGestures Official Plugins

The official plugin **library**. It lives in the app's own repository (this `Plugins/` folder) and the app
connects to it automatically: **Settings ▸ Plugins ▸ Add Plugins** (Pro). Format details: `docs/PLUGIN_LIBRARIES.md`.
Ideas for new triggers and where they belong: `docs/TRIGGER_IDEAS.md`.

| Plugin | Kind | What it does | Permissions |
|---|---|---|---|
| Text | action | Change case, clean up, edit lines, wrap, Markdown, encode/decode, JSON, calculate, word count, insert dates / UUIDs / snippets — on the selection or the clipboard | keystrokes, notifications |
| Timers & Alarms | action | Timers, Pomodoro, alarms (once / daily / weekdays), stopwatch, spoken clock; each can run another action when it goes off | notifications, run actions |
| Web Tools | action | Search selection or clipboard, dictionary lookup, open selected link, copy page URL / Markdown link | keystrokes, notifications |
| Finder Helpers | action | Copy paths, Terminal here, new window, hidden files, desktop icons, eject all disks | keystrokes, notifications |
| System Toggles | action | Dock auto-hide, Stage Manager, keep awake, Wi-Fi, mic mute, screen saver | keystrokes |
| Screen Tools | action | Pick a colour from the screen, find the pointer | notifications |
| Scheduler | detection | Triggers at times you write: `weekdays 8:30`, `every 30 min 9:00-17:00`, `sunset -30m`, `monthly 1 9:00` | — |
| Pointer Gestures | detection | Triggers: shake, circles, rest in a corner | — |
| System Events | detection | Triggers: sleep/wake, lock, power, battery low, disks, network, appearance, idle, app launch/quit | — |

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
`triggers` is read each time the gesture editor opens, so a plugin can offer triggers the user defines (see Scheduler).
Conform to `PluginExtension` to add a settings form, a background service and a custom settings view.
Copy any `plugins/*` directory as a template; `plugin.json` holds the manifest entry.
Keep pure logic in its own file with no app types so it can be unit-tested with a plain `swiftc` (see `plugins/text-tools/Sources/TextOps.swift`).
