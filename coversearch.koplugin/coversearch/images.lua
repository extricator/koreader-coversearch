-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Read the actual encoded dimensions without allocating a full-size bitmap.
local _ = require("coversearch/i18n")
local Images = {}
local function be(data, pos, count)
    if pos + count - 1 > #data then return end
    local n = 0
    for i = pos, pos + count - 1 do n = n * 256 + data:byte(i) end
    return n
end

function Images.inspect(data)
    if type(data) ~= "string" then return nil, _("Empty image") end
    local w, h, ext
    if data:sub(1, 8) == "\137PNG\13\10\26\10" and data:sub(13, 16) == "IHDR" then
        w, h, ext = be(data, 17, 4), be(data, 21, 4), "png"
    elseif data:sub(1, 2) == "\255\216" then
        local pos = 3
        while pos <= #data do
            if data:byte(pos) ~= 255 then break end
            while data:byte(pos) == 255 do pos = pos + 1 end
            local marker = data:byte(pos)
            pos = pos + 1
            if not marker or marker == 217 or marker == 218 then break end
            if marker ~= 1 and not (marker >= 208 and marker <= 215) then
                local length = be(data, pos, 2)
                if not length or length < 2 or pos + length - 1 > #data then break end
                if (marker >= 192 and marker <= 195) or (marker >= 197 and marker <= 199)
                    or (marker >= 201 and marker <= 203) or (marker >= 205 and marker <= 207) then
                    h, w, ext = be(data, pos + 3, 2), be(data, pos + 5, 2), "jpg"
                    break
                end
                pos = pos + length
            end
        end
    end
    if not w or not h or w < 100 or h < 100 then
        return nil, _("Missing cover, placeholder, or unsupported image (JPEG/PNG required)")
    end
    if w > 10000 or h > 10000 or w * h > 20000000 then
        return nil, _("Image exceeds the 20 megapixel Kindle memory limit")
    end
    return { width = w, height = h, extension = ext, bytes = #data }
end

return Images
