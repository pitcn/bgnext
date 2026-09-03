return function(test)
    BG = { BGNext = {} }
    local loaded, sync = pcall(dofile, "Core/BGNext/AuctionTimerSync.lua")
    test.eq(loaded, true, "auction timer synchronizer loads")
    if not loaded then return end

    local bidFrame = { itemID = 1001 }
    local sameAbove = { itemID = 1001 }
    local sameBelow = { itemID = 1001 }
    local different = { itemID = 1002 }
    local refreshed = {}
    local count = sync.refreshMatching({ sameAbove, bidFrame, different, sameBelow }, bidFrame, function(frame)
        refreshed[frame] = (refreshed[frame] or 0) + 1
    end)

    test.eq(count, 3, "a bid refreshes every active frame for the same item")
    test.eq(refreshed[bidFrame], 1, "the frame receiving the bid refreshes once")
    test.eq(refreshed[sameAbove], 1, "the same item above refreshes")
    test.eq(refreshed[sameBelow], 1, "the same item below refreshes")
    test.eq(refreshed[different], nil, "a different item keeps its own deadline")
end
