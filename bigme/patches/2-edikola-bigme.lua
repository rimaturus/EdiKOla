-- EdiKOla on the Bigme B6 Pro Color (KOReader user patch, runs once KOReader's UI is ready).
-- KOReader's Android launcher has no entry for Bigme, so it may take the Kaleido 3 screen for a grayscale one:
-- covers and photos would show in gray and the color-rendering switch would be hidden. On a Bigme, say the
-- screen has color and turn color rendering on once (it stays switchable in Impostazioni > Schermo).
local Device = require("device")
if not Device:isAndroid() then return end
local logger = require("logger")
local android = require("android")

local id = {}
for k, v in pairs(android.prop or {}) do
    if type(v) == "string" then id[#id + 1] = k .. "=" .. v end
end
local props = table.concat(id, " ")
logger.info("EdiKOla: device", props) -- in crash.log, for when the check below needs another name
if not props:lower():find("bigme", 1, true) then return end

if not Device:hasColorScreen() then
    local yes = function() return true end
    Device.hasColorScreen = yes
    Device.screen.isColorScreen = yes
end
if not G_reader_settings:has("color_rendering") then
    G_reader_settings:makeTrue("color_rendering")
    require("document/canvascontext"):setColorRenderingEnabled(true)
end
