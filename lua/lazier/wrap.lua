local state = require("lazier")
local Recorder = require("lazier.recorder")
local Mimic = require("lazier.mimic")
local np = require("lazier.npack")

--- @param opts LazyPluginSpec
--- @return LazyPluginSpec
return function(opts)
    opts = opts or {}
    if state.compiled
        or opts.enabled == false
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
    local recorders = {}

    local oldCmd = vim.cmd
    local cmdRecorder = Recorder.new(recorders)
    vim.cmd = cmdRecorder

    local oldRequire = _G.require
    --- @diagnostic disable-next-line
    _G.require = function(name)
        local r = moduleRecorders[name]
        if not r then
            r = Recorder.new(recorders)
            moduleRecorders[name] = r
        end
        return r
    end

    for _, wrapper in ipairs(allWrappers) do
        wrapper.original = wrapper.obj[wrapper.name]
        wrapper.calls = {}
        wrapper.obj[wrapper.name] = function(...)
            table.insert(wrapper.calls, np.pack(...))
        end
    end
    local success, result
    --- @diagnostic disable-next-line
    success, result = pcall(opts.config)
    _G.require = oldRequire
    vim.cmd = oldCmd
    for _, wrapper in ipairs(allWrappers) do
        wrapper.obj[wrapper.name] = wrapper.original
    end
    if not success then
        error(result)
    end
    local newConfig = result

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
        for k, recorder in pairs(moduleRecorders) do
            Recorder.setValue(recorder, require(k))
        end
        Recorder.setValue(cmdRecorder, vim.cmd)

        for _, recorder in ipairs(recorders) do
            Mimic.new(recorder, Recorder.eval(recorder))
        end

        for _, wrapper in ipairs(allWrappers) do
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

        for k, v in pairs(moduleRecorders) do
            Mimic.new(v, require(k))
        end
        Mimic.new(cmdRecorder, vim.cmd)

        if newConfig then
            newConfig()
        end

        opts.config = nil
    end

    return opts
end
