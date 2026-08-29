local AddonName, ns = ...

BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Pure projection layer for the single current-raid settlement.
--
-- It reads nothing but `root.currentSettlement.trades` and
-- `root.currentSettlement.mails`. It never touches a legacy store, never
-- aggregates per player, and never produces a total, count or ranking: one
-- stored event becomes exactly one row, in chronological order.
local M = {}

local TRADE_STATUS_COLORS = {
    complete = { 0, 1, 0 },
    pending = { 1, 0.82, 0 },
    failed = { 1, 0, 0 },
    cancelled = { 0.5, 0.5, 0.5 },
}

local MAIL_STATUS_COLORS = {
    sent = { 0, 1, 0 },
    pending = { 1, 0.82, 0 },
    failed = { 1, 0, 0 },
}

local NEUTRAL_COLOR = { 0.5, 0.5, 0.5 }

function M.statusColor(kind, status)
    local palette = kind == "mail" and MAIL_STATUS_COLORS or TRADE_STATUS_COLORS
    local color = palette[status] or NEUTRAL_COLOR
    return color[1], color[2], color[3]
end

function M.formatAmount(amount)
    if type(amount) ~= "number" then
        return ""
    end
    return string.format("%d", amount)
end

local function resolveDateFn(dateFn)
    if type(dateFn) == "function" then
        return dateFn
    end
    local injected = rawget(_G, "date")
    if type(injected) == "function" then
        return injected
    end
    return os and os.date
end

function M.formatTime(value, dateFn)
    if type(value) ~= "number" then
        return ""
    end
    local fn = resolveDateFn(dateFn)
    if type(fn) ~= "function" then
        return ""
    end
    local ok, text = pcall(fn, "%H:%M:%S", value)
    if ok and type(text) == "string" then
        return text
    end
    return ""
end

local function isExpired(settlement, now)
    if type(now) ~= "number" or type(settlement.expiresAt) ~= "number" then
        return false
    end
    return now >= settlement.expiresAt
end

local function project(records, dateFn)
    local rows = {}
    for index, record in ipairs(records) do
        rows[#rows + 1] = {
            index = index,
            sortKey = type(record.time) == "number" and record.time or 0,
            player = record.player,
            itemId = record.itemId,
            amount = record.amount,
            time = record.time,
            statusKey = record.status,
            directionKey = record.direction,
            amountText = M.formatAmount(record.amount),
            timeText = M.formatTime(record.time, dateFn),
        }
    end
    -- Chronological, with the stored order preserved for equal timestamps so
    -- the table never reshuffles between refreshes.
    table.sort(rows, function(a, b)
        if a.sortKey ~= b.sortKey then
            return a.sortKey < b.sortKey
        end
        return a.index < b.index
    end)
    return rows, #rows == 0
end

local function settlementOf(root, options)
    local settlement = root and root.currentSettlement
    if not settlement or isExpired(settlement, options.now) then
        return nil
    end
    return settlement
end

function M.trades(root, options)
    options = options or {}
    local settlement = settlementOf(root, options)
    if not settlement then
        return {}, true
    end
    return project(settlement.trades or {}, options.dateFn)
end

function M.mails(root, options)
    options = options or {}
    local settlement = settlementOf(root, options)
    if not settlement then
        return {}, true
    end
    return project(settlement.mails or {}, options.dateFn)
end

-- Scope description for the window header. A single raid identity only; it is
-- never turned into a selectable list of raids.
function M.info(root, now)
    local settlement = root and root.currentSettlement
    if not settlement then
        return { raidId = nil, expired = false }
    end
    return {
        raidId = settlement.raidId,
        startedAt = settlement.startedAt,
        expiresAt = settlement.expiresAt,
        expired = isExpired(settlement, now),
    }
end

BG.BGNext.CurrentSettlementView = M
return M
