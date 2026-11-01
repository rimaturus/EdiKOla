-- KOReader user patch (emulator only): swaps in the demo catalog, then walks through the
-- EdiKOla screens and saves a PNG of each to $KNP_SHOTS. Installed by run.sh, never on the Kobo.
local Device = require("device")
local UIManager = require("ui/uimanager")

package.loaded["giornali"] = dofile(os.getenv("XDG_DOCUMENTS_DIR") .. "/giornali_demo.lua")

local last
local show = UIManager.show
UIManager.show = function(self, widget, ...)
    last = widget
    return show(self, widget, ...)
end

local out = os.getenv("KNP_SHOTS")
local function shot(name) Device.screen:shot(out .. "/" .. name .. ".png") end
local function edicola() return require("apps/filemanager/filemanager").instance.konewspaper.Edicola end

local steps = {
    function() shot("01-edicola-italia") end,
    function() local e = edicola().instance; e.section = "mondo"; e:redraw() end,
    function() shot("02-edicola-mondo") end,
    function() edicola().instance:showCatalog() end,
    function() shot("03-giornali"); UIManager:close(last) end,
    function() edicola().instance:showBooks() end,
    function() shot("04-libri"); UIManager:close(last) end,
    function() Device:showLightDialog() end,
    function() shot("05-luce"); UIManager:close(last) end,
    function()
        local dir = os.getenv("XDG_DOCUMENTS_DIR") .. "/KoNewspaper/borgo/"
        edicola().instance:open(dir .. os.date("%Y-%m-%d") .. ".epub")
    end,
    function() shot("06-prima-pagina") end,
    function() UIManager:sendEvent(require("ui/event"):new("GotoViewRel", 1)) end,
    function() shot("07-articolo") end,
    function() os.exit(0) end,
}

local i = 0
local function step()
    i = i + 1
    local ok, err = pcall(steps[i])
    if not ok then print("SHOT STEP FAILED", i, err) end
    if steps[i + 1] then UIManager:scheduleIn(3, step) end
end
UIManager:scheduleIn(6, step)
