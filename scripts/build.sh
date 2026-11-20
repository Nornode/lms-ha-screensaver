#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

DIST_DIR="$ROOT_DIR/dist"
APPLET_DIST_DIR="$ROOT_DIR/server-plugin/HAScreenSaver/AppletDist"
ZIP_FILE="$DIST_DIR/HAScreenSaver.zip"

mkdir -p "$DIST_DIR" "$APPLET_DIST_DIR"
rm -f "$ZIP_FILE"

echo "==> Packaging radio-applet/HAScreenSaver contents -> $ZIP_FILE"
# SqueezePlay's SetupAppletInstaller creates <appletdir>/HAScreenSaver/ itself
# and extracts archive entries directly inside it (dir .. chunk.filename).
# Files MUST therefore live at the archive root (no leading HAScreenSaver/ folder).
(
    cd "$ROOT_DIR/radio-applet/HAScreenSaver"
    zip -rq "$ZIP_FILE" \
        HAScreenSaverApplet.lua \
        HAScreenSaverMeta.lua \
        HAScreenSaverModel.lua \
        strings.txt \
        icons \
        -x "*.DS_Store" "*~"
)

# Guard against double-nested HAScreenSaver/HAScreenSaver/ extraction
if unzip -Z1 "$ZIP_FILE" | grep -q '^HAScreenSaver/'; then
    echo "ERROR: Applet zip must have HAScreenSaverApplet.lua at root, not under HAScreenSaver/" >&2
    exit 1
fi

SHA1="$(shasum -a 1 "$ZIP_FILE" | awk '{print $1}')"
echo "$SHA1" > "$DIST_DIR/HAScreenSaver.zip.sha1"

cp "$ZIP_FILE" "$APPLET_DIST_DIR/HAScreenSaver.zip"
echo "$SHA1" > "$APPLET_DIST_DIR/HAScreenSaver.zip.sha1"

echo "==> Verifying zip structure (files must be at archive root for AppletInstaller):"
unzip -l "$ZIP_FILE"
echo "==> SHA-1: $SHA1"
echo "==> Copied to server-plugin/HAScreenSaver/AppletDist/HAScreenSaver.zip"
