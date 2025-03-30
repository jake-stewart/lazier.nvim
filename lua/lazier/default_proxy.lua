local DefaultProxy = {}

local VALUES = setmetatable({}, { __mode = "k" })

local function newDefaultProxy(value)
    local proxy = setmetatable({}, DefaultProxy)
    VALUES[proxy] = value
    return proxy
end

function DefaultProxy.__index(t, key)
    local proxy_value = VALUES[t]
    if proxy_value[key] == nil then
        local value = {}
        proxy_value[key] = value
        return newDefaultProxy(value)
    else
        return proxy_value[key]
    end
end

function DefaultProxy.__newindex(t, key, value)
    VALUES[t][key] = value
end

return newDefaultProxy
