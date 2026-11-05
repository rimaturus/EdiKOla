--[[--
Pen notes ("Appunti"): a ruled sheet to write on with the pen (or a finger), one per article, plus free sheets.
- Toolbar: Fine (saves and closes), Articolo (from the notebook), four inks, Gomma (erases whole strokes), Annulla, Pulisci.
- Every touch that starts on the paper draws: it is taken before KOReader's gesture detection, so dots and
  short strokes count too (Input:routeStylusEvents, which on Android never sees a pen of its own).
- Saved in <home>/Appunti: <id>.lua (the strokes, knp_ink.lua) and <id>.png (a picture, for the
  notebook and for copying to a computer). An empty sheet deletes both.
]]
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ink = require("knp_ink")
local theme = require("knp_theme")
local Screen = Device.screen

local Notes = { dir = (Device.home_dir or "/mnt/onboard") .. "/Appunti" }

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

-- An ink swatch: a colored square, a thick border when it's the pen's ink
local Swatch = InputContainer:extend{ ink = nil, size = nil, selected = false, callback = nil }
function Swatch:init()
    self.ges_events = { Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
    local b = Screen:scaleBySize(self.selected and 5 or 2)
    self[1] = FrameContainer:new{
        bordersize = b, padding = Screen:scaleBySize(4), radius = 0,
        background = Blitbuffer.COLOR_WHITE,
        theme.Box:new{ width = self.size - 2 * b - 2 * Screen:scaleBySize(4), height = self.size - 2 * b - 2 * Screen:scaleBySize(4),
            color = theme.color(self.ink) },
    }
end
function Swatch:onTap() self.callback(); return true end

local Sheet = InputContainer:extend{
    covers_fullscreen = true,
    note = nil,   -- see knp_ink.lua
    path = nil,   -- without extension
    on_article = nil, -- function(): open the article this note belongs to (from the notebook)
    close_callback = nil,
}

function Sheet:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end -- Back = Fine
    self.ink = self.ink or "nero"
    self.history = self.history or {}
    self.dot = math.max(2, Screen:scaleBySize(3))
    local m, gap = Screen:scaleBySize(8), Screen:scaleBySize(8)
    local bh = Screen:scaleBySize(52)
    -- the text buttons share what the four ink squares leave of the width
    local half = math.floor(gap / 2)
    local nbtn = self.on_article and 5 or 4
    local sq = math.floor(bh * 0.8) -- ink squares
    local bw = math.floor((sw - 2 * m - 4 * sq - 3 * half - nbtn * gap) / nbtn) - Screen:scaleBySize(4) -- minus borders
    local function btn(text, cb, selected)
        return Button:new{ text = text, width = bw, height = bh, callback = cb,
            text_font_face = "NotoSans-Bold.ttf", text_font_size = 17, radius = Screen:scaleBySize(10),
            bordersize = Screen:scaleBySize(selected and 4 or 2), background = selected and Blitbuffer.COLOR_GRAY_D or nil }
    end
    local bar = HorizontalGroup:new{ align = "center", btn("Fine", function() self:onClose() end) }
    if self.on_article then
        table.insert(bar, HorizontalSpan:new{ width = gap })
        table.insert(bar, btn("Articolo", function() self.close_callback = nil; self:onClose(); self.on_article() end))
    end
    table.insert(bar, HorizontalSpan:new{ width = gap })
    for i, name in ipairs(theme.inks) do
        if i > 1 then table.insert(bar, HorizontalSpan:new{ width = half }) end
        table.insert(bar, Swatch:new{ ink = name, size = sq, selected = not self.eraser and self.ink == name,
            callback = function() self.ink, self.eraser = name, false; self:refreshBar() end })
    end
    table.insert(bar, HorizontalSpan:new{ width = gap })
    table.insert(bar, btn("Gomma", function() self.eraser = true; self:refreshBar() end, self.eraser))
    table.insert(bar, HorizontalSpan:new{ width = gap })
    table.insert(bar, btn("Annulla", function() self:undo() end))
    table.insert(bar, HorizontalSpan:new{ width = gap })
    table.insert(bar, btn("Pulisci", function() self:clear() end))

    local n = self.note
    local head = VerticalGroup:new{
        align = "left",
        bar,
        VerticalSpan:new{ width = gap },
        TextWidget:new{ text = n.title ~= "" and n.title or "Foglio libero", face = Font:getFace("NotoSerif-Bold.ttf", 18),
            max_width = sw - 2 * m },
        TextWidget:new{ text = n.sub or "", face = Font:getFace("NotoSerif-Italic.ttf", 14), max_width = sw - 2 * m,
            fgcolor = Blitbuffer.COLOR_GRAY_5 },
        VerticalSpan:new{ width = Screen:scaleBySize(4) },
        LineWidget:new{ dimen = Geom:new{ w = sw - 2 * m, h = Screen:scaleBySize(2) } },
    }
    self.head = FrameContainer:new{ bordersize = 0, padding = m, padding_bottom = 0, background = Blitbuffer.COLOR_WHITE, head }
    local top = self.head:getSize().h
    self.paper = Geom:new{ x = 0, y = top, w = sw, h = sh - top }
    if not self.bb or self.bb:getWidth() ~= self.paper.w or self.bb:getHeight() ~= self.paper.h then
        if self.bb then self.bb:free() end
        self.bb = Blitbuffer.new(self.paper.w, self.paper.h, Screen.bb:getType())
        ink.fit(n, self.paper.w, self.paper.h)
        n.w, n.h = self.paper.w, self.paper.h
        self:drawAll()
    end
    self[1] = self.head
end

function Sheet:paintTo(bb, x, y)
    self.head:paintTo(bb, x, y)
    bb:blitFrom(self.bb, x + self.paper.x, y + self.paper.y, 0, 0, self.paper.w, self.paper.h)
end

function Sheet:refreshBar()
    self:init()
    UIManager:setDirty(self, "ui", Geom:new{ x = 0, y = 0, w = self.dimen.w, h = self.paper.y })
end

-- the ruled paper: light lines, a margin like a school notebook
function Sheet:drawPaper()
    local bb, w, h = self.bb, self.paper.w, self.paper.h
    bb:fill(Blitbuffer.COLOR_WHITE)
    local step, rule = Screen:scaleBySize(34), theme.color("rule")
    for y = step, h - 1, step do theme.rect(bb, 0, y, w, 1, rule) end
    theme.rect(bb, Screen:scaleBySize(56), 0, Screen:scaleBySize(2), h, theme.color("margin"))
end

-- one segment of a stroke, as squares along it; returns the rectangle it touched (paper coordinates)
function Sheet:segment(c, x0, y0, x1, y1)
    local d, half = self.dot, math.floor(self.dot / 2)
    local steps = math.max(1, math.ceil(math.max(math.abs(x1 - x0), math.abs(y1 - y0)) / math.max(1, half)))
    for i = 0, steps do
        theme.rect(self.bb, math.floor(x0 + (x1 - x0) * i / steps) - half, math.floor(y0 + (y1 - y0) * i / steps) - half, d, d, c)
    end
    local x, y = math.min(x0, x1) - half, math.min(y0, y1) - half
    return Geom:new{ x = x, y = y, w = math.abs(x1 - x0) + d, h = math.abs(y1 - y0) + d }
end

function Sheet:drawStroke(st)
    local c, p = theme.color(st.c), st.p
    if #p == 2 then return self:segment(c, p[1], p[2], p[1], p[2]) end
    for i = 1, #p - 3, 2 do self:segment(c, p[i], p[i + 1], p[i + 2], p[i + 3]) end
end

function Sheet:drawAll()
    self:drawPaper()
    for _, st in ipairs(self.note.strokes) do self:drawStroke(st) end
end

-- straight to the screen, no repaint of the widget: the fastest the display can follow the pen
function Sheet:show(r)
    local x, y = self.paper.x + r.x, self.paper.y + r.y
    Screen.bb:blitFrom(self.bb, x, y, r.x, r.y, r.w, r.h)
    UIManager:setDirty(nil, "fast", Geom:new{ x = x, y = y, w = r.w, h = r.h })
end

function Sheet:remember()
    local copy = {}
    for i, st in ipairs(self.note.strokes) do copy[i] = st end
    table.insert(self.history, copy)
    if #self.history > 50 then table.remove(self.history, 1) end
end

function Sheet:redrawPaper()
    self:drawAll()
    UIManager:setDirty(self, "ui", self.paper)
end

function Sheet:penDown(x, y)
    if self.eraser then
        self.erasing = false
        return self:erase(x, y)
    end
    self:remember()
    self.stroke = { c = self.ink, p = { x, y } }
    table.insert(self.note.strokes, self.stroke)
    self:show(self:segment(theme.color(self.ink), x, y, x, y))
end

function Sheet:penMove(x, y)
    if self.eraser then return self:erase(x, y) end
    local st = self.stroke
    if not st then return end
    local p = st.p
    local lx, ly = p[#p - 1], p[#p]
    if math.abs(x - lx) + math.abs(y - ly) < 2 then return end
    p[#p + 1], p[#p + 2] = x, y
    self:show(self:segment(theme.color(st.c), lx, ly, x, y))
end

function Sheet:penUp()
    self.stroke = nil
    self.erasing = false
end

function Sheet:erase(x, y)
    local r, strokes, hit = Screen:scaleBySize(14), self.note.strokes, false
    for i = #strokes, 1, -1 do
        if ink.hit(strokes[i], x, y, r) then
            if not hit and not self.erasing then self:remember() end -- one undo step per eraser stroke
            hit, self.erasing = true, true
            table.remove(strokes, i)
        end
    end
    if hit then self:redrawPaper() end
end

function Sheet:undo()
    local prev = table.remove(self.history)
    if not prev then return end
    self.note.strokes = prev
    self:redrawPaper()
end

function Sheet:clear()
    if #self.note.strokes == 0 then return end
    self:remember()
    self.note.strokes = {}
    self:redrawPaper()
end

-- Raw touches, before gestures: a contact that starts on the paper belongs to the pen until it lifts.
-- One contact at a time (a resting hand doesn't draw a second line).
function Sheet:feed(s)
    if not (s.x and s.y) then return false end
    local g = Device.input.gesture_detector:adjustGesCoordinate{ ges = "touch", pos = Geom:new{ x = s.x, y = s.y, w = 0, h = 0 } }
    local x, y = math.floor(g.pos.x - self.paper.x), math.floor(g.pos.y - self.paper.y)
    if self.pen == s.slot then
        if s.id == -1 then
            self.pen = nil
            self:penUp()
        else
            self:penMove(math.max(0, math.min(x, self.paper.w - 1)), math.max(0, math.min(y, self.paper.h - 1)))
        end
        return true
    end
    if s.id ~= -1 and not self.pen and x >= 0 and y >= 0 and x < self.paper.w and y < self.paper.h then
        self.pen = s.slot
        self:penDown(x, y)
        return true
    end
    return false
end

function Sheet:onShow()
    local input = Device.input
    self.saved_route = rawget(input, "routeStylusEvents")
    input.routeStylusEvents = function(inp)
        local slots = inp.MTSlots
        if not slots or #slots == 0 then return end
        local keep = {}
        for _, s in ipairs(slots) do
            if not self:feed(s) then keep[#keep + 1] = s end
        end
        if #keep ~= #slots then
            for i = #slots, 1, -1 do slots[i] = nil end
            for i, s in ipairs(keep) do slots[i] = s end
        end
    end
end

function Sheet:save()
    lfs.mkdir(Notes.dir)
    if #self.note.strokes == 0 then
        os.remove(self.path .. ".lua")
        os.remove(self.path .. ".png")
        return
    end
    local f = io.open(self.path .. ".lua", "wb")
    if not f then return logger.warn("KoNewspaper: can't save", self.path) end
    f:write(ink.encode(self.note))
    f:close()
    local ok, err = pcall(self.bb.writePNG, self.bb, self.path .. ".png")
    if not ok then logger.warn("KoNewspaper: note picture", err) end
end

function Sheet:onClose()
    UIManager:close(self)
    return true
end

function Sheet:onCloseWidget()
    Device.input.routeStylusEvents = self.saved_route
    self:save()
    if self.bb then self.bb:free(); self.bb = nil end
    if self.close_callback then self.close_callback() end
end

--- Opens the sheet with this id (a new one if there is none); `fields` (title, sub, file, chapter) for a new note
function Notes.open(id, fields, opts)
    local path = Notes.dir .. "/" .. id
    local note = ink.decode(readFile(path .. ".lua"))
    if not note then
        note = { title = fields.title or "", sub = fields.sub or "", file = fields.file, chapter = fields.chapter, strokes = {} }
    end
    opts = opts or {}
    local sheet = Sheet:new{ note = note, path = path, on_article = opts.on_article, close_callback = opts.close_callback }
    UIManager:show(sheet, "full")
    return sheet
end

function Notes.has(id)
    return lfs.attributes(Notes.dir .. "/" .. id .. ".lua", "mode") == "file"
end

--- Every saved note, newest first: { id=, note=, png=, time= }
function Notes.list()
    local out = {}
    local ok, iter, state = pcall(lfs.dir, Notes.dir)
    if not ok then return out end
    for f in iter, state do
        local id = f:match("^(.+)%.lua$")
        if id then
            local path = Notes.dir .. "/" .. f
            local note = ink.decode(readFile(path))
            if note then
                local png = Notes.dir .. "/" .. id .. ".png"
                table.insert(out, { id = id, note = note, time = lfs.attributes(path, "modification") or 0,
                    png = lfs.attributes(png, "mode") == "file" and png or nil })
            end
        end
    end
    table.sort(out, function(a, b) return a.time > b.time end)
    return out
end

Notes.Sheet = Sheet -- for tools/screenshots
return Notes
