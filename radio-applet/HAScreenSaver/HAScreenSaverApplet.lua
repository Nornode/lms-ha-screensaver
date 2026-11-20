-- Home Assistant Digital Clock Screensaver for Squeezebox Radio (baby, 320x240)
-- Dark shaded background, prominent digital clock, bottom-center weather glyph,
-- lower-left / lower-right sensors with large readable values and subtle labels/units,
-- plus radio alarm icon and optional door-open alert pill.
-- Strict zero-long-term-caching: all sensor values live strictly in transient RAM.

local oo            = require("loop.simple")
local os            = require("os")
local math          = require("math")
local string        = require("string")
local pcall         = pcall
local tostring      = tostring

local Applet        = require("jive.Applet")
local Framework     = require("jive.ui.Framework")
local Window        = require("jive.ui.Window")
local Canvas        = require("jive.ui.Canvas")
local Surface       = require("jive.ui.Surface")
local Font          = require("jive.ui.Font")
local Timer         = require("jive.ui.Timer")
local datetime      = require("jive.utils.datetime")
local Model         = require("applets.HAScreenSaver.HAScreenSaverModel")

local appletManager = appletManager
local jnt           = jnt

module(..., Framework.constants)
oo.class(_M, Applet)

local COLOR_CLOCK     = 0xFFFFFFFF
local COLOR_SHADOW    = 0x000000AA
local COLOR_DIVIDER   = 0x2A3240FF
local COLOR_LABEL     = 0x7E8898FF
local COLOR_VALUE     = 0xF5F7FAFF
local COLOR_UNIT      = 0x8E98A8FF
local COLOR_STALE     = 0x606875FF
local COLOR_ALARM     = 0x8E98A8FF
local COLOR_ALERT_BG  = 0xB8380EFF
local COLOR_ALERT_TXT = 0xFFFFFFFF

local ICON_ALARM_PATH = "applets/HAScreenSaver/icons/icon_alarm.png"
local ICON_DOOR_PATH  = "applets/HAScreenSaver/icons/icon_door.png"
local FALLBACK_FONT   = "fonts/FreeSansBold.ttf"

-- Compose 32-bit RGBA integer without Lua 5.2+ bitwise operators (Lua 5.1 safe)
local function rgba(r, g, b, a)
    return (((r * 256 + g) * 256 + b) * 256) + a
end

function openScreensaver(self)
    if self.window then
        return
    end

    self.state       = Model.newState()
    self.lastTimeStr = nil
    self.fonts       = {}
    self.iconCache   = {}

    local screenW, screenH = Framework:getScreenSize()
    self.screenW = screenW or 320
    self.screenH = screenH or 240

    self.bgSurface = self:_buildShadedBackground(self.screenW, self.screenH)

    local window = Window("window")
    window:setAllowScreensaver(false)
    window:setShowFrameworkWidgets(false)

    self.canvas = Canvas("debug_canvas", function(screen)
        local ok, err = pcall(function()
            self:_drawOnScreen(screen)
        end)
        if not ok and log then
            log:warn("HAScreenSaver draw error: ", err)
        end
    end)
    window:addWidget(self.canvas)

    if EVENT_WINDOW_POP then
        window:addListener(EVENT_WINDOW_POP, function()
            self:_cleanup()
            return EVENT_UNUSED
        end)
    end

    if EVENT_WINDOW_INACTIVE then
        window:addListener(EVENT_WINDOW_INACTIVE, function()
            self:_stopTimers()
            return EVENT_UNUSED
        end)
    end

    if EVENT_WINDOW_ACTIVE then
        window:addListener(EVENT_WINDOW_ACTIVE, function()
            self:_startTimers()
            self:_fetchFromServer()
            return EVENT_UNUSED
        end)
    end

    local manager = appletManager:getAppletInstance("ScreenSavers")
    if manager then
        manager:screensaverWindow(window, true, nil, nil, "HAScreenSaver")
    end

    self.window = window
    self:_startTimers()
    self:_fetchFromServer()

    if jnt then
        jnt:subscribe(self)
    end

    window:show(Window.transitionFadeIn)
    self:_requestRedraw()
end

function closeScreensaver(self)
    if self.window then
        self.window:hide(Window.transitionFadeOut)
    end
    self:_cleanup()
end

function notify_serverConnected(self, server)
    if self.window then
        self:_fetchFromServer()
    end
end

function notify_playerAlarmState(self, player, alarmState)
    if self.window then
        self:_fetchFromServer()
    end
end

function _requestRedraw(self)
    if self.canvas then
        self.canvas:reDraw()
    end
end

function _buildShadedBackground(self, w, h)
    -- Pre-render a smooth dark charcoal-to-near-black vertical gradient once per session
    local bg = Surface:newRGBA(w, h)
    local topR, topG, topB = 28, 34, 44
    local botR, botG, botB = 6, 8, 12

    local bandStep = 2
    for y = 0, h - 1, bandStep do
        local t = y / (h - 1)
        local r = math.floor(topR + (botR - topR) * t + 0.5)
        local g = math.floor(topG + (botG - topG) * t + 0.5)
        local b = math.floor(topB + (botB - topB) * t + 0.5)
        local y2 = y + bandStep - 1
        if y2 >= h then y2 = h - 1 end
        bg:filledRectangle(0, y, w - 1, y2, rgba(r, g, b, 255))
    end
    return bg
end

function _startTimers(self)
    self:_stopTimers()

    self.clockTimer = Timer(1000, function()
        self:_onClockTick()
    end)
    self.clockTimer:start()

    local pollMs = (self.state and self.state.pollIntervalMs) or Model.DEFAULT_POLL_INTERVAL_MS
    self.pollTimer = Timer(pollMs, function()
        self:_fetchFromServer()
    end)
    self.pollTimer:start()
end

function _stopTimers(self)
    if self.clockTimer then
        self.clockTimer:stop()
        self.clockTimer = nil
    end
    if self.pollTimer then
        self.pollTimer:stop()
        self.pollTimer = nil
    end
end

function _cleanup(self)
    self:_stopTimers()
    if jnt then
        jnt:unsubscribe(self)
    end
    self.window      = nil
    self.canvas      = nil
    self.bgSurface   = nil
    self.fonts       = nil
    self.iconCache   = nil
    self.state       = nil
    self.lastTimeStr = nil
end

function _onClockTick(self)
    if not self.window or not self.state then
        return
    end

    local nowMs = Framework:getTicks()
    local staleChanged = Model.expireIfStale(self.state, nowMs)
    local curTime = self:_currentTimeString()

    if curTime ~= self.lastTimeStr or staleChanged then
        self:_requestRedraw()
    end
end

function _currentTimeString(self)
    local t = os.date("*t")
    local is12Hour = false
    if datetime and datetime.getHours then
        local ok, hrMode = pcall(function() return datetime:getHours() end)
        if ok and hrMode == "12" then
            is12Hour = true
        end
    end
    return Model.formatTime(t.hour, t.min, is12Hour)
end

function _markSensorsUnavailable(self)
    if not self.state then
        return
    end
    for i = 1, #self.state.sensors do
        self.state.sensors[i].value = "--"
        self.state.sensors[i].ok    = false
    end
    self.state.weatherIcon = ""
    self.state.alertActive = false
    self.state.alertText   = ""
end

function _fetchFromServer(self)
    if not self.window or not self.state then
        return
    end

    local okPlayer, player = pcall(function()
        return appletManager:callService("getCurrentPlayer")
    end)
    if not okPlayer or not player then
        return
    end

    -- Local alarm fallback
    if player.getAlarmState then
        local okAlarm, localAlarm = pcall(function() return player:getAlarmState() end)
        if okAlarm and localAlarm and localAlarm ~= "none" then
            self.state.alarmActive = true
        end
    end

    local okServer, server = pcall(function() return player:getSlimServer() end)
    if not okServer or not server then
        self:_markSensorsUnavailable()
        self:_requestRedraw()
        return
    end

    local playerId = player:getId()
    pcall(function()
        server:request(
            function(chunk, err)
                if not self.window or not self.state then
                    return
                end
                if err or not chunk or not chunk.data then
                    self:_markSensorsUnavailable()
                    self:_requestRedraw()
                    return
                end
                local prevInterval = self.state.pollIntervalMs
                Model.applyServerPayload(self.state, chunk.data, Framework:getTicks())

                if self.state.pollIntervalMs ~= prevInterval and self.pollTimer then
                    self.pollTimer:setInterval(self.state.pollIntervalMs)
                end

                self:_requestRedraw()
            end,
            playerId,
            { "hascreensaver", "sensors" }
        )
    end)
end

function _getFont(self, path, size)
    if not self.fonts then
        self.fonts = {}
    end
    local key = path .. ":" .. tostring(size)
    if not self.fonts[key] then
        local ok, f = pcall(function() return Font:load(path, size) end)
        if not ok or not f then
            f = Font:load(FALLBACK_FONT, size)
        end
        self.fonts[key] = f
    end
    return self.fonts[key]
end

function _getIcon(self, path)
    if not path then
        return nil
    end
    if not self.iconCache then
        self.iconCache = {}
    end
    if self.iconCache[path] == nil then
        local ok, img = pcall(function() return Surface:loadImage(path) end)
        self.iconCache[path] = (ok and img) or false
    end
    return self.iconCache[path] or nil
end

function _truncateText(self, font, text, maxWidth)
    if not text or text == "" then
        return ""
    end
    local s = text
    while #s > 1 and font:width(s) > maxWidth do
        s = string.sub(s, 1, #s - 1)
    end
    if s ~= text and #s > 3 then
        s = string.sub(s, 1, #s - 2) .. ".."
    end
    return s
end

-- Draw a single sensor cell with large bright value, smaller softer unit, and subtle label
function _drawSensorCell(self, surf, sensor, x, y, width, height, align, labelFont, valueFont, unitFont)
    if not sensor then
        return
    end

    local valColor = sensor.ok and COLOR_VALUE or COLOR_STALE
    local valStr   = sensor.value or "--"
    local unitStr  = (valStr ~= "--" and sensor.unit) or ""
    local lblStr   = self:_truncateText(labelFont, sensor.label or "", width)

    local unitSurf = (unitStr ~= "") and Surface:drawText(unitFont, COLOR_UNIT, unitStr) or nil
    local uw, uh   = 0, 0
    if unitSurf then
        uw, uh = unitSurf:getSize()
    end

    local maxValW = width - (unitSurf and (uw + 3) or 0)
    if maxValW < 24 then maxValW = width end
    valStr = self:_truncateText(valueFont, valStr, maxValW)

    local valSurf = Surface:drawText(valueFont, valColor, valStr)
    local vw, vh  = valSurf:getSize()

    local combinedW = vw + (unitSurf and (uw + 2) or 0)

    local lblSurf = (lblStr ~= "") and Surface:drawText(labelFont, COLOR_LABEL, lblStr) or nil
    local lw, lh  = 0, 0
    if lblSurf then
        lw, lh = lblSurf:getSize()
    end

    local totalH = vh + (lblSurf and (lh + 1) or 0)
    local startY = y + math.floor((height - totalH) / 2)
    if startY < y then startY = y end

    local valX
    local lblX
    if align == "right" then
        valX = x + width - combinedW
        lblX = x + width - lw
    elseif align == "center" then
        valX = x + math.floor((width - combinedW) / 2)
        lblX = x + math.floor((width - lw) / 2)
    else
        valX = x
        lblX = x
    end

    if lblSurf then
        lblSurf:blit(surf, lblX, startY)
    end

    local valY = startY + (lblSurf and (lh + 1) or 0)
    valSurf:blit(surf, valX, valY)

    if unitSurf then
        local unitY = valY + 3
        unitSurf:blit(surf, valX + vw + 2, unitY)
    end
end

function _drawOnScreen(self, surf)
    if not surf or not self.state then
        return
    end

    local w     = self.screenW
    local h     = self.screenH
    local state = self.state

    -- 1. Blit pre-rendered dark shaded gradient background
    if self.bgSurface then
        self.bgSurface:blit(surf, 0, 0)
    else
        surf:filledRectangle(0, 0, w - 1, h - 1, rgba(10, 12, 16, 255))
    end

    local weatherPath = Model.resolveWeatherIconPath(state.weatherIcon)
    local weatherImg  = weatherPath and self:_getIcon(weatherPath) or nil
    local hasWeather  = (weatherImg ~= nil)
    local hasTopBar   = state.alarmActive or (state.alertActive and state.alertText ~= "")
    local layout      = Model.computeLayout(w, h, #state.sensors, hasTopBar, hasWeather)

    local clockFontPath = Model.resolveFontPath(state.fontName)
    local uiFontBold    = self:_getFont("fonts/FreeSansBold.ttf", 12)

    -- 2. Top bar: Optional Door Alert Pill (top-left) + Optional Alarm Icon & Time (top-right)
    local alarmReserveW = 0
    if state.alarmActive then
        local alarmIcon = self:_getIcon(ICON_ALARM_PATH)
        local timeText  = (state.alarmTime ~= "") and state.alarmTime or "ON"
        local timeSurf  = Surface:drawText(uiFontBold, COLOR_ALARM, timeText)
        local tw, th    = timeSurf:getSize()
        local iw, ih    = 0, 0
        if alarmIcon then
            iw, ih = alarmIcon:getSize()
        end
        local totalW = tw + (alarmIcon and (iw + 4) or 0)
        alarmReserveW = totalW + 14

        local rightX = w - totalW - 8
        if alarmIcon then
            alarmIcon:blit(surf, rightX, 6)
            timeSurf:blit(surf, rightX + iw + 4, 6)
        else
            timeSurf:blit(surf, rightX, 6)
        end
    end

    if state.alertActive and state.alertText ~= "" then
        local maxAlertW = w - alarmReserveW - 18
        if maxAlertW > 44 then
            local doorIcon = self:_getIcon(ICON_DOOR_PATH)
            local iconPad  = doorIcon and 18 or 0
            local alertStr = self:_truncateText(uiFontBold, state.alertText, maxAlertW - iconPad - 12)
            local alertSurf = Surface:drawText(uiFontBold, COLOR_ALERT_TXT, alertStr)
            local tw, th = alertSurf:getSize()
            local pillW = tw + iconPad + 12
            local pillH = math.max(th + 6, 20)
            surf:filledRectangle(6, 4, 6 + pillW, 4 + pillH, COLOR_ALERT_BG)
            if doorIcon then
                local dw, dh = doorIcon:getSize()
                doorIcon:blit(surf, 10, 4 + math.floor((pillH - dh) / 2))
            end
            alertSurf:blit(surf, 12 + iconPad, 4 + math.floor((pillH - th) / 2))
        end
    end

    -- 3. Primary Digital Clock (HH:MM, no seconds, no date) with subtle drop shadow
    local timeStr = self:_currentTimeString()
    self.lastTimeStr = timeStr

    local clockFont   = self:_getFont(clockFontPath, layout.clockFontSize)
    local shadowSurf  = Surface:drawText(clockFont, COLOR_SHADOW, timeStr)
    local clockSurf   = Surface:drawText(clockFont, COLOR_CLOCK, timeStr)
    local cw, ch      = clockSurf:getSize()
    local cx          = math.floor((w - cw) / 2)
    local cy          = math.floor(layout.clockCenterY - (ch / 2))
    if cy < layout.topBarH then
        cy = layout.topBarH
    end
    shadowSurf:blit(surf, cx + 2, cy + 2)
    clockSurf:blit(surf, cx, cy)

    -- 4. Bottom Telemetry Band:
    --    Lower-Left = Sensor 1 (Outside), Bottom-Center = Weather Symbol, Lower-Right = Sensor 2 (Indoor)
    --    (3-4 sensors stack cleanly into left & right columns around the center weather symbol)
    if layout.hasBottom and layout.bottomBandY then
        local bandY = layout.bottomBandY
        surf:filledRectangle(0, bandY, w - 1, h - 1, rgba(4, 6, 10, 140))
        surf:filledRectangle(10, bandY, w - 11, bandY, COLOR_DIVIDER)

        local areaTop    = bandY + 4
        local areaHeight = h - areaTop - 4

        local centerReserveW = 0
        if weatherImg then
            local ww, wh = weatherImg:getSize()
            centerReserveW = ww + 12
            local wx = math.floor((w - ww) / 2)
            local wy = areaTop + math.floor((areaHeight - wh) / 2)
            weatherImg:blit(surf, wx, wy)
        end

        local count = #state.sensors
        if count > 0 then
            local labelFont = self:_getFont("fonts/FreeSans.ttf", layout.labelFontSize)
            local valueFont = self:_getFont("fonts/FreeSansBold.ttf", layout.valueFontSize)
            local unitFont  = self:_getFont("fonts/FreeSans.ttf", layout.unitFontSize)

            local sidePad = 12
            local sideW = math.floor((w - (sidePad * 2) - centerReserveW) / 2)
            local leftX = sidePad
            local rightX = w - sidePad - sideW

            if count == 1 then
                self:_drawSensorCell(surf, state.sensors[1], leftX, areaTop, sideW, areaHeight, "left", labelFont, valueFont, unitFont)
            elseif count == 2 then
                self:_drawSensorCell(surf, state.sensors[1], leftX, areaTop, sideW, areaHeight, "left", labelFont, valueFont, unitFont)
                self:_drawSensorCell(surf, state.sensors[2], rightX, areaTop, sideW, areaHeight, "right", labelFont, valueFont, unitFont)
            else
                local rowH = math.floor(areaHeight / 2)
                self:_drawSensorCell(surf, state.sensors[1], leftX,  areaTop,        sideW, rowH, "left",  labelFont, valueFont, unitFont)
                self:_drawSensorCell(surf, state.sensors[2], rightX, areaTop,        sideW, rowH, "right", labelFont, valueFont, unitFont)
                if state.sensors[3] then
                    self:_drawSensorCell(surf, state.sensors[3], leftX,  areaTop + rowH, sideW, rowH, "left",  labelFont, valueFont, unitFont)
                end
                if state.sensors[4] then
                    self:_drawSensorCell(surf, state.sensors[4], rightX, areaTop + rowH, sideW, rowH, "right", labelFont, valueFont, unitFont)
                end
            end
        end
    end
end
