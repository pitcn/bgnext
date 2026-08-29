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
    test.eq(Sender.parseBid(nil, "500"), nil, "a missing auction id is rejected")
    test.eq(Sender.parseBid("bad", "500"), nil, "a malformed auction id is rejected")
    test.eq(Sender.parseBid("42", nil), nil, "a missing bid amount is rejected")
    test.eq(Sender.parseBid("42", "bad"), nil, "a malformed bid amount is rejected")

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

    local auctionModuleSource = assert(io.open("Core/Module/Auction.lua", "rb")):read("*a")
    test.eq(auctionModuleSource:find(
        "Sender.shouldRespondVersion(versionResponseState, rawSender, realm, members, GetTime())", 1, true) ~= nil,
        true, "legacy version replies use the same membership and rate-limit policy")

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
    test.eq(logSource:find("PlayerIdentity.same(v.maijia, tradeName, realmName)", 1, true) ~= nil,
        true, "trade-price lookup uses canonical player identity")
end
