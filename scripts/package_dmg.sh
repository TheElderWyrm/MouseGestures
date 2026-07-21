#!/usr/bin/env bash
#
# package_dmg.sh — build MouseGestures (Release) and package it into a
# distributable .dmg, locally and reproducibly.
#
# Three modes:
#
#   • UNSIGNED (default, no --identity): plain Release build → DMG. Fine for local
#     verification and internal testing, but Gatekeeper blocks it on other users'
#     machines (not signed, not notarized).
#
#   • SIGNED (--identity "<Developer ID Application …>"): archive → exportArchive
#     (developer-id) → DMG. This is the notarization-READY path — it produces a
#     hardened-runtime app with a SECURE TIMESTAMP and WITHOUT the debug
#     `get-task-allow` entitlement (both of which a plain `xcodebuild build`
#     signature lacks, and both of which notarization requires). Gatekeeper still
#     rejects it as "Unnotarized Developer ID" until you also notarize (below).
#
#   • SIGNED + NOTARIZED (--identity … plus a notary credential): the above, then
#     `xcrun notarytool submit --wait` and `xcrun stapler staple`. Produces a
#     fully distributable DMG. Supply exactly ONE credential set via env:
#       API key (preferred):  NOTARY_API_KEY_P8 (path to .p8), NOTARY_API_KEY_ID,
#                             NOTARY_API_ISSUER_ID
#       Apple ID fallback:    NOTARY_APPLE_ID, NOTARY_PASSWORD (app-specific),
#                             NOTARY_TEAM_ID
#     …and pass --notarize.
#
# The publishing team is 2RZ7SBH74J (Developer ID Application: WALKER CARPENTER
# MILLER). The tagged CI release (.github/workflows/release.yml) runs the same
# archive→export→notarize→staple flow; see DEPLOYMENT.md.
#
# Usage:
#   ./scripts/package_dmg.sh [--identity "<codesign identity>"] [--notarize] [--output-dir DIR]
#
set -euo pipefail

# Run from the repo root regardless of where the script is invoked.
cd "$(dirname "$0")/.."

PROJECT="MouseGestures.xcodeproj"
SCHEME="MouseGestures"
CONFIG="Release"
DERIVED_DATA="${DERIVED_DATA:-build/dmg-derived-data}"
DIST_DIR="dist"
IDENTITY=""
NOTARIZE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --identity)   IDENTITY="$2"; shift 2 ;;
    --notarize)   NOTARIZE=1;    shift 1 ;;
    --output-dir) DIST_DIR="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ "$NOTARIZE" = "1" ] && [ -z "$IDENTITY" ]; then
  echo "ERROR: --notarize requires --identity (only a signed app can be notarized)." >&2
  exit 2
fi

BEAUTIFY() { command -v xcbeautify >/dev/null && xcbeautify || cat; }

if [ -z "$IDENTITY" ]; then
  # ── UNSIGNED: plain Release build ──────────────────────────────────────────
  echo "==> Building $SCHEME ($CONFIG, unsigned)…"
  rm -rf "$DERIVED_DATA"
  xcodebuild build \
    -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED_DATA" -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    | BEAUTIFY
  APP="$DERIVED_DATA/Build/Products/$CONFIG/MouseGestures.app"
else
  # ── SIGNED: archive → export (Developer ID, hardened, secure timestamp) ─────
  echo "==> Archiving $SCHEME ($CONFIG) signed with: $IDENTITY"
  ARCHIVE="$DERIVED_DATA/MouseGestures.xcarchive"
  EXPORT="$DERIVED_DATA/export"
  rm -rf "$DERIVED_DATA"
  xcodebuild archive \
    -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
    -archivePath "$ARCHIVE" -destination 'generic/platform=macOS' \
    ENABLE_HARDENED_RUNTIME=YES \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" \
    PROVISIONING_PROFILE_SPECIFIER="" OTHER_CODE_SIGN_FLAGS="--timestamp" \
    | BEAUTIFY
  echo "==> Exporting (developer-id) via exportOptions.plist…"
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist exportOptions.plist \
    -exportPath "$EXPORT" \
    | BEAUTIFY
  APP="$EXPORT/MouseGestures.app"
fi

[ -d "$APP" ] || { echo "ERROR: built app not found at $APP" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
SUFFIX=""; [ -z "$IDENTITY" ] && SUFFIX="-unsigned"
DMG="$DIST_DIR/MouseGestures-${VERSION}${SUFFIX}.dmg"

echo "==> Staging disk-image contents…"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"   # drag-to-install target

echo "==> Creating ${DMG}…"
mkdir -p "$DIST_DIR"
rm -f "$DMG"
hdiutil create \
  -volname "MouseGestures" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG" >/dev/null

# notarytool only requires the *contents* to be signed, but the Gatekeeper
# "primary signature" assessment (and what end users' Gatekeeper checks on
# first open) evaluates the disk image's own signature. Sign the container
# itself with the same Developer ID identity used for the app, or an
# unsigned UDIF notarizes fine but is rejected at that check.
if [ -n "$IDENTITY" ]; then
  echo "==> Signing the DMG container…"
  codesign --sign "$IDENTITY" --timestamp "$DMG"
  codesign --verify --verbose "$DMG"
fi

# ── Optional: notarize the DMG and staple the ticket ─────────────────────────
if [ "$NOTARIZE" = "1" ]; then
  echo "==> Notarizing ${DMG}…"
  if [ -n "${NOTARY_API_KEY_P8:-}" ]; then
    xcrun notarytool submit "$DMG" \
      --key "$NOTARY_API_KEY_P8" \
      --key-id "${NOTARY_API_KEY_ID:?NOTARY_API_KEY_ID required}" \
      --issuer "${NOTARY_API_ISSUER_ID:?NOTARY_API_ISSUER_ID required}" \
      --wait
  elif [ -n "${NOTARY_APPLE_ID:-}" ]; then
    xcrun notarytool submit "$DMG" \
      --apple-id "$NOTARY_APPLE_ID" \
      --password "${NOTARY_PASSWORD:?NOTARY_PASSWORD required}" \
      --team-id "${NOTARY_TEAM_ID:?NOTARY_TEAM_ID required}" \
      --wait
  else
    echo "ERROR: --notarize set but no credentials. Provide either NOTARY_API_KEY_P8" >&2
    echo "       (+ NOTARY_API_KEY_ID, NOTARY_API_ISSUER_ID) or NOTARY_APPLE_ID" >&2
    echo "       (+ NOTARY_PASSWORD, NOTARY_TEAM_ID)." >&2
    exit 2
  fi
  echo "==> Stapling notarization ticket…"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi

echo "==> Done."
echo "    DMG:     $DMG"
echo "    Version: $VERSION"
echo "    SHA-256: $(shasum -a 256 "$DMG" | awk '{print $1}')"
if [ -z "$IDENTITY" ]; then
  echo "    NOTE: unsigned — not distributable to end users until signed + notarized."
elif [ "$NOTARIZE" != "1" ]; then
  echo "    NOTE: signed + notarization-READY, but NOT notarized. Gatekeeper will"
  echo "          reject it ('Unnotarized Developer ID') until you re-run with"
  echo "          --notarize and a notary credential (see header)."
fi
