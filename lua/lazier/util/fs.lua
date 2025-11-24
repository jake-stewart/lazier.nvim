table.unpack = table.unpack or unpack

--- @type any
local uv = vim.uv or vim.loop

local M = {}

function M.write_file(path, data)
    local fd = assert(uv.fs_open(path, "w", 438))
    assert(uv.fs_write(fd, data))
    assert(uv.fs_close(fd))
end

function M.read_file(path)
    local fd = assert(uv.fs_open(path, "r", 438))
    local stat = assert(uv.fs_fstat(fd))
    local data = assert(uv.fs_read(fd, stat.size))
    assert(uv.fs_close(fd))
    return data
end

function M.delete_file(path)
    assert(uv.fs_unlink(path))
end

function M.stat(path)
    return uv.fs_stat(path)
end

function M.create_directory(path)
    assert(uv.fs_mkdir(path, 511))
end

local separator = vim.fn.has('win32') == 1 and "\\" or "/"

function M.join(...)
    return table.concat(vim.tbl_map(function(item)
        if type(item) == "table" then
            return M.join(table.unpack(item))
        else
            return item
        end
    end, {...}), separator)
end

function M.scan_directory(path, allow_empty)
    local handle = uv.fs_scandir(path)
    if allow_empty and not handle then
        return function() end
    end
    assert(handle)
    return function()
        return uv.fs_scandir_next(handle)
    end
end

return M
