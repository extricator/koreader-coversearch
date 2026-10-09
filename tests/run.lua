-- Dependency-free tests for provider parsing, image headers, and cover transactions.
package.path = "coversearch.koplugin/?.lua;" .. package.path
local Model = require("coversearch/model")
local Images = require("coversearch/images")
local Providers = require("coversearch/providers")
local Store = require("coversearch/store")
local passed = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then io.stderr:write("FAIL " .. name .. ": " .. tostring(err) .. "\n"); os.exit(1) end
    passed = passed + 1
    print("PASS " .. name)
end
local function equal(a, b) assert(a == b, tostring(a) .. " ~= " .. tostring(b)) end
local function be(n, bytes)
    local s = ""
    for _ = 1, bytes do s = string.char(n % 256) .. s; n = math.floor(n / 256) end
    return s
end
local function jpeg(w, h)
    return "\255\216\255\224\0\4ab\255\255\192\0\11\8" .. be(h, 2) .. be(w, 2) .. "\1\1\17\0\255\217"
end
local function png(w, h) return "\137PNG\13\10\26\10" .. be(13, 4) .. "IHDR" .. be(w, 4) .. be(h, 4) .. "\8\2\0\0\0" end

test("ISBN checksum validation and ISBN-10 conversion", function()
    equal(Model.isbn("ISBN: 978-0-441-17271-9"), "9780441172719")
    equal(Model.isbn("0441172717"), "0441172717")
    equal(Model.isbn13("0441172717"), "9780441172719")
    equal(Model.isbn("9780441172718"), nil)
    equal(Model.isbn("1234567890"), nil)
end)
test("KOReader metadata and filename fallback", function()
    local m = Model.metadata({ authors = "Frank Herbert\nOther Author", identifiers = "urn:isbn:9780441172719" }, "/books/Dune.epub")
    equal(m.title, "Dune"); equal(m.author, "Frank Herbert"); equal(m.isbn, "9780441172719")
    equal(Model.metadata({ identifiers = { isbn = "0441172717" } }).isbn, "0441172717")
end)
test("URL encoding, HTTPS image URLs, and UTF-8 shortening", function()
    equal(Model.encode("Dune & Muad'Dib"), "Dune%20%26%20Muad%27Dib")
    equal(Model.imageURL("http://example.com/a.jpg?x=1&amp;y=2"), "https://example.com/a.jpg?x=1&y=2")
    equal(Model.imageURL("file:///etc/passwd"), nil)
    equal(Model.imageURL("https://user@example.com/a.jpg"), nil)
    equal(Model.shorten("áé中😀abc", 4), "áé中😀…")
    equal(Model.unescape("D&#369;ne / El mes&#237;as &#x1F600;"), "Dűne / El mesías 😀")
end)
test("JPEG dimensions, marker padding, and PNG dimensions", function()
    local j = assert(Images.inspect(jpeg(894, 1600)))
    equal(j.width, 894); equal(j.height, 1600); equal(j.extension, "jpg")
    local p = assert(Images.inspect(png(1200, 1800)))
    equal(p.width, 1200); equal(p.height, 1800); equal(p.extension, "png")
end)
test("Reject placeholders, HTML, truncated headers, and oversized images", function()
    equal(Images.inspect(jpeg(1, 1)), nil)
    equal(Images.inspect("<html>captcha</html>"), nil)
    equal(Images.inspect(jpeg(894, 1600):sub(1, 17)), nil)
    equal(Images.inspect(png(10000, 10000)), nil)
end)

local book = { title = "Dune", author = "Frank Herbert", isbn = "" }
local prefs = { results = 3, country = "US", amazon_domain = "com", enabled = {} }
test("Open Library candidates", function()
    local result = Providers.openlibrary({ json = function(_, url)
        assert(url:find("title=Dune&author=Frank%%20Herbert"))
        return { docs = {{ title = "Dune", cover_i = 11481354, key = "/works/OL893415W", author_name = { "Frank Herbert" }, isbn = { "0441172717" } }} }
    end }, book, prefs)
    equal(#result, 1); equal(result[1].url, "https://covers.openlibrary.org/b/id/11481354-L.jpg?default=false")
end)
test("Apple uses a large size request without invented dimensions", function()
    local result = Providers.apple({ json = function() return { results = {{ trackName = "Dune", artistName = "Frank Herbert", artworkUrl100 = "https://is1-ssl.mzstatic.com/image/thumb/a.jpg/100x100bb.jpg" }} } end }, book, prefs)
    equal(result[1].url, "https://is1-ssl.mzstatic.com/image/thumb/a.jpg/1600x1600bb.jpg")
    equal(result[1].width, nil)
end)
test("Goodreads removes only the CDN thumbnail transformation", function()
    local result = Providers.goodreads({ json = function() return {{ bookTitleBare = "Dune", author = { name = "Frank Herbert" }, imageUrl = "https://i.gr-assets.com/images/S/compressed.photo.goodreads.com/books/1555447414i/44767458._SY75_.jpg", bookUrl = "/book/show/44767458-dune" }} end }, book, prefs)
    equal(result[1].url, "https://i.gr-assets.com/images/S/compressed.photo.goodreads.com/books/1555447414i/44767458.jpg")
end)
test("Amazon parses search covers, ignores unrelated images, deduplicates", function()
    local result = Providers.amazon({ get = function() return [[
        <img class="logo" src="https://m.media-amazon.com/images/I/logo.jpg">
        <img alt="Dune &amp; more" class="x s-image y" src="https://m.media-amazon.com/images/I/cover._AC_UY218_.jpg">
        <img class='s-image' src='https://m.media-amazon.com/images/I/cover._AC_UY327_.jpg'>
        <img class="s-image" src="https://other.example.com/advert.jpg">
    ]] end }, book, prefs)
    equal(#result, 1); equal(result[1].title, "Dune & more"); equal(result[1].url, "https://m.media-amazon.com/images/I/cover.jpg")
    equal(pcall(Providers.amazon, { get = function() return "validateCaptcha" end }, book, prefs), false)
end)
test("Five supported catalogs have search implementations", function()
    local expected = { "openlibrary", "apple", "goodreads", "amazon", "overdrive" }
    equal(#Providers.list, #expected)
    for index, id in ipairs(expected) do
        equal(Providers.list[index].id, id)
        equal(type(Providers[id]), "function")
    end
end)
test("OverDrive parses broad catalog covers, larger URLs, and fallback images", function()
    local result = Providers.overdrive({ get = function(_, url)
        assert(url:find("q=Dune%%20Frank%%20Herbert"))
        assert(url:find("f-formatClassification=eBook", 1, true))
        return [[<img src="/Content/img/logo.svg">
            <img src="https://img1.od-cdn.com/ImageType-400/6645-1/9A5/7B5/E5/{GUID}Img400.jpg" data-title="D&#369;ne" data-id="8208205" data-ga-action="cover">
            <img src="https://img1.od-cdn.com/ImageType-400/6645-1/{GUID}Img400.jpg" data-id="8208205" data-ga-action="cover">
            <img src="https://img1.od-cdn.com/ImageType-400/1523-1/{OTHER}IMG400.JPG" data-title="Dune" data-id="1243691" data-ga-action="cover">
            <img src="https://unrelated.example.com/cover.jpg" data-id="100" data-ga-action="cover">]]
    end }, book, prefs)
    equal(#result, 2)
    equal(result[1].title, "Dűne")
    equal(result[1].url, "https://img1.od-cdn.com/ImageType-100/6645-1/%7BGUID%7DImg100.jpg")
    equal(result[1].fallback_url, "https://img1.od-cdn.com/ImageType-400/6645-1/9A5/7B5/E5/%7BGUID%7DImg400.jpg")
    equal(result[1].page, "https://www.overdrive.com/media/8208205")
    equal(result[2].url, "https://img1.od-cdn.com/ImageType-100/1523-1/%7BOTHER%7DImg100.JPG")
end)
test("Source failure isolation and round-robin selection", function()
    local client = {
        json = function(_, url)
            if url:find("openlibrary.org", 1, true) then return { docs = {{ title = "Dune", cover_i = 1 }, { title = "Dune", cover_i = 2 }} } end
            if url:find("itunes.apple.com", 1, true) then return { results = {{ artworkUrl100 = "https://a.com/image/100x100bb.jpg" }} } end
            error("HTTP 429")
        end,
        get = function() error("HTTP 403") end,
    }
    local result = Providers.search(client, book, prefs)
    equal(#result.statuses, 5); equal(#result.candidates, 3)
    equal(result.candidates[1].source, "Open Library"); equal(result.candidates[2].source, "Apple Books")
    assert(table.concat(result.statuses):find("HTTP 429", 1, true))
end)

local function filesystem(initial, failures)
    local fs = {}; for k, v in pairs(initial) do fs[k] = v end
    failures = failures or {}
    local deps = {
        dirs = function() return { "/book.sdr", "/central/book.sdr" } end,
        covers = function()
            local result = {}
            for _, name in ipairs({ "/book.sdr/cover.png", "/book.sdr/cover.jpg", "/central/book.sdr/cover.png" }) do
                if fs[name] then result[#result + 1] = name end
            end
            return result
        end,
        mkdir = function() end,
        copy = function(from, to) if failures.copy == to then fs[to] = "partial"; return nil, "disk full" end; fs[to] = fs[from]; return true end,
        exists = function(p) return fs[p] ~= nil end,
        rename = function(from, to)
            if failures.rename == from or failures.target == to then return nil, "rename failed" end
            if not fs[from] then return nil, "missing" end
            fs[to], fs[from] = fs[from], nil; return true
        end,
        remove = function(p) if failures.remove == p then return nil, "read-only" end; fs[p] = nil; return true end,
    }
    return deps, fs
end
test("Atomic replacement across extensions and metadata folders", function()
    local deps, fs = filesystem({ ["/new.jpg"] = "new", ["/book.sdr/cover.png"] = "old", ["/central/book.sdr/cover.png"] = "older" })
    assert(Store.apply(deps, "book", "/new.jpg", "jpg"))
    equal(fs["/book.sdr/cover.jpg"], "new"); equal(fs["/book.sdr/cover.png"], nil); equal(fs["/central/book.sdr/cover.png"], nil)
end)
test("Partial-copy failure preserves previous override and falls back", function()
    local deps, fs = filesystem({ ["/new.jpg"] = "new", ["/book.sdr/cover.png"] = "old" }, { copy = "/book.sdr/.coversearch-new" })
    assert(Store.apply(deps, "book", "/new.jpg", "jpg"))
    equal(fs["/central/book.sdr/cover.jpg"], "new"); equal(fs["/book.sdr/.coversearch-new"], nil)
end)
test("Commit failure rolls back previous cover", function()
    local deps, fs = filesystem({ ["/new.jpg"] = "new", ["/book.sdr/cover.png"] = "old" }, { target = "/book.sdr/cover.jpg" })
    equal(Store.apply(deps, "book", "/new.jpg", "jpg"), nil)
    equal(fs["/book.sdr/cover.png"], "old"); equal(fs["/book.sdr/cover.jpg"], nil)
end)
test("Moving a later override fails and rolls back earlier moves", function()
    local deps, fs = filesystem({ ["/new.jpg"] = "new", ["/book.sdr/cover.png"] = "old", ["/central/book.sdr/cover.png"] = "older" }, { rename = "/central/book.sdr/cover.png" })
    equal(Store.apply(deps, "book", "/new.jpg", "jpg"), nil)
    equal(fs["/book.sdr/cover.png"], "old"); equal(fs["/central/book.sdr/cover.png"], "older")
end)
test("An existing recovery backup is preserved", function()
    local deps, fs = filesystem({ ["/new.jpg"] = "new", ["/book.sdr/cover.png"] = "old", ["/book.sdr/cover.png.coversearch-backup"] = "recoverable" })
    equal(Store.apply(deps, "book", "/new.jpg", "jpg"), nil)
    equal(fs["/book.sdr/cover.png"], "old"); equal(fs["/book.sdr/cover.png.coversearch-backup"], "recoverable")
end)
test("Reset removes overrides and reports unwritable files", function()
    local deps, fs = filesystem({ ["/book.sdr/cover.png"] = "old" })
    assert(Store.reset(deps, "book")); equal(fs["/book.sdr/cover.png"], nil)
    deps, fs = filesystem({ ["/book.sdr/cover.png"] = "old" }, { remove = "/book.sdr/cover.png" })
    equal(Store.reset(deps, "book"), nil); equal(fs["/book.sdr/cover.png"], "old")
end)
print(string.format("\n%d tests passed", passed))
