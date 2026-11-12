--[[--
Ascolta: a newspaper read aloud, like an audiobook (phone APK only, see knp_voce).

- "Ascolta" on a front page starts reading that edition: its name and date, then each article, title first.
  Each article gets the voice of its language (Italian or English).
- A child process makes the audio ahead, a few sentences per WAV file; this process plays them one after the
  other with Android's MediaPlayer, chained (setNextMediaPlayer) so there are no gaps and it goes on with the
  screen off: while it plays, Android keeps the phone awake for the audio and EdiKOla's timer runs.
- The player screen: the article being read, Pausa/Riprendi, previous and next article, the list of articles
  (tap one to jump to it). "Indietro" leaves it playing; "Stop" ends it.
]]
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local theme = require("knp_theme")
local V = require("knp_voce")
local Screen = Device.screen

local DIR = DataStorage:getDataDir() .. "/cache/edikola-voce"
local TICK = 0.5

-- Players. On Android: MediaPlayer through JNI. Elsewhere (KOReader's emulator, for testing): a silent one
-- that takes as long as the WAV lasts.
local P = {}
if Device:isAndroid() then
    local function jni(fn)
        local android = require("android")
        return android.jni:context(android.app.activity.vm, function(j)
            local env = j.env
            local function failed() -- a Java exception must be cleared before any other JNI call
                if env[0].ExceptionCheck(env) == 0 then return false end
                env[0].ExceptionClear(env)
                return true
            end
            local ok, res = pcall(fn, j, env, failed)
            if not ok then logger.warn("EdiKOla: MediaPlayer", res) end
            return ok and res or nil
        end)
    end
    function P.new(path)
        return jni(function(j, env, failed)
            local cls = env[0].FindClass(env, "android/media/MediaPlayer")
            local obj = env[0].NewObject(env, cls, env[0].GetMethodID(env, cls, "<init>", "()V"))
            env[0].DeleteLocalRef(env, cls)
            if failed() then return nil end
            local mp = env[0].NewGlobalRef(env, obj)
            env[0].DeleteLocalRef(env, obj)
            local s = env[0].NewStringUTF(env, path)
            j:callVoidMethod(mp, "setDataSource", "(Ljava/lang/String;)V", s)
            env[0].DeleteLocalRef(env, s)
            local bad = failed()
            if not bad then j:callVoidMethod(mp, "prepare", "()V"); bad = failed() end
            if bad then
                logger.warn("EdiKOla: MediaPlayer can't open", path)
                j:callVoidMethod(mp, "release", "()V")
                env[0].DeleteGlobalRef(env, mp)
                return nil
            end
            return mp
        end)
    end
    local function call(name, sig)
        return function(mp, arg)
            return jni(function(j, _, failed)
                if sig == "()Z" then
                    local r = j:callBooleanMethod(mp, name, sig)
                    return not failed() and r
                elseif sig == "()I" then
                    local r = j:callIntMethod(mp, name, sig)
                    return not failed() and tonumber(r) or 0
                end
                if arg then j:callVoidMethod(mp, name, sig, arg) else j:callVoidMethod(mp, name, sig) end
                failed()
                return true
            end)
        end
    end
    P.start, P.pause, P.playing = call("start", "()V"), call("pause", "()V"), call("isPlaying", "()Z")
    P.chain = call("setNextMediaPlayer", "(Landroid/media/MediaPlayer;)V")
    P.position = call("getCurrentPosition", "()I") -- ms; 0 until it starts
    function P.release(mp)
        jni(function(j, env, failed)
            j:callVoidMethod(mp, "release", "()V")
            failed()
            env[0].DeleteGlobalRef(env, mp)
        end)
    end
else
    local time = require("ui/time")
    local function now() return time.to_s(time.now()) end
    function P.new(path)
        local f = io.open(path, "rb")
        if not f then return nil end
        local size = f:seek("end")
        f:close()
        return { left = (size - 44) / (2 * 22050) }
    end
    function P.start(h) h.t0 = h.t0 or now(); h.started = true end
    function P.position(h) return h.started and 1 or 0 end
    function P.pause(h) h.left, h.t0 = h.left - (now() - h.t0), nil end
    function P.playing(h)
        if h.t0 and now() - h.t0 >= h.left then -- done: the chained one takes over
            h.t0, h.left = nil, 0
            if h.next then P.start(h.next) end
        end
        return h.t0 ~= nil
    end
    function P.chain(h, n) h.next = n end
    function P.release() end
end

local A = {} -- the session: one edition being read
local Screen_ -- the player screen, when shown

local function wav(k) return ("%s/%d.wav"):format(DIR, k) end
local function ready(k) return lfs.attributes(wav(k), "mode") == "file" end

local function kill()
    if not A.pid then return end
    ffiutil.terminateSubProcess(A.pid)
    ffiutil.isSubProcessDone(A.pid, true) -- collects it
    A.pid = nil
end

-- The child process: makes the WAV of every piece from k on, skipping those already there.
local function synthFrom(k)
    kill()
    local chunks = A.chunks
    A.pid = ffiutil.runInSubProcess(function()
        for i = k, #chunks do
            if not ready(i) then
                local tmp = wav(i) .. ".tmp"
                if V.synth(chunks[i], tmp) then os.rename(tmp, wav(i)) else os.remove(tmp) end
            end
        end
    end)
end

local function drop(slot)
    if A[slot] then P.release(A[slot].h); A[slot] = nil end
end

local function changed()
    if Screen_ then Screen_:refresh() end
end

local tick
local function schedule()
    UIManager:unschedule(tick)
    UIManager:scheduleIn(TICK, tick)
end

tick = function()
    if not A.chunks then return end
    if A.pid and ffiutil.isSubProcessDone(A.pid) then A.pid = nil end
    -- The child gone with pieces still to make (Android stops busy child processes of apps in the background):
    -- start it again while the audio still plays, as then the phone is awake.
    if not A.pid and not A.all then
        local k = A.k
        while k <= #A.chunks and ready(k) do k = k + 1 end
        if k <= #A.chunks then synthFrom(k) else A.all = true end
    end
    if A.paused then return end
    local was = A.k
    if not A.cur then
        if A.k > #A.chunks then return A.stop() end
        if ready(A.k) then
            local h = P.new(wav(A.k))
            if h then
                A.cur = { k = A.k, h = h }
                P.start(h)
            else -- a broken file: make it again
                os.remove(wav(A.k))
                A.all = false
            end
        end
    elseif A.nxt and P.playing(A.nxt.h) then -- the chained player took over
        os.remove(wav(A.cur.k))
        drop("cur")
        A.cur, A.nxt = A.nxt, nil
        A.k = A.cur.k
    elseif not P.playing(A.cur.h) then
        if A.nxt and (P.position(A.nxt.h) or 0) == 0 then
            P.start(A.nxt.h) -- the chain didn't start it: do it now
        elseif A.nxt then -- both played already (a very short piece, between two ticks)
            os.remove(wav(A.cur.k)); os.remove(wav(A.nxt.k))
            A.k = A.nxt.k + 1
            drop("cur"); drop("nxt")
        else
            os.remove(wav(A.cur.k))
            drop("cur")
            A.k = A.k + 1
        end
    end
    if A.cur and not A.nxt and A.cur.k < #A.chunks and ready(A.cur.k + 1) then
        local h = P.new(wav(A.cur.k + 1))
        if h then
            A.nxt = { k = A.cur.k + 1, h = h }
            P.chain(A.cur.h, h)
        end
    end
    if A.k ~= was or A.waiting ~= (A.cur == nil) then
        A.waiting = A.cur == nil
        changed()
    end
    schedule()
end

--- The article being read (its number)
function A.article() return A.chunks and (A.chunks[math.min(A.k, #A.chunks)] or {}).article or 1 end

--- Jump to the first piece of article n
function A.go(n)
    if not A.chunks then return end
    n = math.max(1, math.min(n, #A.articles))
    drop("cur"); drop("nxt")
    for k, c in ipairs(A.chunks) do
        if c.article == n then A.k = k; break end
    end
    A.paused, A.all = false, false
    synthFrom(A.k)
    changed()
    schedule()
end

function A.toggle()
    if not A.cur then A.paused = not A.paused
    elseif A.paused then P.start(A.cur.h); A.paused = false
    else P.pause(A.cur.h); A.paused = true end
    changed()
    schedule()
end

function A.stop()
    UIManager:unschedule(tick)
    kill()
    drop("cur"); drop("nxt")
    A.chunks, A.articles, A.epub = nil, nil, nil
    if Screen_ then UIManager:close(Screen_) end
    ffiutil.purgeDir(DIR)
end

--- Reads an edition aloud; just shows the player when it is the one being read
function A.listen(epub, name, date, on_close)
    A.on_close = on_close
    if A.epub ~= epub then
        A.stop()
        local articles = V.read(epub)
        if #articles == 0 then return end
        lfs.mkdir(DataStorage:getDataDir() .. "/cache")
        ffiutil.purgeDir(DIR)
        lfs.mkdir(DIR)
        A.epub, A.name, A.articles = epub, name, articles
        A.chunks = V.chunks(articles, ("%s. %s."):format(name, date))
        A.k, A.paused, A.waiting, A.all = 1, false, true, false
        synthFrom(1)
        schedule()
    end
    UIManager:show(A.Screen:new{}, "full")
end

function A.playing(epub) return A.epub ~= nil and A.epub == epub end

-- The player screen
A.Screen = InputContainer:extend{ covers_fullscreen = true }

function A.Screen:init()
    Screen_ = self
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end
    local m, gap = Screen:scaleBySize(12), Screen:scaleBySize(10)
    local cw = sw - 2 * m
    local ink, tint = theme.color("ink"), theme.color("ink_tint")
    local n = A.article()
    local art = A.articles[n]
    local lang = A.chunks[math.min(A.k, #A.chunks)].lang

    local back_w, bar_h = Screen:scaleBySize(130), Screen:scaleBySize(52)
    local header = VerticalGroup:new{
        align = "left",
        HorizontalGroup:new{
            align = "center",
            Button:new{ text = "◀ Indietro", width = back_w, height = bar_h, text_font_face = "NotoSans-Bold.ttf",
                text_font_size = 19, bordersize = Screen:scaleBySize(2), radius = Screen:scaleBySize(10),
                callback = function() self:onClose() end },
            HorizontalSpan:new{ width = gap },
            TextBoxWidget:new{ text = "Ascolta · " .. A.name, face = Font:getFace("NotoSerif-Bold.ttf", 24),
                width = cw - back_w - gap, height = bar_h, height_overflow_show_ellipsis = true },
        },
        VerticalSpan:new{ width = gap },
        LineWidget:new{ dimen = Geom:new{ w = cw, h = Screen:scaleBySize(2) } },
    }

    local status = A.paused and "In pausa" or A.waiting and "Preparo la voce…"
        or ("Voce %s"):format(lang == "en" and "inglese" or "italiana")
    local now_box = FrameContainer:new{
        width = cw, bordersize = 0, padding = Screen:scaleBySize(14), radius = Screen:scaleBySize(12), background = tint,
        VerticalGroup:new{
            align = "left",
            theme.Text:new{ text = ("ARTICOLO %d DI %d · %s"):format(n, #A.articles, status:upper()),
                face = Font:getFace("NotoSans-Bold.ttf", 15), fgcolor = ink, max_width = cw },
            VerticalSpan:new{ width = Screen:scaleBySize(6) },
            TextBoxWidget:new{ text = art.title, face = Font:getFace("NotoSerif-Bold.ttf", 24),
                width = cw - 2 * Screen:scaleBySize(14), height = Screen:scaleBySize(140), height_overflow_show_ellipsis = true,
                bgcolor = tint },
        },
    }

    local btn_h = Screen:scaleBySize(64)
    local small = math.floor((cw - 3 * gap) / 4)
    local controls = HorizontalGroup:new{
        theme.Pill:new{ text = "◀◀", width = small, height = btn_h, size = 22, fill = tint, fg = ink, enabled = n > 1,
            callback = function() A.go(n - 1) end },
        HorizontalSpan:new{ width = gap },
        theme.Pill:new{ text = A.paused and "Riprendi" or "Pausa", width = 2 * small + gap, height = btn_h, size = 24,
            fill = ink, fg = Blitbuffer.COLOR_WHITE, callback = A.toggle },
        HorizontalSpan:new{ width = gap },
        theme.Pill:new{ text = "▶▶", width = small, height = btn_h, size = 22, fill = tint, fg = ink,
            enabled = n < #A.articles, callback = function() A.go(n + 1) end },
    }
    local stop = theme.Pill:new{ text = "Stop", width = cw, height = Screen:scaleBySize(48), size = 19,
        fill = Blitbuffer.COLOR_WHITE, fg = ink, border = true, callback = A.stop }

    -- the articles: tap one to listen to it; as many as fit, the one being read among them
    local top = VerticalGroup:new{ align = "left", header, VerticalSpan:new{ width = gap }, now_box,
        VerticalSpan:new{ width = gap }, controls, VerticalSpan:new{ width = gap } }
    local avail = sh - 2 * m - top:getSize().h - stop:getSize().h - 2 * gap
    local list = VerticalGroup:new{ align = "left" }
    local rows, used = {}, 0
    for i, a in ipairs(A.articles) do
        rows[i] = theme.Pill:new{ text = ("%d. %s"):format(i, a.title), width = cw, height = Screen:scaleBySize(58),
            size = 16, lines = 2, face = i == n and "NotoSerif-Bold.ttf" or "NotoSerif-Regular.ttf",
            fill = i == n and tint or Blitbuffer.COLOR_WHITE, fg = Blitbuffer.COLOR_BLACK, border = i ~= n,
            callback = function() A.go(i) end }
    end
    local row_h = Screen:scaleBySize(58) + Screen:scaleBySize(6)
    local fit = math.max(1, math.floor(avail / row_h))
    local first = math.max(1, math.min(n - 1, #rows - fit + 1))
    for i = first, math.min(#rows, first + fit - 1) do
        table.insert(list, rows[i])
        table.insert(list, VerticalSpan:new{ width = Screen:scaleBySize(6) })
        used = used + row_h
    end

    self[1] = FrameContainer:new{
        width = sw, height = sh, bordersize = 0, padding = m, background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new{ align = "left", top, list, VerticalSpan:new{ width = math.max(0, avail - used) },
            VerticalSpan:new{ width = gap }, stop },
    }
end

function A.Screen:refresh()
    if not A.chunks then return end
    self:init()
    UIManager:setDirty(self, "ui")
end

function A.Screen:onClose()
    UIManager:close(self)
    return true
end

function A.Screen:onCloseWidget()
    if Screen_ == self then Screen_ = nil end
    if A.on_close then UIManager:nextTick(A.on_close) end
end

return A
