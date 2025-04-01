--- @type any
local uv = vim.loop or vim.uv

local separator = vim.fn.has('macunix') == 1 and "/" or "\\"
table.unpack = table.unpack or unpack

local function readFile(path)
    local fd = assert(uv.fs_open(path, "r", 438))
    local stat = assert(uv.fs_fstat(fd))
    local data = assert(uv.fs_read(fd, stat.size))
    assert(uv.fs_close(fd))
    return data
end

local function join(...)
    return table.concat(vim.tbl_map(function(item)
        if type(item) == "table" then
            return join(table.unpack(item))
        else
            return item
        end
    end, {...}), separator)
end

--- @param path string
local function iter_module(module, path, lookup)
    if uv.fs_lstat(path .. ".lua") then
        lookup[module] = path .. ".lua"
    end
    local scanner, err = uv.fs_scandir(path)
    if err then
        return lookup
    end
    while true do
        local name, type = uv.fs_scandir_next(scanner)
        if not name then
            return lookup
        end
        if name == "init.lua" then
            -- pass
        elseif type == "file" then
            if vim.endswith(name, ".lua") then
                local moduleName = (module and module .. "." or "") .. name:sub(1, #name - 4)
                lookup[moduleName] = join(path, name)
            end
        elseif type == "directory" then
            iter_module(
                (module and module .. "." or "") .. name,
                join(path, name),
                lookup
            )
        end
    end
end

local function bundle(opts)
    local rtp = vim.opt.rtp:get() --[[ @as string[] ]]

    local modules = {}

    for _, module in ipairs(opts.modules) do
        if type(module) == "string" then
            module = { module, recursive = false }
        end
        local components = vim.split(module[1], ".", { plain = true })

        local modulePath
        for _, path in ipairs(rtp) do
            local candidates = {
                { type = "file", path = join(path, "lua", join(components) .. ".lua") },
                { type = "file", path = join(path, "lua", join(components) .. "/init.lua") },
                module.recursive
                    and { type = "directory", path = join(path, "lua", join(components)) }
                    or nil,
            }
            for _, candidate in ipairs(candidates) do
                local stat = uv.fs_stat(candidate.path)
                if stat and stat.type == candidate.type then
                    if stat.type == "file" then
                        modules[module[1]] = candidate.path
                    end
                    modulePath = join(path, "lua", join(components))
                    break
                end
            end
            if modulePath then
                break
            end
        end
        if not modulePath then
            error("could not find " .. module[1])
        end
        if module.recursive then
            iter_module(module[1], modulePath, modules)
        end
    end
    for _, path in ipairs(opts.paths) do
        iter_module(nil, path, modules)
    end

    local buffer = {}
    for moduleName, path in pairs(modules) do
        local content = readFile(path)
        table.insert(buffer, "package.preload[\"" .. moduleName .. "\"] = function(...)")
        table.insert(buffer, content)
        table.insert(buffer, "end")
    end
    if opts.custom_modules then
        for customModule, code in pairs(opts.custom_modules) do
            table.insert(buffer, "package.preload[\"" .. customModule .. "\"] = function(...)")
            table.insert(buffer, code)
            table.insert(buffer, "end")
        end
    end
    return table.concat(buffer, "\n")
end

return bundle
