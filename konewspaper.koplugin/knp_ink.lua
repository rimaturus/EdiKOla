-- Pen notes, the parts without screen: storage format, eraser hit test. Pure Lua (tests/notes-test.lua).
-- A note: { title=, sub=, file=, chapter=, w=, h=, strokes = { { c = "blu", p = { x1, y1, x2, y2, ... } } } }
-- Points are pixels of the paper (w x h), so a note opened on another screen size is scaled.
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
        s[#s + 1] = ("{ c = %q, p = { %s } }"):format(st.c, table.concat(p, ","))
    end
    return ("return { v = 1, title = %q, sub = %q, file = %s, chapter = %s, w = %d, h = %d, strokes = {\n%s\n} }\n"):format(
        n.title or "", n.sub or "", n.file and ("%q"):format(n.file) or "nil", n.chapter and ("%d"):format(n.chapter) or "nil",
        n.w, n.h, table.concat(s, ",\n"))
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
