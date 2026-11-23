# Project Guidelines: LMS HA ScreenSaver

This repository contains an open-source **Lyrion Music Server (LMS)** plugin (`server-plugin/HAScreenSaver/`) and a **SqueezePlay / Squeezebox Radio** Lua screensaver applet (`radio-applet/HAScreenSaver/`) that displays a crisp digital clock, radio alarm indicator, optional door/alert banner, and up to 4 live Home Assistant sensor values.

## Non-Negotiable Architecture Rules

1. **Zero Long-Term Caching (LMS & Radio)**
   - **LMS Plugin (`Plugin.pm`)**: Always fetch Home Assistant states live via `Slim::Networking::SimpleAsyncHTTP` with `cache => 0` and `Cache-Control: no-cache`. NEVER store sensor values in `Slim::Utils::Cache`, SQLite, disk files, or `Slim::Utils::Prefs`. Only static user configuration (entity IDs, labels, formatting, poll interval, font, optional HA URL/token) belongs in prefs.
   - **Radio Applet (`HAScreenSaverApplet.lua`)**: Hold sensor values strictly in transient in-memory widget/table state while the screensaver window is active. NEVER write sensor values to `/etc/squeezeplay/userpath/` flash storage. Clear stale readings to `--` if no fresh response arrives within `2.5 * poll_interval`. Clear all transient sensor state and stop timers on window close/deactivation.

2. **Lua 5.1 Compatibility (Squeezebox Radio / SqueezeOS `baby`)**
   - Squeezebox Radio runs **Lua 5.1** on embedded hardware (~64 MB RAM).
   - Never use Lua 5.2+ syntax: no `goto`, no `//` integer division, no bitwise operators (`&`, `|`, `~`, `<<`, `>>`), no `<const>`/`<close>` attributes, no `table.unpack` without fallback.
   - Always stop `Timer` instances and remove listeners on `EVENT_WINDOW_CLOSED` / `EVENT_WINDOW_INACTIVE` to prevent memory leaks.

3. **Non-Blocking Perl in LMS**
   - Always use `use strict; use warnings;`.
   - Never perform synchronous blocking HTTP calls (`LWP::Simple`, blocking sockets) inside LMS request handlers. Always use `Slim::Networking::SimpleAsyncHTTP` and `$request->setStatusProcessing()` / `$request->setStatusDone()`.

4. **320×240 Landscape & 240×320 Portrait Readability**
   - The digital clock (`HH:MM`, no seconds, no date) is the primary element and must remain large, high-contrast, and legible across a room on both landscape (`baby` 320×240, `fab4` 480×272) and portrait (`jive` 240×320) screens.
   - The alarm indicator reflects the alarm state of the active/controlled player (or clears cleanly when no player is selected on a Controller).
   - The optional alert/text sensor (e.g. open door contacts) only renders when active/non-empty so the display stays uncluttered during normal operation.

5. **Public Release & Zero Secrets**
   - NEVER commit personal hostnames, LAN IP addresses, Home Assistant tokens, SSH keys/passwords, or personal entity names.
   - All local deployment targets must be configured via environment variables or gitignored `.env.local`.

## Workspace Skills

Load the relevant skill from `.agents/skills/` before working in its domain:
- `lms-plugin-dev`: Developing and testing the Lyrion Music Server Perl plugin.
- `squeezeplay-applet-dev`: Developing and styling the Squeezebox Radio Lua 5.1 screensaver applet.
- `lms-radio-deploy`: Building, packaging, testing via SSH, and distributing locally via LMS Applet Installer.
