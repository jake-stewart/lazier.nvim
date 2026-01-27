local sep = vim.fn.has('win32') == 1 and "\\" or "/"
local compiled = vim.fn.stdpath("data") .. sep .. "lazier" .. sep .. "lazier_compiled.lua"

if not vim.uv.fs_stat(compiled) then
    require("lazier.compile_lazier")
end

loadfile(compiled, "b")()

return require("lazier.main")
