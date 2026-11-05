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

-- pressure: stored per point, width follows it, old notes (no q) keep the normal width
local pq = ink.decode(ink.encode{ w = 10, h = 10, text = "ciao\nmondo", strokes = { { c = "nero", p = { 1, 2, 3, 4 }, q = { 2, 8 } } } })
assert(pq.strokes[1].q[2] == 8 and pq.text == "ciao\nmondo")
assert(ink.level(nil) == nil and ink.level(0) == nil and ink.level(0.5) == 5 and ink.level(2) == 9 and ink.level(0.01) == 1)
assert(ink.width(4, nil) == 4 and ink.width(4, 5) == 5 and ink.width(4, 1) == 2 and ink.width(4, 9) == 7)

-- handwriting: lines along the rules, the request, the reply
local hwr = require("knp_hwr")
local s1 = { c = "nero", p = { 10, 30, 20, 50 } }   -- middle 40: line 1 (step 34)
local s2 = { c = "nero", p = { 10, 80, 30, 90 } }   -- middle 85: line 2
local s3 = { c = "nero", p = { 40, 35, 50, 45 } }   -- line 1 again, drawn later
local lines = hwr.lines({ s1, s2, s3 }, 34)
assert(#lines == 2 and lines[1][1] == s1 and lines[1][2] == s3 and lines[2][1] == s2)
local body = hwr.request(lines[1], 1072, 1200, "it")
assert(body:find('"ink":%[%[%[10,20%],%[30,50%]%],%[%[40,50%],%[35,45%]%]%]'), body)
assert(body:find('"writing_area_width":1072') and body:find('"language":"it"'))
assert(hwr.parse('["SUCCESS",[["922de3eeef8d7cd6",["10","IO","I0"],[],{"is_html_escaped":false}]]]') == "10")
assert(hwr.parse('["SUCCESS",[["x",["perch\\u00e8 \\"no\\""],[],{}]]]') == 'perchè "no"')
assert(hwr.parse('["SUCCESS",[["x",[],[],{"is_html_escaped":false}]]]') == "")
assert(hwr.parse('["FAILED_TO_PARSE_REQUEST_BODY"]') == nil)
assert(hwr.parse(nil) == nil)
local answers = { '["SUCCESS",[["a",["prima riga"],[],{}]]]', '["SUCCESS",[["b",["seconda"],[],{}]]]' }
local calls = 0
local text = hwr.transcribe({ s1, s2, s3 }, 34, 1072, 1200, function(url, b)
    calls = calls + 1
    assert(url:find("^https://inputtools%.google%.com/request%?ime=handwriting") and b:find('"ink"'))
    return answers[calls]
end)
assert(text == "prima riga\nseconda" and calls == 2, text)
local t2, err = hwr.transcribe({ s1 }, 34, 10, 10, function() return nil, "HTTP 500" end)
assert(t2 == nil and err == "HTTP 500")

-- Android: tool and pressure added to KOReader's touch events (fake input_android, same shape as the real one)
package.preload.logger = function() return { warn = function() end, info = function() end } end
local A = require("knp_android")
assert(A.toolOf(2, 0) == A.PEN and A.toolOf(4, 0) == A.ERASER and A.toolOf(1, 0) == A.FINGER)
assert(A.toolOf(2, 0x20) == A.ERASER and A.toolOf(2, 0x40) == A.ERASER and A.toolOf(2, 0x80) == A.PEN)
assert(A.toolOf(1, 0, true) == A.PEN) -- Bigme's pen reported as a finger, known by its device
local C = { EV_ABS = 3, ABS_MT_SLOT = 0x2f, ABS_MT_TOOL_TYPE = 0x37, ABS_MT_PRESSURE = 0x3a, ABS_MT_POSITION_X = 0x35 }
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

-- ABS_MT_PRESSURE kept in the slot
local input = { ev_slots = { [3] = {} }, cur_slot = 3, seen = 0 }
function input:setCurrentMtSlot(k, v) self.ev_slots[self.cur_slot][k] = v end
function input:handleTouchEv(ev) self.seen = self.seen + 1 end
A.keepPressure(input, C)
input:handleTouchEv{ type = 3, code = C.ABS_MT_PRESSURE, value = 0.7 }
assert(input.ev_slots[3].pressure == 0.7 and input.seen == 1)

print("notes: all OK")
