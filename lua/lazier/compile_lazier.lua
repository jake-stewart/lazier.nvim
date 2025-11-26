local bundler = require "lazier.util.bundler"
local compiler = require "lazier.util.compiler"
local constants = require "lazier.constants"

compiler.try_compile(
    bundler.bundle({
        modules = {{ "lazier", recursive = true }}
    }),
    constants.lazier_bundle_path,
    constants.lazier_compiled_path
)
