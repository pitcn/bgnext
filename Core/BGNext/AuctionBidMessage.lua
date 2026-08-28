BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Message parsing and validation for the controlled auto-bid.
--
-- Reuses the already-approved BGLite gen1 current-auction protocol: channel
-- "BiaoGeAuction", comma-separated, opcode SendMyMoney. This module only parses,
-- classifies and builds strings; it never sends anything itself. Gen2 (rotating
-- channels, caret separators, anonymous auctions) is out of scope and treated as
-- unknown.
--
-- Two responsibilities live here:
--   1. Strict protocol parsing (parse) — a bid is exactly
--      `SendMyMoney,<auctionID>,<positive integer money>`; empty fields, extra
--      fields, scientific notation, decimals, and out-of-range amounts are all
--      rejected rather than silently accepted.
--   2. The addon-message source adapter (extractSender / classify) — a bid is
--      only acted on once it is a BiaoGeAuction + SendMyMoney candidate, and then
--      only when its distribution is RAID and its sender is a real raid member.
local M = {}

M.ADDON_PREFIX = "BiaoGeAuction"
M.OPCODE = "SendMyMoney"
M.MAX_MONEY = 2147483647

-- The verified CHAT_MSG_ADDON payload order is:
--   prefix, text, channel, sender, target, zoneChannelID, localID, name, instanceID
-- The sender is therefore the FOURTH argument and the target the FIFTH.
M.SENDER_INDEX = 4

-- Parse a gen1 addon message strictly. Returns
--   { opcode, auctionId, auctionIdNum, money }
-- for an exactly-valid SendMyMoney bid, or nil otherwise (wrong channel, another
-- opcode, or any structural violation: empty field, extra field, non-digit,
-- decimal, scientific notation, out-of-range amount, or illegal auction id).
function M.parse(prefix, message)
    if prefix ~= M.ADDON_PREFIX then
        return nil
    end
    if type(message) ~= "string" then
        return nil
    end
    local opcode, auctionIdStr, moneyStr, rest = message:match("^([^,]*),([^,]*),([^,]*)(.*)$")
    if opcode == nil then
        return nil -- fewer than three fields
    end
    if rest ~= "" then
        return nil -- extra fields (including a trailing empty field)
    end
    if opcode ~= M.OPCODE then
        return nil
    end
    if auctionIdStr == "" or not auctionIdStr:match("^%d+$") then
        return nil -- empty or non-digit auction id
    end
    if moneyStr == "" or not moneyStr:match("^%d+$") then
        return nil -- empty or non-digit money
    end
    local auctionIdNum = tonumber(auctionIdStr)
    local money = tonumber(moneyStr)
    if auctionIdNum == nil or auctionIdNum < 1 then
        return nil
    end
    if money == nil or money < 1 or money > M.MAX_MONEY then
        return nil
    end
    return { opcode = opcode, auctionId = auctionIdStr, auctionIdNum = auctionIdNum, money = money }
end

-- Explicit sender extraction for a CHAT_MSG_ADDON event. The sender is the
-- FOURTH argument (the target is the fifth). This is a fixed position, never a
-- fallback — a missing sender must fail closed, so the runtime stops rather than
-- guessing. `build` is accepted for future client families but does not change
-- the position on the supported clients.
function M.extractSender(build, sender, target)
    return sender
end

-- Classify a full addon event into a single decision for the runtime.
--
-- Unrelated addon traffic is dropped first, BEFORE any fail-closed check, so a
-- foreign addon's PARTY/WHISPER/GUILD message can never stop the auto-bid. Only
-- a BiaoGeAuction + SendMyMoney candidate proceeds to the fail-closed checks.
--
-- Returns one of:
--   { kind = "ignored" }             normal non-bid traffic — do nothing
--   { kind = "wrong-auction" }       valid bid for a different auction — ignore
--   { kind = "stop", reason = ... }  fail-closed: stop the armed auto-bid
--   { kind = "bid", parsed, sender } a valid bid for the active auction
--
-- The stop reasons are "not-raid" (distribution is not RAID), "no-sender"
-- (sender could not be read) and "malformed" (a SendMyMoney whose body violates
-- the strict protocol).
function M.classify(build, prefix, message, distribution, sender, target, activeAuctionId)
    if prefix ~= M.ADDON_PREFIX then
        return { kind = "ignored" }
    end
    local opcode = type(message) == "string" and message:match("^([^,]*)") or nil
    if opcode ~= M.OPCODE then
        return { kind = "ignored" } -- BiaoGeAuction but not SendMyMoney (e.g. VersionCheck)
    end
    if distribution ~= "RAID" then
        return { kind = "stop", reason = "not-raid" }
    end
    local senderName = M.extractSender(build, sender, target)
    if senderName == nil or senderName == "" then
        return { kind = "stop", reason = "no-sender" }
    end
    local parsed = M.parse(prefix, message)
    if parsed == nil then
        return { kind = "stop", reason = "malformed" }
    end
    if activeAuctionId ~= nil and parsed.auctionId ~= activeAuctionId then
        return { kind = "wrong-auction" }
    end
    return { kind = "bid", parsed = parsed, sender = senderName }
end

-- Validate a parsed bid event against the current context. Returns nil when the
-- bid is acceptable, or a short reason otherwise. ctx carries:
--   sender       the addon-message sender (canonical full name)
--   raidMembers  a set of current raid members, keyed by canonical full name
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
