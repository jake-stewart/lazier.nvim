local util = require("lazy.core.util")

local function merge_opts(opts, values, extend)
    local lists = {}
    for _, key in ipairs(extend or {}) do
        local path = vim.split(key, ".", { plain = true })
        local list = util.key_get(opts, path)
        local value = util.key_get(values, path)
        if type(list) == "table" and type(value) == "table" then
            lists[key] = { path = path, list = {} }
            vim.list_extend(lists[key].list, list)
            vim.list_extend(lists[key].list, value)
        end
    end
    local merged = util.merge(opts, values)
    for _, list in pairs(lists) do
        util.key_set(merged, list.path, list.list)
    end
    return merged
end

return merge_opts
