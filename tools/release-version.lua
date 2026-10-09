-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Numeric release versions; the prerelease flag is GitHub metadata, not a suffix.
local M = {}

function M.parse(value)
    local parts = { value:match("^(%d+)%.(%d+)%.(%d+)$") }
    assert(#parts == 3, "Version must be X.Y.Z without a v prefix or suffix")
    for i, part in ipairs(parts) do
        parts[i] = tonumber(part)
        assert(tostring(parts[i]) == part, "Version must be X.Y.Z without leading zeros")
    end
    return parts
end

function M.compare(a, b)
    local x, y = M.parse(a), M.parse(b)
    for i = 1, 3 do
        if x[i] ~= y[i] then return x[i] < y[i] and -1 or 1 end
    end
    return 0
end

function M.select(current, mode, custom, published)
    M.parse(current)
    mode = ({ Automatic = "automatic", ["Use code version"] = "code",
        Patch = "patch", Minor = "minor", Major = "major" })[mode] or mode
    assert(({ automatic = true, code = true, patch = true, minor = true, major = true })[mode],
        "Unknown version selection")
    local latest
    for _, tag in ipairs(published) do
        local version = tag:match("^v(%d+%.%d+%.%d+)$")
        if version and pcall(M.parse, version) and (not latest or M.compare(version, latest) > 0) then
            latest = version
        end
    end
    local selected
    if custom ~= "" then
        M.parse(custom)
        selected = custom
    elseif mode == "code" or (mode == "automatic" and (not latest or M.compare(current, latest) > 0)) then
        selected = current
    else
        local base = latest and M.compare(latest, current) > 0 and latest or current
        local parts = M.parse(base)
        if mode == "major" then
            parts = { parts[1] + 1, 0, 0 }
        elseif mode == "minor" then
            parts = { parts[1], parts[2] + 1, 0 }
        else
            parts[3] = parts[3] + 1
        end
        selected = table.concat(parts, ".")
    end
    assert(not latest or M.compare(selected, latest) > 0,
        "Version must be newer than published releases (including prereleases): v" .. (latest or ""))
    return selected
end

function M.write(path, version)
    M.parse(version)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    local updated, count = source:gsub('(version%s*=%s*")[^"]+("%s*,)', function(before, after)
        return before .. version .. after
    end)
    assert(count == 1, "Expected one version field in plugin metadata")
    file = assert(io.open(path, "wb"))
    assert(file:write(updated))
    assert(file:close())
end

return M
