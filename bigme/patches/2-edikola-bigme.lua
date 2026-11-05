-- EdiKOla on the Bigme B6 Pro Color (KOReader user patch, runs once KOReader's UI is ready).
-- KOReader's Android launcher has no entry for Bigme, so it may take the Kaleido 3 screen for a grayscale one:
-- covers and photos would show in gray and the color-rendering switch would be hidden. This package is only
-- for the Bigme, so on Android the screen is said to have color, whatever the device calls itself, and color
-- rendering is turned on once (it stays switchable in KOReader's Screen menu).
local Device = require("device")
if not Device:isAndroid() then return end

local id = {}
for k, v in pairs(require("android").prop or {}) do
    if type(v) == "string" then id[#id + 1] = k .. "=" .. v end
end
require("logger").info("EdiKOla: device", table.concat(id, " ")) -- in crash.log, for reports

if not Device:hasColorScreen() then
    local yes = function() return true end
    Device.hasColorScreen = yes
    Device.screen.isColorScreen = yes
end
if not G_reader_settings:has("color_rendering") then
    G_reader_settings:makeTrue("color_rendering")
    require("document/canvascontext"):setColorRenderingEnabled(true)
end
