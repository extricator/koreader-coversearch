-- Run from the root of an unpacked KOReader Linux runtime. No display is needed.
-- ./luajit /path/to/tests/runtime.lua /path/to/project /path/to/a/cover.jpg
local project, fixture = assert(arg[1], "project path required"), assert(arg[2], "cover fixture required")
require("setupkoenv")
package.path = project .. "/coversearch.koplugin/?.lua;" .. package.path
require("logger"):setLevel(require("logger").levels.warn)
G_defaults = require("luadefaults"):open("/tmp/coversearch-runtime-defaults.lua")
G_reader_settings = require("luasettings"):open("/tmp/coversearch-runtime-settings.lua")
G_reader_settings:saveSetting("language", arg[4] or "C")
require("gettext").changeLang(arg[4] or "C")
local translate = require("coversearch/i18n")
G_reader_settings:saveSetting("document_metadata_folder", "doc")
einkfb = require("ffi/framebuffer")
einkfb.dummy = true
local Device = require("device")
Device.screen:init()
if arg[3] == "landscape" then Device.screen:setRotationMode(1) end
Device.input.dummy = true
if arg[3] == "keys" then Device.isTouchDevice = function() return false end end
require("document/canvascontext"):init(Device)

local UIManager = require("ui/uimanager")
local DocSettings = require("docsettings")
local Images = require("coversearch/images")
local Model = require("coversearch/model")
local HTTP = require("coversearch/http")
local Trapper = require("ui/trapper")
local file = assert(io.open(fixture, "rb"))
local image_data = file:read("*a"); file:close()
local image_info = assert(Images.inspect(image_data))
local lfs = require("libs/libkoreader-lfs")
local root = "/tmp/coversearch-runtime-book"
require("util").makePath(root)
local book = root .. "/test.epub"
file = assert(io.open(book, "wb")); assert(file:write("test ebook must remain unchanged")); file:close()
local ui = {
    document = { file = book }, doc_props = { title = "Dune", authors = "Frank Herbert" },
    doc_settings = DocSettings:open(book),
    menu = { registerToMainMenu = function() end },
}
ui.doc_settings:flush()
local Plugin = dofile(project .. "/coversearch.koplugin/main.lua")
local plugin = Plugin:new{ ui = ui }
local menus = {}; plugin:addToMainMenu(menus)
assert(menus.coversearch.sub_item_table[1].text)
local sources = menus.coversearch.sub_item_table[3].sub_item_table
local expected_sources = { "Open Library", "Apple Books", "Goodreads", "Amazon", "OverDrive" }
assert(#sources == #expected_sources)
for index, name in ipairs(expected_sources) do assert(sources[index].text == name) end
print("PASS real stable plugin initialization and menu registration")

-- Handcrafted fixtures use calibre's EPUB 2/3 identifier representations.
local registry = require("document/documentregistry")
for _, version in ipairs({ 2, 3 }) do
    local document = assert(registry:openDocument(project .. "/tests/fixtures/calibre-epub" .. version .. ".epub"))
    assert(document:loadDocument(false))
    assert(Model.metadata(document:getProps()).isbn == "9780441172719")
    document:close()
end
print("PASS native ISBN extraction from calibre-style EPUB 2 and EPUB 3 metadata")

-- Keep real decoding/widgets/storage, but stub networking and subprocess waits for deterministic UI checks.
local old_get = HTTP.get
HTTP.get = function() return image_data end
local old_run = Trapper.dismissableRunInSubprocess
Trapper.dismissableRunInSubprocess = function(_, task) return true, task() end
local session = {
    book_file = book, query = { title = "Dune" }, dir = plugin.cache_root .. "/session-100-1",
    candidates = {
        { source = "Test source", title = "A test cover", author = "Test author", url = "https://example.com/1.jpg", page = "https://example.com/book" },
        { source = "Another source", title = "Another test cover", author = "Test author", url = "https://example.com/2.jpg", page = "https://example.com/book" },
    }, statuses = { "Test source: 2 candidates" }, downloads = {}, index = 1,
}
require("util").makePath(session.dir)
plugin.session = session
local function top() return UIManager._window_stack[#UIManager._window_stack].widget end
local function button(widget, text)
    for _, row in ipairs(widget.buttons) do for _, b in ipairs(row) do if b.text == translate(text) or b.id == text:lower() then return b end end end
    error("Missing button: " .. text)
end
-- Exercise automatic ISBN discovery, the native checkbox, and the actual submitted query.
plugin.session = nil
local NetworkMgr = require("ui/network/manager")
local old_online, old_search, old_props = NetworkMgr.runWhenOnline, plugin.search, ui.doc_props
local submitted
NetworkMgr.runWhenOnline = function(_, task) task() end
plugin.search = function(_, _, query) submitted = query end
local function searchForm(props, use_isbn)
    ui.doc_props = props; submitted = nil
    plugin:onCoverSearch()
    local form = top()
    assert(#form:getFields() == 3, "ISBN must be an editable field")
    local checkbox = form.isbn_checkbox
    local isbn_field = form.input_fields[3]
    assert(not checkbox.checked and checkbox.enabled and isbn_field.readonly and isbn_field._frame.dim)
    UIManager:forceRePaint()
    local focused = form._input_widget
    isbn_field:onTapTextBox(nil, { pos = isbn_field.dimen })
    isbn_field:onHoldTextBox()
    local saved_isbn = isbn_field:getText()
    isbn_field:addChars("9")
    assert(isbn_field:getText() == saved_isbn, "Disabled field must ignore keyboard edits")
    assert(form._input_widget == focused and top() == form, "Disabled field must consume taps and holds")
    for _, row in ipairs(form.layout) do assert(row[1] ~= isbn_field, "Disabled field must skip key focus") end
    if arg[4] == "es" then
        assert(form.title == "Buscar portadas" and form.fields[1].description == "Título")
        assert(form.fields[2].description == "Autor (opcional)")
        local frame = form.dialog_frame:getSize()
        assert(frame.w <= Device.screen:getWidth() and frame.h <= Device.screen:getHeight())
    end
    if use_isbn then
        form.selected = { x = 2, y = #form.layout }
        local focused_button = form:getFocusItem()
        checkbox:onTapCheckButton()
        assert(not isbn_field.readonly and not isbn_field._frame.dim and form.layout[4][1] == isbn_field)
        assert(form:getFocusItem() == focused_button, "Changing field focus rows must preserve button focus")
    end
    button(form, "Search").callback()
    assert(submitted)
    return checkbox
end
local checkbox = searchForm({ title = "Dune", authors = "Frank Herbert", identifiers = "urn:isbn:9780441172719" }, true)
assert(checkbox.checked and submitted.isbn == "9780441172719")
-- ReaderUI saves raw properties, then uses BookInfo's customized copy without identifiers.
local BookInfo = require("apps/filemanager/filemanagerbookinfo")
local original_props = { title = "Original title", authors = "Original author",
    identifiers = "MOBI-ASIN:B072P65L3N\nISBN:9780876127773\nuuid:ec325383-fd1d-4c89-a804-dfdca76b3c16" }
local customized_props = BookInfo.extendProps(original_props)
assert(customized_props.identifiers == nil)
customized_props.title, customized_props.authors = "Edited title", "Edited author"
ui.doc_settings:saveSetting("doc_props", original_props)
checkbox = searchForm(customized_props, true)
assert(checkbox.checked and submitted.isbn == "9780876127773")
assert(submitted.title == "Edited title" and submitted.author == "Edited author")
assert(customized_props.identifiers == nil, "Discovery must not mutate ReaderUI's properties")
ui.doc_settings:delSetting("doc_props")
print("PASS ISBN discovery through ReaderUI's customized metadata while preserving title/author")
checkbox = searchForm({ title = "Dune", authors = "Frank Herbert", isbn = "0441172717" })
assert(not checkbox.checked and submitted.isbn == "" and submitted.title == "Dune")
checkbox = searchForm({ title = "Dune", authors = "Frank Herbert" })
assert(checkbox.enabled and not checkbox.checked and submitted.isbn == "")
checkbox = searchForm({ title = "Dune", authors = "Frank Herbert", isbn = "9780441172718" })
assert(checkbox.enabled and submitted.isbn == "")
checkbox = searchForm({ title = "Dune", authors = "Frank Herbert", isbn = "ISBN–13: 978–0–441–17271–9" }, true)
assert(checkbox.checked and submitted.isbn == "9780441172719")
checkbox = searchForm({ title = "Dune", authors = "Frank Herbert",
    identifiers = { asin = "080442957X", isbn = "9780441172719" } }, true)
assert(checkbox.checked and submitted.isbn == "9780441172719")
-- A book with no identifier supports manual ISBN-only searches and rejects bad input.
ui.doc_props = { title = "", authors = "" }; submitted = nil
plugin:onCoverSearch()
local manual_form = top()
manual_form.input_fields[1]:setText("")
assert(manual_form.input_fields[3]:getText() == "")
UIManager:forceRePaint()
manual_form.isbn_checkbox:onTapCheckButton()
for _, invalid in ipairs({ "", "9780441172718", "ASIN:0441172717" }) do
    manual_form.input_fields[3]:setText(invalid)
    button(manual_form, "Search").callback()
    assert(not submitted and top().text == translate("Enter a valid ISBN-10 or ISBN-13."))
    UIManager:close(top())
    assert(top() == manual_form, "Invalid input must preserve the form")
end
manual_form.input_fields[3]:setText("ISBN–10: 0–8044–2957–x")
UIManager:forceRePaint()
manual_form.isbn_checkbox:onTapCheckButton()
assert(manual_form.input_fields[3]:getText() == "ISBN–10: 0–8044–2957–x")
UIManager:forceRePaint()
manual_form.isbn_checkbox:onTapCheckButton()
button(manual_form, "Search").callback()
assert(submitted.isbn == "080442957X" and submitted.title == "")
print("PASS manual ISBN input, validation, normalization, preserved opt-out value, and ISBN-only search")
-- A chooser changes only the selected ISBN; title, author, and opt-out survive.
ui.doc_props = { title = "Dune", authors = "Frank Herbert", isbn = "0441172717",
    identifiers = "isbn:9780441172719\nisbn:9780441013593" }
plugin:onCoverSearch()
local form = top()
assert(#form._added_widgets == 1)
local isbn_box, choose = form.isbn_checkbox, form.isbn_chooser
assert(choose.text == string.format(translate("Choose ISBN · %d found"), 2))
assert(not choose.enabled and form.input_fields[3]:getText() == "0441172717")
choose.callback()
assert(top() == form, "Disabled chooser must not open")
form:onCloseKeyboard()
UIManager:forceRePaint()
Device.screen:shot("/tmp/coversearch-isbn-disabled" .. (arg[4] == "es" and "-es" or "") .. ".png")
form.input_fields[1]:setText("Edited title")
form.input_fields[2]:setText("Edited author")
UIManager:forceRePaint()
isbn_box:onTapCheckButton()
choose.callback()
local isbn_picker = top()
UIManager:forceRePaint()
local radio = isbn_picker.widget_frame[1][2][1][1]
radio.radio_buttons_layout[2][1]:onTapCheckButton()
isbn_picker.layout[#isbn_picker.layout][1].callback()
assert(form.input_fields[3]:getText() == "0441172717", "Cancel must retain the input")
choose.callback()
isbn_picker = top()
UIManager:forceRePaint()
radio = isbn_picker.widget_frame[1][2][1][1]
radio.radio_buttons_layout[2][1]:onTapCheckButton()
isbn_picker.layout[#isbn_picker.layout][2].callback()
assert(form.input_fields[3]:getText() == "9780441013593" and isbn_box.checked)
-- Rebuilding after a keyboard-height change must preserve every field and the toggle.
G_reader_settings:saveSetting("virtual_keyboard_enabled", true)
form.skip_first_show_keyboard = nil
form:onSwitchFocus(form.input_fields[3])
UIManager:forceRePaint()
assert(form:isKeyboardVisible(), "Exercise a visible native keyboard")
local isbn_field, keyboard = form.input_fields[3], form._input_widget.keyboard
assert(isbn_field.dimen.y >= 0 and isbn_field.dimen.y + isbn_field.dimen.h <= keyboard.dimen.y,
    "The active ISBN field must fit above the keyboard")
if arg[3] == "landscape" then
    assert(form.cropping_widget, "Short viewports must scroll")
    form.selected = { x = 1, y = 4 }
    for index = 1, 2 do
        form:onFocusMove({ 0, 1 })
        UIManager:forceRePaint()
        local control = form:getFocusItem()
        assert(control.dimen.y >= 0 and control.dimen.y + control.dimen.h <= keyboard.dimen.y,
            "Key navigation must scroll the chooser and buttons above the keyboard")
    end
    form:onSwitchFocus(form.input_fields[3])
    UIManager:forceRePaint()
end
Device.screen:shot("/tmp/coversearch-isbn-editing" .. (arg[3] == "landscape" and "-landscape" or "") .. ".png")
form:onKeyboardHeightChanged()
UIManager:forceRePaint()
assert(form.input_fields[3].dimen.y + form.input_fields[3].dimen.h <= form._input_widget.keyboard.dimen.y)
assert(form:getFields()[1] == "Edited title" and form:getFields()[2] == "Edited author")
assert(form:getFields()[3] == "9780441013593" and form.isbn_checkbox.checked and choose.enabled)
UIManager:forceRePaint()
form.selected = { x = 1, y = 4 }
form.isbn_checkbox:onTapCheckButton()
assert(not form.use_isbn and form.input_fields[3].readonly and not choose.enabled)
assert(form:getFocusItem() == form.isbn_checkbox, "Disabling a focused ISBN must retain usable key focus")
assert(not form:isKeyboardVisible() and form.focused_field_idx ~= 3)
G_reader_settings:delSetting("virtual_keyboard_enabled")
form:onKeyboardHeightChanged()
assert(not form.isbn_checkbox.checked and form:getFields()[3] == "9780441013593")
UIManager:forceRePaint()
form.isbn_checkbox:onTapCheckButton()
UIManager:forceRePaint()
Device.screen:shot("/tmp/coversearch-isbn-search" .. (arg[4] == "es" and "-es" or "") .. ".png")
choose.callback()
isbn_picker = top()
UIManager:forceRePaint()
Device.screen:shot("/tmp/coversearch-isbn-choose" .. (arg[4] == "es" and "-es" or "") .. ".png")
assert(isbn_picker.widget_frame:getSize().h <= Device.screen:getHeight())
isbn_picker:onClose()
button(form, "Search").callback()
assert(submitted.title == "Edited title" and submitted.author == "Edited author" and submitted.isbn == "9780441013593")
ui.doc_props = { isbn = "0441172717", identifiers = "isbn:9780441172719" }
plugin:onCoverSearch()
assert(not top().isbn_chooser, "Equivalent ISBNs should not show a chooser")
button(top(), "Cancel").callback()
print("PASS native ISBN picker, keyboard rebuilds, disabled controls, preserved edits, and equivalent grouping")
local choices = {}
for index = 1, 24 do
    choices[index] = {{ text = "9780441172719", provider = tostring(index), checked = index == 1 }}
end
local large_picker = require("coversearch/dialogs").radio{
    title_text = translate("Choose ISBN"), radio_buttons = choices,
    width = math.floor(Device.screen:getWidth() * 0.8),
}
UIManager:show(large_picker)
UIManager:forceRePaint()
assert(large_picker.cropping_widget and large_picker.widget_frame:getSize().h <= Device.screen:getHeight() * 0.91)
large_picker:moveFocusTo(1, 24)
large_picker:onFocusMove({ 0, 0 })
UIManager:forceRePaint()
assert(large_picker.cropping_widget._scroll_offset_y > 0, "Key focus must scroll to off-screen ISBNs")
large_picker:onClose()
print("PASS bounded long ISBN chooser and keyboard focus scrolling")
NetworkMgr.runWhenOnline, plugin.search, ui.doc_props = old_online, old_search, old_props
print("PASS ISBN prefill, explicit opt-in, disabled touch/key input, and submitted queries")
plugin.session = session
for index = 3, 6 do
    session.candidates[index] = { source = "Test source " .. index, title = "Test cover " .. index,
        author = "Test author", url = "https://example.com/" .. index .. ".jpg", page = "https://example.com/book" }
end
plugin:showGrid(session, 1)
local grid = top()
assert(grid.title:find(string.format(translate("Book covers · page %d / %d"), 1, 2), 1, true))
local columns = Device.screen:getWidth() > Device.screen:getHeight() and 4 or 2
assert(#grid._added_widgets[1] == math.ceil(4 / columns), "Wrong number of thumbnail rows")
assert(session.downloads[4].width == image_info.width)
UIManager:forceRePaint()
for _, row in ipairs(grid._added_widgets[1]) do
    for _, tile in ipairs(row) do
        assert(not tile[1][1][3][1]:isTruncated(), "Downloaded resolutions must remain fully visible")
    end
end
Device.screen:shot("/tmp/coversearch-grid" .. (arg[3] == "landscape" and "-landscape" or "") .. ".png")
local navigation = grid.buttons[#grid.buttons]
assert(navigation[1].text == translate("Summary") and navigation[2].text == "‹ " .. translate("Previous")
    and navigation[3].text == translate("Next") .. " ›" and navigation[4].text == translate("Close"))
if arg[4] == "es" then
    assert(menus.coversearch.text == "Buscar portadas")
    assert(navigation[1].text == "Resumen" and navigation[3].text == "Siguiente ›")
    assert(dofile(project .. "/coversearch.koplugin/_meta.lua").fullname == "Buscar portadas")
end
local previous, next_button = grid:getButtonById("previous"), grid:getButtonById("next")
local content = grid:getContentSize()
assert(math.abs((previous.dimen.x + next_button.dimen.x + next_button.dimen.w) / 2 - content.x - content.w / 2) <= 2,
    "Navigation buttons must be centered together")
button(grid, "Summary").callback()
local status = top()
UIManager:forceRePaint()
assert(status:getContentSize().w <= Device.screen:getWidth() and status:getContentSize().h <= Device.screen:getHeight())
assert(status.height < Device.screen:getHeight() * 0.9, "Short source status should fit its text")
status:onClose()
UIManager:forceRePaint()
local first_tile = grid._added_widgets[1][1][1]
assert(grid:getContentSize().h <= Device.screen:getHeight(), "Grid exceeds screen height")
if Device:isTouchDevice() then
    grid:handleEvent(require("ui/event"):new("Gesture", {
        ges = "tap", pos = require("ui/geometry"):new{ x = first_tile.dimen.x + 10, y = first_tile.dimen.y + 10 },
    }))
else
    first_tile:onOpenCover()
end
local picker = top()
assert(picker.title:find(image_info.width .. " × " .. image_info.height, 1, true))
assert(button(picker, "Use this cover").enabled)
UIManager:forceRePaint()
assert(picker:getContentSize().w <= Device.screen:getWidth() and picker:getContentSize().h <= Device.screen:getHeight())
Device.screen:shot("/tmp/coversearch-picker.png")
print("PASS real stable 2×2 grid, thumbnail tap, native image decode, and actual-resolution label")
button(picker, "Details").callback()
local details = top()
UIManager:forceRePaint()
assert(details:getContentSize().w <= Device.screen:getWidth() and details:getContentSize().h <= Device.screen:getHeight())
details:onClose()
print("PASS centered labeled navigation, search summary, and bounded cover-details windows")
button(picker, "Preview").callback()
local viewer = top()
assert(viewer.file == session.downloads[1].path)
UIManager:forceRePaint()
viewer:onClose()
print("PASS full-screen native ImageViewer preview")
button(picker, "Next").callback()
picker = top()
assert(picker.title:find("2 / 6", 1, true))
assert(button(picker, "Next").enabled)
print("PASS picker navigation")
button(picker, "Back to results").callback()
grid = top()
button(grid, "Next").callback()
grid = top()
assert(grid.title:find(string.format(translate("Book covers · page %d / %d"), 2, 2), 1, true))
assert(#grid._added_widgets[1] == 1 and not button(grid, "Next").enabled)
grid._added_widgets[1][1][2]:onOpenCover()
picker = top()
assert(picker.title:find("6 / 6", 1, true))
assert(not button(picker, "Next").enabled)
print("PASS grid pagination, back navigation, and numbered selection")
button(picker, "Use this cover").callback()
assert(DocSettings:findCustomCoverFile(book))
assert(plugin.session == nil)
file = assert(io.open(book, "rb")); assert(file:read("*a") == "test ebook must remain unchanged"); file:close()
print("PASS actual sidecar cover commit and ebook preservation")
-- Dismiss the success message then use the real reset confirmation.
UIManager:close(top())
plugin:confirmReset()
local confirm = top()
button(confirm, "Cancel").callback()
assert(DocSettings:findCustomCoverFile(book), "Cancelling restore must preserve the chosen cover")
plugin:confirmReset()
confirm = top()
button(confirm, "Restore").callback()
assert(DocSettings:findCustomCoverFile(book) == nil)
print("PASS content-sized restore confirmation: cancel preserves the cover, restore removes it")
while #UIManager._window_stack > 0 do UIManager:close(top()) end
local fallback_session = { dir = plugin.cache_root .. "/session-105-1", candidates = {{
    url = "https://example.com/large.jpg", fallback_url = "https://example.com/small.jpg",
}} }
require("util").makePath(fallback_session.dir)
HTTP.get = function(_, url) if url:find("large", 1, true) then error("HTTP 404") end; return image_data end
local fallback_result = plugin:fetchCandidate(fallback_session, 1)
assert(fallback_result.path and fallback_result.download_url == "https://example.com/small.jpg")
plugin:finishSession(fallback_session)
print("PASS missing large cover falls back to the catalog-provided image")
-- Verify unreadable server responses cannot become cover overrides.
local invalid_session = {
    book_file = book, dir = plugin.cache_root .. "/session-102-1", statuses = {}, index = 1, downloads = {},
    candidates = {{ source = "Broken source", title = "Unavailable cover", author = "", url = "https://example.com/error.jpg" }},
}
require("util").makePath(invalid_session.dir)
HTTP.get = function() return "<html>Blocked by source</html>" end
plugin.session = invalid_session
plugin:showGrid(invalid_session, 1)
grid = top(); grid._added_widgets[1][1][1]:onOpenCover()
picker = top(); assert(not button(picker, "Use this cover").enabled)
picker:onClose()
assert(plugin.session == nil)
print("PASS failed downloads display safely and cannot be applied")
HTTP.get = old_get
Trapper.dismissableRunInSubprocess = old_run
-- Exercise the actual native subprocess and cancellation path (not the deterministic stub).
local slow_session = {
    book_file = book, dir = plugin.cache_root .. "/session-103-1", downloads = {},
    candidates = {{ source = "Slow source", url = "https://example.com/slow.jpg" }},
}
require("util").makePath(slow_session.dir)
plugin.session = slow_session
HTTP.get = function() require("socket").sleep(2); return image_data end
local cancelled = false
UIManager:scheduleIn(0.15, function()
    local trap = top()
    assert(trap.modal and trap.frame and not trap.invisible and not trap.resend_event)
    local hint = Device:isTouchDevice() and translate("Tap to cancel") or translate("Any key cancels")
    assert(trap.text == translate("Downloading cover…") .. "\n" .. hint)
    UIManager:forceRePaint()
    if Device:isTouchDevice() then
        UIManager:handleInputEvent(require("ui/event"):new("Gesture", { ges = "tap",
            pos = require("ui/geometry"):new{ x = trap.frame.dimen.x + 10, y = trap.frame.dimen.y + 10 } }))
    else
        UIManager:handleInputEvent(require("ui/event"):new("KeyPress", require("device/key"):new("Back", {})))
    end
end)
Trapper:wrap(function()
    local result = plugin:download(slow_session, 1)
    assert(result == nil)
    plugin:finishSession(slow_session)
    assert(plugin.session == nil and lfs.attributes(slow_session.dir) == nil)
    cancelled = true
end)
UIManager:runOnce()
assert(cancelled, "Cancellation did not complete")
HTTP.get = old_get
print("PASS actual native subprocess cancellation and session cleanup")
local Providers = require("coversearch/providers")
local old_provider_search = Providers.search
Providers.search = function() require("socket").sleep(2); return { candidates = {}, statuses = {} } end
local search_cancelled = false
UIManager:scheduleIn(0.05, function()
    local trap = top()
    local hint = Device:isTouchDevice() and translate("Tap to cancel") or translate("Any key cancels")
    assert(trap.modal and trap.frame and not trap.invisible)
    assert(trap.text == translate("Searching cover sources…") .. "\n" .. hint)
    if Device:isTouchDevice() then
        UIManager:handleInputEvent(require("ui/event"):new("Gesture", {
            ges = "tap", pos = require("ui/geometry"):new{ x = 1, y = 1 },
        }))
    else
        UIManager:handleInputEvent(require("ui/event"):new("KeyPress", require("device/key"):new("Back", {})))
    end
end)
Trapper:wrap(function()
    plugin:search(book, { title = "Dune", author = "Frank Herbert", isbn = "" })
    assert(not plugin.searching and not plugin.session and #UIManager._window_stack == 0)
    search_cancelled = true
end)
UIManager:runOnce()
Providers.search = old_provider_search
assert(search_cancelled)
print("PASS provider search uses the visible modal and dispatched cancellation clears its busy state")

-- Cancellation must work during the second ISBN request inside the real subprocess.
local original_json, original_prefs = HTTP.json, plugin.prefs
local marker = root .. "/equivalent-search-started"
os.remove(marker)
local enabled = {}
for _, source in ipairs(Providers.list) do enabled[source.id] = source.id == "openlibrary" end
plugin.prefs = { enabled = enabled, results = 3, country = "US", amazon_domain = "com" }
HTTP.json = function(_, url)
    if url:find("isbn=9780441172719", 1, true) then return { docs = {} } end
    assert(url:find("isbn=0441172717", 1, true))
    local flag = assert(io.open(marker, "wb")); flag:write("started"); flag:close()
    require("socket").sleep(2)
    return { docs = {{ title = "Dune", cover_i = 123 }} }
end
local function cancelEquivalent()
    if not lfs.attributes(marker) then UIManager:scheduleIn(0.025, cancelEquivalent); return end
    local trap = top()
    assert(trap.modal and trap.frame and not trap.invisible and not trap.resend_event)
    if Device:isTouchDevice() then
        UIManager:handleInputEvent(require("ui/event"):new("Gesture", {
            ges = "tap", pos = require("ui/geometry"):new{ x = 1, y = 1 },
        }))
    else
        UIManager:handleInputEvent(require("ui/event"):new("KeyPress", require("device/key"):new("Back", {})))
    end
end
local equivalent_cancelled = false
UIManager:scheduleIn(0.025, cancelEquivalent)
Trapper:wrap(function()
    plugin:search(book, Model.metadata({ isbn = "ISBN–13: 978–0–441–17271–9" }))
    assert(lfs.attributes(marker) and not plugin.searching and not plugin.session and #UIManager._window_stack == 0)
    equivalent_cancelled = true
end)
UIManager:runOnce()
HTTP.json, plugin.prefs = original_json, original_prefs
os.remove(marker)
assert(equivalent_cancelled)
print("PASS equivalent-ISBN request uses the same modal and can be cancelled through real touch/key input")
print("All stable runtime checks passed")
