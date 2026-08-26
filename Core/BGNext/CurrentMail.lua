BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}
local FIELDS = { "player", "itemId", "amount", "time", "status", "direction" }

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
    if settlement.startedAt and record.time < settlement.startedAt then
        return false
    end
    if settlement.expiresAt and record.time >= settlement.expiresAt then
        return false
    end
    return true
end

function M.append(root, record)
    if type(record) ~= "table" or not isCurrent(root, record) then
        return false
    end
    local copy = {}
    for _, field in ipairs(FIELDS) do
        copy[field] = record[field]
    end
    table.insert(root.currentSettlement.mails, copy)
    return true
end

BG.BGNext.CurrentMail = M
return M
