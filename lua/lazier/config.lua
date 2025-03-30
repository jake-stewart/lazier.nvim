return function(modulePath, ...)
    local module = require(modulePath)

    if type(module.keys) == "table" then
        for _, spec in ipairs(module.keys) do
            if type(spec) == "table" then
                local rhs = spec[2]
                local ft = spec.ft
                if rhs and not ft then
                    local lhs = spec[1]
                    local mode = spec.mode or "n"
                    vim.keymap.set(mode, lhs, rhs)
                end
            end
        end
    end

    if type(module.config) == "function" then
        module.config(...)
    end

end
