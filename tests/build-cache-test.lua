-- Article cache in knp_build.lua, offline (a fake web stands in for http.request).
-- Runs on KOReader's own runtime (Linux build): cd $KO/lib/koreader && ./luajit <repo>/tests/build-cache-test.lua
require("setupkoenv")
local repo = arg[0]:match("^(.*)/tests/[^/]*$")
package.path = repo .. "/konewspaper.koplugin/?.lua;" .. package.path

local home = os.tmpname()
os.remove(home)
assert(require("libs/libkoreader-lfs").mkdir(home))
package.loaded["device"] = { home_dir = home }

local PNG = "\137PNG\r\n\26\n" .. ("x"):rep(200)
local web, hits = {}, {}
local function article(n)
    local ps = {}
    for i = 1, 8 do
        table.insert(ps, ("<p>Paragraph %d of article %d, long enough to count as real article text.</p>"):format(i, n))
    end
    return "<html><body><article>" .. table.concat(ps) .. '<img src="/p' .. n .. '.png" width="800" height="500">'
        .. "</article></body></html>"
end
local function feed(n)
    local items = {}
    for i = n, 1, -1 do
        table.insert(items, ("<item><title>Title %d</title><link>http://t/a%d</link></item>"):format(i, i))
    end
    table.insert(items, "<item><title>Video</title><link>http://t/video</link></item>")
    return "<rss><channel>" .. table.concat(items) .. "</channel></rss>"
end
for i = 1, 4 do web["http://t/a" .. i] = article(i); web["http://t/p" .. i .. ".png"] = PNG end
web["http://t/video"] = "<html><body><p>short</p></body></html>"

require("socket.http").request = function(req)
    table.insert(hits, req.url)
    local body = web[req.url]
    if not body then return 1, 404, {} end
    req.sink(body)
    req.sink(nil)
    return 1, 200, {}
end

local Build = require("knp_build")
local paper = { id = "test", name = "Test", feed = "http://t/feed" }
local function update(n)
    web["http://t/feed"] = feed(n)
    hits = {}
    local path, err = Build.paper(paper)
    assert(path, err)
    return path, #hits
end
local lfs = require("libs/libkoreader-lfs")

local path, n = update(3)
assert(n == 1 + 3 * 2 + 1, "first update: feed, 3 articles + 3 photos, the video page; got " .. n)
local stamp = lfs.attributes(path, "modification")
local meta = Build.meta(path)
assert(meta.headline == "Title 3" and meta.cover, "front page")

path, n = update(3)
assert(n == 1, "nothing new: only the feed; got " .. n)
assert(lfs.attributes(path, "modification") == stamp, "unchanged edition was rewritten")

path, n = update(4)
assert(n == 1 + 2, "one new article: feed + article + photo; got " .. n)
assert(Build.meta(path).headline == "Title 4")

-- a cached article whose .lua got lost is just downloaded again
local cache = home .. "/KoNewspaper/test/cache"
for f in lfs.dir(cache) do if f:match("%.lua$") then os.remove(cache .. "/" .. f); break end end
web["http://t/feed"] = feed(4)
hits = {}
assert(Build.paper(paper))
assert(#hits == 1 + 2 or #hits == 1 + 1, "one entry re-downloaded; got " .. #hits)

-- the EPUB really holds 4 articles and their photos
local Archiver = require("ffi/archiver")
local r = Archiver.Reader:new()
assert(r:open(path))
local chapters, photos = 0, 0
for e in r:iterate() do
    if e.path:match("^OEBPS/a%d+%.xhtml$") then chapters = chapters + 1 end
    if e.path:match("^OEBPS/images/") then photos = photos + 1 end
end
r:close()
assert(chapters == 4 and photos == 4, ("epub: %d chapters, %d photos"):format(chapters, photos))

os.execute("rm -rf '" .. home .. "'")
print("build cache ok")
