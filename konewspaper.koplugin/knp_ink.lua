-- Pen ink, the parts without screen: storage format, eraser hit test. Pure Lua (tests/notes-test.lua).
-- One file per document: { v = 2, pages = { [page key] = { w =, h =, strokes = { { c = "blu", p = { x1, y1, ... }, q = { 5, ... } } } } } }
-- The page key is where the page starts in the text (or "p<number>" in a PDF), see knp_penna.lua.
-- Points are screen pixels of a w x h page, so ink seen on another screen size is scaled.
-- q: the pen's pressure at each point, 1 (light) to 9 (hard).
local M = {}

--- File name (no extension) for the ink of document `file`
function M.id(file)
    local base = file:match("([^/]+)%.%w+$") or file:match("[^/]+$")
    local folder = file:match("([^/]+)/[^/]+$") or ""
    return ((folder ~= "" and folder .. "-" or "") .. base):gsub("[^%w%-_]", "_")
end

local function strokes(list)
    local s = {}
    for _, st in ipairs(list) do
        local p = {}
        for i, v in ipairs(st.p) do p[i] = ("%d"):format(v) end
        local q = ""
        if st.q then
            local t = {}
            for i, v in ipairs(st.q) do t[i] = ("%d"):format(v) end
            q = (", q = { %s }"):format(table.concat(t, ","))
        end
        s[#s + 1] = ("{ c = %q, p = { %s }%s }"):format(st.c, table.concat(p, ","), q)
    end
    return table.concat(s, ",\n")
end

--- The document's ink as file text; nil when no page has a stroke (the file is then removed)
function M.encode(doc)
    local s = {}
    for key, pg in pairs(doc.pages) do
        if #pg.strokes > 0 then
            s[#s + 1] = ("[%q] = { w = %d, h = %d, strokes = {\n%s\n} }"):format(key, pg.w, pg.h, strokes(pg.strokes))
        end
    end
    if #s == 0 then return nil end
    table.sort(s)
    return "return { v = 2, pages = {\n" .. table.concat(s, ",\n") .. "\n} }\n"
end

--- The document's ink in a file's text, or nil. Runs with no globals: a planted file can't reach anything.
function M.decode(text)
    if type(text) ~= "string" or text:byte(1) == 27 then return nil end -- text only: no bytecode
    local f
    if setfenv then -- LuaJIT / Lua 5.1: compile, then an empty environment
        f = loadstring(text, "ink")
        if f then setfenv(f, {}) end
    else
        f = load(text, "ink", "t", {})
    end
    if not f then return nil end
    local ok, doc = pcall(f)
    if not (ok and type(doc) == "table" and type(doc.pages) == "table") then return nil end
    for key, pg in pairs(doc.pages) do
        if type(key) ~= "string" or type(pg) ~= "table" or type(pg.strokes) ~= "table" then return nil end
    end
    return doc
end

--- Fits a page drawn on a w x h screen to this one (another device or orientation): one scale, top-left kept
function M.fit(pg, w, h)
    if not (pg.w and pg.h) or (pg.w == w and pg.h == h) then return end
    local k = math.min(w / pg.w, h / pg.h)
    for _, st in ipairs(pg.strokes) do
        for i, v in ipairs(st.p) do st.p[i] = math.floor(v * k + 0.5) end
    end
    pg.w, pg.h = w, h
end

--- Pressure 0..1 (Android) to the stored 1..9; nil when there's none
function M.level(pressure)
    if not pressure or pressure <= 0 then return nil end
    return math.max(1, math.min(9, math.floor(pressure * 9 + 0.5)))
end

--- Line width for a pressure level: 0.6x (light) to 1.8x (hard) the normal width, which level 5 gives
function M.width(base, q)
    if not q then return base end
    return math.max(1, math.floor(base * (0.45 + 0.15 * q) + 0.5))
end

-- squared distance from (px, py) to the segment (ax, ay)-(bx, by)
local function dist2(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local t = (dx == 0 and dy == 0) and 0 or math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    local x, y = ax + t * dx - px, ay + t * dy - py
    return x * x + y * y
end

--- Does the eraser at (x, y) with radius r touch the stroke?
function M.hit(st, x, y, r)
    local p, r2 = st.p, r * r
    if #p == 2 then return dist2(x, y, p[1], p[2], p[1], p[2]) <= r2 end
    for i = 1, #p - 3, 2 do
        if dist2(x, y, p[i], p[i + 1], p[i + 2], p[i + 3]) <= r2 then return true end
    end
    return false
end

return M
