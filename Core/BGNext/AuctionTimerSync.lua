BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

-- A bid belongs to one auction id, but duplicate copies of the same item share
-- the visible deadline. The supplied refresh function remains responsible for
-- ignoring ended or paused frames.
function M.refreshMatching(frames, bidFrame, refresh)
    if type(frames) ~= "table" or type(bidFrame) ~= "table" or type(refresh) ~= "function"
        or type(bidFrame.itemID) ~= "number" then
        return 0
    end
    local count = 0
    for _, frame in pairs(frames) do
        if type(frame) == "table" and frame.itemID == bidFrame.itemID then
            refresh(frame)
            count = count + 1
        end
    end
    return count
end

BG.BGNext.AuctionTimerSync = M
return M
