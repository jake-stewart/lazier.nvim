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
                end
            end
        end
    end

    return spec
end
