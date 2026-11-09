--[[--
Enigmistica: free puzzles made on the device, in the spirit of the Italian weekly puzzle magazines.

- Cruciverba del giorno: a "schema libero" crossword; most answers come from today's headlines (the clue
  is the headline with the answer blanked out), the rest from a dictionary of definitions (knp_parole).
- Crucipuzzle: find the words in the grid, the letters left over spell the key.
- Sudoku: facile, medio, difficile.

Everything is generated here (knp_cruciverba, knp_crucipuzzle, knp_sudoku), works offline, and every move
is saved at once (settings/edikola_giochi.lua): a puzzle stays where it was left until it is solved or
replaced with "Nuovo".

The pen writes in the squares, as on paper: a digit or a letter, read on the device (knp_scrittura); a key
typed over it in the same square teaches the reader that hand. In the crucipuzzle a pen line over a word
finds it. The eraser end empties a square. Fingers tap as before.

    require("knp_giochi").show(articles)  -- articles(): today's { { title =, paper = } } for the crossword
]]
local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LuaSettings = require("luasettings")
local RenderText = require("ui/rendertext")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Cards = require("knp_cards")
local C = require("knp_cruciverba")
local P = require("knp_parole")
local Penna = require("knp_penna")
local S = require("knp_sudoku")
local Scrittura = require("knp_scrittura")
local W = require("knp_crucipuzzle")
local theme = require("knp_theme")
local Screen = Device.screen
local G = Blitbuffer

local store
local function db()
    store = store or LuaSettings:open(DataStorage:getSettingsDir() .. "/edikola_giochi.lua")
    return store
end
local function save(key, value)
    db():saveSetting(key, value)
    db():flush()
end
local function today() return tonumber(os.date("%Y%m%d")) end
local function freshSeed() return os.time() % 100000000 end
local function px(n) return Screen:scaleBySize(n) end
local function say(text, timeout)
    UIManager:show(InfoMessage:new{ text = text, face = Font:getFace("cfont", 22), timeout = timeout })
end
local function setChar(s, i, ch) return s:sub(1, i - 1) .. ch .. s:sub(i + 1) end

-- A grid drawn by hand: big squares, and a tap refreshes only the grid on the e-ink screen.
-- cell(c, r) -> { bg = color, text = "A", fg = color, num = "12", block = true } or nil
local Board = InputContainer:extend{ cols = 9, rows = 9, size = 60, cell = nil, on_tap = nil, thick = nil }

function Board:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.cols * self.size + 1, h = self.rows * self.size + 1 }
    self.ges_events = { TapBoard = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
    local scale = px(100) / 100
    self.face = Font:getFace("NotoSans-Bold.ttf", math.floor(self.size * 0.52 / scale))
    self.small = Font:getFace("NotoSans-Bold.ttf", math.max(7, math.floor(self.size * 0.2 / scale)))
end

function Board:getSize() return Geom:new{ w = self.dimen.w, h = self.dimen.h } end

local function centred(bb, face, text, x, y, w, h, fg)
    local tw = RenderText:sizeUtf8Text(0, w, face, text, true, false).x
    local fh, asc = face.ftsize:getHeightAndAscender()
    RenderText:renderUtf8Text(theme.inColor(bb, fg), x + math.floor((w - tw) / 2), y + math.floor((h - fh) / 2 + asc),
        face, text, true, false, fg)
end

function Board:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local s = self.size
    theme.rect(bb, x, y, self.dimen.w, self.dimen.h, G.COLOR_WHITE)
    for r = 1, self.rows do
        for c = 1, self.cols do
            local d = self.cell(c, r)
            local cx, cy = x + (c - 1) * s, y + (r - 1) * s
            if d then
                if d.block then
                    theme.rect(bb, cx, cy, s, s, G.COLOR_BLACK)
                elseif d.bg then
                    theme.rect(bb, cx, cy, s, s, d.bg)
                end
                if d.text and d.text ~= "" and d.text ~= " " then
                    centred(bb, self.face, d.text, cx, cy, s, s, d.fg or G.COLOR_BLACK)
                end
                if d.num then
                    local _, asc = self.small.ftsize:getHeightAndAscender()
                    local fg = d.fg_num or G.COLOR_GRAY_3
                    RenderText:renderUtf8Text(theme.inColor(bb, fg), cx + px(2), cy + px(1) + asc, self.small, d.num, true, false, fg)
                end
            end
        end
    end
    for k = 0, self.cols do
        local t = (self.thick and self.thick(k)) and px(3) or 1
        bb:paintRect(x + k * s - math.floor(t / 2), y, t, self.rows * s + 1, G.COLOR_BLACK)
    end
    for k = 0, self.rows do
        local t = (self.thick and self.thick(k)) and px(3) or 1
        bb:paintRect(x, y + k * s - math.floor(t / 2), self.cols * s + 1, t, G.COLOR_BLACK)
    end
end

function Board:onTapBoard(_, ges)
    local c = math.floor((ges.pos.x - self.dimen.x) / self.size) + 1
    local r = math.floor((ges.pos.y - self.dimen.y) / self.size) + 1
    if c >= 1 and c <= self.cols and r >= 1 and r <= self.rows and self.on_tap then self.on_tap(c, r) end
    return true
end

-- A puzzle screen: "Indietro", the title in the puzzle's color, "Nuovo"; the body is up to each puzzle.
local Gioco = InputContainer:extend{ covers_fullscreen = true, color = "giochi", title = "", close_callback = nil }

function Gioco:init()
    self.sw, self.sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.sw, h = self.sh }
    self.m, self.gap = px(10), px(6)
    self.cw = self.sw - 2 * self.m
    if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
    if not self.st then self:load() end
    self:build()
end

function Gioco:topbar()
    local bw, bh = px(118), px(46)
    return HorizontalGroup:new{
        align = "center",
        theme.Pill:new{ text = "Indietro", width = bw, height = bh, size = 18, fill = theme.color("ink_tint"),
            fg = theme.color("ink"), callback = function() self:onClose() end },
        CenterContainer:new{ dimen = Geom:new{ w = self.cw - 2 * bw, h = bh },
            theme.Text:new{ text = self.title, face = Font:getFace("NotoSerif-Bold.ttf", 26), fgcolor = theme.color(self.color),
                max_width = self.cw - 2 * bw - px(8) } },
        theme.Pill:new{ text = "Nuovo", width = bw, height = bh, size = 18, fill = theme.color(self.color .. "_tint"),
            fg = theme.color(self.color), callback = function()
                UIManager:show(ConfirmBox:new{
                    text = "Cominciare un gioco nuovo?\nQuello in corso va perso.", ok_text = "Nuovo", cancel_text = "Annulla",
                    ok_callback = function() self.st = self:newGame(freshSeed()); self:changed(true) end,
                })
            end },
    }
end

-- the screen: top bar, a colored rule, then the puzzle's own widgets
function Gioco:frame(widgets)
    local body = VerticalGroup:new{ align = "center", self:topbar(), VerticalSpan:new{ width = self.gap },
        theme.Box:new{ width = self.cw, height = px(3), color = theme.color(self.color) } }
    for _, w in ipairs(widgets) do
        table.insert(body, VerticalSpan:new{ width = self.gap })
        table.insert(body, w)
    end
    self[1] = FrameContainer:new{ width = self.sw, height = self.sh, bordersize = 0, padding = self.m,
        background = G.COLOR_WHITE, body }
end

-- a row of pills sharing the width
function Gioco:keys(list, height, size, color)
    local n = #list
    local gap = px(4)
    local w = math.floor((self.cw - (n - 1) * gap) / n)
    local row = HorizontalGroup:new{ align = "center" }
    for i, k in ipairs(list) do
        if i > 1 then table.insert(row, HorizontalSpan:new{ width = gap }) end
        table.insert(row, theme.Pill:new{ text = k[1], width = w, height = height, size = size or 20,
            fill = k.fill or theme.color((color or self.color) .. "_tint"), fg = k.fg or theme.color(color or self.color),
            callback = k[2] })
    end
    return row
end

--- After a move: save, rebuild, refresh (the whole screen only when asked, e.g. a new puzzle)
function Gioco:changed(full)
    save(self.key, self.st)
    self:build()
    UIManager:setDirty(self, full and "full" or "ui")
end

function Gioco:onClose()
    UIManager:close(self)
    return true
end

-- The pen on the grid: its strokes show in ink as it moves, then go to the puzzle (onPenStroke).
-- Fingers, and the pen off the grid, tap as usual.
function Gioco:onShow()
    self.release = Penna.capture(function(s) return self:feedPen(s) end)
end

function Gioco:onCloseWidget()
    if self.release then self.release() end
    if self.read_cb then UIManager:unschedule(self.read_cb) end
    if self.restore then UIManager:unschedule(self.restore); self.restore() end
    if self.close_callback then self.close_callback() end
end

function Gioco:feedPen(s)
    if not (s.x and s.y) then return false end
    local x, y = Penna.position(s)
    local ink = theme.color("scritto")
    if self.pen_slot == s.slot then
        if s.id == -1 then
            local st = self.stroke
            self.pen_slot, self.stroke = nil, nil
            Penna.fastPanel(self, false)
            if st then self:onPenStroke(st, self.rubbing) end
        else
            local p = self.stroke
            local lx, ly = p[#p - 1], p[#p]
            if math.abs(x - lx) + math.abs(y - ly) >= 2 then
                p[#p + 1], p[#p + 2] = x, y
                if not self.rubbing then UIManager:setDirty(nil, "fast", Penna.segment(Screen.bb, 0, 0, ink, lx, ly, x, y)) end
            end
        end
        return true
    end
    if s.id == -1 or self.pen_slot or not (s.tool == Penna.PEN or s.tool == Penna.ERASER) or not self.board then
        return false
    end
    local b = self.board.dimen
    if x < b.x or y < b.y or x >= b.x + b.w or y >= b.y + b.h then return false end
    self.pen_slot, self.rubbing, self.stroke = s.slot, s.tool == Penna.ERASER, { x, y }
    Penna.fastPanel(self, true)
    if not self.rubbing then UIManager:setDirty(nil, "fast", Penna.segment(Screen.bb, 0, 0, ink, x, y, x, y)) end
    return true
end

function Gioco:cellAt(x, y)
    local b = self.board
    local c = math.floor((x - b.dimen.x) / b.size) + 1
    local r = math.floor((y - b.dimen.y) / b.size) + 1
    if c >= 1 and c <= b.cols and r >= 1 and r <= b.rows then return c, r end
end

-- Handwriting in a square (sudoku, crossword): strokes gather per square and are read as one character
-- 0.8 s after the pen lifts, or at once when the pen starts in another square. The eraser empties a square.
function Gioco:onPenStroke(st, rubbing)
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for i = 1, #st - 1, 2 do
        x0, y0, x1, y1 = math.min(x0, st[i]), math.min(y0, st[i + 1]), math.max(x1, st[i]), math.max(y1, st[i + 1])
    end
    local c, r = self:cellAt((x0 + x1) / 2, (y0 + y1) / 2)
    if not c then return end
    local w = self.writing
    if w and (w.c ~= c or w.r ~= r or rubbing) then self:readWriting(); w = nil end
    if rubbing then return self:penWrite(c, r, false) end -- false: empty the square
    if not w then
        w = { c = c, r = r, strokes = {} }
        self.writing = w
    end
    table.insert(w.strokes, st)
    self.read_cb = self.read_cb or function() self:readWriting() end
    UIManager:unschedule(self.read_cb)
    UIManager:scheduleIn(0.8, self.read_cb)
end

local function learned() return db():readSetting("scrittura") or {} end

function Gioco:readWriting()
    if self.read_cb then UIManager:unschedule(self.read_cb) end
    local w = self.writing
    self.writing = nil
    if not w then return end
    local ch = Scrittura.recognize(w.strokes, self.charset, learned())
    if ch then self.last_pen = { c = w.c, r = w.r, strokes = w.strokes, ch = ch, time = os.time() } end
    self:penWrite(w.c, w.r, ch) -- nil: nothing read, the ink just goes
end

--- A key typed over what the pen just wrote in the same square: the pen read it wrong. That writing becomes
-- one of the user's own shapes for the key's character (five kept per character), so it is read right next time.
function Gioco:learn(c, r, ch)
    local lp = self.last_pen
    self.last_pen = nil
    if not lp or lp.c ~= c or lp.r ~= r or lp.ch == ch or os.time() - lp.time > 60 then return end
    local all = learned()
    all[ch] = all[ch] or {}
    table.insert(all[ch], Scrittura.cloud(lp.strokes))
    if #all[ch] > 5 then table.remove(all[ch], 1) end
    save("scrittura", all)
end

---------------------------------------------------------------------------------------------- Sudoku
local Sudoku = Gioco:extend{ color = "sudoku", level = 2, charset = "123456789" }
local LEVELS = { "facile", "medio", "difficile" }

-- the pen wrote a digit in a square (false: the eraser emptied it, nil: nothing readable)
function Sudoku:penWrite(c, r, ch)
    local i = (r - 1) * 9 + c
    if ch == nil or self.st.puz:sub(i, i) ~= "0" then -- unreadable, or a printed digit: only the ink goes
        self.sel = i
        self:build()
        return UIManager:setDirty(self, "ui", self.board.dimen)
    end
    self.sel = i
    self:put(ch or "0")
end

function Sudoku:key(d) -- a digit from the keys: maybe correcting what the pen wrote
    if self.sel then self:learn((self.sel - 1) % 9 + 1, math.floor((self.sel - 1) / 9) + 1, d) end
    self:put(d)
end

function Sudoku:load()
    self.key = "sudoku" .. self.level
    self.title = "Sudoku " .. LEVELS[self.level]
    self.st = db():readSetting(self.key) or self:newGame(today() * 10 + self.level)
end

function Sudoku:newGame(seed)
    local puz, sol = S.generate(seed, self.level)
    self.sel = nil
    return { seed = seed, puz = table.concat(puz), sol = table.concat(sol), cur = table.concat(puz), wrong = {} }
end

function Sudoku:peer(i, j)
    local ri, ci, rj, cj = math.floor((i - 1) / 9), (i - 1) % 9, math.floor((j - 1) / 9), (j - 1) % 9
    return ri == rj or ci == cj or (math.floor(ri / 3) == math.floor(rj / 3) and math.floor(ci / 3) == math.floor(cj / 3))
end

function Sudoku:build()
    local st = self.st
    local pad_h = px(48)
    local avail = self.sh - 2 * self.m - px(46) - px(3) - 5 * self.gap - 2 * pad_h - px(30)
    local size = math.floor(math.min(self.cw, avail) / 9)
    local sel_v = self.sel and st.cur:sub(self.sel, self.sel)
    self.board = Board:new{
        cols = 9, rows = 9, size = size,
        thick = function(k) return k % 3 == 0 end,
        cell = function(c, r)
            local i = (r - 1) * 9 + c
            local v = st.cur:sub(i, i)
            local given = st.puz:sub(i, i) ~= "0"
            local d = { text = v ~= "0" and v or nil }
            if i == self.sel then
                d.bg, d.fg = theme.color("sudoku"), G.COLOR_WHITE
            else
                if self.sel and (self:peer(i, self.sel) or (v ~= "0" and v == sel_v)) then d.bg = theme.color("sudoku_tint") end
                d.fg = given and G.COLOR_BLACK or (st.wrong[i] and theme.color("errore") or theme.color("scritto"))
            end
            return d
        end,
        on_tap = function(c, r)
            self.sel = (r - 1) * 9 + c
            self:build()
            UIManager:setDirty(self, "ui", self.board.dimen)
        end,
    }
    local digits = {}
    for d = 1, 9 do digits[d] = { tostring(d), function() self:key(tostring(d)) end } end
    local empty = 0
    for i = 1, 81 do if st.cur:sub(i, i) == "0" then empty = empty + 1 end end
    local status = st.done and "Risolto! Complimenti." or
        ("Vuote: %d - scrivi con la penna nella casella, o toccala e scegli il numero"):format(empty)
    self:frame{
        CenterContainer:new{ dimen = Geom:new{ w = self.cw, h = 9 * size + 1 }, self.board },
        theme.Text:new{ text = status, face = Font:getFace("NotoSans-Regular.ttf", 17), fgcolor = theme.color("sudoku"), max_width = self.cw },
        self:keys(digits, pad_h, 26),
        self:keys({
            { "Cancella", function() self:put("0") end },
            { "Controlla", function() self:check() end },
            { "Aiuto", function() self:hint() end },
        }, pad_h, 19),
    }
end

function Sudoku:put(v)
    local st, i = self.st, self.sel
    if not i then return say("Prima tocca una casella.", 2) end
    if st.done or st.puz:sub(i, i) ~= "0" then return end
    st.cur = setChar(st.cur, i, v)
    st.wrong[i] = nil
    if st.cur == st.sol then
        st.done = true
        say("Sudoku risolto!\n\nComplimenti.")
    end
    self:changed()
end

function Sudoku:check()
    local st, n = self.st, 0
    for i = 1, 81 do
        local v = st.cur:sub(i, i)
        if v ~= "0" and v ~= st.sol:sub(i, i) then st.wrong[i] = true; n = n + 1 end
    end
    say(n == 0 and "Fin qui è tutto giusto." or ("Numeri sbagliati: %d, ora sono in rosso."):format(n), 2)
    self:changed()
end

function Sudoku:hint()
    local st = self.st
    local i = self.sel
    if not i or st.cur:sub(i, i) == st.sol:sub(i, i) then
        i = nil
        for k = 1, 81 do if st.cur:sub(k, k) ~= st.sol:sub(k, k) then i = k; break end end
    end
    if not i then return end
    self.sel = i
    self:put(st.sol:sub(i, i))
end

-------------------------------------------------------------------------------------------- Cruciverba
local Cruciverba = Gioco:extend{ color = "cruciverba", title = "Cruciverba", key = "cruciverba", articles = nil,
    charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ" }

-- the pen wrote a letter in a square (false: the eraser emptied it, nil: nothing readable)
function Cruciverba:penWrite(c, r, ch)
    if not self:isLetter(c, r) then return self:redrawBoard() end
    self.sel.x, self.sel.y = c, r -- that square is now the selected one, its word the current one
    if ch ~= nil and not self.st.done then
        self:set(c, r, ch or " ")
        save(self.key, self.st)
    end
    self:redrawBoard()
end

function Cruciverba:load()
    self.st = db():readSetting(self.key) or self:newGame(today())
end

function Cruciverba:newGame(seed)
    local cw = C.generate(P.fromNews(self.articles and self.articles() or {}, 11), P.dictionary,
        { seed = seed, w = 12, h = 11, want = 18 })
    local cur = {}
    for y = 1, cw.h do cur[y] = cw.rows[y]:gsub("%a", " ") end
    local first = cw.words[1]
    self.sel = { x = first.x, y = first.y, dir = first.dir }
    return { seed = seed, cw = cw, cur = cur, wrong = {} }
end

function Cruciverba:letter(x, y) local r = self.st.cw.rows[y]; return r and r:sub(x, x) end
function Cruciverba:isLetter(x, y) local l = self:letter(x, y); return l and l ~= "" and l ~= "." end

function Cruciverba:wordAt(x, y, dir)
    for _, wd in ipairs(self.st.cw.words) do
        if wd.dir == dir then
            local dx, dy = dir == "a" and 1 or 0, dir == "d" and 1 or 0
            local k = dx == 1 and x - wd.x or y - wd.y
            if k >= 0 and k < #wd.word and wd.x + dx * k == x and wd.y + dy * k == y then return wd, k end
        end
    end
end

function Cruciverba:current()
    local s = self.sel
    if not s then
        local first = self.st.cw.words[1]
        s = { x = first.x, y = first.y, dir = first.dir }
        self.sel = s
    end
    local wd, k = self:wordAt(s.x, s.y, s.dir)
    if not wd then
        s.dir = s.dir == "a" and "d" or "a"
        wd, k = self:wordAt(s.x, s.y, s.dir)
    end
    return wd, k
end

function Cruciverba:build()
    local st, cw = self.st, self.st.cw
    local wd = self:current()
    local key_h, bar_h = px(44), px(84)
    local avail = self.sh - 2 * self.m - px(46) - px(3) - 8 * self.gap - bar_h - 4 * key_h - 3 * px(4) - px(8)
    local size = math.floor(math.min(self.cw / cw.w, avail / cw.h))
    local in_word = {}
    if wd then
        local dx, dy = wd.dir == "a" and 1 or 0, wd.dir == "d" and 1 or 0
        for k = 0, #wd.word - 1 do in_word[(wd.y + dy * k) * 100 + wd.x + dx * k] = true end
    end
    local nums = {}
    for _, w in ipairs(cw.words) do nums[w.y * 100 + w.x] = tostring(w.num) end
    self.board = Board:new{
        cols = cw.w, rows = cw.h, size = size,
        cell = function(c, r)
            if not self:isLetter(c, r) then return { block = true } end
            local d = { text = st.cur[r]:sub(c, c), num = nums[r * 100 + c] }
            if c == self.sel.x and r == self.sel.y then
                d.bg, d.fg, d.fg_num = theme.color("cruciverba"), G.COLOR_WHITE, G.COLOR_WHITE
            else
                if in_word[r * 100 + c] then d.bg = theme.color("cruciverba_tint") end
                d.fg = st.wrong[r * 100 + c] and theme.color("errore") or theme.color("scritto")
            end
            return d
        end,
        on_tap = function(c, r)
            if not self:isLetter(c, r) then return end
            if c == self.sel.x and r == self.sel.y then
                local other = self.sel.dir == "a" and "d" or "a"
                if self:wordAt(c, r, other) then self.sel.dir = other end
            else
                self.sel.x, self.sel.y = c, r
            end
            self:redrawBoard()
        end,
    }
    -- the clue of the selected word
    local head = wd and ("%d %s - %d lettere"):format(wd.num, wd.dir == "a" and "orizzontale" or "verticale", #wd.word) or ""
    local clue = wd and wd.clue or ""
    if wd and wd.source then clue = clue .. "  (dal titolo di " .. wd.source .. ")" end
    local text_w = self.cw - 2 * px(10)
    local bar = FrameContainer:new{
        width = self.cw, height = bar_h, bordersize = 0, padding = px(6), padding_left = px(10), radius = px(10),
        background = theme.color("cruciverba_tint"),
        VerticalGroup:new{ align = "left",
            theme.Text:new{ text = head, face = Font:getFace("NotoSans-Bold.ttf", 16), fgcolor = theme.color("cruciverba"), max_width = text_w },
            TextBoxWidget:new{ text = clue, face = Font:getFace("NotoSerif-Regular.ttf", 17), width = text_w,
                height = bar_h - px(32), height_overflow_show_ellipsis = true, bgcolor = theme.color("cruciverba_tint") },
        },
    }
    self.bar = bar
    local function row(letters, extra)
        local list = {}
        for ch in letters:gmatch(".") do list[#list + 1] = { ch, function() self:type(ch) end } end
        if extra then list[#list + 1] = extra end
        return self:keys(list, key_h, 22)
    end
    local status = st.done and "Risolto! Complimenti." or nil
    self:frame{
        bar,
        CenterContainer:new{ dimen = Geom:new{ w = self.cw, h = cw.h * size + 1 }, self.board },
        status and theme.Text:new{ text = status, face = Font:getFace("NotoSans-Bold.ttf", 18), fgcolor = theme.color("cruciverba") }
            or VerticalSpan:new{ width = 0 },
        row("QWERTYUIOP"),
        row("ASDFGHJKL"),
        row("ZXCVBNM", { "Canc", function() self:back() end }),
        self:keys({
            { "Definizioni", function() self:clues() end },
            { "Verso", function() self:turn() end },
            { "Controlla", function() self:check() end },
            { "Aiuto", function() self:hint() end },
        }, key_h, 17),
    }
end

function Cruciverba:redrawBoard()
    self:build()
    UIManager:setDirty(self, function() return "ui", self.board.dimen:combine(self.bar.dimen) end)
end

function Cruciverba:set(x, y, ch)
    local st = self.st
    st.cur[y] = setChar(st.cur[y], x, ch)
    st.wrong[y * 100 + x] = nil
    for r = 1, st.cw.h do
        if st.cur[r]:gsub(" ", "?") ~= st.cw.rows[r] then return end
    end
    if not st.done then
        st.done = true
        say("Cruciverba completato!\n\nComplimenti.")
    end
end

function Cruciverba:type(ch)
    local wd, k = self:current()
    if not wd or self.st.done then return end
    self:learn(self.sel.x, self.sel.y, ch) -- maybe correcting what the pen wrote there
    self:set(self.sel.x, self.sel.y, ch)
    if k < #wd.word - 1 then -- next square of the word
        self.sel.x = self.sel.x + (wd.dir == "a" and 1 or 0)
        self.sel.y = self.sel.y + (wd.dir == "d" and 1 or 0)
    end
    save(self.key, self.st)
    self:redrawBoard()
end

function Cruciverba:back()
    local wd, k = self:current()
    if not wd or self.st.done then return end
    if self.st.cur[self.sel.y]:sub(self.sel.x, self.sel.x) == " " and k > 0 then
        self.sel.x = self.sel.x - (wd.dir == "a" and 1 or 0)
        self.sel.y = self.sel.y - (wd.dir == "d" and 1 or 0)
    end
    self:set(self.sel.x, self.sel.y, " ")
    save(self.key, self.st)
    self:redrawBoard()
end

function Cruciverba:turn()
    local other = self.sel.dir == "a" and "d" or "a"
    if self:wordAt(self.sel.x, self.sel.y, other) then self.sel.dir = other; self:redrawBoard() end
end

function Cruciverba:check()
    local st, n = self.st, 0
    for y = 1, st.cw.h do
        for x = 1, st.cw.w do
            local v = st.cur[y]:sub(x, x)
            if v ~= " " and v ~= "." and v ~= st.cw.rows[y]:sub(x, x) then st.wrong[y * 100 + x] = true; n = n + 1 end
        end
    end
    say(n == 0 and "Fin qui è tutto giusto." or ("Lettere sbagliate: %d, ora sono in rosso."):format(n), 2)
    self:changed()
end

function Cruciverba:hint()
    if self.st.done then return end
    self:set(self.sel.x, self.sel.y, self:letter(self.sel.x, self.sel.y))
    self:changed()
end

-- every clue, across then down; tap one to go to it
function Cruciverba:clues()
    local items, list, last = {}, nil, nil
    for _, wd in ipairs(self.st.cw.words) do
        if wd.dir ~= last then
            last = wd.dir
            table.insert(items, { header = wd.dir == "a" and "Orizzontali" or "Verticali", color = "cruciverba" })
        end
        local done = true
        local dx, dy = wd.dir == "a" and 1 or 0, wd.dir == "d" and 1 or 0
        for k = 0, #wd.word - 1 do
            if self.st.cur[wd.y + dy * k]:sub(wd.x + dx * k, wd.x + dx * k) == " " then done = false; break end
        end
        table.insert(items, {
            title = ("%d. %s"):format(wd.num, wd.clue),
            text = ("%d lettere%s%s"):format(#wd.word, wd.source and " - dal titolo di " .. wd.source or "", done and " - completa" or ""),
            color = done and "neutral" or "cruciverba", lines = 1,
            callback = function()
                UIManager:close(list)
                self.sel = { x = wd.x, y = wd.y, dir = wd.dir }
                self:build()
                UIManager:setDirty(self, "ui")
            end,
        })
    end
    list = Cards.show{ title = "Definizioni", items = items }
end

------------------------------------------------------------------------------------------- Crucipuzzle
local Crucipuzzle = Gioco:extend{ color = "crucipuzzle", title = "Crucipuzzle", key = "crucipuzzle", articles = nil }

function Crucipuzzle:load()
    self.st = db():readSetting(self.key) or self:newGame(today())
end

function Crucipuzzle:newGame(seed)
    local pool = P.fromNews(self.articles and self.articles() or {}, 10)
    for _, e in ipairs(P.dictionary) do pool[#pool + 1] = e end
    local wp
    for t = 0, 5 do -- a key has to fit the leftover squares exactly: another seed if none did
        wp = W.generate(pool, { seed = seed + t, w = 10, h = 10 })
        if wp then break end
    end
    self.start = nil
    return { seed = seed, wp = wp, found = {}, nfound = 0 }
end

function Crucipuzzle:cover()
    local map = {}
    for _, p in ipairs(self.st.wp.words) do
        local f = self.st.found[p.word]
        if f then
            for k = 0, #p.word - 1 do map[(p.y + p.dy * k) * 100 + p.x + p.dx * k] = f end
        end
    end
    return map
end

function Crucipuzzle:inWord(c, r)
    for _, p in ipairs(self.st.wp.words) do
        for k = 0, #p.word - 1 do
            if p.x + p.dx * k == c and p.y + p.dy * k == r then return true end
        end
    end
end

function Crucipuzzle:build()
    local st, wp = self.st, self.st.wp
    local all = st.nfound == #wp.words
    local cols = 3
    local list_rows = math.ceil(#wp.words / cols)
    local item_h = px(30)
    local act_h = px(46)
    local avail = self.sh - 2 * self.m - px(46) - px(3) - 6 * self.gap - px(30) - list_rows * (item_h + px(4)) - act_h - px(10)
    local size = math.floor(math.min(self.cw / wp.w, avail / wp.h))
    local map = self:cover()
    self.board = Board:new{
        cols = wp.w, rows = wp.h, size = size,
        cell = function(c, r)
            local d = { text = wp.rows[r]:sub(c, c) }
            if self.start and self.start[1] == c and self.start[2] == r then
                d.bg, d.fg = theme.color("crucipuzzle"), G.COLOR_WHITE
            elseif map[r * 100 + c] then
                d.bg = theme.color("f" .. map[r * 100 + c])
            elseif all and not self:inWord(c, r) then -- the key's letters
                d.bg, d.fg = theme.color("giochi"), G.COLOR_WHITE
            end
            return d
        end,
        on_tap = function(c, r) self:tap(c, r) end,
    }
    -- the word list, three columns; found words take their color
    local gw = math.floor((self.cw - (cols - 1) * px(4)) / cols)
    local list = VerticalGroup:new{ align = "left" }
    for row = 1, list_rows do
        local line = HorizontalGroup:new{}
        for col = 1, cols do
            local p = wp.words[(row - 1) * cols + col]
            if col > 1 then table.insert(line, HorizontalSpan:new{ width = px(4) }) end
            if p then
                local f = st.found[p.word]
                table.insert(line, theme.Pill:new{ text = p.word, width = gw, height = item_h, size = 15,
                    fill = f and theme.color("f" .. f) or G.COLOR_WHITE, fg = f and G.COLOR_GRAY_3 or G.COLOR_BLACK,
                    face = f and "NotoSans-Regular.ttf" or "NotoSans-Bold.ttf" })
            end
        end
        table.insert(list, line)
        table.insert(list, VerticalSpan:new{ width = px(4) })
    end
    local status = all and ("La chiave: " .. (wp.key or "")) or
        ("Trovate %d di %d - riga a penna sulla parola, o tocca la prima e l'ultima lettera"):format(st.nfound, #wp.words)
    self:frame{
        CenterContainer:new{ dimen = Geom:new{ w = self.cw, h = wp.h * size + 1 }, self.board },
        TextBoxWidget:new{ text = status, face = Font:getFace(all and "NotoSans-Bold.ttf" or "NotoSans-Regular.ttf", all and 20 or 16),
            width = self.cw, alignment = "center", fgcolor = theme.color(all and "giochi" or "crucipuzzle") },
        list,
        self:keys({
            { "Soluzione", function() self:solve() end },
        }, act_h, 18),
    }
end

-- a pen line over a word: its first and last letters, as two taps (a dot: one tap)
function Crucipuzzle:onPenStroke(st, rubbing)
    if rubbing then return end
    local c1, r1 = self:cellAt(st[1], st[2])
    local c2, r2 = self:cellAt(st[#st - 1], st[#st])
    if not c1 then return end -- can't happen: the pen is only taken when it starts on the grid
    if not c2 then return self:tap(c1, r1) end -- the line ran off the grid: just its start
    self.start = nil
    if c1 == c2 and r1 == r2 then return self:tap(c1, r1) end
    self:tap(c1, r1)
    self:tap(c2, r2)
end

function Crucipuzzle:tap(c, r)
    local st = self.st
    if not self.start then
        self.start = { c, r }
    elseif self.start[1] == c and self.start[2] == r then
        self.start = nil
    else
        local sx, sy = self.start[1], self.start[2]
        local dx, dy = c - sx, r - sy
        local n = math.max(math.abs(dx), math.abs(dy))
        self.start = nil
        if dx == 0 or dy == 0 or math.abs(dx) == math.abs(dy) then
            dx, dy = dx / n, dy / n
            local s = ""
            for k = 0, n do s = s .. st.wp.rows[sy + dy * k]:sub(sx + dx * k, sx + dx * k) end
            for _, p in ipairs(st.wp.words) do
                if not st.found[p.word] and (p.word == s or p.word == s:reverse()) then
                    st.nfound = st.nfound + 1
                    st.found[p.word] = (st.nfound - 1) % 8 + 1
                    if st.nfound == #st.wp.words then
                        say("Tutte le parole trovate!\n\nLe lettere rimaste formano la chiave:\n" .. (st.wp.key or ""))
                    end
                    return self:changed()
                end
            end
        end
        say("Non è una delle parole dell'elenco.", 1)
    end
    self:build()
    UIManager:setDirty(self, "ui", self.board.dimen)
end

function Crucipuzzle:solve()
    local st = self.st
    for _, p in ipairs(st.wp.words) do
        if not st.found[p.word] then
            st.nfound = st.nfound + 1
            st.found[p.word] = (st.nfound - 1) % 8 + 1
        end
    end
    self:changed()
end

------------------------------------------------------------------------------------------------- Menu
local Giochi = {}

local function progress(key, words)
    local st = db():readSetting(key)
    if not st then return "Nuovo, da cominciare" end
    if st.done then return "Risolto" end
    return words(st)
end

-- A puzzle on the cover: a tinted card with the puzzle's name in its color, what it is, where it's at
local Tile = InputContainer:extend{ item = nil, width = 0, height = 0 }

function Tile:init()
    local it = self.item
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.ges_events = { TapTile = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
    local pad = px(12)
    local tint, color = theme.color(it.color .. "_tint"), theme.color(it.color)
    local w = self.width - 2 * pad
    local body = VerticalGroup:new{
        align = "left",
        theme.Box:new{ width = px(46), height = px(6), radius = px(3), color = color },
        VerticalSpan:new{ width = px(8) },
        TextBoxWidget:new{ text = it.title, face = Font:getFace("NotoSerif-Bold.ttf", it.big and 28 or 22), width = w,
            fgcolor = color, bgcolor = tint },
        VerticalSpan:new{ width = px(4) },
    }
    if it.text then
        table.insert(body, TextBoxWidget:new{ text = it.text, face = Font:getFace("NotoSerif-Regular.ttf", 16), width = w,
            fgcolor = G.COLOR_GRAY_3, bgcolor = tint })
        table.insert(body, VerticalSpan:new{ width = px(8) })
    end
    table.insert(body, TextBoxWidget:new{ text = it.status, face = Font:getFace("NotoSans-Bold.ttf", 16), width = w,
        fgcolor = color, bgcolor = tint })
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, bordersize = 0, padding = pad, radius = px(14), background = tint, body,
    }
end

function Tile:onTapTile()
    self.item.callback()
    return true
end

-- The cover of "La Settimana di EdiKOla": the masthead, the day's crossword, the crucipuzzle, three sudoku
local Cover = InputContainer:extend{ covers_fullscreen = true, items = nil }

function Cover:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
    local m, gap = px(10), px(10)
    local cw = sw - 2 * m
    local color, white = theme.color("giochi"), G.COLOR_WHITE
    local side = px(110)
    local masthead = VerticalGroup:new{
        align = "center",
        theme.Text:new{ text = "La Settimana", face = Font:getFace("NotoSerif-Bold.ttf", 34), fgcolor = white },
        theme.Text:new{ text = "di EdiKOla", face = Font:getFace("NotoSerif-Italic.ttf", 22), fgcolor = white },
        VerticalSpan:new{ width = px(4) },
        theme.Text:new{ text = "numero di " .. require("knp_build").dateLabel(os.time()),
            face = Font:getFace("NotoSans-Regular.ttf", 15), fgcolor = white, max_width = cw - 2 * side },
    }
    local band = FrameContainer:new{
        width = cw, bordersize = 0, padding = px(10), radius = px(14), background = color,
        HorizontalGroup:new{
            align = "center",
            theme.Pill:new{ text = "Indietro", width = side, height = px(46), size = 18, fill = white, fg = color,
                callback = function() self:onClose() end },
            CenterContainer:new{ dimen = Geom:new{ w = cw - 2 * side - px(20), h = masthead:getSize().h }, masthead },
            HorizontalSpan:new{ width = side },
        },
    }
    local avail = sh - 2 * m - band:getSize().h - 3 * gap
    local it = self.items
    local third = math.floor((cw - 2 * gap) / 3)
    local sudoku = HorizontalGroup:new{}
    for k = 3, 5 do
        if k > 3 then table.insert(sudoku, HorizontalSpan:new{ width = gap }) end
        table.insert(sudoku, Tile:new{ item = it[k], width = third, height = avail - 2 * math.floor(avail * 0.34) })
    end
    self[1] = FrameContainer:new{
        width = sw, height = sh, bordersize = 0, padding = m, background = white,
        VerticalGroup:new{
            align = "center",
            band,
            VerticalSpan:new{ width = gap },
            Tile:new{ item = it[1], width = cw, height = math.floor(avail * 0.34) },
            VerticalSpan:new{ width = gap },
            Tile:new{ item = it[2], width = cw, height = math.floor(avail * 0.34) },
            VerticalSpan:new{ width = gap },
            sudoku,
        },
    }
end

function Cover:onClose()
    UIManager:close(self)
    return true
end

function Giochi.show(articles)
    local cover
    local function reopen() -- back from a puzzle: the cover again, with where each puzzle is at now
        if cover then UIManager:close(cover) end
        Giochi.show(articles)
    end
    local function open(class, args)
        args.close_callback = reopen
        args.articles = articles
        UIManager:show(class:new(args), "full")
    end
    local items = {
        { title = "Cruciverba del giorno", color = "cruciverba", big = true,
          text = "Schema libero: molte definizioni sono i titoli delle notizie di oggi, con la parola da trovare.",
          status = progress("cruciverba", function(st)
              local empty = 0
              for y = 1, st.cw.h do empty = empty + select(2, st.cur[y]:gsub(" ", "")) end
              return ("In corso: %d caselle da riempire"):format(empty)
          end),
          callback = function() open(Cruciverba, {}) end },
        { title = "Crucipuzzle", color = "crucipuzzle", big = true,
          text = "Trova le parole nello schema: le lettere che restano, lette in ordine, formano la chiave.",
          status = progress("crucipuzzle", function(st)
              if st.nfound == #st.wp.words then return "Risolto" end
              return ("In corso: trovate %d di %d"):format(st.nfound, #st.wp.words)
          end),
          callback = function() open(Crucipuzzle, {}) end },
    }
    for level = 1, 3 do
        table.insert(items, { title = "Sudoku " .. LEVELS[level], color = "sudoku",
            status = progress("sudoku" .. level, function(st)
                return ("In corso: %d vuote"):format(select(2, st.cur:gsub("0", "")))
            end),
            callback = function() open(Sudoku, { level = level }) end })
    end
    cover = Cover:new{ items = items }
    UIManager:show(cover, "full")
    return cover
end

Giochi.Sudoku, Giochi.Cruciverba, Giochi.Crucipuzzle = Sudoku, Cruciverba, Crucipuzzle -- for tools/screenshots
return Giochi
