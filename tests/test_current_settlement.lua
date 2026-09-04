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
        completed = true,
        status = "complete",
        myGold = 0,
        theirGold = 100,
        myItems = { { itemId = 1, quantity = 1 } },
        theirItems = {},
        time = 101,
        secret = "discard me",
    }), true, "current trade accepted")
    test.eq(root.currentSettlement.trades[1].secret, nil, "unknown trade field discarded")
    test.eq(trade.append(root, {
        raidId = "raid-b", player = "乙", completed = true, status = "complete",
        theirGold = 200, time = 102,
    }), false, "other raid trade rejected")
    test.eq(trade.append(root, {
        raidId = "raid-a", player = "", completed = true, status = "complete",
        theirGold = 200, time = 102,
    }), false, "unnamed trade rejected")

    -- a repeated success event for the same trade must not create a second record
    test.eq(trade.append(root, {
        raidId = "raid-a",
        player = "甲",
        completed = true,
        status = "complete",
        myGold = 0,
        theirGold = 100,
        myItems = { { itemId = 1, quantity = 1 } },
        theirItems = {},
        time = 101,
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
        raidId = "raid-a", player = "丙", completed = true, status = "私人备注", theirGold = 50, time = 104,
    }), false, "free-text trade status rejected")
    test.eq(trade.append(root, {
        raidId = "raid-a", player = "丙", completed = true, status = "cancelled", theirGold = 50, time = 104,
    }), true, "cancelled trade stored as cancelled")
    test.eq(root.currentSettlement.trades[2].status, "cancelled", "cancelled trade is never upgraded to success")
    test.eq(mail.append(root, {
        raidId = "raid-a", player = "丙", amount = 50, time = 105, status = "私人备注", direction = "outgoing",
    }), false, "free-text mail status rejected")
    test.eq(mail.append(root, {
        raidId = "raid-a", player = "丙", amount = 50, time = 105, status = "sent", direction = "私人备注",
    }), false, "free-text mail direction rejected")

    -- gold and item quantity are validated: an explicit 0 is a fact, a negative
    -- or a missing completed fact is rejected, and only a positive whole item
    -- count survives inside the item lists.
    test.eq(trade.append(root, {
        raidId = "raid-a", player = "丁", completed = true, status = "complete",
        myGold = 0, theirGold = 0, myItems = { { itemId = 3, quantity = 2 } }, time = 106,
    }), true, "explicit 0 gold is a valid fact")
    test.eq(root.currentSettlement.trades[3].myGold, 0, "zero gold is stored as 0, not unknown")
    test.eq(root.currentSettlement.trades[3].myItems[1].quantity, 2, "item quantity inside the list is preserved")
    test.eq(trade.append(root, {
        raidId = "raid-a", player = "戊", completed = true, status = "complete",
        theirGold = -1, time = 107,
    }), false, "a negative gold amount is rejected")
    test.eq(trade.append(root, {
        raidId = "raid-a", player = "戊", completed = false, status = "complete",
        theirGold = 50, time = 107,
    }), false, "a trade without the completed fact is rejected")
    test.eq(trade.append(root, {
        raidId = "raid-a", player = "己", completed = true, status = "complete",
        theirGold = 50, myItems = { { itemId = 4, quantity = 0 } }, time = 108,
    }), false, "a zero item quantity is rejected")
    test.eq(trade.append(root, {
        raidId = "raid-a", player = "己", completed = true, status = "complete",
        theirGold = 50, myItems = { { itemId = 4, quantity = 1.5 } }, time = 108,
    }), false, "a fractional item quantity is rejected")
end
