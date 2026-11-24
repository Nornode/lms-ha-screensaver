#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-2.0.1}"
GITHUB_REPO="${2:-Nornode/lms-ha-screensaver}"
TAG="v${VERSION}"
DIST_DIR="$ROOT_DIR/dist"

echo "==> 1. Running test suite..."
"$ROOT_DIR/scripts/test.sh"

echo "==> 2. Building applet zip..."
"$ROOT_DIR/scripts/build.sh"

APPLET_ZIP="$DIST_DIR/HAScreenSaver-applet-${TAG}.zip"
PLUGIN_ZIP="$DIST_DIR/HAScreenSaver-plugin-${TAG}.zip"

cp "$DIST_DIR/HAScreenSaver.zip" "$APPLET_ZIP"
APPLET_SHA1="$(shasum -a 1 "$APPLET_ZIP" | awk '{print $1}')"

echo "==> 3. Packaging LMS server plugin -> $PLUGIN_ZIP"
rm -f "$PLUGIN_ZIP"
(
    cd "$ROOT_DIR/server-plugin"
    zip -rq "$PLUGIN_ZIP" HAScreenSaver -x "*.DS_Store" "*~"
)
PLUGIN_SHA1="$(shasum -a 1 "$PLUGIN_ZIP" | awk '{print $1}')"

echo "==> 4. Generating root repo.xml for ${GITHUB_REPO} (${TAG})..."
# Note: The radio applet is intentionally NOT listed here with an https:// GitHub URL,
# because Squeezebox Radio's SetupAppletInstaller uses plain-HTTP SocketHttp (no TLS).
# Instead, the LMS plugin bundles AppletDist/HAScreenSaver.zip and registers a native
# Slim::Control::Jive extension provider so radios download the applet over plain HTTP
# directly from their local LMS server via relurl="/plugins/HAScreenSaver/HAScreenSaver.zip".
cat > "$ROOT_DIR/repo.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<extensions>
  <details>
    <title lang="EN">Home Assistant Screensaver for Lyrion Music Server</title>
  </details>
  <plugins>
    <plugin name="HAScreenSaver" version="${VERSION}" minTarget="8.0" maxTarget="*" icon="https://raw.githubusercontent.com/${GITHUB_REPO}/main/server-plugin/HAScreenSaver/HTML/EN/plugins/HAScreenSaver/html/images/icon.png">
      <title lang="EN">Home Assistant Screensaver</title>
      <desc lang="EN">Stateless live proxy serving Home Assistant sensor states, weather condition, door/alert status, and radio alarm status to the Home Assistant Clock screensaver applet on Squeezebox Radio, Squeezebox Controller, Squeezebox Touch, and Jivelite, with zero long-term caching. Automatically serves the applet over plain local HTTP to Applet Installer.</desc>
      <url>https://github.com/${GITHUB_REPO}/releases/download/${TAG}/HAScreenSaver-plugin-${TAG}.zip</url>
      <sha>${PLUGIN_SHA1}</sha>
      <creator>Nornode</creator>
      <link>https://github.com/${GITHUB_REPO}</link>
      <category>misc</category>
    </plugin>
  </plugins>
</extensions>
XML

echo "==> Release artifacts ready:"
echo "    Plugin zip : $PLUGIN_ZIP (SHA-1: $PLUGIN_SHA1)"
echo "    Applet zip : $APPLET_ZIP (SHA-1: $APPLET_SHA1)"
echo "    Manifest   : $ROOT_DIR/repo.xml"
