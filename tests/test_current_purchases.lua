return function(test)
    local file = assert(io.open("Core/Module/AuctionLog.lua", "rb"))
    local source = file:read("*a")
    file:close()

    test.eq(source:find('L["我买的"]', 1, true) ~= nil, true,
        "current purchase view retains the original My Purchases filter")
    test.eq(source:find("LogFilter.include(v, BiaoGe.options.auctionLogChoose, BG.playerName, realmName", 1, true) ~= nil, true,
        "current purchase view uses the identity-aware tested filter")
    test.eq(source:find("BiaoGe.playerInfo[RealmID]", 1, true) ~= nil, true,
        "current purchase view retains the existing same-realm own-character scope")
    test.eq(source:find("BiaoGe[FB].auctionLog", 1, true) ~= nil, true,
        "current purchase view reads the current table auction log")
    test.eq(source:find("BiaoGe.History", 1, true), nil,
        "BGLite current purchase view does not read cross-raid history")
end
