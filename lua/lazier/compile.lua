local PreCompiled = {}

--- @type any
local uv = vim.uv or vim.loop

local separator = vim.fn.has('macunix') == 1 and "/" or "\\"

local function writeFile(path, data)
    local fd = assert(uv.fs_open(path, "w", 438))
    assert(uv.fs_write(fd, data))
    assert(uv.fs_close(fd))
end

local function preCompile(s)
    return setmetatable({ code = s }, PreCompiled)
end

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

-- local function x()
--     yield 5
-- end

local function validIdentifier(s)
    if type(s) ~= "string" then
        return false
    end
    if not s:match("^[a-zA-Z_]+[a-zA-Z0-9_]$") then
        return false
    end
    return not RESERVED_WORDS[s]
end

local function compile(o, depth, maxLineLength)
    maxLineLength = maxLineLength or 80
    if type(o) == "string" then
        return '"' .. o:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
    elseif type(o) == "number" or type(o) == "boolean" or o == nil then
        return tostring(o)
    elseif getmetatable(o) == PreCompiled then
        return o.code
    elseif type(o) == "table" then
        local buffer = {}
        local lastIndex = 0
        depth = depth or 0
        for k, v in pairs(o) do
            if k == lastIndex + 1 and k > 0 then
                lastIndex = k
                table.insert(buffer, compile(v, depth + 1))
            else
                lastIndex = -1
                if validIdentifier(k) then
                    local key = k .. " = "
                    table.insert(buffer, key .. compile(v, depth + 1, maxLineLength - #key))
                else
                    local key = "[" .. compile(k, depth + 1) .. "] = "
                    table.insert(buffer, key .. compile(v, depth + 1, maxLineLength - #key))
                end
            end
        end
        local totalLength = 0
        for _, item in ipairs(buffer) do
            totalLength = totalLength + #item
        end
        totalLength = totalLength + (#buffer - 1) * 2 + 4 + (depth * 4)
        if #buffer == 0 then
            return "{}"
        elseif totalLength <= maxLineLength then
            return "{ " .. table.concat(buffer, ", ") .. " }"
        else
            local ws = "\n" .. string.rep(" ", (depth + 1) * 4)
            return "{" .. ws .. table.concat(buffer, "," .. ws) .. "\n" .. string.rep(" ", depth * 4) .. "}"
        end
    else
        error("cannot compile: " .. type(o))
    end
end

local function canCompile(o)
    if type(o) == "string" or type(o) == "number" or type(o) == "boolean" or o == nil then
        return true
    elseif type(o) == "table" then
        if getmetatable(o) then
            return false
        end
        for k, v in pairs(o) do
            if not canCompile(k) or not canCompile(v) then
                return false
            end
        end
        return true
    else
        return false
    end
end

local function compilePlugins(module, transpiledFile)
    local lazy = require("lazy")
    local specPlugins = {}

    local colors_name = vim.g.colors_name
    local colorRtp

    local lazyPlugins = lazy.plugins()

    local useConfigFunc = false
    local useSetupFunc = false
    local useOptsFunc = false

    local lazyUtil = require("lazy.core.util")
    lazyUtil.lsmod(module, function(pluginPath)
        local plugin = require(pluginPath)
        local lazyPlugin
        for _, candidate in ipairs(lazyPlugins) do
            if candidate[1] and candidate[1] == plugin[1]
                or candidate.url and candidate.url == plugin.url
                or candidate.dir and candidate.dir == plugin.dir
            then
                lazyPlugin = candidate
                break
            end
        end
        if lazyPlugin == nil then
            return
        end
        if colors_name and not colorRtp then
            local extensions = { "vim", "lua" }
            for _, extension in ipairs(extensions) do
                local path = table.concat({ lazyPlugin.dir, "colors", colors_name .. "." .. extension }, separator)
                if vim.fn.filereadable(path) == 1 then
                    colorRtp = lazyPlugin.dir
                    break
                end
            end
        end
        local spec = {}
        spec[1] = plugin[1]
        spec.dir = plugin.dir
        spec.event = plugin.event
        spec.branch = plugin.branch
        spec.dependencies = plugin.dependencies
        spec.lazy = plugin.lazy
        spec.ft = plugin.ft
        spec.opts = plugin.opts
        if plugin.opts then
            if canCompile(plugin.opts) then
                spec.opts = plugin.opts
            else
                useOptsFunc = true
                spec.opts = preCompile("__opts(" .. compile(pluginPath) .. ")")
            end
        end
        if plugin.config then
            useConfigFunc = true
            spec.config = preCompile("__config(" .. compile(pluginPath) .. ")")
        end
        if plugin.setup then
            useSetupFunc = true
            spec.config = preCompile("__setup(" .. compile(pluginPath) .. ")")
        end
        if lazyPlugin.keys then
            spec.keys = {}
            for _, key in pairs(lazyPlugin.keys) do
                if type(key) == "string" then
                    table.insert(spec.keys, key)
                else
                    if key.mode and key.mode ~= "n" then
                        table.insert(spec.keys, { key[1], mode = key.mode })
                    else
                        table.insert(spec.keys, key[1])
                    end
                end
            end
        end
        table.insert(specPlugins, spec)
    end)

    local configFunc = "local function __config(module)\n"
        .. "    return function(...)\n"
        .. "        return require(module).config(...)\n"
        .. "    end\n"
        .. "end\n"

    local setupFunc = "local function __setup(module)\n"
        .. "    return function(...)\n"
        .. "        return require(module).setup(...)\n"
        .. "    end\n"
        .. "end\n"

    local optsFunc = "local function __opts(module)\n"
        .. "    return require(module).opts\n"
        .. "end\n"

    local compiled = (useConfigFunc and configFunc or "")
        .. (useSetupFunc and setupFunc or "")
        .. (useOptsFunc and optsFunc or "")
        .. "return " .. compile(specPlugins, 0, 80 - 7)

    writeFile(transpiledFile, compiled)

    return {
        colorRtp = colorRtp
    }
end

return compilePlugins
