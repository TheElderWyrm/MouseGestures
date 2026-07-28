# Deployment Runbook — MouseGestures

This document explains how MouseGestures is built in CI and how a
distributable release is cut. **The pipeline is proven end-to-end**: the
`v1.0.0` tag ran through it and published a signed, notarized, stapled DMG.
The historical blockers are all resolved — see [Blockers](#blockers) below
for the record. The only gate on the next release (`v1.0.1`) is a human
go/no-go on scope (see [Cutting a release](#cutting-a-release)).

For local development build/run instructions, see [README.md](README.md).

---

## Pipeline overview

Two GitHub Actions workflows, split by whether they need secrets:

| Workflow | Trigger | Signs? | Purpose |
|----------|---------|--------|---------|
| `.github/workflows/ci.yml` | push to `main`/`default`, PR, manual | no | Full build + unit tests + SwiftLint (against baseline) on every change. |
| `.github/workflows/release.yml` — `verify` job | PR, manual, and as a gate before a tag | no | Signing-free Release build proof. Works on forks / without secrets. |
| `.github/workflows/release.yml` — `release` job | push tag `v*` | **yes** | Import cert → archive (signed, hardened) → export → DMG → notarize+staple → publish GitHub Release. |

The `release` job `needs: verify`, so a broken build can never reach the signing
stage. `verify` requires no secrets; only the tag-triggered `release` job does.

---

## Blockers

Historical record — every item below is now **✅ RESOLVED** and was proven
by the successful `v1.0.0` tagged run (signed → notarized → stapled →
published). Kept here for provenance.

### 1. Deploy-target fork — ✅ RESOLVED: (B) Direct DMG

**Decision (user, 2026-07-13):** ship via **direct distribution** — a
Developer-ID-signed, notarized **DMG** (Option B). The StoreKit 2 IAP Pro path
(`com.mousegestures.pro.*`) is being **replaced with an external licensing
mechanism**, since IAP only functions for Mac-App-Store-distributed apps.
`exportOptions.plist` (`method = developer-id`) and `release.yml` are already
built for this path.

The fork-driven code work is **done** (commit `4e5a952`): the StoreKit
`PaymentService` was removed and the Pro unlock swapped over to offline,
HMAC-validated license-key validation (`LicenseKey` / `LicenseLogic`). Everything
below assumes **(B) Direct DMG**.

### 2. Signing configuration (project settings)

Current state (from the pbxproj / exportOptions.plist) is notarization-ready:

| Setting | Current | Needs to be |
|---------|---------|-------------|
| `PRODUCT_BUNDLE_IDENTIFIER` | ✅ `com.mousegestures.MouseGestures` | done (was `com.example.` placeholder) |
| `exportOptions.plist` `teamID` | ✅ `2RZ7SBH74J` | done — the PAID Developer Program team, aligned with pbxproj `DEVELOPMENT_TEAM` |
| `exportOptions.plist` `method` | ✅ `developer-id` | correct for path B |
| `CODE_SIGN_IDENTITY` | `Apple Development` (project default; the release **archive** overrides to `Developer ID Application` via CLI) | Developer ID cert is present in the keychain — signed builds work today |
| `ENABLE_HARDENED_RUNTIME` | ✅ `YES` (Release) | done — notarization requires it |
| Entitlements file | ✅ `MouseGesturesCodeBase/MouseGestures.entitlements` | done — see below |

> **Team note.** The Apple ID `millercwalker@gmail.com` owns TWO teams: the free
> personal team `5SCU3Z72Z9` (issues only `Apple Development` certs — cannot
> notarize) and the **paid** individual team **`2RZ7SBH74J`** (WALKER CARPENTER
> MILLER), which holds the `Developer ID Application` / `Apple Distribution` certs.
> `2RZ7SBH74J` is the publisher; all config points at it.

**Entitlements (`MouseGesturesCodeBase/MouseGestures.entitlements`):** App Sandbox
is intentionally **off** (the app needs system-wide input monitoring/control that
the sandbox forbids, and direct distribution doesn't require it). The only
Hardened-Runtime exception declared is `com.apple.security.automation.apple-events`
(the AppleScript-based actions send Apple events). Accessibility / input
monitoring are granted at runtime via TCC, not entitlements.

The project-settings gaps are all closed: the Developer ID Application cert for
`2RZ7SBH74J` is in the keychain, and the release archive signs with it explicitly
(the `CODE_SIGN_IDENTITY` project default of `Apple Development` is overridden on
the archive command line — see the release workflow and `package_dmg.sh`).

### 3. Credentials

The notarize + staple steps are **implemented** (release.yml and
`package_dmg.sh`) and the required GitHub Actions secrets are **confirmed set**
under the exact names below (verified via the Actions API and by a real tagged
run that signed, notarized, and stapled successfully). Note these are GitHub
repo secrets, not HELM's own secret store — release.yml has no access to the
latter, so a value stored only there (e.g. an earlier `APP_SPECIFIC_PASSWORD`
entry) is invisible to this workflow.

---

## GitHub Actions secrets

Set these under **repo → Settings → Secrets and variables → Actions**. Never
commit real values.

**Signing:**

| Secret | What it is |
|--------|------------|
| `SIGNING_CERTIFICATE_P12_BASE64` | Your *Developer ID Application* cert + private key exported as a `.p12`, base64-encoded: `base64 -i cert.p12 \| pbcopy` |
| `SIGNING_CERTIFICATE_PASSWORD` | The password you set when exporting the `.p12` |
| `KEYCHAIN_PASSWORD` | Any throwaway string; used to create the ephemeral CI keychain |

**Notarization — configure exactly ONE set:**

- **(a) App Store Connect API key** (recommended — no 2FA, no personal Apple ID):
  | Secret | What it is |
  |--------|------------|
  | `NOTARY_API_KEY_ID` | Key ID from App Store Connect → Users and Access → Integrations → Keys |
  | `NOTARY_API_ISSUER_ID` | Issuer ID from the same page |
  | `NOTARY_API_KEY_P8_BASE64` | The downloaded `AuthKey_XXXX.p8`, base64-encoded |

- **(b) Apple ID + app-specific password:**
  | Secret | What it is |
  |--------|------------|
  | `NOTARY_APPLE_ID` | The Apple ID email of the account |
  | `NOTARY_PASSWORD` | An **app-specific password** (appleid.apple.com → Sign-In and Security) — *not* the account password |
  | `NOTARY_TEAM_ID` | The 10-char team id |

> **Resolved:** all 6 repo secrets above (signing trio + `NOTARY_APPLE_ID` /
> `NOTARY_PASSWORD` / `NOTARY_TEAM_ID` for team `2RZ7SBH74J`) are set in
> **repo → Settings → Secrets and variables → Actions** under these exact
> names. Confirmed via `GET /repos/.../actions/secrets` and by a real `v1.0.0`
> tag run whose `Notarize and staple` step succeeded end-to-end. Everything
> else was already settled: distribution path (B, Direct DMG), bundle id
> (`com.mousegestures.MouseGestures`), publishing team (`2RZ7SBH74J`), and the
> Developer ID signing cert.

---

## Notarization (implemented)

`release.yml`'s `Notarize and staple` step is now fully implemented (no longer a
stub). It auto-selects whichever credential set is present and runs:

1. `xcrun notarytool submit MouseGestures.dmg … --wait` (API key or Apple ID auth).
2. `xcrun stapler staple MouseGestures.dmg`
3. `xcrun stapler validate MouseGestures.dmg`

`notarytool` accepts a `.dmg` directly, so the DMG is submitted and stapled as a
single artifact. The same flow is available locally:
`./scripts/package_dmg.sh --identity "Developer ID Application: … (2RZ7SBH74J)" --notarize`
with the `NOTARY_*` env vars set. If no credential is configured the step fails
fast with a clear error rather than shipping an un-notarized DMG.

---

## Local packaging (unsigned DMG — available today)

Before Apple enrollment completes you can still produce a real, installable disk
image for local verification and internal testing:

```bash
./scripts/package_dmg.sh
# -> dist/MouseGestures-<version>-unsigned.dmg  (+ prints the SHA-256)
```

The script does a clean unsigned Release build, stages the `.app` alongside an
`Applications` symlink, and writes a compressed (`UDZO`) DMG to `dist/`.

**This unsigned DMG is not a shippable artifact** — it exists to prove the
packaging path end-to-end. The Developer ID cert is now in the keychain, so a
signed, hardened, notarization-ready DMG builds locally with:

```bash
./scripts/package_dmg.sh --identity "Developer ID Application: WALKER CARPENTER MILLER (2RZ7SBH74J)"
# -> dist/MouseGestures-<version>.dmg  (signed; secure-timestamped; get-task-allow stripped)
```

That DMG passes `codesign --verify --deep --strict` but `spctl` still reports
"Unnotarized Developer ID" — add `--notarize` (with a `NOTARY_*` credential) to
notarize + staple it, or let CI cut the canonical signed + notarized release on a
tag (below).

## Cutting a release

```bash
# 1. Ensure ci.yml is green on the commit you want to ship.
# 2. Push the commits, then tag and push the tag:
git push origin main
git tag v1.2.3
git push origin v1.2.3
```

The tag push triggers the `release` job: `verify` runs first, then sign →
archive → export → DMG → notarize/staple → GitHub Release with the DMG attached.

> **v1.0.1 scope gate (human go/no-go).** As of 2026-07-27 local `main` is 13
> commits ahead of `origin/main`. Tagging HEAD ships *all* of them publicly —
> not just the updater self-heal fix, but also the live Lemon Squeezy
> paid-licensing/checkout and ~35 audit bug fixes. The 14 existing v1.0.0
> installs will auto-update to whatever is published. Two clean paths:
> **(A) full** — push all 13, tag `v1.0.1` (requires monetization go-live sign-off);
> **(B) narrow self-heal** — cherry-pick the updater fix (`a60b2eb`, optionally
> the baseline refresh `b09c97f`+`4c765b3`) onto `origin/main`, tag `v1.0.1`,
> defer Lemon Squeezy. Build/tests/lint are green on both paths.

## Post-release

The in-app updater polls GitHub's live release API
(`api.github.com/repos/TheElderWyrm/MouseGestures/releases/latest`) directly
and reads the DMG's URL from that release's actual assets — there's no
separate file to update by hand. As soon as the `release` job above publishes
the GitHub Release with the DMG attached, the in-app updater picks it up on
its next check. The release must be public and not marked draft/prerelease
(the updater ignores both).

---

## Licensing (Lemon Squeezy) — remaining setup

**The app-side code is done and tested**: `LemonSqueezyLicense.swift` (License
API client) + `LicenseService.swift` (activation/deactivation, cached locally
so the app never needs network again after the first successful activation)
+ `LicenseSettingsView.swift` (Settings → License UI). This app's own offline
HMAC keys (`LicenseKey.swift`, still used for manually-issued support/comp
keys) keep working unchanged — activation tries that format first, and only
falls back to an online Lemon Squeezy check for anything else.

**Status: LIVE.** Account, product, and checkout are all set up — the real
checkout overlay is wired into `Website/purchase.html`'s `#buy-btn` (commit
`92df62c`), and the homepage pricing card links straight to `/purchase` too.
Original setup steps (account → store → product → License Keys config →
checkout URL) are done; the two items below are the only ones still open.

**1. Test before announcing sales are open** (if not already done): Lemon
Squeezy stores support a **test mode** — run a real test purchase, confirm
the email actually contains a license key, paste that key into MouseGestures'
Settings → License → Activate, and confirm it unlocks Pro. This is the one
thing that genuinely can't be verified without your account existing.

**2. Two more dashboard fields worth filling in** (both are pure copy/paste,
no code) — Lemon Squeezy shows a "confirmation modal" right after a
successful checkout, and can add a note to the email receipt; both are
configured per-product in your dashboard, not in this repo:

- **Product settings → Confirmation modal** (shown immediately after payment succeeds):
  - Title: `Thanks for going Pro!`
  - Message: `Your license key is in your email receipt — it should land any moment now. Open MouseGestures, go to Preferences → License, paste the key, and click Activate.`
  - Button text: `See the full guide`
  - Button link: `https://mousegestures.app/purchase#license-how`

- **Product settings → Receipt emails → thank you note** (shown inside the email receipt itself, alongside the license key):
  - `Thanks for supporting MouseGestures! Your license key is above — paste it into the app under Preferences → License and click Activate. It works on every Mac you personally use, no account or subscription attached. Questions? Email support@mousegestures.app.`
  - The receipt email also has its own separate "button content" / "destination link" fields (distinct from the note) — worth pointing that button at the same `https://mousegestures.app/purchase#license-how` link too, if you want a second path back to the activation steps.

No ongoing maintenance after this — no webhook, no key inventory to manage.
