-- SPDX-License-Identifier: AGPL-3.0-or-later
local CenterContainer = require("ui/widget/container/centercontainer")
local Button = require("ui/widget/button")
local CheckButton = require("ui/widget/checkbutton")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local DocSettings = require("docsettings")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local ImageViewer = require("ui/widget/imageviewer")
local ImageWidget = require("ui/widget/imagewidget")
local LuaSettings = require("luasettings")
local NetworkMgr = require("ui/network/manager")
local RenderImage = require("ui/renderimage")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local ffiUtil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local Cache = require("coversearch/cache")
local Dialogs = require("coversearch/dialogs")
local HTTP = require("coversearch/http")
local Images = require("coversearch/images")
local Model = require("coversearch/model")
local Providers = require("coversearch/providers")
local Store = require("coversearch/store")
local Tile = require("coversearch/tile")
local _ = require("coversearch/i18n")
local Screen = Device.screen

local CoverSearch = WidgetContainer:extend{ name = "coversearch", is_doc_only = true }

local function message(text)
    UIManager:show(Dialogs.info(text))
end

local function findCovers(book)
    local covers, seen = {}, {}
    for _, location in ipairs({ "doc", "dir", "hash" }) do
        local dir = DocSettings:getSidecarDir(book, location)
        if not seen[dir] then
            seen[dir] = true
            local ok, iter, state = pcall(lfs.dir, dir)
            if ok then
                for file in iter, state do
                    if util.splitFileNameSuffix(file) == "cover" and lfs.attributes(dir .. "/" .. file, "mode") == "file" then
                        covers[#covers + 1] = dir .. "/" .. file
                    end
                end
            end
        end
    end
    return covers
end

local store_deps = {
    dirs = function(book) return DocSettings:getCustomLocationCandidates(book) end,
    covers = findCovers,
    mkdir = util.makePath,
    copy = function(source, target)
        local err = ffiUtil.copyFile(source, target)
        return err == nil, err
    end,
    exists = function(path) return lfs.attributes(path) ~= nil end,
    rename = os.rename,
    remove = os.remove,
}

function CoverSearch:init()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/coversearch.lua")
    self.prefs = {
        enabled = self.settings:readSetting("enabled", {}),
        results = self.settings:readSetting("results", 3),
        country = self.settings:readSetting("country", "US"),
        amazon_domain = self.settings:readSetting("amazon_domain", "com"),
    }
    -- Validate persisted preferences as well as user input.
    if type(self.prefs.enabled) ~= "table" then self.prefs.enabled = {} end
    if self.prefs.results ~= 3 and self.prefs.results ~= 5 and self.prefs.results ~= 10 then self.prefs.results = 3 end
    if type(self.prefs.country) ~= "string" or not self.prefs.country:match("^[A-Z][A-Z]$") then self.prefs.country = "US" end
    if not ({ com = true, ["co.uk"] = true, de = true, fr = true, es = true, it = true, ca = true, ["com.au"] = true, ["co.jp"] = true, ["com.br"] = true, ["com.mx"] = true, ["in"] = true })[self.prefs.amazon_domain] then self.prefs.amazon_domain = "com" end
    self.cache_root = DataStorage:getDataDir() .. "/cache/coversearch"
    util.makePath(self.cache_root)
    -- Clear only this plugin's abandoned sessions from a previous KOReader run.
    local ok, iter, state = pcall(lfs.dir, self.cache_root)
    if ok then
        for entry in iter, state do
            if entry:match("^session%-%d+%-%d+$") then ffiUtil.purgeDir(self.cache_root .. "/" .. entry) end
        end
    end
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
end

function CoverSearch:onDispatcherRegisterActions()
    Dispatcher:registerAction("coversearch", {
        category = "none", event = "CoverSearch", title = _("Search book covers"), reader = true,
    })
end

function CoverSearch:savePreferences()
    for k, v in pairs(self.prefs) do self.settings:saveSetting(k, v) end
    self.settings:flush()
end

function CoverSearch:addToMainMenu(items)
    -- sorting_hint chooses a tab but appends after its built-in entries.
    -- Use the cached menu order to keep cover actions with the book information.
    local order = require("ui/elements/reader_menu_order").main
    local placed = false
    for _, id in ipairs(order or {}) do
        if id == "coversearch" then placed = true; break end
    end
    if not placed then
        for index, id in ipairs(order or {}) do
            if id == "book_info" then table.insert(order, index + 1, "coversearch"); break end
        end
    end
    local sources = {}
    for _, provider in ipairs(Providers.list) do
        local id = provider.id
        sources[#sources + 1] = {
            text = provider.name,
            checked_func = function() return self.prefs.enabled[id] ~= false end,
            callback = function()
                self.prefs.enabled[id] = self.prefs.enabled[id] == false
                self:savePreferences()
            end,
        }
    end
    local counts = {}
    for _, count in ipairs({ 3, 5, 10 }) do
        counts[#counts + 1] = {
            text = tostring(count),
            checked_func = function() return self.prefs.results == count end,
            callback = function() self.prefs.results = count; self:savePreferences() end,
        }
    end
    items.coversearch = {
        text = _("Cover search"), sorting_hint = "main",
        sub_item_table = {
            { text = _("Search covers for this book"), callback = function() self:onCoverSearch() end },
            { text = _("Restore original cover"), enabled_func = function() return DocSettings:findCustomCoverFile(self.ui.document.file) ~= nil end,
                callback = function() self:confirmReset() end },
            { text = _("Sources"), sub_item_table = sources },
            { text = _("Results per source"), sub_item_table = counts },
            { text = _("Store regions"), callback = function() self:editRegions() end },
        },
    }
end

function CoverSearch:editRegions()
    local dialog
    dialog = Dialogs.form{
        title = _("Store regions"),
        fields = {
            { text = self.prefs.country, description = _("Apple Books country (two letters, e.g. US, GB, DE)") },
            { text = self.prefs.amazon_domain, description = _("Amazon domain (com, co.uk, de, fr, es, it, ca, com.au, co.jp, com.br, com.mx, in)") },
        },
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Save"), callback = function()
                local fields = dialog:getFields()
                local country, domain = Model.trim(fields[1]):upper(), Model.trim(fields[2]):lower()
                local allowed = { com = true, ["co.uk"] = true, de = true, fr = true, es = true, it = true, ca = true,
                    ["com.au"] = true, ["co.jp"] = true, ["com.br"] = true, ["com.mx"] = true, ["in"] = true }
                if not country:match("^[A-Z][A-Z]$") or not allowed[domain] then message(_("Enter a two-letter country and one of the listed Amazon domains.")); return end
                self.prefs.country, self.prefs.amazon_domain = country, domain
                self:savePreferences()
                UIManager:close(dialog)
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function CoverSearch:onCoverSearch()
    if not self.ui.document then return end
    if self.session or self.searching then message(_("A cover search is already open. Close it before starting another.")); return end
    local book = Model.metadata(self.ui.doc_props, self.ui.document.file)
    local book_file = self.ui.document.file
    local dialog, isbn_checkbox
    local selected_isbn = book.isbn
    local isbn_label = book.isbn ~= "" and string.format(_("Use ISBN %s"), book.isbn) or _("No ISBN available")
    local choose_label = string.format(_("Choose ISBN · %d found"), #book.isbns)
    local sizing_label = isbn_label
    for index, isbn in ipairs(book.isbns) do
        if #isbn > #book.isbn then sizing_label = string.format(_("Use ISBN %s"), isbn) end
    end
    if #book.isbns > 1 then sizing_label = sizing_label .. "\n" .. choose_label end
    dialog = Dialogs.form({
        title = _("Search book covers"),
        fields = {
            { text = book.title, description = _("Title") },
            { text = book.author, description = _("Author (optional)") },
        },
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function() UIManager:close(dialog) end },
            { text = _("Search"), callback = function()
                local values = dialog:getFields()
                local query = { title = Model.trim(values[1]), author = Model.trim(values[2]),
                    isbn = isbn_checkbox.checked and selected_isbn or "" }
                if query.title == "" and query.isbn == "" then message(_("Enter a title.")); return end
                local enabled = false
                for _, source in ipairs(Providers.list) do if self.prefs.enabled[source.id] ~= false then enabled = true end end
                if not enabled then message(_("Enable at least one source in Cover search → Sources.")); return end
                UIManager:close(dialog)
                NetworkMgr:runWhenOnline(function()
                    Trapper:wrap(function() self:search(book_file, query) end)
                end)
            end },
        }},
    }, sizing_label)
    isbn_checkbox = CheckButton:new{
        text = isbn_label,
        checked = book.isbn ~= "", enabled = book.isbn ~= "",
        parent = dialog, width = math.floor(dialog.width * 0.9),
    }
    dialog:addWidget(isbn_checkbox)
    if #book.isbns > 1 then
        local choose_button = Button:new{
            text = choose_label,
            width = math.floor(dialog.width * 0.9),
            callback = function()
                dialog:onCloseKeyboard()
                local choices = {}
                for _, isbn in ipairs(book.isbns) do
                    choices[#choices + 1] = {{ text = isbn, provider = isbn, checked = isbn == selected_isbn }}
                end
                UIManager:show(Dialogs.radio{
                    title_text = _("Choose ISBN"), radio_buttons = choices, width = dialog.width,
                    cancel_text = _("Cancel"), ok_text = _("Use ISBN"),
                    callback = function(picker)
                        selected_isbn = picker.provider
                        isbn_checkbox.text = string.format(_("Use ISBN %s"), selected_isbn)
                        isbn_checkbox:initCheckButton(isbn_checkbox.checked)
                        UIManager:setDirty(dialog, "ui")
                    end,
                })
            end,
        }
        dialog:addWidget(choose_button)
    end
    UIManager:show(dialog)
    dialog:onShowKeyboard()
    return true
end

function CoverSearch:search(book_file, query)
    if self.session or self.searching or self.document_closed then return end
    self.searching = true
    local completed, results = Dialogs.run(function()
        return Providers.search(HTTP, query, self.prefs)
    end, _("Searching cover sources…"))
    self.searching = false
    if not completed then return end
    if self.document_closed or not self.ui.document or self.ui.document.file ~= book_file then return end
    if not results then message(_("Cover search failed. Please try again.")); return end
    if #results.candidates == 0 then
        UIManager:show(Dialogs.viewer{ title = _("No covers found"), text = table.concat(results.statuses, "\n") .. "\n\n" .. _("Try a shorter title, another author spelling, or turn off the ISBN filter to search other editions.") })
        return
    end
    self.session_count = (self.session_count or 0) + 1
    local dir = self.cache_root .. "/session-" .. os.time() .. "-" .. self.session_count
    util.makePath(dir)
    local session = { book_file = book_file, query = query, dir = dir, candidates = results.candidates,
        statuses = results.statuses, downloads = {}, index = 1 }
    self.session = session
    self:showGrid(session, 1)
end

function CoverSearch:finishSession(session)
    if session.closed then return end
    session.closed = true
    if self.session == session then self.session = nil end
    ffiUtil.purgeDir(session.dir)
end

function CoverSearch:fetchCandidate(session, index, protected)
    local item = session.candidates[index]
    local partial
    session.downloads = session.downloads or {}
    local ok, value = pcall(function()
        local download_url = item.url
        local downloaded, data = pcall(HTTP.get, HTTP, download_url, 8 * 1024 * 1024)
        if not downloaded and item.fallback_url then
            download_url = item.fallback_url
            downloaded, data = pcall(HTTP.get, HTTP, download_url, 8 * 1024 * 1024)
        end
        if not downloaded then error(data) end
        local info, err = Images.inspect(data)
        if not info then error(err) end
        local reserved, reserve_error = Cache.reserve(session, info.bytes, protected or { [index] = true }, lfs.attributes, os.remove)
        if not reserved then error(reserve_error) end
        local path = session.dir .. "/" .. index .. "." .. info.extension
        partial = path .. ".part"
        local file, open_error = io.open(partial, "wb")
        if not file then error(open_error) end
        local written, write_error = file:write(data)
        local closed, close_error = file:close()
        if not written or not closed then error(write_error or close_error) end
        local moved, move_error = os.rename(partial, path)
        if not moved then error(move_error) end
        info.path = path
        info.download_url = download_url
        return Cache.mark(session, info)
    end)
    if not ok and partial then os.remove(partial) end
    local result = ok and value or { error = tostring(value):gsub("^.-:%d+: ", "") }
    session.downloads[index] = result
    return result
end

function CoverSearch:loadCandidates(session, first, last)
    local protected = {}
    for index = first, last do protected[index] = true end
    for index = first, last do
        if not Cache.get(session, index, lfs.attributes) then self:fetchCandidate(session, index, protected) end
    end
    -- Return the whole cache: the subprocess may have evicted older files.
    return { downloads = session.downloads, cache_clock = session.cache_clock }
end

function CoverSearch:download(session, index)
    local cached = Cache.get(session, index, lfs.attributes)
    if cached then return cached end
    local completed, state = Dialogs.run(function()
        return self:loadCandidates(session, index, index)
    end, _("Downloading cover…"))
    if session.closed then return nil end
    if not completed or not state then self:finishSession(session); return nil end
    session.downloads, session.cache_clock = state.downloads, state.cache_clock
    return session.downloads[index]
end

function CoverSearch:discardInterruptedDownloads(session)
    -- An interrupted subprocess may have evicted files or written new ones without
    -- returning its cache state. Reconcile the old entries and remove untracked files.
    local keep = {}
    for index in pairs(session.downloads) do
        local info = Cache.peek(session, index, lfs.attributes)
        if info and info.path then keep[info.path] = true end
    end
    for name in lfs.dir(session.dir) do
        local path = session.dir .. "/" .. name
        if lfs.attributes(path, "mode") == "file" and not keep[path] then
            local removed, err = os.remove(path)
            if not removed then return nil, err end
        end
    end
    return true
end

function CoverSearch:showGrid(session, page, previous_dialog)
    if session.closed or session.loading then return end
    local first, last = (page - 1) * 4 + 1, math.min(page * 4, #session.candidates)
    local cached = true
    for index = first, last do
        if not Cache.get(session, index, lfs.attributes) then cached = false end
    end
    if not cached then
        session.loading = true
        local completed, downloaded = Dialogs.run(function()
            return self:loadCandidates(session, first, last)
        end, previous_dialog and string.format(_("Loading page %d…"), page) or _("Loading cover thumbnails…"))
        session.loading = nil
        if session.closed then return end
        if not completed or not downloaded then
            if previous_dialog then
                local cleaned, err = self:discardInterruptedDownloads(session)
                if not cleaned then
                    UIManager:close(previous_dialog)
                    self:finishSession(session)
                    message(_("Could not clean up the canceled download:\n") .. tostring(err))
                    return
                end
                if completed then message(_("Could not load this page. Please try again.")) end
            else
                self:finishSession(session)
            end
            return
        end
        session.downloads, session.cache_clock = downloaded.downloads, downloaded.cache_clock
    end
    session.page = page
    local dialog
    local function choose(index)
        UIManager:close(dialog)
        Trapper:wrap(function() self:showCandidate(session, index) end)
    end
    local shortcuts = {}
    for index = first, last do shortcuts[#shortcuts + 1] = { text = "#" .. index, callback = function() choose(index) end } end
    local buttons = {}
    if not Device:isTouchDevice() then buttons[#buttons + 1] = shortcuts end
    buttons[#buttons + 1] = {
        { text = _("Summary"), id = "summary", callback = function()
            UIManager:show(Dialogs.viewer{ title = _("Summary"), text = table.concat(session.statuses, "\n")
                .. "\n\n" .. _("Candidates are verified when downloaded. A source can return other editions or related books") })
        end },
        { text = "‹ " .. _("Previous"), id = "previous", enabled = page > 1, callback = function()
            Trapper:wrap(function() self:showGrid(session, page - 1, dialog) end)
        end },
        { text = _("Next") .. " ›", id = "next", enabled = last < #session.candidates, callback = function()
            Trapper:wrap(function() self:showGrid(session, page + 1, dialog) end)
        end },
        { text = _("Close"), id = "close", callback = function() dialog:onClose() end },
    }
    -- Image grids need screen space even when translated headings and buttons are shorter.
    local grid_width = math.floor(Screen:getWidth() * 0.96)
    dialog = Dialogs.buttons({
        title = string.format(_("Book covers · page %d / %d"), page, math.ceil(#session.candidates / 4))
            .. "\n" .. (Device:isTouchDevice() and _("Tap a thumbnail to preview") or _("Choose a numbered cover to preview")),
        title_align = "center", width = grid_width,
        tap_close_callback = function() self:finishSession(session) end,
        buttons = buttons,
    }, grid_width)
    local columns = Screen:getWidth() > Screen:getHeight() and 4 or 2
    local width = math.floor(dialog:getAddedWidgetAvailableWidth() / columns)
    local thumb_height = math.floor(Screen:getHeight() * (columns == 4 and 0.40 or 0.24))
    local grid = VerticalGroup:new{ not_focusable = true }
    local row
    for index = first, last do
        if (index - first) % columns == 0 then row = HorizontalGroup:new{}; grid[#grid + 1] = row end
        local item, info = session.candidates[index], session.downloads[index]
        local bitmap
        if info.path then
            local scale = math.min((width - 20) / info.width, thumb_height / info.height, 1)
            local ok, bb = pcall(RenderImage.renderImageFile, RenderImage, info.path, false,
                math.max(1, math.floor(info.width * scale)), math.max(1, math.floor(info.height * scale)))
            if ok then bitmap = bb end
            if not bitmap then info.error = _("KOReader could not decode this image.") end
        end
        row[#row + 1] = Tile:new{ width = width, image_height = thumb_height, bitmap = bitmap,
            index = index, item = item, info = info, callback = function() choose(index) end }
    end
    dialog:addWidget(grid)
    if previous_dialog then UIManager:close(previous_dialog) end
    UIManager:show(dialog)
end

function CoverSearch:showCandidate(session, index)
    if session.closed then return end
    session.index = index
    session.page = math.ceil(index / 4)
    local item = session.candidates[index]
    local info = self:download(session, index)
    if session.closed then return end
    if not info then self:finishSession(session); return end
    local bitmap
    if info.path then
        local scale = math.min(Screen:getWidth() * 0.68 / info.width, Screen:getHeight() * 0.35 / info.height, 1)
        local ok, bb = pcall(RenderImage.renderImageFile, RenderImage, info.path, false,
            math.max(1, math.floor(info.width * scale)), math.max(1, math.floor(info.height * scale)))
        if ok then bitmap = bb end
        if not bitmap then info.error = _("KOReader could not decode this image. Try another cover.") end
    end
    local valid = bitmap ~= nil
    local dimensions = info.width and string.format("%d × %d px · %.2f MP", info.width, info.height, info.width * info.height / 1000000) or _("Unavailable")
    local dialog
    local function navigate(next_index)
        UIManager:close(dialog)
        Trapper:wrap(function() self:showCandidate(session, next_index) end)
    end
    dialog = Dialogs.buttons({
        title = string.format("%d / %d · %s\n%s\n%s", index, #session.candidates, item.source, dimensions, Model.shorten(item.title, 65)),
        title_align = "center", width_factor = 0.94,
        tap_close_callback = function() self:finishSession(session) end,
        buttons = {
            {
                { text = _("Details"), callback = function()
                    UIManager:show(Dialogs.viewer{
                        title = _("Cover details"),
                        text = item.title .. "\n" .. item.author .. "\n" .. item.source .. "\n" .. dimensions
                            .. (info.bytes and string.format("\n%.0f KB", info.bytes / 1024) or "")
                            .. (info.error and "\n" .. info.error or "") .. "\n\n" .. item.page .. "\n" .. (info.download_url or item.url)
                            .. "\n\n" .. _("Summary (candidates are verified when downloaded):") .. "\n" .. table.concat(session.statuses, "\n"),
                    })
                end },
                { text = "‹ " .. _("Previous"), id = "previous", enabled = index > 1, callback = function() navigate(index - 1) end },
                { text = _("Next") .. " ›", id = "next", enabled = index < #session.candidates, callback = function() navigate(index + 1) end },
                { text = _("Preview"), enabled = valid, callback = function()
                    UIManager:show(ImageViewer:new{ file = info.path, fullscreen = true,
                        title_text = item.source .. " · " .. dimensions, buttons_visible = true })
                end },
            },
            {
                { text = _("Use this cover"), enabled = valid, callback = function()
                    if not self.ui.document or self.ui.document.file ~= session.book_file then message(_("The current book changed. Start a new cover search.")); return end
                    local ok, err = Store.apply(store_deps, session.book_file, info.path, info.extension)
                    if not ok then message(_("Could not save the cover:\n") .. tostring(err)); return end
                    self:invalidateCover(session.book_file)
                    UIManager:close(dialog)
                    self:finishSession(session)
                    message(_("Cover updated"))
                end },
                { text = _("Back to results"), callback = function()
                    UIManager:close(dialog)
                    Trapper:wrap(function() self:showGrid(session, session.page or math.ceil(index / 4)) end)
                end },
            },
        },
    }, bitmap and bitmap:getWidth())
    if bitmap then
        local image = ImageWidget:new{ image = bitmap, image_disposable = true, width = bitmap:getWidth(), height = bitmap:getHeight() }
        local center = CenterContainer:new{
            dimen = Geom:new{ w = dialog:getAddedWidgetAvailableWidth(), h = bitmap:getHeight() },
            not_focusable = true, image,
        }
        dialog:addWidget(center)
    else
        dialog:setTitle(dialog.title .. "\n" .. Model.shorten(info.error, 150))
    end
    UIManager:show(dialog)
end

function CoverSearch:invalidateCover(book)
    if self.ui.doc_settings then self.ui.doc_settings:getCustomCoverFile(true) end
    UIManager:broadcastEvent(Event:new("InvalidateMetadataCache", book))
    UIManager:broadcastEvent(Event:new("BookMetadataChanged"))
end

function CoverSearch:confirmReset()
    local book = self.ui.document.file
    UIManager:show(Dialogs.confirm{
        text = _("Restore the ebook's original cover? This removes its KOReader cover override."),
        ok_text = _("Restore"),
        ok_callback = function()
            local ok, err = Store.reset(store_deps, book)
            self:invalidateCover(book)
            if ok then message(_("Original cover restored.")) else message(_("Could not restore the cover:\n") .. tostring(err)) end
        end,
    })
end

function CoverSearch:onCloseDocument()
    self.document_closed = true
    if self.session then self:finishSession(self.session) end
end

return CoverSearch
