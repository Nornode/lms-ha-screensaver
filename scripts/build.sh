#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DIST_DIR="$ROOT_DIR/dist"
APPLET_DIST_DIR="$ROOT_DIR/server-plugin/HAScreenSaver/AppletDist"
ZIP_FILE="$DIST_DIR/HAScreenSaver.zip"

mkdir -p "$DIST_DIR" "$APPLET_DIST_DIR"
rm -f "$ZIP_FILE"

echo "==> Packaging radio-applet/HAScreenSaver -> $ZIP_FILE"
(
    cd "$ROOT_DIR/radio-applet"
    zip -rq "$ZIP_FILE" HAScreenSaver -x "*.DS_Store" "*~"
)

SHA1="$(shasum -a 1 "$ZIP_FILE" | awk '{print $1}')"
echo "$SHA1" > "$DIST_DIR/HAScreenSaver.zip.sha1"

cp "$ZIP_FILE" "$APPLET_DIST_DIR/HAScreenSaver.zip"
echo "$SHA1" > "$APPLET_DIST_DIR/HAScreenSaver.zip.sha1"

echo "==> Verifying zip structure (must have HAScreenSaver/ at root):"
unzip -l "$ZIP_FILE"
echo "==> SHA-1: $SHA1"
echo "==> Copied to server-plugin/HAScreenSaver/AppletDist/HAScreenSaver.zip"
