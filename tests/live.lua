-- Optional live checks, run from an unpacked KOReader Linux runtime.
-- ./luajit /path/to/tests/live.lua /path/to/project
local project = assert(arg[1], "project path required")
require("setupkoenv")
package.path = project .. "/coversearch.koplugin/?.lua;" .. package.path
G_defaults = require("luadefaults"):open("/tmp/coversearch-live-defaults.lua")
G_reader_settings = require("luasettings"):open("/tmp/coversearch-live-settings.lua")
einkfb = require("ffi/framebuffer"); einkfb.dummy = true
local Device = require("device"); Device.screen:init(); Device.input.dummy = true
require("logger"):setLevel(require("logger").levels.warn)
local HTTP = require("coversearch/http")
local Images = require("coversearch/images")
local Providers = require("coversearch/providers")
local prefs = { results = 3, country = "US", amazon_domain = "com", enabled = {} }
local book = { title = "Dune", author = "Frank Herbert", isbn = "" }
local context, verified = { isbns = {} }, 0
for _, source in ipairs(Providers.list) do
    local ok, candidates = pcall(Providers[source.id], HTTP, book, prefs, context)
    if not ok then
        print(source.name .. " search unavailable: " .. tostring(candidates))
    else
        local found = false
        for _, item in ipairs(candidates) do
            local downloaded, info = pcall(function() return assert(Images.inspect(HTTP:get(item.url, 8 * 1024 * 1024))) end)
            if downloaded then
                print(string.format("VERIFIED %s: %d × %d (%d bytes)", source.name, info.width, info.height, info.bytes))
                verified = verified + 1; found = true; break
            else
                print(source.name .. " candidate unavailable: " .. tostring(info))
            end
        end
        if not found then print(source.name .. ": no verified image") end
    end
end
print(string.format("%d sources supplied a verified cover on this run", verified))
if verified < 5 then os.exit(1) end
