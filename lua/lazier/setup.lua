local constants = require "lazier.constants"
local state = require "lazier.state"
local fs = require "lazier.util.fs"

local function has_lazier_rtp()
    for _, item in ipairs(vim.split(vim.o.rtp, ',', {plain = true})) do
        if string.find(item, "/lazier.nvim", 1, true) then
            return true
        end
    end
    return false
end

local function find_rtps()
    local lazierRtp
    local lazyRtp
    for _, item in ipairs(vim.split(vim.o.rtp, ',', {plain = true})) do
        if string.find(item, "/lazy.nvim", 1, true) then
            lazyRtp = item
        elseif string.find(item, "/lazier.nvim", 1, true) then
            lazierRtp = item
        end
    end
    return { lazier = lazierRtp, lazy = lazyRtp }
end

local function check_cache(detect_config_changes)
    local recompile = false
    local last_modified = 0
    local last_tally = 0
    local cache
    local success, contents = pcall(fs.read_file, constants.cache_path)
    if not success or not fs.stat(constants.user_compiled_path) then
        recompile = true
    else
        success, cache = pcall(vim.json.decode, contents)
        if not success then
            recompile = true
        else
            last_modified = cache.modified
            last_tally = cache.tally
        end
        if cache.version ~= vim.v.version then
            recompile = true
        end
    end

    local tally
    if detect_config_changes then
        recompile, tally = require("lazier.change_detect")(recompile, last_modified, last_tally)
    end

    local timestamp = tonumber(vim.fn.strftime('%s'))
    cache = {
        modified = timestamp,
        colorscheme = cache
            and cache.colorscheme
            or vim.g.colors_name,
        color_rtp = cache and cache.color_rtp,
        bundle_plugins = cache and cache.bundle_plugins,
        non_lazy_plugins = cache and cache.non_lazy_plugins,
        tally = tally,
        version = vim.v.version
    }
    return recompile, cache
end

local function setup_lazier(module, opts)
    opts = opts or {}

    if not vim.o.rtp:find("/lazy/lazy.nvim") then
        local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
        if not (vim.uv or vim.loop).fs_stat(lazypath) then
            require("lazier.clone_lazy")(lazypath)
        end
        vim.opt.rtp:prepend(lazypath)
    end

    local rtps = find_rtps()

    -- local reset_rtp = false
    -- if opts.performance then
    --     if opts.performance.reset_packpath then
    --         vim.go.packpath = vim.env.VIMRUNTIME
    --     end
    --     if opts.performance.rtp and opts.performance.rtp.reset then
    --         reset_rtp = true
    --     end
    -- end

    opts.lazier = opts.lazier or {}
    if opts.lazier.enabled == false then
        if opts.lazier.before then
            opts.lazier.before()
        end
        require("lazy").setup(module, opts)
        if opts.lazier.after then
            opts.lazier.after()
        end
        return
    end
    opts.lazier.bundle_plugins = opts.lazier.bundle_plugins or false
    if opts.lazier.detect_changes == nil then
        opts.lazier.detect_changes = true
    end

    if not fs.stat(constants.data_dir) then
        fs.create_directory(constants.data_dir)
    end

    local modified, cache = check_cache(opts.lazier.detect_changes)

    if modified
        or cache.bundle_plugins ~= opts.lazier.bundle_plugins
    then
        local compile_user = require("lazier.compile_user")
        compile_user(module, opts, cache, rtps, has_lazier_rtp)
        return
    end

    state.compiled = true

    if package.loaded["vim.loader"] then
        vim.loader.enable(false)
        loadfile(constants.user_compiled_path, "b")()
        vim.loader.enable()
    else
        loadfile(constants.user_compiled_path, "b")()
    end

    if opts.lazier.before then
        opts.lazier.before()
    end

    -- if reset_rtp then
    --     local lib = vim.fn.fnamemodify(vim.v.progpath, ":p:h:h") .. "/lib"
    --     lib = vim.uv.fs_stat(lib .. "64") and (lib .. "64") or lib
    --     lib = lib .. "/nvim"
    --     vim.opt.rtp = {
    --         vim.fn.stdpath("config"),
    --         vim.fn.stdpath("data") .. "/site",
    --         rtps.lazierRtp,
    --         rtps.lazyRtp,
    --         vim.env.VIMRUNTIME,
    --         lib,
    --         vim.fn.stdpath("config") .. "/after",
    --     }
    -- end

    local start_lazily
    if type(opts.lazier.start_lazily) == "function" then
        start_lazily = opts.lazier.start_lazily()
    elseif opts.lazier.start_lazily == nil then
        start_lazily = require("lazier.defaults").start_lazily()
    else
        start_lazily = opts.lazier.start_lazily
    end

    if start_lazily then
        local loadplugins = vim.o.loadplugins
        vim.o.loadplugins = false
        if cache.color_rtp then
            vim.opt.rtp:append(cache.color_rtp)
            vim.cmd.colorscheme(cache.colorscheme)
        end
        if cache.non_lazy_plugins then
            for _, plugin in ipairs(cache.non_lazy_plugins) do
                vim.opt.rtp:append(plugin.rtp)
            end
            for _, plugin in ipairs(cache.non_lazy_plugins) do
                if not plugin.dep then
                    local schema = require(plugin.path)
                    if plugin.idx then
                        schema = schema[plugin.idx]
                    end
                    if schema.config == true or (schema.opts and not schema.config) then
                        if plugin.main then
                            local m = require(plugin.main)
                            if m.setup then
                                m.setup(schema.opts)
                            end
                        end
                    elseif schema.config then
                        schema.config(nil, schema.opts)
                    end
                end
            end
        end
        vim.schedule(function()
            require("lazier.after_lazy_start")(
                opts, loadplugins, cache, rtps, has_lazier_rtp)
        end)
    else
        vim.loader.enable()
        local lazy = require("lazy")
        local plugin_spec = require("lazier_plugin_spec")
        lazy.setup(plugin_spec, opts)
            if not has_lazier_rtp() then
                vim.opt.rtp:append(rtps.lazier)
            end
        require("lazier.commands")
        if opts.lazier.after then
            opts.lazier.after()
        end
    end
end

return setup_lazier
