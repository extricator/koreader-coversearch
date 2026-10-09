-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Standalone plugins need their own strings; follow KOReader's UI language
-- without replacing or modifying its shared gettext catalog.
local available, gettext = pcall(require, "gettext")
if not available then gettext = nil end -- Keep dependency-free checks usable.
local catalogs = {}
local I18N = {}

function I18N.language()
    local language = G_reader_settings and G_reader_settings:readSetting("language")
    if type(language) ~= "string" or language == "" then
        language = gettext and gettext.current_lang or "C"
    end
    -- Regional Spanish locales share the Spanish catalog, including es-MX/es_ES.
    return language:lower():match("^([a-z]+)") or "c"
end

local function catalog(language)
    if catalogs[language] == nil then
        local ok, messages = pcall(require, "coversearch/l10n/" .. language)
        catalogs[language] = ok and type(messages) == "table" and messages or false
    end
    return catalogs[language]
end

setmetatable(I18N, { __call = function(_, msgid)
    local language = I18N.language()
    if language == "c" or language == "en" then return msgid end
    local messages = catalog(language)
    return messages and messages[msgid] or (gettext and gettext(msgid)) or msgid
end })

function I18N.ngettext(singular, plural, count)
    local language = I18N.language()
    if language == "c" or language == "en" or catalog(language) then
        return I18N(count == 1 and singular or plural)
    end
    if gettext and gettext.ngettext then return gettext.ngettext(singular, plural, count) end
    return count == 1 and singular or plural
end

return I18N
