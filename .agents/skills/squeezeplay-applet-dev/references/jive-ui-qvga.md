# SqueezePlay Jive UI & 320×240 QVGA Reference

## Built-in Fonts on Squeezebox Radio (`baby`)
SqueezeOS ships with FreeFont TTF files under `fonts/` in the Jive share path:
- `fonts/FreeSansBold.ttf` (default — bold, crisp, best room-distance legibility)
- `fonts/FreeSans.ttf` (clean, lighter stroke)
- `fonts/FreeMonoBold.ttf` (monospace tabular digits — zero horizontal jitter)
- `fonts/FreeSerifBold.ttf` (classic serif clock look)

Custom open-source `.ttf` files can also be dropped into `applets/HAScreenSaver/fonts/<Name>.ttf` and loaded via `Font:load("applets/HAScreenSaver/fonts/<Name>.ttf", size)`.

## Custom Window Styling
To render exact 320×240 positioning without fighting the active skin, apply a custom style table to the screensaver window (or via `jiveStyle`):

```lua
local Tile  = require("jive.ui.Tile")
local Font  = require("jive.ui.Font")
local Surface = require("jive.ui.Surface")
```

- `Window("ha_screensaver")` with `window:setAllowScreensaver(false)` (a screensaver window must not trigger another screensaver).
- `window:setButtonAction("rbutton", nil)` and standard screensaver registration via `manager:registerWindow(window)` ensures any button press / knob turn / power key dismisses the screensaver cleanly!
- Use `Surface:newRGBA(320, 240)` or styled `Label` widgets with `position = LAYOUT_NONE`, `x`, `y`, `w`, `h` for pixel-accurate 320×240 layout that works identically regardless of skin.

## Important Screensaver Window Registration
Always register the window with the `ScreenSavers` manager:
```lua
local manager = appletManager:getAppletInstance("ScreenSavers")
manager:screensaverWindow(window, true, nil, nil, "HAScreenSaver")
```
This hooks up:
- Automatic dismissal on key/scroll/touch/IR input
- Proper z-order above Now Playing
- Backlight / ambient light dimming behavior

## Local Time Formatting
Respect the user's 12h/24h preference from `jive.utils.datetime`:
```lua
local datetime = require("jive.utils.datetime")
local hourFormat = datetime:getHours() -- "12" or "24"
local timeStr = (hourFormat == "12") and os.date("%I:%M") or os.date("%H:%M")
```
(Strip leading zero in 12h mode if desired: `timeStr:gsub("^0", "")`.)
