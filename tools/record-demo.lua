-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Capture native KOReader widgets with saved covers, without relying on live catalogs.
-- Run from a disposable KOReader runtime: ./luajit script.lua project fixture_dir output_dir
local project, fixtures, output = assert(arg[1]), assert(arg[2]), assert(arg[3])
require("setupkoenv")
package.path = project .. "/coversearch.koplugin/?.lua;" .. package.path
G_defaults = require("luadefaults"):open(output .. "/defaults.lua")
G_reader_settings = require("luasettings"):open(output .. "/settings.lua")
G_reader_settings:saveSetting("language", "C")
G_reader_settings:saveSetting("document_metadata_folder", "doc")
require("gettext").changeLang("C")
einkfb = require("ffi/framebuffer"); einkfb.dummy = true
local Device = require("device")
Device.screen:init(); Device.input.dummy = true
require("document/canvascontext"):init(Device)
local UIManager = require("ui/uimanager")
local Trapper = require("ui/trapper")
local ReaderMenu = require("apps/reader/modules/readermenu")
local DocSettings = require("docsettings")
local HTTP = require("coversearch/http")
local Providers = require("coversearch/providers")
local util = require("util")
util.makePath(output)
local book = output .. "/demo.epub"
local file = assert(io.open(book, "wb")); file:write("Cover Search demo book\n"); file:close()
local plugin = dofile(project .. "/coversearch.koplugin/main.lua"):new{
    ui = { document = { file = book }, doc_settings = DocSettings:open(book),
        doc_props = { title = "Dune", authors = "Frank Herbert", isbn = "9780441172719",
            identifiers = "isbn:9780441013593" },
        menu = { registerToMainMenu = function() end },
        keyselection = { stopHighlightIndicator = function() end }, handleEvent = function() end },
}
plugin.prefs = { results = 3, enabled = {}, country = "US", amazon_domain = "com" }
local background = require("ui/widget/container/inputcontainer"):new{
    dimen = Device.screen:getSize(),
    paintTo = function(_, bb) bb:fill(require("ffi/blitbuffer").COLOR_WHITE) end,
}
UIManager:show(background)

local sources = { "Open Library", "Apple Books", "Goodreads", "Amazon" }
local filenames = { "cover-ol.jpg", "cover-apple.jpg", "cover-goodreads.jpg", "cover-amazon.jpg" }
local images, candidates = {}, {}
for index, filename in ipairs(filenames) do
    file = assert(io.open(fixtures .. "/" .. filename, "rb")); images[index] = file:read("*a"); file:close()
end
for index = 1, 8 do
    candidates[index] = { title = "Dune", author = "Frank Herbert", source = sources[(index - 1) % 4 + 1],
        url = "https://example.com/" .. index .. ".jpg", page = "https://example.com/book" }
end
Providers.search = function()
    require("socket").sleep(0.3)
    return { candidates = candidates, statuses = { "Open Library: 2 candidates", "Apple Books: 2 candidates",
        "Goodreads: 2 candidates", "Amazon: 2 candidates" } }
end
HTTP.get = function(_, address)
    require("socket").sleep(0.15)
    return images[(tonumber(address:match("/(%d+)%.jpg")) - 1) % 4 + 1]
end

local frame_number = 0
local manifest = assert(io.open(output .. "/frames.tsv", "wb"))
local function top() return UIManager._window_stack[#UIManager._window_stack].widget end
local function capture(name, delay)
    frame_number = frame_number + 1
    local filename = string.format("%02d-%s.png", frame_number, name)
    UIManager:forceRePaint()
    Device.screen:shot(output .. "/" .. filename)
    manifest:write(filename, "\t", tostring(delay), "\n")
    manifest:flush()
end
local function button(label)
    for _, row in ipairs(top().buttons) do
        for _, item in ipairs(row) do if item.text == label or item.id == label:lower() then return item end end
    end
    error("Missing control: " .. label)
end
local function showMenu(open_submenu)
    local reader_menu = ReaderMenu:new{ ui = plugin.ui }
    local items = reader_menu.menu_items
    local labels = { history = "History", open_previous_document = "Open previous document",
        favorites = "Favorites", collections = "Collections", bookmark_browser = "Bookmark browser",
        book_status = "Book status", mass_storage_actions = "USB storage",
        ota_update = "Update KOReader", help = "Help", exit_menu = "Exit",
        document_settings = "Document settings", set_render_style = "Render style",
        style_tweaks = "Style tweaks", change_font = "Font", typography = "Typography",
        speed_reading_module_perception_expander = "Speed reading", highlight_options = "Highlights" }
    for id, label in pairs(labels) do items[id] = { text = label, callback = function() end } end
    require("apps/filemanager/filemanagerbookinfo"):new{ ui = plugin.ui }:addToMainMenu(items)
    plugin:addToMainMenu(items)
    local entry = items.coversearch
    reader_menu.tab_item_table = require("ui/menusorter"):sort(items, require("ui/elements/reader_menu_order"))
    local typeset_index
    for index, tab in ipairs(reader_menu.tab_item_table) do
        if tab.id == "typeset" then typeset_index = index end
    end
    reader_menu:onShowMenu(typeset_index)
    local menu = reader_menu.menu_container[1]
    if open_submenu ~= false then menu:onMenuSelect(entry) end
    return menu, entry
end

local menu, entry = showMenu(false)
capture("location", 180)
menu:onMenuSelect(entry)
capture("menu", 180)
menu:onMenuSelect(menu.item_table[1])
capture("search", 250)
local form = top()
form.isbn_checkbox:onTapCheckButton()
capture("isbn-enabled", 180)
form.isbn_chooser.callback()
capture("choose-isbn", 220)
top():onClose()
local query = form:getFields()
assert(#query == 3 and form.isbn_checkbox.checked)
UIManager:close(form)

local captured_search, captured_thumbnails = false, false
local function watchSearch()
    local widget = top()
    if widget.text and widget.text:find("Searching cover sources", 1, true) and not captured_search then
        capture("searching", 90); captured_search = true
    elseif widget.text and widget.text:find("Loading cover thumbnails", 1, true) and not captured_thumbnails then
        capture("thumbnails", 120); captured_thumbnails = true
    end
    if not captured_thumbnails then UIManager:scheduleIn(0.025, watchSearch) end
end
UIManager:scheduleIn(0.025, watchSearch)
local function record()
    plugin:search(book, { title = query[1], author = query[2], isbn = query[3] })
    assert(captured_search and captured_thumbnails and plugin.session)
    capture("results", 300)
    top()._added_widgets[1][1][2]:onOpenCover()
    capture("cover", 260)
    button("Preview").callback()
    capture("fullscreen", 250)
    top():onClose()
    button("Back to results").callback()
    capture("back", 150)
    local grid, session = top(), plugin.session
    local loading_captured = false
    UIManager:scheduleIn(0.05, function()
        assert(top().modal and top().frame and not top().invisible)
        capture("loading-page", 120); loading_captured = true
    end)
    plugin:showGrid(session, 2, grid)
    assert(loading_captured and session.page == 2)
    capture("next-page", 220)
    top()._added_widgets[1][2][1]:onOpenCover()
    capture("selected-cover", 240)
    button("Use this cover").callback()
    assert(DocSettings:findCustomCoverFile(book) and not plugin.session)
    capture("updated", 220)
    UIManager:close(top())
    menu = showMenu()
    assert(menu.item_table[2].enabled_func())
    capture("restore-menu", 160)
    menu:onMenuSelect(menu.item_table[2])
    capture("restore", 230)
    button("Restore").callback()
    assert(not DocSettings:findCustomCoverFile(book))
    capture("restored", 220)
end
local recording_error
Trapper:wrap(function()
    local ok, err = pcall(record)
    if not ok then
        recording_error = tostring(err)
        if plugin.session then plugin:finishSession(plugin.session) end
    end
    manifest:close()
    while #UIManager._window_stack > 0 do UIManager:close(top()) end
end)
UIManager:runOnce()
assert(not recording_error, recording_error)
assert(frame_number == 18, "The demo did not complete")
print("Captured " .. frame_number .. " native frames in " .. output)
