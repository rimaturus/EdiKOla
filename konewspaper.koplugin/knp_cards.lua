--[[--
A full-screen list of big cards, in pages: the Sommario, the titles, the books and the notebook all use it.
Each card: a colored stripe, a bold title, a few lines of text, optionally a picture on the right.
Tap a card to open it; swipe or the arrows for the next page; "◀ Indietro" or the Back key closes.

    Cards.show{ title = "…", items = { { title =, text =, color =, image =, callback = } | { header = "…", color = } } }
]]
local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local theme = require("knp_theme")
local Screen = Device.screen

-- text that stops after `lines` lines, with an ellipsis
local function lines(text, face, width, n, fgcolor)
    local t = TextBoxWidget:new{ text = text, face = face, width = width, fgcolor = fgcolor }
    if n and t:getSize().h > n * t:getLineHeight() + 1 then
        t:free()
        t = TextBoxWidget:new{ text = text, face = face, width = width, fgcolor = fgcolor,
            height = n * t:getLineHeight(), height_overflow_show_ellipsis = true }
    end
    return t
end

local Card = InputContainer:extend{ item = nil, width = nil }

function Card:init()
    local it = self.item
    local s = Screen:scaleBySize(1)
    if it.header then -- a section title between cards: colored text over a colored rule
        self[1] = VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = 6 * s },
            theme.Text:new{ text = it.header:upper(), face = Font:getFace("NotoSans-Bold.ttf", 17),
                fgcolor = theme.color(it.color), max_width = self.width },
            theme.Box:new{ width = self.width, height = 2 * s, color = theme.color(it.color) },
        }
        return
    end
    self.ges_events = { Tap = { GestureRange:new{ ges = "tap", range = function() return self.dimen end } } }
    local border, pad, stripe = 2 * s, 10 * s, 8 * s
    local thumb_w = it.image and Screen:scaleBySize(110) or 0
    local text_w = self.width - 2 * (border + pad) - stripe - pad - (thumb_w > 0 and thumb_w + pad or 0)
    local body = VerticalGroup:new{ align = "left" }
    table.insert(body, lines(it.title, Font:getFace("NotoSerif-Bold.ttf", 19), text_w, it.title_lines or 3))
    if it.text and it.text ~= "" then
        table.insert(body, VerticalSpan:new{ width = 4 * s })
        table.insert(body, lines(it.text, Font:getFace("NotoSerif-Regular.ttf", 16), text_w, it.lines or 4,
            Blitbuffer.COLOR_GRAY_3))
    end
    local h = body:getSize().h
    local row = HorizontalGroup:new{
        align = "top",
        theme.Box:new{ width = stripe, height = math.max(h, thumb_w > 0 and Screen:scaleBySize(80) or 0), color = theme.color(it.color) },
        HorizontalSpan:new{ width = pad },
        body,
    }
    if thumb_w > 0 then
        local ok, img = pcall(function()
            local i = ImageWidget:new{ file = it.image, width = thumb_w, height = Screen:scaleBySize(80),
                scale_factor = 0, file_do_cache = false }
            i:getSize()
            return i
        end)
        if ok then
            table.insert(row, HorizontalSpan:new{ width = pad })
            table.insert(row, img)
        end
    end
    self[1] = FrameContainer:new{
        width = self.width, bordersize = border, padding = pad, radius = 8 * s,
        background = Blitbuffer.COLOR_WHITE,
        row,
    }
end

function Card:onTap()
    if self.item.callback then self.item.callback() end
    return true
end

local Cards = InputContainer:extend{
    covers_fullscreen = true,
    title = "",
    items = nil,
    page = 1,
    close_callback = nil,
}

function Cards:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    local m, gap = Screen:scaleBySize(12), Screen:scaleBySize(10)
    local cw = sw - 2 * m
    self.ges_events = { Swipe = { GestureRange:new{ ges = "swipe", range = self.dimen } } }
    if Device:hasKeys() then self.key_events = { Close = { { Device.input.group.Back } } } end

    local back_w, bar_h = Screen:scaleBySize(130), Screen:scaleBySize(52)
    local top = HorizontalGroup:new{
        align = "center",
        Button:new{ text = "◀ Indietro", width = back_w, height = bar_h, text_font_face = "NotoSans-Bold.ttf",
            text_font_size = 19, bordersize = Screen:scaleBySize(2), radius = Screen:scaleBySize(10),
            callback = function() self:onClose() end },
        HorizontalSpan:new{ width = gap },
        lines(self.title, Font:getFace("NotoSerif-Bold.ttf", 26), cw - back_w - gap, 1),
    }
    local header = VerticalGroup:new{ align = "left", top, VerticalSpan:new{ width = gap },
        LineWidget:new{ dimen = Geom:new{ w = cw, h = Screen:scaleBySize(2) } } }
    local pager_h = Screen:scaleBySize(48)
    local avail = sh - 2 * m - header:getSize().h - gap - pager_h - gap

    -- page breaks, from the measured cards (built once, reused when turning pages)
    if not self.cards then
        self.cards, self.starts = {}, { 1 }
        local used = 0
        for i, it in ipairs(self.items) do
            local c = Card:new{ item = it, width = cw }
            local h = c:getSize().h + gap
            -- a header never ends a page: it moves to the next one with its first card
            if used > 0 and (used + h > avail or (it.header and used + h + gap * 6 > avail)) then
                table.insert(self.starts, i)
                used = 0
            end
            used = used + h
            self.cards[i] = c
        end
    end
    local pages = #self.starts
    self.page = math.max(1, math.min(self.page, pages))
    local list = VerticalGroup:new{ align = "left" }
    for i = self.starts[self.page], (self.starts[self.page + 1] or #self.cards + 1) - 1 do
        table.insert(list, self.cards[i])
        table.insert(list, VerticalSpan:new{ width = gap })
    end

    local body = VerticalGroup:new{
        align = "left",
        header,
        VerticalSpan:new{ width = gap },
        CenterContainer:new{ dimen = Geom:new{ w = cw, h = avail }, VerticalGroup:new{ align = "left",
            list, VerticalSpan:new{ width = math.max(0, avail - list:getSize().h) } } },
        VerticalSpan:new{ width = gap },
    }
    if pages > 1 then
        local arrow = function(text, d)
            return Button:new{ text = text, width = back_w, height = pager_h, enabled = self.page + d >= 1 and self.page + d <= pages,
                bordersize = Screen:scaleBySize(2), radius = Screen:scaleBySize(10), text_font_size = 24,
                callback = function() self:turn(d) end }
        end
        table.insert(body, HorizontalGroup:new{
            align = "center",
            arrow("◀", -1),
            CenterContainer:new{ dimen = Geom:new{ w = cw - 2 * back_w, h = pager_h },
                TextWidget:new{ text = ("Pagina %d di %d"):format(self.page, pages), face = Font:getFace("cfont", 20) } },
            arrow("▶", 1),
        })
    end
    self[1] = FrameContainer:new{ width = sw, height = sh, bordersize = 0, padding = m,
        background = Blitbuffer.COLOR_WHITE, body }
end

function Cards:turn(d)
    local p = self.page + d
    if p < 1 or p > #self.starts then return end
    self.page = p
    self:init()
    UIManager:setDirty(self, "ui")
end

function Cards:onSwipe(_, ges)
    if ges.direction == "west" then self:turn(1) elseif ges.direction == "east" then self:turn(-1) end
    return true
end

function Cards:onClose()
    UIManager:close(self)
    return true
end

function Cards:onCloseWidget()
    for _, c in ipairs(self.cards or {}) do c:free() end
    if self.close_callback then self.close_callback() end
end

function Cards.show(args)
    local w = Cards:new(args)
    UIManager:show(w, "full")
    return w
end

return Cards
