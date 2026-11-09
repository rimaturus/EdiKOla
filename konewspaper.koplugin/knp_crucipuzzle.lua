--[[--
Crucipuzzle (word search with a key) generator, pure Lua.

    local wp = W.generate(entries, { seed =, w =, h = })
    wp.rows[y]     string of w letters
    wp.words[i]    { word =, x =, y =, dx =, dy = }   sorted alphabetically
    wp.key         the phrase the leftover letters spell, in reading order (nil if none fitted)

Words run in any of the 8 directions and may share letters. Each word appears exactly once.
]]
local P = require("knp_parole")
local W = {}

local DIRS = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 }, { -1, 0 }, { 0, -1 }, { -1, -1 }, { -1, 1 } }

--- How many times word can be read in the grid (rows = strings), in all 8 directions.
function W.count(rows, word)
    local h, w, n = #rows, #rows[1], 0
    for y = 1, h do
        for x = 1, w do
            if rows[y]:sub(x, x) == word:sub(1, 1) then
                for _, d in ipairs(DIRS) do
                    local k = 2
                    while k <= #word do
                        local cx, cy = x + d[1] * (k - 1), y + d[2] * (k - 1)
                        if cy < 1 or cy > h or cx < 1 or cx > w or rows[cy]:sub(cx, cx) ~= word:sub(k, k) then break end
                        k = k + 1
                    end
                    if k > #word then n = n + 1 end
                end
            end
        end
    end
    -- a palindrome reads the same both ways: count it once
    if #word > 1 and word == word:reverse() then n = n / 2 end
    return n
end

local function attempt(pool, w, h, rand, by_len)
    local g = {}
    for i = 1, w * h do g[i] = false end
    local placed, empties, saved = {}, w * h, nil

    local function try(word)
        local best, best_ov
        for _ = 1, 120 do
            local d = DIRS[rand(8)]
            local x, y = rand(w), rand(h)
            local ex, ey = x + d[1] * (#word - 1), y + d[2] * (#word - 1)
            if ex >= 1 and ex <= w and ey >= 1 and ey <= h then
                local ov, ok = 0, true
                for k = 1, #word do
                    local c = g[(y + d[2] * (k - 1) - 1) * w + x + d[1] * (k - 1)]
                    if c then
                        if c ~= word:sub(k, k) then ok = false; break end
                        ov = ov + 1
                    end
                end
                if ok and ov < #word and (not best_ov or ov > best_ov) then best, best_ov = { x, y, d }, ov end
            end
        end
        return best
    end

    for _, word in ipairs(pool) do
        if empties < 6 then break end
        local s = try(word)
        if s then
            for k = 1, #word do
                local i = (s[2] + s[3][2] * (k - 1) - 1) * w + s[1] + s[3][1] * (k - 1)
                if not g[i] then empties = empties - 1 end
                g[i] = word:sub(k, k)
            end
            table.insert(placed, { word = word, x = s[1], y = s[2], dx = s[3][1], dy = s[3][2] })
            local keys = by_len[empties]
            if keys and #placed >= 8 then -- a key fits the holes left: remember this grid
                local copy = {}
                for i = 1, w * h do copy[i] = g[i] end
                local list = {}
                for i, p in ipairs(placed) do list[i] = p end
                saved = { g = copy, placed = list, key = keys[rand(#keys)] }
            end
        end
    end
    return saved
end

-- letters of the key into the holes, then the checks; nil if a word shows up twice
local function finish(s, w, h)
    local key, k, rows = P.norm(s.key), 0, {}
    for y = 1, h do
        local row = {}
        for x = 1, w do
            local c = s.g[(y - 1) * w + x]
            if not c then k = k + 1; c = key:sub(k, k) end
            row[x] = c
        end
        rows[y] = table.concat(row)
    end
    for _, p in ipairs(s.placed) do
        if W.count(rows, p.word) ~= 1 then return nil end
    end
    table.sort(s.placed, function(a, b) return a.word < b.word end)
    return { w = w, h = h, rows = rows, words = s.placed, key = s.key }
end

function W.generate(entries, opts)
    opts = opts or {}
    local w, h = opts.w or 10, opts.h or 10
    local by_len = {}
    for _, key in ipairs(P.keys) do
        local n = #P.norm(key)
        by_len[n] = by_len[n] or {}
        table.insert(by_len[n], key)
    end
    -- candidate words: fit the grid, and none inside another (it would be found twice)
    local words, seen = {}, {}
    for _, e in ipairs(entries) do
        local wd = e.word
        if #wd >= 4 and #wd <= math.max(w, h) and not seen[wd] then seen[wd] = true; words[#words + 1] = wd end
    end
    local best
    for t = 1, opts.tries or 60 do
        local rand = P.rng((opts.seed or 1) * 131 + t)
        local pool = {}
        for _, wd in ipairs(P.shuffle(words, rand)) do
            local inside = false
            for _, other in ipairs(pool) do
                if other:find(wd, 1, true) or wd:find(other, 1, true)
                    or other:find(wd:reverse(), 1, true) or wd:find(other:reverse(), 1, true) then
                    inside = true; break
                end
            end
            if not inside then pool[#pool + 1] = wd end
            if #pool >= 26 then break end
        end
        table.sort(pool, function(a, b) return #a > #b end) -- long words first, short ones fill the gaps
        local s = attempt(pool, w, h, rand, by_len)
        local done = s and finish(s, w, h)
        if done and (not best or #done.words > #best.words) then best = done end
        if best and #best.words >= 16 then break end
    end
    return best
end

return W
