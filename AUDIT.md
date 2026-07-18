# MouseGestures — Deployment-Readiness Audit

**Date:** 2026-07-18 · **Commit:** `dc8fe4c` (clean tree) · **Toolchain:** Xcode 26.6 / Swift 6.3.3

Single go/no-go sheet for the original directive: *audit state, clean reproducible
build, tests/lint pass, resolve packaging/config/dependency gaps, document run &
deploy, produce a verified deployable artifact, surface credential decisions.*

---

## Verdict

- 🟢 **GO for the achievable (cert-independent) tier.** The tree builds, tests,
  and lints green; config/packaging/dependency gaps are all closed; docs are
  consistent; and a verified **unsigned** DMG exists and installs locally.
- 🟡 **NO-GO for a shippable (end-user) release** — now blocked on a **single
  credential item**: a **notarization credential** (App Store Connect API key or
  Apple ID app-specific password for team `2RZ7SBH74J`). Paid enrollment is
  confirmed and the Developer ID Application cert is in the keychain, so a
  **local signed (notarization-ready) DMG builds today**; only Apple notarization
  remains. No code, config, or design work remains. Steps to unblock are below.

---

## Readiness checklist

| # | Criterion | State | Evidence |
|---|-----------|-------|----------|
| 1 | Reproducible unsigned build | 🟢 GREEN | `xcodebuild build … CODE_SIGNING_ALLOWED=NO` → **BUILD SUCCEEDED** (tool `mousegestures-build-verify`) |
| 2 | Unit tests pass | 🟢 GREEN | `xcodebuild test` → **TEST SUCCEEDED**, **30 tests / 0 failures** (tool `mousegestures-test`) |
| 3 | Lint clean vs baseline | 🟢 GREEN | SwiftLint 0.65.0 `--strict --baseline` → **0 violations, 0 serious in 115 files** (tool `mousegestures-lint`) |
| 4 | Dependencies | 🟢 GREEN | No third-party packages; system frameworks only (StoreKit dependency removed) |
| 5 | Deploy-target fork resolved | 🟢 GREEN | (B) Direct DMG chosen (user, 2026-07-13); StoreKit IAP removed `4e5a952` — 0 `PaymentService` refs, 0 StoreKit imports; Pro = offline HMAC license key |
| 6 | Signing config (project settings) | 🟢 GREEN | bundle id `com.mousegestures.MouseGestures`; `ENABLE_HARDENED_RUNTIME=YES` (Release); entitlements file present (apple-events only, sandbox off by design); exportOptions `method=developer-id`, `teamID=2RZ7SBH74J` aligned with pbxproj (the PAID team holding the Developer ID cert) |
| 7 | Verified deployable artifact | 🟢 GREEN | **Signed** `dist/MouseGestures-1.0.dmg` produced 2026-07-18 via `package_dmg.sh --identity` — SHA-256 `998f4e49…b48b`; `codesign --verify --deep --strict` = *valid + satisfies Designated Requirement*, chain `Developer ID Application (2RZ7SBH74J) → Developer ID CA → Apple Root CA`, `flags=runtime` (hardened), secure Timestamp present; `spctl` = *rejected: Unnotarized Developer ID* (correct — only notarization remains). Prior unsigned `MouseGestures-1.0-unsigned.dmg` (SHA-256 `63d843f9…f2a573`) also retained. (dist/ is gitignored) |
| 8 | Docs: run + deploy | 🟢 GREEN | `README.md` (build/run/test/lint/permissions), `DEPLOYMENT.md` (release runbook + secrets + notarization), `PROJECT_NOTES.md` — reconciled to shipped state this audit (removed stale StoreKit/placeholder/"19 tests"/unresolved-fork text) |
| 9 | CI | 🟢 GREEN | `ci.yml` = build+test+lint, no secrets; `release.yml` verify job = signing-free build proof |
| 10 | **Developer ID cert** | 🟢 GREEN | `Developer ID Application: WALKER CARPENTER MILLER (2RZ7SBH74J)` present in keychain (paid enrollment confirmed 2026-07-18) — local signed build now possible |
| 11 | **Notarization creds + CI signing secrets** | 🔴 GATED | See Blocker 2 — narrowed to the notary credential + (for CI) exporting the cert as `.p12` secrets |
| 12 | Website download link live | ⏸️ PARKED | `#download` is a gated placeholder (Option-B aligned `3144c8f`); flips live when the signed DMG ships |
| 13 | Updater `version.json` repo | ⏸️ PARKED | Requires public `github.com/eldritchbookwyrm/MouseGestures` repo + `version.json` at first release |

---

## Remaining blockers (exact unblock steps)

Blocker 1 (Developer ID cert) is now **RESOLVED** — paid enrollment confirmed and
the cert is in the keychain. The one remaining gate is the **notarization
credential** (and, for the CI path, exporting the cert as `.p12` secrets).

### Blocker 1 — Developer ID Application certificate ✅ RESOLVED (2026-07-18)
- Paid Apple Developer Program enrollment **confirmed** (user, 2026-07-18).
- `Developer ID Application: WALKER CARPENTER MILLER (2RZ7SBH74J)` is present in
  the login keychain and is a valid codesigning identity.
- **Local signed (notarization-ready) build now works:**
  `./scripts/package_dmg.sh --identity "Developer ID Application: WALKER CARPENTER MILLER (2RZ7SBH74J)"`
  → archive → export (developer-id) → hardened, secure-timestamped, no
  `get-task-allow` → DMG. (Add `--notarize` + a notary credential for a fully
  distributable artifact.)
- For CI: export the cert+key as `.p12`; set `SIGNING_CERTIFICATE_P12_BASE64`,
  `SIGNING_CERTIFICATE_PASSWORD`, `KEYCHAIN_PASSWORD` (see `DEPLOYMENT.md`).

### Blocker 2 — Notarization credentials (the last gate)
- **What it gates:** notarize + staple. Without it a signed DMG is still rejected
  by Gatekeeper as *"Unnotarized Developer ID"* end-user-side. (`release.yml` now
  implements the real notarize+staple step — no longer a stub — but it needs the
  credential below.)
- **Unblock:** configure exactly ONE notary credential set (see `DEPLOYMENT.md`):
  **(a)** App Store Connect API key — `NOTARY_API_KEY_ID`, `NOTARY_API_ISSUER_ID`,
  `NOTARY_API_KEY_P8_BASE64` (recommended); **or** **(b)** Apple ID —
  `NOTARY_APPLE_ID`, `NOTARY_PASSWORD` (app-specific), `NOTARY_TEAM_ID`
  (`= 2RZ7SBH74J`). No such credential is stored locally yet (`notarytool` profile
  lookup fails).
- **Cut the release:** `git tag v1.0.0 && git push origin v1.0.0` → the `release`
  job (`needs: verify`) signs → archives → exports → DMG → notarizes → staples → publishes.

### Signing environment — re-probed on this machine (2026-07-18)

Empirical state of the local signing setup (not assumptions):

| Check | Finding |
|-------|---------|
| Codesigning identities present | **`Developer ID Application: WALKER CARPENTER MILLER (2RZ7SBH74J)`** ✅, plus `Apple Distribution` / `Developer ID Installer` / `3rd Party Mac Developer Installer` (all `2RZ7SBH74J`), and dev-only `Apple Development` certs (`5SCU3Z72Z9` and `2RZ7SBH74J`). |
| Publishing team | **`2RZ7SBH74J`** (WALKER CARPENTER MILLER) — the only team registered in Xcode (`IDEProvisioningTeamByIdentifier`), `isFreeProvisioningTeam=0` (PAID), holds the Developer ID cert. `5SCU3Z72Z9` is the same Apple ID's FREE personal team (Apple Development only). |
| Apple ID signed into Xcode | **Yes** — `IDEProvisioningTeamManagerLastSelectedTeamID = 2RZ7SBH74J`. |
| Notary credential profile | **None** stored yet (`notarytool` requires `--key`/`--apple-id` creds) — this is Blocker 2. |

**Team-ID reconciliation (this audit):** an earlier run (`2b10e99`) had switched
config from `2RZ7SBH74J` to `5SCU3Z72Z9`, believing `2RZ7SBH74J` was an unverified
placeholder — a conclusion drawn on 2026-07-14 *before* the Developer ID cert
existed. The live keychain + Xcode state now show `2RZ7SBH74J` is the real paid
publishing team holding the Developer ID cert, so config was reverted to
`2RZ7SBH74J` across `project.pbxproj`, `exportOptions.plist`, and docs (`dc8fe4c`).
Per the user's steering note, team identity is decided by what is actually signed
into Xcode + holds the certs locally, not by portal/API reads that lag enrollment.

### Decisions to surface to the user
- **Notarization credential (last gate):** provide ONE of — an App Store Connect
  API key (`.p8` + key-id + issuer-id) or an Apple ID app-specific password for
  team `2RZ7SBH74J`. Everything else for a signed+notarized DMG is in place.
- **Pro purchase channel + price** for the offline license key is still
  undecided (website `#download` gated until then). Not a build blocker.

---

## How this was verified

- Build / test / lint re-run this audit via the registered mission tools (results above).
- Artifact: `shasum -a 256 dist/*.dmg` matches the recorded fact — **not rebuilt** (nothing changed).
- Source claims spot-checked: `grep` confirms 0 `PaymentService` refs / 0 StoreKit imports; pbxproj bundle id confirmed.
- Signing env re-probed 2026-07-18 (`security find-identity -v -p codesigning`, Xcode `IDEProvisioningTeamByIdentifier`): Developer ID Application cert for `2RZ7SBH74J` present; team `2RZ7SBH74J` signed into Xcode + paid.
- Git tree clean at `dc8fe4c` (real Developer ID signing + notarization wired); docs edited this run to remove contradictions with shipped state.
