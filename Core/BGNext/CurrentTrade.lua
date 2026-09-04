BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}
-- A completed trade is stored as one grouped transaction record. `completed`
-- is the trade fact (the game confirmed the trade), `status` is the
-- reconciliation state, gold is kept on both sides (0 is a valid value, nil is
-- unknown), and the two item lists keep both delivery directions.
local FIELDS = { "player", "time", "completed", "status", "myGold", "theirGold", "myItems", "theirItems" }

-- Reconciliation states only. Free text is rejected so notes, chat or mail
-- content can never reach the stored record through the status field.
local STATUS = {
    complete = true,
    pending = true,
    failed = true,
    cancelled = true,
}

local function validGold(value)
    return value == nil or (type(value) == "number" and value >= 0)
end

local function validItems(value)
    if value == nil then
        return true
    end
    if type(value) ~= "table" then
        return false
    end
    for _, entry in ipairs(value) do
        if type(entry) ~= "table" then
            return false
        end
        if type(entry.itemId) ~= "number" then
            return false
        end
        -- Quantity is the delivered item count of one slot group: a positive
        -- whole number, or nil when the count is unknown or invalid. A zero or
        -- fractional count can never be stored and later read as a delivered item.
        local quantity = entry.quantity
        if quantity ~= nil and (type(quantity) ~= "number"
            or quantity < 1 or quantity % 1 ~= 0) then
            return false
        end
    end
    return true
end

local function isCurrent(root, record)
    local settlement = root and root.currentSettlement
    if not settlement or record.raidId ~= settlement.raidId then
        return false
    end
    if type(record.player) ~= "string" or not record.player:find("%S") then
        return false
    end
    if type(record.time) ~= "number" then
        return false
    end
    -- Only a confirmed trade is ever recorded; the completed fact is explicit
    -- so it can never be fabricated as an unconfirmed event.
    if record.completed ~= true then
        return false
    end
    if not STATUS[record.status] then
        return false
    end
    if not validGold(record.myGold) then
        return false
    end
    if not validGold(record.theirGold) then
        return false
    end
    if not validItems(record.myItems) then
        return false
    end
    if not validItems(record.theirItems) then
        return false
    end
    if settlement.startedAt and record.time < settlement.startedAt then
        return false
    end
    if settlement.expiresAt and record.time >= settlement.expiresAt then
        return false
    end
    return true
end

function M.setStatus(root, index, status)
    local settlement = root and root.currentSettlement
    local record = settlement and settlement.trades and settlement.trades[index]
    if not record or (status ~= "pending" and status ~= "complete") then
        return false
    end
    record.status = status
    return true
end

local function copyItems(value)
    if type(value) ~= "table" then
        return nil
    end
    local out = {}
    for index, entry in ipairs(value) do
        out[index] = { itemId = entry.itemId, quantity = entry.quantity }
    end
    return out
end

local function itemsEqual(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    if #a ~= #b then
        return false
    end
    for index = 1, #a do
        local x, y = a[index], b[index]
        if type(x) ~= "table" or type(y) ~= "table" then
            if x ~= y then
                return false
            end
        elseif x.itemId ~= y.itemId or x.quantity ~= y.quantity then
            return false
        end
    end
    return true
end

local function isDuplicate(records, copy)
    for _, existing in ipairs(records) do
        if existing.player == copy.player
            and existing.time == copy.time
            and existing.completed == copy.completed
            and existing.status == copy.status
            and existing.myGold == copy.myGold
            and existing.theirGold == copy.theirGold
            and itemsEqual(existing.myItems, copy.myItems)
            and itemsEqual(existing.theirItems, copy.theirItems) then
            return true
        end
    end
    return false
end

function M.append(root, record)
    if type(record) ~= "table" or not isCurrent(root, record) then
        return false
    end
    local copy = {}
    for _, field in ipairs(FIELDS) do
        copy[field] = record[field]
    end
    -- Item lists are copied deep so later mutation of the runtime's snapshot
    -- can never rewrite a stored record, and compared deep so a repeated event
    -- cannot become a second row.
    copy.myItems = copyItems(record.myItems)
    copy.theirItems = copyItems(record.theirItems)
    local records = root.currentSettlement.trades
    if isDuplicate(records, copy) then
        return false
    end
    table.insert(records, copy)
    return true
end

BG.BGNext.CurrentTrade = M
return M
