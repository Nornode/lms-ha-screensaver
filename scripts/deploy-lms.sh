#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f "$ROOT_DIR/.env.local" ]]; then
    # shellcheck disable=SC1091
    source "$ROOT_DIR/.env.local"
fi

: "${LMS_SSH_HOST:?Set LMS_SSH_HOST in .env.local or environment (e.g. root@homeassistant.local)}"
LMS_PLUGINS_DIR="${LMS_PLUGINS_DIR:-/config/lms/cache/InstalledPlugins/Plugins}"

echo "==> Building applet package first..."
"$ROOT_DIR/scripts/build.sh"

REMOTE_DIR="${LMS_PLUGINS_DIR}/HAScreenSaver"
echo "==> Deploying LMS plugin to ${LMS_SSH_HOST}:${REMOTE_DIR}"

ssh "$LMS_SSH_HOST" "mkdir -p '${REMOTE_DIR}'"
rsync -avz --delete \
    --exclude '.DS_Store' \
    "$ROOT_DIR/server-plugin/HAScreenSaver/" \
    "${LMS_SSH_HOST}:${REMOTE_DIR}/"

echo "==> Deployment complete!"
echo "Next steps:"
echo "  1. Restart your Lyrion Music Server (or HA LMS add-on) to load Perl changes."
echo "  2. Run ./scripts/test-lms-rpc.sh to verify live JSON-RPC and repo.xml."
