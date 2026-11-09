--[[--
Handwritten digits and capital letters, recognised on the device (pure Lua, tests/scrittura-test.lua).

The $P point-cloud recognizer (Vatavu, Anthony, Wobbrock, "Gestures as point clouds", ICMI 2012): the
strokes become 32 points, scaled and centred, and are matched against each template as an unordered cloud,
so stroke order and direction don't matter. Templates are block capitals and digits drawn here as lines and
arcs in a unit square (y down), a few with a second common shape; the user's own corrected writing can be
added as extra templates (`extra`), so recognition learns their hand.

    S.recognize(strokes, chars, extra) -> char, distance
      strokes: { { x1, y1, x2, y2, ... }, ... } in any units
      chars:   "123456789" or "ABC...Z": the answers allowed
      extra:   { [char] = { cloud, ... } } from S.cloud()
]]
local S = { N = 32 }

-- an arc around (cx, cy), radii rx, ry, from angle a0 to a1 in degrees (0 = right, 90 = down)
local function arc(cx, cy, rx, ry, a0, a1)
    local p, steps = {}, 16
    for i = 0, steps do
        local a = math.rad(a0 + (a1 - a0) * i / steps)
        p[#p + 1] = cx + rx * math.cos(a)
        p[#p + 1] = cy + ry * math.sin(a)
    end
    return p
end
local function join(...) -- polylines and arcs into one stroke
    local out = {}
    for _, part in ipairs({ ... }) do
        for _, v in ipairs(part) do out[#out + 1] = v end
    end
    return out
end

local CIRCLE = arc(0.5, 0.5, 0.4, 0.5, 0, 360)
local OVAL = arc(0.5, 0.5, 0.28, 0.5, 270, 630) -- a narrow O, started at the top like most hands do
local P_BOWL = join({ 0.2, 1, 0.2, 0 }, arc(0.2, 0.25, 0.5, 0.25, 270, 450))
local TEMPLATES = {
    ["0"] = { { CIRCLE }, { OVAL } },
    ["1"] = { { { 0.5, 0, 0.5, 1 } }, { { 0.3, 0.2, 0.5, 0, 0.5, 1 } } },
    ["2"] = { { join(arc(0.5, 0.3, 0.32, 0.28, 190, 400), { 0.15, 1, 0.85, 1 }) } },
    ["3"] = { { join(arc(0.5, 0.27, 0.3, 0.25, 200, 450), arc(0.5, 0.75, 0.33, 0.25, 270, 520)) } },
    ["4"] = { { { 0.65, 0, 0.1, 0.65, 0.9, 0.65 }, { 0.65, 0, 0.65, 1 } },
              { { 0.2, 0, 0.15, 0.6, 0.9, 0.6 }, { 0.7, 0.2, 0.7, 1 } } },
    ["5"] = { { join({ 0.8, 0, 0.25, 0, 0.22, 0.45 }, arc(0.5, 0.68, 0.3, 0.3, 225, 495)) },
              { { 0.25, 0, 0.22, 0.45 }, arc(0.5, 0.68, 0.3, 0.3, 225, 495), { 0.25, 0, 0.8, 0 } } },
    ["6"] = { { join({ 0.7, 0, 0.3, 0.35, 0.2, 0.7 }, arc(0.5, 0.7, 0.3, 0.28, 180, 540)) } },
    ["7"] = { { { 0.1, 0, 0.9, 0, 0.4, 1 } }, { { 0.1, 0, 0.9, 0, 0.4, 1 }, { 0.3, 0.5, 0.75, 0.5 } } },
    ["8"] = { { arc(0.5, 0.27, 0.27, 0.25, 0, 360), arc(0.5, 0.73, 0.33, 0.27, 0, 360) } },
    ["9"] = { { arc(0.5, 0.3, 0.3, 0.28, 0, 360), { 0.8, 0.3, 0.7, 1 } } },
    A = { { { 0.1, 1, 0.5, 0, 0.9, 1 }, { 0.25, 0.6, 0.75, 0.6 } } },
    B = { { { 0.2, 0, 0.2, 1 }, arc(0.2, 0.25, 0.5, 0.25, 270, 450), arc(0.2, 0.75, 0.6, 0.25, 270, 450) } },
    C = { { arc(0.55, 0.5, 0.4, 0.5, 315, 45) } },
    D = { { { 0.2, 0, 0.2, 1 }, arc(0.2, 0.5, 0.6, 0.5, 270, 450) } },
    E = { { { 0.8, 0, 0.2, 0, 0.2, 1, 0.8, 1 }, { 0.2, 0.5, 0.7, 0.5 } } },
    F = { { { 0.8, 0, 0.2, 0, 0.2, 1 }, { 0.2, 0.5, 0.7, 0.5 } } },
    G = { { join(arc(0.55, 0.5, 0.4, 0.5, 315, 30), { 0.95, 0.55, 0.6, 0.55 }) } },
    H = { { { 0.2, 0, 0.2, 1 }, { 0.8, 0, 0.8, 1 }, { 0.2, 0.5, 0.8, 0.5 } } },
    I = { { { 0.5, 0, 0.5, 1 } }, { { 0.3, 0, 0.7, 0 }, { 0.5, 0, 0.5, 1 }, { 0.3, 1, 0.7, 1 } } },
    J = { { join({ 0.75, 0, 0.75, 0.7 }, arc(0.5, 0.7, 0.25, 0.3, 0, 180)) } },
    K = { { { 0.2, 0, 0.2, 1 }, { 0.8, 0, 0.2, 0.55, 0.8, 1 } } },
    L = { { { 0.2, 0, 0.2, 1, 0.8, 1 } } },
    M = { { { 0.1, 1, 0.15, 0, 0.5, 0.6, 0.85, 0, 0.9, 1 } } },
    N = { { { 0.2, 1, 0.2, 0, 0.8, 1, 0.8, 0 } } },
    O = { { CIRCLE }, { OVAL } },
    P = { { P_BOWL } },
    Q = { { CIRCLE, { 0.6, 0.7, 0.95, 1 } } },
    R = { { P_BOWL, { 0.4, 0.5, 0.85, 1 } } },
    S = { { join(arc(0.5, 0.27, 0.3, 0.24, 330, 90), arc(0.5, 0.73, 0.3, 0.24, 270, 510)) } },
    T = { { { 0.1, 0, 0.9, 0 }, { 0.5, 0, 0.5, 1 } } },
    U = { { join({ 0.2, 0, 0.2, 0.65 }, arc(0.5, 0.65, 0.3, 0.35, 180, 0), { 0.8, 0 }) } },
    V = { { { 0.1, 0, 0.5, 1, 0.9, 0 } } },
    W = { { { 0.05, 0, 0.27, 1, 0.5, 0.35, 0.73, 1, 0.95, 0 } } },
    X = { { { 0.15, 0, 0.85, 1 }, { 0.85, 0, 0.15, 1 } } },
    Y = { { { 0.15, 0, 0.5, 0.5, 0.85, 0 }, { 0.5, 0.5, 0.5, 1 } } },
    Z = { { { 0.15, 0, 0.85, 0, 0.15, 1, 0.85, 1 } } },
}

S.shapes = TEMPLATES -- for tests/scrittura-test.lua

-- $P, step 1: the strokes as N points evenly spaced along their length (a point never joins two strokes)
local function resample(strokes, n)
    local pts = {}
    for id, st in ipairs(strokes) do
        for i = 1, #st - 1, 2 do pts[#pts + 1] = { st[i], st[i + 1], id } end
    end
    local length = 0
    for i = 2, #pts do
        if pts[i][3] == pts[i - 1][3] then
            length = length + math.sqrt((pts[i][1] - pts[i - 1][1]) ^ 2 + (pts[i][2] - pts[i - 1][2]) ^ 2)
        end
    end
    if #pts == 0 then return {} end
    local step, acc, out = length / (n - 1), 0, { { pts[1][1], pts[1][2], pts[1][3] } }
    local i = 2
    while i <= #pts do
        local a, b = pts[i - 1], pts[i]
        if a[3] == b[3] then
            local d = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
            if step > 0 and acc + d >= step then
                local t = (step - acc) / d
                local q = { a[1] + t * (b[1] - a[1]), a[2] + t * (b[2] - a[2]), a[3] }
                out[#out + 1] = q
                table.insert(pts, i, q)
                acc = 0
            else
                acc = acc + d
            end
        end
        i = i + 1
    end
    while #out < n do out[#out + 1] = { pts[#pts][1], pts[#pts][2], pts[#pts][3] } end
    while #out > n do out[#out] = nil end
    return out
end

--- $P, steps 1 to 3: N points, scaled into a unit box (aspect kept), centred on their mean
function S.cloud(strokes)
    local p = resample(strokes, S.N)
    if #p == 0 then return p end
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, q in ipairs(p) do
        x0, y0, x1, y1 = math.min(x0, q[1]), math.min(y0, q[2]), math.max(x1, q[1]), math.max(y1, q[2])
    end
    local size = math.max(x1 - x0, y1 - y0)
    if size == 0 then size = 1 end
    local cx, cy = 0, 0
    for _, q in ipairs(p) do
        q[1], q[2] = (q[1] - x0) / size, (q[2] - y0) / size
        cx, cy = cx + q[1], cy + q[2]
    end
    cx, cy = cx / #p, cy / #p
    for _, q in ipairs(p) do q[1], q[2] = q[1] - cx, q[2] - cy end
    return p
end

-- $P, step 4: greedy matching from a start point, earlier matches weigh more
local function cloudDistance(a, b, start)
    local n, matched, sum, i = #a, {}, 0, start
    repeat
        local best, index = math.huge, nil
        for j = 1, n do
            if not matched[j] then
                local d = (a[i][1] - b[j][1]) ^ 2 + (a[i][2] - b[j][2]) ^ 2
                if d < best then best, index = d, j end
            end
        end
        matched[index] = true
        sum = sum + (1 - ((i - start + n) % n) / n) * math.sqrt(best)
        i = i % n + 1
    until i == start
    return sum
end

local function match(a, b)
    local n = #a
    local step = math.floor(n ^ 0.5)
    local best = math.huge
    for start = 1, n, step do
        best = math.min(best, cloudDistance(a, b, start), cloudDistance(b, a, start))
    end
    return best
end

local clouds -- templates as clouds, made the first time they're needed
function S.templates()
    if not clouds then
        clouds = {}
        for ch, forms in pairs(TEMPLATES) do
            clouds[ch] = {}
            for _, strokes in ipairs(forms) do table.insert(clouds[ch], S.cloud(strokes)) end
        end
    end
    return clouds
end

function S.recognize(strokes, chars, extra)
    local c = S.cloud(strokes)
    if #c < S.N then return nil end
    local best, best_d = nil, math.huge
    for ch in chars:gmatch(".") do
        local forms = {}
        for _, t in ipairs(S.templates()[ch] or {}) do forms[#forms + 1] = t end
        for _, t in ipairs(extra and extra[ch] or {}) do forms[#forms + 1] = t end
        for _, t in ipairs(forms) do
            local d = match(c, t)
            if d < best_d then best, best_d = ch, d end
        end
    end
    return best, best_d
end

return S
