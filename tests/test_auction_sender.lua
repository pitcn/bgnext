return function(test)
    BG = { BGNext = {} }
    dofile("Core/BGNext/PlayerIdentity.lua")
    local Sender = dofile("Core/BGNext/AuctionSender.lua")

    -- Canonical full names keep cross-realm identities distinct.
    test.eq(Sender.canonical("Alice", "Realm"), "Alice-Realm", "a bare name gains the realm")
    test.eq(Sender.canonical("Alice-Realm", "Realm"), "Alice-Realm", "a full name is kept verbatim")
    test.eq(Sender.canonical("Alice-OtherRealm", "Realm"), "Alice-OtherRealm", "a cross-realm name is kept verbatim")
    test.eq(Sender.canonical("", "Realm"), nil, "an empty name has no identity")
    test.eq(Sender.canonical(nil, "Realm"), nil, "a missing name has no identity")

    -- A bid is accepted only when its sender is a current raid member.
    test.eq(Sender.isRaidSender("Alice", "Realm", { "Alice", "Bob" }), true, "a bare member name is accepted")
    test.eq(Sender.isRaidSender("Alice-Realm", "Realm", { "Alice" }), true, "a full member name is accepted")
    test.eq(Sender.isRaidSender("Alice", "Realm", { "Bob" }), false, "a non-member is ignored")
    test.eq(Sender.isRaidSender("Alice-OtherRealm", "Realm", { "Alice" }), false,
        "same short name on another realm is ignored")
    test.eq(Sender.isRaidSender("Alice-My-Realm", "My Realm", { "Alice" }), true,
        "realm display separators do not reject a real raid member")
    test.eq(Sender.isRaidSender(nil, "Realm", { "Alice" }), false, "a missing sender is ignored")
    test.eq(Sender.isRaidSender("", "Realm", { "Alice" }), false, "an empty sender is ignored")
    test.eq(Sender.isRaidSender("Alice", "Realm", {}), false, "an empty roster accepts no one")

    local roster = {
        { name = "Leader", rank = 2, isML = false },
        { name = "Looter", rank = 0, isML = true },
        { name = "Assistant", rank = 1, isML = false },
        { name = "Member", rank = 0, isML = false },
    }
    test.eq(Sender.isController("Leader", "Realm", roster), true, "the raid leader may control auctions")
    test.eq(Sender.isController("Looter", "Realm", roster), true, "the master looter may control auctions")
    test.eq(Sender.isController("Assistant", "Realm", roster), false, "an assistant may not control auctions")
    test.eq(Sender.isController("Member", "Realm", roster), false, "a regular member may not control auctions")
    test.eq(Sender.isController("Outsider", "Realm", roster), false, "a non-member may not control auctions")
    test.eq(Sender.isController("Leader-OtherRealm", "Realm", roster), false,
        "a same-name player from another realm may not control auctions")

    -- Malformed protocol numbers are rejected before the event handler compares
    -- them with live auction state. A bad compatible client must not be able to
    -- trigger a Lua error on every raid member running BGNext.
    local auctionID, money = Sender.parseBid("42", "500")
    test.eq(auctionID, 42, "a numeric auction id is accepted")
    test.eq(money, 500, "a numeric bid amount is accepted")
    local fractionalBidID = Sender.parseBid("42.5", "500")
    test.eq(fractionalBidID, 42.5, "a bid keeps its GetTime-style fractional auction id")
    test.eq(Sender.parseBid(nil, "500"), nil, "a missing auction id is rejected")
    test.eq(Sender.parseBid("bad", "500"), nil, "a malformed auction id is rejected")
    test.eq(Sender.parseBid("42", nil), nil, "a missing bid amount is rejected")
    test.eq(Sender.parseBid("42", "bad"), nil, "a malformed bid amount is rejected")
    test.eq(Sender.MAX_MONEY, 10000000, "the protocol publishes the supported gold ceiling")
    test.eq(Sender.parseBid("0", "500"), nil, "a non-positive auction id is rejected")
    test.eq(Sender.parseBid("42", "-1"), nil, "a negative bid amount is rejected")
    test.eq(Sender.parseBid("42", "1.5"), nil, "a fractional bid amount is rejected")
    test.eq(Sender.parseBid("42", "1e309"), nil, "an infinite bid amount is rejected")
    test.eq(Sender.parseBid("42", "10000001"), nil, "a bid above the gold ceiling is rejected")

    local startID, itemID, startMoney, duration = Sender.parseStart("42", "123", "500", "30")
    test.eq(startID, 42, "a valid start auction id is accepted")
    test.eq(itemID, 123, "a valid item id is accepted")
    test.eq(startMoney, 500, "a valid start price is accepted")
    test.eq(duration, 30, "a valid duration is accepted")
    test.eq(Sender.parseStart("bad", "123", "500", "30"), nil, "a malformed start id is rejected")
    test.eq(Sender.parseStart("42", "0", "500", "30"), nil, "a non-positive item id is rejected")
    test.eq(Sender.parseStart("42", "123", "-1", "30"), nil, "a negative start price is rejected")
    test.eq(Sender.parseStart("42", "123", "500", "0"), nil, "a non-positive duration is rejected")
    test.eq(Sender.parseStart("42", "123", "500", "3601"), nil, "an excessive duration is rejected")
    local fractionalStartID = Sender.parseStart("42.5", "123", "500", "30")
    test.eq(fractionalStartID, 42.5, "GetTime-style fractional auction ids are accepted")
    test.eq(Sender.parseStart("42", "123.5", "500", "30"), nil, "a fractional item id is rejected")
    test.eq(Sender.parseStart("42", "123", "1e309", "30"), nil, "an infinite start price is rejected")
    test.eq(Sender.parseStart("42", "123", "10000001", "30"), nil,
        "a start price above the gold ceiling is rejected")
    test.eq(Sender.parseStart("42", "123", "500", "1.5"), nil, "a fractional duration is rejected")

    local rateState = {}
    local members = { "Alice", "Bob", "Cara", "Dan" }
    test.eq(Sender.shouldRespondVersion(rateState, "Alice", "Realm", members, 100), true,
        "the first request from a raid member receives a response")
    test.eq(Sender.shouldRespondVersion(rateState, "Alice", "Realm", members, 101), false,
        "a sender cannot trigger another immediate response")
    test.eq(Sender.shouldRespondVersion(rateState, "Bob", "Realm", members, 102), true,
        "another raid member may request a response")
    test.eq(Sender.shouldRespondVersion(rateState, "Cara", "Realm", members, 103), true,
        "the global window permits a bounded third response")
    test.eq(Sender.shouldRespondVersion(rateState, "Dan", "Realm", members, 104), false,
        "the global response limit prevents amplification")
    test.eq(Sender.shouldRespondVersion(rateState, "Outsider", "Realm", members, 120), false,
        "a non-member cannot trigger a version response")
    test.eq(Sender.shouldRespondVersion(rateState, "Alice", "Realm", members, 131), true,
        "a member may request again after the sender cooldown")

    local bidRateState = {}
    test.eq(Sender.shouldAcceptAuctionMessage(bidRateState, "Alice", "Realm", members, 42, 200, 1), true,
        "the first auction message is accepted")
    test.eq(Sender.shouldAcceptAuctionMessage(bidRateState, "Alice", "Realm", members, 42, 200.5, 1), false,
        "the same sender and auction are limited inside the interval")
    test.eq(Sender.shouldAcceptAuctionMessage(bidRateState, "Alice", "Realm", members, 43, 200.5, 1), true,
        "a different auction has an independent limit")
    test.eq(Sender.shouldAcceptAuctionMessage(bidRateState, "Bob", "Realm", members, 42, 200.5, 1), true,
        "a different sender has an independent limit")
    test.eq(Sender.shouldAcceptAuctionMessage(bidRateState, "Alice", "Realm", members, 42, 201, 1), true,
        "the sender may bid again when the interval expires")
    test.eq(Sender.shouldAcceptAuctionMessage(bidRateState, "Alice", "Realm", members, 42, 199, 1), false,
        "a backwards clock does not bypass the limit")
    test.eq(Sender.shouldAcceptAuctionMessage(bidRateState, "Outsider", "Realm", members, 42, 210, 1), false,
        "a non-member cannot allocate rate-limit state")
    test.eq(Sender.shouldAcceptAuctionMessage(bidRateState, "Alice", "Realm", members, 0, 210, 1), false,
        "an invalid auction id cannot allocate rate-limit state")
    test.eq(Sender.shouldAcceptAuctionMessage(bidRateState, "Alice", "Realm", members, 42.5, 210, 1), true,
        "a GetTime-style fractional auction id can allocate rate-limit state")

    -- The event handler must read the bidder from the sender (fourth argument),
    -- never from the target (fifth), and validate it against the current roster.
    local source = assert(io.open("Core/Module/AuctionWAEvent.lua", "rb")):read("*a")
    test.eq(source:find("local prefix, message, distribution, sender, target = ...", 1, true) ~= nil, true,
        "the handler names the fourth and fifth arguments sender and target")
    test.eq(source:find("wa.SetMoney(frame, money, sender)", 1, true) ~= nil, true,
        "the bidder passed to SetMoney is the sender")
    test.eq(source:find("wa.SetMoney(frame, money, line)", 1, true), nil,
        "the target is never passed as the bidder")
    test.eq(source:find("wa.SetMoney(frame, money, target)", 1, true), nil,
        "the target is never passed as the bidder")
    test.eq(source:find("Sender.isRaidSender(sender, realm, members)", 1, true) ~= nil, true,
        "the sender is validated against the current raid roster")
    test.eq(source:find("Sender.parseBid(auctionIDStr, itemIDStr)", 1, true) ~= nil, true,
        "protocol numbers are validated before live auction comparisons")
    test.eq(source:find("Sender.isController(sender, realm, wa.raidRosterInfo)", 1, true) ~= nil, true,
        "auction control messages require the raid leader or master looter")
    test.eq(source:find("Sender.parseStart(auctionIDStr, itemIDStr, moneyStr, durationStr)", 1, true) ~= nil, true,
        "start-auction fields are validated before item loading")
    test.eq(source:find("Sender.shouldRespondVersion(versionResponseState, sender, realm, members, GetTime())", 1, true) ~= nil,
        true, "auction version replies are rate-limited and restricted to raid members")
    test.eq(source:find(
        "Sender.shouldAcceptAuctionMessage(bidRateState, sender, realm, members, auctionID, GetTime(), 1)",
        1, true) ~= nil, true, "live bids are rate-limited per sender and auction")

    local auctionModuleSource = assert(io.open("Core/Module/Auction.lua", "rb")):read("*a")
    test.eq(auctionModuleSource:find(
        "function BG.SendStartAuctionMsg(itemID, money, duration, link)", 1, true) ~= nil, true,
        "the outgoing start boundary exposes only legacy-compatible fields")
    test.eq(auctionModuleSource:find(
        'C_ChatInfo.SendAddonMessage("BiaoGeAuction", text, "RAID")', 1, true) ~= nil, true,
        "outgoing auctions use the legacy-compatible prefix")
    test.eq(auctionModuleSource:find(
        'GetTime(), itemID, money, duration, "normal", link', 1, true) ~= nil, true,
        "outgoing auctions always use normal mode")
    test.eq(auctionModuleSource:find("BG.SendStartAuctionMsg(isGen2", 1, true), nil,
        "the direct start path does not select a protocol generation")
    test.eq(auctionModuleSource:find("mainFrame.dropDown2", 1, true), nil,
        "the start window has no protocol-generation dropdown")
    test.eq(auctionModuleSource:find("BiaoGe.Auction.mod", 1, true), nil,
        "the start window has no single-option auction-mode state")
    test.eq(auctionModuleSource:find("resetThreshold_OnEnter", 1, true), nil,
        "the start window has no second-generation reset-threshold control")
    test.eq(auctionModuleSource:find("local function UpdateFrame()", 1, true), nil,
        "the removed protocol controls have no update helper")
    test.eq(auctionModuleSource:find('edit._type = "duration"', 1, true) ~= nil, true,
        "the compact start window keeps auction duration")
    test.eq(auctionModuleSource:find('edit._type = "money"', 1, true) ~= nil, true,
        "the compact start window keeps starting price")
    test.eq(auctionModuleSource:find('edit._type = "count"', 1, true) ~= nil, true,
        "the compact start window keeps auction quantity")
    test.eq(auctionModuleSource:find(
        "Sender.shouldRespondVersion(versionResponseState, rawSender, realm, members, GetTime())", 1, true) ~= nil,
        true, "legacy version replies use the same membership and rate-limit policy")
    test.eq(auctionModuleSource:find(
        "Sender.shouldAcceptAuctionMessage(happyRateState, sender, realm, members, auctionID, GetTime(), 5)",
        1, true) ~= nil, true, "auction cheers have an independent five-second limit")
    test.eq(auctionModuleSource:find("SamePlayer(maijia, player)", 1, true) ~= nil, true,
        "the raid leader's own winning bid uses canonical player identity")

    local auctionSource = assert(io.open("Core/Module/AuctionWA.lua", "rb")):read("*a")
    test.eq(auctionSource:find("PlayerIdentity.same(bidFrame.player, wa.GN(), realmName)", 1, true) ~= nil,
        true, "self-bid detection uses canonical player identity")
    test.eq(auctionSource:find("if wa.IsMe(bidFrame) then return end", 1, true) ~= nil,
        true, "automatic bidding stops when the local player is already highest")
    test.eq(auctionSource:find("if player == wa.GN() then", 1, true), nil,
        "live highest-bidder rendering uses canonical player identity")
    test.eq(auctionSource:find("if bidFrame.player == wa.GN() then", 1, true), nil,
        "auction-result rendering uses canonical player identity")

    local eventSource = assert(io.open("Core/Module/AuctionWAEvent.lua", "rb")):read("*a")
    test.eq(eventSource:find("if player == wa.GN() then", 1, true), nil,
        "restored auction frames render the local bidder using canonical identity")
    test.eq(eventSource:find("if wa.IsMe(auctionFrame) then", 1, true) ~= nil, true,
        "restored auction frames show the original green local-player state")

    local logSource = assert(io.open("Core/Module/AuctionLog.lua", "rb")):read("*a")
    test.eq(logSource:find("BG.SendStartAuctionMsg(isGen2", 1, true), nil,
        "auction-log restart paths do not select a protocol generation")
    test.eq(logSource:find("PlayerIdentity.same(v.maijia, tradeName, realmName)", 1, true) ~= nil,
        true, "trade-price lookup uses canonical player identity")
    test.eq(logSource:find("trade = BG.ImML() and SamePlayer(maijia, BG.playerName) or nil", 1, true) ~= nil,
        true, "the raid leader's own auction record uses canonical player identity")
    test.eq(logSource:find("SamePlayer(maijia, tradeName)", 1, true) ~= nil, true,
        "the last-auction trade prompt uses canonical player identity")
    test.eq(logSource:find("PlayerIdentity.find(BG.raidRosterInfo, maijia, realmName)", 1, true) ~= nil, true,
        "auction records resolve buyer class data from the canonical raid roster")
    test.eq(logSource:find("BillBuyer.color(v, GetClassColor)", 1, true) ~= nil, true,
        "auction-log rendering derives a reliable class color")

    local tradeSource = assert(io.open("Core/Module/Trade.lua", "rb")):read("*a")
    test.eq(tradeSource:find("BG.SendStartAuctionMsg(isGen2", 1, true), nil,
        "trade restart paths do not select a protocol generation")
end
