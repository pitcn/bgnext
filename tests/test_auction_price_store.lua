return function(test)
    BG = { BGNext = {} }
    local life = dofile("Core/BGNext/DataLifecycle.lua")
    local store = dofile("Core/BGNext/AuctionPriceStore.lua")

    local saved = {}
    local root = life.ensureRoot(saved)

    test.eq(type(root.leaderAuctionPricePresets), "table", "leader price root")
    test.eq(type(root.personalAuctionExpectations), "table", "personal price root")
    test.eq(root.auctionPresets, nil, "retired auto-bid presets stay unread")

    -- Canonical BGNext client-family keys (matches OwnCharactersAdapters.families).
    local expected = {
        vanilla = 100, tbc = 100, wrath = 1000, titan = 100,
        cata = 100000, mop = 10000, retail = 100000,
    }
    for family, money in pairs(expected) do
        test.eq(store.defaultGlobalPrice(family), money, family .. " default")
    end
end
