-- KOReader user patch (emulator only): swaps in the demo catalog, then walks through the
-- EdiKOla screens and saves a PNG of each to $KNP_SHOTS. Installed by run.sh, never on the Kobo.
local Device = require("device")
local UIManager = require("ui/uimanager")

package.loaded["giornali"] = dofile(os.getenv("XDG_DOCUMENTS_DIR") .. "/giornali_demo.lua")

local last, sommario
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
    function() local e = edicola().instance; e.section = "buone"; e:redraw() end,
    function() shot("09-edicola-buone") end,
    function() local e = edicola().instance; e.section = "scienza"; e:redraw() end,
    function() shot("10-edicola-scienza"); local e = edicola().instance; e.section = "italia"; e:redraw() end,
    function() edicola().instance:showNews() end,
    function() shot("11-sommario"); sommario = last; last.items[1].callback() end, -- open the first topic
    function() shot("12-sommario-argomenti"); UIManager:close(last); UIManager:close(sommario) end,
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
    function() -- pen notes on this article, if on (Bigme): strokes go through the real input hook
        if not G_reader_settings:isTrue("konewspaper_notes") then return end
        require("apps/reader/readerui").instance.konewspaper:openNote()
    end,
    function()
        if not G_reader_settings:isTrue("konewspaper_notes") then return end
        local sheet, W = last, Device.screen:getWidth()
        local function stroke(pts, tool)
            for k = 1, #pts, 2 do -- pressure rises and falls along the stroke, like a real pen
                Device.input.routeStylusEvents{ MTSlots = { { slot = 0, id = 1, x = pts[k], y = pts[k + 1],
                    tool = tool or 1, pressure = 0.25 + 0.7 * math.sin(math.pi * k / #pts) } } }
            end
            Device.input.routeStylusEvents{ MTSlots = { { slot = 0, id = -1, x = pts[#pts - 1], y = pts[#pts], tool = tool or 1 } } }
        end
        _G.knp_stroke = stroke
        local top = sheet.paper.y
        local function handwriting(y, x0, x1, seed) -- loops along a line, like cursive
            local pts = {}
            for x = x0, x1, 3 do
                local t = (x + seed) / 9
                pts[#pts + 1] = x + math.floor(6 * math.cos(t))
                pts[#pts + 1] = y - math.floor(14 * math.abs(math.sin(t * 0.5)) + 4 * math.sin(t * 1.7))
            end
            stroke(pts)
        end
        local step = Device.screen:scaleBySize(34)
        sheet.ink = "nero"
        for r = 1, 5 do handwriting(top + step * (r + 1) - 4, Device.screen:scaleBySize(70), W - Device.screen:scaleBySize(60) - r * 37 % 200, r * 13) end
        sheet.ink = "rosso" -- a circle around a word, an arrow
        local cx, cy, rad, pts = Device.screen:scaleBySize(200), top + step * 2 - 10, Device.screen:scaleBySize(60), {}
        for a = 0, 6.4, 0.08 do pts[#pts + 1] = cx + math.floor(rad * 1.6 * math.cos(a)); pts[#pts + 1] = cy + math.floor(rad * 0.55 * math.sin(a)) end
        stroke(pts)
        stroke({ cx + rad, cy + rad, cx + rad * 2, cy + rad * 3, cx + rad * 2 - 20, cy + rad * 3 - 30 })
        sheet.ink = "blu"
        handwriting(top + step * 9 - 4, Device.screen:scaleBySize(70), W / 2, 5)
        sheet.ink = "verde" -- a tick
        stroke({ W - 200, top + step * 9 - 30, W - 170, top + step * 9, W - 110, top + step * 9 - 70 })
        stroke({ W / 2, top + step * 12 }) -- a dot: short touches count
        -- the pen has been seen: a finger (or a resting hand) on the paper must not draw
        local n = #sheet.note.strokes
        stroke({ 300, top + step * 14, 600, top + step * 15 }, 0)
        if #sheet.note.strokes ~= n then print("SHOT STEP FAILED finger drew after the pen") end
        if not G_reader_settings:isTrue("konewspaper_pen_seen") then print("SHOT STEP FAILED pen not noticed") end
        if not sheet.note.strokes[1].q then print("SHOT STEP FAILED no pressure kept") end
    end,
    function()
        if not G_reader_settings:isTrue("konewspaper_notes") then return end
        shot("14-appunti")
        -- eraser on the green tick, then undo; Pulisci, then undo
        local sheet, step = last, Device.screen:scaleBySize(34)
        local n0, W = #sheet.note.strokes, Device.screen:getWidth()
        knp_stroke({ W - 170, sheet.paper.y + step * 9 }, 2) -- the pen's eraser end on the tick
        if #sheet.note.strokes ~= n0 - 1 then print("SHOT STEP FAILED eraser end", n0, #sheet.note.strokes) end
        sheet:undo()
        sheet.eraser = true -- the Gomma button
        sheet:penDown(W - 170, step * 9); sheet:penUp()
        if #sheet.note.strokes ~= n0 - 1 then print("SHOT STEP FAILED eraser", n0, #sheet.note.strokes) end
        sheet:undo()
        sheet:clear()
        if #sheet.note.strokes ~= 0 then print("SHOT STEP FAILED clear") end
        sheet:undo()
        if #sheet.note.strokes ~= n0 then print("SHOT STEP FAILED undo", n0, #sheet.note.strokes) end
        sheet.eraser = false
        UIManager:close(sheet)
    end,
    function() -- tap on the article photo
        local Geom = require("ui/geometry")
        local ui = require("apps/reader/readerui").instance
        for y = 0, Device.screen:getHeight(), 20 do
            local pos = Geom:new{ x = Device.screen:getWidth() / 2, y = y, w = 0, h = 0 }
            local p = ui.view:screenToPageTransform(pos)
            if p and ui.document:getImageFromPosition(p) then
                UIManager:sendEvent(require("ui/event"):new("Gesture", { ges = "tap", pos = pos }))
                return
            end
        end
        print("SHOT STEP FAILED no photo found")
    end,
    function() shot("08-foto-zoom"); UIManager:close(last) end,
    function() require("apps/reader/readerui").instance:onHome() end,
    function() -- Sommario → second article of the paper: the reader must open at it
        local dir = os.getenv("XDG_DOCUMENTS_DIR") .. "/KoNewspaper/borgo/"
        edicola().instance:openArticle(dir .. os.date("%Y-%m-%d") .. ".epub", 2)
    end,
    function() shot("13-articolo-dal-sommario") end,
    function()
        if not G_reader_settings:isTrue("konewspaper_notes") then return end
        require("apps/reader/readerui").instance:onHome()
    end,
    function()
        if not G_reader_settings:isTrue("konewspaper_notes") or not os.getenv("KNP_HWR") then return end
        local sheet = require("knp_notes").open("foglio-prova", { title = "Foglio libero", sub = "prova" })
        _G.knp_hwr_sheet = sheet
        local y, h = sheet.paper.y + 120, 160
        local one, zero = {}, {}
        for t = 0, h, 6 do one[#one + 1] = 300; one[#one + 1] = y + t end
        for a = 0, 6.3, 0.15 do zero[#zero + 1] = 480 + math.floor(60 * math.sin(a)); zero[#zero + 1] = y + h / 2 - math.floor(h / 2 * math.cos(a)) end
        knp_stroke(one); knp_stroke(zero)
        G_reader_settings:makeTrue("konewspaper_hwr_ok") -- the one-time question, answered
        sheet:transcribe()
    end,
    function()
        if not G_reader_settings:isTrue("konewspaper_notes") or not os.getenv("KNP_HWR") then return end
        shot("17-trascrizione")
        UIManager:close(last) -- the text
    end,
    function()
        if not G_reader_settings:isTrue("konewspaper_notes") or not os.getenv("KNP_HWR") then return end
        last = knp_hwr_sheet
        print("KNP transcription:", last.note.text)
        if last.note.text ~= "10" then print("SHOT STEP FAILED transcription", last.note.text) end
        UIManager:close(last) -- the sheet: saved with its text
    end,
    function()
        if not G_reader_settings:isTrue("konewspaper_notes") then return end
        edicola().instance:showNotebook()
    end,
    function()
        if not G_reader_settings:isTrue("konewspaper_notes") then return end
        shot("15-taccuino")
        for _, it in ipairs(last.items) do -- the note of the article: with its "Articolo" button
            if it.title:find("mercato") then return it.callback() end
        end
        print("SHOT STEP FAILED article note not in the notebook")
    end,
    function()
        if not G_reader_settings:isTrue("konewspaper_notes") then return end
        if #last.note.strokes == 0 then print("SHOT STEP FAILED note not saved") end
        shot("16-appunti-dal-taccuino")
    end,
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
