-- Run from an unpacked KOReader Linux runtime, with project and JPEG/PNG fixture arguments.
local project, fixture = assert(arg[1]), assert(arg[2])
require("setupkoenv")
package.path = project .. "/coversearch.koplugin/?.lua;" .. package.path
require("logger"):setLevel(require("logger").levels.warn)
G_defaults = require("luadefaults"):open("/tmp/coversearch-cache-defaults.lua")
G_reader_settings = require("luasettings"):open("/tmp/coversearch-cache-settings.lua")
G_reader_settings:saveSetting("language", arg[4] or "C")
require("gettext").changeLang(arg[4] or "C")
local translate = require("coversearch/i18n")
einkfb = require("ffi/framebuffer"); einkfb.dummy = true
local Device = require("device")
Device.screen:init(); Device.input.dummy = true
if arg[3] == "landscape" then Device.screen:setRotationMode(1) end
if arg[3] == "keys" then Device.isTouchDevice = function() return false end end
require("document/canvascontext"):init(Device)
local UIManager = require("ui/uimanager")
local Trapper = require("ui/trapper")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local HTTP = require("coversearch/http")
local Cache = require("coversearch/cache")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local file = assert(io.open(fixture, "rb"))
local data = file:read("*a"); file:close()
assert(#data * 12 <= Cache.LIMIT, "Use a fixture smaller than 5 MiB")
local plugin = dofile(project .. "/coversearch.koplugin/main.lua"):new{
    ui = { document = { file = "/tmp/coversearch-cache-book.epub" }, menu = { registerToMainMenu = function() end } },
}
local old_run, old_get = Trapper.dismissableRunInSubprocess, HTTP.get
local requests, workers, session_number = 0, 0, 200
local function top() return UIManager._window_stack[#UIManager._window_stack].widget end
local function button(text)
    for _, row in ipairs(top().buttons) do for _, b in ipairs(row) do if b.text == translate(text) or b.id == text:lower() then return b end end end
    error("Missing button: " .. text)
end
local function newSession(count, limit)
    session_number = session_number + 1
    local session = { book_file = plugin.ui.document.file, candidates = {}, statuses = {}, downloads = {},
        dir = plugin.cache_root .. "/session-" .. session_number .. "-1", cache_limit = limit }
    for index = 1, count do
        session.candidates[index] = { source = "Test", title = "Cover " .. index, author = "Author",
            url = "https://example.com/" .. index .. ".jpg", page = "" }
    end
    util.makePath(session.dir); plugin.session = session
    return session
end
local function diskBytes(session)
    local bytes = 0
    for name in lfs.dir(session.dir) do
        local attrs = lfs.attributes(session.dir .. "/" .. name)
        if attrs.mode == "file" then bytes = bytes + attrs.size end
    end
    return bytes
end
local function showPage(session, page)
    if #UIManager._window_stack > 0 then UIManager:close(top()) end
    plugin:showGrid(session, page)
    assert(session.page == page and not session.closed)
    assert(diskBytes(session) <= (session.cache_limit or Cache.LIMIT))
    UIManager:forceRePaint()
end
local function closeSession(session)
    top():onClose()
    assert(session.closed and not lfs.attributes(session.dir))
end
Trapper.dismissableRunInSubprocess = function(_, task) workers = workers + 1; return true, task() end
HTTP.get = function() requests = requests + 1; return data end

local session = newSession(12)
showPage(session, 1); showPage(session, 2); showPage(session, 3)
assert(requests == 12 and workers == 3)
showPage(session, 2); showPage(session, 1)
assert(requests == 12, "Revisiting three pages redownloaded cached covers")
assert(workers == 3, "Fully cached pages started a loading worker")
for index = 1, 12 do assert(session.downloads[index] and lfs.attributes(session.downloads[index].path)) end
top()._added_widgets[1][1][1]:onOpenCover()
button("Preview").callback(); UIManager:forceRePaint(); top():onClose()
button("Back to results").callback()
assert(requests == 12, "Preview or back navigation downloaded a cached cover")
assert(workers == 3, "Cached preview or back navigation started a loading worker")
assert(os.remove(session.downloads[2].path)); assert(os.remove(session.downloads[3].path))
showPage(session, 1)
assert(requests == 14, "A partially cached page must fetch exactly its missing files")
assert(workers == 4, "A partially cached page should use one download worker")
showPage(session, 1)
assert(requests == 14 and workers == 4)
assert(os.remove(session.downloads[1].path))
top()._added_widgets[1][1][1]:onOpenCover()
assert(requests == 15 and workers == 5, "A missing preview file should be fetched once")
button("Back to results").callback()
assert(requests == 15 and workers == 5)
closeSession(session)
print("PASS three-page retention with zero cached-page workers, preview reuse, missing-file recovery, and cleanup")

session = newSession(12, #data * 8)
showPage(session, 1); showPage(session, 2); showPage(session, 1); showPage(session, 3)
for index = 1, 4 do assert(session.downloads[index], "Recently revisited page was evicted") end
for index = 5, 8 do assert(not session.downloads[index], "Oldest page should be evicted") end
for index = 9, 12 do assert(lfs.attributes(session.downloads[index].path), "Incoming page must stay cached") end
closeSession(session)
print("PASS byte-budget eviction preserves recently used covers and the incoming page")

session = newSession(4)
local failure_requests = 0
HTTP.get = function(_, address)
    failure_requests = failure_requests + 1
    if address:find("/2.jpg", 1, true) then error("HTTP 403") end
    return data
end
local workers_before_failure = workers
showPage(session, 1); showPage(session, 1)
assert(failure_requests == 4 and session.downloads[2].error)
assert(workers == workers_before_failure + 1, "A cached failure started another loading worker")
assert(diskBytes(session) == #data * 3)
closeSession(session)
print("PASS known download failures are retained without retrying or using disk budget")

-- The child modifies files and metadata; the parent must adopt both evictions and the LRU clock.
session = newSession(8, #data * 4)
HTTP.get = function() return data end
plugin:loadCandidates(session, 1, 4)
showPage(session, 1)
local visible_grid = top()
local original_bounds = visible_grid:getContentSize():copy()
local original_title = visible_grid.title
local clock_before = session.cache_clock
Trapper.dismissableRunInSubprocess = old_run
HTTP.get = function() require("socket").sleep(0.1); return data end
local loading_seen = false
UIManager:scheduleIn(0.05, function()
    assert(#UIManager._window_stack == 2 and UIManager._window_stack[1].widget == visible_grid,
        "The current browser must remain visible while paging")
    local trap = top()
    assert(trap.modal and trap.frame and not trap.invisible and not trap.resend_event,
        "Paging must show a visible modal that consumes cancellation input")
    local hint = Device:isTouchDevice() and translate("Tap to cancel") or translate("Any key cancels")
    assert(trap.text == string.format(translate("Loading page %d…"), 2) .. "\n" .. hint)
    assert(visible_grid.title == original_title and session.page == 1)
    UIManager:forceRePaint()
    local frame = trap.frame.dimen
    assert(frame.w <= Device.screen:getWidth() and frame.h <= Device.screen:getHeight())
    assert(math.abs(frame.x + frame.w / 2 - Device.screen:getWidth() / 2) <= 1
        and math.abs(frame.y + frame.h / 2 - Device.screen:getHeight() / 2) <= 1,
        "The loading message must be centered above the browser")
    local loading_bounds = visible_grid:getContentSize()
    assert(loading_bounds.x == original_bounds.x and loading_bounds.y == original_bounds.y
        and loading_bounds.w == original_bounds.w and loading_bounds.h == original_bounds.h,
        "Loading must keep the existing browser's size and position")
    loading_seen = true
end)
local native_done = false
Trapper:wrap(function()
    plugin:showGrid(session, 2, visible_grid)
    assert(loading_seen and top() ~= visible_grid and #UIManager._window_stack == 1)
    assert(session.cache_clock > clock_before)
    for index = 1, 4 do assert(not session.downloads[index] and not lfs.attributes(session.dir .. "/" .. index .. ".jpg")) end
    for index = 5, 8 do assert(session.downloads[index] and lfs.attributes(session.downloads[index].path)) end
    assert(diskBytes(session) == #data * 4)
    closeSession(session)
    native_done = true
end)
UIManager:runOnce()
assert(native_done)
print("PASS real native subprocess transfers evictions, downloads, and access order to the parent")

-- Cancel a page after one image has committed and the next one has been staged.
-- The child has already evicted an old file, but cannot return its updated cache state.
session = newSession(8, #data * 4)
HTTP.get = function() return data end
plugin:loadCandidates(session, 1, 4)
showPage(session, 1)
visible_grid = top()
original_title = visible_grid.title
local browser_inputs, browser_handle = 0, visible_grid.handleEvent
visible_grid.handleEvent = function(self, event)
    if event.handler == "onGesture" or event.handler == "onKeyPress" then browser_inputs = browser_inputs + 1 end
    return browser_handle(self, event)
end
local page_marker = "/tmp/coversearch-cache-page-marker"
os.remove(page_marker)
local page_rename = os.rename
os.rename = function(source, target)
    if source == session.dir .. "/6.jpg.part" then
        local marker = assert(io.open(page_marker, "wb")); marker:write("staged"); marker:close()
        require("socket").sleep(5)
    end
    return page_rename(source, target)
end
local function cancelPageWhenStaged()
    if not lfs.attributes(page_marker) then UIManager:scheduleIn(0.05, cancelPageWhenStaged); return end
    local trap = top()
    assert(UIManager._window_stack[1].widget == visible_grid and trap.modal and trap.frame and not trap.invisible)
    assert(lfs.attributes(session.dir .. "/5.jpg") and lfs.attributes(session.dir .. "/6.jpg.part"))
    UIManager:forceRePaint()
    if Device:isTouchDevice() then
        local target = visible_grid:getButtonById("next").dimen
        if arg[5] == "message" then target = trap.frame.dimen
        elseif arg[5] == "outside" then target = Geom:new{ x = 1, y = 1, w = 2, h = 2 }
        elseif arg[5] == "thumbnail" then target = visible_grid._added_widgets[1][1][1].dimen end
        UIManager:handleInputEvent(Event:new("Gesture", { ges = "tap",
            pos = Geom:new{ x = target.x + target.w / 2, y = target.y + target.h / 2 } }))
    else
        UIManager:handleInputEvent(Event:new("KeyPress", require("device/key"):new("Right", {})))
    end
end
UIManager:scheduleIn(0.05, cancelPageWhenStaged)
local page_cancelled = false
Trapper:wrap(function()
    plugin:showGrid(session, 2, visible_grid)
    assert(top() == visible_grid and visible_grid.title == original_title)
    assert(session.page == 1 and not session.closed and not session.loading)
    assert(not session.downloads[1] and not session.downloads[2], "Evicted files must be reconciled after cancellation")
    assert(not lfs.attributes(session.dir .. "/5.jpg") and not lfs.attributes(session.dir .. "/6.jpg.part"))
    assert(diskBytes(session) == #data * 2, "Interrupted downloads must not bypass the cache budget")
    UIManager:forceRePaint()
    os.rename = page_rename
    -- Check after input dispatch completes, then retry the cancelled control.
    UIManager:nextTick(function()
        assert(browser_inputs == 0, "Cancellation input leaked to the retained browser")
        assert(top() == visible_grid and #UIManager._window_stack == 1, "Cancellation left an overlay behind")
        Trapper.dismissableRunInSubprocess = function(_, task) return true, task() end
        button("Next").callback()
        assert(session.page == 2 and top() ~= visible_grid)
        assert(diskBytes(session) <= session.cache_limit)
        button("Previous").callback()
        assert(session.page == 1 and not session.closed)
        closeSession(session)
        Trapper.dismissableRunInSubprocess = old_run
        page_cancelled = true
    end)
end)
UIManager:runOnce()
assert(page_cancelled)
os.rename = page_rename; os.remove(page_marker)
print("PASS dispatched " .. (Device:isTouchDevice() and (arg[5] or "next-button") .. " tap" or "key")
    .. " cancels without leaking input; browser retention, partial/evicted-file reconciliation, and retry pass")

-- Cancel after a file has been staged, before it can be renamed into the cache.
session = newSession(4)
local staged_marker = "/tmp/coversearch-cache-staged-marker"
os.remove(staged_marker)
local old_rename = os.rename
os.rename = function(source, target)
    if source:sub(1, #session.dir) == session.dir and source:sub(-5) == ".part" then
        local marker = assert(io.open(staged_marker, "wb")); marker:write("staged"); marker:close()
        require("socket").sleep(5)
    end
    return old_rename(source, target)
end
local function cancelWhenStaged()
    if lfs.attributes(staged_marker) then
        local trap = top()
        assert(trap.modal and trap.frame and not trap.invisible)
        local hint = Device:isTouchDevice() and translate("Tap to cancel") or translate("Any key cancels")
        assert(trap.text == translate("Loading cover thumbnails…") .. "\n" .. hint)
        if Device:isTouchDevice() then
            UIManager:handleInputEvent(Event:new("Gesture", { ges = "tap", pos = Geom:new{ x = 1, y = 1 } }))
        else
            UIManager:handleInputEvent(Event:new("KeyPress", require("device/key"):new("Back", {})))
        end
    else
        UIManager:scheduleIn(0.05, cancelWhenStaged)
    end
end
UIManager:scheduleIn(0.05, cancelWhenStaged)
local cancelled = false
Trapper:wrap(function()
    plugin:showGrid(session, 1)
    assert(session.closed and not lfs.attributes(session.dir))
    cancelled = true
end)
UIManager:runOnce()
assert(cancelled and lfs.attributes(staged_marker))
os.rename = old_rename; os.remove(staged_marker)
HTTP.get = old_get; Trapper.dismissableRunInSubprocess = old_run
print("PASS real subprocess cancellation removes staged files and the entire session cache")
print("All cache runtime checks passed")
