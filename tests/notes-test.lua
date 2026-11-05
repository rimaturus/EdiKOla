-- Self-check for knp_ink.lua (pen notes), run from the repo root: texlua tests/notes-test.lua
package.path = "konewspaper.koplugin/?.lua;" .. package.path
local ink = require("knp_ink")

-- ids: one per article of an edition, safe as a file name
assert(ink.id("/sdcard/KoNewspaper/rainews/2026-11-05.epub", 3) == "rainews-2026-11-05-3", ink.id("/sdcard/KoNewspaper/rainews/2026-11-05.epub", 3))
assert(ink.id("/sdcard/Libri/Un libro (2).epub", 7) == "Libri-Un_libro__2_-7")
assert(ink.id():match("^foglio%-%d+%-%d+$"))

-- round trip, titles with quotes and newlines
local n = { title = 'Il "titolo"\ndue righe', sub = "RaiNews24", file = "/x/y.epub", chapter = 4, w = 1072, h = 1200,
    strokes = { { c = "blu", p = { 10, 20, 30, 40, 50, 60 } }, { c = "rosso", p = { 500, 500 } } } }
local back = ink.decode(ink.encode(n))
assert(back.title == n.title and back.sub == n.sub and back.file == n.file and back.chapter == 4)
assert(#back.strokes == 2 and back.strokes[1].c == "blu" and back.strokes[1].p[6] == 60 and back.strokes[2].p[1] == 500)
local free = ink.decode(ink.encode{ title = "", w = 10, h = 10, strokes = {} })
assert(free.file == nil and free.chapter == nil and #free.strokes == 0)

-- a planted file gets no globals, and junk is refused
assert(ink.decode("return { strokes = {}, x = os }").x == nil)
assert(ink.decode("os.exit(1)") == nil)
assert(ink.decode("not lua at all") == nil)
assert(ink.decode(nil) == nil)

-- eraser: near a segment's middle hits, far misses, a dot works
local st = { c = "nero", p = { 0, 0, 100, 0 } }
assert(ink.hit(st, 50, 5, 10))
assert(not ink.hit(st, 50, 30, 10))
assert(not ink.hit(st, 130, 0, 10))
assert(ink.hit({ c = "nero", p = { 7, 7 } }, 10, 10, 5))

-- another screen size: scaled, keeps proportions
local big = { w = 2000, h = 2000, strokes = { { c = "nero", p = { 1000, 2000 } } } }
ink.fit(big, 1000, 1500)
assert(big.w == 1000 and big.strokes[1].p[1] == 500 and big.strokes[1].p[2] == 1000)

print("notes: all OK")
