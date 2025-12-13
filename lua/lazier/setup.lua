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

local function modified_since(stat, timestamp)
    return stat.mtime.sec > timestamp
        or stat.ctime.sec > timestamp
end

local function check_modified_tree(root, timestamp)
    local modified = false
    local tally = 0
    for name, type in fs.scan_directory(root, true) do
        tally = tally + 1
        local path = fs.join(root, name)

        if type == "file" and name:find("%.lua$") then
            if modified_since(fs.stat(path), timestamp) then
                modified = true
            end
        elseif type == "directory" and not name:find("^%.") then
            local child_modified, child_tally =
                check_modified_tree(path, timestamp)
            modified = modified or child_modified
            tally = tally + child_tally
        end
    end
    return modified, tally
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

    local modified, tally
    if detect_config_changes then
        local config_dir = vim.fn.stdpath("config")
        local source_path = fs.join(config_dir, "lua")

        modified, tally = check_modified_tree(source_path, last_modified)
        local extra_files = {
            fs.join(config_dir, "lazy-lock.json")
        }
        for _, file in ipairs(extra_files) do
            local stat = fs.stat(file)
            if stat then
                tally = tally + 1
                if modified_since(stat, last_modified) then
                    modified = true
                end
            end
        end
        recompile = recompile or modified or tally ~= last_tally
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
          local lazyrepo = "https://github.com/folke/lazy.nvim.git"
          local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
          if vim.v.shell_error ~= 0 then
            vim.api.nvim_echo({
              { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
              { out, "WarningMsg" },
              { "\nPress any key to exit..." },
            }, true, {})
            vim.fn.getchar()
            os.exit(1)
          end
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

    local function start_lazily()
        if type(opts.lazier.start_lazily) == "function" then
            return opts.lazier.start_lazily()
        elseif opts.lazier.start_lazily == nil then
            local fname = vim.fn.expand("%")
            if fname == "" then
                return true
            end
            local non_lazy_loadable_extensions = {
                zip = true,
                tar = true,
                gz = true
            }
            local stat = fs.stat(fname)
            return not stat
                or stat.type == "file"
                and not non_lazy_loadable_extensions
                    [vim.fn.fnamemodify(fname, ":e")]
        else
            return opts.lazier.start_lazily
        end
    end

    if not fs.stat(constants.data_dir) then
        fs.create_directory(constants.data_dir)
    end

    local modified, cache = check_cache(opts.lazier.detect_changes)

    if modified
        or cache.bundle_plugins ~= opts.lazier.bundle_plugins
    then
        local required_mods = {}
        local _require = require
        --- @diagnostic disable-next-line
        function _G.require(mod)
            required_mods[mod] = true
            return _require(mod)
        end

        if opts.lazier.before then
            opts.lazier.before()
        end

        _G.require = _require

        local compile_user = require("lazier.compile_user")
        local result = compile_user(
            module,
            opts,
            opts.lazier.bundle_plugins,
            opts.lazier.generate_lazy_mappings,
            opts.lazier.compile_api,
            required_mods
        )
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
        return
    end

    state.compiled = true

    vim.loader.enable(false)
    loadfile(constants.user_compiled_path, "b")()
    vim.loader.enable()
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

    if start_lazily() then
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
            vim.o.loadplugins = loadplugins
            local loader = require("lazy.core.loader")
            local load = loader._load
            if cache.non_lazy_plugins then
                function loader._load(plugin, reason, opts2)
                    for _, candidate in ipairs(cache.non_lazy_plugins) do
                        if plugin.dir
                            and fs.abspath(candidate.rtp)
                                == fs.abspath(plugin.dir)
                        then
                            plugin.config = function() end
                            break
                        end
                    end
                    load(plugin, reason, opts2)
                end
            end
            local lazy = require("lazy")
            local plugin_spec = require("lazier_plugin_spec")
            lazy.setup(plugin_spec, opts)
            loader._load = load
            if not has_lazier_rtp() then
                vim.opt.rtp:append(rtps.lazier)
            end
            require("lazier.commands")
            if opts.lazier.after then
                opts.lazier.after()
            end
            if vim.fn.expand("%") ~= "" then
                vim.schedule(function()
                    pcall(vim.cmd.edit)
                end)
            elseif vim.o.ft ~= "" then
                vim.schedule(function()
                    vim.cmd.setf(vim.o.ft)
                end)
            end
        end)
    else
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
