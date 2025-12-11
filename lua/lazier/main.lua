vim.loader.enable()

local Lazier = {}

function Lazier.setup(module, opts)
    local setup_lazier = require("lazier.setup")
    setup_lazier(module, opts)
end

return setmetatable(Lazier, Lazier)
