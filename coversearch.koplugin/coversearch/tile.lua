-- SPDX-License-Identifier: AGPL-3.0-or-later
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local Device = require("device")
local _ = require("coversearch/i18n")

local Tile = InputContainer:extend{}

function Tile:init()
    local content_width = self.width - 16
    local image
    if self.bitmap then
        image = ImageWidget:new{ image = self.bitmap, image_disposable = true,
            width = self.bitmap:getWidth(), height = self.bitmap:getHeight() }
    else
        image = TextWidget:new{ text = _("Unavailable"), face = Font:getFace("smallinfofont", 16), max_width = content_width }
    end
    local content = VerticalGroup:new{
        CenterContainer:new{ dimen = Geom:new{ w = content_width, h = self.image_height }, image },
    }
    local dimensions = self.info.width and string.format("%d × %d px", self.info.width, self.info.height) or _("Download failed")
    for _, text in ipairs({ "#" .. self.index .. " · " .. self.item.source, dimensions, self.item.title }) do
        local label = TextWidget:new{ text = text, face = Font:getFace("smallinfofont", 16), max_width = content_width }
        content[#content + 1] = CenterContainer:new{ dimen = Geom:new{ w = content_width, h = label:getSize().h }, label }
    end
    self[1] = FrameContainer:new{ margin = 3, padding = 4, bordersize = 1, content }
    self.dimen = self[1]:getSize()
    if Device:isTouchDevice() then
        self.ges_events.OpenCover = { GestureRange:new{ ges = "tap", range = self.dimen } }
    end
end

function Tile:onOpenCover()
    self.callback()
    return true
end

return Tile
