--[[--
Handwriting → text for the pen notes ("Trascrivi"), with Google's handwriting recognition (the service behind
Google's handwriting keyboard). Only on request, after the user agreed once: the strokes leave the device.
Pure Lua (tests/notes-test.lua); the HTTP POST is passed in.

The sheet is cut into lines along its ruled lines (a stroke belongs to the line its middle is on), each line
is recognised on its own, and the lines are joined with newlines.
]]
local M = {
    URL = "https://inputtools.google.com/request?ime=handwriting&app=mobilesearch&cs=1&oe=UTF-8",
}

--- The strokes in lines, top to bottom; each line keeps drawing order
function M.lines(strokes, step)
    local rows, order = {}, {}
    for _, st in ipairs(strokes) do
        local lo, hi = math.huge, -math.huge
        for i = 2, #st.p, 2 do lo, hi = math.min(lo, st.p[i]), math.max(hi, st.p[i]) end
        local r = math.floor((lo + hi) / 2 / step)
        if not rows[r] then rows[r] = {}; order[#order + 1] = r end
        table.insert(rows[r], st)
    end
    table.sort(order)
    local out = {}
    for _, r in ipairs(order) do out[#out + 1] = rows[r] end
    return out
end

--- The JSON body for one line
function M.request(line, w, h, lang)
    local ink = {}
    for _, st in ipairs(line) do
        local xs, ys = {}, {}
        for i = 1, #st.p - 1, 2 do
            xs[#xs + 1] = ("%d"):format(st.p[i])
            ys[#ys + 1] = ("%d"):format(st.p[i + 1])
        end
        ink[#ink + 1] = ("[[%s],[%s]]"):format(table.concat(xs, ","), table.concat(ys, ","))
    end
    return ('{"options":"enable_pre_space","requests":[{"writing_guide":{"writing_area_width":%d,"writing_area_height":%d},'
        .. '"ink":[%s],"language":"%s"}]}'):format(w, h, table.concat(ink, ","), lang or "it")
end

-- a JSON string starting at s[i] == '"': its value and the index after it
local function jstring(s, i)
    local out, j = {}, i + 1
    while j <= #s do
        local c = s:sub(j, j)
        if c == '"' then return table.concat(out), j + 1 end
        if c == "\\" then
            local e = s:sub(j + 1, j + 1)
            if e == "u" then
                local cp = tonumber(s:sub(j + 2, j + 5), 16) or 63
                if cp < 0x80 then out[#out + 1] = string.char(cp)
                elseif cp < 0x800 then out[#out + 1] = string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64)
                else out[#out + 1] = string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64) end
                j = j + 6
            else
                out[#out + 1] = ({ n = "\n", t = "\t", r = "" })[e] or e
                j = j + 2
            end
        else
            out[#out + 1] = c
            j = j + 1
        end
    end
end

--- The best guess in a reply: ["SUCCESS",[["<id>",["best","second",…],…]]] → "best"; or nil, reason
function M.parse(body)
    if type(body) ~= "string" or not body:find('^%s*%[%s*"SUCCESS"') then
        return nil, body and body:sub(1, 80) or "nessuna risposta"
    end
    local p = body:find('%[%s*%[%s*"')
    if not p then return "" end
    local _, after_id = jstring(body, body:find('"', p))
    local at = after_id and body:find('%[%s*"', after_id) -- the candidates list, after the id
    if not at then return "" end
    return (jstring(body, body:find('"', at)))
end

--- The whole sheet as text. post(url, body) → reply body, or nil, error
function M.transcribe(strokes, step, w, h, post, lang)
    local text = {}
    for _, line in ipairs(M.lines(strokes, step)) do
        local reply, err = post(M.URL, M.request(line, w, h, lang))
        if not reply then return nil, err end
        local best, why = M.parse(reply)
        if not best then return nil, why end
        if best ~= "" then text[#text + 1] = best end
    end
    return table.concat(text, "\n")
end

return M
