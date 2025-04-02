local bundler = require "lazier.util.bundler"
local compiler = require "lazier.util.compiler"
local constants = require "lazier.constants"

local function compile_lazier()
    compiler.try_compile(
        bundler.bundle({
            modules = {{ "lazier", recursive = true }}
        }),
        constants.lazier_bundle_path,
        constants.lazier_compiled_path
    )
end

return compile_lazier
