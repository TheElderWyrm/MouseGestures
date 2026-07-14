# Deployment Runbook — MouseGestures

This document explains how MouseGestures is built in CI and what is required to
cut a real, distributable release. **The project is not yet shippable as-is** —
see [Blockers](#blockers) below.

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

The `release` job is wired up but **will fail today**. The remaining work is
signing configuration + credentials.

### 1. Deploy-target fork — ✅ RESOLVED: (B) Direct DMG

**Decision (user, 2026-07-13):** ship via **direct distribution** — a
Developer-ID-signed, notarized **DMG** (Option B). The StoreKit 2 IAP Pro path
(`com.mousegestures.pro.*`) is being **replaced with an external licensing
mechanism**, since IAP only functions for Mac-App-Store-distributed apps.
`exportOptions.plist` (`method = developer-id`) and `release.yml` are already
built for this path.

Remaining fork-driven code work (tracked as a follow-on task): remove the
StoreKit `PaymentService` and swap the Pro unlock over to offline license-key
validation. Everything below assumes **(B) Direct DMG**.

### 2. Signing configuration (project settings)

Current state (from the pbxproj / exportOptions.plist) is dev-only and not
notarizable:

| Setting | Current | Needs to be |
|---------|---------|-------------|
| `PRODUCT_BUNDLE_IDENTIFIER` | ✅ `com.mousegestures.MouseGestures` | done (was `com.example.` placeholder) |
| `exportOptions.plist` `teamID` | ✅ `2RZ7SBH74J` | done — now aligned with pbxproj `DEVELOPMENT_TEAM` |
| `exportOptions.plist` `method` | ✅ `developer-id` | correct for path B |
| `CODE_SIGN_IDENTITY` | `Apple Development` (dev-only) | `Developer ID Application` — **needs cert (pending enrollment)** |
| `ENABLE_HARDENED_RUNTIME` | ✅ `YES` (Release) | done — notarization requires it |
| Entitlements file | ✅ `MouseGesturesCodeBase/MouseGestures.entitlements` | done — see below |

**Entitlements (`MouseGesturesCodeBase/MouseGestures.entitlements`):** App Sandbox
is intentionally **off** (the app needs system-wide input monitoring/control that
the sandbox forbids, and direct distribution doesn't require it). The only
Hardened-Runtime exception declared is `com.apple.security.automation.apple-events`
(the AppleScript-based actions send Apple events). Accessibility / input
monitoring are granted at runtime via TCC, not entitlements.

The only remaining project-settings gap is `CODE_SIGN_IDENTITY`, which stays
`Apple Development` until the Developer ID cert is available (see Credentials).

### 3. Credentials

The GitHub Actions secrets listed below must be configured, and the
notarization step (currently a TODO stub) must be implemented.

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

> **Decisions to surface to the operator:** which distribution path (A/B), the
> real bundle identifier, whether team `2RZ7SBH74J` is correct, and who holds the
> Developer ID cert + App Store Connect access. None of these can be resolved
> autonomously.

---

## Notarization (the TODO stub)

`release.yml` currently has a **stub** for notarize + staple — it prints a
warning and publishes an **un-notarized** DMG (which Gatekeeper will block on
end-user machines). To finish it, replace the stub step with the commented recipe
already in `release.yml`:

1. `xcrun notarytool submit MouseGestures.dmg … --wait` (API key or Apple ID auth).
2. `xcrun stapler staple MouseGestures.dmg`
3. `xcrun stapler validate MouseGestures.dmg`

`notarytool` accepts a `.dmg` directly, so the DMG is submitted and stapled as a
single artifact.

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

**This DMG is unsigned and un-notarized**, so Gatekeeper will block it on other
users' machines (right-click → Open, or `xattr -dr com.apple.quarantine`, is
needed to run it elsewhere). It is *not* a shippable artifact — it exists to prove
the packaging path end-to-end. Once the Developer ID cert is in your keychain you
can sign the build locally with `./scripts/package_dmg.sh --identity "Developer ID
Application: … (2RZ7SBH74J)"`, but the canonical **signed + notarized** release is
cut by CI on a tag (below).

## Cutting a release (once unblocked)

```bash
# 1. Ensure ci.yml is green on the commit you want to ship.
# 2. Tag and push:
git tag v1.2.3
git push origin v1.2.3
```

The tag push triggers the `release` job: `verify` runs first, then sign →
archive → export → DMG → notarize/staple → GitHub Release with the DMG attached.

## Post-release

The in-app updater polls
`github.com/eldritchbookwyrm/MouseGestures/main/version.json`. That repo must
exist, be public, and have `version.json` updated to point at the new DMG for
auto-update to work.
