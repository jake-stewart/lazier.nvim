local fs = require "lazier.util.fs"
local constants = require "lazier.constants"
local cache = require "lazier.cache"

local function print_hl(hl, message)
    vim.api.nvim_echo({{ message, hl } }, true, {})
end

return function()
    local repo_dir
    for _, candidate in ipairs(constants.repo_locations) do
        if fs.stat(candidate) then
            repo_dir = candidate
            break
        end
    end
    if not repo_dir then
        error("Failed to find lazier repo")
    end

    cache.clear()
    print_hl("Title", "Updating Lazier...")
    local old_version = require("lazier.version")
    local result = vim.fn.systemlist({ "git", "-C", repo_dir, "pull" })
    if type(result) == "string" then
        result = { result }
    end
    if vim.v.shell_error == 0 then
        package.loaded["lazier.version"] = nil
        package.preload["lazier.version"] = nil
        local new_version = require("lazier.version")
        if new_version == old_version then
            vim.print("Already up to date. (" .. new_version .. ")")
        else
            vim.print("Update completed successfully. (v"
                .. old_version .. " -> v" .. new_version .. ")")
        end
    else
        print_hl("Error",
            "Update failed with status " .. vim.v.shell_error)
        for _, line in ipairs(result) do
            vim.print(line)
        end
    end
end
