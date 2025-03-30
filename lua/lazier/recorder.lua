local np = require "lazier.npack"

--- @class RecorderInfo
--- @field list? any[]
--- @field lhs? any
--- @field operation? string
--- @field rhs? any

--- @type {[any]: RecorderInfo}
local PROXY_INFO = setmetatable({}, { __mode = "k" })
-- local PROXY_INFO = {}

local function info(recorder)
    return PROXY_INFO[recorder]
end

--- @type {[any]: any}
local EVALUATED = setmetatable({}, { __mode = "k" })
-- local EVALUATED = {}

local PRIMITIVES = {
    ["string"] = true,
    ["number"] = true,
    ["boolean"] = true,
    ["nil"] = true,
    ["userdata"] = true,
    ["thread"] = true
}

local Recorder = {}

--- @param parent RecorderInfo
--- @param lhs any
--- @param op string
--- @param rhs? any
local function operation(parent, lhs, op, rhs)
    local recorder = setmetatable({}, Recorder)
    if parent.list then
        table.insert(parent.list, recorder)
    end
    PROXY_INFO[recorder] = {
        lhs = lhs,
        operation = op,
        list = parent.list,
        rhs = rhs,
    }
    return recorder
end

--- @class Operator
--- @field impl function
--- @field name string
--- @field binary boolean

--- @type Operator[]
local OPERATORS = {}

local function operator(name, binary, impl)
    if binary then
        Recorder[name] = function(a, b)
            local recorder = getmetatable(a) == Recorder and a or b
            return operation(info(recorder), a, name, b)
        end
    else
        Recorder[name] = function(self)
            return operation(info(self), self, name)
        end
    end
    OPERATORS[name] = {
        name = name,
        impl = impl,
        binary = binary
    }
end

function Recorder.__call(self, ...)
    return operation(info(self), self, "__call", np.pack(...))
end

function Recorder.__index(self, key)
    return operation(info(self), self, "__index", key)
end

operator("__add", true, function(a, b) return a + b end)
operator("__mul", true, function(a, b) return a * b end)
operator("__div", true, function(a, b) return a / b end)
operator("__sub", true, function(a, b) return a - b end)
operator("__unm", false, function(a) return -a end)
operator("__mod", true, function(a, b) return a % b end)
operator("__pow", true, function(a, b) return a ^ b end)
operator("__eq", true, function(a, b) return a == b end)
operator("__lt", true, function(a, b) return a < b end)
operator("__le", true, function(a, b) return a <= b end)
operator("__len", false, function(a) return #a end)
operator("__concat", true, function(a, b) return a .. b end)

local M = {}

--- @param recorder any
--- @param value any
function M.setValue(recorder, value)
    EVALUATED[recorder] = { value }
end

--- @param obj any
--- @return string
function M.visualize(obj)
    if getmetatable(obj) == Recorder then
        return M.visualizeProxyInfo(PROXY_INFO[obj])
    else
        return M.visualizeObject(obj)
    end
end

function M.visualizeProxyInfo(item)
    if not item.operation then
        return tostring(item.lhs or "value")
    elseif item.operation == "__call" then
        local buffer = {}
        for i = 1, item.rhs.n do
            if i > 1 then
                table.insert(buffer, ", ")
            end
            table.insert(buffer, M.visualize(item.rhs[i]))
        end
        return M.visualize(item.lhs)
            .. "(" .. table.concat(buffer, "") .. ")"
    elseif item.operation == "__index" then
        if type(item.rhs) == "string" then
            return M.visualize(item.lhs) .. "." .. item.rhs
        else
            return M.visualize(item.lhs)
                .. "[" ..  M.visualize(item.rhs) .. "]"
        end
    else
        local op = OPERATORS[item.operation]
        local args = {
            M.visualize(item.lhs),
            op.binary and M.visualize(item.rhs) or nil,
        }
        return op.name .. "(" .. table.concat(args, ", ") .. ")"
    end
end

--- @param obj any
--- @return string
function M.visualizeObject(obj)
    if type(obj) == "string" then
        return '"' .. obj:gsub('"', '\\"') .. '"'
    elseif type(obj) == "table" then
        --- @type number | nil
        local lastSequentialKey = 0
        local buffer = {}
        for k, v in pairs(obj) do
            if lastSequentialKey and k == lastSequentialKey + 1 then
                lastSequentialKey = k
                table.insert(buffer, M.visualize(v))
            else
                lastSequentialKey = nil
                table.insert(
                    buffer,
                    "[" .. M.visualize(k) .. "] = " .. M.visualize(v)
                )
            end
        end
        return "{" .. table.concat(buffer, ", ") .. "}"
    elseif type(obj) == "function" then
        return "<function>"
    else
        return tostring(obj)
    end
end

--- @param obj any
--- @return any
function M.eval(obj)
    if PRIMITIVES[type(obj)] then
        return obj
    end
    local evaluated = EVALUATED[obj]
    if evaluated then
        return evaluated[1]
    end
    local value
    if getmetatable(obj) == Recorder then
        value = M.evalProxyInfo(PROXY_INFO[obj])
    else
        value = M.evalObject(obj)
    end
    EVALUATED[obj] = { value }
    return value
end

function M.evalProxyInfo(item)
    if item.operation == "__call" then
        local args = { n = item.rhs.n }
        for i = 1, item.rhs.n do
            args[i] = M.eval(item.rhs[i])
        end
        local f = M.eval(item.lhs)
        return f(np.unpack(args))
    elseif item.operation == "__index" then
        local obj = M.eval(item.lhs)
        return obj[M.eval(item.rhs)]
    elseif item.operation then
        local op = OPERATORS[item.operation]
        return op.binary
            and op.impl(M.eval(item.lhs), M.eval(item.rhs))
            or op.impl(M.eval(item.lhs))
    else
        error("invalid operation")
    end
end

function M.evalObject(obj)
    if type(obj) == "table" then
        local evaluated = {}
        for k, v in pairs(obj) do
            evaluated[M.eval(k)] = M.eval(v)
        end
        return setmetatable(evaluated, getmetatable(obj))
    elseif type(obj) == "function" then
        return function(...)
            local args = np.pack(...)
            for i = 1, args.n do
                args[i] = M.eval(args[i])
            end
            return obj(np.unpack(args))
        end
    else
        error("unexpected type:" .. type(obj))
    end
end

--- @param recorder any
function M.clear(recorder)
    EVALUATED[recorder] = nil
end

--- @param recorder any
function M.delete(recorder)
    PROXY_INFO[recorder] = nil
end

--- @param list? any[]
--- @param name? string
--- @return any
function M.new(list, name)
    local recorder = setmetatable({}, Recorder)
    PROXY_INFO[recorder] = { lhs = name, list = list }
    return recorder
end

function M.countUsage()
    local count = {
        proxies = 0,
        objects = 0
    }
    for _ in pairs(PROXY_INFO) do
        count.proxies = count.proxies + 1
    end
    for _ in pairs(EVALUATED) do
        count.objects = count.objects + 1
    end
    return count
end

function M.debug()
    local before = M.countUsage()
    collectgarbage("collect")
    local after = M.countUsage()
    print("objects: " .. before.objects
        .. " -> " .. after.objects)
    print("proxies: " .. before.proxies
        .. " -> " .. after.proxies)
end

return {
    new = M.new,
    setValue = M.setValue,
    clear = M.clear,
    delete = M.delete,
    eval = M.eval,
    visualize = M.visualize,
    debug = M.debug
}
