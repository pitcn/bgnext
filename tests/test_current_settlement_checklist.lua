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

    local function addMail(root, player, amount, status, time)
        return mail.append(root, {
            raidId = root.currentSettlement.raidId,
            player = player, itemId = nil, amount = amount,
            time = time or NOW, status = status or "sent", direction = "outgoing",
        })
    end

    local function bill(rows, summary)
        return {
            hasContent = true,
            rows = rows or {},
            summary = summary or { splitCount = "40", netIncome = "1000" },
        }
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
        { boss = 1, slot = 1, item = "[装备一]", buyer = "买家甲", amount = "100" },
        { boss = 1, slot = 2, item = "[装备二]", buyer = "买家乙", amount = "", debt = 300 },
        { boss = 2, slot = 1, item = "[装备三]", buyer = "", amount = "50" },
        { boss = 2, slot = 2, item = "[装备四]", buyer = "", amount = "abc" },
    }
    report = checklist.evaluate({
        settlement = root.currentSettlement,
        bill = bill(rows, { splitCount = "40", netIncome = "1000" }),
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
        bill = bill({}, { splitCount = "abc", netIncome = "-50" }),
    })
    test.eq(#entries(report, "issue", "summary"), 2, "invalid count and negative income are anomalies")
    report = checklist.evaluate({
        settlement = root.currentSettlement,
        bill = bill({ { boss = 1, slot = 1, item = "[装备一]", buyer = "甲", amount = "100" } },
            { splitCount = "40", netIncome = "0" }),
    })
    test.eq(entries(report, "pending", "summary")[1] ~= nil, true, "zero net income with sales stays pending")
    report = checklist.evaluate({
        settlement = root.currentSettlement,
        bill = bill({}, { splitCount = "40", netIncome = nil }),
    })
    test.eq(entries(report, "pending", "summary")[1] ~= nil, true, "missing net income stays pending")

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

    -- 7. mails: pending records and sold items without any mail evidence
    root = newRoot()
    beginSettlement(root, "ICC")
    -- One trade carrying two copies of the same item id: one evidence unit.
    addTrade(root, "买家甲", 7001, 100, "complete", NOW)
    addTrade(root, "买家甲", 7001, nil, "complete", NOW)
    -- Two separate trades to another buyer.
    addTrade(root, "买家乙", 7002, 200, "complete", NOW + 10)
    addTrade(root, "买家乙", 7003, 300, "complete", NOW + 20)
    -- A buyer whose wage mail is already recorded.
    addTrade(root, "买家丙", 7004, 400, "complete", NOW + 30)
    addMail(root, "买家丙", 400, "sent", NOW + 40)
    addMail(root, "买家丁", 50, "pending", NOW + 50)
    report = checklist.evaluate({ settlement = root.currentSettlement, bill = bill() })
    local pendingMails = entries(report, "pending", "mail")
    test.eq(#pendingMails, 3, "unmailed buyers and pending mail records are grouped")
    local counts = {}
    for _, entry in ipairs(pendingMails) do
        counts[entry.args[1]] = entry.args[2] or "record"
    end
    test.eq(counts["买家甲"], "1", "one trade with duplicate item ids counts once")
    test.eq(counts["买家乙"], "2", "two separate trades count twice")
    test.eq(counts["买家丁"], "record", "a pending mail record is its own entry")
    test.eq(counts["买家丙"], nil, "a buyer with a mail record is not flagged")

    -- 8. everything checked and confirmed reads as ready
    root = newRoot()
    beginSettlement(root, "ICC")
    addTrade(root, "买家甲", 7001, 100, "complete")
    addMail(root, "买家甲", 100, "sent")
    report = checklist.evaluate({
        settlement = root.currentSettlement,
        bill = bill({ { boss = 1, slot = 1, item = "[装备一]", buyer = "买家甲", amount = "100" } },
            { splitCount = "40", netIncome = "100" }),
    })
    test.eq(report.status, "ready", "evidence-complete checklist is ready")
    test.eq(report.total, 0, "ready has no entries")

    -- 9. an anomaly wins over pending, both are counted
    root = newRoot()
    beginSettlement(root, "ICC")
    addTrade(root, "买家甲", 7001, 100, "complete")
    report = checklist.evaluate({
        settlement = root.currentSettlement,
        bill = bill({ { boss = 1, slot = 1, item = "[装备一]", buyer = "", amount = "", debt = 500 } },
            { splitCount = "40", netIncome = "100" }),
    })
    test.eq(report.status, "issues", "an anomaly blocks the ready status")
    test.eq(report.issueCount, 2, "debt and missing buyer/amount are counted")
    test.eq(report.pendingCount, 1, "the unmailed buyer stays pending")
    test.eq(report.total, 3, "the total covers anomalies and pending items")

    -- 10. the collect adapter reads the real bill shapes with gold units
    root = newRoot()
    beginSettlement(root, "ICC")
    addTrade(root, "买家甲", 7001, 100, "pending")
    local tableData = {
        boss1 = { zhuangbei1 = " [装备一] ", maijia1 = "买家甲", jine1 = "100" },
        boss2 = { zhuangbei1 = "[装备二]", maijia1 = "买家乙", jine1 = "", qiankuan1 = 300 },
        boss4 = { jine3 = "500", jine4 = "40" },
    }
    local input = checklist.collect({
        db = root,
        fb = "ICC",
        table = tableData,
        bosses = 2,
        slotsOf = function(fb, b) return b == 1 and 1 or 2 end,
        now = NOW + 60,
    })
    test.eq(input.settlement ~= nil, true, "live settlement is collected")
    test.eq(#input.bill.rows, 3, "bill rows follow the per-boss slot counts")
    test.eq(input.bill.rows[1].item, "[装备一]", "item text keeps its stored value")
    test.eq(input.bill.rows[2].debt, 300, "debt is read as a number in gold")
    test.eq(input.bill.rows[2].amount, "", "amount stays the stored text")
    test.eq(input.bill.summary.splitCount, "40", "split count comes from the summary row")
    test.eq(input.bill.summary.netIncome, "500", "net income comes from the summary row")
    test.eq(input.fb, "ICC", "locate targets use the collected table")
    report = checklist.evaluate(input)
    test.eq(report.status, "issues", "collected input evaluates to the real anomalies")
    test.eq(#entries(report, "issue", "debt"), 1, "collected debt is flagged")

    -- 11. expired settlements are dropped before evaluating
    root = newRoot()
    beginSettlement(root, "ICC")
    root.currentSettlement.expiresAt = NOW - 1
    input = checklist.collect({ db = root, fb = "ICC", now = NOW })
    test.eq(input.settlement, nil, "expired settlement is not evaluated")
    report = checklist.evaluate(input)
    test.eq(report.status, "pending", "expired settlement stays pending")

    -- 12. a different raid table without bill data stays pending
    root = newRoot()
    beginSettlement(root, "ICC")
    addTrade(root, "买家甲", 7001, 100, "complete")
    input = checklist.collect({ db = root, fb = "ICC", table = nil, now = NOW + 60 })
    report = checklist.evaluate(input)
    test.eq(entries(report, "pending", "bill")[1] ~= nil, true, "cleared raid table stays pending")
    test.eq(report.status, "pending", "missing raid table never reads as ready")

    -- 13. locate resolution never fakes a jump
    test.eq(checklist.resolveLocate({ type = "window", kind = "trade", filter = "pending" }, "ICC").window, "trade",
        "window locate resolves")
    test.eq(checklist.resolveLocate({ type = "table", fb = "ICC" }, "TOC").table, "ICC",
        "table locate resolves for another table")
    test.eq(checklist.resolveLocate({ type = "table", fb = "ICC" }, "ICC"), nil,
        "same-table locate offers no fake jump")
    test.eq(checklist.resolveLocate(nil, "ICC"), nil, "missing locate resolves to nothing")
    test.eq(checklist.resolveLocate({ type = "window" }, "ICC").window, "trade",
        "window locate defaults to the trade record")

    -- 14. the ready status has its own color and the report stays memory-only
    local r, g, b = checklist.statusColor("ready")
    test.eq(r ~= g, true, "ready color differs from its channels")
    test.eq(checklist.statusColor("pending"), checklist.statusColor("unknown"), "unknown falls back to pending gold")

    -- 15. the module stays read-only: no send, inbox, history or timer paths
    local file = assert(io.open("Core/BGNext/CurrentSettlementChecklist.lua", "rb"))
    local source = file:read("*a")
    file:close()
    for _, forbidden in ipairs({
        "SendChatMessage", "SendAddonMessage", "C_ChatInfo", "GetInboxText",
        "tradeHistory", "mailHistory", "BiaoGe.History", "C_Timer", "OnUpdate",
        "SetCartItemList",
    }) do
        test.eq(source:find(forbidden, 1, true), nil, "checklist stays read-only: " .. forbidden)
    end
end
