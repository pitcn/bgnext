BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

local function isFrameObject(value)
    local kind = type(value)
    return kind == "table" or kind == "userdata"
end

-- Gen2 explicitly gives duplicate copies of the same item a shared visible
-- deadline. Legacy clients identify the bid only by auctionID and refresh just
-- that card, so BGNext must do the same or mixed clients visibly diverge.
function M.refreshMatching(frames, bidFrame, refresh)
    if type(frames) ~= "table" or not isFrameObject(bidFrame) or type(refresh) ~= "function"
        or type(bidFrame.itemID) ~= "number" then
        return 0
    end
    if bidFrame.isGen2 ~= true then
        refresh(bidFrame)
        return 1
    end
    local count = 0
    for _, frame in pairs(frames) do
        if isFrameObject(frame) and frame.itemID == bidFrame.itemID then
            refresh(frame)
            count = count + 1
        end
    end
    return count
end

BG.BGNext.AuctionTimerSync = M
return M
