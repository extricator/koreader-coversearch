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
local background = require("ui/widget/container/inputcontainer"):new{
    dimen = Device.screen:getSize(),
    paintTo = function(_, bb) bb:fill(require("ffi/blitbuffer").COLOR_WHITE) end,
}
UIManager:show(background)
local ui = { document = { file = "/tmp/coversearch-menu-book.epub" },
    doc_props = { title = "Dune", authors = "Frank Herbert" },
    doc_settings = require("luasettings"):open("/tmp/coversearch-menu-book-settings.lua"),
    keyselection = { stopHighlightIndicator = function() end }, handleEvent = function() end,
    menu = { registerToMainMenu = function() end } }
local plugin = dofile(project .. "/coversearch.koplugin/main.lua"):new{ ui = ui }
-- Populate both tabs rather than testing the plugin in an otherwise empty menu.
local labels = { history = _("History"), open_previous_document = _("Open previous document"),
    favorites = _("Favorites"), collections = _("Collections"), bookmark_browser = _("Bookmark browser"),
    book_status = _("Book status"),
    ota_update = _("Update KOReader"), help = _("Help"), exit_menu = _("Exit"),
    document_settings = _("Document settings"), set_render_style = _("Render style"),
    style_tweaks = _("Style tweaks"), change_font = _("Font"), typography = _("Typography"),
    speed_reading_module_perception_expander = _("Speed reading"), highlight_options = _("Highlights") }
local function populatedReader()
    local reader = ReaderMenu:new{ ui = ui }
    for id, label in pairs(labels) do reader.menu_items[id] = { text = label, callback = function() end } end
    require("apps/filemanager/filemanagerbookinfo"):new{ ui = ui }:addToMainMenu(reader.menu_items)
    return reader
end
local function tab(tabs, id)
    for index, item in ipairs(tabs) do if item.id == id then return item, index end end
    error("Missing tab: " .. id)
end
local function indexOf(items, id)
    for index, item in ipairs(items) do if item.id == id then return index end end
    error("Missing entry: " .. id)
end
local baseline = populatedReader()
baseline.tab_item_table = MenuSorter:sort(baseline.menu_items, order)
local baseline_main, baseline_index = tab(baseline.tab_item_table, "main")
baseline:onShowMenu(baseline_index)
local baseline_menu = baseline.menu_container[1]
local exit_index = indexOf(baseline_main, "exit_menu")
local exit_page = math.floor((exit_index - 1) / baseline_menu.perpage) + 1
local baseline_perpage = baseline_menu.perpage
if arg[2] ~= "landscape" then
    assert(exit_page == 1, "Portrait fixture must exercise Exit at the first-page boundary")
end
baseline:onTapCloseMenu()

local reader = populatedReader()
local items = reader.menu_items
local main_order = table.concat(order.main, "\n")
plugin:addToMainMenu(items)
plugin:addToMainMenu(items)
local occurrences = 0
for index, id in ipairs(order.typeset) do
    if id == "coversearch" then
        occurrences = occurrences + 1
        assert(order.typeset[index - 1] == "document_settings", "Cover search must follow Document settings")
    end
end
assert(occurrences == 1, "Repeated menu registration duplicated the plugin")
assert(table.concat(order.main, "\n") == main_order, "Plugin changed the hamburger menu order")
reader.tab_item_table = MenuSorter:sort(items, order)
local main, main_index = tab(reader.tab_item_table, "main")
assert(#main == #baseline_main, "Plugin added an entry to the hamburger menu")
for index, item in ipairs(main) do
    assert(item.id == baseline_main[index].id and item.separator == baseline_main[index].separator,
        "Plugin changed the hamburger menu entries or grouping")
end
reader:onShowMenu(main_index)
local main_menu = reader.menu_container[1]
assert(main_menu.perpage == baseline_perpage and indexOf(main, "exit_menu") == exit_index,
    "Plugin changed Exit pagination")
assert(math.floor((exit_index - 1) / main_menu.perpage) + 1 == exit_page)
local suffix = (arg[2] or "portrait") .. "-" .. (arg[3] or "en") .. ".png"
UIManager:forceRePaint()
Device.screen:shot("/tmp/coversearch-hamburger-" .. suffix)
reader:onTapCloseMenu()
print("PASS hamburger menu unchanged: Exit " .. exit_index .. ", page " .. exit_page)

local typeset, typeset_index = tab(reader.tab_item_table, "typeset")
local cover_index, settings_index = indexOf(typeset, "coversearch"), indexOf(typeset, "document_settings")
assert(cover_index == settings_index + 1 and not typeset[settings_index].separator,
    "Cover search must share the Document settings group without a separator between them")
assert(typeset[cover_index].separator, "The separator after the document group must remain intact")
reader:onShowMenu(typeset_index)
UIManager:forceRePaint()
local menu = reader.menu_container[1]
assert(menu.page == 1 and cover_index <= menu.perpage and settings_index <= menu.perpage,
    "Document settings and Cover search must both be on the first menu page")
local screenshot = "/tmp/coversearch-menu-" .. suffix
Device.screen:shot(screenshot)
print("PASS populated native menu: Document settings " .. settings_index .. ", Cover search " .. cover_index
    .. ", " .. menu.perpage .. " entries per page; same group and first page")
menu:onMenuSelect(typeset[cover_index])
assert(menu.item_table == typeset[cover_index].sub_item_table)
menu:onMenuSelect(menu.item_table[1])
local form = UIManager._window_stack[#UIManager._window_stack].widget
assert(form.title == require("coversearch/i18n")("Search book covers"))
assert(#UIManager._window_stack == 2, "Selecting search must leave only the search form and background")
UIManager:close(form)
print("PASS submenu selection opens the search form and closes the reader menu")

-- Existing explicit placement is retained; a missing anchor uses sorting_hint.
local original = order.typeset
order.typeset = { "coversearch", "document_settings" }
plugin:addToMainMenu({})
assert(#order.typeset == 2 and order.typeset[1] == "coversearch")
order.typeset = { "change_font", "typography" }
local fallback = {}; plugin:addToMainMenu(fallback)
assert(#order.typeset == 2 and fallback.coversearch.sorting_hint == "typeset")
local fallback_reader = populatedReader()
plugin:addToMainMenu(fallback_reader.menu_items)
local fallback_tabs = MenuSorter:sort(fallback_reader.menu_items, order)
local fallback_typeset = tab(fallback_tabs, "typeset")
assert(indexOf(fallback_typeset, "coversearch") == 3, "Missing anchor must append to the page-icon tab")
order.typeset = original
print("PASS repeated registration, existing menu placement, and missing-anchor fallback")
print("All native menu checks passed: " .. screenshot)
UIManager:close(background)
