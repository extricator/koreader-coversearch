-- SPDX-License-Identifier: AGPL-3.0-or-later
local http = require("socket.http")
local socketutil = require("socketutil")
local socket = require("socket")
local url = require("socket.url")
local JSON = require("json")
local Model = require("coversearch/model")
local _ = require("coversearch/i18n")

local HTTP = {}

function HTTP:get(address, limit)
    address = Model.imageURL(address)
    if not address then error(_("Invalid HTTPS URL")) end
    limit = limit or 3 * 1024 * 1024
    for redirect_count = 1, 5 do
        local chunks, size, start = {}, 0, socket.gettime()
        socketutil:set_timeout(8, 20)
        local ok, result, code, headers = pcall(http.request, {
            url = address,
            redirect = false,
            headers = {
                ["User-Agent"] = "Mozilla/5.0 (compatible; KOReaderCoverSearch/1.0; https://github.com/koreader/koreader)",
                ["Accept-Encoding"] = "identity",
                ["Accept"] = "application/json, image/jpeg, image/png, text/html;q=0.8, */*;q=0.5",
            },
            sink = function(chunk, err)
                if err then return nil, err end
                if socket.gettime() - start > 20 then return nil, _("Request timed out") end
                if chunk then
                    size = size + #chunk
                    if size > limit then return nil, _("Response exceeds download limit") end
                    chunks[#chunks + 1] = chunk
                end
                return 1
            end,
        })
        socketutil:reset_timeout()
        if not ok then error(_("Network request failed")) end
        code = tonumber(code)
        if not result then error(string.format(_("Network request failed: %s"), tostring(code or _("timeout or download limit")))) end
        if code == 200 then return table.concat(chunks), headers end
        if code and code >= 300 and code < 400 and headers and headers.location then
            address = Model.imageURL(url.absolute(address, headers.location))
            if not address then error(_("Invalid redirect")) end
        else
            error("HTTP " .. tostring(code or "error") .. (code == 429 and _(" (rate limited; try later)") or ""))
        end
    end
    error(_("Too many redirects"))
end

function HTTP:json(address)
    local body = self:get(address)
    local ok, data = pcall(JSON.decode, body)
    if not ok or type(data) ~= "table" then error(_("Source did not return valid JSON")) end
    return data
end

return HTTP
