return function(test)
    -- =====================================================================
    -- issue #61: trade records must express the actual paid/received facts.
    --
    -- One completed trade becomes ONE grouped transaction record that keeps
    -- both gold directions, both item directions, the counterparty and time,
    -- and two independent dimensions: the trade-completed fact (`completed`)
    -- and the reconciliation state (`status`). Reconcile-pending never negates
    -- the completed fact; 0 is stored and shown as 0; unknown stays nil and
    -- never collapses into 0; a shared total is stored once; two-way gold and
    -- two-way items are never netted. Legacy flat records keep projecting and
    -- checking safely.
    -- =====================================================================

    BG = { BGNext = {} }
    local life = dofile("Core/BGNext/DataLifecycle.lua")
    local trade = dofile("Core/BGNext/CurrentTrade.lua")
    dofile("Core/BGNext/CurrentMail.lua")
    local runtime = dofile("Core/BGNext/CurrentSettlementRuntime.lua")
    local view = dofile("Core/BGNext/CurrentSettlementView.lua")
    local checklist = dofile("Core/BGNext/CurrentSettlementChecklist.lua")

    local function row(tradeInput)
        local rows = runtime.tradeRows(tradeInput)
        return rows[1]
    end

    local function len(list)
        if type(list) ~= "table" then
            return 0
        end
        return #list
    end

    local function itemId(list, index)
        if type(list) ~= "table" or type(list[index]) ~= "table" then
            return nil
        end
        return list[index].itemId
    end

    local function qty(list, index)
        if type(list) ~= "table" or type(list[index]) ~= "table" then
            return nil
        end
        return list[index].quantity
    end

    -- =====================================================================
    -- 1. single item, they pay 500: completed + reconcile-complete, every
    --    fact preserved, and both directions are explicit.
    -- =====================================================================
    local r = row({
        completed = true, target = "甲", targetmoney = 500, playermoney = 0,
        targetitems = {}, playeritems = { { itemId = 11, count = 1 } },
    })
    test.eq(r ~= nil, true, "a completed sale produces one grouped record")
    test.eq(r.completed, true, "the trade-completed fact is explicit")
    test.eq(r.status, "complete", "a clean single sale reconciles as complete")
    test.eq(r.theirGold, 500, "gold they paid is preserved")
    test.eq(r.myGold, 0, "gold I paid is explicitly zero, not nil")
    test.eq(len(r.myItems), 1, "my delivered item is preserved")
    test.eq(itemId(r.myItems, 1), 11, "my delivered item id is preserved")
    test.eq(qty(r.myItems, 1), 1, "my delivered count is preserved")
    test.eq(len(r.theirItems), 0, "they delivered no item")

    -- =====================================================================
    -- 2. single item, both 0 gold: still a completed trade, reconcile-pending,
    --    and the zero gold is explicit (never invented as unknown or dropped).
    -- =====================================================================
    r = row({
        completed = true, target = "乙", targetmoney = 0, playermoney = 0,
        targetitems = {}, playeritems = { { itemId = 22, count = 1 } },
    })
    test.eq(r.completed, true, "a 0-gold delivery is still a completed trade")
    test.eq(r.status, "pending", "a 0-gold delivery reconciles as pending")
    test.eq(r.myGold, 0, "zero gold I paid stays an explicit 0")
    test.eq(r.theirGold, 0, "zero gold they paid stays an explicit 0")
    test.eq(len(r.myItems), 1, "the delivered item survives a 0-gold trade")
    test.eq(itemId(r.myItems, 1), 22, "the 0-gold item id survives")

    -- =====================================================================
    -- 3. I pay 50 they pay 100: both gold directions survive (no netting).
    -- =====================================================================
    r = row({
        completed = true, target = "丙", targetmoney = 100, playermoney = 50,
        targetitems = {}, playeritems = { { itemId = 33, count = 1 } },
    })
    test.eq(r.myGold, 50, "gold I paid survives two-way gold")
    test.eq(r.theirGold, 100, "gold they paid survives two-way gold")
    test.eq(r.status, "pending", "two-way gold cannot prove a single sale")
    test.eq(itemId(r.myItems, 1), 33, "my item survives two-way gold")

    -- =====================================================================
    -- 4. barter, both 0 gold: both item lists preserved (no netting).
    -- =====================================================================
    r = row({
        completed = true, target = "丁", targetmoney = 0, playermoney = 0,
        targetitems = { { itemId = 44, count = 1 } },
        playeritems = { { itemId = 55, count = 1 } },
    })
    test.eq(len(r.myItems), 1, "barter preserves my delivered item")
    test.eq(itemId(r.myItems, 1), 55, "barter preserves my item id")
    test.eq(len(r.theirItems), 1, "barter preserves their delivered item")
    test.eq(itemId(r.theirItems, 1), 44, "barter preserves their item id")
    test.eq(r.status, "pending", "barter is never auto-settled")

    -- =====================================================================
    -- 5. multiple distinct items + one total of 1000: the total is stored
    --    once on the transaction, both items survive.
    -- =====================================================================
    r = row({
        completed = true, target = "戊", targetmoney = 1000, playermoney = 0,
        targetitems = {},
        playeritems = { { itemId = 5, count = 1 }, { itemId = 6, count = 1 } },
    })
    test.eq(r.theirGold, 1000, "the shared total is stored once, not per item")
    test.eq(len(r.myItems), 2, "both delivered items survive the grouped record")
    test.eq(itemId(r.myItems, 1), 5, "first delivered item id survives")
    test.eq(itemId(r.myItems, 2), 6, "second delivered item id survives")

    -- =====================================================================
    -- 6. two identical single slots vs a single count=2 stack: both keep the
    --    count 2, but only the stack cannot prove a single bill sale.
    -- =====================================================================
    local dup = row({
        completed = true, target = "己", targetmoney = 0, playermoney = 0,
        targetitems = {}, playeritems = { { itemId = 11, count = 1 }, { itemId = 11, count = 1 } },
    })
    test.eq(qty(dup.myItems, 1), 2, "two identical slots aggregate their count")
    test.eq(len(dup.myItems), 1, "two identical slots stay one item entry")

    local stack = row({
        completed = true, target = "己", targetmoney = 100, playermoney = 0,
        targetitems = {}, playeritems = { { itemId = 11, count = 2 } },
    })
    test.eq(qty(stack.myItems, 1), 2, "a stack preserves its count")
    test.eq(stack.status, "pending", "a stack cannot prove a single bill sale")

    -- =====================================================================
    -- 7. cancel / unknown / empty trade never fabricates a record.
    -- =====================================================================
    test.eq(#runtime.tradeRows({ completed = false, target = "庚", targetmoney = 100 }), 0,
        "an unfinished trade records nothing")
    test.eq(#runtime.tradeRows({ completed = true, target = "", targetmoney = 100 }), 0,
        "an unnamed trade records nothing")
    test.eq(#runtime.tradeRows({ completed = true, target = "庚", targetmoney = 0, playermoney = 0 }), 0,
        "an empty trade records nothing")

    -- =====================================================================
    -- 8. the whitelist store persists grouped facts and drops free text; 0 is
    --    a valid stored gold value; unknown stays nil.
    -- =====================================================================
    do
        local root = life.ensureRoot({})
        life.beginSettlement(root, "raid-a", 100)
        test.eq(trade.append(root, {
            raidId = "raid-a", player = "甲", time = 101,
            completed = true, status = "complete",
            myGold = 0, theirGold = 500,
            myItems = { { itemId = 11, quantity = 1 } },
            theirItems = {},
            secret = "discard me",
        }), true, "a grouped trade is accepted")
        local stored = root.currentSettlement.trades[1]
        test.eq(stored.secret, nil, "unknown trade field discarded")
        test.eq(stored.completed, true, "completed fact is stored")
        test.eq(stored.myGold, 0, "explicit zero gold is stored")
        test.eq(stored.theirGold, 500, "their gold is stored")
        test.eq(itemId(stored.myItems, 1), 11, "my item is stored")
        test.eq(qty(stored.myItems, 1), 1, "my quantity is stored")

        -- A repeated completion for the same trade is deduplicated.
        test.eq(trade.append(root, {
            raidId = "raid-a", player = "甲", time = 101,
            completed = true, status = "complete",
            myGold = 0, theirGold = 500,
            myItems = { { itemId = 11, quantity = 1 } },
            theirItems = {},
        }), false, "a duplicate grouped trade is rejected")
        test.eq(#root.currentSettlement.trades, 1, "no second record from the duplicate")
    end

    -- =====================================================================
    -- 9. legacy flat records still project (safe-compat): amount/quantity
    --    carried, no fabricated completed fact, no crash.
    -- =====================================================================
    do
        local root = life.ensureRoot({})
        life.beginSettlement(root, "raid-a", 100)
        root.currentSettlement.trades[1] = {
            player = "甲", itemId = 11, amount = 100, time = 101,
            status = "complete", direction = "outgoing", quantity = 1,
        }
        local rows, empty = view.trades(root, { now = 200, dateFn = function(_, t) return "t" .. t end })
        test.eq(empty, false, "legacy trade projects")
        test.eq(#rows, 1, "legacy trade projects one row")
        test.eq(rows[1].player, "甲", "legacy row keeps the counterparty")
        test.eq(rows[1].itemId, 11, "legacy row keeps the item id")
        test.eq(rows[1].quantity, 1, "legacy row keeps the quantity")
        test.eq(rows[1].amountText, "100", "legacy row keeps the amount text")
        test.eq(rows[1].completedKey, nil, "legacy row invents no completed fact")
    end

    -- =====================================================================
    -- 10. the checklist treats a completed trade's reconcile state and its
    --     delivered facts independently.
    -- =====================================================================
    do
        local function sale(boss, slot, itemId, buyer, amount)
            return { boss = boss, slot = slot, itemId = itemId, item = "[" .. itemId .. "]",
                buyer = buyer, amount = amount, debt = nil }
        end
        local function bill(rows)
            return { hasContent = true, rows = rows,
                summary = { splitCount = "1", netIncome = "1000", wage = "1000.00" } }
        end

        -- Clean grouped sale: proven, ready.
        local report = checklist.evaluate({
            settlement = { trades = { {
                player = "买家甲", time = 100, completed = true, status = "complete",
                myGold = 0, theirGold = 1000,
                myItems = { { itemId = 7001, quantity = 1 } }, theirItems = {},
            } }, mails = {} },
            bill = bill({ sale(1, 1, 7001, "买家甲", "1000") }),
        })
        test.eq(report.status, "ready", "a clean grouped sale proves and reads ready")

        -- Reconcile-pending: the unreconciled trade is surfaced as an issue
        -- and readiness is blocked, even though the trade completed.
        report = checklist.evaluate({
            settlement = { trades = { {
                player = "买家甲", time = 100, completed = true, status = "pending",
                myGold = 0, theirGold = 1000,
                myItems = { { itemId = 7001, quantity = 1 } }, theirItems = {},
            } }, mails = {} },
            bill = bill({ sale(1, 1, 7001, "买家甲", "1000") }),
        })
        test.eq(report.status, "issues", "an unreconciled trade is surfaced as an issue")

        -- Both-gold grouped trade never proves the bill sale.
        report = checklist.evaluate({
            settlement = { trades = { {
                player = "买家甲", time = 100, completed = true, status = "pending",
                myGold = 500, theirGold = 1000,
                myItems = { { itemId = 7001, quantity = 1 } }, theirItems = {},
            } }, mails = {} },
            bill = bill({ sale(1, 1, 7001, "买家甲", "1000") }),
        })
        test.eq(report.status ~= "ready", true, "a both-gold trade blocks readiness")
    end
end
