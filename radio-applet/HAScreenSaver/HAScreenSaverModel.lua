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
    sunny           = "applets/HAScreenSaver/weather_sunny.png",
    clear_night     = "applets/HAScreenSaver/weather_clear_night.png",
    partlycloudy    = "applets/HAScreenSaver/weather_partlycloudy.png",
    cloudy          = "applets/HAScreenSaver/weather_cloudy.png",
    rainy           = "applets/HAScreenSaver/weather_rainy.png",
    pouring         = "applets/HAScreenSaver/weather_pouring.png",
    hail            = "applets/HAScreenSaver/weather_hail.png",
    snowy           = "applets/HAScreenSaver/weather_snowy.png",
    snowy_rainy     = "applets/HAScreenSaver/weather_snowy_rainy.png",
    fog             = "applets/HAScreenSaver/weather_fog.png",
    lightning       = "applets/HAScreenSaver/weather_lightning.png",
    lightning_rainy = "applets/HAScreenSaver/weather_lightning_rainy.png",
    windy           = "applets/HAScreenSaver/weather_windy.png",
    windy_variant   = "applets/HAScreenSaver/weather_windy_variant.png",
    exceptional     = "applets/HAScreenSaver/weather_exceptional.png",
}

M.WEATHER_ICONS_DARK = {
    sunny           = "applets/HAScreenSaver/weather_sunny_dark.png",
    clear_night     = "applets/HAScreenSaver/weather_clear_night_dark.png",
    partlycloudy    = "applets/HAScreenSaver/weather_partlycloudy_dark.png",
    cloudy          = "applets/HAScreenSaver/weather_cloudy_dark.png",
    rainy           = "applets/HAScreenSaver/weather_rainy_dark.png",
    pouring         = "applets/HAScreenSaver/weather_pouring_dark.png",
    hail            = "applets/HAScreenSaver/weather_hail_dark.png",
    snowy           = "applets/HAScreenSaver/weather_snowy_dark.png",
    snowy_rainy     = "applets/HAScreenSaver/weather_snowy_rainy_dark.png",
    fog             = "applets/HAScreenSaver/weather_fog_dark.png",
    lightning       = "applets/HAScreenSaver/weather_lightning_dark.png",
    lightning_rainy = "applets/HAScreenSaver/weather_lightning_rainy_dark.png",
    windy           = "applets/HAScreenSaver/weather_windy_dark.png",
    windy_variant   = "applets/HAScreenSaver/weather_windy_variant_dark.png",
    exceptional     = "applets/HAScreenSaver/weather_exceptional_dark.png",
}

-- Compose 32-bit RGBA integer without Lua 5.2+ bitwise operators (Lua 5.1 safe)
function M.rgba(r, g, b, a)
    return (((r * 256 + g) * 256 + b) * 256) + a
end

function M.parseHexColor(hexStr, fallbackInt)
    if type(hexStr) ~= "string" or hexStr == "" then
        return fallbackInt
    end
    local rh, gh, bh = string.match(hexStr, "^#?([0-9A-Fa-f][0-9A-Fa-f])([0-9A-Fa-f][0-9A-Fa-f])([0-9A-Fa-f][0-9A-Fa-f])$")
    if not rh then
        return fallbackInt
    end
    local r = tonumber(rh, 16)
    local g = tonumber(gh, 16)
    local b = tonumber(bh, 16)
    if not r or not g or not b then
        return fallbackInt
    end
    return M.rgba(r, g, b, 255)
end

local DEFAULT_DARK_COLORS = {
    clock    = 0xFFFFFFFF,
    shadow   = 0x000000AA,
    value    = 0xF5F7FAFF,
    label    = 0x7E8898FF,
    unit     = 0x8E98A8FF,
    stale    = 0x606875FF,
    alarm    = 0x8E98A8FF,
    alertBg  = 0xB8380EFF,
    alertTxt = 0xFFFFFFFF,
}

M.BACKGROUND_PRESETS = {
    slate = {
        top     = { 28, 34, 44 },
        bot     = { 6, 8, 12 },
        band    = M.rgba(4, 6, 10, 140),
        divider = 0x2A3240FF,
        light   = false,
        colors  = DEFAULT_DARK_COLORS,
    },
    black = {
        top     = { 0, 0, 0 },
        bot     = { 0, 0, 0 },
        band    = M.rgba(12, 14, 18, 115),
        divider = 0x1F242CFF,
        light   = false,
        colors  = DEFAULT_DARK_COLORS,
    },
    midnight = {
        top     = { 14, 28, 58 },
        bot     = { 4, 8, 20 },
        band    = M.rgba(3, 6, 16, 140),
        divider = 0x243B66FF,
        light   = false,
        colors  = DEFAULT_DARK_COLORS,
    },
    ember = {
        top     = { 38, 24, 18 },
        bot     = { 10, 6, 5 },
        band    = M.rgba(8, 4, 3, 140),
        divider = 0x4A3226FF,
        light   = false,
        colors  = DEFAULT_DARK_COLORS,
    },
    forest = {
        top     = { 16, 34, 28 },
        bot     = { 5, 10, 8 },
        band    = M.rgba(3, 8, 6, 140),
        divider = 0x234237FF,
        light   = false,
        colors  = DEFAULT_DARK_COLORS,
    },
    graphite = {
        top     = { 62, 64, 68 },
        bot     = { 24, 25, 28 },
        band    = M.rgba(14, 14, 16, 140),
        divider = 0x56585EFF,
        light   = false,
        colors  = {
            clock    = 0xFFFFFFFF,
            shadow   = 0x000000AA,
            value    = 0xF5F7FAFF,
            label    = 0xA4ABB5FF,
            unit     = 0xB2B8C2FF,
            stale    = 0x7A808AFF,
            alarm    = 0xB2B8C2FF,
            alertBg  = 0xB8380EFF,
            alertTxt = 0xFFFFFFFF,
        },
    },
    velvet = {
        top     = { 60, 14, 23 },
        bot     = { 18, 4, 7 },
        band    = M.rgba(12, 2, 4, 148),
        divider = 0x64202DFF,
        light   = false,
        colors  = {
            clock    = 0xFFFFFFFF,
            shadow   = 0x000000B2,
            value    = 0xFAF5F6FF,
            label    = 0xB38C94FF,
            unit     = 0xC29EA5FF,
            stale    = 0x85666DFF,
            alarm    = 0xC29EA5FF,
            alertBg  = 0xB8380EFF,
            alertTxt = 0xFFFFFFFF,
        },
    },
    silver = {
        top     = { 223, 227, 232 },
        bot     = { 182, 190, 200 },
        band    = M.rgba(165, 174, 186, 115),
        divider = 0x8F99A6FF,
        light   = true,
        colors  = {
            clock    = 0x14181FFF,
            shadow   = 0xFFFFFF66,
            value    = 0x161B22FF,
            label    = 0x4A5462FF,
            unit     = 0x3C4552FF,
            stale    = 0x7A8390FF,
            alarm    = 0x3C4552FF,
            alertBg  = 0xB8380EFF,
            alertTxt = 0xFFFFFFFF,
        },
    },
}

local VALID_WEATHER_SIZES = { large = true, compact = true }
local VALID_LABEL_SIZES   = { default = true, medium = true, large = true }
local VALID_SCALE_SIZES   = { compact = true, default = true, large = true }

function M.newState()
    return {
        pollIntervalMs  = M.DEFAULT_POLL_INTERVAL_MS,
        fontName        = "FreeSansBold",
        backgroundStyle = "slate",
        weatherSize     = "large",
        labelSize       = "default",
        labelBold       = false,
        valueSize       = "default",
        clockSize       = "default",
        clockColor      = "",
        valueColor      = "",
        labelColor      = "",
        unitColor       = "",
        alarmActive     = false,
        alarmTime       = "",
        weatherIcon     = "",
        alertActive     = false,
        alertText       = "",
        sensors         = {},
        lastSuccessMs   = nil,
    }
end

function M.resolveFontPath(fontName)
    if type(fontName) == "string" and M.FONT_FILES[fontName] then
        return M.FONT_FILES[fontName]
    end
    return M.FONT_FILES.FreeSansBold
end

function M.resolveWeatherIconPath(iconKey, isLight)
    if type(iconKey) ~= "string" then
        return nil
    end
    if isLight and M.WEATHER_ICONS_DARK[iconKey] then
        return M.WEATHER_ICONS_DARK[iconKey]
    end
    if M.WEATHER_ICONS[iconKey] then
        return M.WEATHER_ICONS[iconKey]
    end
    return nil
end

function M.resolveBackgroundPreset(styleId)
    if type(styleId) == "string" and M.BACKGROUND_PRESETS[styleId] then
        return M.BACKGROUND_PRESETS[styleId]
    end
    return M.BACKGROUND_PRESETS.slate
end

function M.resolveColors(state)
    local preset = M.resolveBackgroundPreset(state and state.backgroundStyle)
    local base   = preset.colors or DEFAULT_DARK_COLORS
    return {
        clock    = M.parseHexColor(state and state.clockColor, base.clock),
        shadow   = base.shadow,
        value    = M.parseHexColor(state and state.valueColor, base.value),
        label    = M.parseHexColor(state and state.labelColor, base.label),
        unit     = M.parseHexColor(state and state.unitColor,  base.unit),
        stale    = base.stale,
        alarm    = base.alarm,
        alertBg  = base.alertBg,
        alertTxt = base.alertTxt,
        divider  = preset.divider,
        band     = preset.band,
        isLight  = (preset.light == true),
        preset   = preset,
    }
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
    else
        state.fontName = "FreeSansBold"
    end

    if type(data.background_style) == "string" and M.BACKGROUND_PRESETS[data.background_style] then
        state.backgroundStyle = data.background_style
    else
        state.backgroundStyle = "slate"
    end

    if type(data.weather_size) == "string" and VALID_WEATHER_SIZES[data.weather_size] then
        state.weatherSize = data.weather_size
    else
        state.weatherSize = "large"
    end

    if type(data.label_size) == "string" and VALID_LABEL_SIZES[data.label_size] then
        state.labelSize = data.label_size
    else
        state.labelSize = "default"
    end

    state.labelBold = (tonumber(data.label_bold) == 1) or (data.label_bold == true)

    if type(data.value_size) == "string" and VALID_SCALE_SIZES[data.value_size] then
        state.valueSize = data.value_size
    else
        state.valueSize = "default"
    end

    if type(data.clock_size) == "string" and VALID_SCALE_SIZES[data.clock_size] then
        state.clockSize = data.clock_size
    else
        state.clockSize = "default"
    end

    state.clockColor = (type(data.clock_color) == "string" and M.parseHexColor(data.clock_color, nil)) and data.clock_color or ""
    state.valueColor = (type(data.value_color) == "string" and M.parseHexColor(data.value_color, nil)) and data.value_color or ""
    state.labelColor = (type(data.label_color) == "string" and M.parseHexColor(data.label_color, nil)) and data.label_color or ""
    state.unitColor  = (type(data.unit_color)  == "string" and M.parseHexColor(data.unit_color,  nil)) and data.unit_color  or ""

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

function M.computeLayout(screenW, screenH, sensorCount, hasTopBar, hasWeather, styleOpts)
    local w = screenW or 320
    local h = screenH or 240
    local n = sensorCount or 0
    if n > 4 then n = 4 end

    local opts        = (type(styleOpts) == "table") and styleOpts or nil
    local weatherSize = (opts and VALID_WEATHER_SIZES[opts.weatherSize]) and opts.weatherSize or "large"
    local labelSize   = (opts and VALID_LABEL_SIZES[opts.labelSize])     and opts.labelSize   or "default"
    local valueSize   = (opts and VALID_SCALE_SIZES[opts.valueSize])     and opts.valueSize   or "default"
    local clockSize   = (opts and VALID_SCALE_SIZES[opts.clockSize])     and opts.clockSize   or "default"

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
        weatherScale    = (weatherSize == "compact") and (44 / 56) or 1.0,
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

    local function applyStyleAdjustments()
        if clockSize ~= "default" and layout.clockFontSize then
            local factor = (clockSize == "compact") and 0.90 or 1.08
            local scaled = math.max(12, math.floor(layout.clockFontSize * factor + 0.5))
            local upperLimitY = layout.bottomBandY or h
            if layout.weatherPlacement == "above_divider" and layout.weatherCenterY then
                local halfWeather = math.floor(28 * scale * layout.weatherScale)
                local weatherTop  = layout.weatherCenterY - halfWeather - math.max(2, S(4))
                if weatherTop < upperLimitY then
                    upperLimitY = weatherTop
                end
            end
            local maxClockH = math.max(12, math.floor((upperLimitY - topBarH) * 0.90))
            if scaled > maxClockH then
                scaled = maxClockH
            end
            layout.clockFontSize = scaled
        end

        if (labelSize ~= "default" or valueSize ~= "default") and layout.labelFontSize and layout.valueFontSize then
            local lblDelta = (labelSize == "medium" and S(2)) or (labelSize == "large" and S(4)) or 0
            local valDelta = (valueSize == "compact" and -S(2)) or (valueSize == "large" and S(2)) or 0
            local unitDelta = (valueSize == "compact" and -S(1)) or (valueSize == "large" and S(1)) or 0

            local newLbl  = math.max(8, layout.labelFontSize + lblDelta)
            local newVal  = math.max(12, layout.valueFontSize + valDelta)
            local newUnit = math.max(9, (layout.unitFontSize or 12) + unitDelta)

            -- Clamp against available sensor cell height so 2x2 cells never overflow vertically
            if layout.hasBottom and layout.bottomBandY and layout.sensorRows and layout.sensorRows > 0 then
                local areaH = h - (layout.bottomBandY + layout.areaPad) - layout.areaPad
                local rowH  = math.floor(areaH / layout.sensorRows)
                local isRowAlign = (layout.isPortrait and layout.cells and layout.cells[1] and layout.cells[1].align == "row")
                if isRowAlign then
                    if newLbl > rowH - 4 then newLbl = math.max(8, rowH - 4) end
                    if newVal > rowH - 2 then newVal = math.max(12, rowH - 2) end
                else
                    local gap = layout.cellLabelGap or 1
                    local maxCombined = math.max(20, rowH - gap - 2)
                    if (newLbl + newVal) > maxCombined then
                        local excess = (newLbl + newVal) - maxCombined
                        local trimLbl = math.min(lblDelta > 0 and lblDelta or 0, excess)
                        newLbl = math.max(8, newLbl - trimLbl)
                        excess = (newLbl + newVal) - maxCombined
                        if excess > 0 then
                            newVal = math.max(12, newVal - excess)
                        end
                    end
                end
            end

            if newUnit >= newVal then
                newUnit = math.max(9, newVal - 2)
            end

            layout.labelFontSize = newLbl
            layout.valueFontSize = newVal
            layout.unitFontSize  = newUnit
        end

        return layout
    end

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

        return applyStyleAdjustments()
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

    return applyStyleAdjustments()
end

return M
