-- Self-check for knp_scrittura.lua (handwriting in the puzzles), from the repo root: lua5.1 tests/scrittura-test.lua
package.path = "konewspaper.koplugin/?.lua;" .. package.path
local S = require("knp_scrittura")

local DIGITS, LETTERS = "123456789", "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

-- a template as a hand would write it: squeezed or stretched, slanted, shaky, in pixels, somewhere in a cell
local function written(strokes, sx, slant, shake, seed)
    local out, k = {}, seed
    for _, st in ipairs(strokes) do
        local p = {}
        for i = 1, #st - 1, 2 do
            k = (k * 16807) % 2147483647
            local jx, jy = (k % 7 - 3) * shake, (math.floor(k / 7) % 7 - 3) * shake
            local x, y = st[i] * sx, st[i + 1]
            p[#p + 1] = 300 + 80 * (x + slant * (1 - y)) + jx
            p[#p + 1] = 500 + 80 * y + jy
        end
        out[#out + 1] = p
    end
    return out
end

local fails = {}
for _, set in ipairs({ DIGITS, LETTERS }) do
    for ch in set:gmatch(".") do
        for f, form in ipairs(S.shapes[ch]) do
            for v, d in ipairs({ { 1, 0, 0 }, { 0.8, 0.15, 0.4 }, { 1.15, -0.1, 0.6 } }) do
                local got = S.recognize(written(form, d[1], d[2], d[3], #ch * 131 + f * 7 + v), set)
                if got ~= ch then fails[#fails + 1] = ("%s (form %d, variant %d) read as %s"):format(ch, f, v, tostring(got)) end
            end
        end
    end
end
assert(#fails == 0, "\n" .. table.concat(fails, "\n"))

-- only the allowed answers come back: a 1 among letters reads as I, never as a digit
assert(S.recognize(written(S.shapes["1"][1], 1, 0, 0, 1), LETTERS) == "I")
-- too little to read: nothing
assert(S.recognize({}, DIGITS) == nil)

-- the user's own writing, taught once, wins over the built-in shapes
local squiggle = { { 0, 0, 1, 0.2, 0, 0.4, 1, 0.6, 0, 0.8, 1, 1 } }
local before = S.recognize(written(squiggle, 1, 0, 0, 3), LETTERS)
assert(S.recognize(written(squiggle, 1, 0, 0.3, 5), LETTERS, { K = { S.cloud(squiggle) } }) == "K", before)
print("scrittura: all OK")
