--- @type any
local uv = vim.uv or vim.loop

local function writeFile(path, data)
    local fd = assert(uv.fs_open(path, "w", 438))
    assert(uv.fs_write(fd, data))
    assert(uv.fs_close(fd))
end

local function deleteFile(path)
    assert(uv.fs_unlink(path))
end

return function(path)
    local bundle = require("lazier.bundle")({
        modules = {
            "lazier.setup",
            "lazier.wrap",
            "lazier.mimic",
            "lazier.recorder",
            "lazier.compile",
            "lazier.bundle",
            "lazier.version",
            "lazier.npack",
        },
        customModules = {},
        paths = {}
    })
    writeFile(path, bundle)
    local chunk, err = loadfile(path, "t", {})
    if chunk then
        writeFile(path, string.dump(chunk))
    else
        deleteFile(path)
        error("failed to compile bytecode: " .. tostring(err))
    end
end
