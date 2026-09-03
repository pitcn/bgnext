return function(test)
    BG = { BGNext = {} }
    local life = dofile("Core/BGNext/DataLifecycle.lua")
    local trade = dofile("Core/BGNext/CurrentTrade.lua")
    local mail = dofile("Core/BGNext/CurrentMail.lua")
    dofile("Core/BGNext/CurrentSettlementView.lua")
    local checklist = dofile("Core/BGNext/CurrentSettlementChecklist.lua")

    local NOW = 1000000
    local function newRoot()
        return life.ensureRoot({})
    end

    local function beginSettlement(root, sourceFb)
        life.beginSettlement(root, sourceFb .. "@123", NOW, { fb = sourceFb, realm = "realm" })
        return root.currentSettlement
    end

    -- Straight through the real whitelist stores so the checklist sees the
    -- exact record shapes the runtime writes.
    local function addTrade(root, player, itemId, amount, status, time, raidId)
        return trade.append(root, {
            raidId = raidId or root.currentSettlement.raidId,
            player = player, itemId = itemId, amount = amount,
            time = time or NOW, status = status,
        })
    end

    local function addMail(root, player, amount, status, time, direction)
        return mail.append(root, {
            raidId = root.currentSettlement.raidId,
            player = player, itemId = nil, amount = amount,
            time = time or NOW, status = status or "sent", direction = direction or "outgoing",
        })
    end

    local function saleRow(boss, slot, itemId, item, buyer, amount, debt)
        return { boss = boss, slot = slot, itemId = itemId, item = item, buyer = buyer, amount = amount, debt = debt }
    end

    local function bill(rows, summary)
        rows = rows or {}
        summary = summary or { splitCount = "40", netIncome = "1000", wage = "25.00" }
        return { hasContent = true, rows = rows, summary = summary }
    end

    local function entries(report, severity, category)
        local found = {}
        for _, entry in ipairs(report.entries) do
            if (severity == nil or entry.severity == severity)
                and (category == nil or entry.category == category) then
                found[#found + 1] = entry
            end
        end
        return found
    end

    -- 1. no settlement at all must stay pending and never claim readiness
    local report = checklist.evaluate({})
    test.eq(report.status, "pending", "no settlement stays pending")
    test.eq(entries(report, "pending", "settlement")[1] ~= nil, true, "missing settlement is reported")
    test.eq(report.issueCount, 0, "no settlement invents no anomaly")

    -- 2. a settlement without any recorded evidence stays pending
    local root = newRoot()
    beginSettlement(root, "ICC")
    report = checklist.evaluate({ settlement = root.currentSettlement, bill = bill() })
    test.eq(entries(report, "pending", "settlement")[1] ~= nil, true, "empty settlement stays pending")

    -- 3. sold-but-unconfirmed trades are issues with a real locate target
    addTrade(root, "买家甲", 7001, 100, "pending")
    addTrade(root, "买家乙", 7002, 200, "complete")
    report = checklist.evaluate({ settlement = root.currentSettlement, bill = bill() })
    local pendingTrades = entries(report, "issue", "trade")
    test.eq(#pendingTrades, 1, "only the unconfirmed trade is flagged")
    test.eq(pendingTrades[1].args[1], "买家甲", "unconfirmed trade names the counterparty")
    test.eq(pendingTrades[1].locate.type, "window", "unconfirmed trade locates to a window")
    test.eq(pendingTrades[1].locate.kind, "trade", "unconfirmed trade locates to the trade record")
    test.eq(pendingTrades[1].locate.filter, "pending", "unconfirmed trade locates with the pending filter")

    -- 4. debts, missing buyers and missing amounts come from the bill rows
    local rows = {
        saleRow(1, 1, 7001, "[装备一]", "买家甲", "100"),
        saleRow(1, 2, 7002, "[装备二]", "买家乙", "", 300),
        saleRow(2, 1, 7003, "[装备三]", "", "50"),
        saleRow(2, 2, 7004, "[装备四]", "", "abc"),
    }
    report = checklist.evaluate({
        settlement = root.currentSettlement,
        bill = bill(rows, { splitCount = "40", netIncome = "1000", wage = "25.00" }),
        fb = "ICC",
    })
    local debts = entries(report, "issue", "debt")
    test.eq(#debts, 1, "one debt row is flagged once")
    test.eq(debts[1].args[1], "300", "debt reports the stored gold amount")
    test.eq(debts[1].args[2], "1", "debt reports the boss index")
    test.eq(debts[1].args[3], "2", "debt reports the slot index")
    test.eq(debts[1].locate.type, "table", "debt locates to the bill table")
    test.eq(debts[1].locate.fb, "ICC", "debt locates to the raid table")
    local billIssues = entries(report, "issue", "bill")
    test.eq(#billIssues, 3, "missing buyer, missing amount and both are flagged")
    test.eq(billIssues[1].args[1], "1", "missing amount names the boss")
    test.eq(billIssues[1].args[2], "2", "missing amount names the slot")
    test.eq(billIssues[2].args[1], "2", "missing buyer names the boss")
    test.eq(billIssues[2].args[2], "1", "missing buyer names the slot")
    test.eq(billIssues[3].args[1], "2", "both-missing names the boss")
    test.eq(billIssues[3].args[2], "2", "both-missing names the slot")

    -- 5. split count and wage summary anomalies
    report = checklist.evaluate({
        settlement = root.currentSettlement,
        bill = bill({}, { splitCount = "0", netIncome = "100" }),
    })
    test.eq(entries(report, "issue", "summary")[1] ~= nil, true, "zero split count is an anomaly")
    report = checklist.evaluate({
        settlement = root.currentSettlement,
        bill = bill({}, { splitCount = nil, netIncome = "100" }),
    })
    test.eq(entries(report, "issue", "summary")[1] ~= nil, true, "missing split count is an anomaly")
    report = checklist.evaluate({
        settlement = root.currentSettlement,
        bill = bill({}, { splitCount = "2.5", netIncome = "100" }),
    })
    test.eq(#entries(report, "issue", "summary"), 1, "a fractional split count is an anomaly")
    report = checklist.evaluate({
        settlement = root.currentSettlement,
        bill = bill({}, { splitCount = "inf", netIncome = "100" }),
    })
    test.eq(#entries(report, "issue", "summary"), 1, "a non-finite split count is an anomaly")
    report = checklist.evaluate({
        settlement = root.currentSettlement,
        bill = bill({}, { splitCount = "abc", netIncome = "-50" }),
    })
    test.eq(#entries(report, "issue", "summary"), 2, "invalid count and negative income are anomalies")
    report = checklist.evaluate({
        settlement = root.currentSettlement,
        bill = bill({ saleRow(1, 1, 7001, "[装备一]", "买家甲", "100") },
            { splitCount = "40", netIncome = "0" }),
    })
    test.eq(entries(report, "pending", "summary")[1] ~= nil, true, "zero net income with sales stays pending")
    report = checklist.evaluate({
        settlement = root.currentSettlement,
        bill = bill({}, { splitCount = "40", netIncome = nil }),
    })
    test.eq(entries(report, "pending", "summary")[1] ~= nil, true, "missing net income stays pending")

    -- 5b. the displayed wage must match BG.GetWages and its rounding policy
    report = checklist.evaluate({
        settlement = root.currentSettlement,
        bill = bill({}, { splitCount = "40", netIncome = "100", wage = "2.50" }),
    })
    test.eq(#entries(report, "pending", "summary"), 0, "a consistent displayed wage passes")
    report = checklist.evaluate({
        settlement = root.currentSettlement,
        bill = bill({}, { splitCount = "40", netIncome = "100", wage = "30.00" }),
    })
    test.eq(#entries(report, "pending", "summary"), 1, "a stale displayed wage stays pending")
    report = checklist.evaluate({
        settlement = root.currentSettlement,
        bill = bill({}, { splitCount = "40", netIncome = "100", wage = "2" }),
    })
    local wageInput = report.entries[1]
    test.eq(wageInput == nil, false, "wage mismatch found")
    report = checklist.evaluate({
        settlement = root.currentSettlement,
        bill = bill({}, { splitCount = "40", netIncome = "100", wage = "2", moLing = true }),
    })
    test.eq(#entries(report, "pending", "summary"), 0, "moLing rounds the expected wage down")
    report = checklist.evaluate({
        settlement = root.currentSettlement,
        bill = bill({}, { splitCount = "40", netIncome = "100", wage = nil }),
    })
    test.eq(#entries(report, "pending", "summary"), 1, "a missing displayed wage stays pending")

    -- 6. bill data gaps stay pending instead of passing
    root = newRoot()
    beginSettlement(root, "ICC")
    report = checklist.evaluate({ settlement = root.currentSettlement, bill = nil })
    test.eq(entries(report, "pending", "bill")[1] ~= nil, true, "unavailable bill stays pending")
    report = checklist.evaluate({
        settlement = root.currentSettlement,
        bill = { hasContent = false, rows = {}, summary = { splitCount = "40", netIncome = "0" } },
    })
    test.eq(entries(report, "pending", "bill")[1] ~= nil, true, "empty bill stays pending")
    test.eq(report.status, "pending", "empty bill never reads as ready")

    -- 7. sold bill rows need proven outgoing delivery, not just an
    --    item/name match; fixtures use the real recorder projection
    local runtime = dofile("Core/BGNext/CurrentSettlementRuntime.lua")
    local function tradesOf(trade)
        return runtime.tradeRows(trade)
    end

    -- 7a. a correct sale with matching gold is proven and stays ready
    root = newRoot()
    beginSettlement(root, "ICC")
    report = checklist.evaluate({
        settlement = { trades = tradesOf({
            completed = true, target = "买家甲", targetmoney = 1000, targetitems = {},
            playeritems = { { itemId = 7001, count = 1 } },
        }), mails = {} },
        bill = bill({ saleRow(1, 1, 7001, "[装备一]", "买家甲", "1000") },
            { splitCount = "1", netIncome = "1000", wage = "1000.00" }),
    })
    test.eq(report.status, "ready", "a proven delivered sale reads as ready")
    test.eq(#entries(report, nil, "sold"), 0, "a proven sale needs no finding")

    for _, count in ipairs({ 2, false }) do
        report = checklist.evaluate({
            settlement = { trades = tradesOf({
                completed = true, target = "买家甲", targetmoney = 1000,
                playeritems = { { itemId = 7001, count = count or nil } },
            }), mails = {} },
            bill = bill({ saleRow(1, 1, 7001, "[装备一]", "买家甲", "1000") },
                { splitCount = "1", netIncome = "1000", wage = "1000.00" }),
        })
        test.eq(report.status ~= "ready", true, "stacked or unknown quantity blocks readiness")
    end

    -- 7b. an inbound purchase can never confirm a bill sale (review repro 1)
    root = newRoot()
    beginSettlement(root, "ICC")
    report = checklist.evaluate({
        settlement = { trades = tradesOf({
            completed = true, target = "买家甲", playermoney = 100, targetmoney = 0,
            targetitems = { { itemId = 7001, count = 1 } }, playeritems = {},
        }), mails = {} },
        bill = bill({ saleRow(1, 1, 7001, "[装备一]", "买家甲", "1000") },
            { splitCount = "1", netIncome = "1000", wage = "1000.00" }),
    })
    test.eq(report.status ~= "ready", true, "an inbound purchase blocks readiness")
    sold = entries(report, "pending", "sold")
    test.eq(#sold, 1, "the bill sale has no outgoing delivery evidence")
    test.eq(sold[1].args[1], "1", "unproven sale names the boss")
    test.eq(sold[1].args[2], "1", "unproven sale names the slot")

    -- 7c. short payment: delivered but underpaid stays pending (review repro 2)
    root = newRoot()
    beginSettlement(root, "ICC")
    report = checklist.evaluate({
        settlement = { trades = tradesOf({
            completed = true, target = "买家甲", targetmoney = 1, targetitems = {},
            playeritems = { { itemId = 7001, count = 1 } },
        }), mails = {} },
        bill = bill({ saleRow(1, 1, 7001, "[装备一]", "买家甲", "1000") },
            { splitCount = "1", netIncome = "1000", wage = "1000.00" }),
    })
    test.eq(report.status ~= "ready", true, "a short payment blocks readiness")
    sold = entries(report, "pending", "sold")
    test.eq(#sold, 1, "the underpaid sale is flagged")
    test.eq(sold[1].args[1], "1", "short payment names the received gold")
    test.eq(sold[1].args[2], "1000", "short payment names the bill gold")

    -- 7d. packed trades share one amount: per-item proof stays pending
    root = newRoot()
    beginSettlement(root, "ICC")
    report = checklist.evaluate({
        settlement = { trades = tradesOf({
            completed = true, target = "买家甲", targetmoney = 2000, targetitems = {},
            playeritems = { { itemId = 7001, count = 1 }, { itemId = 7002, count = 1 } },
        }), mails = {} },
        bill = bill({
            saleRow(1, 1, 7001, "[装备一]", "买家甲", "1000"),
            saleRow(1, 2, 7002, "[装备二]", "买家甲", "1000"),
        }, { splitCount = "1", netIncome = "2000", wage = "2000.00" }),
    })
    test.eq(report.status ~= "ready", true, "packed shared amounts cannot prove each item")
    sold = entries(report, "pending", "sold")
    test.eq(#sold, 2, "both packed items stay pending")
    test.eq(sold[1].args[1], "1", "shared-amount finding names the boss")
    test.eq(sold[1].args[2], "1", "shared-amount finding names the first slot")
    test.eq(sold[2].args[2], "2", "shared-amount finding names the second slot")

    -- 7e. records without a direction (older shape) cannot prove delivery
    root = newRoot()
    beginSettlement(root, "ICC")
    report = checklist.evaluate({
        settlement = { trades = { {
            player = "买家甲", itemId = 7001, amount = 1000,
            time = NOW, status = "complete",
        } }, mails = {} },
        bill = bill({ saleRow(1, 1, 7001, "[装备一]", "买家甲", "1000") },
            { splitCount = "1", netIncome = "1000", wage = "1000.00" }),
    })
    test.eq(report.status ~= "ready", true, "a direction-less record blocks readiness")
    sold = entries(report, "pending", "sold")
    test.eq(#sold, 1, "the direction-less sale is flagged for review")

    -- 7f. surplus delivered sales beyond the bill stay pending
    root = newRoot()
    beginSettlement(root, "ICC")
    report = checklist.evaluate({
        settlement = { trades = tradesOf({
            completed = true, target = "买家甲", targetmoney = 1000, targetitems = {},
            playeritems = { { itemId = 7001, count = 1 }, { itemId = 7001, count = 1 } },
        }), mails = {} },
        bill = bill({ saleRow(1, 1, 7001, "[装备一]", "买家甲", "1000") },
            { splitCount = "1", netIncome = "1000", wage = "1000.00" }),
    })
    test.eq(report.status ~= "ready", true, "a delivered sale missing from the bill blocks readiness")
    sold = entries(report, "pending", "sold")
    test.eq(#sold, 2, "the shared amount and the uncovered delivery are flagged")
    test.eq(sold[1].reasonKey, "对应交易为多件共享金额或对应关系不唯一，无法确认该件实收（第%s个Boss 第%s件）",
        "the duplicate sale cannot be proven against the packed trade")
    test.eq(sold[2].reasonKey, "存在未被账单核对的已完成交易记录（共%s笔），请人工核对是否漏记",
        "the surplus finding names the uncovered delivery")

    -- 7g. an unidentifiable bill item cannot use trade evidence
    root = newRoot()
    beginSettlement(root, "ICC")
    report = checklist.evaluate({
        settlement = { trades = tradesOf({
            completed = true, target = "买家甲", targetmoney = 100, targetitems = {},
            playeritems = { { itemId = 7001, count = 1 } },
        }), mails = {} },
        bill = bill({ saleRow(1, 1, nil, "[神秘物品]", "买家甲", "100") },
            { splitCount = "1", netIncome = "100", wage = "100.00" }),
    })
    sold = entries(report, "pending", "sold")
    test.eq(#sold, 2, "an unidentifiable item and its uncovered delivery are flagged")
    test.eq(sold[1].reasonKey, "账单装备无法识别，无法核对交易证据（第%s个Boss 第%s件）",
        "the unidentifiable row is flagged")
    test.eq(sold[2].reasonKey, "存在未被账单核对的已完成交易记录（共%s笔），请人工核对是否漏记",
        "the delivered item cannot be matched to any bill row")

    -- 7h. gold on both sides is ambiguous and can never prove a bill sale
    root = newRoot()
    beginSettlement(root, "ICC")
    report = checklist.evaluate({
        settlement = { trades = tradesOf({
            completed = true, target = "买家甲", targetmoney = 1000, playermoney = 500,
            playeritems = { { itemId = 7001, count = 1 } },
        }), mails = {} },
        bill = bill({ saleRow(1, 1, 7001, "[装备一]", "买家甲", "1000") },
            { splitCount = "1", netIncome = "1000", wage = "1000.00" }),
    })
    test.eq(report.status ~= "ready", true, "a both-gold trade blocks readiness")
    sold = entries(report, "pending", "sold")
    test.eq(#sold, 1, "the both-gold delivery has no sale evidence")

    -- 7i. a single record with a known quantity above one is a shared delivery
    --     and can never prove a single bill row on its own.
    root = newRoot()
    beginSettlement(root, "ICC")
    report = checklist.evaluate({
        settlement = { trades = { {
            player = "买家甲", itemId = 7001, amount = 1000, time = NOW,
            status = "complete", direction = "outgoing", quantity = 2,
        } }, mails = {} },
        bill = bill({ saleRow(1, 1, 7001, "[装备一]", "买家甲", "1000") },
            { splitCount = "1", netIncome = "1000", wage = "1000.00" }),
    })
    test.eq(report.status ~= "ready", true, "a two-item delivery cannot prove a single sale")
    sold = entries(report, "pending", "sold")
    test.eq(#sold, 2, "the shared delivery and its uncovered second item are flagged")
    test.eq(sold[1].reasonKey, "对应交易为多件共享金额或对应关系不唯一，无法确认该件实收（第%s个Boss 第%s件）",
        "a quantity above one is treated as a shared delivery")
    test.eq(sold[2].reasonKey, "存在未被账单核对的已完成交易记录（共%s笔），请人工核对是否漏记",
        "the uncovered second item is surfaced as surplus")

    -- 7j. a legacy record without a quantity cannot masquerade as one settled item
    root = newRoot()
    beginSettlement(root, "ICC")
    report = checklist.evaluate({
        settlement = { trades = { {
            player = "买家甲", itemId = 7001, amount = 1000, time = NOW,
            status = "complete", direction = "outgoing",
        } }, mails = {} },
        bill = bill({ saleRow(1, 1, 7001, "[装备一]", "买家甲", "1000") },
            { splitCount = "1", netIncome = "1000", wage = "1000.00" }),
    })
    test.eq(report.status ~= "ready", true, "an unknown-quantity record cannot prove a settled sale")
    sold = entries(report, "pending", "sold")
    test.eq(#sold, 1, "the unknown-quantity delivery is flagged for review")

    -- 8. mail records are judged by status and direction, never by buyer身份
    root = newRoot()
    beginSettlement(root, "ICC")
    addTrade(root, "买家甲", 7001, 100, "complete")
    addMail(root, "买家乙", 200, "failed")
    addMail(root, "买家丙", 300, "pending")
    mail.append(root, {
        raidId = root.currentSettlement.raidId, player = "买家丁", itemId = nil,
        amount = 400, time = NOW + 40, status = "sent",
    })
    report = checklist.evaluate({ settlement = root.currentSettlement, bill = bill() })
    test.eq(entries(report, "pending", "mail")[1] ~= nil, true, "the wage-mail flow stays pending-free of buyer inference")
    local mailEntries = entries(report, "pending", "mail")
    test.eq(#mailEntries, 3, "failed, pending and direction-less mails are surfaced")
    test.eq(mailEntries[1].args[1], "买家乙", "failed mail names its recipient")
    test.eq(mailEntries[2].args[1], "买家丙", "pending mail names its recipient")
    test.eq(mailEntries[3].args[1], "买家丁", "direction-less mail names its recipient")
    for _, entry in ipairs(report.entries) do
        test.eq(entry.args[1] == "买家甲", false, "no mail obligation is inferred from being a buyer")
    end

    -- 9. everything checked and confirmed reads as ready
    root = newRoot()
    beginSettlement(root, "ICC")
    report = checklist.evaluate({
        settlement = { trades = tradesOf({
            completed = true, target = "买家甲", targetmoney = 100, targetitems = {},
            playeritems = { { itemId = 7001, count = 1 } },
        }), mails = {} },
        bill = bill({ saleRow(1, 1, 7001, "[装备一]", "买家甲", "100") },
            { splitCount = "1", netIncome = "100", wage = "100.00" }),
    })
    test.eq(report.status, "ready", "evidence-complete checklist is ready")
    test.eq(report.total, 0, "ready has no entries")
    -- 10. an anomaly wins over pending, both are counted
    root = newRoot()
    beginSettlement(root, "ICC")
    addTrade(root, "买家甲", 7001, 100, "complete")
    report = checklist.evaluate({
        settlement = root.currentSettlement,
        bill = bill({ saleRow(1, 1, 7001, "[装备一]", "", "", 500) },
            { splitCount = "40", netIncome = "100", wage = "2.50" }),
    })
    test.eq(report.status, "issues", "an anomaly blocks the ready status")
    test.eq(report.issueCount, 2, "debt and missing buyer/amount are counted")
    test.eq(report.pendingCount, 0, "an unsold row without buyer needs no mail evidence")
    test.eq(report.total, 2, "the total covers anomalies and pending items")

    -- 11. the collect adapter reads the real bill shapes with gold units
    root = newRoot()
    beginSettlement(root, "ICC")
    addTrade(root, "买家甲", 7001, 100, "pending")
    local tableData = {
        boss1 = { zhuangbei1 = " [装备一] ", maijia1 = "买家甲", jine1 = "100" },
        boss2 = { zhuangbei1 = "[装备二]", maijia1 = "买家乙", jine1 = "", qiankuan1 = 300 },
        boss4 = { jine3 = "500", jine4 = "40", jine5 = "12.50" },
    }
    local input = checklist.collect({
        db = root,
        fb = "ICC",
        table = tableData,
        bosses = 2,
        slotsOf = function(fb, b) return b == 1 and 1 or 2 end,
        itemIdOf = function(text) return text == " [装备一] " and 7001 or 7002 end,
        now = NOW + 60,
    })
    test.eq(input.settlement ~= nil, true, "live settlement is collected")
    test.eq(#input.bill.rows, 3, "bill rows follow the per-boss slot counts")
    test.eq(input.bill.rows[1].item, "[装备一]", "item text keeps its stored value")
    test.eq(input.bill.rows[1].itemId, 7001, "item ids are projected for matching")
    test.eq(input.bill.rows[2].debt, 300, "debt is read as a number in gold")
    test.eq(input.bill.rows[2].amount, "", "amount stays the stored text")
    test.eq(input.bill.summary.splitCount, "40", "split count comes from the summary row")
    test.eq(input.bill.summary.netIncome, "500", "net income comes from the summary row")
    test.eq(input.bill.summary.wage, "12.50", "the displayed wage comes from the summary row")
    test.eq(input.fb, "ICC", "locate targets use the collected table")
    test.eq(input.scopeMismatch, nil, "matching scopes collect normally")
    report = checklist.evaluate(input)
    test.eq(report.status, "issues", "collected input evaluates to the real anomalies")
    test.eq(#entries(report, "issue", "debt"), 1, "collected debt is flagged")

    -- 12. expired settlements are dropped before evaluating
    root = newRoot()
    beginSettlement(root, "ICC")
    root.currentSettlement.expiresAt = NOW - 1
    input = checklist.collect({ db = root, fb = "ICC", now = NOW })
    test.eq(input.settlement, nil, "expired settlement is not evaluated")
    report = checklist.evaluate(input)
    test.eq(report.status, "pending", "expired settlement stays pending")

    -- 13. a different raid identity with populated bill data is rejected
    root = newRoot()
    beginSettlement(root, "ICC")
    addTrade(root, "买家甲", 7001, 100, "complete")
    input = checklist.collect({
        db = root, fb = "TOC", now = NOW + 60,
        table = { boss1 = { zhuangbei1 = "[装备一]", maijia1 = "买家甲", jine1 = "100" } },
        bosses = 1,
        slotsOf = function() return 1 end,
        itemIdOf = function() return 7001 end,
    })
    test.eq(input.scopeMismatch, true, "scope mismatch is collected")
    test.eq(input.bill, nil, "a mismatched bill is not evaluated")
    report = checklist.evaluate(input)
    test.eq(entries(report, "pending", "bill")[1] ~= nil, true, "scope mismatch stays pending")
    test.eq(report.status, "pending", "cross-raid data never reads as ready")

    -- 14. a cleared raid table stays pending
    root = newRoot()
    beginSettlement(root, "ICC")
    addTrade(root, "买家甲", 7001, 100, "complete")
    input = checklist.collect({ db = root, fb = "ICC", table = nil, now = NOW + 60 })
    report = checklist.evaluate(input)
    test.eq(entries(report, "pending", "bill")[1] ~= nil, true, "cleared raid table stays pending")
    test.eq(report.status, "pending", "missing raid table never reads as ready")

    -- 15. locate resolution never fakes a jump
    test.eq(checklist.resolveLocate({ type = "window", kind = "trade", filter = "pending" }, "ICC").window, "trade",
        "window locate resolves")
    test.eq(checklist.resolveLocate({ type = "table", fb = "ICC" }, "TOC").table, "ICC",
        "table locate resolves for another table")
    test.eq(checklist.resolveLocate({ type = "table", fb = "ICC" }, "ICC"), nil,
        "same-table locate offers no fake jump")
    test.eq(checklist.resolveLocate(nil, "ICC"), nil, "missing locate resolves to nothing")
    test.eq(checklist.resolveLocate({ type = "window" }, "ICC").window, "trade",
        "window locate defaults to the trade record")

    -- 16. the ready status has its own color and the report stays memory-only
    local r, g, b = checklist.statusColor("ready")
    test.eq(r ~= g, true, "ready color differs from its channels")
    test.eq(checklist.statusColor("pending"), checklist.statusColor("unknown"), "unknown falls back to pending gold")

    -- 17. the module stays read-only: no send, inbox, history or timer paths
    local file = assert(io.open("Core/BGNext/CurrentSettlementChecklist.lua", "rb"))
    local source = file:read("*a")
    file:close()
    for _, forbidden in ipairs({
        "SendChatMessage", "SendAddonMessage", "C_ChatInfo", "GetInboxText",
        "tradeHistory", "mailHistory", "BiaoGe.History", "C_Timer", "OnUpdate",
    }) do
        test.eq(source:find(forbidden, 1, true), nil, "checklist stays read-only: " .. forbidden)
    end
end
