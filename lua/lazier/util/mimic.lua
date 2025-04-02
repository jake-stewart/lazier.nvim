--- @class MimicMetatable
--- @field _mimic any
local MimicMetatable = {}

function MimicMetatable.__index(self, key)
    return self._mimic[key]
end

function MimicMetatable.__call(self, ...)
    return self._mimic(...)
end

local function binary(callback)
    return function(a, b)
        if getmetatable(a) == MimicMetatable then
            return callback(a._mimic, b)
        else
            return callback(a, b._mimic)
        end
    end
end

local function unary(callback)
    return function(a)
        return callback(a._mimic)
    end
end

MimicMetatable.__add = binary(function(a, b) return a + b end)
MimicMetatable.__mul = binary(function(a, b) return a * b end)
MimicMetatable.__div = binary(function(a, b) return a / b end)
MimicMetatable.__sub = binary(function(a, b) return a - b end)
MimicMetatable.__unm = unary(function(a) return -a end)
MimicMetatable.__mod = binary(function(a, b) return a % b end)
MimicMetatable.__pow = binary(function(a, b) return a ^ b end)
MimicMetatable.__eq = binary(function(a, b) return a == b end)
MimicMetatable.__lt = binary(function(a, b) return a < b end)
MimicMetatable.__le = binary(function(a, b) return a < b end)
MimicMetatable.__len = unary(function(a) return #a end)
MimicMetatable.__concat = binary(function(a, b) return a .. b end)

--- @generic T
--- @obj any
--- @mimic T
--- @return T
local function create_mimic(obj, mimic)
    setmetatable(obj, nil)
    for k in pairs(obj) do
        obj[k] = nil
    end
    obj._mimic = mimic
    return setmetatable(obj, MimicMetatable)
end

return {
    new = create_mimic
};
