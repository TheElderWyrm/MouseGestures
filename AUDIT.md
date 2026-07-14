# MouseGestures — Deployment-Readiness Audit

**Date:** 2026-07-14 · **Commit:** `78ed961` (clean tree) · **Toolchain:** Xcode 26.6 / Swift 6.3.3

Single go/no-go sheet for the original directive: *audit state, clean reproducible
build, tests/lint pass, resolve packaging/config/dependency gaps, document run &
deploy, produce a verified deployable artifact, surface credential decisions.*

---

## Verdict

- 🟢 **GO for the achievable (cert-independent) tier.** The tree builds, tests,
  and lints green; config/packaging/dependency gaps are all closed; docs are
  consistent; and a verified **unsigned** DMG exists and installs locally.
- 🟡 **NO-GO for a shippable (end-user) release** — blocked only on **2
  credential items** (Apple Developer ID cert + notarization creds). No code,
  config, or design work remains; these are enrollment/credential steps a human
  must complete. Steps to unblock are below.

---

## Readiness checklist

| # | Criterion | State | Evidence |
|---|-----------|-------|----------|
| 1 | Reproducible unsigned build | 🟢 GREEN | `xcodebuild build … CODE_SIGNING_ALLOWED=NO` → **BUILD SUCCEEDED** (tool `mousegestures-build-verify`) |
| 2 | Unit tests pass | 🟢 GREEN | `xcodebuild test` → **TEST SUCCEEDED**, **30 tests / 0 failures** (tool `mousegestures-test`) |
| 3 | Lint clean vs baseline | 🟢 GREEN | SwiftLint 0.65.0 `--strict --baseline` → **0 violations, 0 serious in 115 files** (tool `mousegestures-lint`) |
| 4 | Dependencies | 🟢 GREEN | No third-party packages; system frameworks only (StoreKit dependency removed) |
| 5 | Deploy-target fork resolved | 🟢 GREEN | (B) Direct DMG chosen (user, 2026-07-13); StoreKit IAP removed `4e5a952` — 0 `PaymentService` refs, 0 StoreKit imports; Pro = offline HMAC license key |
| 6 | Signing config (project settings) | 🟢 GREEN | bundle id `com.mousegestures.MouseGestures`; `ENABLE_HARDENED_RUNTIME=YES` (Release); entitlements file present (apple-events only, sandbox off by design); exportOptions `method=developer-id`, `teamID=5SCU3Z72Z9` aligned with pbxproj |
| 7 | Verified deployable artifact (unsigned) | 🟢 GREEN | `dist/MouseGestures-1.0-unsigned.dmg` (2.9 MB), SHA-256 `63d843f9…f2a573`; built + verified E2E `78ed961`; **unchanged this run — not rebuilt** |
| 8 | Docs: run + deploy | 🟢 GREEN | `README.md` (build/run/test/lint/permissions), `DEPLOYMENT.md` (release runbook + secrets + notarization), `PROJECT_NOTES.md` — reconciled to shipped state this audit (removed stale StoreKit/placeholder/"19 tests"/unresolved-fork text) |
| 9 | CI | 🟢 GREEN | `ci.yml` = build+test+lint, no secrets; `release.yml` verify job = signing-free build proof |
| 10 | **Developer ID cert** | 🔴 GATED | See Blocker 1 |
| 11 | **Notarization creds + CI signing secrets** | 🔴 GATED | See Blocker 2 |
| 12 | Website download link live | ⏸️ PARKED | `#download` is a gated placeholder (Option-B aligned `3144c8f`); flips live when the signed DMG ships |
| 13 | Updater `version.json` repo | ⏸️ PARKED | Requires public `github.com/eldritchbookwyrm/MouseGestures` repo + `version.json` at first release |

---

## Remaining blockers (exact unblock steps)

Both are **credential-gated** — Apple Developer enrollment is pending (user says
coming soon). Nothing else stands between the current tree and a shippable release.

### Blocker 1 — Developer ID Application certificate
- **What it gates:** `CODE_SIGN_IDENTITY` (still `Apple Development`, dev-only) →
  a Gatekeeper-acceptable signature.
- **Unblock:**
  1. Complete Apple Developer Program enrollment for team `5SCU3Z72Z9`.
  2. Create/download a **Developer ID Application** cert; install the cert + key
     in the signing keychain.
  3. Export as `.p12`; set CI secrets `SIGNING_CERTIFICATE_P12_BASE64`,
     `SIGNING_CERTIFICATE_PASSWORD`, `KEYCHAIN_PASSWORD` (see `DEPLOYMENT.md`).
  4. Local signed build path: `./scripts/package_dmg.sh --identity "Developer ID Application: … (5SCU3Z72Z9)"`.

### Blocker 2 — Notarization credentials + notarize step
- **What it gates:** notarize + staple. `release.yml` currently has a **stub**
  that publishes an un-notarized DMG (Gatekeeper blocks it end-user-side).
- **Unblock:**
  1. Configure exactly ONE notary credential set (see `DEPLOYMENT.md`):
     **(a)** App Store Connect API key — `NOTARY_API_KEY_ID`,
     `NOTARY_API_ISSUER_ID`, `NOTARY_API_KEY_P8_BASE64` (recommended); **or**
     **(b)** Apple ID — `NOTARY_APPLE_ID`, `NOTARY_PASSWORD` (app-specific),
     `NOTARY_TEAM_ID`.
  2. Replace the notarize TODO stub in `release.yml` with the commented recipe
     already inline: `notarytool submit … --wait` → `stapler staple` → `stapler validate`.
  3. Cut the release: `git tag v1.0.0 && git push origin v1.0.0` → the `release`
     job (`needs: verify`) signs → archives → exports → DMG → notarizes → publishes.

### Signing environment — probed on this machine (2026-07-14)

Empirical state of the local signing setup (not assumptions):

| Check | Finding |
|-------|---------|
| Codesigning identities present | Only **`Apple Development: millercwalker@gmail.com (5SCU3Z72Z9)`** (×2). No `Developer ID Application` identity. (The keychain's *"Developer ID Certification Authority"* is Apple's intermediate CA, not a signing identity.) |
| Team of the available account | **`5SCU3Z72Z9`** (millercwalker@gmail.com) — the account the user designated as the credential holder. |
| Apple ID signed into Xcode | **No** — `IDEProvisioningTeams` absent; automatic provisioning errors *"No Account for Team 5SCU3Z72Z9."* |
| Provisioning profiles installed | **None** — so manual signing with the dev cert also fails. |
| Notary credential profile | **None** stored (`notarytool` profile lookup fails). |

**Config correction made this run:** the project/exportOptions/docs were pinned to
team **`2RZ7SBH74J`**, which matches **no** account or cert on this machine and
appears to be an unverified placeholder introduced in `241a7ed`. Reconciled to the
real, evidence-backed team **`5SCU3Z72Z9`** across `project.pbxproj`
(`DEVELOPMENT_TEAM`), `exportOptions.plist`, and docs. This removes a latent bug
that would have broken the signed build even after a Developer ID cert was created.

### Decisions to surface to the user
- **Is `millercwalker@gmail.com` (team `5SCU3Z72Z9`) enrolled in the *paid* Apple
  Developer Program?** A free personal team yields only the `Apple Development`
  certs seen here and **cannot** create a `Developer ID Application` cert or
  notarize. Paid enrollment is the true gate for both remaining blockers.
- **Confirm `5SCU3Z72Z9` is the publishing account** (config now reflects it). If
  a different org account is intended, say which and it will be re-pinned.
- **To unblock local signing**, either sign `millercwalker@gmail.com` into Xcode
  (Settings → Accounts) so profiles/certs sync, or export the `Developer ID
  Application` cert + key as a `.p12` for CI (see `DEPLOYMENT.md`).
- **Pro purchase channel + price** for the offline license key is still
  undecided (website `#download` gated until then). Not a build blocker.

---

## How this was verified

- Build / test / lint re-run this audit via the registered mission tools (results above).
- Artifact: `shasum -a 256 dist/*.dmg` matches the recorded fact — **not rebuilt** (nothing changed).
- Source claims spot-checked: `grep` confirms 0 `PaymentService` refs / 0 StoreKit imports; pbxproj bundle id confirmed.
- Git tree clean at `78ed961`; docs edited this run to remove contradictions with shipped state.
