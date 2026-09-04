BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- User-confirmed return markers for the one current settlement. This module
-- never edits the bill and never infers a refund: it records only which bill
-- row the leader selected for later correction.
local M = {}

local function positiveInteger(value)
    return type(value) == "number" and value >= 1 and value % 1 == 0
end

function M.ensure(root)
    local settlement = root and root.currentSettlement
    if type(settlement) ~= "table" then return {} end
    local clean = {}
    for _, marker in ipairs(type(settlement.returns) == "table" and settlement.returns or {}) do
        local amount = type(marker) == "table" and marker.originalAmount or nil
        local validAmount = amount == nil or (type(amount) == "number" and amount >= 0)
        local validTime = type(marker) == "table" and type(marker.time) == "number"
            and (settlement.startedAt == nil or marker.time >= settlement.startedAt)
            and (settlement.expiresAt == nil or marker.time < settlement.expiresAt)
        if type(marker) == "table" and positiveInteger(marker.tradeIndex)
            and positiveInteger(marker.itemId) and positiveInteger(marker.boss)
            and positiveInteger(marker.slot) and type(marker.player) == "string"
            and marker.player:find("%S") and (marker.status == "pending" or marker.status == "cleared")
            and validAmount and validTime then
            clean[#clean + 1] = {
                tradeIndex = marker.tradeIndex, itemId = marker.itemId,
                boss = marker.boss, slot = marker.slot, player = marker.player,
                originalBuyer = type(marker.originalBuyer) == "string" and marker.originalBuyer or nil,
                originalAmount = amount, time = marker.time, status = marker.status,
            }
        end
    end
    settlement.returns = clean
    return clean
end

local function trim(value)
    if type(value) ~= "string" then return "" end
    return value:match("^%s*(.-)%s*$")
end

local function samePlayer(left, right, normalize)
    left, right = trim(left), trim(right)
    if type(normalize) == "function" then
        local okLeft, normalizedLeft = pcall(normalize, left)
        local okRight, normalizedRight = pcall(normalize, right)
        if okLeft and type(normalizedLeft) == "string" then left = normalizedLeft end
        if okRight and type(normalizedRight) == "string" then right = normalizedRight end
    end
    return left ~= "" and left == right
end

local function validTrade(settlement, tradeIndex)
    local trade = settlement and settlement.trades and settlement.trades[tradeIndex]
    if type(trade) ~= "table" or trade.completed ~= true or type(trade.theirItems) ~= "table" then
        return nil
    end
    return trade
end

function M.candidates(root, tradeIndex, billRows, normalize)
    local settlement = root and root.currentSettlement
    M.ensure(root)
    local trade = validTrade(settlement, tradeIndex)
    if not trade or type(billRows) ~= "table" then return {} end
    local received = {}
    for _, item in ipairs(trade.theirItems) do
        if type(item) == "table" and type(item.itemId) == "number" then
            received[item.itemId] = true
        end
    end
    local out = {}
    for _, row in ipairs(billRows) do
        if type(row) == "table" and received[row.itemId]
            and samePlayer(row.buyer, trade.player, normalize)
            and type(row.boss) == "number" and type(row.slot) == "number" then
            out[#out + 1] = {
                boss = row.boss,
                slot = row.slot,
                itemId = row.itemId,
                buyer = trim(row.buyer),
                amount = tonumber(row.amount),
            }
        end
    end
    return out
end

local function selectedCandidate(candidates, selection)
    if selection == nil then
        return #candidates == 1 and candidates[1] or nil
    end
    if type(selection) ~= "table" then return nil end
    for _, candidate in ipairs(candidates) do
        if candidate.boss == selection.boss and candidate.slot == selection.slot then
            return candidate
        end
    end
    return nil
end

function M.mark(root, tradeIndex, selection, billRows, now, authorised, normalize)
    if authorised ~= true then return false, "not-authorised" end
    local settlement = root and root.currentSettlement
    if not settlement or settlement.raidId == nil or type(now) ~= "number"
        or (settlement.expiresAt and now >= settlement.expiresAt) then
        return false, "no-settlement"
    end
    local candidates = M.candidates(root, tradeIndex, billRows, normalize)
    if #candidates > 1 and selection == nil then return false, "selection-required" end
    local candidate = selectedCandidate(candidates, selection)
    if not candidate then return false, "no-match" end
    settlement.returns = settlement.returns or {}
    M.ensure(root)
    for _, marker in ipairs(settlement.returns) do
        if marker.tradeIndex == tradeIndex and marker.boss == candidate.boss
            and marker.slot == candidate.slot and marker.status == "pending" then
            return false, "duplicate"
        end
    end
    settlement.returns[#settlement.returns + 1] = {
        tradeIndex = tradeIndex,
        itemId = candidate.itemId,
        boss = candidate.boss,
        slot = candidate.slot,
        player = root.currentSettlement.trades[tradeIndex].player,
        originalBuyer = candidate.buyer,
        originalAmount = candidate.amount,
        time = now,
        status = "pending",
    }
    return true
end

function M.clear(root, markerIndex, authorised)
    if authorised ~= true then return false end
    M.ensure(root)
    local marker = root and root.currentSettlement and root.currentSettlement.returns
        and root.currentSettlement.returns[markerIndex]
    if type(marker) ~= "table" or marker.status ~= "pending" then return false end
    marker.status = "cleared"
    return true
end

function M.pendingForTrade(root, tradeIndex)
    local returns = M.ensure(root)
    for index, marker in ipairs(returns) do
        if marker.tradeIndex == tradeIndex and marker.status == "pending" then
            return marker, index
        end
    end
    return nil
end

BG.BGNext.ReturnMarker = M
return M
