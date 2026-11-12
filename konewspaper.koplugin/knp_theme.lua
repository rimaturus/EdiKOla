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
    -- the newsstand frame: ink-blue masthead, its light tint for buttons
    ink = { "#1C2E4A", G.COLOR_BLACK },          ink_tint = { "#DCE3EE", G.COLOR_GRAY_E },
    -- puzzles: one color each, a tint for their highlights
    giochi = { "#D84315", G.COLOR_BLACK },       giochi_tint = { "#FBE0D3", G.COLOR_GRAY_E },
    sudoku = { "#00695C", G.COLOR_BLACK },       sudoku_tint = { "#D3ECE8", G.COLOR_GRAY_E },
    cruciverba = { "#283593", G.COLOR_BLACK },   cruciverba_tint = { "#DCE0F5", G.COLOR_GRAY_E },
    crucipuzzle = { "#AD1457", G.COLOR_BLACK },  crucipuzzle_tint = { "#F7D7E5", G.COLOR_GRAY_E },
    errore = { "#C62828", G.COLOR_BLACK },       scritto = { "#1A3FA8", G.COLOR_DARK_GRAY },
    -- found words in the crucipuzzle, each in its own light color
    f1 = { "#FFE082", G.COLOR_GRAY_D }, f2 = { "#A5D6A7", G.COLOR_GRAY_B }, f3 = { "#90CAF9", G.COLOR_GRAY_D },
    f4 = { "#F48FB1", G.COLOR_GRAY_B }, f5 = { "#FFCC80", G.COLOR_GRAY_D }, f6 = { "#CE93D8", G.COLOR_GRAY_B },
    f7 = { "#80CBC4", G.COLOR_GRAY_D }, f8 = { "#E6EE9C", G.COLOR_GRAY_B },
}

-- Night mode (phones): KOReader inverts the whole screen, which turns every hue into its opposite (red into
-- cyan). So in night mode a color is painted as the inverse of itself with its lightness flipped: once
-- inverted on screen it keeps its hue, and light tints become dark ones, like white becomes black.
local function night(hex)
    local r, g, b = tonumber(hex:sub(2, 3), 16) / 255, tonumber(hex:sub(4, 5), 16) / 255, tonumber(hex:sub(6, 7), 16) / 255
    local max, min = math.max(r, g, b), math.min(r, g, b)
    local l = (max + min) / 2
    local nl = 1 - l -- same hue and saturation, flipped lightness: scale the distance from gray
    local k = (l == 0 or l == 1) and 0 or math.min(nl, 1 - nl) / math.min(l, 1 - l)
    local function ch(c) return math.floor(255 * (1 - (nl + (c - l) * k)) + 0.5) end
    return ("#%02X%02X%02X"):format(ch(r), ch(g), ch(b))
end

local cache = {}
local T = {}

--- The color for a name (falls back to gray); follows KOReader's "color rendering" switch and night mode
function T.color(name)
    local p = PALETTE[name] or PALETTE.neutral
    if not Screen:isColorEnabled() then return p[2] end
    local hex = Screen.night_mode and night(p[1]) or p[1]
    cache[hex] = cache[hex] or Blitbuffer.colorFromString(hex)
    return cache[hex]
end
T.night = night -- for the tests

T.inks = { "nero", "blu", "rosso", "verde" }

--- A filled rectangle in any color (bb:paintRect alone turns colors gray)
function T.rect(bb, x, y, w, h, c)
    if Blitbuffer.isColor8(c) then bb:paintRect(x, y, w, h, c) else bb:paintRectRGB32(x, y, w, h, c) end
end

--- A plain colored block, for stripes and bands; with a radius, a rounded one (radius = half: a dot)
local Geom = require("ui/geometry")
T.Box = require("ui/widget/widget"):extend{ width = 0, height = 0, color = nil, radius = nil }
function T.Box:getSize() return Geom:new{ w = self.width, h = self.height } end
function T.Box:paintTo(bb, x, y)
    if not self.radius then return T.rect(bb, x, y, self.width, self.height, self.color) end
    local f = Blitbuffer.isColor8(self.color) and bb.paintRoundedRect or bb.paintRoundedRectRGB32
    f(bb, x, y, self.width, self.height, self.color, self.radius)
end

--- The buffer as KOReader's text code sees it, but glyphs keep fg's real color: TextWidget and
-- RenderText blit glyphs with colorblitFrom, which turns any color gray (TextBoxWidget does it right).
function T.inColor(bb, fg)
    if not fg or Blitbuffer.isColor8(fg) then return bb end
    return setmetatable({ colorblitFrom = function(_, src, ...) return bb:colorblitFromRGB32(src, ...) end }, {
        __index = function(_, k)
            local v = bb[k]
            if type(v) == "function" then return function(_, ...) return v(bb, ...) end end
            return v
        end,
    })
end

--- A TextWidget that shows its fgcolor in color
local TextWidget = require("ui/widget/textwidget")
T.Text = TextWidget:extend{}
function T.Text:paintTo(bb, x, y) return TextWidget.paintTo(self, T.inColor(bb, self.fgcolor), x, y) end

--- A rounded, filled, tappable label: the newsstand's buttons and tabs, the puzzles' keys.
-- Pill:new{ text =, width =, height =, fill = color, fg = color, size = 20, callback =, enabled = true, lines = n }
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local GestureRange = require("ui/gesturerange")
local TextBoxWidget = require("ui/widget/textboxwidget")
T.Pill = require("ui/widget/container/inputcontainer"):extend{
    text = "", width = 100, height = 50, fill = nil, fg = nil, size = 20, callback = nil, enabled = true,
    border = false, face = "NotoSans-Bold.ttf", lines = nil, -- lines: at most that many, then "…"
}
function T.Pill:init()
    local fill = self.fill or G.COLOR_WHITE
    local bw = self.border and Screen:scaleBySize(2) or 0
    local fg = self.enabled and (self.fg or G.COLOR_BLACK) or G.COLOR_GRAY_9
    local function box(height)
        return TextBoxWidget:new{
            text = self.text, face = Font:getFace(self.face, self.size), alignment = "center",
            width = self.width - 2 * bw - Screen:scaleBySize(8), fgcolor = fg, bgcolor = fill,
            height = height, height_overflow_show_ellipsis = height and true,
        }
    end
    local text = box()
    local max_h = self.lines and self.lines * text:getLineHeight()
    if max_h and text:getSize().h > max_h + 1 then -- too long: "…"
        text:free()
        text = box(max_h)
    end
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self[1] = FrameContainer:new{
        width = self.width, height = self.height, padding = 0, margin = 0, bordersize = bw,
        radius = Screen:scaleBySize(12), background = fill,
        CenterContainer:new{ dimen = Geom:new{ w = self.width - 2 * bw, h = self.height - 2 * bw }, text },
    }
    self.ges_events = { TapPill = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
end
function T.Pill:onTapPill()
    if self.enabled and self.callback then self.callback() end
    return true
end

return T
