-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Run from the repository root; an optional release tag must match the metadata.
package.path = "coversearch.koplugin/?.lua;" .. package.path
local version = dofile("coversearch.koplugin/_meta.lua").version
local major, minor, patch = version:match("^(%d+)%.(%d+)%.(%d+)$")
assert(major and tostring(tonumber(major)) == major and tostring(tonumber(minor)) == minor
    and tostring(tonumber(patch)) == patch, "Version must be X.Y.Z without leading zeros")
assert(not arg[1] or arg[1] == "" or arg[1] == "v" .. version,
    "Release tag must match plugin metadata: v" .. version)
print(version)
