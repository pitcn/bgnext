local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

local function keys(columns)
    local list = {}
    for index, column in ipairs(columns) do
        list[index] = column.key
    end
    return table.concat(list, ",")
end

return function(test)
    BG = { BGNext = {} }
    local life = dofile("Core/BGNext/DataLifecycle.lua")
    local trade = dofile("Core/BGNext/CurrentTrade.lua")
    local mail = dofile("Core/BGNext/CurrentMail.lua")
    dofile("Core/BGNext/CurrentSettlementView.lua")
    local ui = dofile("Core/BGNext/CurrentSettlementUI.lua")

    local function stubDate(_, t)
        return "t" .. tostring(t)
    end

    -- 1. the tables keep the familiar column order and are clearly scoped
    test.eq(keys(ui.columns("trade")), "item,player,amount,time,status", "trade column order")
    test.eq(keys(ui.columns("mail")), "item,player,amount,time,direction,status", "mail column order")
    test.eq(ui.title("trade"), "交易记录（当前团）", "trade window title names the current raid scope")
    test.eq(ui.title("mail"), "邮件记录（当前团）", "mail window title names the current raid scope")

    -- 2. empty state
    local saved = {
        tradeHistory = { { player = "历史买家" } },
        mailHistory = { { player = "历史收件人" } },
        History = { ["raid-old"] = true },
        ICC = { auctionLog = { { maijia = "我" } } },
        options = { autoTrade = 1 },
    }
    local root = life.ensureRoot(saved)
    local rows, isEmpty = ui.rows(root, "trade", { now = 1000, dateFn = stubDate })
    test.eq(#rows, 0, "no trade rows in a fresh settlement")
    test.eq(isEmpty, true, "trade table reports the empty state")
    test.eq(type(ui.emptyText("trade")), "string", "trade empty state has text")
    test.eq(ui.emptyText("trade") ~= ui.emptyText("mail"), true, "each table has its own empty state text")

    -- 3. rows come only from the current settlement
    life.beginSettlement(root, "raid-a", 1000)
    test.eq(trade.append(root, {
        raidId = "raid-a", player = "甲", itemId = 11, amount = 100, time = 1100, status = "complete",
    }), true, "trade stored")
    test.eq(mail.append(root, {
        raidId = "raid-a", player = "乙", amount = 200, time = 1200, status = "sent", direction = "outgoing",
    }), true, "mail stored")

    rows, isEmpty = ui.rows(root, "trade", { now = 1300, dateFn = stubDate })
    test.eq(isEmpty, false, "trade table is populated")
    test.eq(#rows, 1, "only the settlement trade is listed")
    test.eq(rows[1].player, "甲", "trade row shows the counterparty")
    test.eq(rows[1].amountText, "100", "trade row shows the amount")
    test.eq(rows[1].timeText, "t1100", "trade row shows the time")

    local mailRows = ui.rows(root, "mail", { now = 1300, dateFn = stubDate })
    test.eq(#mailRows, 1, "only the settlement mail is listed")
    test.eq(mailRows[1].player, "乙", "mail row shows the counterparty")
    test.eq(mailRows[1].subject, nil, "mail row exposes no subject")
    test.eq(mailRows[1].body, nil, "mail row exposes no body")

    -- 4. status and direction are presented with distinct labels and colours
    test.eq(ui.statusLabel("trade", "complete") ~= ui.statusLabel("trade", "pending"), true,
        "success and pending are distinguishable")
    test.eq(ui.statusLabel("trade", "cancelled") ~= ui.statusLabel("trade", "failed"), true,
        "cancelled and failed are distinguishable")
    test.eq(type(ui.statusLabel("mail", "sent")), "string", "mail sent status has a label")
    test.eq(ui.directionLabel("outgoing") ~= ui.directionLabel("incoming"), true,
        "mail directions are distinguishable")
    local r, g, b = ui.statusColor("trade", "complete")
    test.eq(r == 0 and g == 1 and b == 0, true, "success is green in the table")
    r, g, b = ui.statusColor("trade", "pending")
    test.eq(r == 1 and b == 0, true, "pending is gold in the table")
    r, g, b = ui.statusColor("trade", "failed")
    test.eq(r == 1 and g == 0 and b == 0, true, "failure is red in the table")

    -- 5. the tooltip is driven by the stored item id, nothing else
    test.eq(ui.tooltipTarget({ itemId = 11 }), 11, "tooltip uses the stored item id")
    test.eq(ui.tooltipTarget({ itemId = "11" }), nil, "tooltip refuses a non-numeric item id")
    test.eq(ui.tooltipTarget({}), nil, "a row without an item has no tooltip")

    -- 6. clearing removes the settlement only
    test.eq(type(ui.clearConfirmText()), "string", "clearing asks for confirmation")
    test.eq(ui.clear(root), true, "clear reported success")
    test.eq(root.currentSettlement.raidId, nil, "settlement identity cleared")
    test.eq(#root.currentSettlement.trades, 0, "settlement trades cleared")
    test.eq(#root.currentSettlement.mails, 0, "settlement mails cleared")
    -- everything else survives
    test.eq(saved.ICC.auctionLog[1].maijia, "我", "the current bill and purchase log survive")
    test.eq(saved.options.autoTrade, 1, "BGLite options survive")
    test.eq(saved.tradeHistory ~= nil, true, "untouched legacy data is not deleted")
    test.eq(saved.mailHistory ~= nil, true, "untouched legacy mail data is not deleted")
    test.eq(saved.History ~= nil, true, "untouched legacy raid data is not deleted")
    test.eq(root.wishlist ~= nil, true, "wishlist survives")
    test.eq(root.equipmentFilters ~= nil, true, "equipment filters survive")
    test.eq(root.ownCharacters ~= nil, true, "own-character overview survives")
    test.eq(root.auctionPresets ~= nil, true, "auction presets survive")
    test.eq(root.settings ~= nil, true, "settings survive")

    -- 7. an expired settlement is purged before the table is shown
    life.beginSettlement(root, "raid-b", 2000)
    test.eq(trade.append(root, {
        raidId = "raid-b", player = "丙", itemId = 22, amount = 300, time = 2100, status = "complete",
    }), true, "second settlement trade stored")
    test.eq(ui.prepare(root, 2000 + 7 * 86400), true, "opening the page purges an expired settlement")
    test.eq(root.currentSettlement.raidId, nil, "expired settlement identity removed")
    rows, isEmpty = ui.rows(root, "trade", { now = 2000 + 7 * 86400, dateFn = stubDate })
    test.eq(#rows, 0, "no expired rows are displayed")
    test.eq(isEmpty, true, "expired settlement shows the empty state")

    -- 8. defence in depth on the source
    local source = readAll("Core/BGNext/CurrentSettlementUI.lua")
    for _, forbidden in ipairs({
        "SendAddonMessage", "SendChatMessage", "NotifyInspect",
        "COMBAT_LOG_EVENT_UNFILTERED", "tradeHistory", "mailHistory",
        "BiaoGe.History", "GetInboxText",
    }) do
        test.eq(source:find(forbidden, 1, true), nil, "settlement UI never references " .. forbidden)
    end
    test.eq(source:find("交易记录（当前团）", 1, true) ~= nil, true, "trade window is explicitly labelled")
    test.eq(source:find("邮件记录（当前团）", 1, true) ~= nil, true, "mail window is explicitly labelled")
    test.eq(source:find("StaticPopup_Show", 1, true) ~= nil, true, "clearing goes through a confirmation popup")
end
