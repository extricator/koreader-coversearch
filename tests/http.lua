package.path = "coversearch.koplugin/?.lua;" .. package.path
local replies, calls, resets, clock = {}, {}, 0, 0
package.preload["socket.http"] = function() return {
    request = function(args)
        calls[#calls + 1] = args
        local reply = table.remove(replies, 1); assert(reply, "No mock response")
        if reply.exception then error(reply.exception) end
        for _, chunk in ipairs(reply.chunks or {}) do
            if reply.delay then clock = clock + reply.delay end
            local ok, err = args.sink(chunk)
            if not ok then return nil, err end
        end
        args.sink(nil)
        return 1, reply.code or 200, reply.headers or {}
    end,
} end
package.preload["socketutil"] = function() return { set_timeout = function() end, reset_timeout = function() resets = resets + 1 end } end
package.preload["socket"] = function() return { gettime = function() return clock end } end
package.preload["socket.url"] = function() return { absolute = function(base, to) return to:match("^https?://") and to or base:match("^https://[^/]+") .. to end } end
package.preload["json"] = function() return { decode = function(body) if body == "valid" then return { ok = true } end; error("Malformed JSON") end } end
local HTTP = require("coversearch/http")
local passed = 0
local function test(name, fn)
    replies, calls, resets, clock = {}, {}, 0, 0
    local ok, err = pcall(fn)
    if not ok then io.stderr:write("FAIL " .. name .. ": " .. tostring(err) .. "\n"); os.exit(1) end
    passed = passed + 1; print("PASS " .. name)
end
test("Bounded HTTP body and explicit identity encoding", function()
    replies = {{ chunks = { "ab", "cd" } }}
    assert(HTTP:get("https://example.com/a", 4) == "abcd")
    assert(calls[1].headers["Accept-Encoding"] == "identity" and calls[1].redirect == false)
    assert(resets == 1)
end)
test("Download cap failure restores KOReader socket timeouts", function()
    replies = {{ chunks = { "abcd", "e" } }}
    assert(not pcall(HTTP.get, HTTP, "https://example.com/a", 4)); assert(resets == 1)
end)
test("Total response time bound", function()
    replies = {{ chunks = { "a", "b" }, delay = 11 }}
    assert(not pcall(HTTP.get, HTTP, "https://example.com/a")); assert(resets == 1)
end)
test("Relative redirects and rejected unsafe redirect", function()
    replies = {{ code = 302, headers = { location = "/b" } }, { chunks = { "result" } }}
    assert(HTTP:get("https://example.com/a") == "result"); assert(calls[2].url == "https://example.com/b")
    replies = {{ code = 302, headers = { location = "https://user@example.com/b" } }}
    assert(not pcall(HTTP.get, HTTP, "https://example.com/a"))
end)
test("Redirect loop bounded to five requests", function()
    for _ = 1, 5 do replies[#replies + 1] = { code = 302, headers = { location = "/b" } } end
    assert(not pcall(HTTP.get, HTTP, "https://example.com/a")); assert(#calls == 5 and resets == 5)
end)
test("Rate limit errors and thrown requests restore timeouts", function()
    replies = {{ code = 429 }}
    local ok, err = pcall(HTTP.get, HTTP, "https://example.com/a")
    assert(not ok and tostring(err):find("rate limited", 1, true)); assert(resets == 1)
    replies = {{ exception = "bad socket" }}
    assert(not pcall(HTTP.get, HTTP, "https://example.com/a")); assert(resets == 2)
end)
test("JSON parsing reports invalid responses", function()
    replies = {{ chunks = { "valid" } }, { chunks = { "<html>captcha</html>" } }}
    assert(HTTP:json("https://example.com/a").ok)
    assert(not pcall(HTTP.json, HTTP, "https://example.com/a"))
end)
print(string.format("\n%d HTTP tests passed", passed))
