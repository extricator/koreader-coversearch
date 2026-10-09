-- SPDX-License-Identifier: AGPL-3.0-or-later
local Model = {}

function Model.trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

function Model.encode(value)
    return tostring(value or ""):gsub("[^%w%-._~]", function(c)
        return string.format("%%%02X", c:byte())
    end)
end

local function isbnText(value)
    local s = tostring(value or "")
    -- Normalize typographic separators before parsing; queries always use compact ISBNs.
    for _, dash in ipairs({ "‐", "‑", "‒", "–", "—", "−" }) do s = s:gsub(dash, "-") end
    for _, space in ipairs({ " ", " ", " " }) do s = s:gsub(space, " ") end
    return Model.trim(s)
end

function Model.isbn(value)
    local s = isbnText(value):upper():gsub("^URN:ISBN:", "")
        :gsub("^ISBN%s*%-?%s*1[03]%s*:?%s*", ""):gsub("^ISBN:?%s*", "")
    s = s:gsub("[%s%-]", "")
    if #s == 13 and s:match("^97[89]%d+$") then
        local sum = 0
        for i = 1, 13 do sum = sum + tonumber(s:sub(i, i)) * (i % 2 == 0 and 3 or 1) end
        if sum % 10 == 0 then return s end
    elseif #s == 10 and s:match("^%d%d%d%d%d%d%d%d%d[%dX]$") then
        local sum = 0
        for i = 1, 10 do
            local c = s:sub(i, i)
            sum = sum + (c == "X" and 10 or tonumber(c)) * (11 - i)
        end
        if sum % 11 == 0 then return s end
    end
end

function Model.isbn13(value)
    local isbn = Model.isbn(value)
    if not isbn or #isbn == 13 then return isbn end
    local prefix, sum = "978" .. isbn:sub(1, 9), 0
    for i = 1, 12 do sum = sum + tonumber(prefix:sub(i, i)) * (i % 2 == 0 and 3 or 1) end
    return prefix .. tostring((10 - sum % 10) % 10)
end

function Model.isbn10(value)
    local isbn = Model.isbn(value)
    if not isbn or #isbn == 10 then return isbn end
    if isbn:sub(1, 3) ~= "978" then return end
    local prefix, sum = isbn:sub(4, 12), 0
    for i = 1, 9 do sum = sum + tonumber(prefix:sub(i, i)) * (11 - i) end
    local check = (11 - sum % 11) % 11
    return prefix .. (check == 10 and "X" or tostring(check))
end

local function isISBNKey(key)
    key = isbnText(key):lower():gsub("[%s%-]", "")
    return key == "isbn" or key == "isbn10" or key == "isbn13"
end

local function extractISBN(value)
    local isbn = Model.isbn(value)
    if isbn then return isbn end
    for digits in isbnText(value):gmatch("%d[%d%s%-]*[%dXx]") do
        isbn = Model.isbn(digits)
        if isbn then return isbn end
    end
end

function Model.metadata(props, filename)
    props = props or {}
    local title = Model.trim(props.title)
    if title == "" then title = tostring(filename or ""):match("([^/]+)$") or ""; title = title:gsub("%.[^.]+$", "") end
    local identifiers, entries = props.identifiers or "", {}
    local function add(value, key)
        if type(value) ~= "string" then return end
        for part in value:gmatch("[^\n;,]+") do
            local text = isbnText(part)
            local upper = text:upper()
            local explicit = isISBNKey(key) or upper:match("^URN:ISBN:") ~= nil
                or (upper:match("^ISBN") ~= nil and Model.isbn(text) ~= nil)
            -- Keep typed identifiers such as ASIN, UUID, and catalog IDs out of the fallback.
            local untyped = key == nil and not text:match("^%a[%w_%-]*%s*:")
            entries[#entries + 1] = { text = text, explicit = explicit, untyped = untyped }
        end
    end
    if type(identifiers) == "table" then
        -- Prefer marked ISBNs regardless of table iteration order; retain list order.
        local keys = {}
        for key in pairs(identifiers) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b)
            if type(a) == "number" and type(b) == "number" then return a < b end
            if type(a) == "number" then return true end
            if type(b) == "number" then return false end
            return tostring(a) < tostring(b)
        end)
        for _, key in ipairs(keys) do add(identifiers[key], type(key) == "string" and key or nil) end
    else
        add(tostring(identifiers))
    end
    local isbns, seen = {}, {}
    local function collect(value)
        local isbn = Model.isbn(value)
        if not isbn then return end
        local identity = Model.isbn13(isbn)
        if not seen[identity] then
            seen[identity] = true
            isbns[#isbns + 1] = isbn
        end
    end
    collect(props.isbn)
    for _, priority in ipairs({ "explicit", "untyped" }) do
        for _, entry in ipairs(entries) do
            if entry[priority] then collect(extractISBN(entry.text)) end
        end
    end
    -- KOReader separates multiple authors with newlines. A single author improves searches.
    local author = Model.trim(props.authors or props.author):match("[^\n]+") or ""
    return { title = title, author = author, isbn = isbns[1] or "", isbns = isbns }
end

function Model.query(book)
    return Model.trim(book.title .. " " .. (book.author or ""))
end

function Model.shorten(value, count)
    local s, chars, last = tostring(value or ""), 0, 0
    for pos in s:gmatch("()[%z\1-\127\194-\244][\128-\191]*") do
        chars = chars + 1
        if chars > count then return s:sub(1, last) .. "…" end
        local next_pos = pos + 1
        while next_pos <= #s and s:byte(next_pos) >= 128 and s:byte(next_pos) <= 191 do next_pos = next_pos + 1 end
        last = next_pos - 1
    end
    return s
end

function Model.unescape(value)
    local s = tostring(value or "")
    local entities = { amp = "&", quot = '"', apos = "'", lt = "<", gt = ">", nbsp = " " }
    return (s:gsub("&(#?[%w]+);", function(entity)
        if entities[entity] then return entities[entity] end
        local n = entity:match("^#(%d+)$") or entity:match("^#x(%x+)$")
        n = n and tonumber(n, entity:sub(1, 2) == "#x" and 16 or 10)
        if n and n > 0 and n <= 0x10FFFF and not (n >= 0xD800 and n <= 0xDFFF) then
            if n < 128 then return string.char(n) end
            if n < 2048 then return string.char(192 + math.floor(n / 64), 128 + n % 64) end
            if n < 65536 then return string.char(224 + math.floor(n / 4096), 128 + math.floor(n / 64) % 64, 128 + n % 64) end
            return string.char(240 + math.floor(n / 262144), 128 + math.floor(n / 4096) % 64, 128 + math.floor(n / 64) % 64, 128 + n % 64)
        end
        return "&" .. entity .. ";"
    end))
end

function Model.imageURL(value)
    if type(value) ~= "string" then return end
    local u = Model.unescape(value):gsub("^http://", "https://")
    if u:match("^https://[^/%s@]+/[^%s]*$") then return u end
end

-- Round-robin sources so the first few choices include several catalogs.
function Model.interleave(groups)
    local out, seen, index = {}, {}, 1
    while true do
        local any = false
        for _, group in ipairs(groups) do
            local item = group[index]
            if item then
                any = true
                if not seen[item.url] then out[#out + 1] = item; seen[item.url] = true end
            end
        end
        if not any then break end
        index = index + 1
    end
    return out
end

return Model
