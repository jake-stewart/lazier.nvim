local fs = require "lazier.util.fs"

--- @param path string
local function iter_module(module, path, lookup)
    if fs.stat(path .. ".lua") then
        lookup[module] = path .. ".lua"
    end
    for name, type in fs.scan_directory(path, true) do
        if name == "init.lua" then
            lookup[module] = fs.join(path, name)
            -- pass
        elseif type == "file" then
            if vim.endswith(name, ".lua") then
                local module_name = (module and module .. "." or "")
                    .. name:sub(1, #name - 4)
                lookup[module_name] = fs.join(path, name)
            end
        elseif type == "directory" then
            iter_module(
                (module and module .. "." or "") .. name,
                fs.join(path, name),
                lookup
            )
        end
    end
    return lookup
end

local M = {}

function M.bundle(opts)
    --- @type any
    local rtp = vim.opt.rtp:get()

    local modules = {}

    opts.modules = opts.modules or {}
    opts.paths = opts.paths or {}
    opts.custom_modules = opts.custom_modules or {}

    for _, module in ipairs(opts.modules) do
        if type(module) == "string" then
            module = { module, recursive = false }
        end
        local components = vim.split(module[1], ".", { plain = true })

        local module_path
        for _, path in ipairs(rtp) do
            local candidates = {
                {
                    type = "file",
                    path = fs.join(path, "lua", components) .. ".lua",
                },
                {
                    type = "file",
                    path = fs.join(path, "lua", components, "init.lua"),
                },
                module.recursive
                    and {
                        type = "directory",
                        path = fs.join(path, "lua", components),
                    }
                    or nil,
            }
            for _, candidate in ipairs(candidates) do
                local stat = fs.stat(candidate.path)
                if stat and stat.type == candidate.type then
                    if stat.type == "file" then
                        modules[module[1]] = candidate.path
                    end
                    module_path = fs.join(path, "lua", components)
                    break
                end
            end
            if module_path then
                break
            end
        end
        if not module_path then
            -- can't hurt to ignore this
            -- since missing modules will requried normally
        elseif module.recursive then
            iter_module(module[1], module_path, modules)
        end
    end
    for _, path in ipairs(opts.paths) do
        iter_module(nil, path, modules)
    end

    for _, path in ipairs(opts.paths) do
        iter_module(nil, path, modules)
    end

    local module_keys = {}
    for module_name in pairs(modules) do
        if not opts.filter or opts.filter[module_name] then
            table.insert(module_keys, module_name)
        end
    end
    table.sort(module_keys)

    local buffer = {}
    for _, module_name in ipairs(module_keys) do
        local path = modules[module_name]
        local content = fs.read_file(path)
        table.insert(buffer, "package.preload[\"" .. module_name .. "\"] = function(...)")
        table.insert(buffer, content)
        table.insert(buffer, "end")
    end

    local custom_module_keys = {}
    for module_name in pairs(opts.custom_modules) do
        table.insert(custom_module_keys, module_name)
    end
    table.sort(custom_module_keys)
    for _, module_name in ipairs(custom_module_keys) do
        table.insert(buffer, "package.preload[\"" .. module_name .. "\"] = function(...)")
        table.insert(buffer, opts.custom_modules[module_name])
        table.insert(buffer, "end")
    end

    return table.concat(buffer, "\n")
end

return M
