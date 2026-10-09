-- SPDX-License-Identifier: AGPL-3.0-or-later
-- Commit only after a complete staged copy. Keep the previous override recoverable until commit.
local _ = require("coversearch/i18n")
local Store = {}

function Store.apply(deps, book, image, extension)
    local target_dirs = deps.dirs(book)
    local last_error
    for directory_index, dir in ipairs(target_dirs) do
        deps.mkdir(dir)
        local target, stage = dir .. "/cover." .. extension, dir .. "/.coversearch-new"
        local copied, err = deps.copy(image, stage)
        if copied then
            local backups, failed = {}, false
            -- KOReader can find older overrides in more than one metadata location.
            -- Move all of them aside so only one cover will be discoverable after commit.
            for cover_index, old in ipairs(deps.covers(book)) do
                local backup = old .. ".coversearch-backup"
                if deps.exists(backup) then failed = true; last_error = string.format(_("An unfinished cover backup exists: %s"), backup); break end
                local moved, move_error = deps.rename(old, backup)
                if not moved then failed = true; last_error = move_error; break end
                backups[#backups + 1] = { old = old, backup = backup }
            end
            if not failed then
                local committed, commit_error = deps.rename(stage, target)
                if committed then
                    for _, entry in ipairs(backups) do deps.remove(entry.backup) end
                    return true
                end
                last_error = commit_error
            end
            local rollback_errors = {}
            for i = #backups, 1, -1 do
                local restored, restore_error = deps.rename(backups[i].backup, backups[i].old)
                if not restored then rollback_errors[#rollback_errors + 1] = tostring(restore_error) end
            end
            deps.remove(stage)
            if #rollback_errors > 0 then return nil, string.format(_("Cover rollback failed; backup retained: %s"), table.concat(rollback_errors, "; ")) end
            return nil, last_error or _("Could not replace the previous cover")
        end
        deps.remove(stage)
        last_error = err
    end
    return nil, last_error or _("No writable KOReader metadata folder")
end

function Store.reset(deps, book)
    local covers = deps.covers(book)
    for cover_index, file in ipairs(covers) do
        local removed, err = deps.remove(file)
        if not removed then return nil, err or _("Could not remove cover override") end
    end
    return true
end

return Store
