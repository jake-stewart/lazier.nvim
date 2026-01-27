local state = require "lazier.state"

local M = {}

function M.const_require(module)
    state.const_modules[module] = true
    return require(module)
end

function M.compile_require(module)
    if state.compiled then
        return require(module)
    else
        local src = require(module)
        state.compile_modules[module] = src
        return loadstring(src)()
    end
end

return M
