local function printHl(hl, message)
    vim.api.nvim_echo({{ message, hl } }, true, {})
end

vim.api.nvim_create_user_command("LazierUpdate", function()
    local separator = vim.fn.has('macunix') == 1 and "/" or "\\"
    local repoDirLocations = {
        table.concat({ vim.fn.stdpath("data"), "lazier", "lazier.nvim" }, separator),
        table.concat({ vim.fn.stdpath("data"), "lazier.nvim" }, separator),
    }
    local repoDir
    for _, candidate in ipairs(repoDirLocations) do
        local stat = (vim.uv or vim.loop).fs_lstat(candidate)
        if stat then
            repoDir = candidate
            break
        end
    end
    if not repoDir then
        error("Failed to find lazier repo")
    end
    printHl("Title", "Updating Lazier...")
    vim.print()
    local oldVersion = require("lazier.version")
    local result = vim.fn.systemlist({ "git", "-C", repoDir, "pull" })
    if type(result) == "string" then
        result = { result }
    end
    if vim.v.shell_error == 0 then
        package.loaded["lazier.version"] = nil
        local newVersion = require("lazier.version")
        if newVersion == oldVersion then
            vim.print("Already up to date. (" .. newVersion .. ")")
        else
            vim.print("Update completed successfully. (v" .. oldVersion .. " -> v" .. newVersion .. ")")
        end
    else
        printHl("Error",
            "Update failed with status " .. vim.v.shell_error)
        for _, line in ipairs(result) do
            vim.print(line)
        end
    end
end, {})


local Lazier = {
    compiled = false
}

--- @param opts LazyPluginSpec
--- @return LazyPluginSpec
function Lazier.__call(_, opts)
    --return opts
    return require("lazier.wrap")(opts)
end

function Lazier.setup(module, opts)
    return require("lazier.setup")(module, opts)
end

return setmetatable(Lazier, Lazier)
