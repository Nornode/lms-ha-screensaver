---
name: squeezeplay-applet-dev
description: >-
  Guide and reference for developing, styling, and testing SqueezePlay / Jive Lua 5.1
  screensaver applets for Logitech Squeezebox Radio / UE Smart Radio (hardware target baby,
  320x240 QVGA landscape).
---

# SqueezePlay / Squeezebox Radio Applet Development Skill

Use this skill whenever creating, modifying, or debugging Lua code under `radio-applet/HAScreenSaver/`.

## 1. Target Hardware & Runtime Constraints

- **Device**: Logitech Squeezebox Radio / UE Smart Radio (converted to Squeezebox firmware)
- **Hardware Target**: `baby` (`320×240` QVGA landscape LCD, 2.4", ambient light dimmer)
- **Lua Runtime**: **Lua 5.1** inside Jive / SqueezePlay (`~64 MB` total RAM)
- **Strict Lua 5.1 rules**:
  - Use `module(..., Framework.constants)` and `oo.class(_M, Applet)` / `oo.class(_M, AppletMeta)`.
  - Never use Lua 5.2+ features (`goto`, `//`, `&`, `|`, `~`, `<<`, `>>`, `<const>`, `<close>`).
  - Never write transient sensor data to `/etc/squeezeplay/userpath/settings/`.

## 2. Applet Structure

```text
radio-applet/HAScreenSaver/
├── HAScreenSaverMeta.lua     # Registers screensaver with ScreenSavers service
├── HAScreenSaverApplet.lua   # Window, 320x240 layout, clock + poll timers, Comet RPC
├── strings.txt               # Applet UI strings
└── fonts/                    # Optional bundled TTF fonts
```

## 3. Registering a Screensaver (`HAScreenSaverMeta.lua`)

Register inside `configureApplet(meta)`:

```lua
appletManager:callService(
    "addScreenSaver",
    meta:string("HA_SCREENSAVER"),
    "HAScreenSaver",
    "openScreensaver",
    _,
    _,
    90,
    "closeScreensaver"
)
```

- `openScreensaver` creates and shows the screensaver `Window`.
- `closeScreensaver` cleanly hides the window, stops timers, and wipes transient sensor state.

## 4. Layout Design (320×240 QVGA)

- **Background**: Pure black (`0x000000FF`) for crisp contrast and comfortable nighttime dimming.
- **Top-right corner**: Compact alarm badge (e.g. `ALM 07:00` or bell glyph + time) shown **only** when the radio has an active scheduled alarm.
- **Optional Alert Bar (top-left or top strip)**: Shown **only** when the configured alert/door sensor is active (e.g. `Door: Open` in amber/red highlight); completely hidden when normal.
- **Primary Clock (center-upper)**: Large digital `HH:MM` (no seconds, no date) using configurable font (`FreeSansBold`, `FreeSans`, `FreeMonoBold`, `FreeSerifBold`, or custom TTF in `fonts/`).
- **Bottom Sensor Area**: Adapts cleanly to 1, 2, 3, or 4 sensors:
  - 1–2 sensors: Single horizontal row with generous font size (`22px`–`24px`).
  - 3–4 sensors: Compact 2×2 grid (`18px`–`20px`) with crisp labels and values.

## 5. Querying LMS Over Comet (Zero Caching)

```lua
local player = appletManager:callService("getCurrentPlayer")
local server = player and player:getSlimServer()
if server then
    server:userRequest(
        function(chunk, err)
            if err or not chunk or not chunk.data then return end
            self:_applyServerData(chunk.data)
        end,
        player:getId(),
        { "hascreensaver", "sensors" }
    )
end
```

- Poll immediately when the screensaver opens, then on a `Timer` matching `poll_interval` (default `60000` ms).
- Track `lastSuccessMs = Framework:getTicks()`; if `now - lastSuccessMs > pollIntervalMs * 2.5`, reset displayed sensor values to `--` so stale data never lingers.
- Optionally subscribe to `notify_serverConnected` or Comet `hascreensaver refresh` notifications for instant updates on door/alert changes.

## 6. Lifecycle & Memory Hygiene

On `EVENT_WINDOW_POP` (note: SqueezePlay uses `EVENT_WINDOW_POP`, **not** `EVENT_WINDOW_CLOSED`, which is `nil` and causes `Invalid event mask`!) and `closeScreensaver`:
1. Stop `clockTimer` and `pollTimer`.
2. Unsubscribe from `jnt`.
3. Nil out `self.state`, `self.window`, `self.canvas`, `self.bgSurface`, `self.fonts`, and `self.iconCache`.
4. Always use `Window("window")` + `Canvas("debug_canvas", function(screen) ... end)` for skin-independent full-screen drawing, and wrap draw/fetch callbacks in `pcall` so missing HA entities gracefully render `--` without ever blocking the digital clock.

Note: Stock Squeezebox Radio (`baby`) ships only `fonts/FreeSans.ttf` and `fonts/FreeSansBold.ttf` in `/usr/share/jive/fonts/`. Always fall back to `fonts/FreeSansBold.ttf` if a configured font fails to load.

See [references/jive-ui-qvga.md](./references/jive-ui-qvga.md) for skinning, font paths, and widget positioning details.
