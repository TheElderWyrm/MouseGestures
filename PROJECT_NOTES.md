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
- Signing config now notarizable: bundle id = `com.mousegestures.MouseGestures`;
  ENABLE_HARDENED_RUNTIME = YES (Release); entitlements file present
  (apple-events only, sandbox off by design); exportOptions teamID = pbxproj
  DEVELOPMENT_TEAM = 5SCU3Z72Z9 (aligned); exportOptions method = developer-id.
- Website aligned to Option-B direct-DMG (3144c8f); #download is a gated placeholder.
REMAINING BLOCKERS = 2, both credential-gated (Apple enrollment pending, user):
  (1) `Developer ID Application` cert (→ CODE_SIGN_IDENTITY, still "Apple Development");
  (2) notarization key/creds (→ replace the notarize TODO stub in release.yml) +
  the CI signing secrets. release.yml `release` job runs on tag once these land.
- Updater polls github.com/eldritchbookwyrm/MouseGestures/main/version.json (repo must exist+be public).
