local state = require "lazier"

--- @type any
local uv = vim.uv or vim.loop

local function readFile(path)
    local fd = assert(uv.fs_open(path, "r", 438))
    local stat = assert(uv.fs_fstat(fd))
    local data = assert(uv.fs_read(fd, stat.size))
    assert(uv.fs_close(fd))
    return data
end

local function writeFile(path, data)
    local fd = assert(uv.fs_open(path, "w", 438))
    assert(uv.fs_write(fd, data))
    assert(uv.fs_close(fd))
end

local function fileExists(path)
    return uv.fs_stat(path)
end

local function mkdir(path)
    return uv.fs_mkdir(path, 511)
end

local function checkDirModified(root, modifiedSince)
    local handle = assert(uv.fs_scandir(root))
    local modified = false
    local tally = 0

    while true do
        local name, type = uv.fs_scandir_next(handle)
        if not name then
            return modified, tally
        end
        tally = tally + 1
        local path = root .. "/" .. name

        if type == "file" and name:match("%.lua$") then
            local stat = assert(uv.fs_stat(path))
            if stat.mtime.sec > modifiedSince
                or stat.ctime.sec > modifiedSince
            then
                modified = true
            end
        end
    end
end

local function checkCache(cacheFile, sourcePath, transpiledFile)
    local recompile = false
    local lastModified = 0
    local lastTally = 0
    local cache
    local success, contents = pcall(readFile, cacheFile)
    if not success or not fileExists(transpiledFile) then
        recompile = true
    else
        cache = vim.json.decode(contents)
        if not cache then
            recompile = true
        else
            lastModified = cache.modified
            lastTally = cache.tally
        end
    end

    local modified, tally = checkDirModified(sourcePath, lastModified)
    recompile = recompile or modified or tally ~= lastTally
    local timestamp = tonumber(vim.fn.strftime('%s'))
    cache = {
        modified = timestamp,
        colorscheme = cache
            and cache.colorscheme
            or vim.g.colors_name,
        colorRtp = cache and cache.colorRtp,
        tally = tally,
    }
    return recompile, cache
end

local function ensureDirExists(path)
    if not fileExists(path) then
        assert(mkdir(path))
    end
end


return function(module, opts)
    opts = opts or {}
    opts.lazier = opts.lazier or {}

    local function start_lazily()
        if type(opts.lazier.start_lazily) == "function" then
            return opts.lazier.start_lazily()
        elseif opts.lazier.start_lazily == nil then
            local nonLazyLoadableExtensions = {
                zip = true,
                tar = true,
                gz = true
            }
            local fname = vim.fn.expand("%")
            return fname == ""
                or vim.fn.isdirectory(fname) == 0
                and not nonLazyLoadableExtensions[vim.fn.fnamemodify(fname, ":e")]
        else
            return opts.lazier.start_lazily
        end
    end

    local separator = vim.fn.has('macunix') == 1 and "/" or "\\"
    local dataDir = table.concat({ vim.fn.stdpath("data"), "lazier" }, separator)
    ensureDirExists(dataDir)
    local transpiledFile = table.concat({ dataDir, "transpiled.lua" }, separator)
    local cacheFile = table.concat({ dataDir, "cache.json" }, separator)
    local modulePath = module:gsub("%.", separator)
    local sourcePath = table.concat({ vim.fn.stdpath("config"), "lua", modulePath }, separator)
    local modified, cache = checkCache(cacheFile, sourcePath, transpiledFile)
    if modified then
        require("lazy").setup(module, opts)
        local result = require("lazier.compile")(module, transpiledFile)
        if opts.lazier.after then
            opts.lazier.after()
        end
        cache.colorscheme = vim.g.colors_name
        cache.colorRtp = result.colorRtp
        writeFile(cacheFile, vim.json.encode(cache))
        return
    end

    state.compiled = true

    if start_lazily() then
        local loadplugins = vim.o.loadplugins
        vim.o.loadplugins = false
        if cache.colorRtp then
            vim.opt.rtp:append(cache.colorRtp)
            vim.cmd.colorscheme(cache.colorscheme)
        end
        vim.schedule(function()
            vim.o.loadplugins = loadplugins
            require("lazy").setup(loadfile(transpiledFile)(), opts)
            if opts.lazier.after then
                opts.lazier.after()
            end
            if vim.g.colors_name ~= cache.colorscheme then
                local result = require("lazier.compile")(module, transpiledFile)
                cache.colorscheme = vim.g.colors_name
                cache.colorRtp = result.colorRtp
                writeFile(cacheFile, vim.json.encode(cache))
            end
            if vim.o.ft ~= "" then
                vim.cmd.setf(vim.o.ft)
            end
        end)
    else
        require("lazy").setup(loadfile(transpiledFile)(), opts)
        if opts.lazier.after then
            opts.lazier.after()
        end
        if vim.g.colors_name ~= cache.colorscheme then
            local result = require("lazier.compile")(module, transpiledFile)
            cache.colorscheme = vim.g.colors_name
            cache.colorRtp = result.colorRtp
            writeFile(cacheFile, vim.json.encode(cache))
        end
    end

end

