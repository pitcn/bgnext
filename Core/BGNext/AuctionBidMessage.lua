BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Message parsing and validation for the controlled auto-bid.
--
-- Reuses the already-approved BGLite gen1 current-auction protocol: channel
-- "BiaoGeAuction", comma-separated, opcode SendMyMoney. This module only parses
-- and builds strings; it never sends anything itself. Gen2 (rotating channels,
-- caret separators, anonymous auctions) is out of scope and treated as unknown.
local M = {}

M.ADDON_PREFIX = "BiaoGeAuction"
M.OPCODE = "SendMyMoney"
M.MAX_MONEY = 2147483647

-- Parse a gen1 addon message. Returns { opcode, auctionId, money } for a
-- structurally valid SendMyMoney bid, or nil otherwise (wrong channel, another
-- opcode, or a malformed body).
function M.parse(prefix, message)
    if prefix ~= M.ADDON_PREFIX then
        return nil
    end
    if type(message) ~= "string" then
        return nil
    end
    local parts = {}
    for token in message:gmatch("[^,]+") do
        parts[#parts + 1] = token
    end
    if parts[1] ~= M.OPCODE then
        return nil
    end
    if parts[2] == nil or parts[2] == "" then
        return nil
    end
    local money = tonumber(parts[3])
    if money == nil then
        return nil
    end
    return { opcode = parts[1], auctionId = parts[2], money = money }
end

-- Validate a parsed bid event against the current context. Returns nil when the
-- bid is acceptable, or a short reason otherwise. ctx carries:
--   sender       the addon-message sender name (required)
--   raidMembers  a set of current raid members, keyed by name
--   auctionId    the active auction instance id
--   maxMoney     optional amount ceiling (defaults to the copper cap)
function M.validateBidEvent(parsed, ctx)
    if type(parsed) ~= "table" or parsed.opcode ~= M.OPCODE then
        return "bad-fields"
    end
    ctx = ctx or {}

    if type(ctx.raidMembers) == "table" and not ctx.raidMembers[ctx.sender] then
        return "not-raid"
    end

    if ctx.auctionId ~= nil and parsed.auctionId ~= ctx.auctionId then
        return "wrong-auction"
    end

    local money = parsed.money
    local maxMoney = ctx.maxMoney or M.MAX_MONEY
    if type(money) ~= "number" or money < 1 or money % 1 ~= 0 or money > maxMoney then
        return "bad-money"
    end

    return nil
end

-- Build the outbound SendMyMoney message in the approved gen1 format.
function M.buildBidMessage(auctionId, money)
    return M.OPCODE .. "," .. tostring(auctionId) .. "," .. tostring(money)
end

BG.BGNext.AuctionBidMessage = M

return M
