# What can trigger an action?

MouseGestures began with **active** triggers: you do something on purpose. Plugins now open the door to
**passive** ones: something happens and an action runs without you touching anything. This is the map of
what exists, what's planned, and where each belongs, so new plugins land in the right place.

Legend: ✅ built · 🟡 partly · 💡 idea

## Active — you did something

| Family | Examples | Status |
|---|---|---|
| Pointer position | Screen edges and corners (built-in zones), rest in a corner (Pointer Gestures) | ✅ |
| Pointer motion | Shake left-right / up-down, circle clockwise / counter-clockwise (Pointer Gestures) | ✅ |
| Pointer shapes | Triangle, square, check mark, "Z", spiral | 💡 (same recogniser, more shapes) |
| Mouse buttons | Extra buttons, chorded clicks, click-and-hold (built-in) | ✅ |
| Keyboard | Shortcuts, modifier keys held (built-in) | ✅ |
| Trackpad | Multi-finger swipes, pinch, force-click, edge swipes | 💡 |
| Scroll | Modifier + scroll, scroll along a screen edge | 💡 |
| Typing | Type-a-phrase text triggers ("`;sig`"), double-tap a key | 💡 |
| Outside the Mac | URL scheme `mousegestures://run?…`, Shortcuts app action, AppleScript, command line | 🟡 (dev runner only) |
| Hardware | Stream Deck, MIDI pad, game controller, Touch Bar | 💡 |
| Voice | A spoken phrase | 💡 |
| Menu bar | Click or scroll on the MouseGestures icon | 💡 |

## Passive — something happened

| Family | Examples | Plugin | Status |
|---|---|---|---|
| Time of day | At 8:30, weekdays, mon/wed/fri, every 30 min, sunrise / sunset ± offset, monthly, once | **Scheduler** | ✅ |
| Countdown | A timer / alarm / Pomodoro finished, then run something | **Timers & Alarms** ("then run action") | ✅ |
| Calendar | An event starts / ends, a reminder is due | — | 💡 |
| Power | Sleep, wake, plugged in / unplugged, battery low, low-power mode | **System Events** | ✅ (low-power mode 💡) |
| Session | Screen locked / unlocked, login / logout, boot | **System Events** | 🟡 |
| Idle | No input for N minutes, back from idle | **System Events** | ✅ |
| Displays | Connected / removed, mirroring, resolution change | **System Events** | 🟡 |
| Network | Internet lost / back, Wi-Fi network joined / left, VPN up / down | **System Events** | 🟡 (online/offline only; SSID needs Location permission) |
| Disks | Volume mounted / unmounted, USB or Thunderbolt device plugged, Time Machine finished | **System Events** | 🟡 (mount / unmount) |
| Peripherals | Headphones plugged / audio output or microphone changed | **System Events** | ✅ |
| Peripherals (more) | Bluetooth device connected (AirPods), camera or mic in use | — | 💡 |
| Appearance | Dark / Light switched, Focus mode on / off | **System Events** | 🟡 (Dark / Light) |
| Apps | A named app launched / quit / came to front; frontmost window title or browser URL changed | **System Events** | 🟡 (one watched app: launch / quit) |
| Clipboard | Something copied, a web address copied (patterns like code or numbers 💡) | **System Events** | 🟡 |
| Files | A folder changed, a download finished, a screenshot was taken | — | 💡 |
| System health | CPU / memory pressure, thermal state, disk space low | — | 💡 |
| Location | Arrived at / left a place | — | 💡 (needs Location permission) |
| Media | Now-playing track changed, playback started / stopped | — | 💡 |
| Network messages | A webhook, push message or MQTT / Home Assistant event arrives | — | 💡 |

## Other shapes of trigger

- **Chained** — another action finished (success / failure). Timers already support "then run action".
- **Conditional** — only when something is true (an app is frontmost, a Wi-Fi network is joined, it's a weekday). The gesture editor has conditions; time and state conditions would extend them.
- **Counted / sequenced** — the third time, or A then B within two seconds.
- **Combined** — any of several triggers (OR) or all of them (AND).

## Where plugins should live

One plugin per *theme*, so each has one settings page and one background monitor:

| Plugin | Theme | Kind |
|---|---|---|
| Pointer Gestures | triggers from pointer movement | detection |
| Scheduler | triggers from the clock | detection |
| System Events | triggers from the state of the Mac | detection |
| Timers & Alarms | countdowns, alarms, stopwatch (+ "then run") | action |
| Text | everything that changes or inserts text | action |
| Clipboard | history and clipboard handling | action |
| Quick Capture | send text to files, Reminders, Notes | action |
| Finder Helpers | Finder windows, files, desktop, disks | action |
| System Toggles | switches for system settings | action |
| Web Tools | search, lookup, links, browser page | action |
| Screen Tools | colour picker, find the pointer | action |

Rule of thumb for a new idea: if it reacts to the *pointer* it goes in Pointer Gestures, to the *clock*
in Scheduler, to the *Mac's state* in System Events; if it *does* something it joins the action plugin
whose theme matches, and only becomes a new plugin when it needs its own settings or background service.
