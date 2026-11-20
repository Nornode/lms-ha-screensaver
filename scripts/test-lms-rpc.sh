#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f "$ROOT_DIR/.env.local" ]]; then
    # shellcheck disable=SC1091
    source "$ROOT_DIR/.env.local"
fi

: "${LMS_HOST:?Set LMS_HOST in .env.local or environment (e.g. 192.168.1.10)}"
LMS_PORT="${LMS_PORT:-9000}"
BASE_URL="http://${LMS_HOST}:${LMS_PORT}"

echo "==> 1. Testing live JSON-RPC: hascreensaver sensors"
curl -sS -X POST "${BASE_URL}/jsonrpc.js" \
    -H "Content-Type: application/json" \
    -d '{"id":1,"method":"slim.request","params":["",["hascreensaver","sensors"]]}'
echo ""

echo "==> 2. Testing self-hosted repo.xml"
curl -sS "${BASE_URL}/plugins/HAScreenSaver/repo.xml"
echo ""

echo "==> 3. Checking HAScreenSaver.zip download & SHA-1"
TMP_ZIP="$(mktemp)"
trap 'rm -f "$TMP_ZIP"' EXIT
curl -sSf "${BASE_URL}/plugins/HAScreenSaver/HAScreenSaver.zip" -o "$TMP_ZIP"
echo "    Downloaded $(wc -c < "$TMP_ZIP" | tr -d ' ') bytes, SHA-1: $(shasum -a 1 "$TMP_ZIP" | awk '{print $1}')"
