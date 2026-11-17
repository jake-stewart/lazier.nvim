local fs = require "lazier.util.fs"
local bundler = require "lazier.util.bundler"
local serializer = require "lazier.util.serializer"
local compiler = require "lazier.util.compiler"
local constants = require "lazier.constants"
local wrap = require "lazier.wrap"
local state = require "lazier.state"

table.unpack = table.unpack or unpack

local function has_index(obj, index)
    while obj do
        if obj == index then
            return true
        end
        obj = getmetatable(obj)
        obj = obj and obj.__index
    end
    return false
end

local dict_metatable = getmetatable(vim.empty_dict())

local function count_tables(obj, counts)
    counts[obj] = (counts[obj] or 0) + 1
    if counts[obj] == 1 then
        for _, v in pairs(obj) do
            if type(v) == "table" then
                count_tables(v, counts)
            end
        end
    end
end

local function fragment_spec(parent, obj, path, counts)
    local spec = {}
    for k, v in pairs(obj) do
        if type(k) == "table" or not serializer.can_serialize(k) then
            return nil
        end
        table.insert(path, k)
        local ref = serializer.index(parent, table.unpack(path))[1]
        if type(v) == "function" then
            spec[k] = serializer.fragment("function(...) return " .. ref .. "(...) end")
        elseif type(v) == "table" and getmetatable(v) == serializer.Fragment then
            spec[k] = v
        elseif type(v) == "table" then
            local metatable = getmetatable(v)
            if counts[v] == 1
                and (#path == 1 or not metatable or metatable == dict_metatable)
            then
                spec[k] = fragment_spec(parent, v, path, counts)
            end
            spec[k] = spec[k] or serializer.fragment(ref)
        elseif serializer.can_serialize(v) then
            spec[k] = v
        else
            spec[k] = serializer.fragment(ref)
        end
        table.remove(path)
    end
    return setmetatable(spec, getmetatable(obj) == dict_metatable and dict_metatable or nil)
end

local function compile_user(module, opts, cache, rtps, has_lazier_rtp)
    vim.loader.enable()
    local required_mods = {}
    local _require = require
    --- @diagnostic disable-next-line
    function _G.require(mod)
        if not vim.startswith("mod", "vim.") then
            required_mods[mod] = true
        end
        return _require(mod)
    end

    if opts.lazier.before then
        opts.lazier.before()
    end

    _G.require = _require

    if opts.lazier.generate_lazy_mappings ~= false then
        local Spec = require("lazy.core.plugin").Spec
        local parse = Spec.parse
        function Spec:parse(spec)
            parse(self, spec)
            for _, plugin in pairs(self.plugins) do
                wrap(plugin)
            end
        end
    end

    local lazy_util = require("lazy.core.util")
    local plugin_modules = {}
    local plugin_paths = {}
    lazy_util.lsmod(module, function(plugin_path, modpath)
        local mod = require(plugin_path)
        plugin_paths[modpath] = mod
        plugin_modules[plugin_path] = mod
    end)
    local loadfile = _G.loadfile
    function _G.loadfile(path)
        if plugin_paths[path] then
            return function()
                return plugin_paths[path]
            end
        else
            return loadfile(path)
        end
    end

    -- lets wrap tell a config's own calls from those of plugins it pulls in while running
    local lazy_loader = require("lazy.core.loader")
    local load_plugin = lazy_loader._load
    function lazy_loader._load(plugin, ...)
        local commands = vim.api.nvim_get_commands({ builtin = false })
        table.insert(state.loading, plugin.name)
        local success, result = pcall(load_plugin, plugin, ...)
        table.remove(state.loading)
        for k in pairs(vim.api.nvim_get_commands({ builtin = false })) do
            if not commands[k] then
                state.claimed_commands[k] = true
            end
        end
        if not success then
            error(result, 0)
        end
    end

    local lazy = require("lazy")
    lazy.setup(module, opts)
    _G.loadfile = loadfile
    lazy_loader._load = load_plugin

    local loader = require("lazy.core.loader")

    local spec_plugins = {}
    local colors_name = vim.g.colors_name
    local color_rtp
    local non_lazy_plugins = {}
    local lazy_plugins = lazy.plugins()
    local plugins_paths = vim.tbl_keys(plugin_modules)
    table.sort(plugins_paths)
    for _, plugins_path in ipairs(plugins_paths) do
        local plugins = plugin_modules[plugins_path]
        local listSchema = true;
        if
            type(plugins[1]) == "string"
            or type(plugins.url) == "string"
            or type(plugins.dir) == "string"
            or type(plugins.import) == "string"
        then
            listSchema = false
            plugins = { plugins }
        end
        package.loaded[plugins_path] = plugins
        for plugin_idx, plugin in ipairs(plugins) do
            if type(plugin) == "string" then
                plugin = { plugin }
            end
            local import = plugin.import
            if import then
                plugin = require(import)
            end
            local lazy_plugin
            for _, candidate in ipairs(lazy_plugins) do
                if has_index(candidate, plugin)
                    or plugin[1] ~= nil and candidate[1] == plugin[1]
                    or candidate.dir and plugin.dir
                    and fs.abspath(candidate.dir)
                        == fs.abspath(plugin.dir)
                then
                    lazy_plugin = candidate
                    break
                end
            end

            if lazy_plugin ~= nil then
                if colors_name and not color_rtp then
                    local extensions = { "vim", "lua" }
                    for _, extension in ipairs(extensions) do
                        local path = fs.join(
                            lazy_plugin.dir, "colors", colors_name .. "." .. extension)
                        if fs.stat(path) then
                            color_rtp = lazy_plugin.dir
                            break
                        end
                    end
                end

                local function push_non_lazy_plugin(non_lazy_plugin)
                    for i, existing in ipairs(non_lazy_plugins) do
                        if existing.name == non_lazy_plugin.name then
                            non_lazy_plugins[i] = non_lazy_plugin
                            non_lazy_plugin.dep = existing.dep and non_lazy_plugin.dep
                            return
                        end
                    end
                    table.insert(non_lazy_plugins, non_lazy_plugin)
                end

                if lazy_plugin.lazy == false and color_rtp ~= lazy_plugin.dir then
                    for _, dep in ipairs(lazy_plugin.dependencies or {}) do
                        for _, dep_lazy_plugin in ipairs(lazy_plugins) do
                            if dep_lazy_plugin.name == dep then
                                push_non_lazy_plugin({
                                    name = dep_lazy_plugin.name,
                                    rtp = dep_lazy_plugin.dir,
                                    dep = true,
                                })
                            end
                        end
                    end
                    push_non_lazy_plugin({
                        name = lazy_plugin.name,
                        rtp = lazy_plugin.dir,
                        priority = lazy_plugin.priority,
                        path = import or plugins_path,
                        idx = listSchema and not import and plugin_idx or nil,
                        main = loader.get_main(lazy_plugin),
                    })
                end
                local spec = {}
                for k, v in pairs(plugin) do
                    spec[k] = v
                end
                spec.keys = lazy_plugin.keys
                spec.event = lazy_plugin.event
                spec.ft = lazy_plugin.ft
                spec.cmd = lazy_plugin.cmd
                local parent = serializer.function_call("require", import or plugins_path)
                if listSchema and not import then
                    parent = serializer.index(parent, plugin_idx)
                end
                parent = serializer.serialize(parent)
                if type(spec.opts) == "table" and not serializer.can_serialize(spec.opts) then
                    spec.opts = serializer.fragment("function(_, opts) return "
                        .. serializer.function_call(
                            serializer.function_call("require", "lazier.merge_opts")[1],
                            serializer.fragment("opts"),
                            serializer.index(parent, "opts"),
                            plugin.opts_extend
                        )[1]
                        .. " end")
                end
                local counts = {}
                count_tables(spec, counts)
                table.insert(spec_plugins,
                    fragment_spec(parent, spec, {}, counts) or serializer.fragment(parent))
            end
        end
    end

    local compiled_plugin_spec =
        "return " .. serializer.serialize(spec_plugins, 0, 80 - 7)

    local paths = {
        vim.fn.stdpath("config") .. "/lua"
    }
    if opts.lazier.bundle_plugins then
        local prefix = fs.join(vim.fn.stdpath("data"), "lazy")
        for _, plugin in ipairs(require("lazy").plugins()) do
            if plugin.dir and vim.startswith(plugin.dir, prefix) then
                table.insert(paths, fs.join(plugin.dir, "lua"))
            end
        end
    end

    -- if opts.lazier.compile_api == nil then
    --     opts.lazier.compile_api = true
    -- end
    -- local api_mods = opts.lazier.compile_api and (type(opts.lazier.compile_api) == "boolean" and {
    --     'vim.filetype',
    --     'vim.filetype.detect',
    --     'vim.treesitter.language',
    --     'vim.func',
    --     'vim.func._memoize',
    --     'vim.treesitter.query',
    --     'vim.treesitter._range',
    --     'vim.treesitter.languagetree',
    --     'vim.treesitter',
    --     'vim.F',
    --     'vim.treesitter.highlighter',
    -- } or opts.lazier.compile_api) or {}
    --
    -- for _, mod in ipairs(api_mods) do
    --     required_mods[mod] = true
    -- end

    local custom_modules = {
        lazier_plugin_spec = compiled_plugin_spec
    }

    for mod, _ in pairs(state.const_modules) do
        custom_modules[mod] = "return " .. serializer.serialize(package.loaded[mod])
    end
    for mod, src in pairs(state.compile_modules) do
        custom_modules[mod] = src
    end

    local bundled = bundler.bundle({
        -- modules = api_mods,
        paths = paths,
        filter = required_mods,
        custom_modules = custom_modules
    })

    compiler.try_compile(
        bundled,
        constants.user_bundle_path,
        constants.user_compiled_path
    )

    table.sort(non_lazy_plugins, function(a, b)
        return (a.priority or 50) > (b.priority or 50)
    end)

    local result = {
        non_lazy_plugins = #non_lazy_plugins > 0
            and non_lazy_plugins or nil,
        color_rtp = color_rtp
    }

    if not has_lazier_rtp() then
        vim.opt.rtp:append(rtps.lazier)
    end
    require("lazier.commands")
    if opts.lazier.after then
        opts.lazier.after()
    end
    cache.colorscheme = vim.g.colors_name
    cache.color_rtp = result.color_rtp
    cache.non_lazy_plugins = result.non_lazy_plugins
    cache.bundle_plugins = opts.lazier.bundle_plugins
    fs.write_file(constants.cache_path, vim.json.encode(cache))
end

return compile_user
