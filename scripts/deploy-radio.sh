#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f "$ROOT_DIR/.env.local" ]]; then
    # shellcheck disable=SC1091
    source "$ROOT_DIR/.env.local"
fi

: "${RADIO_IP:?Set RADIO_IP in .env.local or environment (e.g. 192.168.1.20)}"
RADIO_SSH_USER="${RADIO_SSH_USER:-root}"
REMOTE_APPLET_DIR="/usr/share/jive/applets/HAScreenSaver"

# Squeezebox Radio runs legacy Dropbear SSH; allow ssh-rsa / legacy kex if needed
SSH_OPTS=(
    -o HostKeyAlgorithms=+ssh-rsa
    -o PubkeyAcceptedAlgorithms=+ssh-rsa
)
if [[ -n "${RADIO_SSH_JUMP:-}" ]]; then
    SSH_OPTS+=(-J "$RADIO_SSH_JUMP")
fi
if [[ -n "${RADIO_SSH_KEY:-}" ]]; then
    SSH_OPTS+=(-i "$RADIO_SSH_KEY")
fi

echo "==> Pushing radio-applet/HAScreenSaver to ${RADIO_SSH_USER}@${RADIO_IP}:${REMOTE_APPLET_DIR} and restarting SqueezePlay..."
echo "    (Enter radio SSH password when prompted — default is 1234)"
COPYFILE_DISABLE=1 tar --no-xattrs --format ustar -cf - -C "$ROOT_DIR/radio-applet/HAScreenSaver" . | \
    ssh "${SSH_OPTS[@]}" "${RADIO_SSH_USER}@${RADIO_IP}" \
        "rm -rf /etc/squeezeplay/userpath/applets/HAScreenSaver '${REMOTE_APPLET_DIR}' && mkdir -p '${REMOTE_APPLET_DIR}' && tar -xf - -C '${REMOTE_APPLET_DIR}' && (killall jive || /etc/init.d/squeezeplay restart)"

echo "==> Done! Select 'Home Assistant Clock' under Settings > Screen > Screensavers on your radio."
