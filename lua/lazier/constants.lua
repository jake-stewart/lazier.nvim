local sep = vim.fn.has('win32') == 1 and "\\" or "/"

local data_dir = vim.fn.stdpath("data") .. sep .. "lazier"

return {
    data_dir = data_dir,
    lazier_compiled_path = data_dir .. sep .. "lazier_compiled.lua",
    lazier_bundle_path = data_dir .. sep .. "lazier_bundle.lua",
    repo_dir = data_dir .. sep .. "lazier.nvim",
    user_bundle_path = data_dir .. sep .. "bundle.lua",
    user_compiled_path = data_dir .. sep .. "compiled.lua",
    cache_path = data_dir .. sep .. "cache.json"
}
