# PROJECT NOTES — MouseGestures Project
Agentic memory. Update when project state changes. Index: ../Notes.txt

What: macOS Swift app (mouse gestures w/ Free/Pro trial model). Code in MouseGesturesCodeBase/ + MouseGestures.xcodeproj; marketing site in Website/; planning deck Architecture Planning.pptx.
Status: last touched 2026-05-07 (changelog 2026-04-19: trial expiration notifications, single-profile enforcement for Free, Pro-action locking). History: MouseGestures_changelog.txt (READ FIRST when resuming).
Dev tools: add_remove_files_xcode.py (local copy; identical canonical copy in ../python-tools/) — add/remove file refs in the .xcodeproj.

How to run/build (verified 2026-07-08, Xcode 26.6 / Swift 6.3.3):
`xcodebuild build -project MouseGestures.xcodeproj -scheme MouseGestures -configuration Debug CODE_SIGNING_ALLOWED=NO -destination 'platform=macOS'` → BUILD SUCCEEDED. macOS-only, arm64, deploy target 13.0, menu-bar (LSUIElement). Now has README.md, DEPLOYMENT.md, SwiftLint config+baseline, and a 30-test no-host unit target.

DEPLOYMENT READINESS (2026-07-14 audit; full checklist in AUDIT.md):
GREEN today (cert-independent): build SUCCEEDED, 30 tests pass, SwiftLint 0 new
violations; verified unsigned DMG (dist/MouseGestures-1.0-unsigned.dmg,
SHA-256 63d843f9…). All config/fork blockers cleared:
- DEPLOY-TARGET FORK **RESOLVED (user, 2026-07-13):** (B) Direct DMG. StoreKit-2 IAP
  (`PaymentService`, `com.mousegestures.pro.*`) REMOVED (4e5a952) → Pro unlocks via
  offline HMAC license key (LicenseKey/LicenseLogic/LicenseService). 0 StoreKit refs.
- Signing config notarizable & VERIFIED (2026-07-18): bundle id =
  `com.mousegestures.MouseGestures`; ENABLE_HARDENED_RUNTIME = YES (Release);
  entitlements file present (apple-events only, sandbox off by design);
  exportOptions teamID = pbxproj DEVELOPMENT_TEAM = `2RZ7SBH74J` (the PAID
  individual team; `5SCU3Z72Z9` is the same Apple ID's FREE personal team and is
  NOT the publisher — the earlier "correction" to it was a regression, now
  reverted); exportOptions method = developer-id.
- Apple Developer Program enrollment CONFIRMED (user, 2026-07-18). Developer ID
  Application cert for `2RZ7SBH74J` is in the keychain (valid Jul 18 2026 →
  Feb 1 2027, private key present). A signed, HARDENED, secure-TIMESTAMPED,
  `get-task-allow`-free `.app` is produced by `archive → exportArchive`
  (proven locally) → dist DMG. `spctl` = "Unnotarized Developer ID" (expected).
- Website aligned to Option-B direct-DMG (3144c8f); #download is a gated placeholder.
REMAINING BLOCKER = 1, credential-gated: a NOTARIZATION credential (App Store
  Connect API key .p8 + key-id + issuer, OR Apple ID + app-specific password +
  team-id). No such cred is on the machine (`notarytool history` → "Must provide
  credentials"). notarize+staple is now fully WIRED (not a stub) in both
  release.yml (CI, via secrets) and package_dmg.sh (`--notarize`); it runs the
  moment a cred is supplied. release.yml `release` job cuts the signed+notarized
  DMG on a `v*` tag once the CI secrets land.
- Updater polls github.com/eldritchbookwyrm/MouseGestures/main/version.json (repo must exist+be public).
