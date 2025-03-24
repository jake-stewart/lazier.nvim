local Recorder = require("lazier.recorder")
local Mimic = require("lazier.mimic")

local function printHl(hl, message)
    vim.api.nvim_echo({{ message, hl } }, true, {})
end

vim.api.nvim_create_user_command("LazierUpdate", function()
    local separator = vim.fn.has('macunix') == 1 and "/" or "\\"
    local repoDir = table.concat({ vim.fn.stdpath("data"), "lazier.nvim" }, separator)
    --- @diagnostic disable-next-line
    local _, err = (vim.uv or vim.loop).fs_lstat(repoDir)
    if err then
        error("Failed to find lazier repo at '" .. repoDir .. "': " .. tostring(error))
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

--- @param opts LazyPluginSpec
--- @return LazyPluginSpec
local function plug(opts)
    opts = opts or {}
    if opts.enabled == false
        or opts.lazy == false
        or type(opts.config) ~= "function"
    then
        return opts
    end
    local keymaps = { obj = vim.keymap, name = "set" };
    local allWrappers = {
        keymaps,
        { obj = vim.api, name = "nvim_set_hl" },
        { obj = vim.api, name = "nvim_create_augroup" },
        { obj = vim.api, name = "nvim_create_autocmd" },
    }

    local moduleRecorders = {}
    local oldCmd = vim.cmd
    local cmdRecorder = Recorder.new()

    local oldRequire = _G.require
    --- @diagnostic disable-next-line
    _G.require = function(name)
        local r = moduleRecorders[name]
        if not r then
            r = Recorder.new()
            moduleRecorders[name] = r
        end
        return r
    end

    for _, wrapper in ipairs(allWrappers) do
        wrapper.original = wrapper.obj[wrapper.name]
        wrapper.calls = {}
        wrapper.obj[wrapper.name] = function(...)
            table.insert(wrapper.calls, {...})
        end
    end
    local success, newConfigOrError
    --- @diagnostic disable-next-line
    success, newConfigOrError = pcall(opts.config)
    _G.require = oldRequire
    vim.cmd = oldCmd
    for _, wrapper in ipairs(allWrappers) do
        wrapper.obj[wrapper.name] = wrapper.original
    end
    if not success then
        error(newConfigOrError)
    end

    if #keymaps.calls > 0 then
        opts.keys = opts.keys or {}
        if type(opts.keys) ~= "table" then
            error("expected table for 'keys'")
        end
        for _, keymap in ipairs(keymaps.calls) do
            --- @diagnostic disable-next-line
            table.insert(opts.keys,
                { keymap[2], mode = keymap[1] })
        end
    end

    opts.config = function()
        for k, v in pairs(moduleRecorders) do
            local module = require(k)
            for _, item in ipairs(v._list) do
                Recorder.eval(item, module)
            end
        end
        for _, item in ipairs(cmdRecorder._list) do
            Recorder.eval(item, nil)
        end

        for _, wrapper in ipairs(allWrappers) do
            for _, call in ipairs(wrapper.calls) do
                for i, v in ipairs(call) do
                    call[i] = Recorder.eval(v, nil)
                end
                wrapper.obj[wrapper.name](table.unpack(call))
            end
        end

        for k, v in pairs(moduleRecorders) do
            setmetatable(v, nil)
            for key in pairs(v) do
                v[key] = nil
            end
            Mimic.new(v, require(k))
        end
        if newConfigOrError then
            newConfigOrError()
        end
    end

    return opts
end

return plug
