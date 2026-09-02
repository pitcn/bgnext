-- Small event-burst coordinator shared by BGNext and reviewed BGLite UI hooks.
-- It holds no player data: while a callback is pending, repeated triggers are
-- collapsed into that one callback.

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

function M.debounce(after, delay, callback)
    if type(after) ~= "function" or type(callback) ~= "function" then return nil end
    local pending = false
    return function()
        if pending then return end
        pending = true
        after(delay, function()
            pending = false
            callback()
        end)
    end
end

BG.BGNext.EventRefresh = M
return M
