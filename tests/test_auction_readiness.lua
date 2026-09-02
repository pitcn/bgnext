return function(test)
    BG = { BGNext = {} }
    local Readiness = dofile("Core/BGNext/AuctionReadiness.lua")

    local roster = {
        { name = "Leader", online = true },
        { name = "AddonOnly", online = true },
        { name = "Silent", online = true },
        { name = "Offline", online = false },
    }
    local addonVersions = {
        Leader = "2.4.0",
        AddonOnly = "2.3.5",
        StalePlayer = "2.4.0",
    }
    local auctionVersions = {
        Leader = "v4.0",
        Offline = "v4.0",
        StalePlayer = "v4.0",
    }
    local compatibleAddonVersions = {
        Leader = true,
        StalePlayer = true,
    }

    test.eq(Readiness.status(roster[1], addonVersions, auctionVersions), Readiness.READY,
        "an auction endpoint response proves readiness")
    test.eq(Readiness.status(roster[2], addonVersions, auctionVersions), Readiness.ADDON_ONLY,
        "an addon response alone does not prove auction readiness")
    test.eq(Readiness.status(roster[3], addonVersions, auctionVersions), Readiness.NO_RESPONSE,
        "an online member without a response stays unconfirmed")
    test.eq(Readiness.status(roster[4], addonVersions, auctionVersions), Readiness.OFFLINE,
        "offline status takes precedence over a stale response")

    local ready, total = Readiness.summarize(roster, addonVersions, auctionVersions)
    test.eq(ready, 1, "only auction endpoint responses count as ready")
    test.eq(total, 4, "the summary includes every current raid member")

    local soloView = Readiness.footerView(false, roster, addonVersions, auctionVersions)
    test.eq(soloView.mode, "solo", "the readiness entry remains discoverable while solo")
    local raidView = Readiness.footerView(true, roster, addonVersions, auctionVersions)
    test.eq(raidView.mode, "raid", "the readiness entry switches to raid status in a raid")
    test.eq(raidView.ready, 1, "raid footer view carries the ready count")
    test.eq(raidView.total, 4, "raid footer view carries the roster total")

    Readiness.prune(addonVersions, auctionVersions, roster, compatibleAddonVersions)
    test.eq(addonVersions.StalePlayer, nil, "addon responses from departed members are discarded")
    test.eq(auctionVersions.StalePlayer, nil, "auction responses from departed members are discarded")
    test.eq(addonVersions.Leader, "2.4.0", "current addon responses are retained")
    test.eq(auctionVersions.Leader, "v4.0", "current auction responses are retained")
    test.eq(compatibleAddonVersions.StalePlayer, nil,
        "derived compatibility state from departed members is discarded")
    test.eq(compatibleAddonVersions.Leader, true, "current derived compatibility state is retained")

    local requestState = {}
    test.eq(Readiness.takeRequest(requestState, 100, true), true,
        "the raid controller may start a readiness request")
    test.eq(Readiness.takeRequest(requestState, 101, true), false,
        "readiness requests are locally rate limited")
    test.eq(Readiness.takeRequest(requestState, 115, true), true,
        "the controller may request again after the cooldown")
    test.eq(Readiness.takeRequest({}, 100, false), false,
        "a regular raid member cannot create an automatic request burst")
    test.eq(Readiness.takeRequest(requestState, 90, true), false,
        "a backwards clock cannot bypass the request cooldown")
    test.eq(Readiness.requestDelay(requestState, 116, true), 14,
        "a roster change can schedule one request for the end of the cooldown")
    test.eq(Readiness.requestDelay(requestState, 130, true), 0,
        "no delay remains when the cooldown has expired")
    test.eq(Readiness.requestDelay(requestState, 116, false), nil,
        "a regular member never schedules an automatic request")
    test.eq(Readiness.requestDelay(requestState, 90, true), nil,
        "a backwards clock does not create a delayed request")

    local source = assert(io.open("Core/Module/Auction.lua", "rb")):read("*a")
    test.eq(source:find('L["团队拍卖：已就绪 %s"]', 1, true) ~= nil, true,
        "the raid footer uses one readiness summary")
    test.eq(source:find('L["团队拍卖：未组团"]', 1, true) ~= nil, true,
        "the solo footer explains why no readiness result is available")
    test.eq(source:find('L["兼容插件版本"]', 1, true), nil,
        "the ambiguous compatibility-version label is removed")
    test.eq(source:find("GetNumGuildMembers", 1, true), nil,
        "guild census work is removed from the auction runtime")
    test.eq(source:find('SendAddonMessage("BiaoGeAuction", "VersionCheck", "RAID")', 1, true) ~= nil, true,
        "readiness requests reuse the existing auction version protocol")
    test.eq(source:find("Readiness.takeRequest", 1, true) ~= nil, true,
        "outgoing readiness requests pass through the local rate limiter")
    test.eq(source:find("Sender.isRaidSender(rawSender, realm, members)", 1, true) ~= nil, true,
        "version responses are accepted only from current raid members")
end
