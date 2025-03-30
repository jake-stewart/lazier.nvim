vim.api.nvim_create_user_command("LazierUpdate", function()
    require("lazier.update")()
end, {})


local Lazier = {
    compiled = false
}

--- @param opts LazyPluginSpec
--- @return LazyPluginSpec
function Lazier.__call(_, opts)
    --return opts
    return require("lazier.wrap")(opts)
end

function Lazier.setup(module, opts)
    return require("lazier.setup")(module, opts)
end

return setmetatable(Lazier, Lazier)
