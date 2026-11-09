-- Self-check for knp_ink.lua (pen ink) and knp_android.lua (pen input), from the repo root: lua5.1 tests/notes-test.lua
package.path = "konewspaper.koplugin/?.lua;" .. package.path
local ink = require("knp_ink")

-- ids: one per document, safe as a file name
assert(ink.id("/sdcard/KoNewspaper/rainews/2026-11-05.epub") == "rainews-2026-11-05", ink.id("/sdcard/KoNewspaper/rainews/2026-11-05.epub"))
assert(ink.id("/sdcard/Libri/Un libro (2).epub") == "Libri-Un_libro__2_")

-- round trip: pages keyed by where they start in the text, with quotes and brackets in the key
local key = '/body/DocFragment[3]/body/p[2]/text().17 "x"'
local doc = { pages = {
    [key] = { w = 1072, h = 1448, strokes = { { c = "blu", p = { 10, 20, 30, 40, 50, 60 }, q = { 2, 5, 8 } }, { c = "rosso", p = { 500, 500 } } } },
    p12 = { w = 1072, h = 1448, strokes = { { c = "nero", p = { 1, 2 } } } },
    empty = { w = 1, h = 1, strokes = {} },
} }
local back = ink.decode(ink.encode(doc))
local pg = back.pages[key]
assert(#pg.strokes == 2 and pg.strokes[1].c == "blu" and pg.strokes[1].p[6] == 60 and pg.strokes[1].q[3] == 8)
assert(pg.strokes[2].p[1] == 500 and pg.w == 1072 and back.pages.p12 and back.pages.empty == nil)
assert(ink.encode{ pages = { a = { w = 1, h = 1, strokes = {} } } } == nil) -- no ink at all: no file

-- a planted file gets no globals, and junk is refused
assert(ink.decode("return { pages = {}, x = os }").x == nil)
assert(ink.decode("return { pages = { [1] = { strokes = {} } } }") == nil)
assert(ink.decode("os.exit(1)") == nil)
assert(ink.decode(string.dump(function() return { pages = {} } end)) == nil) -- bytecode is refused
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

-- pressure: width follows it, a stroke without pressure keeps the normal width
assert(ink.level(nil) == nil and ink.level(0) == nil and ink.level(0.5) == 5 and ink.level(2) == 9 and ink.level(0.01) == 1)
assert(ink.width(4, nil) == 4 and ink.width(4, 5) == 5 and ink.width(4, 1) == 2 and ink.width(4, 9) == 7)

-- Android: tool and pressure added to KOReader's touch events (fake input_android, same shape as the real one)
package.preload.logger = function() return { warn = function() end, info = function() end } end
local A = require("knp_android")
assert(A.toolOf(2, 0) == A.PEN and A.toolOf(4, 0) == A.ERASER and A.toolOf(1, 0) == A.FINGER)
assert(A.toolOf(2, 0x20) == A.ERASER and A.toolOf(2, 0x40) == A.ERASER and A.toolOf(2, 0x80) == A.PEN)
assert(A.toolOf(1, 0, true) == A.PEN) -- Bigme's pen reported as a finger, known by its device
local C = { EV_ABS = 3, EV_SYN = 0, SYN_REPORT = 0, ABS_MT_SLOT = 0x2f, ABS_MT_TOOL_TYPE = 0x37, ABS_MT_PRESSURE = 0x3a,
    ABS_MT_POSITION_X = 0x35, ABS_MT_POSITION_Y = 0x36 }
local fake = (function()
    local inputQueue = {}
    local function genInputTimeval(ts) return { sec = ts } end
    local function genEmuEvent(t, c, v, tv) inputQueue[#inputQueue + 1] = { t, c, v } end
    local function genTouchDownEvent(ev, slot, index)
        local tv = genInputTimeval(1)
        genEmuEvent(C.EV_ABS, C.ABS_MT_SLOT, slot, tv); genEmuEvent(C.EV_ABS, C.ABS_MT_POSITION_X, ev.x, tv)
    end
    local function genTouchMoveEvent(ev, tv, slot, index)
        genEmuEvent(C.EV_ABS, C.ABS_MT_SLOT, slot, tv); genEmuEvent(C.EV_ABS, C.ABS_MT_POSITION_X, ev.x, tv)
    end
    local function motionEventHandler(ev)
        if ev.down then genTouchDownEvent(ev, 3, 0) else genTouchMoveEvent(ev, {}, 3, 0) end
    end
    return { waitForEvent = function(ev) inputQueue = {}; motionEventHandler(ev); return inputQueue end }
end)()
local lib = {
    AMotionEvent_getToolType = function(ev) return ev.tool end, AMotionEvent_getButtonState = function(ev) return ev.buttons end,
    AMotionEvent_getPressure = function(ev) return ev.p end, AInputEvent_getDeviceId = function(ev) return ev.dev end,
    AMotionEvent_getEventTime = function() return 1 end,
    AMotionEvent_getHistorySize = function(ev) return ev.hist and #ev.hist or 0 end,
    AMotionEvent_getHistoricalX = function(ev, _, h) return ev.hist[h + 1][1] end,
    AMotionEvent_getHistoricalY = function(ev, _, h) return ev.hist[h + 1][2] end,
    AMotionEvent_getHistoricalPressure = function() return 0.4 end,
}
assert(A.hookInput(fake, { C = C, lib = lib, penDevice = function(dev) return dev == 7 end }))
local function tool_in(q) for _, e in ipairs(q) do if e[2] == C.ABS_MT_TOOL_TYPE then return e[3] end end end
local function pressure_in(q) for _, e in ipairs(q) do if e[2] == C.ABS_MT_PRESSURE then return e[3] end end end
local q = fake.waitForEvent{ down = true, x = 5, tool = 2, buttons = 0, p = 0.5, dev = 1 }
assert(q[1][2] == C.ABS_MT_SLOT and q[1][3] == 3 and tool_in(q) == A.PEN and pressure_in(q) == 0.5)
assert(q[#q][2] == C.ABS_MT_POSITION_X and q[#q][3] == 5) -- KOReader's own events still follow
assert(tool_in(fake.waitForEvent{ x = 6, tool = 1, buttons = 0, p = 1, dev = 7 }) == A.PEN)    -- move, pen device
assert(tool_in(fake.waitForEvent{ down = true, x = 6, tool = 1, buttons = 0, p = 1, dev = 2 }) == A.FINGER)
assert(tool_in(fake.waitForEvent{ down = true, x = 6, tool = 4, buttons = 0, p = 1, dev = 1 }) == A.ERASER)
assert(A.hookInput(fake, { C = C, lib = lib }) == true) -- a second call doesn't wrap twice
assert(#fake.waitForEvent{ down = true, x = 1, tool = 2, buttons = 0, p = 1, dev = 1 } == 5)
assert(A.hookInput({ waitForEvent = function() end }, { C = C, lib = lib }) == false) -- unexpected shape: left alone

-- the pen's in-between positions: one input frame each, before the event's own position; none for a finger
local function frames(q)
    local out, x = {}, nil
    for _, e in ipairs(q) do
        if e[2] == C.ABS_MT_POSITION_X then x = e[3] end
        if e[1] == C.EV_SYN then out[#out + 1] = x end
    end
    return out
end
q = fake.waitForEvent{ x = 9, tool = 2, buttons = 0, p = 1, dev = 1, hist = { { 7, 70 }, { 8, 80 } } }
local f = frames(q)
assert(#f == 2 and f[1] == 7 and f[2] == 8, #f)
assert(q[#q][2] == C.ABS_MT_POSITION_X and q[#q][3] == 9) -- then the current position, as before
assert(#frames(fake.waitForEvent{ x = 9, tool = 1, buttons = 0, p = 1, dev = 2, hist = { { 7, 70 } } }) == 0)

-- ABS_MT_PRESSURE kept in the slot
local input = { ev_slots = { [3] = {} }, cur_slot = 3, seen = 0 }
function input:setCurrentMtSlot(k, v) self.ev_slots[self.cur_slot][k] = v end
function input:handleTouchEv(ev) self.seen = self.seen + 1 end
A.keepPressure(input, C)
input:handleTouchEv{ type = 3, code = C.ABS_MT_PRESSURE, value = 0.7 }
assert(input.ev_slots[3].pressure == 0.7 and input.seen == 1)

print("notes: all OK")
