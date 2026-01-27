local Lazier = {}

function Lazier.setup(module, opts)
    require("lazier.setup")(module, opts)
end

local lazier_require = require("lazier.require")
Lazier.const_require = lazier_require.const_require
Lazier.compile_require = lazier_require.compile_require

return setmetatable(Lazier, Lazier)
