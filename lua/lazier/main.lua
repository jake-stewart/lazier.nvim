require "lazier.commands"

local Lazier = {}

--- @param opts LazyPluginSpec
--- @return LazyPluginSpec
function Lazier.__call(_, opts)
    if Lazier.compiled then
        return opts
    end
    local wrap = require("lazier.wrap")
    return wrap(opts)
end

function Lazier.setup(module, opts)
    local setup_lazier = require("lazier.setup")
    setup_lazier(module, opts)
end

return setmetatable(Lazier, Lazier)
