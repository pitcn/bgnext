return function(test)
    BG = { BGNext = {} }
    dofile("Core/BGNext/PlayerIdentity.lua")
    local TradeAuctionState = dofile("Core/BGNext/TradeAuctionState.lua")
    local function itemId(link)
        return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
    end

    local records = {
        { type = 1, maijia = "Alice-MyRealm", zhuangbei = "item:1001" },
        { type = 1, maijia = "Bob-MyRealm", zhuangbei = "item:1001" },
    }
    local changed = TradeAuctionState.markDelivered(records, "Alice", "My Realm", {
        { link = "item:1001", count = 1 },
    }, itemId)

    test.eq(changed, 1, "a completed local-realm trade matches short and full buyer names")
    test.eq(records[1].trade, true, "the matching buyer's auction is marked delivered")
    test.eq(records[2].trade, nil, "another buyer's auction remains untraded")

    local duplicateRecords = {
        { type = 1, maijia = "Alice-MyRealm", zhuangbei = "item:2002" },
        { type = 1, maijia = "Alice-MyRealm", zhuangbei = "item:2002" },
        { type = 1, maijia = "Alice-MyRealm", zhuangbei = "item:2002" },
    }
    changed = TradeAuctionState.markDelivered(duplicateRecords, "Alice", "My Realm", {
        { link = "item:2002", count = 2 },
    }, itemId)
    test.eq(changed, 2, "a stacked trade marks exactly the delivered number of identical auctions")
    test.eq(duplicateRecords[1].trade, true, "the first delivered copy is marked")
    test.eq(duplicateRecords[2].trade, true, "the second delivered copy is marked")
    test.eq(duplicateRecords[3].trade, nil, "an undelivered identical copy remains untraded")

    local remoteRecord = {
        { type = 1, maijia = "Alice-OtherRealm", zhuangbei = "item:3003" },
        { type = 1, maijia = "Alice-MyRealm", zhuangbei = "item:3003", trade = true },
    }
    changed = TradeAuctionState.markDelivered(remoteRecord, "Alice", "My Realm", {
        { link = "item:3003", count = 1 },
    }, itemId)
    test.eq(changed, 0, "a local trade never marks a remote same-name buyer or recounts delivered records")
    test.eq(remoteRecord[1].trade, nil, "the remote same-name buyer remains untraded")

    local atomicRecords = {
        { type = 1, maijia = "Alice-MyRealm", zhuangbei = "item:4004" },
    }
    changed = TradeAuctionState.markDelivered(atomicRecords, "Alice", "My Realm", {
        { link = "item:4004", count = 1 },
        { link = "item:5005" },
    }, itemId)
    test.eq(changed, 0, "a partly malformed trade snapshot is rejected atomically")
    test.eq(atomicRecords[1].trade, nil, "validation finishes before any auction record is mutated")

    changed = TradeAuctionState.markDelivered({ atomicRecords[1], false }, "Alice", "My Realm", {
        { link = "item:4004", count = 1 },
    }, itemId)
    test.eq(changed, 0, "a malformed auction record rejects the update without a partial mutation")
    test.eq(atomicRecords[1].trade, nil, "malformed saved data leaves earlier valid records unchanged")

    local strictItemId = function(link)
        return tonumber(link:match("item:(%d+)"))
    end
    local ok, malformedLinkChanged = pcall(TradeAuctionState.markDelivered, atomicRecords,
        "Alice", "My Realm", { { link = true, count = 1 } }, strictItemId)
    test.eq(ok, true, "a malformed trade link never reaches the runtime item parser")
    test.eq(malformedLinkChanged, 0, "a malformed trade link rejects the whole update")

    local malformedMatchingRecords = {
        atomicRecords[1],
        { type = 1, maijia = "Alice-MyRealm" },
    }
    changed = TradeAuctionState.markDelivered(malformedMatchingRecords, "Alice", "My Realm", {
        { link = "item:4004", count = 1 },
    }, itemId)
    test.eq(changed, 0, "a malformed matching auction record rejects the whole update")
    test.eq(atomicRecords[1].trade, nil, "all matching records validate before any delivery state is committed")

    local tocHandle = assert(io.open("BGLite.toc", "r"))
    local toc = tocHandle:read("*a")
    tocHandle:close()
    local tradeHandle = assert(io.open("Core/Module/Trade.lua", "r"))
    local tradeSource = tradeHandle:read("*a")
    tradeHandle:close()
    local statePos = toc:find("Core\\BGNext\\TradeAuctionState.lua", 1, true)
    local tradePos = toc:find("Core\\Module\\Trade.lua", 1, true)
    test.eq(statePos ~= nil and tradePos ~= nil and statePos < tradePos, true,
        "the trade auction state module loads before the trade runtime")
    test.eq(tradeSource:find("TradeAuctionState.markDelivered", 1, true) ~= nil, true,
        "the completed-trade runtime delegates auction-state updates to the identity-safe helper")
    test.eq(tradeSource:find("v.maijia == tradeName", 1, true), nil,
        "the completed-trade runtime no longer compares raw buyer names")
end
