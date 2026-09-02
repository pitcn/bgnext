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

    local function context(now, rosterTime, fb, members)
        return {
            fb = fb or "ICC",
            realm = "测试服",
            inRaid = true,
            roster = rosterTime and {
                time = rosterTime,
                realm = "测试服",
                roster = members or { "甲", "乙", "丙", "丁", "戊", "己" },
            } or nil,
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

    -- 6b. gold on both sides cannot name the buyer or the direction: the
    --     delivered item is kept as a pending record with no amount and no
    --     direction, so the checklist can never read it as a proven sale.
    local ambiguous = runtime.tradeRows({
        completed = true, target = "甲", targetmoney = 100, playermoney = 50,
        playeritems = { { itemId = 7001 } },
    })
    test.eq(#ambiguous, 1, "both-gold trade projects one pending row")
    test.eq(ambiguous[1].itemId, 7001, "the delivered item is kept")
    test.eq(ambiguous[1].amount, nil, "no amount is invented for a both-gold trade")
    test.eq(ambiguous[1].direction, nil, "both-gold direction is not guessed")
    test.eq(ambiguous[1].status, "pending", "both-gold trade stays pending")
    local ambiguousRoot = life.ensureRoot({})
    test.eq(runtime.recordTrade(ambiguousRoot, context(5450, 5000), {
        completed = true, target = "甲", targetmoney = 100, playermoney = 50,
        playeritems = { { itemId = 7001 } },
    }), 1, "both-gold trade is recorded as pending")
    local ambiguousRecord = ambiguousRoot.currentSettlement.trades[1]
    test.eq(ambiguousRecord.direction, nil, "stored both-gold direction stays nil")
    test.eq(ambiguousRecord.amount, nil, "stored both-gold amount stays nil")
    test.eq(ambiguousRecord.status, "pending", "stored both-gold status is pending")

    -- 7. mail: only a plugin-executed send result, whitelisted fields only
    test.eq(runtime.recordMail(root, context(5500, 5000), {
        player = "甲", amount = 300,
    }), false, "mail without a send signal is not recorded")
    test.eq(runtime.recordMail(root, context(5500, 5000), {
        sent = true, scope = "raid", player = "甲", amount = 300,
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
        sent = true, scope = "raid", player = "甲", amount = 300,
    }), false, "duplicate mail send ignored")
    test.eq(#root.currentSettlement.mails, 1, "duplicate mail send not stored")

    -- 9. a settlement that is already established still accepts records after
    --    the group disbands, because it is the one unsettled raid
    test.eq(runtime.recordMail(root, {
        fb = "ICC", realm = "测试服", inRaid = false,
        roster = { time = 5000, realm = "测试服", roster = { "甲", "乙" } }, now = 5600,
    }, { sent = true, scope = "raid", player = "乙", amount = 400 }), true,
        "wage mail to a recorded raid member after disband still reconciles")
    test.eq(#root.currentSettlement.mails, 2, "post-raid wage mail stored")

    test.eq(runtime.recordMail(root, {
        fb = "ICC", realm = "测试服", inRaid = false,
        roster = { time = 5000, realm = "测试服", roster = { "甲", "乙" } }, now = 5601,
    }, { sent = true, scope = "custom", player = "乙", amount = 400 }), false,
        "custom-list mail is never attributed to the raid")
    test.eq(runtime.recordMail(root, {
        fb = "ICC", realm = "测试服", inRaid = false,
        roster = { time = 5000, realm = "测试服", roster = { "甲", "乙" } }, now = 5602,
    }, { sent = true, scope = "raid", player = "路人", amount = 400 }), false,
        "mail to a non-roster recipient is rejected")
    test.eq(runtime.recordTrade(root, context(5603, 5000), {
        completed = true, target = "路人", targetmoney = 100, playeritems = { { itemId = 99 } },
    }), 0, "trade with a non-roster counterparty is rejected")

    -- 10. a later boss in the same raid refreshes raidRoster.time but must not
    --     replace the settlement or erase earlier rows.
    test.eq(runtime.recordTrade(root, context(9000, 8000), {
        completed = true, target = "戊", targetmoney = 700, targetitems = { { itemId = 55 } },
    }), 1, "later boss trade recorded")
    test.eq(root.currentSettlement.raidId, "ICC@5000", "same raid keeps its stable settlement identity")
    test.eq(#root.currentSettlement.trades, 3, "same-raid earlier trades survive later boss timestamps")
    test.eq(#root.currentSettlement.mails, 2, "same-raid earlier mails survive later boss timestamps")

    -- BGLite's existing same-team check compares the live roster with the
    -- table roster. If it says this is a different team, the stale settlement
    -- is cleared and no event is attributed until BGLite stamps the new raid.
    local changedTeam = context(9100, 9000, "ICC", { "新甲", "新乙" })
    changedTeam.sameTeam = false
    test.eq(runtime.recordTrade(root, changedTeam, {
        completed = true, target = "新甲", targetmoney = 700,
        targetitems = { { itemId = 56 } },
    }), 0, "same-instance new team is not merged into the previous settlement")
    test.eq(root.currentSettlement.raidId, nil, "new-team boundary clears the stale settlement")

    changedTeam.sameTeam = true
    test.eq(runtime.recordTrade(root, changedTeam, {
        completed = true, target = "新甲", targetmoney = 700,
        targetitems = { { itemId = 56 } },
    }), 1, "new team starts only after BGLite confirms its roster stamp")
    test.eq(root.currentSettlement.raidId, "ICC@9000", "same-instance new team gets a new identity")
    test.eq(#root.currentSettlement.trades, 1, "new team does not retain prior-team trades")
    test.eq(#root.currentSettlement.mails, 0, "new team does not retain prior-team mails")

    -- A genuinely different detected instance starts a new settlement.
    test.eq(runtime.recordTrade(root, context(10000, 9500, "TOC", { "庚" }), {
        completed = true, target = "庚", targetmoney = 700, targetitems = { { itemId = 66 } },
    }), 1, "different-instance raid trade recorded")
    test.eq(root.currentSettlement.raidId, "TOC@9500", "different instance replaces the settlement identity")
    test.eq(#root.currentSettlement.trades, 1, "different-instance raid clears prior trades")
    test.eq(#root.currentSettlement.mails, 0, "different-instance raid clears prior mails")

    test.eq(runtime.onTableCleared(root, "ICC"), false,
        "clearing a different table does not erase the active settlement")
    test.eq(runtime.onTableCleared(root, "TOC"), true,
        "clearing the active raid table clears its settlement")
    test.eq(root.currentSettlement.raidId, nil, "manual table clear removes the settlement identity")

    -- Re-establish for the expiry check.
    test.eq(runtime.recordTrade(root, context(10000, 9500, "TOC", { "庚" }), {
        completed = true, target = "庚", targetmoney = 700, targetitems = { { itemId = 66 } },
    }), 1, "settlement can be established again after a manual clear")

    -- 11. an expired settlement is purged instead of extended
    local expired = 10000 + 7 * 86400
    test.eq(runtime.recordMail(root, {
        fb = "ICC", realm = "测试服", inRaid = false, roster = nil, now = expired,
    }, { sent = true, scope = "raid", player = "己", amount = 900 }), false, "expired settlement accepts nothing")
    test.eq(root.currentSettlement.raidId, nil, "expired settlement cleared")
    test.eq(#root.currentSettlement.trades, 0, "expired trades cleared")

    -- 12. live attribution follows the detected instance and authoritative
    --     server clock, never the table the user happens to be browsing.
    BG.BGNext.DB = root
    BG.FB1 = "TOC"
    BG.FB2 = "ICC"
    BG.realmName = "测试服"
    BG.GSN = function(name) return name end
    BiaoGe = {
        ICC = { raidRoster = { time = 12000, realm = "测试服", roster = { "甲" } } },
        TOC = { raidRoster = { time = 1, realm = "测试服", roster = { "路人" } } },
    }
    IsInRaid = function() return true end
    GetServerTime = function() return 12100 end
    time = function() return 999999 end
    local live = runtime.liveContext()
    test.eq(live.fb, "ICC", "live context uses the detected instance rather than selected table")
    test.eq(live.roster, BiaoGe.ICC.raidRoster, "live context uses the detected instance roster")
    test.eq(live.now, 12100, "live context uses the server clock")

    -- One mail attempt owns exactly one success result. A duplicated result is
    -- ignored even when the clock advances; a genuinely new identical attempt
    -- gets a new in-memory token and may be recorded.
    life.beginSettlement(root, "ICC@12000", 12100, { fb = "ICC", realm = "测试服" })
    test.eq(runtime.notifyMailAttempt("甲", 300, "raid"), true, "raid mail attempt is armed")
    test.eq(runtime.notifyMailSent("甲", 300, "raid"), true, "first result consumes the mail attempt")
    GetServerTime = function() return 12101 end
    test.eq(runtime.notifyMailSent("甲", 300, "raid"), false,
        "duplicate mail result in a later second cannot be recorded")
    test.eq(runtime.notifyMailAttempt("甲", 300, "raid"), true, "new identical mail gets a new attempt token")
    test.eq(runtime.notifyMailSent("甲", 300, "raid"), true,
        "new identical mail attempt can be recorded independently")
    test.eq(runtime.notifyMailAttempt("甲", 300, "custom"), false,
        "custom-list mail never receives a settlement token")

    -- Successful writes refresh only the affected visible table. Rejected or
    -- duplicate events do not cause redraw churn.
    local refreshes = {}
    BG.BGNext.CurrentSettlementUI = {
        Refresh = function(kind) refreshes[#refreshes + 1] = kind end,
    }
    local refreshRoot = life.ensureRoot({})
    test.eq(runtime.recordTrade(refreshRoot, context(13000, 12900), {
        completed = true, target = "甲", targetmoney = 100,
        playeritems = { { itemId = 77 } },
    }), 1, "new trade writes before live refresh")
    test.eq(refreshes[1], "trade", "trade write refreshes the trade table")
    test.eq(runtime.recordTrade(refreshRoot, context(13000, 12900), {
        completed = true, target = "甲", targetmoney = 100,
        playeritems = { { itemId = 77 } },
    }), 0, "duplicate trade remains rejected")
    test.eq(#refreshes, 1, "rejected duplicate does not redraw")
    test.eq(runtime.recordMail(refreshRoot, context(13001, 12900), {
        sent = true, scope = "raid", player = "乙", amount = 200,
    }), true, "new raid mail writes before live refresh")
    test.eq(refreshes[2], "mail", "mail write refreshes the mail table")

    -- 13. defence in depth: the collector adds no communication or history reads
    local source = readAll("Core/BGNext/CurrentSettlementRuntime.lua")
    for _, forbidden in ipairs({
        "SendAddonMessage", "SendChatMessage", "NotifyInspect",
        "COMBAT_LOG_EVENT_UNFILTERED", "tradeHistory", "mailHistory",
        "BiaoGe.History", "http", "GetInboxText", "GetInboxHeaderInfo",
    }) do
        test.eq(source:find(forbidden, 1, true), nil, "collector never references " .. forbidden)
    end
    test.eq(source:find('BG.RegisterEvent("GROUP_ROSTER_UPDATE"', 1, true), nil,
        "ordinary roster churn cannot clear the settlement while members leave")
    test.eq(source:find('BG.RegisterEvent("PLAYER_ENTERING_WORLD"', 1, true), nil,
        "leaving an instance cannot race a delayed team-boundary check")
    test.eq(source:find('BG.RegisterEvent("ENCOUNTER_START"', 1, true) ~= nil, true,
        "same-instance team boundary is checked before BGLite replaces the boss roster")
end
