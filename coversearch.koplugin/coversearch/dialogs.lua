-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Content-sized native dialogs, bounded by the current screen dimensions.
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local CheckButton = require("ui/widget/checkbutton")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local IconWidget = require("ui/widget/iconwidget")
local InfoMessage = require("ui/widget/infomessage")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local RadioButtonWidget = require("ui/widget/radiobuttonwidget")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Geom = require("ui/geometry")
local FocusManager = require("ui/widget/focusmanager")
local Device = require("device")
local Screen = Device.screen
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextViewer = require("ui/widget/textviewer")
local TextWidget = require("ui/widget/textwidget")
local Trapper = require("ui/trapper")
local TrapWidget = require("ui/widget/trapwidget")
local UIManager = require("ui/uimanager")
local _ = require("coversearch/i18n")
local Dialogs = {}

local function textWidth(text, face, limit, bold)
    local width = 1
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        local label = TextWidget:new{ text = line, face = face, bold = bold, max_width = limit }
        width = math.max(width, label:getWidth())
        label:free()
    end
    return math.min(width + Screen:scaleBySize(4), limit)
end

local function buttonWidth(buttons)
    local width = Screen:scaleBySize(100)
    for _, row in ipairs(buttons or {}) do
        local cell = 0
        for _, button in ipairs(row) do
            cell = math.max(cell, textWidth(button.text, Font:getFace(button.font_face or "cfont", button.font_size or 20), Screen:getWidth(), button.font_bold ~= false))
        end
        width = math.max(width, (cell + 2 * Size.padding.button) * #row + #row - 1)
    end
    return width
end

function Dialogs.info(text)
    local face = Font:getFace("infofont")
    local limit = math.floor(Screen:getWidth() * 0.85)
    return InfoMessage:new{ text = text, face = face,
        width = math.min(textWidth(text, face, limit) + IconWidget.width, limit) }
end

-- Keep the toggle inside the field layout so keyboard-height changes rebuild it safely.
local ISBNForm = MultiInputDialog:extend{ use_isbn = false }

function ISBNForm:updateISBNFilter()
    local field = self.input_fields[3]
    local focused = self:getFocusItem()
    if not self.use_isbn and self._input_widget == field then
        self:onCloseKeyboard()
        field:unfocus()
        self._input_widget = self.input_fields[2]
        self.focused_field_idx = 2
        self._input_widget:focus()
    end
    if not self.use_isbn and focused == field then focused = self.isbn_checkbox end
    field.readonly = not self.use_isbn
    field._frame.dim = not self.use_isbn
    for index, row in ipairs(self.layout) do
        if row[1] == field then table.remove(self.layout, index); break end
    end
    if self.use_isbn then table.insert(self.layout, 4, { field }) end
    for index, row in ipairs(self.layout) do
        for column, widget in ipairs(row) do
            if widget == focused then self.selected.x, self.selected.y = column, index end
        end
    end
    if self.isbn_chooser then self.isbn_chooser:enableDisable(self.use_isbn) end
    UIManager:setDirty(self, "ui")
end

function ISBNForm:init()
    if self.cropping_widget then self.cropping_widget:reset() end
    self.cropping_widget, self._viewport_height, self._scroll_target = nil, nil, nil
    MultiInputDialog.init(self)
    local field = self.input_fields[3]
    -- Read-only InputText still supports selection menus; consume disabled taps and holds.
    for _, event in ipairs({ "onTapTextBox", "onHoldTextBox", "holdTextBox", "onFocus" }) do
        local handler = field[event]
        field[event] = function(widget, ...)
            if not self.use_isbn then return true end
            if handler then return handler(widget, ...) end
        end
    end
    self.isbn_checkbox = CheckButton:new{
        text = _("Use ISBN"), checked = self.use_isbn, parent = self,
        width = math.floor(self.width * 0.9),
        callback = function()
            self.use_isbn = self.isbn_checkbox.checked
            self._scroll_target = self.isbn_checkbox
            self:updateISBNFilter()
        end,
    }
    local group = self.dialog_frame[1]
    for index, container in ipairs(group) do
        if container[1] == field then
            table.insert(group, index, CenterContainer:new{
                dimen = Geom:new{ w = self.width, h = self.isbn_checkbox:getSize().h }, self.isbn_checkbox,
            })
            break
        end
    end
    table.insert(self.layout, 3, { self.isbn_checkbox })
    group:resetLayout()
    self:updateISBNFilter()
end

function ISBNForm:onSwitchFocus(field)
    if field == self.input_fields[3] and not self.use_isbn then return end
    self._scroll_target = field
    return MultiInputDialog.onSwitchFocus(self, field)
end

function ISBNForm:onFocusMove(args)
    local result = FocusManager.onFocusMove(self, args)
    self._scroll_target = self:getFocusItem()
    return result
end

function ISBNForm:paintTo(bb, x, y)
    local available = Screen:getHeight() - (self:isKeyboardVisible() and self._input_widget:getKeyboardDimen().h or 0)
    local size = self.dialog_frame:getSize()
    local changed = self._viewport_height ~= available or self._content_height ~= size.h
    if changed then
        if self.cropping_widget then self.cropping_widget:reset() end
        self.cropping_widget = nil
        local content = self.dialog_frame
        if size.h > available then
            content = ScrollableContainer:new{
                dimen = Geom:new{ w = size.w + ScrollableContainer:getScrollbarWidth(), h = available },
                show_parent = self, self.dialog_frame,
            }
            self.cropping_widget = content
        end
        self[1] = CenterContainer:new{ dimen = Geom:new{ w = Screen:getWidth(), h = available }, content }
        self._viewport_height, self._content_height = available, size.h
    end
    MultiInputDialog.paintTo(self, bb, x, y)
    local scroll, target = self.cropping_widget, self._scroll_target or self._input_widget
    if scroll and target.dimen and self.dialog_frame.dimen and (changed or target ~= self._scrolled_target) then
        local offset = target.dimen.y - self.dialog_frame.dimen.y
        local current = scroll._scroll_offset_y
        if offset < current then scroll:_scrollBy(0, offset - current)
        elseif offset + target.dimen.h > current + available then
            scroll:_scrollBy(0, offset + target.dimen.h - current - available)
        end
        if current ~= scroll._scroll_offset_y then MultiInputDialog.paintTo(self, bb, x, y) end
    end
    self._scrolled_target = target
end

function Dialogs.form(options, extra_text)
    local limit = math.floor(Screen:getWidth() * 0.9)
    local field_face = Font:getFace("x_smallinfofont")
    local width = math.max(Screen:scaleBySize(260), buttonWidth(options.buttons),
        textWidth(options.title, Font:getFace("x_smalltfont"), limit) + 2 * IconWidget.width)
    for _, field in ipairs(options.fields) do
        width = math.max(width, (textWidth(field.text, field_face, limit) + 2 * Size.padding.default) / 0.9,
            (textWidth(field.description, field_face, limit) + 2 * Size.padding.default) / 0.9)
    end
    if extra_text then
        width = math.max(width, (textWidth(extra_text, Font:getFace("smallinfofont"), limit) + Screen:scaleBySize(36)) / 0.9)
    end
    options.width = math.floor(math.min(width, limit))
    return (options.isbn_filter and ISBNForm or MultiInputDialog):new(options)
end

function Dialogs.buttons(options, content_width)
    local limit = options.width or math.floor(Screen:getWidth() * 0.94)
    local padding = 2 * (ButtonDialog.info_padding + ButtonDialog.info_margin)
    options.width = limit
    options.shrink_unneeded_width = true
    options.shrink_min_width = math.min(limit - 2 * Size.border.window - 2 * Size.padding.button,
        math.max(textWidth(options.title, options.info_face or Font:getFace("infofont"), limit) + padding,
            (content_width or 0) + padding, Screen:scaleBySize(100)))
    return ButtonDialog:new(options)
end

function Dialogs.confirm(options)
    local dialog
    dialog = Dialogs.buttons{
        title = options.text, title_align = "left",
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() dialog:onClose() end },
            { text = options.ok_text, callback = function() options.ok_callback(); UIManager:close(dialog) end },
        }},
    }
    return dialog
end

function Dialogs.radio(options)
    local picker = RadioButtonWidget:new(options)
    local group = picker.widget_frame[1]
    local content = group[2][1]
    local limit = math.floor(Screen:getHeight() * 0.9)
    local overhead = picker.widget_frame:getSize().h - group[2]:getSize().h
    local height = math.max(Screen:scaleBySize(40), limit - overhead)
    if group[2]:getSize().h > height then
        local scroll = ScrollableContainer:new{
            dimen = Geom:new{ w = content:getSize().w + ScrollableContainer:getScrollbarWidth(), h = height },
            show_parent = picker, content,
        }
        picker.cropping_widget = scroll
        group[2] = CenterContainer:new{ dimen = Geom:new{ w = picker.width, h = height }, scroll }
        group:resetLayout()
        picker.onFocusMove = function(self, args)
            local result = FocusManager.onFocusMove(self, args)
            local focused = self:getFocusItem()
            if focused and focused.provider and focused.dimen then
                local offset = focused.dimen.y - scroll.dimen.y + scroll._scroll_offset_y
                scroll:_scrollBy(0, offset, true)
            end
            return result
        end
    end
    return picker
end

function Dialogs.viewer(options)
    local settings = G_reader_settings:readSetting("textviewer_text_types", {})
    local general = settings.general or TextViewer.text_types.general
    local face = Font:getFace(general.monospace_font and "smallinfont" or "x_smallinfofont", general.font_size)
    local limit = math.floor(Screen:getWidth() * 0.94)
    local padding = 2 * (TextViewer.text_padding + TextViewer.text_margin)
        + ScrollTextWidget.scroll_bar_width + ScrollTextWidget.text_scroll_span
    local controls = buttonWidth({{ { text = _("Find") }, { text = "↖" }, { text = "↘" }, { text = _("Close") } }})
    options.width = math.floor(math.min(limit, math.max(controls + 2 * Size.padding.default,
        textWidth(options.title, Font:getFace("x_smalltfont"), limit) + 2 * IconWidget.width,
        textWidth(options.text, face, limit) + padding)))
    options.height = math.floor(Screen:getHeight() * 0.9)
    options.title_multilines = true
    local viewer = TextViewer:new(options)
    local height = math.min(options.height, viewer.titlebar:getHeight() + viewer.button_table:getSize().h
        + 2 * (viewer.text_padding + viewer.text_margin) + viewer.box_widget:getAllLineCount() * viewer.box_widget:getLineHeight()
        + Screen:scaleBySize(4))
    if height < viewer.height then
        viewer:free()
        viewer.height = math.ceil(height)
        viewer:init(true)
    end
    return viewer
end

function Dialogs.run(task, text)
    text = text .. "\n" .. (Device:isTouchDevice() and _("Tap to cancel") or _("Any key cancels"))
    -- A visible modal catches input across the screen, including browser controls
    -- behind the message. The cancellation event must never be replayed there.
    local trap = TrapWidget:new{ resend_event = false }
    trap.invisible = nil
    trap.text = text
    local screen = Screen:getSize()
    local label = TextBoxWidget:new{ text = text, face = trap.face,
        alignment = "center", width = textWidth(text, trap.face, math.floor(screen.w * 0.85)) }
    trap.frame = FrameContainer:new{ background = Blitbuffer.COLOR_WHITE,
        bordersize = Size.border.window, radius = Size.radius.window,
        margin = 0, padding = Size.padding.large, label }
    trap[1] = CenterContainer:new{ dimen = screen, trap.frame }
    UIManager:show(trap)
    UIManager:forceRePaint()
    local completed, result = Trapper:dismissableRunInSubprocess(task, trap)
    UIManager:close(trap)
    return completed, result
end

return Dialogs
