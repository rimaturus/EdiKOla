--[[--
Pure-Lua news helpers (no KOReader deps, so they run under any Lua 5.1+):
RSS/Atom parsing and article extraction down to plain paragraphs, subheads and images.

Extraction is a small readability: every <p> gives its text length to its ancestors (slowly
decaying, 6 levels up); the best-scored element is the article body. Only text and <img> survive,
links become plain text, so there's nothing to tap that leaves the page.
]]

local M = {}

local VOID = { area=1, base=1, br=1, col=1, embed=1, hr=1, img=1, input=1, link=1, meta=1, param=1, source=1, track=1, wbr=1 }
-- Whole subtrees we never want
local DROP = { script=1, style=1, noscript=1, svg=1, iframe=1, form=1, button=1, nav=1, footer=1, header=1, aside=1, template=1, select=1, dialog=1, video=1, audio=1, object=1, canvas=1,
               figcaption=1, time=1 }
local BLOCK = { p=1, h2=1, h3=1, h4=1, li=1, blockquote=1 }
local JUNK = { "comment", "share", "social", "related", "promo", "newsletter", "subscri", "sidebar", "cookie", "consent",
               "banner", "recirc", "outbrain", "taboola", "advert", "sponsor", "mostread", "most%-read", "paywall", "byline",
               "breadcrumb", "caption%-credit", "read%-more", "readmore", "tags", "toolbar", "^ad$", "^ad[%-_]", "[%-_]ad$", "[%-_]ad[%-_]" }

local ENT = { nbsp=" ", amp="&", lt="<", gt=">", quot='"', apos="'", rsquo="’", lsquo="‘", rdquo="”", ldquo="“",
              ndash="–", mdash="—", hellip="…", laquo="«", raquo="»", euro="€", copy="©", deg="°", middot="·", bull="•",
              agrave="à", aacute="á", egrave="è", eacute="é", igrave="ì", iacute="í", ograve="ò", oacute="ó", ugrave="ù", uacute="ú",
              Agrave="À", Egrave="È", Eacute="É", Igrave="Ì", Ograve="Ò", Ugrave="Ù", ccedil="ç", ntilde="ñ", uuml="ü", ouml="ö", auml="ä", szlig="ß",
              times="×", shy="", zwj="", zwnj="", thinsp=" ", ensp=" ", emsp=" ", prime="′", Prime="″", trade="™", reg="®" }

local function utf8char(c)
    if c < 0x80 then return string.char(c) end
    if c < 0x800 then return string.char(0xC0 + math.floor(c / 0x40), 0x80 + c % 0x40) end
    if c < 0x10000 then return string.char(0xE0 + math.floor(c / 0x1000), 0x80 + math.floor(c / 0x40) % 0x40, 0x80 + c % 0x40) end
    return string.char(0xF0 + math.floor(c / 0x40000), 0x80 + math.floor(c / 0x1000) % 0x40, 0x80 + math.floor(c / 0x40) % 0x40, 0x80 + c % 0x40)
end

local function validUTF8(s)
    local i, n = 1, #s
    while i <= n do
        local c = s:byte(i)
        local len = c < 0x80 and 1 or (c >= 0xC2 and c < 0xE0) and 2 or (c >= 0xE0 and c < 0xF0) and 3 or (c >= 0xF0 and c < 0xF5) and 4 or nil
        if not len then return false end
        for j = i + 1, i + len - 1 do
            local b = s:byte(j)
            if not b or b < 0x80 or b > 0xBF then return false end
        end
        i = i + len
    end
    return true
end

-- Windows-1252 extras in 0x80-0x9F (Latin-1 has control codes there)
local CP1252 = { [0x80]=0x20AC, [0x82]=0x201A, [0x83]=0x0192, [0x84]=0x201E, [0x85]=0x2026, [0x86]=0x2020, [0x87]=0x2021,
                 [0x88]=0x02C6, [0x89]=0x2030, [0x8A]=0x0160, [0x8B]=0x2039, [0x8C]=0x0152, [0x8E]=0x017D, [0x91]=0x2018,
                 [0x92]=0x2019, [0x93]=0x201C, [0x94]=0x201D, [0x95]=0x2022, [0x96]=0x2013, [0x97]=0x2014, [0x98]=0x02DC,
                 [0x99]=0x2122, [0x9A]=0x0161, [0x9B]=0x203A, [0x9C]=0x0153, [0x9E]=0x017E, [0x9F]=0x0178 }

--- Pages that aren't valid UTF-8 (Corriere serves Latin-1) are read as Windows-1252
function M.toUTF8(s)
    if validUTF8(s) then return s end
    return (s:gsub("[\128-\255]", function(ch)
        local b = ch:byte()
        return utf8char(CP1252[b] or b)
    end))
end

function M.decode(s)
    s = s:gsub("&#[xX](%x+);", function(h) local n = tonumber(h, 16); return n and n < 0x110000 and utf8char(n) or "" end)
    s = s:gsub("&#(%d+);", function(d) local n = tonumber(d); return n and n < 0x110000 and utf8char(n) or "" end)
    return (s:gsub("&(%a+);", function(n) return ENT[n] end))
end

function M.escape(s)
    return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

local function cdata(s)
    return (s:gsub("<!%[CDATA%[(.-)%]%]>", "%1"))
end

-- Tags out, entities decoded, whitespace collapsed
function M.text(html)
    local s = M.decode(html:gsub("<br[^>]*>", " "):gsub("<[^>]*>", ""))
    return (s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

local function attr(attrs, name) -- case-insensitive name (BBC writes srcSet)
    local lower = attrs:lower()
    for _, q in ipairs({ '"', "'" }) do
        local _, e = lower:find("[%s/]" .. name:gsub("%-", "%%-") .. "%s*=%s*" .. q)
        if e then return attrs:match("^([^" .. q .. "]*)", e + 1) end
    end
end

local function isJunk(attrs)
    if attrs:find('aria%-hidden%s*=%s*"true"') or attrs:find("[%s/]hidden[%s/=>]") or attrs:find("[%s/]hidden$") then
        return true
    end
    local names = ((attr(attrs, "class") or "") .. " " .. (attr(attrs, "id") or "")):lower()
    for word in names:gmatch("%S+") do
        for _, j in ipairs(JUNK) do
            if word:find(j) then return true end
        end
    end
    return false
end

-- Pick the srcset candidate closest to a 758px-wide e-ink screen (Kobo Nia)
local TARGET_W = 800
local function bestSrc(attrs)
    local srcset = attr(attrs, "srcset") or attr(attrs, "data-srcset")
    if srcset then
        local best, best_d
        for url, w in srcset:gmatch("(%S+)%s+(%d+)w") do
            local d = math.abs(tonumber(w) - TARGET_W)
            if not best_d or d < best_d then best, best_d = url, d end
        end
        if best then return M.decode(best) end
    end
    local src = attr(attrs, "data-src") or attr(attrs, "data-lazy-src") or attr(attrs, "data-original") or attr(attrs, "src")
    return src and M.decode(src)
end

local function usableImage(attrs, src)
    if not src or src == "" or src:find("^data:") or src:lower():find("%.svg") then return false end
    local w, h = tonumber(attr(attrs, "width") or ""), tonumber(attr(attrs, "height") or "")
    if (w and w < 120) or (h and h < 120) then return false end -- icons, logos, tracking pixels
    if src:lower():find("logo") or src:lower():find("icon") or src:lower():find("pixel") then return false end
    return true
end

--- Returns the article as a list of blocks: {kind="p"|"h", text=...} or {kind="img", src=...}
function M.article(html)
    html = M.toUTF8(html):gsub("<!%-%-.-%-%->", "")
    for _, t in ipairs({ "script", "style", "noscript", "svg", "template" }) do
        html = html:gsub("<" .. t .. "[%s>].-</" .. t .. "%s*>", "")
    end

    local parent, score, junk = { [0] = -1 }, { [0] = 0 }, {}
    local stack = { { name = "#root", id = 0 } }
    local items = {}
    local skip_name, skip_depth -- inside a dropped subtree
    local open_block            -- { name, start, id }
    local nid, pos = 0, 1

    local function finishBlock(stop)
        local name = open_block.name
        local txt = M.text(html:sub(open_block.start, stop - 1))
        if #txt > 1 then
            table.insert(items, { kind = name:find("^h%d") and "h" or "p", text = txt, node = open_block.id })
            if name == "p" and #txt >= 25 and not junk[open_block.id] then
                -- slow decay up 6 levels: BBC & co. wrap each paragraph in its own divs, so the
                -- body may sit 5 levels up; a wrapper only wins if it adds real extra text
                local n = parent[open_block.id]
                for k = 1, 6 do
                    if not n or n < 0 then break end
                    if not junk[n] then score[n] = score[n] + #txt * (1 - (k - 1) * 0.12) end
                    n = parent[n]
                end
            end
        end
        open_block = nil
    end

    while true do
        local s, e, slash, name, attrs = html:find("<(/?)([%a][%w%-]*)([^>]*)>", pos)
        if not s then break end
        pos = e + 1
        name = name:lower()
        local closing = slash == "/"
        local selfclose = attrs:sub(-1) == "/"

        if not closing and (name == "p" or name == "li") and stack[#stack].name == name then
            -- implicitly closed <p>/<li> (sloppy HTML): close it before opening the next one
            if open_block and open_block.id == stack[#stack].id then finishBlock(s) end
            stack[#stack] = nil
        end

        if skip_name then
            if name == skip_name and not VOID[name] and not selfclose then
                skip_depth = skip_depth + (closing and -1 or 1)
                if skip_depth == 0 then skip_name = nil end
            end
        elseif closing then
            if open_block and name == open_block.name then finishBlock(s) end
            for i = #stack, 2, -1 do -- pop up to the matching tag, tolerating sloppy HTML
                if stack[i].name == name then
                    for j = #stack, i, -1 do stack[j] = nil end
                    break
                end
            end
        elseif name == "img" then
            local src = bestSrc(attrs)
            if usableImage(attrs, src) then
                table.insert(items, { kind = "img", src = src, node = stack[#stack].id })
            end
        elseif not VOID[name] and not selfclose then
            if DROP[name] then
                skip_name, skip_depth = name, 1
            else
                nid = nid + 1
                parent[nid] = stack[#stack].id
                score[nid] = 0
                junk[nid] = isJunk(attrs)
                stack[#stack + 1] = { name = name, id = nid }
                if BLOCK[name] and not open_block then
                    open_block = { name = name, start = e + 1, id = nid }
                end
            end
        end
    end

    local best, best_score = 0, 0
    for id = 1, nid do
        if score[id] > best_score then best, best_score = id, score[id] end
    end

    -- Keep blocks inside the body, unless something between them and the body is junk
    -- (junk above the body doesn't count: BBC wraps everything in "...WithSidebarWrapper")
    local out, seen = {}, {}
    for _, it in ipairs(items) do
        local n, bad = it.node, false
        while n and n >= 0 and n ~= best do
            bad = bad or junk[n]
            n = parent[n]
        end
        if n == best and not bad and not (it.kind == "p" and #it.text < 20) then -- "Published", "Watch:"
            local key = it.src or it.text
            if not seen[key] then
                seen[key] = true
                table.insert(out, it)
            end
        end
    end
    return out
end

--- Characters of body text, to tell a real article from a teaser
function M.length(blocks)
    local n = 0
    for _, b in ipairs(blocks) do
        if b.kind == "p" then n = n + #b.text end
    end
    return n
end

local function tag(block, name)
    local v = block:match("<" .. name .. "[^>]*>(.-)</" .. name .. ">")
    return v and cdata(v)
end

--- RSS 2.0 / Atom → { {title=, link=, content=}, ... }
function M.feed(xml)
    xml = M.toUTF8(xml)
    local out = {}
    for _, pat in ipairs({ "<item[%s>].-</item>", "<entry[%s>].-</entry>" }) do
        for block in xml:gmatch(pat) do
            local link = tag(block, "link")
            if not link or link:match("^%s*$") then
                link = block:match('<link[^>]-rel="alternate"[^>]-href="([^"]+)"') or block:match('<link[^>]-href="([^"]+)"')
            end
            local title = tag(block, "title")
            if link and title then
                table.insert(out, {
                    title = M.text(cdata(M.decode(title))),
                    link = M.decode(link:match("^%s*(.-)%s*$")),
                    content = tag(block, "content:encoded") or tag(block, "content") or tag(block, "description") or tag(block, "summary") or "",
                })
            end
        end
    end
    return out
end

--- Feed descriptions are usually entity-escaped HTML
function M.feedHTML(content)
    if content:find("&lt;") then content = M.decode(content) end
    return content
end

return M
