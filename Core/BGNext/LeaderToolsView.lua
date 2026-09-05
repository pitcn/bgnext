BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Read-only projections for current auctions and settlement facts.
local M = {}

local function isObject(value)
    return type(value) == "table" or type(value) == "userdata"
end

local function finiteWhole(value, allowZero)
    value = tonumber(value)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge
        or value % 1 ~= 0 or value < (allowZero and 0 or 1) then return nil end
    return value
end

function M.projectAuctions(frames, filter, isMe)
    local result = {}
    filter = filter == "mine" and "mine" or filter == "urgent" and "urgent" or "all"
    for _, frame in pairs(type(frames) == "table" and frames or {}) do
        if isObject(frame) then
            local mine = type(isMe) == "function" and isMe(frame) == true or false
            local remaining = tonumber(frame.remaining)
            local active = frame.IsEnd ~= true
            local urgent = active and remaining ~= nil and remaining >= 0 and remaining <= 5
            if filter == "all" or (filter == "mine" and mine) or (filter == "urgent" and urgent) then
                result[#result + 1] = {
                    identity = frame.auctionID or frame.auctionId or frame.auctionIdKey or frame,
                    itemId = frame.itemID,
                    link = frame.link,
                    amount = finiteWhole(frame.money, true),
                    remaining = remaining,
                    player = frame.player,
                    mine = mine,
                    urgent = urgent,
                    ended = not active,
                    paused = frame.isPaused == true,
                    source = frame,
                }
            end
        end
    end
    table.sort(result, function(a, b)
        if a.ended ~= b.ended then return not a.ended end
        local ar, br = a.remaining or math.huge, b.remaining or math.huge
        if ar ~= br then return ar < br end
        return tostring(a.identity) < tostring(b.identity)
    end)
    return result
end

function M.isRiskyBid(current, offered)
    current, offered = finiteWhole(current, false), finiteWhole(offered, false)
    return current ~= nil and offered ~= nil and offered >= current * 10 and offered - current >= 1000
end

local function cleanSale(record)
    if type(record) ~= "table" or record.completed ~= true or record.status ~= "complete"
        or finiteWhole(record.myGold, true) ~= 0 or type(record.myItems) ~= "table"
        or #record.myItems ~= 1 or type(record.theirItems) ~= "table" or #record.theirItems ~= 0 then return nil end
    local received = finiteWhole(record.theirGold, true)
    if not received or received <= 0 then return nil end
    local item = record.myItems[1]
    local itemId = type(item) == "table" and finiteWhole(item.itemId, false) or nil
    if not itemId or item.quantity ~= 1 then return nil end
    return received, itemId
end

function M.settlementSummary(bill, settlement)
    bill, settlement = type(bill) == "table" and bill or {}, type(settlement) == "table" and settlement or {}
    local result = { ledgerIncome = 0, provenReceived = 0, expenses = 0, debt = 0, pendingCount = 0 }
    local saleRows, billKeys = 0, {}
    for _, row in ipairs(type(bill.rows) == "table" and bill.rows or {}) do
        local value = finiteWhole(row.amount, true)
        if type(row.item) == "string" and row.item ~= "" and type(row.buyer) == "string"
            and row.buyer ~= "" and value and value > 0 then
            result.ledgerIncome, saleRows = result.ledgerIncome + value, saleRows + 1
            if finiteWhole(row.itemId, false) then
                local key = tostring(row.itemId) .. "|" .. tostring(value)
                billKeys[key] = (billKeys[key] or 0) + 1
            else
                result.pendingCount = result.pendingCount + 1
            end
        elseif type(row.item) == "string" and row.item ~= "" then
            result.pendingCount = result.pendingCount + 1
        end
        local debt = finiteWhole(row.debt, true)
        if debt and debt > 0 then result.debt = result.debt + debt end
    end
    for _, row in ipairs(type(bill.expenses) == "table" and bill.expenses or {}) do
        local value = finiteWhole(row.amount, true)
        local hasName = type(row.name) == "string" and row.name:find("%S") ~= nil
        local hasAmount = row.amount ~= nil and tostring(row.amount):find("%S") ~= nil
        if hasName and value then
            result.expenses = result.expenses + value
        elseif hasName or hasAmount then
            result.pendingCount = result.pendingCount + 1
        end
    end
    local provenTrades, tradeKeys = 0, {}
    for _, record in ipairs(type(settlement.trades) == "table" and settlement.trades or {}) do
        local received, itemId = cleanSale(record)
        if received then
            result.provenReceived, provenTrades = result.provenReceived + received, provenTrades + 1
            local key = tostring(itemId) .. "|" .. tostring(received)
            tradeKeys[key] = (tradeKeys[key] or 0) + 1
        elseif type(record) == "table" and record.completed == true
            and type(record.myItems) == "table" and #record.myItems > 0 then
            result.pendingCount = result.pendingCount + 1
        end
    end
    local splitCount = finiteWhole(bill.splitCount, false)
    result.splitCount = splitCount
    if result.debt > 0 then result.pendingCount = result.pendingCount + 1 end
    -- A distributable number is intentionally conservative: every sale row
    -- must have one clean trade and total actual receipts must equal the bill.
    local pairsMatch = true
    for key, count in pairs(billKeys) do if tradeKeys[key] ~= count then pairsMatch = false break end end
    if pairsMatch then
        for key, count in pairs(tradeKeys) do if billKeys[key] ~= count then pairsMatch = false break end end
    end
    if not pairsMatch then result.pendingCount = result.pendingCount + 1 end
    if result.pendingCount == 0 and pairsMatch and saleRows > 0 and saleRows == provenTrades
        and result.ledgerIncome == result.provenReceived and splitCount then
        result.distributable = result.ledgerIncome - result.expenses
        if result.distributable >= 0 then result.wage = result.distributable / splitCount
        else result.distributable = nil end
    end
    return result
end

local function token(value)
    return tostring(value == nil and "?" or value):gsub("[|;,:]", function(char)
        return string.format("%%%02X", string.byte(char))
    end)
end

-- Memory-only fingerprint used to invalidate a local confirmation. It covers
-- only the already allowed bill and current-settlement facts and is never
-- persisted or sent.
function M.settlementFingerprint(bill, settlement)
    bill, settlement = type(bill) == "table" and bill or {}, type(settlement) == "table" and settlement or {}
    local parts = { "S1", token(bill.splitCount) }
    for _, row in ipairs(type(bill.rows) == "table" and bill.rows or {}) do
        parts[#parts + 1] = table.concat({ "B", token(row.itemId), token(row.item), token(row.buyer), token(row.amount), token(row.debt) }, ":")
    end
    for _, row in ipairs(type(bill.expenses) == "table" and bill.expenses or {}) do
        parts[#parts + 1] = table.concat({ "E", token(row.name), token(row.amount) }, ":")
    end
    for _, record in ipairs(type(settlement.trades) == "table" and settlement.trades or {}) do
        local entry = { "T", token(record.completed), token(record.status), token(record.myGold), token(record.theirGold), token(record.time) }
        for _, item in ipairs(type(record.myItems) == "table" and record.myItems or {}) do
            entry[#entry + 1] = "M" .. token(item.itemId) .. "," .. token(item.quantity)
        end
        for _, item in ipairs(type(record.theirItems) == "table" and record.theirItems or {}) do
            entry[#entry + 1] = "Y" .. token(item.itemId) .. "," .. token(item.quantity)
        end
        parts[#parts + 1] = table.concat(entry, ":")
    end
    for _, record in ipairs(type(settlement.mails) == "table" and settlement.mails or {}) do
        parts[#parts + 1] = table.concat({ "M", token(record.itemId), token(record.amount), token(record.time),
            token(record.status), token(record.direction) }, ":")
    end
    return table.concat(parts, "|")
end

BG.BGNext.LeaderToolsView = M
return M
