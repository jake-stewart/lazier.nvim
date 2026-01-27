local function after_lazy_start(opts, loadplugins, cache, rtps, has_lazier_rtp)
    vim.loader.enable()
    local fs = require "lazier.util.fs"
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
end

return after_lazy_start
