BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}
local FIELDS = { "player", "itemId", "amount", "time", "status", "direction" }

-- Reconciliation states and directions only. Free text is rejected so a mail
-- subject, body or private note can never reach the stored record.
local STATUS = {
    sent = true,
    pending = true,
    failed = true,
}

local DIRECTION = {
    outgoing = true,
    incoming = true,
}

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
    if not STATUS[record.status] then
        return false
    end
    if record.direction ~= nil and not DIRECTION[record.direction] then
        return false
    end
    if record.itemId ~= nil and type(record.itemId) ~= "number" then
        return false
    end
    if record.amount ~= nil and (type(record.amount) ~= "number" or record.amount < 0) then
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

local function isDuplicate(records, copy)
    for _, existing in ipairs(records) do
        local same = true
        for _, field in ipairs(FIELDS) do
            if existing[field] ~= copy[field] then
                same = false
                break
            end
        end
        if same then
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
    local records = root.currentSettlement.mails
    if isDuplicate(records, copy) then
        return false
    end
    table.insert(records, copy)
    return true
end

BG.BGNext.CurrentMail = M
return M
