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
    if not s:match("^[a-zA-Z_]+[a-zA-Z0-9_]$") then
        return false
    end
    return not RESERVED_WORDS[s]
end

function M.serialize(o, depth, max_line_length)
    max_line_length = max_line_length or 80
    if type(o) == "string" then
        return '"' .. o:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
    elseif type(o) == "number" or type(o) == "boolean" or o == nil then
        return tostring(o)
    elseif getmetatable(o) == M.Fragment then
        return o[1]
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

function M.can_serialize(o)
    if type(o) == "string"
        or type(o) == "number"
        or type(o) == "boolean"
        or o == nil
    then
        return true
    elseif type(o) == "table" then
        local metatable = getmetatable(o)
        if metatable == M.Fragment then
            return true
        elseif metatable then
            return false
        end
        for k, v in pairs(o) do
            if not M.can_serialize(k)
                or not M.can_serialize(v)
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
