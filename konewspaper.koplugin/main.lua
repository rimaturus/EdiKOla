--[[--
KoNewspaper: a newsstand ("edicola") home screen on top of KOReader's reader.

- Every time KOReader shows its file browser, the newsstand covers it.
- Four shelves (Italia, Mondo, Buone notizie, Scienza e tecnologia): each newspaper shows today's front
  page (headline + photo). Swipe or the arrows for more papers.
- Tap a newspaper: today's edition opens (downloaded first if needed).
- "Sommario" (also shown after "Aggiorna"): every article of the day by newspaper, or with the briefs on,
  by topic with each article's opening sentences (knp_topics.lua). Tap one to read it.
- In a newspaper, "Titoli" goes back to its front page (the list of headlines).
- "I miei libri": the user's own EPUB/PDF files, big list, one tap to open.
- "Giornali": tick which newspapers from the catalog (giornali.lua) are on the shelves.
- While reading, a big "Edicola" button in the top-left corner goes back, "A− A+" top-right change
  the text size, the clock sits top-centre, and a tap on a photo opens it full screen to zoom.
- Lock screen: lockscreen/edikola.png.
  Long-press a word for the dictionaries (Italian, English, both translations).
- Admin escape hatch: long-press the "Edicola" title to reach KOReader's file browser.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Build = require("knp_build")
local giornali = require("giornali")
local topics = require("knp_topics")
local Screen = Device.screen

-- Wi-Fi: this router often refuses the address it has just offered (DHCP offer, then NAK, about 3 tries in 4
-- in crash.log), and KOReader's obtain-ip.sh gives up after 30 s: about 1 connection in 5 failed.
-- Up to 3 rounds of DHCP before giving up.
if Device:isKobo() and NetworkMgr.obtainIP and NetworkMgr.ifHasAnAddress and not NetworkMgr.konewspaper_retry then
    NetworkMgr.konewspaper_retry = true
    local obtainIP = NetworkMgr.obtainIP
    function NetworkMgr:obtainIP()
        for try = 1, 3 do
            obtainIP(self)
            if self:ifHasAnAddress() then return end
            logger.warn("KoNewspaper: no IP address after DHCP round", try)
        end
    end
end

local BOOK_EXT = { epub = true, pdf = true, mobi = true, azw3 = true, fb2 = true, txt = true, rtf = true, djvu = true, cbz = true, docx = true }
local SECTIONS = {
    { id = "italia", name = "Italia" },
    { id = "mondo", name = "Mondo" },
    { id = "buone", name = "Buone notizie" },
    { id = "scienza", name = "Scienza e tecnologia" }, -- long labels wrap to 2 lines on their own
}
local PER_PAGE = 4 -- front pages per shelf page (2 x 2)
local BOOKS_DIR = (Device.home_dir or "/mnt/onboard") .. "/Libri" -- where phone transfers land

-- One-time defaults: big text, room for the home button, no Wi-Fi questions, e-ink tuned refresh
local DEFAULTS = {
    copt_font_size = 26,             -- KOReader default is 22
    copt_t_page_margin = 50,         -- keeps the first line clear of the "Edicola" button
    wifi_enable_action = "turn_on",  -- connect without asking
    wifi_disable_action = "turn_off",
    full_refresh_count = 6,          -- flash every 6 pages: clears ghosting, still quick
    refresh_on_pages_with_images = true, -- clean flash on photo pages
    start_with = "filemanager",
}

-- Lock screen: the EdiKOla newsstand picture shipped in lockscreen/
local function lockscreenDefaults(plugin_path)
    return {
        screensaver_type = "random_image",
        screensaver_dir = (plugin_path:sub(1, 1) == "/" and "" or lfs.currentdir() .. "/") .. plugin_path .. "/lockscreen",
        screensaver_show_message = false,
        screensaver_img_background = "white",
        screensaver_stretch_images = false,
    }
end

-- KOReader plugins EdiKOla never shows: each one costs start-up time and RAM. Applies from the next start.
local UNUSED_PLUGINS = { "coverbrowser", "statistics", "vocabbuilder", "wallabag", "opds", "calibre", "kosync",
    "terminal", "texteditor", "perceptionexpander", "newsdownloader", "japanese", "exporter", "profiles",
    "hotkeys", "systemstat", "hello", "httpinspector" }
local function slimDefaults()
    local off = G_reader_settings:readSetting("plugins_disabled") or {}
    for _, name in ipairs(UNUSED_PLUGINS) do off[name] = true end
    return { plugins_disabled = off }
end

-- The Buone notizie and Scienza shelves came later: put their default papers on an existing selection once
local function newShelvesDefaults()
    local sel = G_reader_settings:readSetting("konewspaper_selected")
    if not sel then return {} end -- no selection yet: catalog defaults already apply
    for _, p in ipairs(giornali) do
        if p.default and (p.section == "buone" or p.section == "scienza") then sel[p.id] = true end
    end
    return { konewspaper_selected = sel }
end

-- Status bar while reading: only "18/40 (1/5)", centred (page of the paper, page of the article).
-- The one item kept is chapter_progress; addReaderControls gives it that text. Tapping it changes nothing.
local FOOTER_ITEMS = { "page_progress", "pages_left_book", "time", "pages_left", "battery", "percentage",
    "book_time_to_read", "chapter_time_to_read", "frontlight", "mem_usage", "wifi_status", "book_title",
    "book_chapter", "bookmark_count", "frontlight_warmth", "custom_text", "book_author",
    "page_turning_inverted", "dynamic_filler", "additional_content" }
local function footerDefaults()
    local f = G_reader_settings:readSetting("footer")
        or require("util").tableDeepCopy(require("apps/reader/modules/readerfooter").default_settings)
    for _, k in ipairs(FOOTER_ITEMS) do f[k] = false end
    f.chapter_progress, f.all_at_once, f.lock_tap, f.disable_progress_bar, f.align = true, true, true, true, "center"
    f.text_font_size, f.text_font_bold, f.container_height = 18, true, 20 -- as big as the clock
    return { footer = f, reader_footer_mode = 1 }
end

local function applyDefaults(plugin_path)
    local sets = { -- functions, so a set is only computed (and settings touched) the one time it applies
        konewspaper_defaults_v1 = function() return DEFAULTS end,
        konewspaper_defaults_v2 = lockscreenDefaults,
        konewspaper_defaults_v3 = slimDefaults,
        konewspaper_defaults_v4 = newShelvesDefaults,
        konewspaper_defaults_v5 = footerDefaults,
    }
    for flag, set in pairs(sets) do
        if not G_reader_settings:isTrue(flag) then
            for k, v in pairs(set(plugin_path)) do G_reader_settings:saveSetting(k, v) end
            G_reader_settings:makeTrue(flag)
            G_reader_settings:flush()
        end
    end
end

-- Clock, top of the screen, on the newsstand and while reading. One timer, aligned to the minute.
local clock_refresh -- set by whichever screen is showing: function() that marks the clock dirty
local function clockTick()
    if clock_refresh then clock_refresh() end
    UIManager:scheduleIn(60 - os.date("*t").sec, clockTick)
end
local function startClock()
    UIManager:unschedule(clockTick)
    UIManager:scheduleIn(60 - os.date("*t").sec, clockTick)
end

--- { [id] = true } of the papers on the shelves (catalog defaults until the user picks)
local function selection()
    local sel = G_reader_settings:readSetting("konewspaper_selected")
    if sel then return sel end
    sel = {}
    for _, p in ipairs(giornali) do
        if p.default then sel[p.id] = true end
    end
    return sel
end

local function shelf(section)
    local sel, out = selection(), {}
    for _, p in ipairs(giornali) do
        if p.section == section and sel[p.id] then table.insert(out, p) end
    end
    return out
end

local function isToday(file)
    return file and file:find(os.date("%Y-%m-%d"), 1, true) ~= nil
end

local function openFile(file)
    require("apps/reader/readerui"):showReader(file)
end

local function bigButton(text, width, height, callback, selected)
    return Button:new{
        text = text, width = width, height = height, callback = callback,
        text_font_face = "NotoSans-Bold.ttf", text_font_size = 22,
        bordersize = Screen:scaleBySize(selected and 4 or 2),
        radius = Screen:scaleBySize(10),
        background = selected and Blitbuffer.COLOR_GRAY_D or nil,
    }
end

-- A newspaper on the shelf: masthead, date rule, then today's front page (headline + photo)
local FrontPage = InputContainer:extend{
    width = nil, height = nil, paper = nil, callback = nil,
}

function FrontPage:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.ges_events = { TapPaper = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
    local border = Screen:scaleBySize(2)
    local pad = Screen:scaleBySize(8)
    local w = self.width - 2 * (border + pad)
    local h = self.height - 2 * (border + pad)

    local latest = Build.latest(self.paper)
    local meta = latest and Build.meta(latest) or {}
    local status
    if isToday(latest) then
        status = Build.dateLabel(os.time())
    elseif latest then
        status = "Vecchia edizione · tocca per aggiornare"
    else
        status = "Tocca per scaricare"
    end

    local rule = function(t) return LineWidget:new{ dimen = Geom:new{ w = w, h = Screen:scaleBySize(t) } } end
    local page = VerticalGroup:new{
        align = "center",
        TextBoxWidget:new{
            text = self.paper.name, face = Font:getFace("NotoSerif-Bold.ttf", 22),
            width = w, alignment = "center", height = Screen:scaleBySize(34), height_overflow_show_ellipsis = true,
        },
        rule(2),
        VerticalSpan:new{ width = Screen:scaleBySize(2) },
        TextWidget:new{ text = status, face = Font:getFace("NotoSerif-Italic.ttf", 13), max_width = w },
        VerticalSpan:new{ width = Screen:scaleBySize(2) },
        rule(1),
        VerticalSpan:new{ width = Screen:scaleBySize(6) },
    }
    local left = h - page:getSize().h
    if meta.headline and left > Screen:scaleBySize(40) then
        local headline = TextBoxWidget:new{
            text = meta.headline, face = Font:getFace("NotoSerif-Bold.ttf", 15), width = w, alignment = "left",
            height = math.min(left, Screen:scaleBySize(40)), height_overflow_show_ellipsis = true, -- 2 lines: leave room for the photo
        }
        table.insert(page, headline)
        left = left - headline:getSize().h - Screen:scaleBySize(6)
        if meta.cover and left > Screen:scaleBySize(36) and lfs.attributes(meta.cover, "mode") == "file" then
            local ok, img = pcall(function()
                local i = ImageWidget:new{ file = meta.cover, width = w, height = left, scale_factor = 0, file_do_cache = false }
                i:getSize() -- decode now, so a bad image is caught here and not at paint time
                return i
            end)
            if ok then
                table.insert(page, VerticalSpan:new{ width = Screen:scaleBySize(6) })
                table.insert(page, img)
            else
                logger.warn("KoNewspaper: cover", meta.cover, img)
            end
        end
    elseif not meta.headline then
        table.insert(page, CenterContainer:new{
            dimen = Geom:new{ w = w, h = left },
            TextBoxWidget:new{
                text = latest and "Pronto da leggere\n\ntocca per aprire" or "Tocca qui per\nscaricare l'edizione\ndi oggi",
                face = Font:getFace("cfont", 18),
                width = w, alignment = "center", fgcolor = Blitbuffer.COLOR_DARK_GRAY,
            },
        })
    end

    page:resetLayout() -- getSize() above cached offsets before the headline/photo were added

    self[1] = FrameContainer:new{
        width = self.width, height = self.height,
        bordersize = border, padding = pad, radius = 0,
        background = Blitbuffer.COLOR_WHITE,
        page,
    }
end

function FrontPage:onTapPaper()
    if self.callback then self.callback() end
    return true
end

local Edicola = InputContainer:extend{
    covers_fullscreen = true,
    section = "italia",
    page = 1,
}

function Edicola:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    local m = Screen:scaleBySize(12)
    local gap = Screen:scaleBySize(10)
    local cw = sw - 2 * m

    -- Masthead, flanked by the two things an elder reaches for: light and "get a file from my phone"
    local side_w = Screen:scaleBySize(110)
    local side_h = Screen:scaleBySize(52)
    self.clock = TextWidget:new{ text = os.date("%H:%M"), face = Font:getFace("NotoSans-Bold.ttf", 18) }
    local date_line = HorizontalGroup:new{
        TextWidget:new{ text = Build.dateLabel(os.time()) .. "  ·  ", face = Font:getFace("NotoSerif-Italic.ttf", 18) },
        self.clock,
    }
    local masthead = VerticalGroup:new{
        align = "center",
        TextWidget:new{ text = "Edicola", face = Font:getFace("NotoSerif-Bold.ttf", 38) },
        date_line,
    }
    local masthead_box = CenterContainer:new{ dimen = Geom:new{ w = cw - 2 * side_w, h = masthead:getSize().h }, masthead }
    local day = os.date("%Y-%m-%d")
    self.refreshClock = function()
        if os.date("%Y-%m-%d") ~= day then return self:redraw() end -- midnight: new date, new editions
        self.clock:setText(os.date("%H:%M"))
        date_line:resetLayout()
        masthead:resetLayout()
        UIManager:setDirty(self, "ui", masthead_box.dimen)
    end
    local header = VerticalGroup:new{
        align = "center",
        HorizontalGroup:new{
            align = "center",
            bigButton("Luce", side_w, side_h, function() Device:showLightDialog() end),
            masthead_box,
            bigButton("Telefono", side_w, side_h, function() self:receiveFromPhone() end),
        },
        VerticalSpan:new{ width = Screen:scaleBySize(4) },
        LineWidget:new{ dimen = Geom:new{ w = cw, h = Screen:scaleBySize(3) } },
        VerticalSpan:new{ width = Screen:scaleBySize(2) },
        LineWidget:new{ dimen = Geom:new{ w = cw, h = Screen:scaleBySize(1) } },
    }
    local header_h = header:getSize().h
    self.ges_events = {
        HoldTitle = { GestureRange:new{ ges = "hold", range = Geom:new{ x = 0, y = 0, w = sw, h = header_h + m } } },
    }

    -- Section tabs
    local tab_w = math.floor((cw - (#SECTIONS - 1) * gap) / #SECTIONS)
    local tabs = HorizontalGroup:new{}
    for i, s in ipairs(SECTIONS) do
        if i > 1 then table.insert(tabs, HorizontalSpan:new{ width = gap }) end
        table.insert(tabs, bigButton(s.name, tab_w, Screen:scaleBySize(52), function()
            if s.id == self.section then return end
            self.section, self.page = s.id, 1
            self:redraw("ui")
        end, s.id == self.section))
    end

    -- Bottom bar
    local quarter = math.floor((cw - 3 * gap) / 4)
    local btn_h = Screen:scaleBySize(56)
    local bottom = HorizontalGroup:new{
        bigButton("I miei libri", quarter, btn_h, function() self:showBooks() end),
        HorizontalSpan:new{ width = gap },
        bigButton("Aggiorna", quarter, btn_h, function()
            local all = {}
            for _, s in ipairs(SECTIONS) do
                for _, p in ipairs(shelf(s.id)) do table.insert(all, p) end
            end
            self:fetch(all, function() self:showNews() end)
        end),
        HorizontalSpan:new{ width = gap },
        bigButton("Sommario", quarter, btn_h, function() self:showNews() end),
        HorizontalSpan:new{ width = gap },
        bigButton("Giornali", quarter, btn_h, function() self:showCatalog() end),
    }

    -- Pages of the shelf: arrows only when there is more than one page; a swipe turns them too
    local papers = shelf(self.section)
    local pages = math.max(1, math.ceil(#papers / PER_PAGE))
    self.page = math.min(self.page, pages)
    self.turn = function(d)
        local p = self.page + d
        if p >= 1 and p <= pages then self.page = p; self:redraw("ui") end
    end
    local pager
    if pages > 1 then
        local arrow_w, pager_h = Screen:scaleBySize(130), Screen:scaleBySize(44)
        local arrow = function(text, d, enabled)
            return Button:new{ text = text, width = arrow_w, height = pager_h, enabled = enabled,
                bordersize = Screen:scaleBySize(2), radius = Screen:scaleBySize(10), text_font_size = 24,
                callback = function() self.turn(d) end }
        end
        pager = HorizontalGroup:new{
            align = "center",
            arrow("◀", -1, self.page > 1),
            CenterContainer:new{
                dimen = Geom:new{ w = cw - 2 * arrow_w, h = pager_h },
                TextWidget:new{ text = ("Pagina %d di %d"):format(self.page, pages), face = Font:getFace("cfont", 20) },
            },
            arrow("▶", 1, self.page < pages),
        }
    end
    self.ges_events.Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } }

    -- Shelves: 2 rows of 2 front pages, each row standing on a shelf board. Sizes are measured
    -- (a Button is taller than its height, by its border), so the bottom bar never runs off the screen.
    local board_h = Screen:scaleBySize(8)
    local shelves_h = sh - 2 * m - header_h - tabs:getSize().h - bottom:getSize().h - 3 * gap
        - (pager and pager:getSize().h + gap or 0)
    local row_h = math.floor(shelves_h / 2) - board_h - gap
    local tile_w = math.floor((cw - 2 * gap) / 2)
    local shelves = VerticalGroup:new{ align = "center" }
    if #papers == 0 then
        table.insert(shelves, CenterContainer:new{
            dimen = Geom:new{ w = cw, h = shelves_h },
            TextBoxWidget:new{
                text = "Nessun giornale su questo scaffale.\nTocca «Giornali» per sceglierli.",
                face = Font:getFace("cfont", 22), width = cw, alignment = "center",
            },
        })
    else
        for r = 1, 2 do
            local row = HorizontalGroup:new{ align = "bottom", HorizontalSpan:new{ width = gap } }
            for c = 1, 2 do
                local paper = papers[(self.page - 1) * PER_PAGE + (r - 1) * 2 + c]
                if c > 1 then table.insert(row, HorizontalSpan:new{ width = gap }) end
                if paper then
                    table.insert(row, FrontPage:new{
                        width = tile_w, height = row_h, paper = paper,
                        callback = function() self:openPaper(paper) end,
                    })
                else
                    table.insert(row, HorizontalSpan:new{ width = tile_w })
                end
            end
            table.insert(shelves, row)
            table.insert(shelves, LineWidget:new{ dimen = Geom:new{ w = cw, h = board_h }, background = Blitbuffer.COLOR_DARK_GRAY })
            table.insert(shelves, VerticalSpan:new{ width = gap })
        end
    end

    local body = VerticalGroup:new{
        align = "center",
        header,
        VerticalSpan:new{ width = gap },
        tabs,
        VerticalSpan:new{ width = gap },
        CenterContainer:new{ dimen = Geom:new{ w = cw, h = shelves_h }, shelves },
    }
    if pager then
        table.insert(body, pager)
        table.insert(body, VerticalSpan:new{ width = gap })
    end
    table.insert(body, VerticalSpan:new{ width = gap })
    table.insert(body, bottom)
    self[1] = FrameContainer:new{
        width = sw, height = sh, bordersize = 0, padding = m,
        background = Blitbuffer.COLOR_WHITE,
        body,
    }
end

function Edicola:onSwipe(_, ges)
    if ges.direction == "west" then self.turn(1) elseif ges.direction == "east" then self.turn(-1) end
    return true
end

function Edicola.show()
    if Edicola.instance then return end
    Edicola.instance = Edicola:new{}
    UIManager:show(Edicola.instance, "full")
    clock_refresh = function() if Edicola.instance then Edicola.instance.refreshClock() end end
    startClock()
end

function Edicola:onCloseWidget()
    if Edicola.instance == self then
        Edicola.instance = nil
        clock_refresh = nil
    end
end

function Edicola:onResume() -- the clock is stale after sleep
    self.refreshClock()
end

function Edicola:onHoldTitle()
    UIManager:close(self) -- reveals KOReader's file browser (for setup only)
    return true
end

function Edicola:redraw(mode) -- "ui" for tabs and shelf pages: no black flash; "full" after downloads
    self:init()
    UIManager:setDirty(self, mode or "full")
end

function Edicola:open(file)
    UIManager:close(self)
    openFile(file)
end

function Edicola:openPaper(paper)
    local latest = Build.latest(paper)
    if isToday(latest) then return self:open(latest) end
    self:fetch({ paper }, function()
        local f = Build.latest(paper) -- today's, or yesterday's if the download failed
        if f then self:open(f) end
    end)
end

-- Downloads the given papers (Wi-Fi turns on by itself, and off again after). Several at once, each in
-- its own process: a download mostly waits on the network, and KOReader's sockets block.
-- ponytail: fixed worker count; lower it if updates run out of memory (256 MB), raise it on a fast connection
local PARALLEL = 4
function Edicola:fetch(list, after)
    if #list == 0 then return end
    NetworkMgr:runWhenOnline(function()
        Trapper:wrap(function()
            local failed, running, nrunning, nextp, ndone = {}, {}, 0, 1, 0
            local shown
            while nextp <= #list or nrunning > 0 do
                while nextp <= #list and nrunning < PARALLEL do
                    local paper = list[nextp]
                    nextp = nextp + 1
                    local pid, fd = ffiutil.runInSubProcess(function(_, out)
                        local ok, path, err = pcall(Build.paper, paper)
                        if not ok then
                            logger.err("KoNewspaper:", paper.name, path)
                            err = "errore imprevisto"
                        end
                        ffiutil.writeToFD(out, (ok and path) and "" or tostring(err), true)
                    end, true)
                    if pid then
                        running[pid] = { paper = paper, fd = fd }
                        nrunning = nrunning + 1
                    else
                        table.insert(failed, paper.name .. ": " .. tostring(fd))
                    end
                end
                for pid, job in pairs(running) do
                    if ffiutil.isSubProcessDone(pid) then
                        local err = ffiutil.readAllFromFD(job.fd)
                        if err ~= "" then table.insert(failed, job.paper.name .. ": " .. err) end
                        running[pid] = nil
                        nrunning = nrunning - 1
                        ndone = ndone + 1
                    end
                end
                if nextp > #list and nrunning == 0 then break end

                local names = {}
                for _, job in pairs(running) do table.insert(names, job.paper.name) end
                table.sort(names)
                local text = #list == 1 and ("%s\n\nScarico il giornale…"):format(list[1].name)
                    or ("Giornali pronti: %d di %d\n\nIn corso:\n%s"):format(ndone, #list, table.concat(names, "\n"))
                text = text .. "\n\n(tocca lo schermo per annullare)"
                -- same text: refresh only the message box (no e-ink flash); new text: redraw it
                if not Trapper:info(text, text == shown) then
                    for pid, job in pairs(running) do
                        ffiutil.terminateSubProcess(pid)
                        ffiutil.readAllFromFD(job.fd) -- returns once the process is gone
                        ffiutil.isSubProcessDone(pid, true)
                    end
                    break
                end
                shown = text
                ffiutil.usleep(500000) -- Trapper:info already gave the screen 0.1 s for taps
            end
            Trapper:clear()
            NetworkMgr:turnOffWifi()
            if Edicola.instance then Edicola.instance:redraw() end
            if #failed > 0 then
                UIManager:show(InfoMessage:new{
                    text = "Non sono riuscito a scaricare:\n\n" .. table.concat(failed, "\n"),
                    face = Font:getFace("cfont", 22),
                })
            end
            if after then after() end
        end)
    end)
end

-- Phone → Kobo over Wi-Fi with the LocalSend app (receiver: localsend.koplugin, MIT, kaikozlov)
function Edicola:receiveFromPhone()
    local fm = require("apps/filemanager/filemanager").instance
    local ls = fm and fm.LocalSend
    if not ls then
        UIManager:show(InfoMessage:new{ text = "Manca il plugin LocalSend." })
        return
    end
    if not G_reader_settings:has("LocalSend_save_dir") then
        lfs.mkdir(BOOKS_DIR)
        G_reader_settings:saveSetting("LocalSend_save_dir", BOOKS_DIR)
        ls.save_dir = BOOKS_DIR
    end
    if (G_reader_settings:readSetting("LocalSend_device_name") or "") == "" then
        G_reader_settings:saveSetting("LocalSend_device_name", "EdiKOla")
        ls.device_name = "EdiKOla"
    end
    NetworkMgr:runWhenConnected(function()
        if not ls:isRunning() then ls:start(true) end
        UIManager:show(InfoMessage:new{
            text = "Pronto a ricevere!\n\nSul telefono: apri il file, tocca «Condividi», scegli «LocalSend», poi «EdiKOla».\n\nI file arrivano in «I miei libri».\n\nQuando hai finito, tocca qui.",
            face = Font:getFace("cfont", 22),
            dismiss_callback = function()
                ls:stop()
                NetworkMgr:turnOffWifi()
            end,
        })
    end)
end

-- Catalog: tap a newspaper to put it on (✓) or take it off the shelves
function Edicola:showCatalog()
    local sel = {}
    for id in pairs(selection()) do sel[id] = true end
    local menu
    local function items()
        local t = {}
        for _, s in ipairs(SECTIONS) do
            table.insert(t, { text = "— " .. s.name:upper() .. " —", select_enabled = false, bold = true })
            for _, p in ipairs(giornali) do
                if p.section == s.id then
                    table.insert(t, {
                        text = (sel[p.id] and "✓  " or "      ") .. p.name,
                        callback = function()
                            sel[p.id] = not sel[p.id] or nil
                            local idx
                            for i, it in ipairs(menu.item_table) do
                                if it.paper_id == p.id then idx = i end
                            end
                            menu:switchItemTable(nil, items(), idx)
                        end,
                        paper_id = p.id,
                    })
                end
            end
        end
        return t
    end
    menu = Menu:new{
        title = "Scegli i giornali",
        item_table = items(),
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        is_enable_shortcut = false, -- no Q/W/E key hints (they appear on devices with keyboards)
        items_per_page = 10,
        items_font_size = 24,
        close_callback = function()
            G_reader_settings:saveSetting("konewspaper_selected", sel)
            G_reader_settings:flush()
            if Edicola.instance then Edicola.instance:redraw() end
        end,
    }
    UIManager:show(menu, "full")
end

-- Opening an edition at one article: the reader jumps there once the book is ready (KoNewspaper:onReaderReady)
local pending_article -- { file =, chapter = }
function Edicola:openArticle(file, i)
    pending_article = { file = file, chapter = i + 1 } -- chapter 1 is the front page
    self:open(file)
end

-- Sommario, in Italian (English papers are translated when they are downloaded):
--   1. one entry per topic: how many articles, and the main headlines (lead stories of different papers first)
--   2. tap a topic: each of its articles with the newspaper and its opening sentences
--   3. tap an article: it opens. ✕ goes back one level. The last entry lists every title by newspaper.
function Edicola:showNews()
    local entries = {}
    for _, s in ipairs(SECTIONS) do
        for _, p in ipairs(shelf(s.id)) do
            local f = Build.latest(p)
            if isToday(f) then
                for i, a in ipairs(Build.meta(f).articles or {}) do
                    table.insert(entries, { paper = p, file = f, i = i, n = #entries + 1, title = a.title, brief = a.brief })
                end
            end
        end
    end

    local shown = {} -- the Sommario's screens: all close when an article opens
    local function show(title, items)
        local menu = Menu:new{
            title = title, item_table = items,
            width = Screen:getWidth(), height = Screen:getHeight(),
            covers_fullscreen = true, is_borderless = true, is_popout = false, is_enable_shortcut = false,
            items_per_page = 8, items_font_size = 19, items_max_lines = 4,
        }
        table.insert(shown, menu)
        UIManager:show(menu, "full")
    end
    local function read(e)
        for _, m in ipairs(shown) do UIManager:close(m) end
        self:openArticle(e.file, e.i)
    end
    -- two rows per entry, as the list turns newlines into spaces: a bold title, then the text
    local function entry(items, title, text, callback)
        table.insert(items, { text = title, bold = true, callback = callback })
        table.insert(items, { text = text, callback = callback })
    end

    local by, items = {}, {}
    for _, e in ipairs(entries) do
        local t = topics.of(e.title, e.brief)
        by[t] = by[t] or {}
        table.insert(by[t], e)
    end
    for _, t in ipairs(topics.names) do
        local list = by[t]
        if list then
            table.sort(list, function(a, b) if a.i ~= b.i then return a.i < b.i end return a.n < b.n end)
            local heads, papers = {}, {}
            for _, e in ipairs(list) do
                if #heads < 3 and not papers[e.paper] then papers[e.paper] = true; table.insert(heads, e.title) end
            end
            entry(items, ("%s · %d %s"):format(t, #list, #list == 1 and "notizia" or "notizie"),
                table.concat(heads, " · "), function()
                    local rows = {}
                    for _, e in ipairs(list) do
                        entry(rows, e.title, ("%s · %s"):format(e.paper.name, e.brief), function() read(e) end)
                    end
                    show(t, rows)
                end)
        end
    end
    if #entries == 0 then
        table.insert(items, { text = "Nessun articolo di oggi. Tocca «Aggiorna» per scaricare i giornali.", select_enabled = false })
    else
        entry(items, "Tutti i titoli", "Giornale per giornale", function()
            local rows, last = {}, nil
            for _, e in ipairs(entries) do
                if e.paper ~= last then
                    table.insert(rows, { text = "— " .. e.paper.name:upper() .. " —", select_enabled = false, bold = true })
                    last = e.paper
                end
                table.insert(rows, { text = e.title, callback = function() read(e) end })
            end
            show("Tutti i titoli", rows)
        end)
    end
    show("Le notizie di oggi", items)
end

local function findBooks(dir, out, depth)
    local ok, iter, state = pcall(lfs.dir, dir)
    if not ok then return end
    for f in iter, state do
        if f:sub(1, 1) ~= "." then
            local path = dir .. "/" .. f
            local mode = lfs.attributes(path, "mode")
            if mode == "directory" and path ~= Build.root and depth < 5 then
                findBooks(path, out, depth + 1)
            elseif mode == "file" and BOOK_EXT[(f:match("%.(%w+)$") or ""):lower()] then
                table.insert(out, { path = path, name = f:gsub("%.%w+$", ""):gsub("[_]+", " ") })
            end
        end
    end
end

function Edicola:showBooks()
    local books = {}
    findBooks(Device.home_dir or "/mnt/onboard", books, 0)
    table.sort(books, function(a, b) return a.name:lower() < b.name:lower() end)

    local menu
    local items = {}
    for _, b in ipairs(books) do
        table.insert(items, {
            text = b.name,
            callback = function()
                UIManager:close(menu)
                self:open(b.path)
            end,
        })
    end
    if #items == 0 then
        items[1] = { text = "Nessun libro. Collega il Kobo al computer e copia i file EPUB o PDF.", select_enabled = false }
    end
    menu = Menu:new{
        title = "I miei libri",
        item_table = items,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        is_enable_shortcut = false, -- no Q/W/E key hints (they appear on devices with keyboards)
        items_per_page = 7,
        items_font_size = 26,
        items_max_lines = 2,
    }
    UIManager:show(menu, "full")
end

-- The plugin: newsstand over the file browser, home button in the reader
local KoNewspaper = WidgetContainer:extend{
    name = "konewspaper",
    is_doc_only = false,
}
KoNewspaper.Edicola = Edicola -- for tools/screenshots

function KoNewspaper:init()
    applyDefaults(self.path)
    if self.ui.document then
        self:addReaderControls()
    else
        UIManager:nextTick(Edicola.show)
    end
end

local TAP_ZONES = { -- KOReader's own taps that our buttons take precedence over
    "readermenu_tap", "readermenu_ext_tap", "tap_forward", "tap_backward", "tap_link",
    "readerhighlight_tap", "readerfooter_tap", "readerconfigmenu_tap", "readerconfigmenu_ext_tap",
    "tap_top_left_corner", "tap_top_right_corner", "konewspaper_photo",
}

local function label(text)
    return FrameContainer:new{
        bordersize = Screen:scaleBySize(2),
        radius = Screen:scaleBySize(8),
        padding = Screen:scaleBySize(6),
        padding_left = Screen:scaleBySize(12),
        padding_right = Screen:scaleBySize(12),
        background = Blitbuffer.COLOR_WHITE,
        TextWidget:new{ text = text, face = Font:getFace("NotoSans-Bold.ttf", 18) },
    }
end

-- While reading: "◀ Edicola" (and "Titoli" in a newspaper) top-left, clock top-centre, "A− A+" top-right
-- (EPUB etc.), tap or spread on a photo opens it full screen.
function KoNewspaper:addReaderControls()
    local sw = Screen:getWidth()
    local margin = Screen:scaleBySize(6)
    local left = { { label("◀ Edicola"), function() self.ui:onHome() end } }
    if (self.ui.document.file or ""):find(Build.root, 1, true) == 1 then -- a newspaper: back to its headlines
        table.insert(left, { label("Titoli"), function() self.ui:handleEvent(Event:new("GotoPage", 1)) end })
    end
    local right = {}
    if self.ui.rolling then -- reflowable: text size; PDFs keep KOReader's zoom
        table.insert(right, { label("A+"), function() self.ui:handleEvent(Event:new("ChangeSize", 2)) end })
        table.insert(right, { label("A−"), function() self.ui:handleEvent(Event:new("ChangeSize", -2)) end })
    end
    local buttons, x = {}, margin
    for _, b in ipairs(left) do -- left to right from the left edge
        b.x, x = x, x + b[1]:getSize().w + 2 * margin
        table.insert(buttons, b)
    end
    x = sw - margin
    for _, b in ipairs(right) do -- right to left from the right edge
        b.x = x - b[1]:getSize().w
        x = b.x - 2 * margin
        table.insert(buttons, b)
    end
    local zones = {}
    for i, b in ipairs(buttons) do
        local size = b[1]:getSize()
        local zx = math.max(0, b.x - margin) -- tap zone a bit larger than the drawn button
        table.insert(zones, {
            id = "konewspaper_btn" .. i,
            ges = "tap",
            screen_zone = {
                ratio_x = zx / sw, ratio_y = 0,
                ratio_w = math.min(sw - zx, size.w + 2 * margin) / sw,
                ratio_h = (size.h + 3 * margin) / Screen:getHeight(),
            },
            overrides = TAP_ZONES,
            handler = function() b[2](); return true end,
        })
    end

    local clock_face = Font:getFace("NotoSans-Bold.ttf", 18)
    local clock_rect = Geom:new{ x = math.floor(sw / 2) - Screen:scaleBySize(60), y = 0,
                                 w = Screen:scaleBySize(120), h = Screen:scaleBySize(40) }
    self.ui.view:registerViewModule("konewspaper_controls", {
        paintTo = function(_, bb, px, py)
            for _, b in ipairs(buttons) do b[1]:paintTo(bb, px + b.x, py + margin) end
            local clock = TextWidget:new{ text = os.date("%H:%M"), face = clock_face }
            clock:paintTo(bb, px + math.floor((sw - clock:getSize().w) / 2), py + margin + Screen:scaleBySize(6))
            clock:free()
        end,
    })
    clock_refresh = function() UIManager:setDirty(self.ui, "ui", clock_rect) end
    startClock()

    -- Bottom centre: "18/40 (1/5)" = page 18 of 40 in the paper, page 1 of 5 of this article.
    -- Books without a table of contents show just "18/40".
    local footer = self.ui.view.footer
    local chapterProgress = footer.getChapterProgress
    function footer:getChapterProgress(get_percentage, pageno)
        if get_percentage then return chapterProgress(self, get_percentage, pageno) end
        local text = ("%d/%d"):format(self.pageno, self.pages)
        local done, count = self.ui.toc:getChapterPagesDone(self.pageno), self.ui.toc:getChapterPageCount(self.pageno)
        if done and count then text = text .. (" (%d/%d)"):format(done + 1, count) end
        return text
    end

    -- Photos: tap or spread opens the image viewer (pinch/spread zoom, drag pans, buttons to
    -- scale/close). Anywhere else, taps turn pages and pinch/spread keep KOReader's text size/zoom.
    local function openPhoto(ges)
        local pos = self.ui.view:screenToPageTransform(ges.pos)
        local image = pos and self.ui.document:getImageFromPosition(pos, true, true)
        if not image then return false end
        UIManager:show(require("ui/widget/imageviewer"):new{
            image = image, with_title_bar = false, fullscreen = true, buttons_visible = true,
        })
        return true
    end
    local whole = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 }
    table.insert(zones, { id = "konewspaper_photo", ges = "tap", screen_zone = whole, handler = openPhoto,
        overrides = { "tap_forward", "tap_backward", "tap_link", "readerhighlight_tap", "readermenu_tap", "readermenu_ext_tap" } })
    table.insert(zones, { id = "konewspaper_photo_zoom", ges = "spread", screen_zone = whole, handler = openPhoto,
        overrides = { "spread_gesture" } })
    self.ui:registerTouchZones(zones)
end

function KoNewspaper:onReaderReady() -- opened from the Sommario: go to that article
    local go = pending_article
    pending_article = nil
    if not (go and self.ui.document and self.ui.document.file == go.file) then return end
    local toc = self.ui.toc
    toc:fillToc()
    local entry = toc.toc and toc.toc[go.chapter]
    if entry and entry.page then self.ui:handleEvent(Event:new("GotoPage", entry.page)) end
end

function KoNewspaper:onCloseDocument()
    clock_refresh = nil
end

function KoNewspaper:onResume()
    if self.ui.document and clock_refresh then clock_refresh() end
end

return KoNewspaper
