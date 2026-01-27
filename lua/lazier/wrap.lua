local np = require "lazier.util.npack"

local AUTOCOMMAND_GROUPS = {
    insertenter = {
        "insertenter",
        "insertleave",
        "insertchange",
        "textchangedi",
        "textchangedp",
        "cursormovedi",
        "completechanged",
    },
    cmdlineenter = {
        "cmdlineenter",
        "cmdlineleave",
        "cmdlinechanged",
    },
    cmdwinenter = {
        "cmdwinenter",
        "cmdwinleave",
    }
}

local commands = vim.api.nvim_get_commands({ builtin = false })

--- @param spec LazyPluginSpec | LazyPluginSpec[]
--- @return LazyPluginSpec
return function(spec)
    spec = spec or {}

    local plugins = spec
    if
        type(plugins[1]) == "string"
        or type(plugins.url) == "string"
        or type(plugins.dir) == "string"
    then
        plugins = { plugins }
    end

    for _, plugin in ipairs(plugins --[[ @as LazyPluginSpec[] ]]) do
        if plugin.enabled == false or plugin.lazy == false then
        else
            local pluginConfig = plugin.config
            local pluginOpts = plugin.opts
            if (type(pluginConfig) == "function") ~= (pluginOpts ~= nil) then
                local isPluginLazy = plugin.lazy
                plugin.lazy = false
                plugin.config = function(lazyPlugin, lazyPluginOpts)
                    if pluginConfig == nil then
                        pluginConfig = function()
                            local loader = require("lazy.core.loader")
                            local main = loader.get_main(lazyPlugin)
                            if main then
                                require(main).setup(lazyPluginOpts)
                            end
                        end
                    end
                    plugin.lazy = isPluginLazy
                    local wrappers = {
                        keymaps = { obj = vim.keymap, name = "set" },
                        events = { obj = vim.api, name = "nvim_create_autocmd" },
                    }
                    for _, wrapper in pairs(wrappers) do
                        wrapper.original = wrapper.obj[wrapper.name]
                        wrapper.calls = {}
                        wrapper.obj[wrapper.name] = function(...)
                            local ret = wrapper.original(...)
                            table.insert(wrapper.calls, np.pack(...))
                            return ret
                        end
                    end
                    local success, result = pcall(pluginConfig)
                    for _, wrapper in pairs(wrappers) do
                        wrapper.obj[wrapper.name] = wrapper.original
                    end
                    if not success then
                        error(result)
                    end

                    local new_commands = vim.api.nvim_get_commands({ builtin = false })
                    for k in pairs(new_commands) do
                      if not commands[k] then
                        if type(plugin.cmd) == "table" then
                        elseif type(plugin.cmd) == "string" then
                            plugin.cmd = { plugin.cmd --[[ @as any ]] }
                        else
                            plugin.cmd = {}
                        end
                        table.insert(plugin.cmd --[[ @as any ]], k)
                      end
                    end
                    commands = new_commands

                    if #wrappers.events.calls > 0 then
                        if type(plugin.ft) == "table" then
                        elseif type(plugin.ft) == "string" then
                            plugin.ft = { plugin.ft --[[ @as any ]] }
                        else
                            plugin.ft = {}
                        end
                        if type(plugin.event) == "table" then
                        elseif type(plugin.event) == "string" then
                            plugin.event = { plugin.event --[[ @as any ]] }
                        else
                            plugin.event = {}
                        end
                        local function add_filetypes(au_opts)
                            if type(au_opts) == "table" then
                                if type(au_opts.pattern) == "string" then
                                    table.insert(plugin.ft, au_opts.pattern)
                                elseif type(au_opts.pattern) == "table" then
                                    for _, ft in ipairs(au_opts.pattern) do
                                        table.insert(plugin.ft, ft)
                                    end
                                end
                            end
                        end
                        for _, args in ipairs(wrappers.events.calls) do
                            if type(args[1]) == "string" then
                                local lower = args[1]:lower()
                                if lower == "filetype" then
                                    add_filetypes(args[2])
                                else
                                    table.insert(plugin.event --[[ @as any ]], args[1])
                                end
                            elseif type(args[1]) == "table" then
                                for _, event in ipairs(args[1]) do
                                    table.insert(plugin.event --[[ @as any ]], event)
                                end
                            end
                        end
                        local uniq_events = {}
                        for _, v in ipairs(plugin.event) do
                            uniq_events[v:lower()] = true
                        end
                        for enter_cmd, group in pairs(AUTOCOMMAND_GROUPS) do
                            local has_autocmd = false
                            for _, autocmd in ipairs(group) do
                                if uniq_events[autocmd] then
                                    has_autocmd = true
                                    break
                                end
                            end
                            if has_autocmd then
                                for _, autocmd in ipairs(group) do
                                    uniq_events[autocmd] = nil
                                end
                                uniq_events[enter_cmd] = true
                            end
                        end
                        local uniq_ft = {}
                        for _, v in ipairs(plugin.ft) do
                            uniq_ft[v:lower()] = true
                        end
                        plugin.event = vim.tbl_keys(uniq_events)
                        plugin.ft = vim.tbl_keys(uniq_ft)
                        for _, e in ipairs(plugin.event --[[ @as any ]]) do
                            if e == "vimenter"
                                or e == "bufenter"
                                or e == "winenter"
                                or e == "bufwinenter"
                                or e == "verylazy"
                            then
                                plugin.event = { "VeryLazy" }
                                break
                            end
                        end
                    end

                    if #wrappers.keymaps.calls > 0 then
                        if type(plugin.keys) == "table" then
                        elseif type(plugin.keys) == "string" then
                            plugin.keys = { plugin.keys --[[ @as any ]] }
                        else
                            plugin.keys = {}
                        end
                        if type(plugin.keys) ~= "table" then
                            error("expected table for 'keys'")
                        end
                        for _, args in ipairs(wrappers.keymaps.calls) do
                            local desc = type(args[4]) == "table"
                                and args[4].desc
                                or nil
                            table.insert(plugin.keys --[[ @as any ]], {
                                args[2],
                                mode = args[1],
                                desc = desc
                            })
                        end
                    end
                end
            end
        end
    end

    return spec
end
