local oo            = require("loop.simple")
local AppletMeta    = require("jive.AppletMeta")
local appletManager = appletManager

module(...)
oo.class(_M, AppletMeta)

function jiveVersion(meta)
    return 1, 1
end

function defaultSettings(meta)
    -- No sensor data is ever stored in radio settings/flash
    return {}
end

function registerApplet(meta)
end

function configureApplet(meta)
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
end
