local fs = require "lazier.util.fs"
local bundler = require "lazier.util.bundler"
local serializer = require "lazier.util.serializer"
local compiler = require "lazier.util.compiler"
local constants = require "lazier.constants"
local lazy = require "lazy"

local function compile_user(module, bundle_plugins)
    local spec_plugins = {}

    local colors_name = vim.g.colors_name
    local color_rtp

    local lazy_plugins = lazy.plugins()

    local use_config_func = false
    local use_init_func = false
    local use_opts_func = false
    local use_keymap_func = false

    local lazy_util = require("lazy.core.util")
    lazy_util.lsmod(module, function(plugin_path)
        local plugin = require(plugin_path)
        local lazy_plugin
        for _, candidate in ipairs(lazy_plugins) do
            if candidate[1] and candidate[1] == plugin[1]
                or candidate.url and candidate.url == plugin.url
                or candidate.dir and candidate.dir == plugin.dir
            then
                lazy_plugin = candidate
                break
            end
        end
        if lazy_plugin == nil then
            return
        end
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
        local spec = {}
        spec[1] = plugin[1]
        spec.dir = plugin.dir
        spec.event = plugin.event
        spec.branch = plugin.branch
        spec.dependencies = plugin.dependencies
        spec.lazy = plugin.lazy
        spec.ft = plugin.ft
        spec.opts = plugin.opts
        if plugin.opts then
            if serializer.can_serialize(plugin.opts) then
                spec.opts = plugin.opts
            else
                use_opts_func = true
                spec.opts = serializer.function_call("__opts", plugin_path)
            end
        end
        if plugin.config then
            use_config_func = true
            spec.config = serializer.function_call("__config", plugin_path)
        end
        if plugin.init then
            use_init_func = true
            spec.init = serializer.function_call("__init", plugin_path)
        end
        if lazy_plugin.keys then
            spec.keys = {}
            for i, key in ipairs(lazy_plugin.keys) do
                if type(key) == "string" then
                    table.insert(spec.keys, key)
                else
                    local rhs = nil
                    if type(key[2]) == "string" then
                        rhs = key[2]
                    elseif type(key[2]) == "function" then
                        use_keymap_func = true
                        rhs = serializer.function_call("__keymap", plugin_path, i)
                    end
                    if key.mode and key.mode ~= "n"
                        or rhs
                        or key.desc
                        or key.noremap
                        or key.remap
                        or key.expr
                        or key.nowait
                    then
                        table.insert(spec.keys, {
                            key[1],
                            rhs,
                            mode = key.mode,
                            desc = key.desc,
                            noremap = key.noremap,
                            remap = key.remap,
                            expr = key.expr,
                        })
                    else
                        table.insert(spec.keys, key[1])
                    end
                end
            end
        end
        table.insert(spec_plugins, spec)
    end)

    local config_func = "local function __config(module)\n"
        .. "    return function(...)\n"
        .. "        require(module).config(...)\n"
        .. "    end\n"
        .. "end\n"

    local init_func = "local function __init(module)\n"
        .. "    return function(...)\n"
        .. "        require(module).init(...)\n"
        .. "    end\n"
        .. "end\n"

    local opts_func = "local function __opts(module)\n"
        .. "    return require(module).opts\n"
        .. "end\n"

    local keymap_func = "local function __keymap(module, idx)\n"
        .. "    return function(...)\n"
        .. "        require(module).keys[idx][2](...)\n"
        .. "    end\n"
        .. "end\n"

    local compiled_plugin_spec = (use_config_func and config_func or "")
        .. (use_init_func and init_func or "")
        .. (use_opts_func and opts_func or "")
        .. (use_keymap_func and keymap_func or "")
        .. "return " .. serializer.serialize(spec_plugins, 0, 80 - 7)

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
