return function(test)
    BG = { BGNext = {} }
    local Msg = dofile("Core/BGNext/AuctionBidMessage.lua")

    -- The gen1 bid message parses into its fields.
    local parsed = Msg.parse("BiaoGeAuction", "SendMyMoney,12,500000")
    test.eq(parsed.opcode, "SendMyMoney", "parses the opcode")
    test.eq(parsed.auctionId, "12", "parses the auction id")
    test.eq(parsed.money, 500000, "parses the money as a number")

    -- Only the gen1 channel is accepted; rotating gen2 channels are out of scope.
    test.eq(Msg.parse("BiaoGeAuction1", "SendMyMoney,12,500000"), nil, "gen2 channels are out of scope")
    test.eq(Msg.parse(nil, "SendMyMoney,12,500000"), nil, "a missing prefix is rejected")

    -- Non-bid opcodes are not bid events.
    test.eq(Msg.parse("BiaoGeAuction", "StartAuction,12,500000"), nil, "StartAuction is not a bid event")
    test.eq(Msg.parse("BiaoGeAuction", "CancelAuction,12"), nil, "CancelAuction is not a bid event")

    -- Malformed messages are rejected at the structure level.
    test.eq(Msg.parse("BiaoGeAuction", "SendMyMoney,12"), nil, "a missing amount is rejected")
    test.eq(Msg.parse("BiaoGeAuction", "SendMyMoney"), nil, "missing fields are rejected")
    test.eq(Msg.parse("BiaoGeAuction", "SendMyMoney,12,abc"), nil, "a non-numeric amount is rejected")
    test.eq(Msg.parse("BiaoGeAuction", ""), nil, "an empty message is rejected")

    -- A bid event is validated against the current raid and active auction.
    local raid = { ["Alice"] = true, ["Me"] = true }
    local function reason(event, ctx)
        return Msg.validateBidEvent(event, ctx)
    end
    local ok = { opcode = "SendMyMoney", auctionId = "12", money = 500000 }

    test.eq(reason(ok, { sender = "Alice", raidMembers = raid, auctionId = "12" }), nil,
        "a raid member bidding on the active auction is valid")
    test.eq(reason(ok, { sender = "Stranger", raidMembers = raid, auctionId = "12" }), "not-raid",
        "a non-raid sender is rejected")
    test.eq(reason(ok, { sender = nil, raidMembers = raid, auctionId = "12" }), "not-raid",
        "a missing sender is rejected")
    test.eq(reason(ok, { sender = "Alice", raidMembers = raid, auctionId = "99" }), "wrong-auction",
        "a bid for another auction is rejected")

    test.eq(reason({ opcode = "SendMyMoney", auctionId = "12", money = 0 }, { sender = "Alice", raidMembers = raid, auctionId = "12" }), "bad-money",
        "a zero amount is rejected")
    test.eq(reason({ opcode = "SendMyMoney", auctionId = "12", money = -5 }, { sender = "Alice", raidMembers = raid, auctionId = "12" }), "bad-money",
        "a negative amount is rejected")
    test.eq(reason({ opcode = "SendMyMoney", auctionId = "12", money = 500.5 }, { sender = "Alice", raidMembers = raid, auctionId = "12" }), "bad-money",
        "a fractional amount is rejected")
    test.eq(reason({ opcode = "SendMyMoney", auctionId = "12", money = 2147483648 }, { sender = "Alice", raidMembers = raid, auctionId = "12" }), "bad-money",
        "an amount over the cap is rejected")
    test.eq(reason(nil, { sender = "Alice", raidMembers = raid, auctionId = "12" }), "bad-fields",
        "a missing event is rejected")
    test.eq(reason({ opcode = "VersionCheck", auctionId = "12", money = 500000 }, { sender = "Alice", raidMembers = raid, auctionId = "12" }), "bad-fields",
        "a non-bid opcode fails validation")

    -- The outbound format is defined once and matches the approved protocol.
    test.eq(Msg.buildBidMessage("12", 500000), "SendMyMoney,12,500000", "buildBidMessage matches the approved format")

    -- Source-level invariants: the adapter only parses and builds strings.
    local handle = io.open("Core/BGNext/AuctionBidMessage.lua", "r")
    local source = handle:read("*a")
    handle:close()
    -- "BiaoGe." (not the bare word) catches the SavedVariables global while
    -- still allowing the protocol's channel name "BiaoGeAuction".
    for _, forbidden in ipairs({
        "BiaoGe.", "SendAddonMessage", "SendChatMessage", "C_ChatInfo",
        "CreateFrame", "RegisterEvent", "C_Timer", "random",
    }) do
        test.eq(string.find(source, forbidden, 1, true), nil, "adapter never uses " .. forbidden)
    end
end
