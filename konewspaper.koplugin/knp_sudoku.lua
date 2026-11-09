--[[--
Sudoku generator (pure Lua). Grids are 81 numbers, row by row, 0 = empty.

    local puzzle, solution = S.generate(seed, level)  -- level 1 facile, 2 medio, 3 difficile
    S.solutions(grid, limit)                           -- how many solutions, counting up to limit

Every puzzle has exactly one solution; clues are removed in pairs symmetric about the centre, like the
magazines print them.
]]
local P = require("knp_parole")
local S = {}

local function candidates(g, i)
    local r, c = math.floor((i - 1) / 9), (i - 1) % 9
    local used = {}
    for k = 0, 8 do
        used[g[r * 9 + k + 1]] = true
        used[g[k * 9 + c + 1]] = true
    end
    local br, bc = r - r % 3, c - c % 3
    for dr = 0, 2 do
        for dc = 0, 2 do used[g[(br + dr) * 9 + bc + dc + 1]] = true end
    end
    local out = {}
    for v = 1, 9 do
        if not used[v] then out[#out + 1] = v end
    end
    return out
end

-- the empty cell with the fewest candidates (nil when the grid is full)
local function tightest(g)
    local best, best_c
    for i = 1, 81 do
        if g[i] == 0 then
            local c = candidates(g, i)
            if #c == 0 then return i, c end
            if not best or #c < #best_c then best, best_c = i, c end
        end
    end
    return best, best_c
end

local function fill(g, rand)
    local i, c = tightest(g)
    if not i then return true end
    for _, v in ipairs(P.shuffle(c, rand)) do
        g[i] = v
        if fill(g, rand) then return true end
    end
    g[i] = 0
    return false
end

--- Number of solutions of g, counting no further than limit. g is left as it was.
function S.solutions(g, limit)
    local i, c = tightest(g)
    if not i then return 1 end
    local n = 0
    for _, v in ipairs(c) do
        g[i] = v
        n = n + S.solutions(g, limit - n)
        if n >= limit then break end
    end
    g[i] = 0
    return n
end

S.CLUES = { 38, 30, 25 } -- facile, medio, difficile: how many digits are given (at least)

function S.generate(seed, level)
    local rand = P.rng(seed)
    local sol = {}
    for i = 1, 81 do sol[i] = 0 end
    fill(sol, rand)
    local puz = {}
    for i = 1, 81 do puz[i] = sol[i] end
    local order = {}
    for i = 1, 41 do order[i] = i end -- cell i and its mirror 82 - i (41 is the centre)
    P.shuffle(order, rand)
    local clues, target = 81, S.CLUES[level] or S.CLUES[2]
    for _, i in ipairs(order) do
        local j = 82 - i
        local n = i == j and 1 or 2
        if clues - n >= target then
            local a, b = puz[i], puz[j]
            puz[i], puz[j] = 0, 0
            if S.solutions(puz, 2) == 1 then
                clues = clues - n
            else
                puz[i], puz[j] = a, b
            end
        end
    end
    return puz, sol
end

return S
