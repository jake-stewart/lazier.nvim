local fs = require "lazier.util.fs"

local function modified_since(stat, timestamp)
    return stat.mtime.sec > timestamp
        or stat.ctime.sec > timestamp
end

local function check_modified_tree(root, timestamp)
    local modified = false
    local tally = 0
    for name, type in fs.scan_directory(root, true) do
        tally = tally + 1
        local path = fs.join(root, name)

        if type == "file" and name:find("%.lua$") then
            if modified_since(fs.stat(path), timestamp) then
                modified = true
            end
        elseif type == "directory" and not name:find("^%.") then
            local child_modified, child_tally =
                check_modified_tree(path, timestamp)
            modified = modified or child_modified
            tally = tally + child_tally
        end
    end
    return modified, tally
end

local function detect_config_changes(recompile, last_modified, last_tally)
    local config_dir = vim.fn.stdpath("config")
    local source_path = fs.join(config_dir, "lua")
    local modified, tally

    modified, tally = check_modified_tree(source_path, last_modified)
    local extra_files = {
        fs.join(config_dir, "lazy-lock.json")
    }
    for _, file in ipairs(extra_files) do
        local stat = fs.stat(file)
        if stat then
            tally = tally + 1
            if modified_since(stat, last_modified) then
                modified = true
            end
        end
    end
    recompile = recompile or modified or tally ~= last_tally
    return recompile, tally
end

return detect_config_changes
