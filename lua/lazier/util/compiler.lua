local fs = require "lazier.util.fs"

local M = {}

function M.try_compile(code, bundled_file, compiled_file)
    local _, err = pcall(function()
        local parent = vim.fn.fnamemodify(bundled_file, ":h")
        if not fs.stat(parent) then
            fs.create_directory(vim.fn.fnamemodify(bundled_file, ":h"))
        end
        fs.write_file(bundled_file, code)
        local chunk, err = loadfile(bundled_file, "t", {})
        if not chunk then
            error(err)
        end
        fs.write_file(compiled_file, string.dump(chunk))
    end)

    if err then
        vim.api.nvim_echo({
            {"lazier.nvim: failed to compile bytecode\n", "Error"},
            {tostring(err), "WarningMsg"}
        }, true, {})
    end
end

return M
