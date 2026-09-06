BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Pure height calculation for the login update popup. Font strings have
-- already been width-constrained before their measured heights arrive here.
local M = {}

function M.height(textHeights, gap, topPadding, bottomPadding, minimum)
    local heights = type(textHeights) == "table" and textHeights or {}
    local total = math.max(0, tonumber(topPadding) or 0) + math.max(0, tonumber(bottomPadding) or 0)
    local spacing = math.max(0, tonumber(gap) or 0)
    for index, measured in ipairs(heights) do
        if index > 1 then total = total + spacing end
        total = total + math.max(0, tonumber(measured) or 0)
    end
    return math.max(math.max(0, tonumber(minimum) or 0), math.ceil(total))
end

BG.BGNext.UpdateLogLayout = M
return M
