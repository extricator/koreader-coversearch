-- SPDX-License-Identifier: AGPL-3.0-or-later
local version = dofile("tools/release-version.lua")
if arg[1] == "write" then
    version.write(assert(arg[2]), assert(arg[3]))
else
    local published = {}
    local published_path = assert(arg[4], "Provide the published-tag file")
    for line in io.lines(published_path) do
        published[#published + 1] = line
    end
    print(version.select(assert(arg[1]), assert(arg[2]), arg[3] or "", published))
end
