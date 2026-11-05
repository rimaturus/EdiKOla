--[[--
Android (Bigme B6 Pro Color) extras for the pen notes. Each one is best-effort: if KOReader or the Bigme
firmware isn't what we expect, it logs why and leaves KOReader as it was.

1. Pen, eraser and pressure. Android reports, for every touch, which tool made it (finger, stylus, eraser
   end), the stylus button and the pressure; KOReader's Android input (ffi/input_android.lua) drops all
   three. hookInput() wraps its touch functions so each contact also carries ABS_MT_TOOL_TYPE and
   ABS_MT_PRESSURE, the way Kobo's pen panels send them. Bigme firmware may call its pen a finger: the
   pen is then recognised by its input device's name ("fts_ts_pen").
2. A faster screen for the pen. KOReader copies the whole screen to Android on every refresh; for "fast"
   refreshes (the pen's) only the changed rectangle is copied, so Android and the e-ink panel only
   update that.
3. Bigme's E-Ink Center has a low-latency handwriting mode (1029), set per app through its system service
   xrz_display_policy_service; the notes sheet switches KOReader to it, and back when it closes.
   (Mode numbers and service names from the Kalamos project's notes on Bigme firmware.)
]]
local logger = require("logger")

local M = {
    PEN = 1, ERASER = 2, FINGER = 0, -- KOReader's tool numbers (frontend/device/input.lua)
    HANDWRITE_MODE = 1029,
}

-- Android's AMOTION_EVENT_TOOL_TYPE_STYLUS and _ERASER
local A_STYLUS, A_ERASER = 2, 4

--- KOReader tool for an Android pointer: the eraser end, or the pen's side button held, erase
function M.toolOf(android_tool, buttons, pen_device)
    if android_tool == A_ERASER then return M.ERASER end
    if android_tool == A_STYLUS or pen_device then
        if buttons and buttons % 0x80 >= 0x20 then return M.ERASER end -- BUTTON_STYLUS_PRIMARY/SECONDARY (0x20, 0x40)
        return M.PEN
    end
    return M.FINGER
end

local function upvalue(f, name)
    if type(f) ~= "function" then return end
    for i = 1, 200 do
        local n, v = debug.getupvalue(f, i)
        if not n then return end
        if n == name then return v, i end
    end
end

--- Wraps the touch-down and touch-move generators of an input_android-like module.
-- deps = { C = ffi.C-like constants, lib = NDK functions, penDevice = function(device_id): bool }
-- Returns true when hooked.
function M.hookInput(input_mod, deps)
    if input_mod.edikola_hooked then return true end
    local motion, mi = upvalue(input_mod.waitForEvent, "motionEventHandler")
    local down, di = upvalue(motion, "genTouchDownEvent")
    local move, vi = upvalue(motion, "genTouchMoveEvent")
    local emu = upvalue(down, "genEmuEvent")
    local timeval = upvalue(down, "genInputTimeval")
    if not (mi and di and vi and emu and timeval) then
        logger.warn("EdiKOla: Android input not as expected, pen = finger")
        return false
    end
    local C, lib = deps.C, deps.lib
    local function extra(event, timev, slot, index)
        local ok, tool, buttons, pressure, device = pcall(function()
            return tonumber(lib.AMotionEvent_getToolType(event, index)), tonumber(lib.AMotionEvent_getButtonState(event)),
                tonumber(lib.AMotionEvent_getPressure(event, index)), tonumber(lib.AInputEvent_getDeviceId(event))
        end)
        if not ok then return end
        local pen_device = deps.penDevice and deps.penDevice(device)
        emu(C.EV_ABS, C.ABS_MT_SLOT, slot, timev)
        emu(C.EV_ABS, C.ABS_MT_TOOL_TYPE, M.toolOf(tool, buttons, pen_device), timev)
        emu(C.EV_ABS, C.ABS_MT_PRESSURE, pressure, timev)
    end
    debug.setupvalue(motion, di, function(event, slot, index)
        extra(event, timeval(lib.AMotionEvent_getEventTime(event)), slot, index)
        return down(event, slot, index)
    end)
    debug.setupvalue(motion, vi, function(event, timev, slot, index)
        extra(event, timev, slot, index)
        return move(event, timev, slot, index)
    end)
    input_mod.edikola_hooked = true
    return true
end

--- Keeps ABS_MT_PRESSURE in the slot data (KOReader's handleTouchEv ignores it): slot.pressure, 0..1
function M.keepPressure(input, C)
    if input.edikola_pressure then return end
    input.edikola_pressure = true
    local handle = input.handleTouchEv
    input.handleTouchEv = function(self, ev)
        if ev.type == C.EV_ABS and ev.code == C.ABS_MT_PRESSURE and self.ev_slots and self.ev_slots[self.cur_slot] then
            self:setCurrentMtSlot("pressure", ev.value)
        end
        return handle(self, ev)
    end
end

-- ---------------------------------------------------------------- JNI (Android only)

-- Runs fn(env, check) attached to the JVM; check(x) is false when x is NULL or a Java exception is pending
-- (and clears it), so a missing class or method never crashes KOReader.
local function java(fn)
    local android = require("android")
    local ok, res = pcall(android.jni.context, android.jni, android.app.activity.vm, function(jni)
        local env = jni.env
        local function check(x)
            if env[0].ExceptionCheck(env) ~= 0 then
                env[0].ExceptionClear(env)
                return false
            end
            return x ~= nil
        end
        return fn(env, check)
    end)
    if not ok then logger.warn("EdiKOla: java", res) end
    return ok and res or nil
end

local function ffi_int(v) return require("ffi").new("int32_t", v) end -- varargs to JNI need a C type

local pen_devices = {}
--- Is this input device Bigme's pen? (cached per device id)
function M.penDevice(id)
    if pen_devices[id] == nil then
        local name = java(function(env, check)
            local cls = env[0].FindClass(env, "android/view/InputDevice")
            if not check(cls) then return end
            local get = env[0].GetStaticMethodID(env, cls, "getDevice", "(I)Landroid/view/InputDevice;")
            if not check(get) then return end
            local dev = env[0].CallStaticObjectMethod(env, cls, get, ffi_int(id))
            if not check(dev) then return end
            local getName = env[0].GetMethodID(env, cls, "getName", "()Ljava/lang/String;")
            if not check(getName) then return end
            local s = env[0].CallObjectMethod(env, dev, getName)
            if not check(s) then return end
            local chars = env[0].GetStringUTFChars(env, s, nil)
            local out = require("ffi").string(chars)
            env[0].ReleaseStringUTFChars(env, s, chars)
            return out
        end) or ""
        pen_devices[id] = name:lower() == "fts_ts_pen" or name:lower():find("stylus", 1, true) ~= nil
        logger.info("EdiKOla: input device", id, name, pen_devices[id] and "(pen)" or "")
    end
    return pen_devices[id]
end

-- E-Ink Center: setRefreshModeForPackage(our package, mode). Returns the mode it replaced, or nil.
function M.einkMode(mode)
    return java(function(env, check)
        local ffi = require("ffi")
        local android = require("android")
        local function str(s) return env[0].NewStringUTF(env, s) end
        -- our package name
        local act = android.app.activity.clazz
        local acls = env[0].GetObjectClass(env, act)
        local gp = env[0].GetMethodID(env, acls, "getPackageName", "()Ljava/lang/String;")
        if not check(gp) then return end
        local pkg = env[0].CallObjectMethod(env, act, gp)
        if not check(pkg) then return end
        -- the service, through android.os.ServiceManager (hidden API: may be refused)
        local sm = env[0].FindClass(env, "android/os/ServiceManager")
        if not check(sm) then return logger.info("EdiKOla: no ServiceManager") end
        local gs = env[0].GetStaticMethodID(env, sm, "getService", "(Ljava/lang/String;)Landroid/os/IBinder;")
        if not check(gs) then return logger.info("EdiKOla: ServiceManager.getService refused") end
        local binder = env[0].CallStaticObjectMethod(env, sm, gs, str("xrz_display_policy_service"))
        if not check(binder) then return logger.info("EdiKOla: no Bigme display service") end
        local stub = env[0].FindClass(env, "xrz/framework/manager/IDisplayPolicyManager$Stub")
        if not check(stub) then return logger.info("EdiKOla: no Bigme display API") end
        local as = env[0].GetStaticMethodID(env, stub, "asInterface", "(Landroid/os/IBinder;)Lxrz/framework/manager/IDisplayPolicyManager;")
        if not check(as) then return end
        local mgr = env[0].CallStaticObjectMethod(env, stub, as, binder)
        if not check(mgr) then return end
        local mcls = env[0].GetObjectClass(env, mgr)
        local get = env[0].GetMethodID(env, mcls, "getRefreshModeForPackage", "(Ljava/lang/String;)I")
        if not check(get) then return end
        local old = tonumber(env[0].CallIntMethod(env, mgr, get, pkg))
        if not check(true) then return end
        for _, call in ipairs{ { "setIsRefreshSettingForPackage", 1 }, { "setRefreshModeForPackage", mode } } do
            local m = env[0].GetMethodID(env, mcls, call[1], "(Ljava/lang/String;I)Z")
            if not check(m) then return end
            env[0].CallBooleanMethod(env, mgr, m, pkg, ffi.new("int32_t", call[2]))
            if not check(true) then return end
        end
        logger.info("EdiKOla: E-Ink Center mode", old, "->", mode)
        return old
    end)
end

-- ---------------------------------------------------------------- screen

--- "fast" refreshes copy only their rectangle to the Android window (portrait, no night mode; else as before)
function M.partialFastRefresh(screen)
    local ffi = require("ffi")
    local android = require("android")
    local BB = require("ffi/blitbuffer")
    local C = ffi.C
    if screen.edikola_partial or android.isEinkFull() then return end
    screen.edikola_partial = true
    local function partial(self, x, y, w, h)
        local src = self.full_bb or self.bb
        if src:getRotation() ~= 0 or src:getInverse() == 1 or android.app.window == nil then return false end
        x, y, w, h = src:getBoundedRect(x, y, w, h)
        if w <= 0 or h <= 0 then return true end
        local rect = ffi.new("ARect[1]")
        rect[0].left, rect[0].top, rect[0].right, rect[0].bottom = x, y, x + w, y + h
        local buf = ffi.new("ANativeWindow_Buffer[1]")
        if android.lib.ANativeWindow_lock(android.app.window, buf, rect) < 0 then return false end
        local b = buf[0]
        if b.format == C.WINDOW_FORMAT_RGBA_8888 or b.format == C.WINDOW_FORMAT_RGBX_8888 then
            -- Android may grow the rectangle (it must then be redrawn whole): copy what it asks for
            local win = BB.new(b.width, b.height, BB.TYPE_BBRGB32, b.bits, b.stride * 4, b.stride)
            local r = rect[0]
            win:blitFrom(src, r.left, r.top, r.left, r.top, r.right - r.left, r.bottom - r.top)
        else -- RGB565: as KOReader does it, whole
            local win = BB.new(b.width, b.height, BB.TYPE_BBRGB16, b.bits, b.stride * 2, b.stride)
            win:blitFrom(src)
        end
        android.lib.ANativeWindow_unlockAndPost(android.app.window)
        return true
    end
    local fast = screen.refreshFastImp
    screen.refreshFastImp = function(self, x, y, w, h)
        local ok, done = pcall(partial, self, x, y, w, h)
        if not (ok and done) then
            if not ok then logger.warn("EdiKOla: partial refresh", done) end
            return fast(self, x, y, w, h)
        end
    end
end

--- Everything above, once, on Android
function M.setup(Device)
    if M.done or not Device:isAndroid() then return end
    M.done = true
    local ok, err = pcall(function()
        local ffi = require("ffi")
        local android = require("android")
        for _, decl in ipairs{
            "int32_t AMotionEvent_getToolType(const AInputEvent* motion_event, size_t pointer_index);",
            "int32_t AMotionEvent_getButtonState(const AInputEvent* motion_event);",
        } do pcall(ffi.cdef, decl) end -- already declared on some builds: fine
        if M.hookInput(require("ffi/input_android"), { C = ffi.C, lib = android.lib, penDevice = M.penDevice }) then
            M.keepPressure(Device.input, ffi.C)
        end
        M.partialFastRefresh(Device.screen)
    end)
    if not ok then logger.warn("EdiKOla: Android setup", err) end
end

return M
