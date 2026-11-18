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
    local events = { "BufReadPre", "BufReadPost", "FileType", "Syntax", "BufEnter", "BufWinEnter" } -- order :edit fires them in
    local function ungrouped_key(au)
        return au.event .. tostring(au.pattern) .. tostring(au.buffer) .. (au.command or "") .. tostring(au.callback)
    end
    local old_groups, old_ungrouped = {}, {}
    for _, ev in ipairs(events) do
        old_groups[ev] = {}
        for _, au in ipairs(vim.api.nvim_get_autocmds({ event = ev })) do
            if au.group_name then
                table.insert(old_groups[ev], au.group_name)
            else
                old_ungrouped[ungrouped_key(au)] = true
            end
        end
    end
    local old_rtp = {}
    for _, path in ipairs(vim.opt.rtp:get()) do
        old_rtp[path] = true
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
    local redetect = opts.lazier.redetect_filetype
    if redetect == nil then
        redetect = false
    end
    assert(type(redetect) == "boolean" or vim.islist(redetect), "lazier: redetect_filetype must be a boolean or a list of patterns")
    local function glob_hit(pattern, target, file)
        if target == file and not pattern:find("/") then -- like nvim, slash-less file patterns match the tail
            target = vim.fn.fnamemodify(file, ":t")
        end
        return vim.regex(vim.fn.glob2regpat(pattern)):match_str(target) ~= nil
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
                local function catch_up()
                    if not vim.api.nvim_buf_is_loaded(buf) then
                        return
                    end
                    local trigger = require("lazy.core.handler.event").trigger
                    local file = vim.api.nvim_buf_get_name(buf)
                    local detected = false -- its FileType then already reached every group
                    local before = vim.bo[buf].filetype
                    local wants_redetect = before == "" or redetect == true
                        or type(redetect) == "table" and vim.iter(redetect):any(function(p) return glob_hit(p, file, file) end)
                    for _, ev in ipairs(events) do
                        if ev == "BufReadPost" and wants_redetect and vim.fn.exists("#filetypedetect#BufReadPost") == 1 then -- ftdetect of plugins added by lazy.setup lands in the old filetypedetect group
                            local eventignore = vim.o.eventignore
                            vim.opt.eventignore:append("FileType") -- an unchanged filetype must not refire every FileType handler
                            trigger({ event = ev, group = "filetypedetect", buffer = buf })
                            vim.o.eventignore = eventignore
                            if vim.bo[buf].filetype ~= before then
                                vim.bo[buf].filetype = vim.bo[buf].filetype
                                detected = true
                            end
                        end
                        if detected and (ev == "FileType" or ev == "Syntax") then
                            goto continue
                        end
                        trigger({ event = ev, exclude = old_groups[ev], buffer = buf })
                        -- lazy's trigger only reaches grouped autocmds, and exec_autocmds can't target the ungrouped ones alone
                        local match = ev == "FileType" and vim.bo[buf].filetype or ev == "Syntax" and vim.bo[buf].syntax or file
                        for _, au in ipairs(vim.api.nvim_get_autocmds({ event = ev })) do
                            if not au.group and not old_ungrouped[ungrouped_key(au)] then
                                if au.buflocal and au.buffer == buf or not au.buflocal and glob_hit(au.pattern, match, file) then
                                    if au.once then
                                        vim.api.nvim_del_autocmd(assert(au.id, "vimscript ++once autocmds carry no id to delete by"))
                                    end
                                    require("lazy.core.util").try(function()
                                        vim.api.nvim_buf_call(buf, function()
                                            if au.callback then
                                                au.callback({ id = au.id, event = ev, match = match, buf = buf, file = file })
                                            else
                                                vim.cmd(au.command)
                                            end
                                        end)
                                    end)
                                end
                            end
                        end
                        ::continue::
                    end
                    if detected then
                        return
                    end
                    local new_rtp = {}
                    for _, path in ipairs(vim.opt.rtp:get()) do
                        if not old_rtp[path] then
                            table.insert(new_rtp, (path:gsub(",", "\\,")))
                        end
                    end
                    new_rtp = table.concat(new_rtp, ",")
                    local ft = vim.bo[buf].filetype
                    if ft ~= "" and (vim.fn.globpath(new_rtp, "{ftplugin,indent,syntax}/" .. ft .. "[._]*") ~= "" or vim.fn.globpath(new_rtp, "{ftplugin,indent,syntax}/" .. ft .. "/*") ~= "") then -- old groups filetypeplugin/filetypeindent/syntaxset source these
                        for _, au in ipairs(vim.api.nvim_get_autocmds({ event = "FileType" })) do
                            if au.group_name == "filetypeplugin" or au.group_name == "filetypeindent" or au.group_name == "syntaxset" then
                                trigger({ event = "FileType", group = au.group_name, buffer = buf })
                            end
                        end
                    end
                end
                if visible[buf] then
                    catch_up()
                else
                    vim.api.nvim_create_autocmd("BufEnter", {
                        buffer = buf,
                        once = true,
                        callback = function()
                            vim.schedule(catch_up)
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
