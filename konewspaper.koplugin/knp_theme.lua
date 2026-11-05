-- Colors for the Bigme B6 Pro Color (Kaleido 3): deep tones for bands, stripes and ink (no text on them,
-- except white on bands), light tints behind black text. Every color has a gray for grayscale screens.
local Blitbuffer = require("ffi/blitbuffer")
local Screen = require("device").screen

local G = Blitbuffer
local PALETTE = { -- name = { color, gray }
    italia = { "#C62828", G.COLOR_BLACK },       italia_tint = { "#F7D9D9", G.COLOR_GRAY_E },
    mondo = { "#1565C0", G.COLOR_BLACK },        mondo_tint = { "#D6E4F7", G.COLOR_GRAY_E },
    buone = { "#2E7D32", G.COLOR_BLACK },        buone_tint = { "#DAEEDB", G.COLOR_GRAY_E },
    scienza = { "#6A1B9A", G.COLOR_BLACK },      scienza_tint = { "#E8D9F1", G.COLOR_GRAY_E },
    -- Sommario topics (knp_topics.names)
    ["Politica"] = { "#C62828", G.COLOR_BLACK },
    ["Economia e lavoro"] = { "#EF6C00", G.COLOR_DARK_GRAY },
    ["Esteri e conflitti"] = { "#1565C0", G.COLOR_BLACK },
    ["Cronaca"] = { "#5D4037", G.COLOR_DARK_GRAY },
    ["Salute"] = { "#00897B", G.COLOR_DARK_GRAY },
    ["Scienza e tecnologia"] = { "#6A1B9A", G.COLOR_BLACK },
    ["Ambiente"] = { "#2E7D32", G.COLOR_DARK_GRAY },
    ["Cultura e spettacoli"] = { "#AD1457", G.COLOR_DARK_GRAY },
    ["Sport"] = { "#F9A825", G.COLOR_GRAY_9 },
    ["Altre notizie"] = { "#757575", G.COLOR_GRAY_9 },
    -- pen inks and the notebook paper
    nero = { "#000000", G.COLOR_BLACK },         blu = { "#1A3FA8", G.COLOR_DARK_GRAY },
    rosso = { "#C62828", G.COLOR_DARK_GRAY },     verde = { "#2E7D32", G.COLOR_DARK_GRAY },
    rule = { "#BCD3EC", G.COLOR_GRAY_D },        margin = { "#E88B8B", G.COLOR_GRAY_B },
    neutral = { "#757575", G.COLOR_GRAY_9 },
}

local cache = {}
local T = {}

--- The color for a name (falls back to gray); follows KOReader's "color rendering" switch
function T.color(name)
    local p = PALETTE[name] or PALETTE.neutral
    if not Screen:isColorEnabled() then return p[2] end
    cache[p[1]] = cache[p[1]] or Blitbuffer.colorFromString(p[1])
    return cache[p[1]]
end

T.inks = { "nero", "blu", "rosso", "verde" }

--- A filled rectangle in any color (bb:paintRect alone turns colors gray)
function T.rect(bb, x, y, w, h, c)
    if Blitbuffer.isColor8(c) then bb:paintRect(x, y, w, h, c) else bb:paintRectRGB32(x, y, w, h, c) end
end

--- A plain colored block, for stripes and bands
local Geom = require("ui/geometry")
T.Box = require("ui/widget/widget"):extend{ width = 0, height = 0, color = nil }
function T.Box:getSize() return Geom:new{ w = self.width, h = self.height } end
function T.Box:paintTo(bb, x, y) T.rect(bb, x, y, self.width, self.height, self.color) end

return T
