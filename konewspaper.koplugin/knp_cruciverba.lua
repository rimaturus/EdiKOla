--[[--
"Schema libero" crossword generator (pure Lua).

    local cw = C.generate(news, dictionary, { seed =, w =, h =, want = })
    cw.w, cw.h            size after cropping
    cw.rows[y]            string of w chars: a letter, or "." for a black square
    cw.words[i]           { word =, clue =, source =, x =, y =, dir = "a"|"d", num = }  (a = orizzontale)

Every word crosses another, and no run of two or more letters appears that is not a word of the list.
News words are tried before dictionary words, so the day's headlines fill most of the grid.
]]
local P = require("knp_parole")
local C = {}

local function attempt(news, dict, w, h, want, rand)
    local grid, used = {}, {} -- grid[y][x] = letter; used[y][x] = { a = true, d = true }
    for y = 1, h do grid[y], used[y] = {}, {} end
    local function at(x, y) return grid[y] and grid[y][x] end
    local placed, seen, by_letter = {}, {}, {}

    local function fit(word, x, y, dir)
        local dx, dy = dir == "a" and 1 or 0, dir == "d" and 1 or 0
        local n = #word
        if x < 1 or y < 1 or x + dx * (n - 1) > w or y + dy * (n - 1) > h then return nil end
        if at(x - dx, y - dy) or at(x + dx * n, y + dy * n) then return nil end
        local crossings = 0
        for k = 1, n do
            local cx, cy = x + dx * (k - 1), y + dy * (k - 1)
            local ch, l = word:sub(k, k), at(cx, cy)
            if l then
                if l ~= ch or used[cy][cx][dir] then return nil end
                crossings = crossings + 1
            elseif at(cx + dy, cy + dx) or at(cx - dy, cy - dx) then -- a letter alongside: would make a new run
                return nil
            end
        end
        return crossings
    end

    local function put(e, x, y, dir)
        local dx, dy = dir == "a" and 1 or 0, dir == "d" and 1 or 0
        for k = 1, #e.word do
            local cx, cy = x + dx * (k - 1), y + dy * (k - 1)
            if not grid[cy][cx] then
                grid[cy][cx] = e.word:sub(k, k)
                used[cy][cx] = {}
                local l = grid[cy][cx]
                by_letter[l] = by_letter[l] or {}
                table.insert(by_letter[l], { cx, cy })
            end
            used[cy][cx][dir] = true
        end
        seen[e.word] = true
        table.insert(placed, { word = e.word, clue = e.clue, source = e.source, x = x, y = y, dir = dir })
    end

    -- the best spot for a word: most crossings, then a random one among equals
    local function spot(e)
        local best, best_score
        for k = 1, #e.word do
            for _, p in ipairs(by_letter[e.word:sub(k, k)] or {}) do
                for _, dir in ipairs({ "a", "d" }) do
                    local x = p[1] - (dir == "a" and k - 1 or 0)
                    local y = p[2] - (dir == "d" and k - 1 or 0)
                    local cr = fit(e.word, x, y, dir)
                    if cr and cr > 0 then
                        local score = cr * 100 + rand(99)
                        if not best_score or score > best_score then best, best_score = { x, y, dir }, score end
                    end
                end
            end
        end
        return best, best_score
    end

    local order = {}
    for _, e in ipairs(P.shuffle(news, rand)) do order[#order + 1] = e end
    table.sort(order, function(a, b) return #a.word > #b.word end)
    for _, e in ipairs(P.shuffle(dict, rand)) do order[#order + 1] = e end

    -- the first word: the longest headline word that fits across the middle
    for _, e in ipairs(order) do
        if #e.word <= w then
            put(e, math.floor((w - #e.word) / 2) + 1, math.floor(h / 2), "a")
            break
        end
    end
    local crossings = 0
    for _ = 1, 3 do -- later words open new crossings for the ones skipped before
        for _, e in ipairs(order) do
            if #placed >= want then break end
            if not seen[e.word] and #e.word >= 3 then
                local s = spot(e)
                if s then
                    crossings = crossings + (fit(e.word, s[1], s[2], s[3]) or 0)
                    put(e, s[1], s[2], s[3])
                end
            end
        end
    end
    return { grid = grid, placed = placed, crossings = crossings, w = w, h = h }
end

-- crop to the letters, number the squares that start a word
local function finish(a)
    local x0, y0, x1, y1 = a.w, a.h, 1, 1
    for y = 1, a.h do
        for x = 1, a.w do
            if a.grid[y][x] then
                x0, y0, x1, y1 = math.min(x0, x), math.min(y0, y), math.max(x1, x), math.max(y1, y)
            end
        end
    end
    local cw = { w = x1 - x0 + 1, h = y1 - y0 + 1, rows = {}, words = {} }
    for y = y0, y1 do
        local row = {}
        for x = x0, x1 do row[#row + 1] = a.grid[y][x] or "." end
        cw.rows[#cw.rows + 1] = table.concat(row)
    end
    local starts = {}
    for _, p in ipairs(a.placed) do
        local wd = { word = p.word, clue = p.clue, source = p.source, x = p.x - x0 + 1, y = p.y - y0 + 1, dir = p.dir }
        starts[wd.y * 1000 + wd.x] = true
        cw.words[#cw.words + 1] = wd
    end
    local num, nums = 0, {}
    for y = 1, cw.h do
        for x = 1, cw.w do
            if starts[y * 1000 + x] then num = num + 1; nums[y * 1000 + x] = num end
        end
    end
    for _, wd in ipairs(cw.words) do wd.num = nums[wd.y * 1000 + wd.x] end
    table.sort(cw.words, function(a, b)
        if a.dir ~= b.dir then return a.dir == "a" end
        return a.num < b.num
    end)
    return cw
end

function C.generate(news, dict, opts)
    opts = opts or {}
    local w, h, want = opts.w or 13, opts.h or 12, opts.want or 18
    local best
    for t = 1, opts.tries or 30 do
        local rand = P.rng((opts.seed or 1) * 97 + t)
        local copy_news, copy_dict = {}, {}
        for i, e in ipairs(news or {}) do copy_news[i] = e end
        for i, e in ipairs(dict or {}) do copy_dict[i] = e end
        local a = attempt(copy_news, copy_dict, w, h, want, rand)
        local score = #a.placed * 1000 + a.crossings
        if not best or score > best.score then a.score = score; best = a end
        if #a.placed >= want then break end
    end
    return finish(best)
end

return C
