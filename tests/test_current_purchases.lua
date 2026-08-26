return function(test)
    local file = assert(io.open("Core/Module/AuctionLog.lua", "rb"))
    local source = file:read("*a")
    file:close()

    test.eq(source:find('L["我买的"]', 1, true) ~= nil, true,
        "current purchase view retains the original My Purchases filter")
    test.eq(source:find("IsMyPlayer(v.maijia)", 1, true) ~= nil, true,
        "current purchase view includes only the player's own characters")
    test.eq(source:find("BiaoGe[FB].auctionLog", 1, true) ~= nil, true,
        "current purchase view reads the current table auction log")
    test.eq(source:find("BiaoGe.History", 1, true), nil,
        "BGLite current purchase view does not read cross-raid history")
end
