local fs = require "lazier.util.fs"

local data_dir = fs.join(vim.fn.stdpath("data"), "lazier")

return {
    data_dir = data_dir,
    lazier_compiled_path = fs.join(data_dir, "lazier_compiled.lua"),
    lazier_bundle_path = fs.join(data_dir, "lazier_bundle.lua"),
    repo_locations = {
        fs.join(data_dir, "lazier.nvim"),
        fs.join(vim.fn.stdpath("data"), "lazier.nvim")
    },
    user_bundle_path = fs.join(data_dir, "bundle.lua"),
    user_compiled_path = fs.join(data_dir, "compiled.lua"),
    cache_path = fs.join(data_dir, "cache.json")
}
