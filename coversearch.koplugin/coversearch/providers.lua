-- SPDX-License-Identifier: AGPL-3.0-or-later
local Model = require("coversearch/model")
local _ = require("coversearch/i18n")
local N_ = _.ngettext
local Providers = {}

Providers.list = {
    { id = "openlibrary", name = "Open Library", isbn_search = true },
    { id = "apple", name = "Apple Books" },
    { id = "goodreads", name = "Goodreads", isbn_search = true },
    { id = "amazon", name = "Amazon", isbn_search = true },
    { id = "overdrive", name = "OverDrive", isbn_search = true },
}

local function candidate(out, source, image, title, author, page, isbn)
    local address = Model.imageURL(image)
    if address then
        out[#out + 1] = {
            source = source, url = address, title = Model.unescape(title),
            author = author or "", page = page or "", isbn = isbn or "",
        }
    end
end

function Providers.openlibrary(client, book, prefs)
    local query = book.isbn ~= "" and ("isbn=" .. Model.encode(book.isbn))
        or ("title=" .. Model.encode(book.title) .. "&author=" .. Model.encode(book.author))
    local data = client:json("https://openlibrary.org/search.json?" .. query
        .. "&limit=" .. prefs.results .. "&fields=key,title,author_name,cover_i")
    local out = {}
    for _, item in ipairs(data.docs or {}) do
        if item.cover_i and tonumber(item.cover_i) and tonumber(item.cover_i) > 0 then
            candidate(out, "Open Library", "https://covers.openlibrary.org/b/id/" .. item.cover_i .. "-L.jpg?default=false",
                item.title, table.concat(item.author_name or {}, ", "), "https://openlibrary.org" .. (item.key or ""))
        end
    end
    return out
end

function Providers.apple(client, book, prefs)
    local data = client:json("https://itunes.apple.com/search?entity=ebook&media=ebook&country=" .. prefs.country
        .. "&limit=" .. prefs.results .. "&term=" .. Model.encode(Model.query(book)))
    local out = {}
    for _, item in ipairs(data.results or {}) do
        local image = item.artworkUrl100 or item.artworkUrl60
        if image then
            -- This CDN size request is best effort. Never report the requested size as the actual resolution.
            image = image:gsub("/%d+x%d+bb[^/]*%.jpg", "/1600x1600bb.jpg")
            candidate(out, "Apple Books", image, item.trackName, item.artistName, item.trackViewUrl)
        end
    end
    return out
end

function Providers.goodreads(client, book, prefs)
    local query = book.isbn ~= "" and book.isbn or Model.query(book)
    local data = client:json("https://www.goodreads.com/book/auto_complete?format=json&q=" .. Model.encode(query))
    local out = {}
    for _, item in ipairs(data) do
        if #out >= prefs.results then break end
        if item.imageUrl and not item.imageUrl:find("nophoto", 1, true) then
            local image = item.imageUrl:gsub("%._[^/]-_%.([%w]+)$", ".%1")
            candidate(out, "Goodreads", image, item.bookTitleBare or item.title,
                type(item.author) == "table" and item.author.name or "", "https://www.goodreads.com" .. (item.bookUrl or ""))
        end
    end
    return out
end

local function attr(tag, name)
    name = name:gsub("(%W)", "%%%1")
    return tag:match('%s' .. name .. '%s*=%s*"([^"]*)"') or tag:match("%s" .. name .. "%s*=%s*'([^']*)'")
end

function Providers.amazon(client, book, prefs)
    local host = "https://www.amazon." .. prefs.amazon_domain
    local address = host .. "/s?i=stripbooks&k=" .. Model.encode(book.isbn ~= "" and book.isbn or Model.query(book))
    local body = client:get(address)
    if body:find("validateCaptcha", 1, true) or body:find("api-services-support@amazon.com", 1, true) then
        error(_("Amazon requires a browser verification; try another source"))
    end
    local out, seen = {}, {}
    for tag in body:gmatch("<img%s[^>]+>") do
        local class = " " .. (attr(tag, "class") or "") .. " "
        if class:find(" s%-image ") then
            local image = attr(tag, "src")
            if image and image:find("media%-amazon%.com/images/I/") then
                image = Model.unescape(image):gsub("%._[^/]-_%.([%w]+)$", ".%1")
                if not seen[image] then
                    candidate(out, "Amazon", image, attr(tag, "alt") or book.title, "", address)
                    seen[image] = true
                end
                if #out >= prefs.results then break end
            end
        end
    end
    -- A recognized search page may have no candidates. Unknown/blocked layouts remain errors.
    if #out == 0 and not body:match('data%-component%-type%s*=%s*["\']s%-search%-results["\']') then
        error(_("No cover images in Amazon search (page layout or access may have changed)"))
    end
    return out
end

function Providers.overdrive(client, book, prefs)
    local query = book.isbn ~= "" and book.isbn or Model.query(book)
    local address = "https://www.overdrive.com/search?f-formatClassification=eBook&q=" .. Model.encode(query)
    local body = client:get(address)
    local out, seen = {}, {}
    for tag in body:gmatch("<img%s[^>]+>") do
        local image, id = attr(tag, "src"), attr(tag, "data-id")
        if image and id and id:match("^%d+$") and attr(tag, "data-ga-action") == "cover"
            and image:match("^https://img%d+%.od%-cdn%.com/ImageType%-%d+/") then
            image = image:gsub("{", "%%7B"):gsub("}", "%%7D")
            -- Type 100 is the larger cover. It omits Type 400's optional three shard directories.
            local large = image:gsub("(ImageType%-400/[^/]+/)[^/]+/[^/]+/[^/]+/(%%7B)", "%1%2")
                :gsub("ImageType%-400/", "ImageType-100/"):gsub("[Ii][Mm][Gg]400%.", "Img100.")
            if not seen[id] then
                candidate(out, "OverDrive", large, attr(tag, "data-title") or (attr(tag, "alt") or ""):gsub("^cover image of ", ""),
                    "", "https://www.overdrive.com/media/" .. id)
                if out[#out] and large ~= image then out[#out].fallback_url = image end
                seen[id] = true
                if #out >= prefs.results then break end
            end
        end
    end
    if #out == 0 and not body:find("title%-result") then
        error(_("No cover results in OverDrive search (page layout or access may have changed)"))
    end
    return out
end

function Providers.search(client, book, prefs)
    local groups, statuses = {}, {}
    local isbn = Model.isbn(book.isbn)
    local equivalent = isbn and (#isbn == 10 and Model.isbn13(isbn) or Model.isbn10(isbn))
    for _, source in ipairs(Providers.list) do
        if prefs.enabled[source.id] ~= false then
            local ok, results = pcall(Providers[source.id], client, book, prefs)
            if ok and #results == 0 and source.isbn_search and equivalent then
                -- Only an empty successful search gets one equivalent-ISBN attempt.
                -- Never retry HTTP, parsing, or access failures, or broaden to other editions.
                local alternate = {}
                for key, value in pairs(book) do alternate[key] = value end
                alternate.isbn = equivalent
                ok, results = pcall(Providers[source.id], client, alternate, prefs)
            end
            if ok then
                groups[#groups + 1] = results
                statuses[#statuses + 1] = source.name .. ": " .. string.format(N_("%d candidate", "%d candidates", #results), #results)
            else
                -- Strip local Lua file names/line numbers from errors shown on the device.
                statuses[#statuses + 1] = source.name .. ": " .. tostring(results):gsub("^.-:%d+: ", "")
            end
        end
    end
    return { candidates = Model.interleave(groups), statuses = statuses }
end

return Providers
