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
# SqueezePlay's SetupAppletInstaller:
#   1. Creates <appletdir>/HAScreenSaver/ itself and extracts directly inside it.
#   2. Has a bug in _zipSink() where any directory entry sets fh = 'DIR' and the
#      next entry crashes calling fh:close() on the string 'DIR', hanging the
#      "Downloading Applets" popup forever.
# Therefore ALL applet files MUST live flat at the archive root with ZERO subdirectories.
(
    cd "$ROOT_DIR/radio-applet/HAScreenSaver"
    zip -rq "$ZIP_FILE" \
        HAScreenSaverApplet.lua \
        HAScreenSaverMeta.lua \
        HAScreenSaverModel.lua \
        strings.txt \
        *.png \
        -x "*.DS_Store" "*~"
)

# Guard against any subdirectory entry (prevents SqueezePlay _zipSink fh='DIR' crash)
if unzip -Z1 "$ZIP_FILE" | grep -q '/'; then
    echo "ERROR: Applet zip must be completely flat (zero subdirectories) for SqueezePlay AppletInstaller" >&2
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
