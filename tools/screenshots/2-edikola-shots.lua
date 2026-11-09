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
    function() -- the pen writes straight on the article (Bigme): strokes go through the real input hook
        local ui = require("apps/reader/readerui").instance
        local pen = ui.konewspaper.pen
        if not pen then return print("SHOT STEP FAILED no pen ink in the reader") end
        local W, s = Device.screen:getWidth(), Device.screen:scaleBySize(1)
        local function stroke(pts, tool)
            for k = 1, #pts, 2 do -- pressure rises and falls along the stroke, like a real pen
                Device.input.routeStylusEvents{ MTSlots = { { slot = 0, id = 1, x = pts[k], y = pts[k + 1],
                    tool = tool or 1, pressure = 0.25 + 0.7 * math.sin(math.pi * k / #pts) } } }
            end
            Device.input.routeStylusEvents{ MTSlots = { { slot = 0, id = -1, x = pts[#pts - 1], y = pts[#pts], tool = tool or 1 } } }
        end
        _G.knp_stroke, _G.knp_pen = stroke, pen
        pen.color = "rosso" -- a line underlined, a word circled
        stroke({ 30 * s, 345 * s, W - 40 * s, 349 * s })
        local cx, cy, rad, pts = 230 * s, 272 * s, 48 * s, {}
        for a = 0, 6.4, 0.08 do pts[#pts + 1] = cx + math.floor(rad * 1.8 * math.cos(a)); pts[#pts + 1] = cy + math.floor(rad * 0.6 * math.sin(a)) end
        stroke(pts)
        pen.color = "blu" -- a note, joined-up
        local hw = {}
        for x = 40 * s, 320 * s, 3 do
            local t = x / 9
            hw[#hw + 1] = x + math.floor(6 * math.cos(t)); hw[#hw + 1] = 470 * s - math.floor(14 * math.abs(math.sin(t * 0.5)))
        end
        stroke(hw)
        pen.color = "verde" -- a tick
        stroke({ W - 200, 600 * s, W - 170, 630 * s, W - 110, 560 * s })
        -- a finger on the page must not draw: fingers turn pages
        local n = #pen:page().strokes
        stroke({ 300, 700 * s, 600, 720 * s }, 0)
        if #pen:page().strokes ~= n then print("SHOT STEP FAILED finger drew") end
        if n ~= 4 then print("SHOT STEP FAILED strokes", n) end
        if not pen:page().strokes[1].q then print("SHOT STEP FAILED no pressure kept") end
        UIManager:setDirty(ui, "full")
    end,
    function()
        shot("14-penna-sull-articolo")
        -- the pen's eraser end on the tick, then undo
        local pen, W, s = knp_pen, Device.screen:getWidth(), Device.screen:scaleBySize(1)
        local n0 = #pen:page().strokes
        knp_stroke({ W - 170, 630 * s }, 2)
        if #pen:page().strokes ~= n0 - 1 then print("SHOT STEP FAILED eraser end", n0, #pen:page().strokes) end
        pen:undo()
        if #pen:page().strokes ~= n0 then print("SHOT STEP FAILED undo", n0, #pen:page().strokes) end
        _G.knp_page_key = pen:key()
        UIManager:sendEvent(require("ui/event"):new("GotoViewRel", 1))
    end,
    function() -- the next page has no ink; back again, the ink is there
        if knp_pen:page() then print("SHOT STEP FAILED ink on the next page") end
        UIManager:sendEvent(require("ui/event"):new("GotoViewRel", -1))
    end,
    function()
        if knp_pen:key() ~= knp_page_key or not knp_pen:page() then print("SHOT STEP FAILED ink lost going back") end
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
    function() -- the ink was saved: the paper, opened again, still has it
        local ui = require("apps/reader/readerui").instance
        local n = 0
        for _ in pairs(ui.konewspaper.pen.doc.pages) do n = n + 1 end
        if n ~= 1 then print("SHOT STEP FAILED ink not saved", n) end
        ui:onHome()
    end,
    function() -- back to the newsstand: close whatever the steps above left open (the notebook, a sheet)
        local stack = UIManager._window_stack
        for i = #stack, 1, -1 do
            local w = stack[i].widget
            if w == edicola().instance then break end
            UIManager:close(w)
        end
    end,
    -- a shelf scrolls: Italia has a second page, with the "+ Altri giornali" place
    function() local e = edicola().instance; e.section = "italia"; e.page = 2; e:redraw() end,
    function() shot("20-edicola-pagina-2") end,
    function() edicola().instance:showCatalog("italia") end,
    function() shot("21-giornali-di-italia"); UIManager:close(last); local e = edicola().instance; e.page = 1; e:redraw() end,
    -- the newspaper reader: "Prossimo" opens the next paper of the shelf
    function()
        local dir = os.getenv("XDG_DOCUMENTS_DIR") .. "/KoNewspaper/borgo/"
        edicola().instance:open(dir .. os.date("%Y-%m-%d") .. ".epub")
    end,
    function() shot("22-lettore-prossimo") end,
    function() require("apps/reader/readerui").instance:onHome() end,
    -- Enigmistica
    function() edicola().instance:showGiochi() end,
    function() shot("30-enigmistica"); last.items[1].callback(); _G.knp_game = last end,
    function() shot("31-cruciverba") end,
    function() -- write the first word, then a wrong letter elsewhere, then "Controlla"
        local g = knp_game
        local wd = g:current()
        for k = 1, #wd.word do g:type(wd.word:sub(k, k)) end
        local dx, dy = wd.dir == "a" and 1 or 0, wd.dir == "d" and 1 or 0
        for k = 0, #wd.word - 1 do
            local x, y = wd.x + dx * k, wd.y + dy * k
            if g.st.cur[y]:sub(x, x) ~= wd.word:sub(k + 1, k + 1) then print("SHOT STEP FAILED crossword typing", wd.word) end
        end
        local tx, ty
        for y = 1, g.st.cw.h do
            for x = 1, g.st.cw.w do
                local sol = g.st.cw.rows[y]:sub(x, x)
                if not tx and sol ~= "." and sol ~= "Z" and g.st.cur[y]:sub(x, x) == " " then tx, ty = x, y end
            end
        end
        g.board.on_tap(tx, ty)
        g:type("Z")
        g:check()
        local wrong = 0
        for _ in pairs(g.st.wrong) do wrong = wrong + 1 end
        if wrong ~= 1 or not g.st.wrong[ty * 100 + tx] then print("SHOT STEP FAILED crossword check", wrong) end
    end,
    function() shot("32-cruciverba-in-corso"); UIManager:close(last) end, -- the message
    function() -- the pen writes a letter in an empty square, as on paper
        local g = knp_game
        -- strokes of a character, drawn inside square (c, r) of the game's grid
        _G.knp_write = function(game, c, r, ch)
            local b = game.board
            local x0 = b.dimen.x + (c - 1) * b.size + b.size * 0.2
            local y0 = b.dimen.y + (r - 1) * b.size + b.size * 0.15
            for _, st in ipairs(require("knp_scrittura").shapes[ch][1]) do
                local pts = {}
                for i = 1, #st - 1, 2 do
                    pts[#pts + 1] = math.floor(x0 + st[i] * b.size * 0.6)
                    pts[#pts + 1] = math.floor(y0 + st[i + 1] * b.size * 0.7)
                end
                knp_stroke(pts)
            end
            game:readWriting() -- what the 0.8 s pause would do
        end
        for y = 1, g.st.cw.h do
            for x = 1, g.st.cw.w do
                local sol = g.st.cw.rows[y]:sub(x, x)
                if not _G.knp_pen_cell and sol ~= "." and g.st.cur[y]:sub(x, x) == " " then _G.knp_pen_cell = { x, y, sol } end
            end
        end
        local x, y, sol = knp_pen_cell[1], knp_pen_cell[2], knp_pen_cell[3]
        knp_write(g, x, y, sol)
        if g.st.cur[y]:sub(x, x) ~= sol then print("SHOT STEP FAILED pen letter", sol, g.st.cur[y]:sub(x, x)) end
        -- a key typed over the pen's letter in that square teaches the reader; then the right letter back
        local other = sol == "A" and "B" or "A"
        g:type(other)
        g.sel.x, g.sel.y = x, y
        g:type(sol)
    end,
    function() shot("38-cruciverba-penna") end,
    function() UIManager:close(knp_game) end, -- the crossword: the menu comes back
    function() last.items[2].callback(); knp_game = last end,
    function() shot("33-crucipuzzle") end,
    function() -- find three words, tapping first and last letter (one of them backwards)
        local g = knp_game
        for i = 1, 3 do
            local p = g.st.wp.words[i]
            local n = #p.word - 1
            local a, b = { p.x, p.y }, { p.x + p.dx * n, p.y + p.dy * n }
            if i == 2 then a, b = b, a end
            g:tap(a[1], a[2]); g:tap(b[1], b[2])
        end
        if g.st.nfound ~= 3 then print("SHOT STEP FAILED crucipuzzle found", g.st.nfound) end
    end,
    function() shot("34-crucipuzzle-in-corso"); knp_game:solve() end,
    function() shot("35-crucipuzzle-chiave"); UIManager:close(knp_game) end,
    function() last.items[4].callback(); knp_game = last end, -- sudoku medio
    function()
        local g = knp_game
        local empty
        for i = 1, 81 do if g.st.puz:sub(i, i) == "0" then empty = i; break end end
        g.board.on_tap((empty - 1) % 9 + 1, math.floor((empty - 1) / 9) + 1)
        g:put(g.st.sol:sub(empty, empty))
        if g.st.cur:sub(empty, empty) ~= g.st.sol:sub(empty, empty) then print("SHOT STEP FAILED sudoku put") end
        g:hint()
    end,
    function() shot("36-sudoku"); UIManager:close(knp_game) end,
    function() shot("37-enigmistica-dopo") end,
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
