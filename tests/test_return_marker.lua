return function(test)
    BG = { BGNext = {} }
    local life = dofile("Core/BGNext/DataLifecycle.lua")
    local marker = dofile("Core/BGNext/ReturnMarker.lua")
    local root = life.ensureRoot({})
    life.beginSettlement(root, "ICC@100", 100, { fb = "ICC", realm = "Realm" })
    root.currentSettlement.trades = { {
        player = "买家甲", time = 110, completed = true, status = "pending",
        myGold = 0, theirGold = 0, myItems = {},
        theirItems = { { itemId = 7001, quantity = 1 } },
    } }
    local bill = {
        { boss = 1, slot = 1, itemId = 7001, buyer = "买家甲", amount = "1000" },
        { boss = 2, slot = 3, itemId = 7001, buyer = "买家甲", amount = "1200" },
    }

    local candidates = marker.candidates(root, 1, bill)
    test.eq(#candidates, 2, "duplicate returned items require a bill-row choice")
    local ok, reason = marker.mark(root, 1, nil, bill, 120, true)
    test.eq(ok, false, "an ambiguous return is never marked automatically")
    test.eq(reason, "selection-required", "ambiguous return explains that a row must be selected")
    test.eq(#root.currentSettlement.returns, 0, "failed selection stores nothing")

    local originalBuyer, originalAmount = bill[2].buyer, bill[2].amount
    ok, reason = marker.mark(root, 1, { boss = 2, slot = 3 }, bill, 120, true)
    test.eq(ok, true, "an authorised explicit row selection marks the return")
    test.eq(reason, nil, "successful mark has no failure reason")
    local saved = root.currentSettlement.returns[1]
    test.eq(saved.status, "pending", "new return stays pending until manually cleared")
    test.eq(saved.itemId, 7001, "return stores only the selected item identity")
    test.eq(saved.boss, 2, "return stores the selected bill row")
    test.eq(saved.slot, 3, "return stores the selected bill slot")
    test.eq(saved.player, "买家甲", "return stores the counterparty for current-raid audit")
    test.eq(saved.originalBuyer, "买家甲", "return preserves the original buyer as evidence")
    test.eq(saved.originalAmount, 1200, "return preserves the original amount as evidence")
    test.eq(bill[2].buyer, originalBuyer, "marking never clears the buyer")
    test.eq(bill[2].amount, originalAmount, "marking never changes or refunds the amount")

    local checklist = dofile("Core/BGNext/CurrentSettlementChecklist.lua")
    local report = checklist.evaluate({
        settlement = root.currentSettlement,
        bill = { hasContent = true, rows = bill, summary = {} },
    })
    local returnFinding
    for _, entry in ipairs(report.entries) do
        if entry.category == "return" then returnFinding = entry end
    end
    test.eq(returnFinding ~= nil, true, "a pending return is visible in the settlement checklist")
    test.eq(returnFinding.locate.fb, "ICC", "the return warning points at the current bill")
    test.eq(returnFinding.locate.boss, 2, "the return warning points at the selected boss")
    test.eq(returnFinding.locate.slot, 3, "the return warning points at the selected row")

    test.eq(marker.clear(root, 1, true), true, "leader can manually clear the pending return")
    test.eq(root.currentSettlement.returns[1].status, "cleared", "clear keeps a brief current-raid audit fact")

    root.currentSettlement.returns = {
        { tradeIndex = 1, itemId = 7001, boss = 2, slot = 3, player = "买家甲",
            originalBuyer = "买家甲", originalAmount = 1200, time = 120,
            status = "pending", secret = "discard" },
        { tradeIndex = "bad", itemId = 7001, boss = 2, slot = 3, player = "买家甲",
            time = 120, status = "pending" },
    }
    marker.ensure(root)
    test.eq(#root.currentSettlement.returns, 1, "invalid persisted return markers are discarded")
    test.eq(root.currentSettlement.returns[1].secret, nil, "return markers are rebuilt from a field whitelist")

    life.clearSettlement(root)
    test.eq(#root.currentSettlement.returns, 0, "manual settlement clear removes return markers")
end
