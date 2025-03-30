--- @diagnostic disable-next-line
table.unpack = table.unpack or unpack

--- @alias NPacked<T> { [integer]: T, n: integer }

local M = {}

--- @return NPacked<any>
function M.pack(...)
    return { n = select("#", ...), ... }
end

--- @param t NPacked<any>
function M.unpack(t)
    return table.unpack(t, 1, t.n)
end

return M
