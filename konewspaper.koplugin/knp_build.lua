--[[--
Downloads one newspaper and packs it as a single EPUB: a front page with the headlines,
then one chapter per article (text + up to 3 photos), each ending with a "back to headlines" link.
]]

local Archiver = require("ffi/archiver")
local Device = require("device")
local ffiutil = require("ffi/util")
local http = require("socket.http")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ltn12 = require("ltn12")
local sha2 = require("ffi/sha2")
local socket = require("socket")
local socket_url = require("socket.url")
local socketutil = require("socketutil")
local X = require("knp_extract")

local Build = {}

Build.root = (Device.home_dir or "/mnt/onboard") .. "/KoNewspaper"
local KEEP_DAYS = 3
local MAX_IMAGES = 3
local MAX_IMAGE_BYTES = 1500 * 1024
local UA = "Mozilla/5.0 (X11; Linux armv7l) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36"

local GIORNI = { "domenica", "lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "sabato" }
local MESI = { "gennaio", "febbraio", "marzo", "aprile", "maggio", "giugno", "luglio", "agosto", "settembre", "ottobre", "novembre", "dicembre" }

function Build.dateLabel(t)
    local d = os.date("*t", t)
    return ("%s %d %s %d"):format(GIORNI[d.wday], d.day, MESI[d.month], d.year)
end

function Build.path(paper, t)
    return ("%s/%s/%s.epub"):format(Build.root, paper.id, os.date("%Y-%m-%d", t))
end

--- Front-page info for the newsstand tile and the Sommario: { headline=, cover=, articles={ {title=, brief=} } } (or {})
function Build.meta(epub)
    local ok, meta = pcall(dofile, (epub:gsub("%.epub$", ".meta.lua")))
    return ok and type(meta) == "table" and meta or {}
end

--- Newest edition on disk, or nil
function Build.latest(paper)
    local dir = Build.root .. "/" .. paper.id
    if lfs.attributes(dir, "mode") ~= "directory" then return nil end
    local newest
    for f in lfs.dir(dir) do
        if f:match("^%d%d%d%d%-%d%d%-%d%d%.epub$") and (not newest or f > newest) then newest = f end
    end
    return newest and dir .. "/" .. newest
end

local function get(url)
    for _ = 1, 5 do -- follow redirects ourselves: luasocket won't across http/https
        local sink = {}
        socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
        local code, headers = socket.skip(1, http.request{
            url = url,
            method = "GET",
            sink = ltn12.sink.table(sink),
            redirect = false,
            headers = { ["user-agent"] = UA, ["accept-language"] = "it-IT,it;q=0.9,en;q=0.8" },
        })
        socketutil:reset_timeout()
        if type(code) ~= "number" then
            logger.warn("KoNewspaper: no response", url, code)
            return nil
        end
        if code >= 300 and code < 400 and headers and headers.location then
            url = socket_url.absolute(url, headers.location)
        elseif code == 200 then
            return table.concat(sink)
        else
            logger.warn("KoNewspaper: HTTP", code, url)
            return nil
        end
    end
end

local function imageType(data)
    if data:sub(1, 3) == "\255\216\255" then return "jpg", "image/jpeg" end
    if data:sub(1, 8) == "\137PNG\r\n\26\n" then return "png", "image/png" end
    if data:sub(1, 4) == "GIF8" then return "gif", "image/gif" end
    if data:sub(1, 4) == "RIFF" and data:sub(9, 12) == "WEBP" then return "webp", "image/webp" end
end

local CSS = [[
body { margin: 0; text-align: justify; }
h1 { font-size: 1.45em; line-height: 1.2; text-align: left; margin: 0 0 0.6em 0; }
h2, h3 { font-size: 1.15em; text-align: left; margin: 1em 0 0.4em 0; }
p { margin: 0 0 0.7em 0; text-indent: 0; }
a { color: black; text-decoration: none; }
.mast { font-size: 2.2em; text-align: center; margin: 0.2em 0 0.1em 0; }
.date { text-align: center; font-style: italic; margin-bottom: 1em; border-bottom: 2px solid black; padding-bottom: 0.5em; }
.toc p { font-size: 1.1em; text-align: left; margin: 0; padding: 0.55em 0; border-bottom: 1px solid #999; }
.img { text-align: center; margin: 0.8em 0; }
.img img { max-width: 100%; }
.back { text-align: center; font-weight: bold; margin-top: 1.5em; padding: 0.5em; border: 2px solid black; }
]]

local function page(title, body)
    return ([[<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml"><head><meta charset="utf-8"/><title>%s</title>
<link rel="stylesheet" type="text/css" href="style.css"/></head><body>
%s
</body></html>]]):format(X.escape(title), body)
end

-- Article cache, in <paper>/cache/: <md5 of link>.lua (title, body, photo list) and the photos next to it.
-- An article already downloaded costs no network on the next update; so does a link that gave no usable
-- article ({ skip = true }: videos, teasers). The .lua is written last, so an interrupted save is just a miss.
local function loadCached(cache, key)
    local ok, art = pcall(dofile, cache .. "/" .. key .. ".lua")
    if not (ok and type(art) == "table") then return nil end
    for _, img in ipairs(art.images or {}) do
        local f = io.open(cache .. "/" .. img.name:match("[^/]+$"), "rb")
        if not f then return nil end
        img.data = f:read("*a")
        f:close()
    end
    return art
end

local function saveCached(cache, key, art)
    local list = {}
    for _, img in ipairs(art.images or {}) do
        local f = io.open(cache .. "/" .. img.name:match("[^/]+$"), "wb")
        if not f then return end
        f:write(img.data)
        f:close()
        table.insert(list, ("{ name = %q, mime = %q, ext = %q }"):format(img.name, img.mime, img.ext))
    end
    local f = io.open(cache .. "/" .. key .. ".lua", "w")
    if not f then return end
    if art.skip then
        f:write("return { skip = true }\n")
    else
        f:write(("return { title = %q, body = %q, images = { %s } }\n"):format(art.title, art.body, table.concat(list, ", ")))
    end
    f:close()
end

-- Keeps only the cache entries of the links looked at in this update
local function pruneCache(cache, used)
    for f in lfs.dir(cache) do
        local key = f:match("^(%x+)[_.]")
        if key and not used[key] then os.remove(cache .. "/" .. f) end
    end
end

-- One article: { title=, body=, images={ {name=, data=, mime=, ext=} } }, or { skip = true }
local function download(item, key)
    local html = get(item.link)
    local blocks = html and X.article(html) or {}
    if X.length(blocks) < 400 then blocks = X.article(X.feedHTML(item.content)) end
    if X.length(blocks) < 400 then return { skip = true } end
    local body, images = {}, {}
    for _, b in ipairs(blocks) do
        if b.kind == "img" then
            if #images < MAX_IMAGES then
                local data = get(socket_url.absolute(item.link, b.src))
                local ext, mime
                if data and #data <= MAX_IMAGE_BYTES then ext, mime = imageType(data) end
                if ext then
                    local name = ("images/%s_%d.%s"):format(key, #images + 1, ext)
                    table.insert(images, { name = name, data = data, mime = mime, ext = ext })
                    table.insert(body, ('<div class="img"><img src="%s" alt=""/></div>'):format(name))
                end
            end
        elseif b.kind == "h" then
            table.insert(body, "<h3>" .. X.escape(b.text) .. "</h3>")
        else
            table.insert(body, "<p>" .. X.escape(b.text) .. "</p>")
        end
    end
    return { title = item.title, body = table.concat(body, "\n"), images = images }
end

--- Builds today's edition. progress(msg) returns false to cancel.
-- Only articles not downloaded before use the network. Today's edition is kept as it is when nothing is new.
-- Returns the EPUB path, or nil and an error message.
function Build.paper(paper, progress)
    progress = progress or function() return true end
    if not progress(("%s\n\nScarico i titoli…"):format(paper.name)) then return nil, "annullato" end

    local xml = get(paper.feed)
    if not xml then return nil, "giornale non raggiungibile" end
    local items = X.feed(xml)

    local dir = Build.root .. "/" .. paper.id
    local cache = dir .. "/cache"
    lfs.mkdir(Build.root)
    lfs.mkdir(dir)
    lfs.mkdir(cache)
    local max = paper.max or 10
    local articles, images, used, fresh = {}, {}, {}, 0
    for i = 1, math.min(#items, max * 2) do -- spare tries: videos and teasers are skipped
        if #articles >= max then break end
        local item = items[i]
        local key = sha2.md5(item.link)
        if not used[key] then -- the same link twice in a feed
            used[key] = true
            local art = loadCached(cache, key)
            if not art then
                fresh = fresh + 1
                if not progress(("%s\n\nArticolo nuovo %d…"):format(paper.name, fresh)) then return nil, "annullato" end
                art = download(item, key)
                saveCached(cache, key, art)
            end
            if not art.skip then
                table.insert(articles, art)
                for _, img in ipairs(art.images) do table.insert(images, img) end
            end
        end
    end
    pruneCache(cache, used)
    if #articles == 0 then return nil, "nessun articolo gratuito trovato" end

    local now = os.time()
    local path = Build.path(paper, now)
    -- nothing new today (editions from before the article list get rebuilt once, from the cache)
    if fresh == 0 and lfs.attributes(path, "mode") == "file" and Build.meta(path).articles then return path end
    if not progress(("%s\n\nPreparo il giornale…"):format(paper.name)) then return nil, "annullato" end

    local tmp = path .. ".tmp"
    local epub = Archiver.Writer:new{}
    if not epub:open(tmp, "epub") then return nil, "impossibile scrivere il file" end

    local title = ("%s – %s"):format(paper.name, Build.dateLabel(now))
    local manifest, spine, nav, toc = {}, {}, {}, {}
    local function chapter(id, file, label, html)
        epub:addFileFromMemory("OEBPS/" .. file, html, now)
        table.insert(manifest, ('<item id="%s" href="%s" media-type="application/xhtml+xml"/>'):format(id, file))
        table.insert(spine, ('<itemref idref="%s"/>'):format(id))
        local n = #nav + 1
        table.insert(nav, ('<navPoint id="n%d" playOrder="%d"><navLabel><text>%s</text></navLabel><content src="%s"/></navPoint>'):format(n, n, X.escape(label), file))
    end

    epub:setZipCompression("store")
    epub:addFileFromMemory("mimetype", "application/epub+zip", now)
    epub:setZipCompression("deflate")
    epub:addFileFromMemory("META-INF/container.xml", [[<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>]], now)
    epub:addFileFromMemory("OEBPS/style.css", CSS, now)

    for i, a in ipairs(articles) do
        table.insert(toc, ('<p><a href="a%d.xhtml">%s</a></p>'):format(i, X.escape(a.title)))
    end
    chapter("front", "index.xhtml", "Prima pagina", page(title,
        ('<h1 class="mast">%s</h1><p class="date">%s</p><div class="toc">%s</div>'):format(
            X.escape(paper.name), Build.dateLabel(now), table.concat(toc, "\n"))))
    for i, a in ipairs(articles) do
        chapter("a" .. i, ("a%d.xhtml"):format(i), a.title, page(a.title,
            ('<h1>%s</h1>\n%s\n<p class="back"><a href="index.xhtml">↩ Torna ai titoli</a></p>'):format(X.escape(a.title), a.body)))
    end

    epub:setZipCompression("store") -- photos are already compressed
    for i, img in ipairs(images) do
        epub:addFileFromMemory("OEBPS/" .. img.name, img.data, now)
        table.insert(manifest, ('<item id="img%d" href="%s" media-type="%s"/>'):format(i, img.name, img.mime))
    end
    epub:setZipCompression("deflate")

    epub:addFileFromMemory("OEBPS/content.opf", ([[<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/" unique-identifier="bookid" version="2.0">
<metadata><dc:title>%s</dc:title><dc:creator>%s</dc:creator><dc:language>it</dc:language><dc:identifier id="bookid">konewspaper-%s-%s</dc:identifier></metadata>
<manifest><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/><item id="css" href="style.css" media-type="text/css"/>
%s
</manifest>
<spine toc="ncx">%s</spine>
</package>]]):format(X.escape(title), X.escape(paper.name), paper.id, os.date("%Y%m%d%H%M", now), table.concat(manifest, "\n"), table.concat(spine)), now)
    epub:addFileFromMemory("OEBPS/toc.ncx", ([[<?xml version="1.0" encoding="utf-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
<head><meta name="dtb:uid" content="konewspaper-%s"/></head><docTitle><text>%s</text></docTitle>
<navMap>%s</navMap>
</ncx>]]):format(paper.id, X.escape(title), table.concat(nav, "\n")), now)
    epub:close()

    os.remove(path) -- replacing today's edition
    os.rename(tmp, path)

    -- front page for the newsstand: top headline + first jpg/png photo (webp may not decode in ImageWidget)
    local base = path:gsub("%.epub$", "")
    local meta = { headline = articles[1].title }
    for _, img in ipairs(images) do
        if img.ext == "jpg" or img.ext == "png" then
            meta.cover = base .. ".cover." .. img.ext
            local f = io.open(meta.cover, "wb")
            if f then f:write(img.data); f:close() else meta.cover = nil end
            break
        end
    end
    local f = io.open(base .. ".meta.lua", "w")
    if f then
        -- articles: title and brief of each, in reading order (chapter i + 1 of the EPUB), for the Sommario
        local list = {}
        for _, a in ipairs(articles) do
            table.insert(list, ("{ title = %q, brief = %q }"):format(a.title, X.brief(a.body)))
        end
        f:write(("return { headline = %q, cover = %s, articles = { %s } }\n"):format(meta.headline,
            meta.cover and ("%q"):format(meta.cover) or "nil", table.concat(list, ", ")))
        f:close()
    end
    Build.prune(paper)
    return path
end

--- Keep the last few editions (with cover, meta and KOReader's .sdr), so the device never fills up
function Build.prune(paper)
    local dir = Build.root .. "/" .. paper.id
    local dates, seen = {}, {}
    for f in lfs.dir(dir) do
        local d = f:match("^(%d%d%d%d%-%d%d%-%d%d)%.")
        if d and not seen[d] then seen[d] = true; table.insert(dates, d) end
    end
    table.sort(dates, function(a, b) return a > b end)
    local old = {}
    for i = KEEP_DAYS + 1, #dates do old[dates[i]] = true end
    for f in lfs.dir(dir) do
        local d = f:match("^(%d%d%d%d%-%d%d%-%d%d)%.")
        if d and old[d] then
            local path = dir .. "/" .. f
            if lfs.attributes(path, "mode") == "directory" then ffiutil.purgeDir(path) else os.remove(path) end
        end
    end
end

return Build
