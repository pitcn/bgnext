return function(test)
    BG = { BGNext = {} }
    local Msg = dofile("Core/BGNext/AuctionBidMessage.lua")

    -- The gen1 bid message parses into its fields.
    local parsed = Msg.parse("BiaoGeAuction", "SendMyMoney,12,500000")
    test.eq(parsed.opcode, "SendMyMoney", "parses the opcode")
    test.eq(parsed.auctionId, "12", "parses the auction id")
    test.eq(parsed.auctionIdNum, 12, "parses the auction id as a number")
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

    -- Strict protocol: empty fields, extra fields, notation and range all fail.
    test.eq(Msg.parse("BiaoGeAuction", "SendMyMoney,,500000"), nil, "an empty auction id is rejected")
    test.eq(Msg.parse("BiaoGeAuction", "SendMyMoney,12,"), nil, "an empty amount is rejected")
    test.eq(Msg.parse("BiaoGeAuction", "SendMyMoney,12,500000,extra"), nil, "an extra field is rejected")
    test.eq(Msg.parse("BiaoGeAuction", "SendMyMoney,12,500000,"), nil, "a trailing empty field is rejected")
    test.eq(Msg.parse("BiaoGeAuction", "SendMyMoney,12,5e3"), nil, "scientific notation is rejected")
    test.eq(Msg.parse("BiaoGeAuction", "SendMyMoney,12,5.5"), nil, "a decimal amount is rejected")
    test.eq(Msg.parse("BiaoGeAuction", "SendMyMoney,abc,500000"), nil, "a non-numeric auction id is rejected")
    test.eq(Msg.parse("BiaoGeAuction", "SendMyMoney,0,500000"), nil, "a zero auction id is rejected")
    test.eq(Msg.parse("BiaoGeAuction", "SendMyMoney,12,0"), nil, "a zero amount is rejected")
    test.eq(Msg.parse("BiaoGeAuction", "SendMyMoney,12,2147483648"), nil, "an amount over the cap is rejected")
    test.eq(Msg.parse("BiaoGeAuction", "SendMyMoney,12,0007").money, 7, "leading zeros still parse as a number")

    -- The explicit sender adapter reads the fifth argument, never the fourth.
    test.eq(Msg.extractSender("build", "Target-Name", "Alice"), "Alice", "the sender is the fifth argument")
    test.eq(Msg.extractSender("build", "Alice", nil), nil, "a missing fifth argument fails closed")
    test.eq(Msg.extractSender("build", "Alice", ""), "", "an empty fifth argument is empty, not the target")

    -- classify turns a raw event into one decision.
    local function classify(prefix, message, distribution, arg4, arg5, active)
        return Msg.classify("build", prefix, message, distribution, arg4, arg5, active)
    end
    local bid = classify("BiaoGeAuction", "SendMyMoney,12,500000", "RAID", "Target", "Alice", "12")
    test.eq(bid.kind, "bid", "a RAID bid for the active auction is a bid")
    test.eq(bid.sender, "Alice", "the classified bid carries the sender")
    test.eq(classify("BiaoGeAuction", "SendMyMoney,12,500000", "PARTY", "Target", "Alice", "12").reason,
        "not-raid", "a PARTY distribution is rejected")
    test.eq(classify("BiaoGeAuction", "SendMyMoney,12,500000", "WHISPER", "Target", "Alice", "12").reason,
        "not-raid", "a WHISPER distribution is rejected")
    test.eq(classify("BiaoGeAuction", "SendMyMoney,12,500000", "INSTANCE_CHAT", "Target", "Alice", "12").reason,
        "not-raid", "an INSTANCE_CHAT distribution is rejected")
    test.eq(classify("BiaoGeAuction", "SendMyMoney,12,500000", "GUILD", "Target", "Alice", "12").reason,
        "not-raid", "a GUILD distribution is rejected")
    test.eq(classify("BiaoGeAuction", "SendMyMoney,12,500000", nil, "Target", "Alice", "12").reason,
        "not-raid", "a missing distribution is rejected")
    test.eq(classify("BiaoGeAuction", "SendMyMoney,12,500000", "RAID", "Target", nil, "12").reason,
        "no-sender", "a missing sender is rejected")
    test.eq(classify("BiaoGeAuction", "StartAuction,12,500000", "RAID", "Target", "Alice", "12").kind,
        "ignored", "a non-bid opcode is ignored")
    test.eq(classify("BiaoGe", "SendMyMoney,12,500000", "RAID", "Target", "Alice", "12").kind,
        "ignored", "another channel is ignored")
    test.eq(classify("BiaoGeAuction", "SendMyMoney,12,abc", "RAID", "Target", "Alice", "12").reason,
        "malformed", "a malformed bid body fails closed")
    test.eq(classify("BiaoGeAuction", "SendMyMoney,99,500000", "RAID", "Target", "Alice", "12").kind,
        "wrong-auction", "a bid for another auction is ignored")

    -- A bid event is validated against the current raid and active auction.
    local raid = { ["Alice-Realm"] = true, ["Me-Realm"] = true }
    local function reason(event, ctx)
        return Msg.validateBidEvent(event, ctx)
    end
    local ok = { opcode = "SendMyMoney", auctionId = "12", money = 500000 }

    test.eq(reason(ok, { sender = "Alice-Realm", raidMembers = raid, auctionId = "12" }), nil,
        "a raid member bidding on the active auction is valid")
    test.eq(reason(ok, { sender = "Stranger-Realm", raidMembers = raid, auctionId = "12" }), "not-raid",
        "a non-raid sender is rejected")
    test.eq(reason(ok, { sender = nil, raidMembers = raid, auctionId = "12" }), "not-raid",
        "a missing sender is rejected")
    test.eq(reason(ok, { sender = "Alice-Realm", raidMembers = raid, auctionId = "99" }), "wrong-auction",
        "a bid for another auction is rejected")

    test.eq(reason({ opcode = "SendMyMoney", auctionId = "12", money = 0 }, { sender = "Alice-Realm", raidMembers = raid, auctionId = "12" }), "bad-money",
        "a zero amount is rejected")
    test.eq(reason({ opcode = "SendMyMoney", auctionId = "12", money = -5 }, { sender = "Alice-Realm", raidMembers = raid, auctionId = "12" }), "bad-money",
        "a negative amount is rejected")
    test.eq(reason({ opcode = "SendMyMoney", auctionId = "12", money = 500.5 }, { sender = "Alice-Realm", raidMembers = raid, auctionId = "12" }), "bad-money",
        "a fractional amount is rejected")
    test.eq(reason({ opcode = "SendMyMoney", auctionId = "12", money = 2147483648 }, { sender = "Alice-Realm", raidMembers = raid, auctionId = "12" }), "bad-money",
        "an amount over the cap is rejected")
    test.eq(reason(nil, { sender = "Alice-Realm", raidMembers = raid, auctionId = "12" }), "bad-fields",
        "a missing event is rejected")
    test.eq(reason({ opcode = "VersionCheck", auctionId = "12", money = 500000 }, { sender = "Alice-Realm", raidMembers = raid, auctionId = "12" }), "bad-fields",
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
