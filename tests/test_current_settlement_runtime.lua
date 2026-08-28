local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

return function(test)
    BG = { BGNext = {} }
    local life = dofile("Core/BGNext/DataLifecycle.lua")
    dofile("Core/BGNext/CurrentTrade.lua")
    dofile("Core/BGNext/CurrentMail.lua")
    local runtime = dofile("Core/BGNext/CurrentSettlementRuntime.lua")

    local function context(now, rosterTime)
        return {
            fb = "ICC",
            realm = "测试服",
            inRaid = true,
            roster = rosterTime and { time = rosterTime, realm = "测试服" } or nil,
            now = now,
        }
    end

    -- 1. attribution must be provable, otherwise nothing is recorded
    test.eq(runtime.raidId(context(5100, nil)), nil, "no raid roster means no provable raid identity")
    test.eq(runtime.raidId({ fb = "ICC", realm = "测试服", inRaid = false, roster = { time = 5000, realm = "测试服" }, now = 5100 }),
        nil, "outside a raid a new settlement is not established")
    test.eq(runtime.raidId({ fb = nil, realm = "测试服", inRaid = true, roster = { time = 5000, realm = "测试服" }, now = 5100 }),
        nil, "without a current table there is no raid identity")
    test.eq(runtime.raidId({ fb = "ICC", realm = "测试服", inRaid = true, roster = { time = 5000, realm = "别的服" }, now = 5100 }),
        nil, "a roster from another realm is not the current raid")
    test.eq(runtime.raidId(context(5100, 5000)), "ICC@5000", "provable raid identity")

    -- an unprovable event on an empty store writes nothing
    local root = life.ensureRoot({})
    test.eq(runtime.recordTrade(root, context(5100, nil), {
        completed = true, target = "甲", targetmoney = 100,
    }), 0, "no settlement means no trade record")
    test.eq(#root.currentSettlement.trades, 0, "unattributable trade is not stored")
    test.eq(root.currentSettlement.raidId, nil, "no settlement was invented")

    -- 2. a completed trade with a provable raid establishes and records
    --    (loot master hands over the item, the buyer puts up the gold)
    test.eq(runtime.recordTrade(root, context(5100, 5000), {
        completed = true, target = "甲", targetmoney = 100, playermoney = 0,
        playeritems = { { itemId = 11 } },
    }), 1, "completed trade recorded")
    test.eq(root.currentSettlement.raidId, "ICC@5000", "settlement established from the raid roster")
    local first = root.currentSettlement.trades[1]
    test.eq(first.player, "甲", "counterparty stored")
    test.eq(first.itemId, 11, "item stored")
    test.eq(first.amount, 100, "amount stored")
    test.eq(first.status, "complete", "completed trade stored as complete")
    test.eq(first.raidId, nil, "raidId is not copied into the record")

    -- 3. a repeated success event for the same trade writes nothing extra
    test.eq(runtime.recordTrade(root, context(5100, 5000), {
        completed = true, target = "甲", targetmoney = 100, playermoney = 0,
        playeritems = { { itemId = 11 } },
    }), 0, "duplicate trade completion ignored")
    test.eq(#root.currentSettlement.trades, 1, "duplicate trade completion not stored")

    -- 4. an unfinished, cancelled or closed trade is never stored as success
    test.eq(runtime.recordTrade(root, context(5200, 5000), {
        target = "乙", targetmoney = 500, targetitems = { { itemId = 22 } },
    }), 0, "trade without a completion signal is not recorded")
    test.eq(runtime.recordTrade(root, context(5200, 5000), {
        completed = false, target = "乙", targetmoney = 500, targetitems = { { itemId = 22 } },
    }), 0, "explicitly unfinished trade is not recorded")
    test.eq(#root.currentSettlement.trades, 1, "no cancelled trade was stored")

    -- 5. an item-only trade cannot prove a settlement amount: pending, never success
    test.eq(runtime.recordTrade(root, context(5300, 5000), {
        completed = true, target = "丙", targetmoney = 0, playermoney = 0,
        targetitems = { { itemId = 33 } }, playeritems = { { itemId = 44 } },
    }), 1, "item-only trade recorded for manual reconciliation")
    local pending = root.currentSettlement.trades[2]
    test.eq(pending.status, "pending", "item-only trade is pending, not complete")
    test.eq(pending.amount, nil, "no amount is invented for an item-only trade")

    -- 6. a trade with neither items nor money is not an event at all
    test.eq(runtime.recordTrade(root, context(5400, 5000), {
        completed = true, target = "丁", targetmoney = 0, playermoney = 0,
    }), 0, "empty trade is not recorded")

    -- 7. mail: only a plugin-executed send result, whitelisted fields only
    test.eq(runtime.recordMail(root, context(5500, 5000), {
        player = "甲", amount = 300,
    }), false, "mail without a send signal is not recorded")
    test.eq(runtime.recordMail(root, context(5500, 5000), {
        sent = true, player = "甲", amount = 300,
        subject = "团本工资", body = "私人内容", attachments = { 1, 2 },
    }), true, "plugin-executed mail send recorded")
    local mailRow = root.currentSettlement.mails[1]
    test.eq(mailRow.player, "甲", "mail counterparty stored")
    test.eq(mailRow.amount, 300, "mail amount stored")
    test.eq(mailRow.status, "sent", "mail stored as sent")
    test.eq(mailRow.direction, "outgoing", "mail direction stored")
    test.eq(mailRow.subject, nil, "mail subject never stored")
    test.eq(mailRow.body, nil, "mail body never stored")
    test.eq(mailRow.attachments, nil, "unrelated attachments never stored")

    -- 8. repeated mail success event writes nothing extra
    test.eq(runtime.recordMail(root, context(5500, 5000), {
        sent = true, player = "甲", amount = 300,
    }), false, "duplicate mail send ignored")
    test.eq(#root.currentSettlement.mails, 1, "duplicate mail send not stored")

    -- 9. a settlement that is already established still accepts records after
    --    the group disbands, because it is the one unsettled raid
    test.eq(runtime.recordMail(root, {
        fb = "ICC", realm = "测试服", inRaid = false, roster = nil, now = 5600,
    }, { sent = true, player = "乙", amount = 400 }), true, "wage mail after the raid disbands still reconciles")
    test.eq(#root.currentSettlement.mails, 2, "post-raid wage mail stored")

    -- 10. a new raid replaces the previous settlement instead of accumulating
    test.eq(runtime.recordTrade(root, context(9000, 8000), {
        completed = true, target = "戊", targetmoney = 700, targetitems = { { itemId = 55 } },
    }), 1, "new raid trade recorded")
    test.eq(root.currentSettlement.raidId, "ICC@8000", "new raid replaces the settlement identity")
    test.eq(#root.currentSettlement.trades, 1, "previous raid trades cleared")
    test.eq(#root.currentSettlement.mails, 0, "previous raid mails cleared")

    -- 11. an expired settlement is purged instead of extended
    local expired = 9000 + 7 * 86400
    test.eq(runtime.recordMail(root, {
        fb = "ICC", realm = "测试服", inRaid = false, roster = nil, now = expired,
    }, { sent = true, player = "己", amount = 900 }), false, "expired settlement accepts nothing")
    test.eq(root.currentSettlement.raidId, nil, "expired settlement cleared")
    test.eq(#root.currentSettlement.trades, 0, "expired trades cleared")

    -- 12. defence in depth: the collector adds no communication or history reads
    local source = readAll("Core/BGNext/CurrentSettlementRuntime.lua")
    for _, forbidden in ipairs({
        "SendAddonMessage", "SendChatMessage", "NotifyInspect",
        "COMBAT_LOG_EVENT_UNFILTERED", "tradeHistory", "mailHistory",
        "BiaoGe.History", "http", "GetInboxText", "GetInboxHeaderInfo",
    }) do
        test.eq(source:find(forbidden, 1, true), nil, "collector never references " .. forbidden)
    end
end
