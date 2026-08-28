return function(test)
    BG = { BGNext = {} }
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
    test.eq(Sender.isRaidSender(nil, "Realm", { "Alice" }), false, "a missing sender is ignored")
    test.eq(Sender.isRaidSender("", "Realm", { "Alice" }), false, "an empty sender is ignored")
    test.eq(Sender.isRaidSender("Alice", "Realm", {}), false, "an empty roster accepts no one")

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
end
