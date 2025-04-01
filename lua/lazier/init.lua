--- @type any
local uv = vim.uv or vim.loop

vim.api.nvim_create_user_command("LazierUpdate", function()
    require("lazier.update")()
end, {})

local separator = vim.fn.has('macunix') == 1 and "/" or "\\"
local lazierData = vim.fn.stdpath("data") .. separator .. "lazier"
local lazierBytecode = lazierData .. separator .. "lazierbytecode.lua"

if not uv.fs_stat(lazierBytecode) then
    require("lazier.bytecode")(lazierBytecode)
end
loadfile(lazierBytecode, "b")()

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
