local M = {}

function M.start_lazily()
    local fs = require "lazier.util.fs"
    local fname = vim.fn.expand("%")
    if fname == "" then
        return true
    end
    local non_lazy_loadable_extensions = {
        zip = true,
        tar = true,
        gz = true
    }
    local stat = fs.stat(fname)
    return not stat
        or stat.type == "file"
        and not non_lazy_loadable_extensions
            [vim.fn.fnamemodify(fname, ":e")]
end

return M
