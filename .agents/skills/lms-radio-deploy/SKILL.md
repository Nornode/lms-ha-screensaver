---
name: lms-radio-deploy
description: >-
  Runbook and scripts for building, testing, deploying to a local Lyrion Music Server
  (including the pssc/ha-addon-lms Home Assistant add-on), fast SSH iteration on a single
  Squeezebox Radio, and local LAN distribution via Applet Installer.
---

# LMS & Squeezebox Radio Build, Deploy, and Distribution Skill

Use this skill when packaging, testing, deploying to LMS, testing on a physical Squeezebox Radio, or preparing a public release.

## 1. Local Environment Setup (Never Commit Secrets)

Copy `.env.example` to `.env.local` (gitignored) and set your local targets:

```bash
LMS_HOST=192.168.x.x          # IP or hostname of your Lyrion Music Server
LMS_PORT=9000                 # Default LMS web/JSON-RPC port
LMS_SSH_HOST=user@ha-host     # SSH target for HA / LMS host
LMS_PLUGINS_DIR=/config/lms/cache/InstalledPlugins/Plugins
RADIO_IP=192.168.x.y          # IP of your test Squeezebox Radio
```

## 2. Build & Test Locally

```bash
./scripts/test.sh     # Perl syntax + unit tests, Lua 5.1 compatibility + unit tests
./scripts/build.sh    # Builds dist/HAScreenSaver.zip + copies into LMS plugin AppletDist/
```

`build.sh` ensures the zip has `HAScreenSaver/` at the archive root (required by SqueezePlay `AppletInstaller`) and computes its lowercase SHA-1 digest.

## 3. Deploy Plugin to Lyrion Music Server

```bash
./scripts/deploy-lms.sh
```

- Runs `build.sh` first so the bundled applet zip is always up to date.
- Syncs `server-plugin/HAScreenSaver/` to `$LMS_SSH_HOST:$LMS_PLUGINS_DIR/HAScreenSaver`.
- Restart the LMS add-on/service to load Perl changes, then check LMS logs:
  ```bash
  ssh "$LMS_SSH_HOST" "tail -n 60 /config/lms/logs/server.log"
  ```
- Verify live JSON-RPC and self-hosted `repo.xml`:
  ```bash
  ./scripts/test-lms-rpc.sh
  ```

## 4. Fast Dev-Loop Testing on a Single Squeezebox Radio (SSH)

Enable SSH on your test radio once: **Settings → Advanced → Remote Login → Enable** (user `root`, default password `1234`).

```bash
./scripts/deploy-radio.sh
```

This streams `radio-applet/HAScreenSaver/` over SSH (`tar` over `ssh`, since SqueezeOS Dropbear lacks SFTP for modern `scp` and legacy `ssh-rsa` flags are required) into `/usr/share/jive/applets/HAScreenSaver` on `$RADIO_IP` and restarts Jive (`killall jive`) in a single SSH connection so changes appear within ~10 seconds without rebooting the radio.

To view live Lua logs on the radio:
```bash
ssh root@"$RADIO_IP" "tail -f /var/log/messages"
```

## 5. Local LAN Distribution to All Radios (Applet Installer)

1. Open LMS Web UI → **Settings → Plugins** (or **Manage Plugins**).
2. Under **Additional Repositories**, add:
   ```text
   http://<LMS_HOST>:9000/plugins/HAScreenSaver/repo.xml
   ```
3. Click **Apply** and restart LMS if prompted.
4. On any Squeezebox Radio:
   - Go to **Settings → Advanced → Applet Installer**.
   - Uncheck **Recommended Applets Only**.
   - Select **HA Screensaver** → **Install** (the radio downloads the `.zip`, verifies SHA-1, installs, and restarts).
5. Select the screensaver under **Settings → Screen → Screensavers** (for When Off / When Stopped / When Playing).

## 6. Pre-Release Security & Hygiene Checklist

Before tagging a public release:
- Run `./scripts/test.sh` and confirm 100% pass.
- Run `git status` and `git grep -iE '(bearer |eyJ[a-zA-Z0-9_-]{20,}|password|192\.168\.[0-9]+\.[0-9]+|10\.[0-9]+\.[0-9]+\.[0-9]+)'` to verify zero secrets or private LAN IPs exist in tracked files.
