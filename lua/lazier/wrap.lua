local Recorder = require "lazier.util.recorder"
local Mimic = require "lazier.util.mimic"
local np = require "lazier.util.npack"

--- @param opts LazyPluginSpec
--- @return LazyPluginSpec
return function(opts)
    opts = opts or {}
    if opts.enabled == false
        or opts.lazy == false
        or type(opts.config) ~= "function"
    then
        return opts
    end

    local keymaps = { obj = vim.keymap, name = "set" };
    local all_wrappers = {
        keymaps,
        { obj = vim.api, name = "nvim_set_hl" },
        { obj = vim.api, name = "nvim_create_augroup" },
        { obj = vim.api, name = "nvim_create_autocmd" },
    }

    local module_recorders = {}
    local recorders = {}

    local old_cmd = vim.cmd
    local cmd_recorder = Recorder.new(recorders)
    vim.cmd = cmd_recorder

    local old_require = _G.require
    --- @diagnostic disable-next-line
    _G.require = function(name)
        local r = module_recorders[name]
        if not r then
            r = Recorder.new(recorders)
            module_recorders[name] = r
        end
        return r
    end

    for _, wrapper in ipairs(all_wrappers) do
        wrapper.original = wrapper.obj[wrapper.name]
        wrapper.calls = {}
        wrapper.obj[wrapper.name] = function(...)
            table.insert(wrapper.calls, np.pack(...))
        end
    end
    local success, result
    --- @diagnostic disable-next-line
    success, result = pcall(opts.config)
    _G.require = old_require
    vim.cmd = old_cmd
    for _, wrapper in ipairs(all_wrappers) do
        wrapper.obj[wrapper.name] = wrapper.original
    end
    if not success then
        error(result)
    end
    local new_config = result

    if #keymaps.calls > 0 then
        opts.keys = opts.keys or {}
        if type(opts.keys) ~= "table" then
            error("expected table for 'keys'")
        end
        for _, keymap in ipairs(keymaps.calls) do
            local desc = type(keymap[4]) == "table"
                and keymap[4].desc
                or nil
            table.insert(opts.keys, {
                keymap[2],
                mode = keymap[1],
                desc = desc
            })
        end
    end

    opts.config = function()
        for k, recorder in pairs(module_recorders) do
            Recorder.set_value(recorder, require(k))
        end
        Recorder.set_value(cmd_recorder, vim.cmd)

        for _, recorder in ipairs(recorders) do
            Mimic.new(recorder, Recorder.eval(recorder))
        end

        for _, wrapper in ipairs(all_wrappers) do
            for _, call in ipairs(wrapper.calls) do
                for i, v in ipairs(call) do
                    call[i] = Recorder.eval(v)
                end
                wrapper.obj[wrapper.name](np.unpack(call))
            end
        end

        for i = #recorders, 1, -1 do
            recorders[i] = nil
        end

        for k, v in pairs(module_recorders) do
            Mimic.new(v, require(k))
        end
        Mimic.new(cmd_recorder, vim.cmd)

        if new_config then
            new_config()
        end

        opts.config = nil
    end

    return opts
end
