local state = require("lazier")
local Recorder = require("lazier.recorder")
local Mimic = require("lazier.mimic")
local np = require("lazier.npack")

--- @class LazierModule
local LazierModule = {}

LazierModule.__index = LazierModule

function LazierModule:runConfig(opts)
    self.keymaps = { obj = vim.keymap, name = "set" };
    self.allWrappers = {
        self.keymaps,
        { obj = vim.api, name = "nvim_set_hl" },
        { obj = vim.api, name = "nvim_create_augroup" },
        { obj = vim.api, name = "nvim_create_autocmd" },
    }

    self.moduleRecorders = {}
    self.recorders = {}

    self.oldCmd = vim.cmd
    self.cmdRecorder = Recorder.new(self.recorders)
    vim.cmd = self.cmdRecorder

    local oldRequire = _G.require
    --- @diagnostic disable-next-line
    _G.require = function(name)
        local r = self.moduleRecorders[name]
        if not r then
            r = Recorder.new(self.recorders)
            self.moduleRecorders[name] = r
        end
        return r
    end

    for _, wrapper in ipairs(self.allWrappers) do
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
    vim.cmd = self.oldCmd
    for _, wrapper in ipairs(self.allWrappers) do
        wrapper.obj[wrapper.name] = wrapper.original
    end
    if not success then
        error(result)
    end
    self.newConfig = result

    if #self.keymaps.calls > 0 then
        opts.keys = opts.keys or {}
        if type(opts.keys) ~= "table" then
            error("expected table for 'keys'")
        end
        for _, keymap in ipairs(self.keymaps.calls) do
            --- @diagnostic disable-next-line
            table.insert(opts.keys,
                { keymap[2], mode = keymap[1] })
        end
    end
end

function LazierModule:applyConfig(opts)
    for k, recorder in pairs(self.moduleRecorders) do
        Recorder.setValue(recorder, require(k))
    end
    Recorder.setValue(self.cmdRecorder, vim.cmd)

    for _, recorder in ipairs(self.recorders) do
        Recorder.eval(recorder)
    end

    for i = #self.recorders, 1, -1 do
        Recorder.delete(self.recorders[i])
        self.recorders[i] = nil
    end

    for _, wrapper in ipairs(self.allWrappers) do
        for _, call in ipairs(wrapper.calls) do
            for i, v in ipairs(call) do
                call[i] = Recorder.eval(v)
            end
            wrapper.obj[wrapper.name](np.unpack(call))
        end
    end

    for k, v in pairs(self.moduleRecorders) do
        self.moduleRecorders[k] = nil
        Mimic.new(v, require(k))
    end
    -- moduleRecorders = nil
    Mimic.new(self.cmdRecorder, vim.cmd)
    -- cmdRecorder = nil

    if self.newConfig then
        self.newConfig()
    end
end

function LazierModule:wrapConfig(opts)
    self:runConfig(opts)
    opts.config = function()
        self:applyConfig(opts)
        opts.config = nil
    end
    return opts
end
---
--- @param opts LazyPluginSpec
--- @return LazyPluginSpec
return function(opts)
    opts = opts or {}
    if state.compiled then
        return opts
    end
    if opts.enabled == false
        or opts.lazy == false
        or type(opts.config) ~= "function"
    then
        return opts
    end

    --- @type LazierModule
    local module = setmetatable({}, LazierModule)
    return module:wrapConfig(opts)
end
