--- @diagnostic disable-next-line
table.unpack = table.unpack or unpack

local pack = function(...)
    return { n = select("#", ...), ... }
end

local unpack = function(t)
    return unpack(t, 1, t.n)
end

--- @class RecorderMetatable
local RecorderMetatable = {}

local function createRecorder(list)
    return setmetatable({ _list = list }, RecorderMetatable)
end

local evaluatedLookup = setmetatable({}, { __mode = "k" })
-- local evaluatedLookup = setmetatable({}, {})

local primitives = {
    ["string"] = true,
    ["number"] = true,
    ["boolean"] = true,
    ["nil"] = true,
}

local function evaluateRecorder(value, obj)
    if primitives[type(value)] then
        return value
    end
    local evaluated = evaluatedLookup[value]
    if not evaluated then
        if getmetatable(value) == RecorderMetatable then
            local result = value._callback(obj)
            if type(result) == "function" then
                evaluated = { function(...)
                    local args = pack(...)
                    for i = 1, args.n do
                        args[i] = evaluateRecorder(args[i], obj)
                    end
                    return result(unpack(args))
                end }
            else
                evaluated = { result }
            end
        elseif type(value) == "table" then
            local copy = {}
            for k, v in pairs(value) do
                copy[evaluateRecorder(k, obj)] = evaluateRecorder(v, obj)
            end
            evaluated = { copy }
        elseif type(value) == "function" then
            evaluated = { function(...)
                local args = pack(value(...))
                for i = 1, args.n do
                    args[i] = evaluateRecorder(args[i], obj)
                end
                return unpack(evaluateRecorder(args, obj))
            end }
        else
            evaluated = { value }
        end
        evaluatedLookup[value] = evaluated
    end
    return evaluated[1]
end

local function child(self, callback)
    local recorder = createRecorder(self._list)
    rawset(recorder, "_callback", function(obj)
        local value = evaluatedLookup[recorder]
        if not value then
            value = { callback(self._callback(obj)) }
            evaluatedLookup[recorder] = value
        end
        return value[1]
    end)
    table.insert(self._list, recorder)
    return recorder
end

function RecorderMetatable.__index(self, key)
    return child(self, function(obj)
        return obj[key]
    end)
end

function RecorderMetatable.__call(self, ...)
    local args = pack(...)
    return child(self, function(obj)
        for i = 1, args.n do
            args[i] = evaluateRecorder(args[i], obj)
        end
        return obj(unpack(args))
    end)
end

local function binary(callback)
    return function(a, b)
        if getmetatable(a) == RecorderMetatable then
            return child(a, function(obj) return callback(obj, b) end)
        else
            return child(b, function(obj) return callback(a, obj) end)
        end
    end
end

local function unary(callback)
    return function(a)
        return child(a, callback)
    end
end

RecorderMetatable.__add = binary(function(a, b) return a + b end)
RecorderMetatable.__mul = binary(function(a, b) return a * b end)
RecorderMetatable.__div = binary(function(a, b) return a / b end)
RecorderMetatable.__sub = binary(function(a, b) return a - b end)
RecorderMetatable.__unm = unary(function(a) return -a end)
RecorderMetatable.__mod = binary(function(a, b) return a % b end)
RecorderMetatable.__pow = binary(function(a, b) return a ^ b end)
RecorderMetatable.__eq = binary(function(a, b) return a == b end)
RecorderMetatable.__lt = binary(function(a, b) return a < b end)
RecorderMetatable.__le = binary(function(a, b) return a < b end)
RecorderMetatable.__len = unary(function(a) return #a end)
RecorderMetatable.__concat = binary(function(a, b) return a .. b end)

local function newRecorder()
    local recorder = createRecorder({})
    rawset(recorder, "_callback", function(obj) return obj end)
    return recorder
end

return {
    new = newRecorder,
    eval = evaluateRecorder
}
