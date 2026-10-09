-- Dependency-free ISBN discovery and request-count checks using real provider parsers.
package.path = "coversearch.koplugin/?.lua;" .. package.path
local Model = require("coversearch/model")
local Providers = require("coversearch/providers")
local passed = 0
local function test(name, check)
    local ok, err = pcall(check)
    if not ok then io.stderr:write("FAIL " .. name .. ": " .. tostring(err) .. "\n"); os.exit(1) end
    passed = passed + 1; print("PASS " .. name)
end
local function equal(actual, expected) assert(actual == expected, tostring(actual) .. " ~= " .. tostring(expected)) end

local isbn10, isbn13, isbn979 = "0441172717", "9780441172719", "9791090636071"
test("ISBN labels, Unicode separators, and final lowercase x", function()
    for _, input in ipairs({ isbn13, "ISBN: 978-0-441-17271-9", "ISBN-13: 9780441172719",
        "ISBN 13: 9780441172719", "urn:isbn:9780441172719", "978–0–441–17271–9",
        "978‑0‑441‑17271‑9", "978−0−441−17271−9", "978 0 441 17271 9",
        "978 0 441 17271 9", "978 0 441 17271 9" }) do
        equal(Model.isbn(input), isbn13)
    end
    equal(Model.isbn("ISBN-10: 0-8044-2957-x"), "080442957X")
    equal(Model.isbn(isbn979), isbn979)
end)
test("Invalid check digits and unrelated identifiers stay invalid", function()
    for _, input in ipairs({ "ISBN-13: 9780441172718", "ISBN-10: 0441172718", "ASIN: 0441172717",
        "ISBN: 1234567890", "9791090636072", "ISBN: 9780441172719 extra", "" }) do
        equal(Model.isbn(input), nil)
    end
end)
test("Equivalent conversion works in both directions and preserves X", function()
    equal(Model.isbn13(isbn10), isbn13)
    equal(Model.isbn10(isbn13), isbn10)
    equal(Model.isbn10("9780804429573"), "080442957X")
    equal(Model.isbn13("080442957X"), "9780804429573")
    equal(Model.isbn10(isbn10), isbn10); equal(Model.isbn13(isbn13), isbn13)
    equal(Model.isbn10(isbn979), nil); equal(Model.isbn13(isbn979), isbn979)
    equal(Model.isbn10("9780441172718"), nil)
end)
test("Explicit ISBNs take priority over bare and unrelated identifiers", function()
    equal(Model.metadata({ identifiers = "9780804429573\nASIN:080442957X\nISBN-13:9780441172719" }).isbn, isbn13)
    equal(Model.metadata({ identifiers = { asin = "080442957X", isbn = "ISBN-13:9780441172719" } }).isbn, isbn13)
    equal(Model.metadata({ identifiers = { "9780804429573", "urn:isbn:" .. isbn13 } }).isbn, isbn13)
    equal(Model.metadata({ isbn = "ISBN-10: " .. isbn10, identifiers = "isbn:9780804429573" }).isbn, isbn10)
    equal(Model.metadata({ identifiers = { ["ISBN-10"] = "0-8044-2957-x", ISBN13 = isbn13 } }).isbn, "080442957X")
end)
test("Typed non-ISBN identifiers cannot supply an ISBN", function()
    equal(Model.metadata({ identifiers = "ASIN:0441172717\ngoodreads:9780441172719" }).isbn, "")
    equal(Model.metadata({ identifiers = { asin = isbn10, goodreads = isbn13, isbn = "9780441172718" } }).isbn, "")
    equal(Model.metadata({ identifiers = "urn:uuid:12345678-1234-1234-1234-123456789abc" }).isbn, "")
end)
test("Bare metadata and calibre identifier representations remain supported", function()
    equal(Model.metadata({ identifiers = "ISBN:" .. isbn13 }).isbn, isbn13)
    equal(Model.metadata({ identifiers = "isbn:" .. isbn13 }).isbn, isbn13)
    equal(Model.metadata({ identifiers = { isbn = isbn13 } }).isbn, isbn13)
    equal(Model.metadata({ identifiers = { "9780441172718", isbn10 } }).isbn, isbn10)
    equal(Model.metadata({ identifiers = "Book identifier 978–0–441–17271–9" }).isbn, isbn13)
end)

test("Equivalent ISBNs count as one choice and preserve the dedicated representation", function()
    local book = Model.metadata({ isbn = isbn10, identifiers = "isbn:" .. isbn13 .. "\nisbn:" .. isbn10 })
    equal(#book.isbns, 1); equal(book.isbns[1], isbn10); equal(book.isbn, isbn10)
end)
test("Distinct choices retain priority and ignore unrelated or invalid identifiers", function()
    local book = Model.metadata({ isbn = isbn10,
        identifiers = { "9780804429573", "isbn:9780441013593", "ASIN:080442957X", "isbn:9780441172718" } })
    equal(#book.isbns, 3)
    equal(book.isbns[1], isbn10); equal(book.isbns[2], "9780441013593"); equal(book.isbns[3], "9780804429573")
    equal(#Model.metadata({ identifiers = "ASIN:0441172717" }).isbns, 0)
end)
test("Identifier maps produce deterministic choices without duplicate equivalent pairs", function()
    local book = Model.metadata({ identifiers = { ISBN13 = isbn13, ["ISBN-10"] = isbn10,
        other = "ASIN:080442957X", isbn = "9780441013593" } })
    equal(#book.isbns, 2); equal(book.isbns[1], isbn10); equal(book.isbns[2], "9780441013593")
end)

local sources = { "openlibrary", "goodreads", "amazon", "overdrive" }
local function preferences(selected)
    local enabled = {}
    for _, source in ipairs(Providers.list) do enabled[source.id] = source.id == selected end
    return { enabled = enabled, results = 3, country = "US", amazon_domain = "com" }
end
local function query(isbn) return { title = "Dune", author = "Frank Herbert", isbn = isbn } end
local function response(id, empty)
    if id == "openlibrary" then
        return { docs = empty and {} or {{ title = "Dune", cover_i = 123 }} }
    elseif id == "goodreads" then
        return empty and {} or {{ bookTitleBare = "Dune", imageUrl = "https://images.example.com/cover.jpg" }}
    elseif id == "amazon" then
        return '<div data-component-type="s-search-results">'
            .. (empty and "" or '<img class="s-image" src="https://m.media-amazon.com/images/I/cover.jpg">') .. '</div>'
    elseif id == "overdrive" then
        return '<div class="title-result">'
            .. (empty and "" or '<img src="https://img1.od-cdn.com/ImageType-100/1234-1/cover.jpg" data-id="123" data-ga-action="cover">') .. '</div>'
    elseif id == "apple" then
        return { results = empty and {} or {{ trackName = "Dune", artworkUrl100 = "https://images.example.com/100x100bb.jpg" }} }
    end
end
local function clientFor(id, handler)
    local calls = {}
    local function request(_, url)
        calls[#calls + 1] = url
        return handler(#calls, url)
    end
    return { json = request, get = request }, calls
end

test("Every ISBN-aware source tries the equivalent only after an empty result", function()
    for _, id in ipairs(sources) do
        for _, pair in ipairs({ { isbn10, isbn13 }, { isbn13, isbn10 }, { "080442957X", "9780804429573" } }) do
            local client, calls = clientFor(id, function(index) return response(id, index == 1) end)
            local book = query(pair[1])
            local result = Providers.search(client, book, preferences(id))
            equal(#calls, 2); equal(#result.candidates, 1); equal(#result.statuses, 1)
            assert(calls[1]:find(pair[1], 1, true) and calls[2]:find(pair[2], 1, true))
            equal(book.isbn, pair[1])
        end
    end
end)
test("Successful primary searches make just one request", function()
    for _, id in ipairs(sources) do
        local client, calls = clientFor(id, function() return response(id, false) end)
        local result = Providers.search(client, query(isbn13), preferences(id))
        equal(#calls, 1); equal(#result.candidates, 1)
    end
end)
test("Repeated empty results stop after two requests per source", function()
    for _, id in ipairs(sources) do
        local client, calls = clientFor(id, function() return response(id, true) end)
        local result = Providers.search(client, query(isbn13), preferences(id))
        equal(#calls, 2); equal(#result.candidates, 0); equal(#result.statuses, 1)
        assert(result.statuses[1]:find("0 candidates", 1, true))
    end
end)
test("Equivalent searches retain the configured result limit", function()
    for _, limit in ipairs({ 3, 5, 10 }) do
        local client, calls = clientFor("goodreads", function(index)
            if index == 1 then return {{ bookTitleBare = "Dune", imageUrl = "https://example.com/nophoto.jpg" }} end
            local items = {}
            for i = 1, limit + 1 do
                items[i] = { bookTitleBare = "Dune", imageUrl = "https://images.example.com/" .. i .. ".jpg" }
            end
            return items
        end)
        local prefs = preferences("goodreads"); prefs.results = limit
        local result = Providers.search(client, query(isbn13), prefs)
        equal(#calls, 2); equal(#result.candidates, limit)
    end
end)
test("979, missing, and invalid ISBNs do not get extra requests", function()
    for _, id in ipairs(sources) do
        for _, isbn in ipairs({ isbn979, "", "9780441172718" }) do
            local client, calls = clientFor(id, function() return response(id, true) end)
            Providers.search(client, query(isbn), preferences(id))
            equal(#calls, 1)
        end
    end
end)
test("Apple remains a single title-and-author search even with an ISBN", function()
    local client, calls = clientFor("apple", function() return response("apple", true) end)
    Providers.search(client, query(isbn13), preferences("apple"))
    equal(#calls, 1)
    assert(calls[1]:find("term=Dune%20Frank%20Herbert", 1, true) and not calls[1]:find(isbn13, 1, true))
end)
test("HTTP, timeout, and parsing failures do not trigger equivalent searches", function()
    for _, id in ipairs(sources) do
        for _, failure in ipairs({ "HTTP 429", "HTTP 403", "timeout", "Invalid JSON" }) do
            local client, calls = clientFor(id, function() error(failure) end)
            local result = Providers.search(client, query(isbn13), preferences(id))
            equal(#calls, 1); equal(#result.candidates, 0)
            assert(result.statuses[1]:find(failure, 1, true))
        end
    end
end)
test("Amazon verification and unknown page layouts stay errors without retrying", function()
    for _, body in ipairs({ "validateCaptcha", "<html>unknown page layout</html>" }) do
        local client, calls = clientFor("amazon", function() return body end)
        local result = Providers.search(client, query(isbn13), preferences("amazon"))
        equal(#calls, 1); equal(#result.candidates, 0)
        assert(not result.statuses[1]:find("0 candidates", 1, true))
    end
    local client, calls = clientFor("overdrive", function() return "<html>unknown page layout</html>" end)
    local result = Providers.search(client, query(isbn13), preferences("overdrive"))
    equal(#calls, 1); assert(result.statuses[1]:find("page layout", 1, true))
end)
test("An equivalent-search failure stays isolated and does not retry again", function()
    local client, calls = clientFor("openlibrary", function(index, url)
        if url:find("itunes.apple.com", 1, true) then return response("apple", false) end
        if index == 1 then return response("openlibrary", true) end
        error("HTTP 429")
    end)
    local prefs = preferences("openlibrary"); prefs.enabled.apple = true
    local result = Providers.search(client, query(isbn13), prefs)
    equal(#calls, 3); equal(#result.statuses, 2); equal(#result.candidates, 1)
    assert(result.statuses[1]:find("HTTP 429", 1, true))
    equal(result.candidates[1].source, "Apple Books")
end)
test("Disabled sources make no requests", function()
    local client, calls = clientFor("openlibrary", function() error("must not run") end)
    local prefs = preferences("none"); prefs.enabled.retired_source = true
    local result = Providers.search(client, query(isbn13), prefs)
    equal(#calls, 0); equal(#result.statuses, 0)
end)
print("All " .. passed .. " ISBN checks passed")
