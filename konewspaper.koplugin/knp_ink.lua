-- Pen notes, the parts without screen: storage format, eraser hit test. Pure Lua (tests/notes-test.lua).
-- A note: { title=, sub=, file=, chapter=, w=, h=, text=, strokes = { { c = "blu", p = { x1, y1, ... }, q = { 5, ... } } } }
-- Points are pixels of the paper (w x h), so a note opened on another screen size is scaled.
-- q: the pen's pressure at each point, 1 (light) to 9 (hard); absent for a finger. text: its transcription.
local M = {}

--- File name (no extension) for the note of chapter `chapter` of document `file`, or a free sheet
function M.id(file, chapter)
    if not file then return "foglio-" .. os.date("%Y%m%d-%H%M%S") end
    local base = file:match("([^/]+)%.%w+$") or file:match("[^/]+$")
    local paper = file:match("([^/]+)/[^/]+$") or ""
    local id = ((paper ~= "" and paper .. "-" or "") .. base .. "-" .. (chapter or 0)):gsub("[^%w%-_]", "_")
    return id
end

function M.encode(n)
    local s = {}
    for _, st in ipairs(n.strokes) do
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
    return ("return { v = 1, title = %q, sub = %q, file = %s, chapter = %s, w = %d, h = %d, text = %s, strokes = {\n%s\n} }\n"):format(
        n.title or "", n.sub or "", n.file and ("%q"):format(n.file) or "nil", n.chapter and ("%d"):format(n.chapter) or "nil",
        n.w, n.h, n.text and ("%q"):format(n.text) or "nil", table.concat(s, ",\n"))
end

--- The note in a file's text, or nil. Runs with no globals: a planted file can't reach anything.
function M.decode(text)
    local f = type(text) == "string" and load(text, "note", "t", {}) -- text only: no bytecode
    if not f then return nil end
    if setfenv then setfenv(f, {}) end -- LuaJIT: make sure of the empty environment
    local ok, n = pcall(f)
    if not (ok and type(n) == "table" and type(n.strokes) == "table") then return nil end
    return n
end

--- Fits a note drawn on a w x h paper to this one (another device or orientation): one scale, top-left kept
function M.fit(n, w, h)
    if not (n.w and n.h) or (n.w == w and n.h == h) then return end
    local k = math.min(w / n.w, h / n.h)
    for _, st in ipairs(n.strokes) do
        for i, v in ipairs(st.p) do st.p[i] = math.floor(v * k + 0.5) end
    end
    n.w, n.h = w, h
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
