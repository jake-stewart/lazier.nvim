--- @class PartialProxy
local PartialProxy = {}

local function ignore(self)
    return self
end

PartialProxy.__call = ignore
PartialProxy.__index = ignore
PartialProxy.__add = ignore
PartialProxy.__mul = ignore
PartialProxy.__div = ignore
PartialProxy.__sub = ignore
PartialProxy.__unm = ignore
PartialProxy.__mod = ignore
PartialProxy.__pow = ignore
PartialProxy.__eq = ignore
PartialProxy.__lt = ignore
PartialProxy.__le = ignore
PartialProxy.__len = ignore
PartialProxy.__concat = ignore

local function new_partial_proxy(obj)
    return setmetatable(obj, PartialProxy)
end

return new_partial_proxy
