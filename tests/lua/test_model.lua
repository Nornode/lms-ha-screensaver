-- Unit tests for HAScreenSaverModel.lua (run with lua tests/lua/test_model.lua)

package.path = "radio-applet/HAScreenSaver/?.lua;" .. package.path
local Model = require("HAScreenSaverModel")

local passed = 0
local failed = 0

local function assertEq(actual, expected, msg)
    if actual == expected then
        passed = passed + 1
    else
        failed = failed + 1
        io.stderr:write(string.format("FAIL: %s (expected=%s, actual=%s)\n", msg, tostring(expected), tostring(actual)))
    end
end

-- 1. Time formatting (no seconds, no date)
assertEq(Model.formatTime(9, 5, false),  "09:05", "24h format zero-padded")
assertEq(Model.formatTime(22, 45, false),"22:45", "24h format evening")
assertEq(Model.formatTime(0, 7, true),   "12:07", "12h format midnight")
assertEq(Model.formatTime(13, 30, true), "1:30",  "12h format afternoon")
assertEq(Model.formatTime(12, 0, true),  "12:00", "12h format noon")

-- 2. Font & weather icon resolution
assertEq(Model.resolveFontPath("FreeSansBold"),  "fonts/FreeSansBold.ttf",  "Default font resolves")
assertEq(Model.resolveFontPath("FreeMonoBold"),  "fonts/FreeMonoBold.ttf",  "Mono font resolves")
assertEq(Model.resolveFontPath("UnknownFont"),   "fonts/FreeSansBold.ttf",  "Unknown font falls back")
assertEq(Model.resolveWeatherIconPath("partlycloudy"), "applets/HAScreenSaver/weather_partlycloudy.png", "Weather icon resolves")
assertEq(Model.resolveWeatherIconPath("bogus"), nil, "Unknown weather icon returns nil")

-- 3. Server payload parsing (up to 4 sensors + weather + alarm + alert)
local st = Model.newState()
Model.applyServerPayload(st, {
    poll_interval = 60,
    font_name     = "FreeSerifBold",
    alarm_active  = 1,
    alarm_time    = "07:00",
    weather_icon  = "rainy",
    alert_active  = 1,
    alert_text    = "Open: Front Door",
    sensors_loop  = {
        { label = "Out", value = "6.2",  unit = "°C", ok = 1 },
        { label = "In",  value = "21.5", unit = "°C", ok = 1 },
        { label = "Hum", value = "48",   unit = "%",  ok = 1 },
        { label = "CO2", value = "520",  unit = "ppm",ok = 1 },
        { label = "Extra", value = "99", unit = "",   ok = 1 },
    },
}, 10000)

assertEq(st.pollIntervalMs, 60000,              "Poll interval converted to ms")
assertEq(st.fontName,       "FreeSerifBold",    "Font updated from server")
assertEq(st.alarmActive,    true,               "Alarm active parsed")
assertEq(st.alarmTime,      "07:00",            "Alarm time parsed")
assertEq(st.weatherIcon,    "rainy",            "Weather icon parsed")
assertEq(st.alertActive,    true,               "Alert active parsed")
assertEq(st.alertText,      "Open: Front Door", "Alert text parsed")
assertEq(#st.sensors,       4,                  "Sensors capped at 4")
assertEq(Model.formatSensorDisplay(st.sensors[1]), "6.2°C", "Sensor display joins value + unit")

-- 4. Staleness expiry (zero long-term caching on radio)
local changedFresh = Model.expireIfStale(st, 10000 + 120000) -- 120s <= 150s (2.5 * 60s)
assertEq(changedFresh,       false, "Not stale within 2.5x poll interval")
assertEq(st.sensors[1].value,"6.2", "Fresh sensor retained during active window")

local changedStale = Model.expireIfStale(st, 10000 + 150001) -- > 150s
assertEq(changedStale,       true,  "Stale detected after 2.5x poll interval")
assertEq(st.sensors[1].value,"--",  "Stale sensor cleared to --")
assertEq(st.sensors[1].ok,   false, "Stale sensor marked not ok")
assertEq(st.weatherIcon,     "",    "Stale weather icon cleared")
assertEq(st.alertActive,     false, "Stale alert cleared")
assertEq(st.alertText,       "",    "Stale alert text cleared")

-- 5. Adaptive 320x240 layout math & typography hierarchy
local lay0 = Model.computeLayout(320, 240, 0, false, false)
assertEq(lay0.sensorRows, 0, "0 sensors uses 0 rows")

local lay2 = Model.computeLayout(320, 240, 2, true, true)
assertEq(lay2.sensorRows, 1, "2 sensors uses 1 row")
assertEq(lay2.sensorCols, 2, "2 sensors uses 2 cols")
assertEq(lay2.valueFontSize > lay2.unitFontSize,  true, "Temperature value font larger than unit font")
assertEq(lay2.valueFontSize > lay2.labelFontSize, true, "Temperature value font larger than label font")

local lay4 = Model.computeLayout(320, 240, 4, true, true)
assertEq(lay4.sensorRows, 2, "4 sensors uses 2x2 grid rows")
assertEq(lay4.sensorCols, 2, "4 sensors uses 2x2 grid cols")
assertEq(lay4.clockFontSize < lay2.clockFontSize, true, "Clock scales slightly smaller for 2x2 grid")

print(string.format("Lua unit tests: %d passed, %d failed", passed, failed))
if failed > 0 then
    os.exit(1)
end
