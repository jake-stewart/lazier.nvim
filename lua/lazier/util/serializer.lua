local np = require "lazier.util.npack"

local RESERVED_WORDS = {
    ["and"] = true,
    ["break"] = true,
    ["do"] = true,
    ["else"] = true,
    ["elseif"] = true,
    ["end"] = true,
    ["false"] = true,
    ["for"] = true,
    ["function"] = true,
    ["if"] = true,
    ["in"] = true,
    ["local"] = true,
    ["nil"] = true,
    ["not"] = true,
    ["or"] = true,
    ["repeat"] = true,
    ["return"] = true,
    ["then"] = true,
    ["true"] = true,
    ["until"] = true,
    ["while"] = true
}

local M = {}

M.Fragment = {}

local dict_metatable = getmetatable(vim.empty_dict())

function M.fragment(s)
    return setmetatable({ tostring(s) }, M.Fragment)
end

function M.index(obj, ...)
    if type(obj) ~= "string" then
        obj = M.serialize(obj)
    end
    local path = np.pack(...)
    local serialized_path = {}
    for i = 1, path.n do
        if M.valid_identifier(path[i]) then
            serialized_path[i] = "." .. path[i]
        else
            serialized_path[i] = "[" .. M.serialize(path[i]) .. "]";
        end
    end
    return M.fragment(obj .. table.concat(serialized_path, ""))
end

function M.assignment(lhs, rhs)
    if type(lhs) ~= "string" then
        lhs = M.serialize(lhs)
    end
    return M.fragment(lhs .. " = " .. M.serialize(rhs))
end

function M.function_call(func, ...)
    if type(func) ~= "string" then
        func = M.serialize(func)
    end
    local args = np.pack(...)
    local serialized_args = {}
    for i = 1, args.n do
        serialized_args[i] = M.serialize(args[i])
    end
    return M.fragment(
        func .. "(" .. table.concat(serialized_args, ", ") .. ")"
    )
end

function M.valid_identifier(s)
    if type(s) ~= "string" then
        return false
    end
    if not s:match("^[a-zA-Z_][a-zA-Z0-9_]*$") then
        return false
    end
    return not RESERVED_WORDS[s]
end

function M.serialize(o, depth, max_line_length)
    max_line_length = max_line_length or 80
    if type(o) == "string" then
        return ("%q"):format(o)
    elseif type(o) == "number" then
        if o ~= o then
            return "0/0"
        elseif o == math.huge then
            return "math.huge"
        elseif o == -math.huge then
            return "-math.huge"
        elseif tonumber(tostring(o)) == o then
            return tostring(o)
        end
        return ("%.17g"):format(o)
    elseif type(o) == "boolean" or o == nil then
        return tostring(o)
    elseif o == vim.NIL then
        return "vim.NIL"
    elseif getmetatable(o) == M.Fragment then
        return o[1]
    elseif getmetatable(o) == dict_metatable then
        if next(o) == nil then
            return "vim.empty_dict()"
        end
        return "setmetatable("
            .. M.serialize(setmetatable(vim.deepcopy(o), nil), depth, max_line_length)
            .. ", getmetatable(vim.empty_dict()))"
    elseif type(o) == "table" then
        local buffer = {}
        local last_index = 0
        depth = depth or 0
        for k, v in pairs(o) do
            if k == last_index + 1 and k > 0 then
                last_index = k
                table.insert(buffer, M.serialize(v, depth + 1))
            else
                last_index = -1
                if M.valid_identifier(k) then
                    local key = k .. " = "
                    table.insert(buffer, key .. M.serialize(
                        v, depth + 1, max_line_length - #key))
                else
                    local key = "[" .. M.serialize(k, depth + 1) .. "] = "
                    table.insert(buffer, key .. M.serialize(
                        v, depth + 1, max_line_length - #key))
                end
            end
        end
        local total_length = 0
        for _, item in ipairs(buffer) do
            total_length = total_length + #item
        end
        total_length = total_length + (#buffer - 1) * 2 + 4 + (depth * 4)
        if #buffer == 0 then
            return "{}"
        elseif total_length <= max_line_length then
            return "{ " .. table.concat(buffer, ", ") .. " }"
        else
            local ws = "\n" .. string.rep(" ", (depth + 1) * 4)
            return "{"
                .. ws
                .. table.concat(buffer, "," .. ws)
                .. "\n"
                .. string.rep(" ", depth * 4)
                .. "}"
        end
    else
        error("cannot serialize: " .. type(o))
    end
end

function M.can_serialize(o, seen)
    if type(o) == "string"
        or type(o) == "number"
        or type(o) == "boolean"
        or o == nil
        or o == vim.NIL
    then
        return true
    elseif type(o) == "table" then
        local metatable = getmetatable(o)
        if metatable == M.Fragment then
            return true
        elseif metatable and metatable ~= dict_metatable then
            return false
        end
        seen = seen or {}
        if seen[o] then
            return false
        end
        seen[o] = true
        for k, v in pairs(o) do
            if type(k) == "table"
                or not M.can_serialize(k)
                or not M.can_serialize(v, seen)
            then
                return false
            end
        end
        return true
    else
        return false
    end
end

return M
