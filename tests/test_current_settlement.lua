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
    test.eq(mail.append(root, { raidId = "raid-a", player = "甲", amount = 1, time = 100 + 7 * 86400 }), false, "expired mail rejected")
end
