local compiled = table.concat({
    vim.fn.stdpath("data"), "lazier", "lazier_compiled.lua"
}, vim.fn.has('macunix') == 1 and "/" or "\\")

if not (vim.uv or vim.loop).fs_stat(compiled) then
    require("lazier.compile_lazier")()
end

loadfile(compiled, "b")()

return require("lazier.main")
