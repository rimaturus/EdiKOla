-- The voice (knp_voce) and the Ascolta player (knp_ascolta), offline, on KOReader's own runtime (Linux build):
--   cd $KO/lib/koreader && VOCI=<voci dir> ./luajit <repo>/tests/voce-test.lua
-- VOCI: a voci/ folder as android/build.sh makes it, plus lib/ with sherpa-onnx for Linux. Without it only the
-- text part runs. The player plays silently, on a clock 20 times faster, so the voice has to keep up.
require("setupkoenv")
local repo = arg[0]:match("^(.*)/tests/[^/]*$")
package.path = repo .. "/konewspaper.koplugin/?.lua;" .. package.path
local lfs = require("libs/libkoreader-lfs")
local socket = require("socket")

local home = os.tmpname()
os.remove(home)
assert(lfs.mkdir(home))

-- KOReader's UI isn't running: just enough of it for the player's logic
local tasks = {}
package.loaded["ui/uimanager"] = {
    scheduleIn = function(_, s, f) table.insert(tasks, { at = socket.gettime() + s, f = f }) end,
    unschedule = function(_, f) for i = #tasks, 1, -1 do if tasks[i].f == f then table.remove(tasks, i) end end end,
    nextTick = function(_, f) table.insert(tasks, { at = 0, f = f }) end,
    show = function() end, close = function() end, setDirty = function() end,
}
local function run(seconds, done)
    local stop = socket.gettime() + seconds
    while socket.gettime() < stop and not (done and done()) do
        local now = socket.gettime()
        for i = #tasks, 1, -1 do
            if tasks[i] and tasks[i].at <= now then table.remove(tasks, i).f() end
        end
        socket.sleep(0.05)
    end
end
package.loaded["ui/time"] = { now = function() return socket.gettime() * 20 end, to_s = function(t) return t end }
package.loaded["device"] = { home_dir = home, isAndroid = function() return false end, hasKeys = function() return false end,
    screen = {} }
package.loaded["datastorage"] = { getDataDir = function() return home end }
local Widget = { extend = function(_, t) t = t or {}; t.new = function(_, o) return o or {} end; return t end }
for _, m in ipairs{ "ui/widget/button", "ui/widget/container/centercontainer", "ui/font", "ui/widget/container/framecontainer",
    "ui/geometry", "ui/widget/horizontalgroup", "ui/widget/horizontalspan", "ui/widget/container/inputcontainer",
    "ui/widget/linewidget", "ui/widget/textboxwidget", "ui/widget/verticalgroup", "ui/widget/verticalspan", "knp_theme" } do
    package.loaded[m] = Widget
end

local V = require("knp_voce")
if os.getenv("VOCI") then V.dir = os.getenv("VOCI") end

-- an edition as knp_build writes it: an Italian article, an English one
local X = require("knp_extract")
local function chapter(title, ps)
    local body = { "<h1>" .. X.escape(title) .. "</h1>", '<div class="img"><img src="images/x.jpg" alt=""/></div>' }
    for _, p in ipairs(ps) do table.insert(body, "<p>" .. X.escape(p) .. "</p>") end
    table.insert(body, '<p class="back"><a href="index.xhtml">↩ Torna ai titoli</a></p>')
    return ('<?xml version="1.0"?><html><head><title>%s</title></head><body>\n%s\n</body></html>'):format(X.escape(title), table.concat(body, "\n"))
end
local it = { "Il mercato torna in piazza sabato, con più di quaranta banchi di frutta, fiori e formaggi del territorio.",
    "Il sindaco ha detto che è una festa per tutta la città e che la piazza sarà chiusa al traffico.",
    "Gli organizzatori aspettano molti visitatori anche dai paesi vicini, se il tempo sarà bello." }
local en = { "New sleeper routes will link three capitals from December, the operators said on Tuesday.",
    "Tickets cost from forty-nine euros, and the first trains are already full for the holidays.",
    "Rail fans have waited for this for years, and they say it is the most relaxed way to travel." }
local epub = home .. "/2026-11-12.epub"
local w = require("ffi/archiver").Writer:new{}
assert(w:open(epub, "epub"))
w:addFileFromMemory("OEBPS/index.xhtml", chapter("Il Corriere", {}))
w:addFileFromMemory("OEBPS/a1.xhtml", chapter("Torna il mercato del sabato & dei fiori", it))
w:addFileFromMemory("OEBPS/a2.xhtml", chapter("Night trains return to Europe", en))
w:close()

local arts = V.read(epub)
assert(#arts == 2, "articles: " .. #arts)
assert(arts[1].title == "Torna il mercato del sabato & dei fiori", arts[1].title)
assert(#arts[1].text == 3 and arts[1].text[1] == it[1], "the link back to the headlines is not read")
assert(V.lang(arts[1].title .. " " .. table.concat(arts[1].text, " ")) == "it")
assert(V.lang(arts[2].title .. " " .. table.concat(arts[2].text, " ")) == "en")
local chunks = V.chunks(arts, "Il Corriere. Giovedì 12 novembre 2026.")
assert(chunks[1].lang == "it" and chunks[1].pause == 1)
assert(chunks[2].text == arts[1].title and chunks[2].article == 1)
assert(chunks[#chunks].lang == "en" and chunks[#chunks].article == 2 and chunks[#chunks].pause == 1.5)
for _, c in ipairs(chunks) do assert(#c.text <= 700 + 200, "piece too long") end
local long = V.chunks({ { title = "T", text = { ("Una frase di prova, abbastanza lunga da contare. "):rep(40) } } })
assert(#long > 3, "a long paragraph is split in sentences")
for _, c in ipairs(long) do assert(#c.text <= 700 + 60, "piece too long: " .. #c.text) end
print("text ok:", #chunks, "pieces")

if not V.ready() then return print("no voices (VOCI): player not tested") end
local A = require("knp_ascolta")
local seen = {}
A.listen(epub, "Il Corriere", "giovedì 12 novembre 2026", function() end)
run(60, function() seen[A.k or 0] = A.cur ~= nil or nil; return A.chunks and A.article() == 2 end)
assert(A.chunks and A.article() == 2, "article 2 never reached")
assert(seen[1] and seen[2], "intro and title not played")
A.toggle()
assert(A.paused)
local k = A.k
run(3)
assert(A.k == k, "moved while paused")
A.toggle()
A.go(1)
assert(A.k == 1 and not A.cur)
run(1)
assert(A.pid, "no child making the audio")
require("ffi/util").terminateSubProcess(A.pid) -- as Android may do: the player starts another one
run(90, function() return not A.chunks end)
assert(not A.chunks, "never finished")
assert(not lfs.attributes(home .. "/cache/edikola-voce"), "audio left behind")
print("player ok")
