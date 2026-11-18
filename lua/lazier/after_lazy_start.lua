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
    vim.schedule(function()
        local visible = {}
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            visible[vim.api.nvim_win_get_buf(win)] = true
        end
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(buf)
                and vim.bo[buf].buftype == ""
                and vim.api.nvim_buf_get_name(buf) ~= ""
            then
                local function reedit()
                    if vim.api.nvim_buf_is_loaded(buf) then
                        vim.api.nvim_buf_call(buf, function()
                            pcall(vim.cmd.edit)
                        end)
                    end
                end
                if visible[buf] then
                    reedit()
                else
                    vim.api.nvim_create_autocmd("BufEnter", {
                        buffer = buf,
                        once = true,
                        callback = function()
                            vim.schedule(reedit)
                        end,
                    })
                end
            end
        end
    end)
    if vim.fn.expand("%") == "" and vim.o.ft ~= "" then
        vim.schedule(function()
            vim.cmd.setf(vim.o.ft)
        end)
    end
end

return after_lazy_start
