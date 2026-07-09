# PROJECT NOTES — MouseGestures Project
Agentic memory. Update when project state changes. Index: ../Notes.txt

What: macOS Swift app (mouse gestures w/ Free/Pro trial model). Code in MouseGesturesCodeBase/ + MouseGestures.xcodeproj; marketing site in Website/; planning deck Architecture Planning.pptx.
Status: last touched 2026-05-07 (changelog 2026-04-19: trial expiration notifications, single-profile enforcement for Free, Pro-action locking). History: MouseGestures_changelog.txt (READ FIRST when resuming).
Dev tools: add_remove_files_xcode.py (local copy; identical canonical copy in ../python-tools/) — add/remove file refs in the .xcodeproj.

How to run/build (verified 2026-07-08, Xcode 26.6 / Swift 6.3.3):
`xcodebuild build -project MouseGestures.xcodeproj -scheme MouseGestures -configuration Debug CODE_SIGNING_ALLOWED=NO -destination 'platform=macOS'` → BUILD SUCCEEDED. macOS-only, arm64, deploy target 13.0, menu-bar (LSUIElement). No tests, no lint config, no README yet.

DEPLOYMENT READINESS (2026-07-08 audit; full detail in helm workspace AUDIT.md):
Source compiles clean. Blockers are packaging/config + one architecture fork:
- **DEPLOY-TARGET FORK (user decision, gates everything):** app has StoreKit-2 IAP
  (`com.mousegestures.pro.*`) → implies **Mac App Store**, but exportOptions/CI target
  `developer-id` DMG → **direct distribution**. StoreKit IAP does NOT work outside the
  App Store. Must pick: (A) App Store [keep StoreKit; add sandbox+products] or
  (B) Direct DMG [notarize; replace StoreKit purchase path w/ external licensing].
- Signing config is non-notarizable regardless: bundle id = placeholder
  `com.example.MouseGestures`; CODE_SIGN_IDENTITY = "Apple Development" (dev-only);
  ENABLE_HARDENED_RUNTIME = NO (notarization needs YES); exportOptions teamID =
  YOUR_TEAM_ID while pbxproj DEVELOPMENT_TEAM = 2RZ7SBH74J (confirm+align); no
  entitlements file; CI has no cert import or notarize step.
- Updater polls github.com/eldritchbookwyrm/MouseGestures/main/version.json (repo must exist+be public).
