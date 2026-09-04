local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

return function(test)
    BG = { BGNext = {} }
    local life = dofile("Core/BGNext/DataLifecycle.lua")
    local trade = dofile("Core/BGNext/CurrentTrade.lua")
    local mail = dofile("Core/BGNext/CurrentMail.lua")
    local view = dofile("Core/BGNext/CurrentSettlementView.lua")

    local function stubDate(_, t)
        return "t" .. tostring(t)
    end

    local saved = {
        tradeHistory = { { player = "历史买家", itemId = 99, amount = 999 } },
        mailHistory = { { player = "历史收件人", amount = 888 } },
        History = { ["raid-old"] = { leaked = true } },
    }
    local root = life.ensureRoot(saved)
    life.beginSettlement(root, "raid-a", 1000)

    -- empty state
    local rows, isEmpty = view.trades(root, { now = 1000, dateFn = stubDate })
    test.eq(#rows, 0, "no trade rows before any event")
    test.eq(isEmpty, true, "trade view reports the empty state")
    local mailRows, mailEmpty = view.mails(root, { now = 1000, dateFn = stubDate })
    test.eq(#mailRows, 0, "no mail rows before any event")
    test.eq(mailEmpty, true, "mail view reports the empty state")

    -- appended out of chronological order on purpose
    test.eq(trade.append(root, {
        raidId = "raid-a", player = "乙", completed = true, status = "pending",
        myGold = 0, theirGold = 200, myItems = { { itemId = 22, quantity = 1 } }, time = 1300,
    }), true, "second trade accepted")
    test.eq(trade.append(root, {
        raidId = "raid-a", player = "甲", completed = true, status = "complete",
        myGold = 0, theirGold = 100, myItems = { { itemId = 11, quantity = 1 } }, time = 1100,
    }), true, "first trade accepted")
    test.eq(trade.append(root, {
        raidId = "raid-a", player = "甲", completed = true, status = "cancelled",
        myGold = 0, theirGold = 300, myItems = { { itemId = 33, quantity = 1 } }, time = 1100,
    }), true, "same-second trade accepted")

    rows, isEmpty = view.trades(root, { now = 1400, dateFn = stubDate })
    test.eq(isEmpty, false, "trade view is no longer empty")
    test.eq(#rows, 3, "every stored trade is projected without aggregation")

    -- chronological, and equal timestamps keep their stored order (stable sort)
    test.eq(rows[1].time, 1100, "earliest trade first")
    test.eq(rows[1].myItems[1].itemId, 11, "equal timestamps keep insertion order")
    test.eq(rows[2].myItems[1].itemId, 33, "equal timestamps are not reordered")
    test.eq(rows[3].time, 1300, "latest trade last")

    -- the same player appears once per event; no per-player totals or ranking
    test.eq(rows[1].player, "甲", "row keeps the trade partner name")
    test.eq(rows[2].player, "甲", "repeat partner is a separate row, not a group")
    test.eq(rows[1].total, nil, "no per-player accumulated total")
    test.eq(rows[1].count, nil, "no per-player event count")
    test.eq(rows[1].rank, nil, "no ranking field")

    -- the grouped transaction carries its facts through the projection
    test.eq(rows[1].theirGold, 100, "received gold carried through the projection")
    test.eq(rows[1].myGold, 0, "paid gold carried through the projection")
    test.eq(rows[1].completedKey, true, "completed fact carried through the projection")
    test.eq(rows[1].timeText, "t1100", "time formatted through the injected formatter")
    test.eq(rows[1].statusKey, "complete", "status key preserved for the UI")

    -- quantity is carried through the projection so the visible table can show
    -- that two of the same item were delivered; a grouped record has no legacy
    -- quantity field, so nothing is invented.
    test.eq(trade.append(root, {
        raidId = "raid-a", player = "乙", completed = true, status = "complete",
        myGold = 0, theirGold = 400, myItems = { { itemId = 22, quantity = 2 } }, time = 1400,
    }), true, "a quantity-aware trade is stored")
    rows, isEmpty = view.trades(root, { now = 1500, dateFn = stubDate })
    test.eq(#rows, 4, "the quantity-aware trade adds one projected row")
    local qtyRow = rows[4]
    test.eq(qtyRow.myItems[1].quantity, 2, "the projected row carries the delivered count")
    test.eq(qtyRow.myItems[1].itemId, 22, "the quantity-aware row still names the item")
    local groupedRow = rows[1]
    test.eq(groupedRow.quantity, nil, "a grouped record has no legacy quantity field")

    -- a legacy flat record (written before the grouped model) still projects
    -- through its legacy passthrough fields without being rewritten.
    table.insert(root.currentSettlement.trades, {
        raidId = "raid-a", player = "甲", itemId = 55, amount = 500,
        time = 1500, status = "complete", direction = "outgoing", quantity = 1,
    })
    rows, isEmpty = view.trades(root, { now = 1600, dateFn = stubDate })
    test.eq(#rows, 5, "a legacy record adds one projected row")
    local legacyFlat = rows[5]
    test.eq(legacyFlat.itemId, 55, "legacy item passthrough survives")
    test.eq(legacyFlat.amount, 500, "legacy amount passthrough survives")
    test.eq(legacyFlat.directionKey, "outgoing", "legacy direction passthrough survives")
    test.eq(legacyFlat.quantity, 1, "legacy quantity passthrough survives")
    local r, g, b = view.statusColor("trade", "complete")
    test.eq(r == 0 and g == 1 and b == 0, true, "success status is green")
    r, g, b = view.statusColor("trade", "pending")
    test.eq(r == 1 and g > 0.5 and b == 0, true, "pending status is gold")
    r, g, b = view.statusColor("trade", "failed")
    test.eq(r == 1 and g == 0 and b == 0, true, "failed status is red")
    r, g, b = view.statusColor("trade", "cancelled")
    test.eq(r == g and g == b, true, "cancelled status is neutral grey")

    -- mail projection reads only currentSettlement.mails
    test.eq(mail.append(root, {
        raidId = "raid-a", player = "丙", itemId = 44, amount = 400, time = 1200,
        status = "sent", direction = "outgoing",
    }), true, "mail accepted")
    mailRows, mailEmpty = view.mails(root, { now = 1400, dateFn = stubDate })
    test.eq(mailEmpty, false, "mail view is no longer empty")
    test.eq(#mailRows, 1, "only the stored settlement mail is projected")
    test.eq(mailRows[1].player, "丙", "mail row keeps the counterparty name")
    test.eq(mailRows[1].directionKey, "outgoing", "mail row keeps the direction key")
    test.eq(mailRows[1].subject, nil, "mail row never exposes a subject")
    test.eq(mailRows[1].body, nil, "mail row never exposes a body")

    -- legacy stores are never projected
    for _, row in ipairs(rows) do
        test.eq(row.player ~= "历史买家", true, "legacy trade history is not projected")
    end
    for _, row in ipairs(mailRows) do
        test.eq(row.player ~= "历史收件人", true, "legacy mail history is not projected")
    end

    -- an expired settlement projects nothing even before the store is purged
    rows, isEmpty = view.trades(root, { now = 1000 + 7 * 86400, dateFn = stubDate })
    test.eq(#rows, 0, "expired settlement projects no trade rows")
    test.eq(isEmpty, true, "expired settlement reports the empty state")
    mailRows, mailEmpty = view.mails(root, { now = 1000 + 7 * 86400, dateFn = stubDate })
    test.eq(#mailRows, 0, "expired settlement projects no mail rows")
    test.eq(mailEmpty, true, "expired settlement mail reports the empty state")

    -- defence in depth: the projection source never names a legacy store
    local source = readAll("Core/BGNext/CurrentSettlementView.lua")
    test.eq(source:find("tradeHistory", 1, true), nil, "view never reads tradeHistory")
    test.eq(source:find("mailHistory", 1, true), nil, "view never reads mailHistory")
    test.eq(source:find("BiaoGe.History", 1, true), nil, "view never reads cross-raid history")
    test.eq(source:find("SendAddonMessage", 1, true), nil, "view sends no addon message")
    test.eq(source:find("SendChatMessage", 1, true), nil, "view sends no chat message")
end
