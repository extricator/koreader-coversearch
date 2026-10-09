-- Run from a disposable KOReader runtime: ./luajit script.lua project [portrait|landscape] [es]
local project = assert(arg[1])
require("setupkoenv")
package.path = project .. "/coversearch.koplugin/?.lua;" .. package.path
require("logger"):setLevel(require("logger").levels.err)
G_defaults = require("luadefaults"):open("/tmp/coversearch-menu-defaults.lua")
G_reader_settings = require("luasettings"):open("/tmp/coversearch-menu-settings.lua")
G_reader_settings:saveSetting("language", arg[3] or "C")
require("gettext").changeLang(arg[3] or "C")
einkfb = require("ffi/framebuffer"); einkfb.dummy = true
local Device = require("device")
Device.screen:init(); Device.input.dummy = true
if arg[2] == "landscape" then Device.screen:setRotationMode(1) end
require("document/canvascontext"):init(Device)
local UIManager = require("ui/uimanager")
local ReaderMenu = require("apps/reader/modules/readermenu")
local MenuSorter = require("ui/menusorter")
local order = require("ui/elements/reader_menu_order")
local _ = require("gettext")
local ui = { document = { file = "/tmp/coversearch-menu-book.epub" },
    doc_props = { title = "Dune", authors = "Frank Herbert" },
    doc_settings = require("luasettings"):open("/tmp/coversearch-menu-book-settings.lua"),
    keyselection = { stopHighlightIndicator = function() end }, handleEvent = function() end,
    menu = { registerToMainMenu = function() end } }
local plugin = dofile(project .. "/coversearch.koplugin/main.lua"):new{ ui = ui }
local reader = ReaderMenu:new{ ui = ui }
local items = reader.menu_items
-- Populate the main tab rather than testing the plugin in an otherwise empty menu.
local labels = { history = _("History"), open_previous_document = _("Open previous document"),
    favorites = _("Favorites"), collections = _("Collections"), bookmark_browser = _("Bookmark browser"),
    book_status = _("Book status"), mass_storage_actions = _("USB storage"),
    ota_update = _("Update KOReader"), help = _("Help"), exit_menu = _("Exit") }
for id, label in pairs(labels) do items[id] = { text = label, callback = function() end } end
require("apps/filemanager/filemanagerbookinfo"):new{ ui = ui }:addToMainMenu(items)
plugin:addToMainMenu(items)
plugin:addToMainMenu(items)
local occurrences = 0
for index, id in ipairs(order.main) do
    if id == "coversearch" then
        occurrences = occurrences + 1
        assert(order.main[index - 1] == "book_info", "Cover search must follow Book information")
    end
end
assert(occurrences == 1, "Repeated menu registration duplicated the plugin")
reader.tab_item_table = MenuSorter:sort(items, order)
local main_index, main
for index, tab in ipairs(reader.tab_item_table) do
    if tab.id == "main" then main_index, main = index, tab end
end
assert(main)
local cover_index, info_index
for index, item in ipairs(main) do
    if item.id == "coversearch" then cover_index = index end
    if item.id == "book_info" then info_index = index end
end
assert(cover_index == info_index + 1 and not main[info_index].separator,
    "Cover search must share the Book information group without a separator between them")
assert(main[cover_index].separator, "The separator after the book group must remain intact")
reader:onShowMenu(main_index)
UIManager:forceRePaint()
local menu = reader.menu_container[1]
assert(menu.page == 1 and cover_index <= menu.perpage and info_index <= menu.perpage,
    "Book information and Cover search must both be on the first menu page")
local screenshot = "/tmp/coversearch-menu-" .. (arg[2] or "portrait") .. "-" .. (arg[3] or "en") .. ".png"
Device.screen:shot(screenshot)
print("PASS populated native menu: Book information " .. info_index .. ", Cover search " .. cover_index
    .. ", " .. menu.perpage .. " entries per page; same group and first page")
menu:onMenuSelect(main[cover_index])
assert(menu.item_table == main[cover_index].sub_item_table)
menu:onMenuSelect(menu.item_table[1])
local form = UIManager._window_stack[#UIManager._window_stack].widget
assert(form.title == require("coversearch/i18n")("Search book covers"))
assert(#UIManager._window_stack == 1, "Selecting search must close the parent menu")
UIManager:close(form)
print("PASS submenu selection opens the search form and closes the reader menu")

-- Existing explicit placement is retained; a missing anchor uses sorting_hint.
local original = order.main
order.main = { "coversearch", "book_info" }
plugin:addToMainMenu({})
assert(#order.main == 2 and order.main[1] == "coversearch")
order.main = { "history", "help" }
local fallback = {}; plugin:addToMainMenu(fallback)
assert(#order.main == 2 and fallback.coversearch.sorting_hint == "main")
order.main = original
print("PASS repeated registration, existing menu placement, and missing-anchor fallback")
print("All native menu checks passed: " .. screenshot)
