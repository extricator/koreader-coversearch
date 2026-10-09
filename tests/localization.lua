-- Dependency-free catalog, fallback, formatting, and source-summary checks.
package.path = "coversearch.koplugin/?.lua;" .. package.path
local core = setmetatable({ current_lang = "C", translation = { Close = "native close" }, context = {} }, {
    __call = function(self, text) return self.translation[text] or text end,
})
package.preload["gettext"] = function() return core end
local settings = { language = "C" }
G_reader_settings = { readSetting = function(_, key) return settings[key] end }
local _ = require("coversearch/i18n")
local spanish = require("coversearch/l10n/es")
local passed = 0
local function test(name, check)
    check(); passed = passed + 1; print("PASS " .. name)
end

test("English source strings and plural forms", function()
    for language_index, language in ipairs({ "C", "en", "en_US", "en-GB" }) do
        settings.language = language
        assert(_("Cover search") == "Cover search" and _("Close") == "Close")
        assert(string.format(_.ngettext("%d candidate", "%d candidates", 1), 1) == "1 candidate")
        assert(string.format(_.ngettext("%d candidate", "%d candidates", 0), 0) == "0 candidates")
    end
end)
test("Spanish UI setting and regional locale fallback", function()
    for language_index, language in ipairs({ "es", "es_ES", "es_MX.UTF-8", "es-DO", "ES" }) do
        settings.language = language
        assert(_("Cover search") == "Buscar portadas" and _("Close") == "Cerrar")
        assert(_("Use ISBN") == "Usar ISBN" and _("ISBN-10 or ISBN-13") == "ISBN-10 o ISBN-13")
    end
end)
test("Missing UI preference uses KOReader's active language", function()
    settings.language = nil; core.current_lang = "es"
    assert(_("Cover updated") == "Portada actualizada")
    core.current_lang = "C"
end)
test("Unsupported language and untranslated text fall back without changing core gettext", function()
    settings.language = "fr"
    assert(_("Cover search") == "Cover search" and _("Close") == "native close")
    settings.language = "es"
    assert(_("Unknown future string") == "Unknown future string")
    assert(core.current_lang == "C" and core.translation.Close == "native close" and next(core.context) == nil)
end)
test("Every Spanish entry preserves printf arguments and explicit line breaks", function()
    local function placeholders(text)
        local values = {}
        for value in text:gmatch("%%[%d%.%+%-%s#]*%a") do values[#values + 1] = value end
        return table.concat(values, "|")
    end
    for original, translated in pairs(spanish) do
        assert(type(translated) == "string" and translated ~= "", original)
        assert(placeholders(original) == placeholders(translated), "Changed format arguments: " .. original)
        local _, original_lines = original:gsub("\n", "")
        local _, translated_lines = translated:gsub("\n", "")
        assert(original_lines == translated_lines, "Changed line breaks: " .. original)
    end
end)
test("Spanish catalog covers every localized plugin string", function()
    local messages = {}
    local function collect(literal)
        local text = assert(loadstring("return " .. literal))()
        assert(spanish[text], "Missing Spanish translation: " .. text)
        messages[text] = true
    end
    for _, path in ipairs({ "main.lua", "_meta.lua", "coversearch/dialogs.lua", "coversearch/tile.lua",
        "coversearch/providers.lua", "coversearch/http.lua", "coversearch/images.lua", "coversearch/cache.lua", "coversearch/store.lua" }) do
        local file = assert(io.open("coversearch.koplugin/" .. path, "rb"))
        local source = file:read("*a"); file:close()
        for literal in source:gmatch('_%(%s*(".-")') do collect(literal) end
        for singular, plural in source:gmatch('N_%(%s*(".-")%s*,%s*(".-")') do collect(singular); collect(plural) end
    end
    local count = 0
    for _ in pairs(messages) do count = count + 1 end
    assert(count >= 80, "Expected to check UI, provider, download, image, cache, and storage strings")
    print("Verified Spanish coverage for " .. count .. " source strings")
end)
test("Localized provider counts use singular, plural, and untranslated source names", function()
    settings.language = "es"
    local providers = require("coversearch/providers")
    local originals = {}
    for _, source in ipairs(providers.list) do
        originals[source.id] = providers[source.id]
        providers[source.id] = function()
            local results = {}
            local count = source.id == "openlibrary" and 1 or source.id == "apple" and 2 or 0
            for index = 1, count do results[index] = { url = source.id .. index } end
            return results
        end
    end
    local result = providers.search({}, {}, { enabled = {} })
    assert(result.statuses[1] == "Open Library: 1 portada")
    assert(result.statuses[2] == "Apple Books: 2 portadas")
    assert(result.statuses[3] == "Goodreads: 0 portadas")
    for id, original in pairs(originals) do providers[id] = original end
    local enabled = {}
    for _, source in ipairs(providers.list) do enabled[source.id] = source.id == "amazon" end
    result = providers.search({ get = function() return "validateCaptcha" end }, { title = "Dune", author = "", isbn = "" },
        { enabled = enabled, amazon_domain = "com" })
    assert(result.statuses[1] == "Amazon: " .. spanish["Amazon requires a browser verification; try another source"], result.statuses[1])
end)
test("Actual image, cache, and storage error messages are translated", function()
    settings.language = "es"
    local _, image_error = require("coversearch/images").inspect(nil)
    assert(image_error == "Imagen vacía")
    local _, cache_error = require("coversearch/cache").reserve({ cache_limit = 1 }, 2)
    assert(cache_error == "La imagen supera el límite de la caché de portadas")
    local _, storage_error = require("coversearch/store").reset({ covers = function() return { "cover.jpg" } end,
        remove = function() return nil end }, "book.epub")
    assert(storage_error == "No se pudo eliminar la portada personalizada")
end)
print("All " .. passed .. " localization checks passed")
