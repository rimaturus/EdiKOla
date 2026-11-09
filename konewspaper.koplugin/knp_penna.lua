--[[--
Pen ink on what is being read: write with the pen straight on an article or a book page.

- Only the pen writes; its eraser end (or the side button) rubs out whole strokes. Fingers keep turning
  pages, following links and zooming photos as before. Nothing to switch on: the pen just writes.
- Strokes show up as the pen moves: drawn straight into the screen buffer and refreshed only in the little
  rectangle each bit of stroke touched. knp_android passes on Android's in-between pen positions, so the
  line is continuous, and E-Ink Center's handwriting mode is on while the pen works (Bigme).
- Ink belongs to its page: one file per document in <home>/Appunti/<doc>.lua (knp_ink), page by page.
  A page is known by where it starts in the text, so its ink comes back with the same text size.
- The "Penna" button (once a pen has been seen): ink color, undo, clear the page.

    local pen = require("knp_penna").attach(ui, { top = y, on_pen = function() end })  -- pen:detach()
]]
local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local Geom = require("ui/geometry")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ink = require("knp_ink")
local theme = require("knp_theme")
local Screen = Device.screen

local PEN, ERASER = 1, 2 -- slot.tool, as on Kobo pen panels (knp_android adds them on Android)
local DIR = (Device.home_dir or "/mnt/onboard") .. "/Appunti"

local M = { INKS = { { "nero", "Nero" }, { "blu", "Blu" }, { "rosso", "Rosso" }, { "verde", "Verde" } } }

function M.penSeen() return G_reader_settings:isTrue("konewspaper_pen_seen") end

local Ink = {}
Ink.__index = Ink

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

--- Attaches ink to a ReaderUI. opts.top: pen touches above this y stay taps (the top bar's buttons);
-- opts.on_pen(): the first time a pen is seen, so the caller can show its "Penna" button.
function M.attach(ui, opts)
    local self = setmetatable({ ui = ui, opts = opts or {}, history = {} }, Ink)
    self.color = G_reader_settings:readSetting("konewspaper_ink") or "nero"
    self.path = DIR .. "/" .. ink.id(ui.document.file) .. ".lua"
    self.doc = ink.decode(readFile(self.path)) or { v = 2, pages = {} }
    self.dot = math.max(2, Screen:scaleBySize(2))
    self.sw, self.sh = Screen:getWidth(), Screen:getHeight()
    ui.view:registerViewModule("konewspaper_ink", { paintTo = function(_, bb, x, y) self:paint(bb, x, y) end })
    self:hook()
    return self
end

-- where the page on screen starts: the top of the page in the text, or the page number in a PDF
function Ink:key()
    if self.ui.rolling then
        local ok, xp = pcall(self.ui.document.getXPointer, self.ui.document)
        if ok and xp then return xp end
    end
    return "p" .. tostring(self.ui:getCurrentPage())
end

function Ink:page(create)
    local k = self:key()
    local pg = self.doc.pages[k]
    if not pg and create then
        pg = { w = self.sw, h = self.sh, strokes = {} }
        self.doc.pages[k] = pg
    end
    if pg then ink.fit(pg, self.sw, self.sh) end
    return pg, k
end

-- one bit of stroke, as squares of side d along it; returns the rectangle it touched
local function segment(bb, ox, oy, c, x0, y0, x1, y1, d)
    d = d or math.max(2, Screen:scaleBySize(2))
    local half = math.floor(d / 2)
    local steps = math.max(1, math.ceil(math.max(math.abs(x1 - x0), math.abs(y1 - y0)) / math.max(1, half)))
    for i = 0, steps do
        theme.rect(bb, ox + math.floor(x0 + (x1 - x0) * i / steps) - half, oy + math.floor(y0 + (y1 - y0) * i / steps) - half, d, d, c)
    end
    return Geom:new{ x = ox + math.min(x0, x1) - half, y = oy + math.min(y0, y1) - half,
        w = math.abs(x1 - x0) + d, h = math.abs(y1 - y0) + d }
end

function Ink:stroke(bb, ox, oy, st)
    local c, p, q = theme.color(st.c), st.p, st.q
    if #p == 2 then return segment(bb, ox, oy, c, p[1], p[2], p[1], p[2], ink.width(self.dot, q and q[1])) end
    for i = 1, #p - 3, 2 do
        segment(bb, ox, oy, c, p[i], p[i + 1], p[i + 2], p[i + 3], ink.width(self.dot, q and q[(i + 1) / 2 + 1]))
    end
end

-- the reader's view module: the page's ink over the page, at every repaint
function Ink:paint(bb, x, y)
    local pg = self:page()
    if not pg then return end
    for _, st in ipairs(pg.strokes) do self:stroke(bb, x, y, st) end
end

-- straight to the screen, no repaint of the page: the fastest the panel can follow the pen
function Ink:show(r)
    UIManager:setDirty(nil, "fast", r)
end

-- E-Ink Center's handwriting waveform while the pen works, back to the reading one 3 s after it lifts
function Ink:fastPanel(on)
    if not Device:isAndroid() then return end
    local A = require("knp_android")
    self.restore = self.restore or function()
        if self.eink_old then A.einkMode(self.eink_old > 0 and self.eink_old or 178) end
        self.eink_old = nil
    end
    UIManager:unschedule(self.restore)
    if on then
        if self.eink_old == nil then self.eink_old = A.einkMode(A.HANDWRITE_MODE) or false end
    else
        UIManager:scheduleIn(3, self.restore)
    end
end

function Ink:remember(k, pg)
    local copy = {}
    for i, st in ipairs(pg.strokes) do copy[i] = st end
    self.history[k] = self.history[k] or {}
    table.insert(self.history[k], copy)
    if #self.history[k] > 50 then table.remove(self.history[k], 1) end
end

function Ink:down(x, y, tool, pressure)
    self:fastPanel(true)
    if tool == ERASER then
        self.rubbing, self.rubbed = true, false
        return self:erase(x, y)
    end
    local pg, k = self:page(true)
    self:remember(k, pg)
    local q = ink.level(pressure)
    self.cur = { c = self.color, p = { x, y }, q = q and { q } or nil }
    table.insert(pg.strokes, self.cur)
    self:show(segment(Screen.bb, 0, 0, theme.color(self.color), x, y, x, y, ink.width(self.dot, q)))
end

function Ink:move(x, y, pressure)
    if self.rubbing then return self:erase(x, y) end
    local st = self.cur
    if not st then return end
    local p = st.p
    local lx, ly = p[#p - 1], p[#p]
    if math.abs(x - lx) + math.abs(y - ly) < 2 then return end
    p[#p + 1], p[#p + 2] = x, y
    local q
    if st.q then
        q = ink.level(pressure) or st.q[#st.q]
        st.q[#st.q + 1] = q
    end
    self:show(segment(Screen.bb, 0, 0, theme.color(st.c), lx, ly, x, y, ink.width(self.dot, q)))
end

function Ink:up()
    self.cur, self.rubbing = nil, false
    self:fastPanel(false)
    self:save()
end

function Ink:erase(x, y)
    local pg, k = self:page()
    if not pg then return end
    local r, hit = Screen:scaleBySize(14), false
    for i = #pg.strokes, 1, -1 do
        if ink.hit(pg.strokes[i], x, y, r) then
            if not self.rubbed then self:remember(k, pg); self.rubbed = true end -- one undo step per rub
            table.remove(pg.strokes, i)
            hit = true
        end
    end
    if hit then UIManager:setDirty(self.ui, "ui") end
end

function Ink:undo()
    local pg, k = self:page()
    local prev = self.history[k] and table.remove(self.history[k])
    if not (pg and prev) then return end
    pg.strokes = prev
    self:save()
    UIManager:setDirty(self.ui, "ui")
end

function Ink:clearPage()
    local pg, k = self:page()
    if not pg or #pg.strokes == 0 then return end
    self:remember(k, pg)
    pg.strokes = {}
    self:save()
    UIManager:setDirty(self.ui, "ui")
end

function Ink:save()
    local text = ink.encode(self.doc)
    if not text then return os.remove(self.path) end
    lfs.mkdir(DIR)
    local f = io.open(self.path, "wb")
    if not f then return logger.warn("EdiKOla: can't save ink", self.path) end
    f:write(text)
    f:close()
end

--- The "Penna" button's menu
function Ink:menu(on_color)
    local dialog
    local row = {}
    for _, i in ipairs(M.INKS) do
        table.insert(row, { text = (i[1] == self.color and "[" .. i[2] .. "]" or i[2]), callback = function()
            UIManager:close(dialog)
            self.color = i[1]
            G_reader_settings:saveSetting("konewspaper_ink", i[1])
            if on_color then on_color() end
        end })
    end
    dialog = ButtonDialog:new{
        title = "Penna: scrivi sull'articolo, il gommino cancella",
        buttons = {
            row,
            { { text = "Annulla l'ultimo tratto", callback = function() UIManager:close(dialog); self:undo() end },
              { text = "Cancella la pagina", callback = function() UIManager:close(dialog); self:clearPage() end } },
        },
    }
    UIManager:show(dialog)
end

-- Raw touches, before gestures: a pen contact on the page draws until it lifts; anything else
-- (fingers, and the pen on the top bar) goes on to KOReader's gestures as usual.
function Ink:feed(s)
    if not (s.x and s.y) then return false end
    local x, y = M.position(s)
    if self.slot == s.slot then
        if s.id == -1 then
            self.slot = nil
            self:up()
        else
            self:move(x, y, s.pressure)
        end
        return true
    end
    if s.id == -1 or not (s.tool == PEN or s.tool == ERASER) or self.slot then return false end
    if y < (self.opts.top or 0) then return false end
    if not M.penSeen() then
        G_reader_settings:makeTrue("konewspaper_pen_seen")
        G_reader_settings:flush()
        if self.opts.on_pen then self.opts.on_pen() end
    end
    self.slot = s.slot
    self:down(x, y, s.tool, s.pressure)
    return true
end

--- Raw contacts, before KOReader's gestures: handler(slot) returns true for the ones it takes (they never
-- become taps or swipes). Returns the function that gives the contacts back to whoever had them before.
function M.capture(handler)
    local input = Device.input
    local saved = rawget(input, "routeStylusEvents")
    input.routeStylusEvents = function(inp)
        local slots = inp.MTSlots
        if not slots or #slots == 0 then return end
        local keep = {}
        for _, s in ipairs(slots) do
            if not handler(s) then keep[#keep + 1] = s end
        end
        if #keep ~= #slots then
            for i = #slots, 1, -1 do slots[i] = nil end
            for i, s in ipairs(keep) do slots[i] = s end
        end
    end
    return function() input.routeStylusEvents = saved end
end

--- A contact's position on screen (rotation applied), clamped to the screen
function M.position(s)
    local g = Device.input.gesture_detector:adjustGesCoordinate{ ges = "touch", pos = Geom:new{ x = s.x, y = s.y, w = 0, h = 0 } }
    return math.max(0, math.min(math.floor(g.pos.x), Screen:getWidth() - 1)),
        math.max(0, math.min(math.floor(g.pos.y), Screen:getHeight() - 1))
end

M.segment = segment
M.PEN, M.ERASER = PEN, ERASER
M.fastPanel = function(owner, on) return Ink.fastPanel(owner, on) end

function Ink:hook()
    self.release = M.capture(function(s) return self:feed(s) end)
end

function Ink:detach()
    self.release()
    if self.restore then UIManager:unschedule(self.restore); self.restore() end
    self:save()
end

return M
