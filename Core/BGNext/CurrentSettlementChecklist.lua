BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Read-only settlement readiness checklist for the single current raid.
--
-- `collect` turns injected database and bill-table snapshots into one input
-- value, `evaluate` derives the report, and neither reads a global: the caller
-- (CurrentSettlementUI) gathers the settlement and the current table, renders
-- the result and owns every locate action. Nothing here writes, sends or
-- schedules; the report exists only while the checklist window shows it.
--
-- Amounts stay in the stored units: bill amounts are gold text, debts are
-- gold numbers, settlement trade amounts are gold numbers. They are never
-- summed per item — one packed trade stays one evidence unit (player + time).
local M = {}

local function trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:match("^%s*(.-)%s*$")
end

local function normalize(input, name)
    local trimmed = trim(name)
    if trimmed == "" then
        return nil
    end
    local fn = input and input.normalizeName
    if type(fn) == "function" then
        local ok, value = pcall(fn, trimmed)
        if ok and type(value) == "string" and value ~= "" then
            return value
        end
    end
    return trimmed
end

local function evaluateTradesAndMails(input, addIssue, addPending)
    local settlement = input.settlement
    local trades, mails = settlement.trades or {}, settlement.mails or {}
    if #trades == 0 and #mails == 0 then
        addPending("settlement", "当前团还没有可核对的交易或邮件记录")
        return
    end

    for _, record in ipairs(trades) do
        if record.status == "pending" then
            addIssue("trade", "交易已记录，尚未核对完成：%s", { tostring(record.player) },
                { type = "window", kind = "trade", filter = "pending" })
        end
    end

    -- Mail records are judged only by their own status and direction. Being a
    -- trade counterparty is not evidence of a mail obligation: the ordinary
    -- pre-distribution flow (wages not mailed yet) must not read as a problem.
    for _, record in ipairs(mails) do
        local player = tostring(record.player)
        if record.status == "failed" then
            addPending("mail", "邮件发送失败：%s", { player }, { type = "window", kind = "mail" })
        elseif record.status ~= "sent" or record.direction ~= "outgoing" then
            addPending("mail", "邮件记录待核对：%s", { player }, { type = "window", kind = "mail" })
        end
    end
end

local function evaluateReturns(input, addIssue)
    for _, marker in ipairs(input.settlement.returns or {}) do
        if marker.status == "pending" then
            addIssue("return", "退货装备尚未处理：%s（第%s个Boss 第%s件），请核对买家、金额与退款",
                { tostring(marker.player), tostring(marker.boss), tostring(marker.slot) },
                { type = "table", fb = input.settlement.sourceFb,
                    boss = marker.boss, slot = marker.slot })
        end
    end
end

-- Reconciles sold bill rows against confirmed trade deliveries. An item/name
-- match alone is never proof: only an outgoing record (the runtime stamps the
-- direction it observed) whose gold equals the bill amount proves the delivery
-- and its payment. Direction-less legacy records, incoming purchases, short
-- payments and packed shared amounts all stay pending, and each evidence row
-- is consumed at most once. Amounts are never apportioned across items.
-- Normalizes one stored trade record into the delivery candidates the bill
-- matcher consumes. A grouped transaction record (the current shape) yields one
-- candidate per delivered item — outgoing from myItems, incoming from theirItems
-- — with the recorded gold on the matching side, but only when the trade is
-- reconciled. A legacy flat record keeps its single item/amount/direction/
-- quantity. A reconcile-pending grouped trade yields no evidence, so its
-- completed fact is never silently treated as a settled sale.
local function recordEvidence(record)
    local evidence = {}
    if type(record) ~= "table" then
        return evidence
    end
    if type(record.completed) == "boolean" or type(record.myItems) == "table"
        or type(record.myGold) == "number" then
        if record.status ~= "complete" then
            return evidence
        end
        if type(record.myItems) == "table" then
            for _, entry in ipairs(record.myItems) do
                evidence[#evidence + 1] = {
                    itemId = entry.itemId,
                    quantity = entry.quantity,
                    direction = "outgoing",
                    amount = record.theirGold,
                }
            end
        end
        if type(record.theirItems) == "table" then
            for _, entry in ipairs(record.theirItems) do
                evidence[#evidence + 1] = {
                    itemId = entry.itemId,
                    quantity = entry.quantity,
                    direction = "incoming",
                    amount = record.myGold,
                }
            end
        end
        return evidence
    end
    if record.status == "complete" and type(record.itemId) == "number" then
        evidence[#evidence + 1] = {
            itemId = record.itemId,
            quantity = record.quantity,
            direction = record.direction,
            amount = tonumber(record.amount),
        }
    end
    return evidence
end

local function evaluateSoldRows(input, addPending)
    -- Group outgoing candidates by trade (player + time) so a packed trade
    -- (several delivered items sharing one gold amount) can be recognised:
    -- the gold is the trade total and can never prove a single bill row's
    -- price.
    local candidates, outgoingByTrade = {}, {}
    for _, record in ipairs(input.settlement.trades or {}) do
        local player = normalize(input, record.player)
        if player then
            local tradeKey = player .. "|" .. tostring(record.time)
            for _, entry in ipairs(recordEvidence(record)) do
                if entry.direction == "outgoing" then
                    outgoingByTrade[tradeKey] = (outgoingByTrade[tradeKey] or 0) + 1
                end
                local key = tostring(entry.itemId) .. "|" .. player
                local list = candidates[key]
                if not list then
                    list = {}
                    candidates[key] = list
                end
                local quantity = type(entry.quantity) == "number"
                    and entry.quantity >= 1 and entry.quantity % 1 == 0
                    and entry.quantity or nil
                list[#list + 1] = {
                    amount = entry.amount,
                    direction = entry.direction,
                    tradeKey = tradeKey,
                    quantity = quantity,
                    remaining = quantity,
                    consumed = false,
                }
            end
        end
    end
    for _, list in pairs(candidates) do
        for _, candidate in ipairs(list) do
            candidate.packed = (outgoingByTrade[candidate.tradeKey] or 0) > 1
                or candidate.quantity == nil
                or (candidate.quantity ~= nil and candidate.quantity > 1)
        end
    end
    for _, row in ipairs(input.bill.rows) do
        local amount = tonumber(row.amount)
        if row.item ~= "" and row.buyer ~= "" and amount ~= nil and amount > 0 then
            local buyer = normalize(input, row.buyer)
            local key = row.itemId and buyer and (tostring(row.itemId) .. "|" .. buyer) or nil
            local location = { tostring(row.boss), tostring(row.slot) }
            if not key then
                addPending("sold", "账单装备无法识别，无法核对交易证据（第%s个Boss 第%s件）", location)
            else
                local list = candidates[key]
                local unconsumedOutgoing = {}
                if list then
                    for _, candidate in ipairs(list) do
                        if not candidate.consumed and candidate.direction == "outgoing" then
                            unconsumedOutgoing[#unconsumedOutgoing + 1] = candidate
                        end
                    end
                end
                local pick
                if #unconsumedOutgoing >= 1 then
                    -- Proven: one unpacked outgoing delivery for the exact
                    -- billed gold.
                    for _, candidate in ipairs(unconsumedOutgoing) do
                        if not candidate.packed and candidate.amount == amount then
                            pick = { candidate = candidate, reason = "proven" }
                            break
                        end
                    end
                    if not pick then
                        if #unconsumedOutgoing == 1 and not unconsumedOutgoing[1].packed
                            and unconsumedOutgoing[1].amount ~= nil then
                            -- Short payment: delivered, but the gold differs.
                            pick = { candidate = unconsumedOutgoing[1], reason = "short" }
                        else
                            -- Packed shared amounts or an ambiguous
                            -- association can never prove a single row.
                            pick = { candidate = #unconsumedOutgoing == 1
                                and unconsumedOutgoing[1] or nil, reason = "packed" }
                        end
                    end
                elseif list then
                    -- Legacy records without a direction, or inbound-only
                    -- purchases, can never prove a sale delivery.
                    local hasIncoming
                    for _, candidate in ipairs(list) do
                        if candidate.direction == nil then
                            pick = { reason = "unknown" }
                            break
                        end
                        hasIncoming = true
                    end
                    if not pick and hasIncoming then
                        pick = { reason = "incoming" }
                    end
                end
                if not pick then
                    addPending("sold", "账单已售装备暂无对应交易证据（第%s个Boss 第%s件）", location)
                elseif pick.reason == "proven" then
                    pick.candidate.consumed = true
                elseif pick.reason == "short" then
                    pick.candidate.consumed = true
                    addPending("sold", "对应交易的实收金额与账单不一致（%s金 / 账单%s金）（第%s个Boss 第%s件）",
                        { tostring(pick.candidate.amount), tostring(amount), location[1], location[2] })
                elseif pick.reason == "packed" then
                    if pick.candidate then
                        -- One bill row can account for at most one delivered
                        -- unit of a shared/ambiguous delivery; the rest stays
                        -- uncovered. A legacy record of unknown quantity is
                        -- treated as fully accounted once it is flagged.
                        if pick.candidate.remaining ~= nil then
                            pick.candidate.remaining = pick.candidate.remaining - 1
                            if pick.candidate.remaining < 0 then
                                pick.candidate.remaining = 0
                            end
                        else
                            pick.candidate.consumed = true
                        end
                    end
                    addPending("sold", "对应交易为多件共享金额或对应关系不唯一，无法确认该件实收（第%s个Boss 第%s件）", location)
                elseif pick.reason == "unknown" then
                    addPending("sold", "已找到对应交易，但交易方向无法从记录确认，请人工核对（第%s个Boss 第%s件）", location)
                elseif pick.reason == "incoming" then
                    addPending("sold", "该交易记录为买入方向，不能作为卖出交付证据（第%s个Boss 第%s件）", location)
                end
            end
        end
    end
    -- Delivered sales the bill does not cover: the bill may be missing a row.
    for _, list in pairs(candidates) do
        local leftover = 0
        for _, candidate in ipairs(list) do
            if not candidate.consumed and candidate.direction == "outgoing" then
                leftover = leftover + (candidate.remaining or 1)
            end
        end
        if leftover > 0 then
            addPending("sold", "存在未被账单核对的已完成交易记录（共%s件），请人工核对是否漏记", { tostring(leftover) })
        end
    end
end

local function evaluateBillRows(input, addIssue)
    for _, row in ipairs(input.bill.rows) do
        if type(row.debt) == "number" and row.debt > 0 then
            addIssue("debt", "欠款未处理：%s金（第%s个Boss 第%s件）",
                { tostring(row.debt), tostring(row.boss), tostring(row.slot) },
                { type = "table", fb = input.fb })
        end
        if row.item ~= "" then
            local missingBuyer = row.buyer == ""
            local missingAmount = row.amount == "" or tonumber(row.amount) == nil
            if missingBuyer and missingAmount then
                addIssue("bill", "装备缺少买家和金额（第%s个Boss 第%s件）",
                    { tostring(row.boss), tostring(row.slot) }, { type = "table", fb = input.fb })
            elseif missingBuyer then
                addIssue("bill", "装备缺少买家（第%s个Boss 第%s件）",
                    { tostring(row.boss), tostring(row.slot) }, { type = "table", fb = input.fb })
            elseif missingAmount then
                addIssue("bill", "装备缺少金额（第%s个Boss 第%s件）",
                    { tostring(row.boss), tostring(row.slot) }, { type = "table", fb = input.fb })
            end
        end
    end
end

local function evaluateSummary(input, addIssue, addPending)
    local summary = input.bill.summary or {}
    local splitCount = tonumber(summary.splitCount)
    local countUsable = splitCount ~= nil and splitCount == splitCount
        and splitCount ~= math.huge and splitCount > 0 and splitCount % 1 == 0
    if not countUsable then
        addIssue("summary", "分金人数未设置或无效")
    end
    local netIncome = tonumber(summary.netIncome)
    if netIncome == nil or netIncome ~= netIncome or netIncome == math.huge or netIncome == -math.huge then
        addPending("summary", "净收入未录入，无法计算工资")
        return
    end
    if netIncome < 0 then
        addIssue("summary", "净收入为负数（%s金）", { tostring(summary.netIncome) })
        return
    end
    if netIncome == 0 then
        for _, row in ipairs(input.bill.rows) do
            local amount = tonumber(row.amount)
            if amount ~= nil and amount > 0 then
                addPending("summary", "净收入为 0，请确认收入与支出是否录入完整")
                return
            end
        end
        return
    end
    if not countUsable then
        return
    end
    if summary.wage == nil then
        addPending("summary", "人均工资未录入，无法核对工资")
        return
    end
    -- Match the displayed wage against BG.GetWages and its rounding option
    -- (BiaoGe.options.moLing floors, otherwise two decimals).
    local expected = summary.moLing
        and tostring(math.floor(netIncome / splitCount))
        or string.format("%.2f", netIncome / splitCount)
    local displayed = trim(tostring(summary.wage))
    if displayed == "" then
        addPending("summary", "人均工资未录入，无法核对工资")
    elseif displayed ~= expected then
        addPending("summary", "人均工资（%s）与分金设置计算值（%s）不一致", { displayed, expected })
    end
end

-- Derives the read-only report. `input` comes from M.collect:
--   settlement = active currentSettlement table, or nil when missing/expired
--   bill       = { hasContent, rows = { { boss, slot, itemId, item, buyer, amount, debt } },
--                  summary = { splitCount, netIncome, wage, moLing } }
--                or nil when the raid table is unavailable
--   scopeMismatch = true when the settlement's raid table differs from the
--                collected bill table
--   fb         = the table the bill belongs to (locate target)
--   normalizeName = optional player-name normalizer for trade/mail matching
function M.evaluate(input)
    input = input or {}
    local entries = {}
    local issueCount, pendingCount = 0, 0

    local function add(severity, category, reasonKey, args, locate)
        entries[#entries + 1] = {
            severity = severity,
            category = category,
            reasonKey = reasonKey,
            args = args or {},
            locate = locate,
        }
        if severity == "issue" then
            issueCount = issueCount + 1
        else
            pendingCount = pendingCount + 1
        end
    end
    local function addIssue(category, reasonKey, args, locate)
        add("issue", category, reasonKey, args, locate)
    end
    local function addPending(category, reasonKey, args, locate)
        add("pending", category, reasonKey, args, locate)
    end

    local hasBillData = input.bill ~= nil and input.bill.hasContent == true
    if not input.settlement then
        addPending("settlement", "当前没有进行中的团结算记录，无法核对交易与邮件")
    else
        evaluateTradesAndMails(input, addIssue, addPending)
        evaluateReturns(input, addIssue)
        if hasBillData then
            evaluateSoldRows(input, addPending)
        end
    end

    if input.bill == nil then
        if input.scopeMismatch then
            addPending("bill", "结算与当前表格不一致，账单未核对")
        else
            addPending("bill", "当前表格数据不可用，无法核对账单")
        end
    elseif not hasBillData then
        addPending("bill", "当前表格还没有账单数据")
    else
        evaluateBillRows(input, addIssue)
        evaluateSummary(input, addIssue, addPending)
    end

    local status = "pending"
    if issueCount > 0 then
        status = "issues"
    elseif pendingCount == 0 then
        status = "ready"
    end
    return {
        status = status,
        issueCount = issueCount,
        pendingCount = pendingCount,
        total = issueCount + pendingCount,
        entries = entries,
    }
end

-- Gathers the evaluate input from injected snapshots only. `options.table` is
-- the raid's BiaoGe table (or nil), `options.slotsOf(fb, boss)` the per-boss
-- item slot count, `options.itemIdOf(itemText)` the item-id resolver,
-- `options.bosses` the boss row count, `options.moLing` the wage rounding
-- option. A settlement whose sourceFb differs from options.fb is a scope
-- mismatch: the bill is rejected instead of being checked across raids.
function M.collect(options)
    options = options or {}
    local db = options.db
    local settlement = db and db.currentSettlement or nil
    local now = options.now
    if settlement then
        local expired = type(settlement.expiresAt) == "number" and type(now) == "number"
            and now >= settlement.expiresAt
        if settlement.raidId == nil or expired then
            settlement = nil
        end
    end
    local scopeMismatch = settlement ~= nil
        and type(settlement.sourceFb) == "string" and type(options.fb) == "string"
        and settlement.sourceFb ~= options.fb

    local bill = nil
    if not scopeMismatch then
        local tableData = options.table
        local bosses = tonumber(options.bosses) or 0
        if type(tableData) == "table" and bosses >= 1 then
            bill = { rows = {}, hasContent = false }
            for boss = 1, bosses do
                local bossData = tableData["boss" .. boss]
                local slots = 0
                if type(options.slotsOf) == "function" then
                    local ok, value = pcall(options.slotsOf, options.fb, boss)
                    if ok and type(value) == "number" then
                        slots = value
                    end
                end
                for slot = 1, slots do
                    local item, buyer, amount, debt, itemId = "", "", "", nil, nil
                    if type(bossData) == "table" then
                        local rawItem = bossData["zhuangbei" .. slot]
                        item = trim(rawItem)
                        buyer = trim(bossData["maijia" .. slot])
                        amount = trim(bossData["jine" .. slot])
                        debt = tonumber(bossData["qiankuan" .. slot])
                        if item ~= "" and type(options.itemIdOf) == "function" then
                            -- Resolvers see the stored text, exactly like the game.
                            local ok, value = pcall(options.itemIdOf, rawItem)
                            if ok and type(value) == "number" then
                                itemId = value
                            end
                        end
                    end
                    if item ~= "" or buyer ~= "" or amount ~= "" or debt ~= nil then
                        bill.hasContent = true
                    end
                    bill.rows[#bill.rows + 1] = {
                        boss = boss, slot = slot, itemId = itemId,
                        item = item, buyer = buyer, amount = amount, debt = debt,
                    }
                end
            end
            local summaryRow = tableData["boss" .. (bosses + 2)]
            bill.summary = {
                splitCount = type(summaryRow) == "table" and summaryRow["jine4"] or nil,
                netIncome = type(summaryRow) == "table" and summaryRow["jine3"] or nil,
                wage = type(summaryRow) == "table" and summaryRow["jine5"] or nil,
                moLing = options.moLing == true,
            }
        end
    end

    return {
        settlement = settlement,
        bill = bill,
        scopeMismatch = scopeMismatch or nil,
        fb = options.fb,
        now = now,
        normalizeName = options.normalizeName,
    }
end

-- One-shot convenience: collect from options, then evaluate.
function M.report(options)
    return M.evaluate(M.collect(options))
end

-- Resolves an entry's locate descriptor to a concrete target, or nil when no
-- honest jump exists (same-table bill rows are described in their reason text
-- instead of pretending a row-level jump).
function M.resolveLocate(locate, currentFb)
    if type(locate) ~= "table" then
        return nil
    end
    if locate.type == "window" then
        return { window = locate.kind == "mail" and "mail" or "trade", filter = locate.filter }
    end
    if locate.type == "table" and type(locate.fb) == "string" and locate.fb ~= currentFb then
        return { table = locate.fb }
    end
    return nil
end

local STATUS_COLORS = {
    ready = { 0, 1, 0 },
    pending = { 1, 0.82, 0 },
    issues = { 1, 0.3, 0.3 },
}

function M.statusColor(status)
    local color = STATUS_COLORS[status] or STATUS_COLORS.pending
    return color[1], color[2], color[3]
end

BG.BGNext.CurrentSettlementChecklist = M
return M
