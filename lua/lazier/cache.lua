local fs = require "lazier.util.fs"
local constants = require "lazier.constants"

local function remove_files_in_directory(directory, allow_empty)
    for name, type in fs.scan_directory(directory, allow_empty) do
        if type == 'file' then
            fs.delete_file(fs.join(directory, name))
        end
    end
end

local M = {}

function M.clear()
    remove_files_in_directory(constants.data_dir, true)
end

return M
