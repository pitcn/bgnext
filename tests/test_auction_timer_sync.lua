return function(test)
    BG = { BGNext = {} }
    local loaded, sync = pcall(dofile, "Core/BGNext/AuctionTimerSync.lua")
    test.eq(loaded, true, "auction timer synchronizer loads")
    if not loaded then return end

    local bidFrame = { itemID = 1001, isGen2 = true }
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

    -- Legacy starts identify bids by auctionID and older compatible clients do
    -- not refresh sibling copies of the same item. BGNext must not invent a
    -- local-only shared deadline or the two clients visibly diverge.
    local legacyBid = { itemID = 1001, auctionID = 11, isGen2 = false }
    local legacySibling = { itemID = 1001, auctionID = 12, isGen2 = false }
    refreshed = {}
    count = sync.refreshMatching({ legacyBid, legacySibling }, legacyBid, function(frame)
        refreshed[frame] = (refreshed[frame] or 0) + 1
    end)
    test.eq(count, 1, "a legacy bid refreshes only its auctionID frame")
    test.eq(refreshed[legacyBid], 1, "the legacy bid card receives its extension")
    test.eq(refreshed[legacySibling], nil, "a same-item legacy sibling keeps its own deadline")
end
