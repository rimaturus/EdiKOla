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
- Phone APK (android/build.sh): "Ascolta" on a front page reads the edition aloud, offline (knp_ascolta.lua),
  and "Notte" in place of "Luce" switches KOReader's night mode (knp_theme keeps the colors' hues).
- Lock screen: lockscreen/edikola.png.
  Long-press a word for the dictionaries (Italian, English, both translations).
- Admin escape hatch: long-press the "Edicola" title to reach KOReader's file browser.
]]

local Blitbuffer = require("ffi/blitbuffer")
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
local Ascolta = require("knp_ascolta")
local Build = require("knp_build")
local Cards = require("knp_cards")
local giornali = require("giornali")
local theme = require("knp_theme")
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
local ANDROID = Device:isAndroid() -- Bigme B6 Pro Color: KOReader as an Android app, Android owns Wi-Fi/4G
local PHONE = ANDROID and not Device:hasEinkScreen() -- an Android phone: night mode instead of the light
-- Pen ink on what is being read (knp_penna): the "Penna" button where there's a pen (Android e-readers,
-- or once a pen has touched a Kobo)
local function penOn() return ANDROID or require("knp_penna").penSeen() end

-- Network: on Kobo KOReader turns Wi-Fi on and off itself; on Android it can only open the settings
-- (it would do that after every update), and the Bigme may be online over 4G with Wi-Fi off.
local function whenOnline(fn)
    if not ANDROID then return NetworkMgr:runWhenOnline(fn) end
    if NetworkMgr:isConnected() then return fn() end
    UIManager:show(InfoMessage:new{
        text = "Nessuna connessione a internet.\n\nAccendi il Wi-Fi o i dati mobili (scorri giù dall'alto dello schermo), poi riprova.",
        face = Font:getFace("cfont", 22),
    })
end
local function wifiOff()
    if not ANDROID then NetworkMgr:turnOffWifi() end
end
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

-- KOReader plugins EdiKOla never shows: each one costs start-up time and RAM. Applies from the next start.
local UNUSED_PLUGINS = { "coverbrowser", "statistics", "vocabbuilder", "wallabag", "opds", "calibre", "kosync",
    "terminal", "texteditor", "perceptionexpander", "newsdownloader", "japanese", "exporter", "profiles",
    "hotkeys", "systemstat", "hello", "httpinspector" }
local function androidDefaults()
    local off = G_reader_settings:readSetting("plugins_disabled") or {}
    for _, name in ipairs(UNUSED_PLUGINS) do off[name] = true end
    return { plugins_disabled = off }
end

local function applyDefaults(plugin_path)
    local sets = { -- functions, so a set is only computed (and settings touched) the one time it applies
        konewspaper_defaults_v1 = function() return DEFAULTS end,
        konewspaper_defaults_v2 = lockscreenDefaults,
        konewspaper_defaults_v4 = newShelvesDefaults, -- v3 is on dev (custom OS plan)
        konewspaper_defaults_v5 = footerDefaults,
        konewspaper_defaults_v6 = ANDROID and androidDefaults or nil, -- v3 is on dev (custom OS plan)
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

local WHITE = Blitbuffer.COLOR_WHITE

-- Today's articles of every paper on the shelves, for the puzzles: { { title =, paper = } }
local function todaysArticles()
    local out = {}
    for _, sec in ipairs(SECTIONS) do
        for _, p in ipairs(shelf(sec.id)) do
            local f = Build.latest(p)
            if isToday(f) then
                for _, a in ipairs(Build.meta(f).articles or {}) do table.insert(out, { title = a.title, paper = p.name }) end
            end
        end
    end
    return out
end

-- How many papers of a section's catalog are not on its shelf yet
local function notOnShelf(section)
    local sel, n = selection(), 0
    for _, p in ipairs(giornali) do
        if p.section == section and not sel[p.id] then n = n + 1 end
    end
    return n
end

-- A newspaper on the shelf: masthead, date rule, then today's front page (headline + photo)
local FrontPage = InputContainer:extend{
    width = nil, height = nil, paper = nil, callback = nil, listen = nil,
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
    -- masthead: the paper's name in white on its shelf's color (black on grayscale screens)
    local band = theme.color(self.paper.section)
    local page = VerticalGroup:new{
        align = "center",
        FrameContainer:new{
            bordersize = 0, padding = Screen:scaleBySize(2), radius = Screen:scaleBySize(4), background = band,
            TextBoxWidget:new{
                text = self.paper.name, face = Font:getFace("NotoSerif-Bold.ttf", 21),
                width = w - 2 * Screen:scaleBySize(2), alignment = "center", height = Screen:scaleBySize(32),
                height_overflow_show_ellipsis = true, fgcolor = Blitbuffer.COLOR_WHITE, bgcolor = band,
            },
        },
        VerticalSpan:new{ width = Screen:scaleBySize(3) },
        VerticalSpan:new{ width = Screen:scaleBySize(2) },
        TextWidget:new{ text = status, face = Font:getFace("NotoSerif-Italic.ttf", 13), max_width = w },
        VerticalSpan:new{ width = Screen:scaleBySize(2) },
        rule(1),
        VerticalSpan:new{ width = Screen:scaleBySize(6) },
    }
    local left = h - page:getSize().h
    -- "Ascolta" at the bottom, where there's a voice (phone APK) and an edition to read
    local listen
    if self.listen and latest and require("knp_voce").ready() then
        listen = theme.Pill:new{ text = Ascolta.playing(latest) and "In ascolto" or "▶ Ascolta", width = w,
            height = Screen:scaleBySize(40), size = 16, fill = theme.color(self.paper.section .. "_tint"),
            fg = theme.color(self.paper.section), callback = function() self.listen(latest) end }
        left = left - listen:getSize().h - Screen:scaleBySize(6)
    end
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
    if listen then
        table.insert(page, VerticalSpan:new{ width = h - page:getSize().h - listen:getSize().h })
        table.insert(page, listen)
        page:resetLayout()
    end

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

-- The last place on a shelf: "+ Altri giornali", the section's catalog. It also shows that a shelf scrolls.
local AddTile = InputContainer:extend{ width = nil, height = nil, section = nil, count = 0, callback = nil }

function AddTile:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.ges_events = { TapAdd = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
    local w = self.width - 2 * Screen:scaleBySize(12)
    local color, tint = theme.color(self.section), theme.color(self.section .. "_tint")
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, bordersize = 0, padding = 0, radius = Screen:scaleBySize(10),
        background = tint,
        CenterContainer:new{ dimen = Geom:new{ w = self.width, h = self.height }, VerticalGroup:new{
            align = "center",
            theme.Text:new{ text = "+", face = Font:getFace("NotoSans-Bold.ttf", 54), fgcolor = color },
            theme.Text:new{ text = "Altri giornali", face = Font:getFace("NotoSerif-Bold.ttf", 22), fgcolor = color, max_width = w },
            VerticalSpan:new{ width = Screen:scaleBySize(6) },
            TextBoxWidget:new{ text = ("%d da scegliere\ntocca per vederli"):format(self.count),
                face = Font:getFace("NotoSerif-Italic.ttf", 16), width = w, alignment = "center",
                fgcolor = Blitbuffer.COLOR_GRAY_3, bgcolor = tint },
        } },
    }
end

function AddTile:onTapAdd()
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
    local ink, ink_tint = theme.color("ink"), theme.color("ink_tint")

    -- Masthead: a band of ink with the title, the date and the clock; light on the left, puzzles on the right
    local side_w, side_h = Screen:scaleBySize(104), Screen:scaleBySize(48)
    local band_pad = Screen:scaleBySize(8)
    self.clock = TextWidget:new{ text = os.date("%H:%M"), face = Font:getFace("NotoSans-Bold.ttf", 18), fgcolor = WHITE }
    local date_line = HorizontalGroup:new{
        TextWidget:new{ text = Build.dateLabel(os.time()) .. "  ·  ", face = Font:getFace("NotoSerif-Italic.ttf", 18), fgcolor = WHITE },
        self.clock,
    }
    local masthead = VerticalGroup:new{
        align = "center",
        TextWidget:new{ text = "Edicola", face = Font:getFace("NotoSerif-Bold.ttf", 38), fgcolor = WHITE },
        date_line,
    }
    local masthead_box = CenterContainer:new{
        dimen = Geom:new{ w = cw - 2 * side_w - 2 * band_pad, h = masthead:getSize().h }, masthead }
    local day = os.date("%Y-%m-%d")
    self.refreshClock = function()
        if os.date("%Y-%m-%d") ~= day then return self:redraw() end -- midnight: new date, new editions
        self.clock:setText(os.date("%H:%M"))
        date_line:resetLayout()
        masthead:resetLayout()
        UIManager:setDirty(self, "ui", masthead_box.dimen)
    end
    local header = FrameContainer:new{
        width = cw, bordersize = 0, padding = band_pad, radius = Screen:scaleBySize(12), background = ink,
        HorizontalGroup:new{
            align = "center",
            theme.Pill:new{ text = PHONE and (Screen.night_mode and "Giorno" or "Notte") or "Luce",
                width = side_w, height = side_h, size = 20, fill = WHITE, fg = ink, callback = function()
                    if not PHONE then return Device:showLightDialog() end
                    UIManager:broadcastEvent(Event:new("ToggleNightMode")) -- KOReader's own, kept in its settings
                    self:redraw()
                end },
            masthead_box,
            theme.Pill:new{ text = "Giochi", width = side_w, height = side_h, size = 20, fill = theme.color("giochi"),
                fg = WHITE, callback = function() self:showGiochi() end },
        },
    }
    local header_h = header:getSize().h
    self.ges_events = {
        HoldTitle = { GestureRange:new{ ges = "hold", range = Geom:new{ x = 0, y = 0, w = sw, h = header_h + m } } },
    }

    -- Section tabs: the open one filled with its color, the others in its light tint
    local tab_w = math.floor((cw - (#SECTIONS - 1) * gap) / #SECTIONS)
    local tabs = HorizontalGroup:new{}
    for i, s in ipairs(SECTIONS) do
        local open = s.id == self.section
        if i > 1 then table.insert(tabs, HorizontalSpan:new{ width = gap }) end
        table.insert(tabs, theme.Pill:new{
            text = s.name, width = tab_w, height = Screen:scaleBySize(50), size = 19,
            fill = theme.color(open and s.id or s.id .. "_tint"), fg = open and WHITE or theme.color(s.id),
            callback = function()
                if open then return end
                self.section, self.page = s.id, 1
                self:redraw("ui")
            end,
        })
    end

    -- Bottom bar: "Aggiorna" stands out in ink, the rest in its tint
    local actions = {
        { "I miei libri", function() self:showBooks() end },
        { "Aggiorna", function()
            local all = {}
            for _, s in ipairs(SECTIONS) do
                for _, p in ipairs(shelf(s.id)) do table.insert(all, p) end
            end
            self:fetch(all, function() self:showNews() end)
        end, true },
        { "Sommario", function() self:showNews() end },
        { "Giornali", function() self:showCatalog() end },
    }
    if not ANDROID then table.insert(actions, { "Telefono", function() self:receiveFromPhone() end }) end
    local btn_w = math.floor((cw - (#actions - 1) * gap) / #actions)
    local bottom = HorizontalGroup:new{}
    for i, a in ipairs(actions) do
        if i > 1 then table.insert(bottom, HorizontalSpan:new{ width = gap }) end
        table.insert(bottom, theme.Pill:new{ text = a[1], width = btn_w, height = Screen:scaleBySize(56), size = #actions > 4 and 16 or 20,
            fill = a[3] and ink or ink_tint, fg = a[3] and WHITE or ink, callback = a[2] })
    end

    -- Pages of the shelf: its papers, then the "+ Altri giornali" place when the catalog has more.
    -- Arrows and dots whenever there is more than one page; a swipe turns them too.
    local papers = shelf(self.section)
    local more = notOnShelf(self.section)
    local slots = #papers + (more > 0 and 1 or 0)
    -- Rows of 2 front pages: as many as fit with front pages about as tall as wide (2 on e-readers, 3 on a phone).
    -- The room is the screen less everything else, the pager included (measured below, estimated here).
    local board_h = Screen:scaleBySize(8)
    local tile_w = math.floor((cw - 2 * gap) / 2)
    local room = sh - 2 * m - header_h - Screen:scaleBySize(50) - bottom:getSize().h - 4 * gap - Screen:scaleBySize(44)
    local per_page = 2 * math.max(2, math.floor(room / (0.9 * tile_w + board_h + 2 * gap)))
    local pages = math.max(1, math.ceil(slots / per_page))
    self.page = math.min(self.page, pages)
    self.turn = function(d)
        local p = self.page + d
        if p >= 1 and p <= pages then self.page = p; self:redraw("ui") end
    end
    local color, tint = theme.color(self.section), theme.color(self.section .. "_tint")
    local pager
    if pages > 1 then
        local arrow_w, pager_h = Screen:scaleBySize(120), Screen:scaleBySize(44)
        local arrow = function(text, d, enabled)
            return theme.Pill:new{ text = text, width = arrow_w, height = pager_h, size = 26, enabled = enabled,
                fill = enabled and tint or WHITE, fg = color, callback = function() self.turn(d) end }
        end
        local dot = Screen:scaleBySize(14)
        local dots = HorizontalGroup:new{ align = "center" }
        for p = 1, pages do
            if p > 1 then table.insert(dots, HorizontalSpan:new{ width = Screen:scaleBySize(8) }) end
            table.insert(dots, theme.Box:new{ width = dot, height = dot, radius = math.floor(dot / 2),
                color = p == self.page and color or tint })
        end
        pager = HorizontalGroup:new{
            align = "center",
            arrow("<", -1, self.page > 1),
            CenterContainer:new{ dimen = Geom:new{ w = cw - 2 * arrow_w, h = pager_h }, HorizontalGroup:new{
                align = "center", dots, HorizontalSpan:new{ width = Screen:scaleBySize(14) },
                theme.Text:new{ text = ("pagina %d di %d"):format(self.page, pages), face = Font:getFace("cfont", 18), fgcolor = color },
            } },
            arrow(">", 1, self.page < pages),
        }
    end
    self.ges_events.Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } }

    -- Shelves: rows of 2 front pages, each row standing on a shelf board in the section's color.
    -- Sizes are measured, so the bottom bar never runs off the screen.
    local shelves_h = sh - 2 * m - header_h - tabs:getSize().h - bottom:getSize().h - 3 * gap
        - (pager and pager:getSize().h + gap or 0)
    local row_h = math.floor(shelves_h / (per_page / 2)) - board_h - gap
    local shelves = VerticalGroup:new{ align = "center" }
    if slots == 0 then
        table.insert(shelves, CenterContainer:new{
            dimen = Geom:new{ w = cw, h = shelves_h },
            TextBoxWidget:new{
                text = "Nessun giornale su questo scaffale.\nTocca «Giornali» per sceglierli.",
                face = Font:getFace("cfont", 22), width = cw, alignment = "center",
            },
        })
    else
        local on_page = math.min(per_page, slots - (self.page - 1) * per_page)
        for r = 1, math.ceil(on_page / 2) do -- a half-empty last page shows one shelf, not an empty board
            local row = HorizontalGroup:new{ align = "bottom", HorizontalSpan:new{ width = gap } }
            for c = 1, 2 do
                local n = (self.page - 1) * per_page + (r - 1) * 2 + c
                local paper = papers[n]
                if c > 1 then table.insert(row, HorizontalSpan:new{ width = gap }) end
                if paper then
                    table.insert(row, FrontPage:new{
                        width = tile_w, height = row_h, paper = paper,
                        callback = function() self:openPaper(paper) end,
                        listen = function(epub)
                            local y, mo, d = epub:match("(%d+)%-(%d+)%-(%d+)%.epub$")
                            Ascolta.listen(epub, paper.name, Build.dateLabel(os.time{ year = y, month = mo, day = d, hour = 12 }),
                                function() if Edicola.instance then Edicola.instance:redraw("ui") end end)
                        end,
                    })
                elseif n == #papers + 1 and more > 0 then
                    table.insert(row, AddTile:new{ width = tile_w, height = row_h, section = self.section, count = more,
                        callback = function() self:showCatalog(self.section) end })
                else
                    table.insert(row, HorizontalSpan:new{ width = tile_w })
                end
            end
            table.insert(shelves, row)
            table.insert(shelves, theme.Box:new{ width = cw, height = board_h, color = color })
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
local PARALLEL = ANDROID and 8 or 4 -- the Bigme has 8 GB and 8 cores
function Edicola:fetch(list, after)
    if #list == 0 then return end
    whenOnline(function()
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
            wifiOff()
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
                wifiOff()
            end,
        })
    end)
end

-- Catalog: tap a newspaper to put it on (✓) or take it off the shelves. With a section: only its papers.
function Edicola:showCatalog(section)
    local sel = {}
    for id in pairs(selection()) do sel[id] = true end
    local menu
    local function items()
        local t = {}
        for _, s in ipairs(SECTIONS) do
            if not section then
                table.insert(t, { text = "— " .. s.name:upper() .. " —", select_enabled = false, bold = true })
            end
            for _, p in ipairs(giornali) do
                if p.section == s.id and (not section or section == s.id) then
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
    local name
    for _, s in ipairs(SECTIONS) do if s.id == section then name = s.name end end
    menu = Menu:new{
        title = name and ("Giornali: " .. name) or "Scegli i giornali",
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
        table.insert(shown, Cards.show{ title = title, items = items })
    end
    local function read(e)
        for _, m in ipairs(shown) do UIManager:close(m) end
        self:openArticle(e.file, e.i)
    end
    -- a card: colored stripe (the topic, or the paper's shelf), bold title, text
    local function entry(items, title, text, callback, color)
        table.insert(items, { title = title, text = text, callback = callback, color = color })
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
                        entry(rows, e.title, ("%s · %s"):format(e.paper.name, e.brief), function() read(e) end, t)
                    end
                    show(t, rows)
                end, t)
        end
    end
    if #entries == 0 then
        entry(items, "Nessun articolo di oggi", "Tocca «Aggiorna» nell'Edicola per scaricare i giornali.")
    else
        entry(items, "Tutti i titoli", "Giornale per giornale", function()
            local rows, last = {}, nil
            for _, e in ipairs(entries) do
                if e.paper ~= last then
                    table.insert(rows, { header = e.paper.name, color = e.paper.section })
                    last = e.paper
                end
                table.insert(rows, { title = e.title, callback = function() read(e) end, color = e.paper.section })
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

-- Enigmistica: crossword from today's headlines, crucipuzzle, sudoku (knp_giochi)
function Edicola:showGiochi()
    return require("knp_giochi").show(todaysArticles)
end

function Edicola:showBooks()
    local books = {}
    findBooks(Device.home_dir or "/mnt/onboard", books, 0)
    table.sort(books, function(a, b) return a.name:lower() < b.name:lower() end)

    local list
    local items = {}
    for _, b in ipairs(books) do
        table.insert(items, {
            title = b.name, text = (b.path:match("%.(%w+)$") or ""):upper(), title_lines = 2,
            callback = function()
                UIManager:close(list)
                self:open(b.path)
            end,
        })
    end
    if #items == 0 then
        items[1] = { title = "Nessun libro", text = ("Copia i file EPUB o PDF nella cartella «Libri»%s."):format(
            ANDROID and " (dal computer via USB, o dal telefono con l'app LocalSend)" or " dal computer") }
    end
    list = Cards.show{ title = "I miei libri", items = items }
end

-- The plugin: newsstand over the file browser, home button in the reader
local KoNewspaper = WidgetContainer:extend{
    name = "konewspaper",
    is_doc_only = false,
}
KoNewspaper.Edicola = Edicola -- for tools/screenshots

function KoNewspaper:init()
    applyDefaults(self.path)
    require("knp_android").setup(Device) -- pen, pressure, fast pen refresh (Android only, once)
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

local function label(text, fill, fg)
    return FrameContainer:new{
        bordersize = fill and 0 or Screen:scaleBySize(2),
        radius = Screen:scaleBySize(10),
        padding = Screen:scaleBySize(6) + (fill and Screen:scaleBySize(2) or 0),
        padding_left = Screen:scaleBySize(14),
        padding_right = Screen:scaleBySize(14),
        background = fill or Blitbuffer.COLOR_WHITE,
        TextWidget:new{ text = text, face = Font:getFace("NotoSans-Bold.ttf", 18), fgcolor = fg },
    }
end

-- The paper after this one on its shelf that has an edition to open (wrapping round), or nil
local function nextPaper(file)
    local id = file:match("/([^/]+)/[^/]+$")
    local here
    for _, p in ipairs(giornali) do if p.id == id then here = p end end
    if not here then return end
    local list, at = shelf(here.section), nil
    for i, p in ipairs(list) do if p.id == id then at = i end end
    if not at then return end
    for k = 1, #list - 1 do
        local p = list[(at - 1 + k) % #list + 1]
        local f = Build.latest(p)
        if f then return p, f end
    end
end

-- While reading: "◀ Edicola" (and "Titoli" in a newspaper) top-left, clock top-centre, "A− A+" top-right
-- (EPUB etc.), tap or spread on a photo opens it full screen.
function KoNewspaper:addReaderControls()
    local sw = Screen:getWidth()
    local margin = Screen:scaleBySize(6)
    local ink = theme.color("ink")
    local file = self.ui.document.file or ""
    local left = { { label("Edicola", ink, WHITE), function() self.ui:onHome() end } }
    local right = {}
    if file:find(Build.root, 1, true) == 1 then -- a newspaper: back to its headlines, on to the next paper
        table.insert(left, { label("Titoli", theme.color("ink_tint"), ink), function() self.ui:handleEvent(Event:new("GotoPage", 1)) end })
        local nextp, next_file = nextPaper(file)
        if nextp then
            table.insert(right, { label("Prossimo", theme.color(nextp.section), WHITE), function()
                self.ui:switchDocument(next_file)
            end })
        end
    end
    if self.ui.rolling then -- reflowable: text size; PDFs keep KOReader's zoom
        table.insert(right, { label("A+"), function() self.ui:handleEvent(Event:new("ChangeSize", 2)) end })
        table.insert(right, { label("A−"), function() self.ui:handleEvent(Event:new("ChangeSize", -2)) end })
    end
    local pen_button
    if penOn() then -- the pen writes on the page; this button: ink color, undo, clear the page
        local color = function() return theme.color(G_reader_settings:readSetting("konewspaper_ink") or "nero") end
        pen_button = { label("Penna", color(), WHITE), function()
            self.pen:menu(function() -- the button takes the new ink's color
                pen_button[1] = label("Penna", color(), WHITE)
                UIManager:setDirty(self.ui, "ui")
            end)
        end }
        table.insert(right, pen_button)
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
    local clock_free = true -- no button over the clock's place (with many buttons the clock gives way)
    for _, b in ipairs(buttons) do
        local w = b[1]:getSize().w
        if b.x < clock_rect.x + clock_rect.w and b.x + w > clock_rect.x then clock_free = false end
    end
    self.ui.view:registerViewModule("konewspaper_controls", {
        paintTo = function(_, bb, px, py)
            for _, b in ipairs(buttons) do b[1]:paintTo(bb, px + b.x, py + margin) end
            if not clock_free then return end
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

    -- the pen writes anywhere below the top bar; its buttons stay buttons for the pen too
    local bar_h = 0
    for _, b in ipairs(buttons) do bar_h = math.max(bar_h, b[1]:getSize().h) end
    self.pen = require("knp_penna").attach(self.ui, { top = bar_h + 3 * margin })
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
    if self.pen then self.pen:detach(); self.pen = nil end
end

function KoNewspaper:onResume()
    if self.ui.document and clock_refresh then clock_refresh() end
end

return KoNewspaper
