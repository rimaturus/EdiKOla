-- KOReader user patch (installed in .adds/koreader/patches/ by minimal/build.sh), runs before the first screen.
-- minimal/prune.sh removes the Chinese/Japanese/Korean, Arabic, Bengali and Devanagari fonts. They are on
-- KOReader's fallback list, so without this KOReader tries each missing one again for every new text size
-- (95 errors in crash.log for one run through the screens).
local Font = require("ui/font")
local FontList = require("fontlist")

local paths = FontList:getFontList()
local function installed(name)
    local pattern = "/" .. name:gsub("%p", "%%%0") .. "$"
    for _, path in ipairs(paths) do
        if path:find(pattern) then return true end
    end
end

local kept, insert_at = {}, Font.additional_fallback_insert_indice
for i, name in ipairs(Font.fallbacks) do
    if installed(name) then
        table.insert(kept, name)
    elseif i < Font.additional_fallback_insert_indice then
        insert_at = insert_at - 1
    end
end
Font.fallbacks = kept
Font.additional_fallback_insert_indice = math.max(2, insert_at)
