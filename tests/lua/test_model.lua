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

-- 5. Adaptive 320x240 (baby) layout math & typography hierarchy (exact v1.2.1 regression)
local lay0 = Model.computeLayout(320, 240, 0, false, false)
assertEq(lay0.scale,      1,   "320x240 scale is 1")
assertEq(lay0.topBarH,    10,  "320x240 topBarH without bar")
assertEq(lay0.sensorRows, 0,   "0 sensors uses 0 rows")
assertEq(lay0.clockFontSize, 105, "320x240 0-sensor clockFontSize preserved")

local lay2 = Model.computeLayout(320, 240, 2, true, true)
assertEq(lay2.scale,         1,   "320x240 scale is 1 with 2 sensors")
assertEq(lay2.topBarH,       28,  "320x240 topBarH with bar")
assertEq(lay2.bottomBandY,   168, "320x240 2-sensor bottomBandY preserved")
assertEq(lay2.clockFontSize, 96,  "320x240 2-sensor clockFontSize preserved")
assertEq(lay2.labelFontSize, 11,  "320x240 2-sensor labelFontSize preserved")
assertEq(lay2.valueFontSize, 28,  "320x240 2-sensor valueFontSize preserved")
assertEq(lay2.unitFontSize,  14,  "320x240 2-sensor unitFontSize preserved")
assertEq(lay2.sensorRows,    1,   "2 sensors uses 1 row")
assertEq(lay2.sensorCols,    2,   "2 sensors uses 2 cols")
assertEq(lay2.valueFontSize > lay2.unitFontSize,  true, "Temperature value font larger than unit font")
assertEq(lay2.valueFontSize > lay2.labelFontSize, true, "Temperature value font larger than label font")

local lay4 = Model.computeLayout(320, 240, 4, true, true)
assertEq(lay4.bottomBandY,   134, "320x240 4-sensor bottomBandY preserved")
assertEq(lay4.clockFontSize, 76,  "320x240 4-sensor clockFontSize preserved")
assertEq(lay4.labelFontSize, 10,  "320x240 4-sensor labelFontSize preserved")
assertEq(lay4.valueFontSize, 20,  "320x240 4-sensor valueFontSize preserved")
assertEq(lay4.unitFontSize,  12,  "320x240 4-sensor unitFontSize preserved")
assertEq(lay4.sensorRows,    2,   "4 sensors on 320x240 uses 2x2 grid rows")
assertEq(lay4.sensorCols,    2,   "4 sensors on 320x240 uses 2x2 grid cols")
assertEq(lay4.clockFontSize < lay2.clockFontSize, true, "Clock scales slightly smaller for 2x2 grid")

-- 6. Squeezebox Touch (420x272 & 480x272) and Jivelite (800x480, 1280x720, 1920x1080, 240x320)
local lay420 = Model.computeLayout(420, 272, 4, true, true)
assertEq(lay420.sensorRows, 2, "420x272 (aspect 1.54 < 1.65) uses 2x2 grid")
assertEq(lay420.topBarH < lay420.bottomBandY, true, "420x272 topBarH < bottomBandY")
assertEq(lay420.bottomBandY < 272, true, "420x272 bottomBandY < h")
assertEq(lay420.valueFontSize > lay4.valueFontSize, true, "420x272 value font scales up vs 320x240")

local layTouch = Model.computeLayout(480, 272, 4, true, true)
assertEq(layTouch.sensorRows, 1, "480x272 Touch (aspect 1.76 >= 1.65) uses 1-row 4-sensor band")
assertEq(layTouch.sensorCols, 4, "480x272 Touch uses 4 cols")
assertEq(layTouch.bottomBandY, math.floor(272 * 0.70), "480x272 Touch 1-row band gives clock more headroom")
assertEq(layTouch.clockFontSize, math.floor(272 * 0.40), "480x272 Touch clock scales for 1-row band")

local layJive800 = Model.computeLayout(800, 480, 3, true, true)
assertEq(layJive800.scale, 2, "800x480 Jivelite scale is 2")
assertEq(layJive800.sensorRows, 1, "800x480 Jivelite (aspect 1.67 >= 1.65) uses 1-row band")
assertEq(layJive800.uiFontSize, 24, "800x480 uiFontSize scales 2x")

local layJive1080 = Model.computeLayout(1920, 1080, 4, true, true)
assertEq(layJive1080.scale, 4.5, "1920x1080 Jivelite scale is 4.5")
assertEq(layJive1080.sensorRows, 1, "1920x1080 Jivelite uses 1-row 4-sensor band")
assertEq(layJive1080.topBarH < layJive1080.bottomBandY, true, "1920x1080 topBarH < bottomBandY")
assertEq(layJive1080.bottomBandY < 1080, true, "1920x1080 bottomBandY < h")
assertEq(layJive1080.valueFontSize, 108, "1920x1080 valueFontSize scales proportionally")

local layPortrait = Model.computeLayout(240, 320, 2, true, false)
assertEq(layPortrait.scale, 0.75, "240x320 portrait scale is 0.75")
assertEq(layPortrait.topBarH < layPortrait.bottomBandY, true, "240x320 topBarH < bottomBandY")

-- 7. UTF-8 safe truncation helper & localized textual sensor payloads
assertEq(Model.utf8PopLastChar("Open"), "Ope", "utf8PopLastChar pops ASCII char")
assertEq(Model.utf8PopLastChar("Öppen"), "Öppe", "utf8PopLastChar pops ASCII trailing char after UTF-8")
assertEq(Model.utf8PopLastChar("Olå"), "Ol", "utf8PopLastChar pops full 2-byte UTF-8 char 'å'")
assertEq(Model.utf8PopLastChar("Ö"), "", "utf8PopLastChar pops single 2-byte UTF-8 char cleanly")
assertEq(Model.utf8PopLastChar(""), "", "utf8PopLastChar handles empty string")

-- Mock widthFn where every byte costs 10px, to verify UTF-8 safe boundary truncation in "Från"
local mockWidth = function(s) return #s * 10 end
assertEq(Model.truncateUtf8Text("Frånkopplad", 50, mockWidth), "Fr..", "truncateUtf8Text never splits 2-byte 'å' when adding '..'")
assertEq(Model.truncateUtf8Text("Open", 100, mockWidth), "Open", "truncateUtf8Text leaves fitting text untouched")

local stText = Model.newState()
Model.applyServerPayload(stText, {
    poll_interval = 60,
    sensors_loop  = {
        { label = "Door", value = "Öppen", unit = "", ok = 1 },
        { label = "Lock", value = "Olåst", unit = "", ok = 1 },
    },
}, 20000)
assertEq(Model.formatSensorDisplay(stText.sensors[1]), "Öppen", "Localized binary_sensor value preserved without unit")
assertEq(Model.formatSensorDisplay(stText.sensors[2]), "Olåst", "Localized lock value preserved without unit")

print(string.format("Lua unit tests: %d passed, %d failed", passed, failed))
if failed > 0 then
    os.exit(1)
end
