return function(test)
    BG = { BGNext = {} }
    local life = dofile("Core/BGNext/DataLifecycle.lua")
    local trade = dofile("Core/BGNext/CurrentTrade.lua")
    local mail = dofile("Core/BGNext/CurrentMail.lua")
    local saved = {
        tradeHistory = { legacy = true },
        mailHistory = { legacy = true },
        History = { legacy = true },
    }
    local root = life.ensureRoot(saved)

    test.eq(saved.tradeHistory.legacy, true, "legacy trade data is untouched")
    test.eq(saved.mailHistory.legacy, true, "legacy mail data is untouched")
    test.eq(saved.History.legacy, true, "legacy raid data is untouched")

    life.beginSettlement(root, "raid-a", 100)
    test.eq(trade.append(root, {
        raidId = "raid-a",
        player = "甲",
        itemId = 1,
        amount = 100,
        time = 101,
        status = "complete",
        secret = "discard me",
    }), true, "current trade accepted")
    test.eq(root.currentSettlement.trades[1].secret, nil, "unknown trade field discarded")
    test.eq(trade.append(root, { raidId = "raid-b", player = "乙", amount = 200, time = 102 }), false, "other raid trade rejected")
    test.eq(trade.append(root, { raidId = "raid-a", player = "", amount = 200, time = 102 }), false, "unnamed trade rejected")

    -- a repeated success event for the same trade must not create a second record
    test.eq(trade.append(root, {
        raidId = "raid-a",
        player = "甲",
        itemId = 1,
        amount = 100,
        time = 101,
        status = "complete",
    }), false, "duplicate trade event rejected")
    test.eq(#root.currentSettlement.trades, 1, "duplicate trade event not stored")

    test.eq(mail.append(root, {
        raidId = "raid-a",
        player = "甲",
        itemId = 1,
        amount = 100,
        time = 103,
        status = "sent",
        direction = "outgoing",
        subject = "private",
        body = "secret",
    }), true, "current mail accepted")
    test.eq(root.currentSettlement.mails[1].subject, nil, "mail subject discarded")
    test.eq(root.currentSettlement.mails[1].body, nil, "mail body discarded")

    -- a repeated mail success event must not create a second record
    test.eq(mail.append(root, {
        raidId = "raid-a",
        player = "甲",
        itemId = 1,
        amount = 100,
        time = 103,
        status = "sent",
        direction = "outgoing",
    }), false, "duplicate mail event rejected")
    test.eq(#root.currentSettlement.mails, 1, "duplicate mail event not stored")

    test.eq(mail.append(root, { raidId = "raid-a", player = "甲", amount = 1, time = 100 + 7 * 86400 }), false, "expired mail rejected")

    -- status and direction accept only declared reconciliation states, never free text
    test.eq(trade.append(root, {
        raidId = "raid-a", player = "丙", itemId = 2, amount = 50, time = 104, status = "私人备注",
    }), false, "free-text trade status rejected")
    test.eq(trade.append(root, {
        raidId = "raid-a", player = "丙", itemId = 2, amount = 50, time = 104, status = "cancelled",
    }), true, "cancelled trade stored as cancelled")
    test.eq(root.currentSettlement.trades[2].status, "cancelled", "cancelled trade is never upgraded to success")
    test.eq(mail.append(root, {
        raidId = "raid-a", player = "丙", amount = 50, time = 105, status = "私人备注", direction = "outgoing",
    }), false, "free-text mail status rejected")
    test.eq(mail.append(root, {
        raidId = "raid-a", player = "丙", amount = 50, time = 105, status = "sent", direction = "私人备注",
    }), false, "free-text mail direction rejected")

    -- quantity is whitelisted and validated: only a positive whole count survives
    test.eq(trade.append(root, {
        raidId = "raid-a", player = "丁", itemId = 3, amount = 50, time = 106,
        status = "complete", quantity = 2,
    }), true, "a valid quantity is stored")
    test.eq(root.currentSettlement.trades[3].quantity, 2, "quantity field is preserved")
    test.eq(trade.append(root, {
        raidId = "raid-a", player = "戊", itemId = 4, amount = 50, time = 107,
        status = "complete", quantity = 0,
    }), false, "a zero quantity is rejected")
    test.eq(trade.append(root, {
        raidId = "raid-a", player = "戊", itemId = 4, amount = 50, time = 107,
        status = "complete", quantity = 1.5,
    }), false, "a fractional quantity is rejected")
end
