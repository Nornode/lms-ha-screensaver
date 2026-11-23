-- Pure Lua 5.1 helper functions for HAScreenSaver (unit-testable outside Jive)

local M = {}

M.DEFAULT_POLL_INTERVAL_MS = 60000
M.MIN_POLL_INTERVAL_MS     = 10000
M.MAX_POLL_INTERVAL_MS     = 300000
M.STALE_MULTIPLIER         = 2.5

M.FONT_FILES = {
    FreeSansBold  = "fonts/FreeSansBold.ttf",
    FreeSans      = "fonts/FreeSans.ttf",
    FreeMonoBold  = "fonts/FreeMonoBold.ttf",
    FreeSerifBold = "fonts/FreeSerifBold.ttf",
}

M.WEATHER_ICONS = {
    sunny        = "applets/HAScreenSaver/weather_sunny.png",
    clear_night  = "applets/HAScreenSaver/weather_clear_night.png",
    partlycloudy = "applets/HAScreenSaver/weather_partlycloudy.png",
    cloudy       = "applets/HAScreenSaver/weather_cloudy.png",
    rainy        = "applets/HAScreenSaver/weather_rainy.png",
    pouring      = "applets/HAScreenSaver/weather_pouring.png",
    snowy        = "applets/HAScreenSaver/weather_snowy.png",
    fog          = "applets/HAScreenSaver/weather_fog.png",
    lightning    = "applets/HAScreenSaver/weather_lightning.png",
    windy        = "applets/HAScreenSaver/weather_windy.png",
}

function M.newState()
    return {
        pollIntervalMs = M.DEFAULT_POLL_INTERVAL_MS,
        fontName       = "FreeSansBold",
        alarmActive    = false,
        alarmTime      = "",
        weatherIcon    = "",
        alertActive    = false,
        alertText      = "",
        sensors        = {},
        lastSuccessMs  = nil,
    }
end

function M.resolveFontPath(fontName)
    if type(fontName) == "string" and M.FONT_FILES[fontName] then
        return M.FONT_FILES[fontName]
    end
    return M.FONT_FILES.FreeSansBold
end

function M.resolveWeatherIconPath(iconKey)
    if type(iconKey) == "string" and M.WEATHER_ICONS[iconKey] then
        return M.WEATHER_ICONS[iconKey]
    end
    return nil
end

function M.formatTime(hour24, min, is12Hour)
    local h = tonumber(hour24) or 0
    local m = tonumber(min) or 0
    if is12Hour then
        local h12 = h % 12
        if h12 == 0 then
            h12 = 12
        end
        return string.format("%d:%02d", h12, m)
    end
    return string.format("%02d:%02d", h, m)
end

function M.applyServerPayload(state, data, nowMs)
    if type(data) ~= "table" then
        return state
    end

    local intervalSec = tonumber(data.poll_interval)
    if intervalSec then
        local ms = math.floor(intervalSec * 1000)
        if ms < M.MIN_POLL_INTERVAL_MS then ms = M.MIN_POLL_INTERVAL_MS end
        if ms > M.MAX_POLL_INTERVAL_MS then ms = M.MAX_POLL_INTERVAL_MS end
        state.pollIntervalMs = ms
    end

    if type(data.font_name) == "string" and M.FONT_FILES[data.font_name] then
        state.fontName = data.font_name
    end

    state.alarmActive = (tonumber(data.alarm_active) == 1) or (data.alarm_active == true)
    state.alarmTime   = (type(data.alarm_time) == "string") and data.alarm_time or ""

    if type(data.weather_icon) == "string" and M.WEATHER_ICONS[data.weather_icon] then
        state.weatherIcon = data.weather_icon
    else
        state.weatherIcon = ""
    end

    state.alertActive = (tonumber(data.alert_active) == 1) or (data.alert_active == true)
    state.alertText   = (type(data.alert_text) == "string") and data.alert_text or ""

    local parsed = {}
    if type(data.sensors_loop) == "table" then
        local count = #data.sensors_loop
        if count > 4 then count = 4 end
        for i = 1, count do
            local item = data.sensors_loop[i]
            if type(item) == "table" then
                parsed[#parsed + 1] = {
                    label = (type(item.label) == "string") and item.label or "",
                    value = (type(item.value) == "string") and item.value or "--",
                    unit  = (type(item.unit) == "string") and item.unit or "",
                    ok    = (tonumber(item.ok) == 1) or (item.ok == true),
                }
            end
        end
    end

    state.sensors       = parsed
    state.lastSuccessMs = nowMs
    return state
end

function M.expireIfStale(state, nowMs)
    if not state.lastSuccessMs or not nowMs then
        return false
    end

    local ageMs = nowMs - state.lastSuccessMs
    local maxAgeMs = state.pollIntervalMs * M.STALE_MULTIPLIER
    if ageMs <= maxAgeMs then
        return false
    end

    local changed = false
    for i = 1, #state.sensors do
        if state.sensors[i].value ~= "--" or state.sensors[i].ok then
            state.sensors[i].value = "--"
            state.sensors[i].ok    = false
            changed = true
        end
    end
    if state.weatherIcon ~= "" then
        state.weatherIcon = ""
        changed = true
    end
    if state.alertActive or state.alertText ~= "" then
        state.alertActive = false
        state.alertText   = ""
        changed = true
    end
    return changed
end

function M.utf8PopLastChar(s)
    if type(s) ~= "string" or #s == 0 then
        return ""
    end
    local i = #s
    while i > 1 do
        local b = string.byte(s, i)
        if b < 128 or b >= 192 then
            break
        end
        i = i - 1
    end
    return string.sub(s, 1, i - 1)
end

function M.truncateUtf8Text(text, maxWidth, widthFn)
    if type(text) ~= "string" or text == "" then
        return ""
    end
    if type(widthFn) ~= "function" or type(maxWidth) ~= "number" then
        return text
    end
    local s = text
    while #s > 1 and widthFn(s) > maxWidth do
        local nextS = M.utf8PopLastChar(s)
        if nextS == "" or nextS == s then
            break
        end
        s = nextS
    end
    if s ~= text and #s > 3 then
        local t1 = M.utf8PopLastChar(s)
        local t2 = M.utf8PopLastChar(t1)
        if #t2 > 0 then
            s = t2 .. ".."
        end
    end
    return s
end

function M.formatSensorDisplay(sensor)
    if type(sensor) ~= "table" then
        return "--"
    end
    local val  = sensor.value or "--"
    local unit = sensor.unit or ""
    if val == "--" or unit == "" then
        return val
    end
    return val .. unit
end

function M.computeLayout(screenW, screenH, sensorCount, hasTopBar, hasWeather)
    local w = screenW or 320
    local h = screenH or 240
    local n = sensorCount or 0
    if n > 4 then n = 4 end

    local isPortrait = (h > w)
    local scale = isPortrait and math.min(w / 240, h / 320) or math.min(w / 320, h / 240)
    if scale <= 0 then scale = 1 end
    local function S(px)
        return math.floor(px * scale + 0.5)
    end

    local hasBottom = (isPortrait and (n > 0)) or ((not isPortrait) and ((n > 0) or (hasWeather == true)))
    local topBarH = hasTopBar and math.max(14, S(28)) or math.max(4, S(10))
    local layout = {
        screenW         = w,
        screenH         = h,
        isPortrait      = isPortrait,
        scale           = scale,
        topBarH         = topBarH,
        hasBottom       = hasBottom,
        sensorRows      = 0,
        sensorCols      = 0,
        uiFontSize      = math.max(8, S(12)),
        sidePad         = isPortrait and math.max(4, S(10)) or math.max(4, S(12)),
        colGap          = math.max(4, S(8)),
        shadowOffset    = math.max(2, S(2)),
        dividerH        = math.max(1, S(1)),
        dividerInset    = math.max(4, S(10)),
        areaPad         = math.max(2, S(4)),
        weatherPad      = math.max(4, S(12)),
        alarmRightPad   = math.max(4, S(8)),
        alarmTopY       = math.max(2, S(6)),
        alarmIconGap    = math.max(2, S(4)),
        alarmReservePad = math.max(6, S(14)),
        pillX           = math.max(3, S(6)),
        pillY           = math.max(2, S(4)),
        pillPadX        = math.max(6, S(12)),
        pillPadY        = math.max(3, S(6)),
        pillMinH        = math.max(12, S(20)),
        pillIconGap     = math.max(2, S(4)),
        cellUnitGap     = math.max(1, S(2)),
        cellUnitReserve = math.max(2, S(3)),
        cellUnitYOffset = math.max(1, S(3)),
        cellLabelGap    = math.max(1, S(1)),
        cellMinValW     = math.max(12, S(24)),
        weatherPlacement = nil,
        weatherCenterY  = nil,
        cells           = {},
    }

    if isPortrait then
        local fullW = w - (layout.sidePad * 2)
        local colW = math.floor((fullW - layout.colGap) / 2)
        local rightColX = w - layout.sidePad - colW

        if n == 0 then
            layout.bottomBandY = nil
            layout.clockFontSize = math.max(12, math.floor(w * 0.34))
            if hasWeather == true then
                local availH = h - topBarH
                layout.weatherPlacement = "above_divider"
                layout.clockCenterY     = topBarH + math.floor(availH * 0.38)
                layout.weatherCenterY   = topBarH + math.floor(availH * 0.72)
            else
                layout.clockCenterY = math.floor((h + topBarH) / 2) - math.floor(h * 0.03)
            end
        elseif n <= 2 then
            layout.bottomBandY = (hasWeather == true) and math.floor(h * 0.66) or math.floor(h * 0.64)
            local upperH = layout.bottomBandY - topBarH
            if hasWeather == true then
                layout.weatherPlacement = "above_divider"
                layout.clockFontSize    = math.max(12, math.floor(w * 0.32))
                layout.clockCenterY     = topBarH + math.floor(upperH * 0.34)
                layout.weatherCenterY   = layout.bottomBandY - math.floor(upperH * 0.21)
            else
                layout.clockFontSize = math.max(12, math.floor(w * 0.34))
                layout.clockCenterY  = math.floor((topBarH + layout.bottomBandY) / 2) - math.floor(h * 0.03)
            end

            local areaTop = layout.bottomBandY + layout.areaPad
            local areaH   = h - areaTop - layout.areaPad
            if n == 1 then
                layout.sensorRows    = 1
                layout.sensorCols    = 1
                layout.labelFontSize = math.max(8, S(12))
                layout.valueFontSize = math.max(12, S(30))
                layout.unitFontSize  = math.max(9, S(15))
                layout.cells[1] = { x = layout.sidePad, y = areaTop, w = fullW, h = areaH, align = "center" }
            else
                local rowH = math.floor(areaH / 2)
                layout.sensorRows    = 2
                layout.sensorCols    = 1
                layout.labelFontSize = math.max(8, S(12))
                layout.valueFontSize = math.max(12, S(26))
                layout.unitFontSize  = math.max(9, S(13))
                layout.cells[1] = { x = layout.sidePad, y = areaTop,        w = fullW, h = rowH, align = "row" }
                layout.cells[2] = { x = layout.sidePad, y = areaTop + rowH, w = fullW, h = rowH, align = "row" }
            end
        else
            layout.sensorRows  = 2
            layout.sensorCols  = 2
            layout.bottomBandY = math.floor(h * 0.56)
            local upperH = layout.bottomBandY - topBarH
            if hasWeather == true then
                layout.weatherPlacement = "above_divider"
                layout.clockFontSize    = math.max(12, math.floor(w * 0.28))
                layout.clockCenterY     = topBarH + math.floor(upperH * 0.32)
                layout.weatherCenterY   = layout.bottomBandY - math.floor(upperH * 0.20)
            else
                layout.clockFontSize = math.max(12, math.floor(w * 0.33))
                layout.clockCenterY  = math.floor((topBarH + layout.bottomBandY) / 2) - math.floor(h * 0.03)
            end

            layout.labelFontSize = math.max(8, S(10))
            layout.valueFontSize = math.max(12, S(20))
            layout.unitFontSize  = math.max(9, S(12))

            local areaTop = layout.bottomBandY + layout.areaPad
            local areaH   = h - areaTop - layout.areaPad
            local rowH    = math.floor(areaH / 2)
            layout.cells[1] = { x = layout.sidePad, y = areaTop, w = colW, h = rowH, align = "left" }
            layout.cells[2] = { x = rightColX,      y = areaTop, w = colW, h = rowH, align = "right" }
            if n == 3 then
                layout.cells[3] = { x = layout.sidePad, y = areaTop + rowH, w = fullW, h = rowH, align = "center" }
            else
                layout.cells[3] = { x = layout.sidePad, y = areaTop + rowH, w = colW, h = rowH, align = "left" }
                layout.cells[4] = { x = rightColX,      y = areaTop + rowH, w = colW, h = rowH, align = "right" }
            end
        end

        return layout
    end

    if not hasBottom then
        layout.clockFontSize = math.floor(h * 0.44)
        layout.clockCenterY  = math.floor((h + topBarH) / 2) - math.floor(h * 0.04)
        layout.bottomBandY   = nil
    elseif n <= 2 then
        layout.sensorRows    = (n > 0) and 1 or 0
        layout.sensorCols    = n
        layout.bottomBandY   = math.floor(h * 0.70)
        layout.clockFontSize = math.floor(h * 0.40)
        layout.clockCenterY  = math.floor((topBarH + layout.bottomBandY) / 2) - math.floor(h * 0.05)
        layout.labelFontSize = math.max(8, S(11))
        layout.valueFontSize = math.max(12, S(28))
        layout.unitFontSize  = math.max(9, S(14))
    elseif (w / h) >= 1.65 then
        layout.sensorRows    = 1
        layout.sensorCols    = n
        layout.bottomBandY   = math.floor(h * 0.70)
        layout.clockFontSize = math.floor(h * 0.40)
        layout.clockCenterY  = math.floor((topBarH + layout.bottomBandY) / 2) - math.floor(h * 0.05)
        layout.labelFontSize = math.max(8, S(11))
        layout.valueFontSize = math.max(12, S(24))
        layout.unitFontSize  = math.max(9, S(13))
    else
        layout.sensorRows    = 2
        layout.sensorCols  = 2
        layout.bottomBandY   = math.floor(h * 0.56)
        layout.clockFontSize = math.floor(h * 0.32)
        layout.clockCenterY  = math.floor((topBarH + layout.bottomBandY) / 2) - math.floor(h * 0.04)
        layout.labelFontSize = math.max(8, S(10))
        layout.valueFontSize = math.max(12, S(20))
        layout.unitFontSize  = math.max(9, S(12))
    end

    return layout
end

return M
