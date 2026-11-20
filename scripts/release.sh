#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-1.1.0}"
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
cat > "$ROOT_DIR/repo.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<extensions>
  <details>
    <title lang="EN">Home Assistant Screensaver for Lyrion Music Server</title>
  </details>
  <plugins>
    <plugin name="HAScreenSaver" version="${VERSION}" minTarget="8.0" maxTarget="*" icon="https://raw.githubusercontent.com/${GITHUB_REPO}/main/server-plugin/HAScreenSaver/HTML/EN/plugins/HAScreenSaver/html/images/icon.png">
      <title lang="EN">Home Assistant Screensaver</title>
      <desc lang="EN">Stateless live proxy serving Home Assistant sensor states, weather condition, door/alert status, and radio alarm status to the Home Assistant Clock screensaver applet on Squeezebox Radio / UE Smart Radio, with zero long-term caching.</desc>
      <url>https://github.com/${GITHUB_REPO}/releases/download/${TAG}/HAScreenSaver-plugin-${TAG}.zip</url>
      <sha>${PLUGIN_SHA1}</sha>
      <creator>Nornode</creator>
      <link>https://github.com/${GITHUB_REPO}</link>
      <category>misc</category>
    </plugin>
  </plugins>
  <applets>
    <applet name="HAScreenSaver"
            creator="Nornode"
            link="https://github.com/${GITHUB_REPO}"
            minTarget="7.7"
            maxTarget="*"
            target="baby|fab4|jive|squeezeplay"
            version="${VERSION}"
            url="https://github.com/${GITHUB_REPO}/releases/download/${TAG}/HAScreenSaver-applet-${TAG}.zip"
            sha="${APPLET_SHA1}">
      <title lang="EN">Home Assistant Clock</title>
      <desc lang="EN">Dark-shaded digital clock screensaver for Squeezebox Radio with bottom-center weather icon, up to 4 live Home Assistant sensors, subtle radio alarm indicator, and optional door/alert banner. Zero long-term caching.</desc>
    </applet>
  </applets>
</extensions>
XML

echo "==> Release artifacts ready:"
echo "    Plugin zip : $PLUGIN_ZIP (SHA-1: $PLUGIN_SHA1)"
echo "    Applet zip : $APPLET_ZIP (SHA-1: $APPLET_SHA1)"
echo "    Manifest   : $ROOT_DIR/repo.xml"
