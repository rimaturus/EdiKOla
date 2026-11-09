-- Self-check for the puzzle generators, from the repo root: lua5.1 tests/giochi-test.lua
package.path = "konewspaper.koplugin/?.lua;" .. package.path
local P = require("knp_parole")
local S = require("knp_sudoku")
local C = require("knp_cruciverba")
local W = require("knp_crucipuzzle")

-- words: the same seed gives the same sequence; accents are dropped; headlines give blanked clues
local a, b = P.rng(7), P.rng(7)
for _ = 1, 5 do assert(a(1000) == b(1000)) end
assert(P.norm("Perché Città") == "PERCHECITTA")
local nw = P.fromNews({ { title = "Il Papa in Argentina, al Cottolengo", paper = "X" }, { title = "Oggi e ieri", paper = "Y" } })
assert(#nw == 1 and nw[1].word == "COTTOLENGO" and nw[1].clue == "Il Papa in Argentina, al ...", nw[1].clue)
for _, e in ipairs(P.dictionary) do assert(e.word:match("^[A-Z]+$") and #e.word >= 3, e.word) end

-- sudoku: a valid full solution, the puzzle agrees with it, one solution only, symmetric clues
local function valid(g)
    for k = 0, 8 do
        local r, c, bx = {}, {}, {}
        for j = 0, 8 do
            local br, bc = math.floor(k / 3) * 3 + math.floor(j / 3), k % 3 * 3 + j % 3
            for _, t in ipairs({ { r, g[k * 9 + j + 1] }, { c, g[j * 9 + k + 1] }, { bx, g[br * 9 + bc + 1] } }) do
                if t[1][t[2]] then return false end
                t[1][t[2]] = true
            end
        end
    end
    return true
end
for level = 1, 3 do
    for seed = 1, 3 do
        local t0 = os.clock()
        local puz, sol = S.generate(seed * 1000 + level, level)
        assert(valid(sol), "solution")
        local clues = 0
        for i = 1, 81 do
            if puz[i] ~= 0 then clues = clues + 1; assert(puz[i] == sol[i]) end
            assert((puz[i] == 0) == (puz[82 - i] == 0), "symmetry")
        end
        assert(S.solutions(puz, 2) == 1, "unique")
        assert(clues >= S.CLUES[level] and clues <= S.CLUES[level] + 12, "clues " .. clues)
        print(("sudoku level %d seed %d: %d clues, %.2fs"):format(level, seed, clues, os.clock() - t0))
    end
end

-- crossword: every run of 2+ letters is a listed word at its place, all words connected
local news = P.fromNews({
    { title = "Attacco hacker alla Dia: dati in vendita sul dark web", paper = "A" },
    { title = "Codice della strada, ecco cosa cambia per i monopattini", paper = "B" },
    { title = "Il Papa in Argentina incontra i giovani", paper = "C" },
    { title = "Idrogeno, un segnale di quattro miliardi di anni fa", paper = "D" },
    { title = "Arte rupestre in Catalogna, un film preistorico", paper = "E" },
})
for seed = 1, 5 do
    local cw = C.generate(news, P.dictionary, { seed = seed })
    local at = function(x, y) local r = cw.rows[y]; local ch = r and r:sub(x, x); return ch ~= "" and ch ~= "." and ch or nil end
    local listed = {}
    for _, wd in ipairs(cw.words) do
        local dx, dy = wd.dir == "a" and 1 or 0, wd.dir == "d" and 1 or 0
        for k = 1, #wd.word do assert(at(wd.x + dx * (k - 1), wd.y + dy * (k - 1)) == wd.word:sub(k, k), wd.word) end
        listed[wd.dir .. wd.x .. "," .. wd.y] = wd.word
        assert(wd.num and wd.clue, wd.word)
    end
    for _, dir in ipairs({ "a", "d" }) do
        local dx, dy = dir == "a" and 1 or 0, dir == "d" and 1 or 0
        for y = 1, cw.h do
            for x = 1, cw.w do
                if at(x, y) and not at(x - dx, y - dy) and at(x + dx, y + dy) then -- a run starts here
                    local run, k = "", 0
                    while at(x + dx * k, y + dy * k) do run = run .. at(x + dx * k, y + dy * k); k = k + 1 end
                    assert(listed[dir .. x .. "," .. y] == run, "stray run " .. run)
                end
            end
        end
    end
    -- connected: flood from one letter reaches every letter
    local total, seen, stack = 0, {}, { { cw.words[1].x, cw.words[1].y } }
    for y = 1, cw.h do for x = 1, cw.w do if at(x, y) then total = total + 1 end end end
    local reached = 0
    while #stack > 0 do
        local p = table.remove(stack)
        local key = p[1] .. "," .. p[2]
        if at(p[1], p[2]) and not seen[key] then
            seen[key], reached = true, reached + 1
            for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do table.insert(stack, { p[1] + d[1], p[2] + d[2] }) end
        end
    end
    assert(reached == total, "not connected")
    local from_news = 0
    for _, wd in ipairs(cw.words) do if wd.source then from_news = from_news + 1 end end
    assert(cw.w <= 13 and cw.h <= 12)
    print(("crossword seed %d: %dx%d, %d words (%d from the news)"):format(seed, cw.w, cw.h, #cw.words, from_news))
    assert(#cw.words >= 12, "too few words")
end

-- crucipuzzle: each word once at its place, the leftover letters spell the key
for seed = 1, 5 do
    local t0 = os.clock()
    local wp = W.generate(P.dictionary, { seed = seed })
    assert(wp and wp.key, "no key fitted")
    local covered = {}
    for _, p in ipairs(wp.words) do
        for k = 1, #p.word do
            local x, y = p.x + p.dx * (k - 1), p.y + p.dy * (k - 1)
            assert(wp.rows[y]:sub(x, x) == p.word:sub(k, k), p.word)
            covered[y * 100 + x] = true
        end
        assert(W.count(wp.rows, p.word) == 1, "twice: " .. p.word)
    end
    local left = ""
    for y = 1, wp.h do for x = 1, wp.w do if not covered[y * 100 + x] then left = left .. wp.rows[y]:sub(x, x) end end end
    assert(left == P.norm(wp.key), left .. " vs " .. wp.key)
    print(("crucipuzzle seed %d: %d words, key %q, %.2fs"):format(seed, #wp.words, wp.key, os.clock() - t0))
end
print("giochi-test: ok")
