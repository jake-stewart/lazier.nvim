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

local function checkModifiedFile(file, modifiedSince)
    local stat = uv.fs_stat(file)
    if stat.type == "file" then
        if stat.mtime.sec > modifiedSince
            or stat.ctime.sec > modifiedSince
        then
            return true, 1
        end
        return false, 1
    end
    return false, 0
end

local function checkModifiedTree(root, modifiedSince)
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
        elseif type == "directory" then
            local childModified, childTally =
                checkModifiedTree(path, modifiedSince)
            modified = modified or childModified
            tally = tally + childTally
        end
    end
end

local function checkCache(cacheFile, compiledFile)
    local recompile = false
    local lastModified = 0
    local lastTally = 0
    local cache
    local success, contents = pcall(readFile, cacheFile)
    if not success or not fileExists(compiledFile) then
        recompile = true
    else
        cache = vim.json.decode(contents)
        if not cache then
            recompile = true
        else
            lastModified = cache.modified
            lastTally = cache.tally
        end
        if cache.version ~= vim.v.version then
            recompile = true
        end
    end

    local configDir = vim.fn.stdpath("config")
    local sourcePath = configDir .. "/lua"

    local modified, tally = checkModifiedTree(sourcePath, lastModified)
    for _, file in ipairs({
        "lazy-lock.json"
    }) do
        local fileModified, fileTally =
            checkModifiedFile(configDir .. "/" .. file, lastModified)
        modified = modified or fileModified
        tally = tally + fileTally
    end

    recompile = recompile or modified or tally ~= lastTally
    local timestamp = tonumber(vim.fn.strftime('%s'))
    cache = {
        modified = timestamp,
        colorscheme = cache
            and cache.colorscheme
            or vim.g.colors_name,
        colorRtp = cache and cache.colorRtp,
        bundle_plugins = cache and cache.bundle_plugins,
        tally = tally,
        version = vim.v.version
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
    opts.lazier.bundle_plugins = opts.lazier.bundle_plugins or false

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
    local compiledFile = table.concat({ dataDir, "compiled.lua" }, separator)
    local cacheFile = table.concat({ dataDir, "cache.json" }, separator)
    local modified, cache = checkCache(cacheFile, compiledFile)
    if modified or cache.bundle_plugins ~= opts.lazier.bundle_plugins then
        if opts.lazier.before then
            opts.lazier.before()
        end
        require("lazy").setup(module, opts)
        local result = require("lazier.compile")(
            module, compiledFile, opts.lazier.bundle_plugins)
        if opts.lazier.after then
            opts.lazier.after()
        end
        cache.colorscheme = vim.g.colors_name
        cache.colorRtp = result.colorRtp
        cache.bundle_plugins = opts.lazier.bundle_plugins
        writeFile(cacheFile, vim.json.encode(cache))
        return
    end

    state.compiled = true

    loadfile(compiledFile, "b")()
    if opts.lazier.before then
        opts.lazier.before()
    end

    if start_lazily() then
        local loadplugins = vim.o.loadplugins
        vim.o.loadplugins = false
        if cache.colorRtp then
            vim.opt.rtp:append(cache.colorRtp)
            vim.cmd.colorscheme(cache.colorscheme)
        end

        vim.schedule(function()
            vim.o.loadplugins = loadplugins
            require("lazy").setup(require("lazierbundle"), opts)
            if opts.lazier.after then
                opts.lazier.after()
            end

            if vim.g.colors_name ~= cache.colorscheme then
                local result = require("lazier.compile")(
                    module, compiledFile, opts.lazier.bundle_plugins)
                cache.colorscheme = vim.g.colors_name
                cache.colorRtp = result.colorRtp
                cache.bundle_plugins = opts.lazier.bundle_plugins
                writeFile(cacheFile, vim.json.encode(cache))
            end
            if vim.o.ft ~= "" then
                vim.cmd.setf(vim.o.ft)
            end
        end)
    else
        require("lazy").setup(require("lazierbundle"), opts)
        if opts.lazier.after then
            opts.lazier.after()
        end
        if vim.g.colors_name ~= cache.colorscheme then
            local result = require("lazier.compile")(
                module, compiledFile, opts.lazier.bundle_plugins)
            cache.colorscheme = vim.g.colors_name
            cache.colorRtp = result.colorRtp
            cache.bundle_plugins = opts.lazier.bundle_plugins
            writeFile(cacheFile, vim.json.encode(cache))
        end
    end

end

