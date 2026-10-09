-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Store only serializable metadata here: KOReader downloads run in a subprocess.
local _ = require("coversearch/i18n")
local Cache = { LIMIT = 64 * 1024 * 1024 }

function Cache.peek(session, index, stat)
    session.downloads = session.downloads or {}
    local info = session.downloads[index]
    if info and info.path then
        local attrs = stat(info.path)
        if not attrs or attrs.mode ~= "file" then
            session.downloads[index] = nil
            return nil
        end
        info.bytes = attrs.size
    end
    return info
end

function Cache.mark(session, info)
    if info.path then
        session.cache_clock = (session.cache_clock or 0) + 1
        info.last_used = session.cache_clock
    end
    return info
end

function Cache.get(session, index, stat)
    local info = Cache.peek(session, index, stat)
    return info and Cache.mark(session, info)
end

-- Make room before writing a new file, protecting the incoming page or preview.
-- Use measured file sizes, and stop if a deletion fails rather than exceeding the budget.
function Cache.reserve(session, bytes, protected, stat, remove)
    local limit = session.cache_limit or Cache.LIMIT
    if bytes > limit then return nil, _("Image exceeds the cover cache budget") end
    local total, victims = 0, {}
    session.downloads = session.downloads or {}
    for index in pairs(session.downloads) do
        local info = Cache.peek(session, index, stat)
        if info and info.path then
            total = total + info.bytes
            if not protected[index] then
                victims[#victims + 1] = { index = index, info = info }
            end
        end
    end
    table.sort(victims, function(a, b)
        local x, y = a.info.last_used or 0, b.info.last_used or 0
        return x < y or (x == y and a.index < b.index)
    end)
    for victim_index, victim in ipairs(victims) do
        if total + bytes <= limit then break end
        local removed, err = remove(victim.info.path)
        if not removed and stat(victim.info.path) then
            return nil, string.format(_("Could not free cover cache space: %s"), tostring(err))
        end
        total = total - victim.info.bytes
        session.downloads[victim.index] = nil
    end
    if total + bytes > limit then return nil, _("Not enough space in the cover cache budget") end
    return true
end

return Cache
