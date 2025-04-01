local uv = vim.uv or vim.loop

local separator = vim.fn.has('macunix') == 1 and "/" or "\\"

local function removeFilesInDirectory(directory)
    local scanner, err = uv.fs_scandir(directory)
    if err then
        return
    end
    while true do
        local name, type = uv.fs_scandir_next(scanner)
        if not name then
            break
        end
        local path = directory .. separator .. name
        if type == 'file' then
            uv.fs_unlink(path)
        end
    end
end

local function printHl(hl, message)
    vim.api.nvim_echo({{ message, hl } }, true, {})
end

return function()
    local repoDirLocations = {
        table.concat({ vim.fn.stdpath("data"), "lazier", "lazier.nvim" }, separator),
        table.concat({ vim.fn.stdpath("data"), "lazier.nvim" }, separator),
    }
    local repoDir
    for _, candidate in ipairs(repoDirLocations) do
        local stat = uv.fs_lstat(candidate)
        if stat then
            repoDir = candidate
            break
        end
    end
    if not repoDir then
        error("Failed to find lazier repo")
    end

    local cacheDir = table.concat({ vim.fn.stdpath("data"), "lazier" }, separator)
    removeFilesInDirectory(cacheDir)

    printHl("Title", "Updating Lazier...")
    vim.print()
    local oldVersion = require("lazier.version")
    local result = vim.fn.systemlist({ "git", "-C", repoDir, "pull" })
    if type(result) == "string" then
        result = { result }
    end
    if vim.v.shell_error == 0 then
        package.loaded["lazier.version"] = nil
        package.preload["lazier.version"] = nil
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
end
