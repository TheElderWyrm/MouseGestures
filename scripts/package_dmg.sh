#!/usr/bin/env bash
#
# package_dmg.sh — build MouseGestures (Release) and package it into a
# distributable .dmg, locally and reproducibly.
#
# Default: produces an UNSIGNED DMG. This works today (before Apple Developer
# enrollment completes) and is fine for local verification and internal testing,
# but Gatekeeper will warn/block it on other users' machines until the DMG is
# signed with a Developer ID cert AND notarized. The signed + notarized release
# is produced by .github/workflows/release.yml on a version tag; see DEPLOYMENT.md.
#
# Once a "Developer ID Application" cert is in your keychain you can sign locally:
#   ./scripts/package_dmg.sh --identity "Developer ID Application: NAME (2RZ7SBH74J)"
# (notarization is still a separate `xcrun notarytool` step — see DEPLOYMENT.md).
#
# Usage:
#   ./scripts/package_dmg.sh [--identity "<codesign identity>"] [--output-dir DIR]
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

while [ $# -gt 0 ]; do
  case "$1" in
    --identity)   IDENTITY="$2"; shift 2 ;;
    --output-dir) DIST_DIR="$2";  shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

echo "==> Building $SCHEME ($CONFIG)…"
rm -rf "$DERIVED_DATA"
if [ -z "$IDENTITY" ]; then
  echo "    (unsigned build — no --identity given)"
  xcodebuild build \
    -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED_DATA" -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    | (command -v xcbeautify >/dev/null && xcbeautify || cat)
else
  echo "    (signing with: $IDENTITY)"
  xcodebuild build \
    -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
    -derivedDataPath "$DERIVED_DATA" -destination 'platform=macOS' \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" \
    | (command -v xcbeautify >/dev/null && xcbeautify || cat)
fi

APP="$DERIVED_DATA/Build/Products/$CONFIG/MouseGestures.app"
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

echo "==> Done."
echo "    DMG:     $DMG"
echo "    Version: $VERSION"
echo "    SHA-256: $(shasum -a 256 "$DMG" | awk '{print $1}')"
[ -z "$IDENTITY" ] && echo "    NOTE: unsigned — not distributable to end users until signed + notarized."
