BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

function M.new(cooldown)
    local lastAllowed
    return {
        allow = function(now)
            if type(now) ~= "number" then return true end
            if lastAllowed == nil or now < lastAllowed or now - lastAllowed >= cooldown then
                lastAllowed = now
                return true
            end
            return false
        end,
        reset = function()
            lastAllowed = nil
        end,
    }
end

BG.BGNext.AlertThrottle = M
return M
