local fs = require "lazier.util.fs"
local bundler = require "lazier.util.bundler"
local serializer = require "lazier.util.serializer"
local compiler = require "lazier.util.compiler"
local constants = require "lazier.constants"
local wrap = require "lazier.wrap"

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

local function fragment_functions(parent, obj, path, i)
    for k, v in pairs(obj) do
        path[i] = k
        if type(v) == "function" then
            local code = "function(...) return " .. parent
            for j = 1, i do
                if serializer.valid_identifier(path[j]) then
                    code = code .. "." .. path[j]
                else
                    code = code .. "[" .. serializer.serialize(path[j]) .. "]"
                end
            end
            code = code .. "(...) end"
            obj[k] = serializer.fragment(code)
        elseif type(v) == "table" then
            fragment_functions(parent, v, path, i + 1)
        end
        path[i] = nil
    end
end

local function compile_user(module, opts, bundle_plugins, generate_lazy_mappings, compile_api, required_mods)
    if compile_api == nil then
        compile_api = true
    end
    if generate_lazy_mappings ~= false then
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

    local lazy = require("lazy")
    lazy.setup(module, opts)
    _G.loadfile = loadfile

    local loader = require("lazy.core.loader")

    local spec_plugins = {}
    local colors_name = vim.g.colors_name
    local color_rtp
    local non_lazy_plugins = {}
    local lazy_plugins = lazy.plugins()
    for plugins_path, plugins in pairs(plugin_modules) do
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
            if plugin.import then
                plugin = require(plugin.import)
            end
            local lazy_plugin
            for _, candidate in ipairs(lazy_plugins) do
                if has_index(candidate, plugin)
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
                        path = plugins_path,
                        idx = listSchema and plugin_idx or nil,
                        main = loader.get_main(lazy_plugin),
                    })
                end
                local spec = vim.deepcopy(plugin)
                spec.keys = lazy_plugin.keys
                spec.event = lazy_plugin.event
                spec.cmd = lazy_plugin.cmd
                local parent = serializer.function_call("require", plugins_path);
                if listSchema then
                    parent = serializer.index(parent, plugin_idx)
                end
                fragment_functions(serializer.serialize(parent), spec, {}, 1)
                for _, v in pairs(spec) do
                    if type(v) == "table"
                        and getmetatable(v) ~= serializer.Fragment
                    then
                        setmetatable(v, nil)
                    end
                end
                if serializer.can_serialize(spec) then
                    table.insert(spec_plugins, spec)
                else
                    table.insert(spec_plugins, parent)
                end
            end
        end
    end

    local compiled_plugin_spec =
        "return " .. serializer.serialize(spec_plugins, 0, 80 - 7)

    local paths = {
        vim.fn.stdpath("config") .. "/lua"
    }
    if bundle_plugins then
        local prefix = fs.join(vim.fn.stdpath("data"), "lazy")
        for _, plugin in ipairs(require("lazy").plugins()) do
            if plugin.dir and vim.startswith(plugin.dir, prefix) then
                table.insert(paths, fs.join(plugin.dir, "lua"))
            end
        end
    end

    local api_mods = compile_api and (type(compile_api) == "boolean" and {
        "vim.filetype",
        "vim.filetype.detect",
    } or compile_api) or {}

    for _, mod in ipairs(api_mods) do
        required_mods[mod] = true
    end

    local bundled = bundler.bundle({
        modules = api_mods,
        paths = paths,
        -- filter = required_mods,
        custom_modules = {
            lazier_plugin_spec = compiled_plugin_spec
        }
    })

    compiler.try_compile(
        bundled,
        constants.user_bundle_path,
        constants.user_compiled_path
    )

    table.sort(non_lazy_plugins, function(a, b)
        return (a.priority or 50) > (b.priority or 50)
    end)

    return {
        non_lazy_plugins = #non_lazy_plugins > 0
            and non_lazy_plugins or nil,
        color_rtp = color_rtp
    }
end

return compile_user
