local np = require "lazier.util.npack"

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
        if plugin.enabled == false
            or plugin.lazy == false
            or type(plugin.config) ~= "function"
        then
        else
            local pluginConfig = plugin.config;
            if type(pluginConfig) == "function" then
                local isPluginLazy = plugin.lazy
                plugin.lazy = false
                plugin.config = function()
                    plugin.lazy = isPluginLazy
                    local wrappers = {
                        keymaps = { obj = vim.keymap, name = "set" },
                        -- autocmds = { obj = vim.api, name = "nvim_create_autocmd" },
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

                    -- if #wrappers.autocmds.calls > 0 then
                    --     if type(plugin.event) == "table" then
                    --     elseif type(plugin.event) == "string" then
                    --         plugin.event = { plugin.event --[[ @as any ]] }
                    --     else
                    --         plugin.event = {}
                    --     end
                    --     if type(plugin.event) ~= "table" then
                    --         error("expected table for 'event'")
                    --     end
                    --     for _, args in ipairs(wrappers.autocmds.calls) do
                    --         if type(args[1]) == "string" then
                    --             table.insert(plugin.event --[[ @as any ]], args[1])
                    --         else
                    --             for _, event in ipairs(args[1]) do
                    --                 table.insert(plugin.event --[[ @as any ]], event)
                    --             end
                    --         end
                    --     end
                    -- end

                end
            end
        end
    end

    return spec
end
