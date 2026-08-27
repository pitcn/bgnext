BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Local price configuration for controlled auto-bid.
--
-- This module only ever holds two user-entered values (每次加价金额 and 心理最高价).
-- It is pure: no frames, no messages, no SavedVariables access of its own — the
-- caller passes the presets table in and receives validated values back.
local M = {}

-- WoW stores money as 32-bit copper; anything above this is not a real amount.
local MAX_MONEY = 2147483647

local function normalize(value)
    if type(value) == "string" then
        if not value:match("^%d+$") then
            return nil
        end
        value = tonumber(value)
    end
    if type(value) ~= "number" then
        return nil
    end
    if value ~= value or value == math.huge or value == -math.huge then
        return nil
    end
    if value < 1 or value > MAX_MONEY then
        return nil
    end
    if value % 1 ~= 0 then
        return nil
    end
    return value
end

function M.validateMoney(value)
    return normalize(value)
end

function M.validateIncrement(value)
    return normalize(value)
end

function M.get(presets)
    presets = presets or {}
    return {
        increment = presets.increment,
        cap = presets.cap,
    }
end

-- Writes only the two whitelisted fields. A field that is present but illegal
-- fails the whole call and leaves the stored value untouched; a field that is
-- absent is left as-is. Unknown fields are ignored entirely.
function M.set(presets, fields)
    if type(presets) ~= "table" then
        return nil
    end
    fields = fields or {}
    local increment = normalize(fields.increment)
    local cap = normalize(fields.cap)
    if fields.increment ~= nil and increment == nil then
        return nil
    end
    if fields.cap ~= nil and cap == nil then
        return nil
    end
    if increment ~= nil then
        presets.increment = increment
    end
    if cap ~= nil then
        presets.cap = cap
    end
    return { increment = presets.increment, cap = presets.cap }
end

function M.reset(presets)
    if type(presets) ~= "table" then
        return nil
    end
    presets.increment = nil
    presets.cap = nil
    return presets
end

BG.BGNext.AuctionPresetStore = M

return M
