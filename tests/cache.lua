-- Dependency-free cache policy tests. Small budgets make eviction cases deterministic.
package.path = "coversearch.koplugin/?.lua;" .. package.path
local Cache = require("coversearch/cache")
local passed = 0
local function test(name, fn)
    fn()
    passed = passed + 1
    print("PASS " .. name)
end
local function fixture(limit)
    local session = { downloads = {}, cache_limit = limit }
    local files = {}
    local function stat(path) return files[path] and { mode = "file", size = files[path] } end
    local function remove(path) files[path] = nil; return true end
    local function put(index, size, protected)
        assert(Cache.reserve(session, size, protected or { [index] = true }, stat, remove))
        local path = tostring(index)
        files[path] = size
        session.downloads[index] = Cache.mark(session, { path = path, bytes = size })
        local total = 0
        for _, bytes in pairs(files) do total = total + bytes end
        assert(total <= limit, "Cache exceeded its budget")
    end
    return session, files, stat, remove, put
end
test("More than eight small covers fit without eviction", function()
    local session, files, stat, _, put = fixture(64)
    for i = 1, 20 do put(i, 3) end
    for i = 1, 20 do assert(Cache.get(session, i, stat) and files[tostring(i)] == 3) end
end)
test("Revisited covers survive eviction of the least recently used", function()
    local session, files, stat, _, put = fixture(12)
    for i = 1, 3 do put(i, 4) end
    Cache.get(session, 1, stat)
    put(4, 4)
    assert(files['1'] and not files['2'] and files['3'] and files['4'])
    assert(not session.downloads[2])
end)
test("Protect the entire incoming page including covers not yet accessed", function()
    local session, files, _, _, put = fixture(16)
    for i = 1, 4 do put(i, 4) end
    put(5, 4, { [1] = true, [2] = true, [5] = true, [6] = true })
    put(6, 4, { [1] = true, [2] = true, [5] = true, [6] = true })
    assert(files['1'] and files['2'] and files['5'] and files['6'])
    assert(not files['3'] and not files['4'])
end)
test("Actual disk sizes determine how much space must be reclaimed", function()
    local session, files, stat, remove, put = fixture(12)
    put(1, 4); put(2, 4)
    files['1'] = 8
    assert(Cache.reserve(session, 4, { [2] = true }, stat, remove))
    assert(not files['1'] and files['2'])
end)
test("Missing files become cache misses; failure records consume no disk budget", function()
    local session, files, stat, _, put = fixture(4)
    put(1, 4); files['1'] = nil
    assert(not Cache.get(session, 1, stat) and not session.downloads[1])
    session.downloads[2] = { error = "HTTP 403" }
    put(3, 4)
    assert(Cache.get(session, 2, stat).error == "HTTP 403")
end)
test("A failed deletion cannot allow a download to exceed the limit", function()
    local session, files, stat, _, put = fixture(4)
    put(1, 4)
    local ok, err = Cache.reserve(session, 4, {}, stat, function() return nil, "permission denied" end)
    assert(not ok and err:find("permission denied", 1, true))
    assert(files['1'] and session.downloads[1])
end)
test("An oversized image or all-protected cache is refused", function()
    local session, files, stat, remove, put = fixture(4)
    put(1, 4)
    assert(not Cache.reserve(session, 5, {}, stat, remove))
    assert(not Cache.reserve(session, 1, { [1] = true }, stat, remove))
    assert(files['1'])
end)
print("All " .. passed .. " cache checks passed")
