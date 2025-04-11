local fs = require "lazier.util.fs"
local bundler = require "lazier.util.bundler"
local serializer = require "lazier.util.serializer"
local compiler = require "lazier.util.compiler"
local constants = require "lazier.constants"

table.unpack = table.unpack or unpack

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

local function compile_user(module, opts, bundle_plugins)
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

    local spec_plugins = {}
    local colors_name = vim.g.colors_name
    local color_rtp
    local lazy_plugins = lazy.plugins()
    for plugin_path, plugin in pairs(plugin_modules) do
        package.loaded[plugin_path] = plugin
        local lazy_plugin
        for _, candidate in ipairs(lazy_plugins) do
            if candidate[1] and candidate[1] == plugin[1]
                or candidate.url and candidate.url == plugin.url
                or candidate.dir and plugin.dir
                    and vim.fs.abspath(candidate.dir)
                        == vim.fs.abspath(plugin.dir)
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
            local spec = vim.deepcopy(plugin)
            local parent = serializer.function_call("require", plugin_path)
            fragment_functions(parent[1], spec, {}, 1)
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

    local bundled = bundler.bundle({
        modules = {
            "vim.func",
            "vim.func._memoize",
            "vim.loader",
            "vim.uri",
            "vim.F",
            "vim.fs",
            "vim.hl",
            "vim.treesitter.highlighter",
            "vim.treesitter.query",
            "vim.treesitter.languagetree",
            "vim.treesitter.language",
            "vim.treesitter._range",
            "vim.treesitter",
            "vim.filetype",
            "vim.diagnostic",
        },
        paths = paths,
        custom_modules = {
            lazier_plugin_spec = compiled_plugin_spec
        }
    })

    compiler.try_compile(
        bundled,
        constants.user_bundle_path,
        constants.user_compiled_path
    )

    return {
        color_rtp = color_rtp
    }
end

return compile_user
