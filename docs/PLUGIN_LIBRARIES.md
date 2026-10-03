# Plugin Libraries

A **plugin library** is a GitHub repository that lists prebuilt MouseGestures
plugins. Users add a repo in **Developer ▸ Plugin Management ▸ Browse Libraries**
(`owner/repo`, `owner/repo@branch-or-tag`, or a github.com URL) and can then
install, update and remove its **action** and **detection** plugins.

## Repository layout

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
  `fileSystem`, `executeActions`, `configuration`. Shown in the install prompt and applied to
  the plugin's sandbox when it loads; anything unlisted is denied.

## Plugin types

- **Action** plugin: subclass `NSObject`, conform to `GestureActionPlugin`, `@objc(Name)`, set `NSPrincipalClass`.
- **Detection** plugin: subclass `NSObject`, conform to `ExternalTriggerPlugin` (`ExternalTriggerAPI.swift`),
  declare `triggers`, and call `host.fire(triggerId:)`. In the gesture editor it appears as a *Plugin* trigger.

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
