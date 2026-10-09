# Plugin Libraries

A **plugin library** is a GitHub repository (or a folder inside one) that lists prebuilt
MouseGestures plugins. The official library is the `Plugins/` folder of this repository
(`TheElderWyrm/MouseGestures/Plugins`); it is connected automatically. **Settings ▸ Plugins ▸
Add Plugins** (a Pro feature) browses every connected library and can also install a plugin file
from disk. Extra libraries (`owner/repo`, `owner/repo/folder`, `owner/repo@branch-or-tag`, or a
github.com URL) are connected under **Developer Settings ▸ Plugin Sources**. A library in a folder
keeps `library.json` and `dist/` inside that folder; download paths are relative to it. Libraries are only contacted when the
Add Plugins sheet opens or you press Check for Updates.

## Repository layout (the library root is the repo, or the folder)

`library.json` at the repo root (public repos only):

```json
{
  "schemaVersion": 1,
  "name": "My Gesture Plugins",
  "description": "Optional one-liner",
  "plugins": [
    {
      "id": "com.example.cool-actions",
      "name": "Cool Actions",
      "kind": "action",
      "version": "1.2.0",
      "author": "Me",
      "description": "Optional",
      "minAppVersion": "1.0.1",
      "download": "dist/cool-actions-1.2.0.zip",
      "sha256": "<64 hex chars: shasum -a 256 the-zip>"
    }
  ]
}
```

- `kind`: `action` (`GestureActionPlugin`) or `detection` (`DetectionPlugin`).
- `id` must equal the plugin class's `identifier`; installs where it doesn't are rolled back.
- `download`: a path inside the repo, or an absolute `https` URL on github.com /
  githubusercontent.com (e.g. a Release asset).
- `version` / `minAppVersion`: dotted numbers. A higher `version` shows as an update.
- The zip holds exactly one `.plugin` bundle at its top level
  (`ditto -c -k --keepParent Foo.plugin foo.zip`). The bundle must carry at least an
  ad-hoc signature (`codesign --force -s - Foo.plugin`).

- `permissions` (optional): any of `systemAPIs` (keystrokes + AppleScript), `windowManager`,
  `fileSystem`, `executeActions`, `configuration`, `notifications` (show notifications). Shown in the install prompt and applied to
  the plugin's sandbox when it loads; anything unlisted is denied.

## Plugin types

- **Action** plugin: subclass `NSObject`, conform to `GestureActionPlugin`, `@objc(Name)`, set `NSPrincipalClass`.
- **Detection** plugin: subclass `NSObject`, conform to `ExternalTriggerPlugin` (`ExternalTriggerAPI.swift`),
  declare `triggers`, and call `host.fire(triggerId:)`. In the gesture editor it appears as a *Plugin* trigger.

## Settings, services and UI

Any plugin may additionally conform to `PluginExtension` (`Services/PluginExtensions.swift`):

- **Settings** — return `settingsFields` (toggle, text, number, choice, path, info). The app
  renders the form in the plugin's *Settings* sheet, persists values per plugin and calls
  `settingChanged`. Read values with `host.bool/number/string(key)`.
- **Services** — set `runsBackgroundService`; `startService`/`stopService` run while the plugin
  is loaded and its service switch is on (shown in the sheet). `host.storageDirectory` is a
  private persistent folder; `host.notify` and `host.executeAction` are available.
- **UI** — `hasCustomSettingsView` + `makeSettingsView()` supply an `NSView` shown below the form.

`pluginAttached(host:)` delivers the `PluginHost`. Per-plugin actions can still add their own
parameter UI via `configurationView(for:)`. The Focus Timer plugin uses all three.

Plugins `import MouseGestures` and are compiled against a Release build's `MouseGestures.swiftmodule`
with `-Xlinker -undefined -Xlinker dynamic_lookup` (the app links with `-export_dynamic`).
See the official library's `build.py` for a working recipe.

## What the app enforces

1. SHA-256 of the download must match the manifest (checked before unzipping).
2. Downloads limited to 50 MB and to GitHub hosts; paths can't traverse.
3. Archive symlinks can't point outside it; `codesign --verify --deep --strict` must pass.
4. The user confirms each install/update, and a freshly loaded plugin must expose exactly the promised `id`.

**Trust model:** plugins are native code running with MouseGestures' permissions
(including Accessibility). The checksum proves the file is what the manifest
says, not that the author is trustworthy. Only add libraries you trust. To load
third-party bundles, the app's hardened runtime has library validation relaxed
(`com.apple.security.cs.disable-library-validation`).

## Updates

Updating a plugin that's already loaded stages the new files and asks for a relaunch
(loaded code can't be swapped in-process). Fresh installs load immediately.
Installed/library state lives in `~/Library/Application Support/MouseGestures/PluginLibraries/`.
