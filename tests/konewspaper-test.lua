-- Self-check for knp_extract.lua, run from the repo root: texlua tests/konewspaper-test.lua [samples-dir | live]
package.path = "konewspaper.koplugin/?.lua;" .. package.path
local X = require("knp_extract")

-- tiny inline fixture: body beats sidebar, junk/links/scripts dropped, sloppy <p> handled
local html = [[<html><body><nav><p>Menu menu menu menu menu menu menu</p></nav>
<div class="sidebar"><p>Most read: something long enough to count as a paragraph here</p></div>
<article><div class="body"><p>First paragraph of the real article, long enough to score.
<p>Second &egrave; paragraph with <a href="http://x">a link</a> inside it, also long enough.</p>
<img src="https://img/photo.jpg" width="800" height="500"><img src="/logo.png">
<div class="share-tools"><p>Share this on social media please now right now</p></div>
<script>var p = "<p>nope</p>";</script></div></article></body></html>]]
local b = X.article(html)
assert(#b == 3, "blocks: " .. #b)
assert(b[1].text:find("^First paragraph"))
assert(b[2].text == "Second è paragraph with a link inside it, also long enough.", b[2].text)
assert(b[3].kind == "img" and b[3].src == "https://img/photo.jpg")

local f = X.feed([==[<rss><channel><item><title><![CDATA[Ciao &amp; mondo]]></title><link>https://a/1</link>
<description>&lt;p&gt;hi&lt;/p&gt;</description></item></channel></rss>]==])
assert(#f == 1 and f[1].title == "Ciao & mondo" and f[1].link == "https://a/1")
assert(X.feedHTML(f[1].content) == "<p>hi</p>")
assert(X.toUTF8("perch\232 \147ok\148") == "perchè “ok”") -- Latin-1/cp1252 page
assert(X.toUTF8("già") == "già")                            -- valid UTF-8 untouched
print("fixtures ok")

local dir = arg[1]
if dir then
    for _, name in ipairs({ "a1", "a2", "a3", "rai", "fatto", "ansa" }) do
        local fh = io.open(dir .. "/" .. name .. ".html", "rb")
        if fh then
            local blocks = X.article(fh:read("a")); fh:close()
            local imgs = 0
            for _, x in ipairs(blocks) do if x.kind == "img" then imgs = imgs + 1 end end
            print(("%-6s blocks=%3d chars=%6d imgs=%d"):format(name, #blocks, X.length(blocks), imgs))
            for i = 1, math.min(3, #blocks) do print("   ", blocks[i].kind, (blocks[i].text or blocks[i].src):sub(1, 90)) end
            local last = blocks[#blocks]; if last then print("   last", last.kind, (last.text or last.src):sub(1, 90)) end
        end
    end
end

-- Live check of every paper: texlua tests/konewspaper-test.lua live
if arg[1] == "live" then
    local function get(url)
        local p = io.popen('curl -sL -m 20 -A "Mozilla/5.0 (X11; Linux armv7l) AppleWebKit/537.36 Chrome/120 Safari/537.36" "' .. url .. '"', "r")
        local s = p:read("a"); p:close(); return s
    end
    for _, paper in ipairs(dofile("konewspaper.koplugin/giornali.lua")) do
        local items = X.feed(get(paper.feed))
        local good, chars, imgs = 0, 0, 0
        for i = 1, math.min(3, #items) do
            local b = X.article(get(items[i].link))
            if X.length(b) < 400 then b = X.article(X.feedHTML(items[i].content)) end
            if X.length(b) >= 400 then
                good = good + 1; chars = chars + X.length(b)
                for _, x in ipairs(b) do if x.kind == "img" then imgs = imgs + 1 end end
            end
        end
        print(("%-20s items=%2d  usable=%d/3  chars=%6d imgs=%d  first=%s"):format(paper.name, #items, good, chars, imgs, (items[1] and items[1].title or "-"):sub(1, 50)))
    end
end
