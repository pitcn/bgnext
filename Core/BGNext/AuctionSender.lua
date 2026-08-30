BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Sender validation for the retained BGLite native auction protocol. Pure
-- helpers (no WoW API) so the fail-closed checks are unit-testable. The caller
-- supplies the normalized realm and the raw current raid-member name list.
local M = {}
local PlayerIdentity = assert(BG.BGNext.PlayerIdentity, "BGNext PlayerIdentity must load before AuctionSender")

M.MAX_ID = 2147483647
M.MAX_MONEY = 10000000
M.MAX_RATE_KEYS = 256

local function boundedInteger(value, minimum, maximum)
    local number = tonumber(value)
    if not number or number ~= number or number == math.huge or number == -math.huge then return nil end
    if number % 1 ~= 0 or number < minimum or number > maximum then return nil end
    return number
end

-- Canonical full name ("Name-Realm"). A name that already carries a realm
-- suffix is kept verbatim; a bare name gains `realm`. Empty/missing -> nil.
function M.canonical(name, realm)
    if type(name) ~= "string" or name == "" then return nil end
    if name:find("-", 1, true) then return name end
    if realm == nil or realm == "" then return name end
    return name .. "-" .. realm
end

-- True only when `sender` names a current raid member. `memberNames` is the
-- list of raw member names from the roster; each is canonicalized the same way
-- before comparison. A missing/empty sender or an empty roster fails closed.
function M.isRaidSender(sender, realm, memberNames)
    if PlayerIdentity.key(sender, realm) == nil then return false end
    for _, name in ipairs(memberNames or {}) do
        if PlayerIdentity.same(sender, name, realm) then return true end
    end
    return false
end

function M.isController(sender, realm, roster)
    if PlayerIdentity.key(sender, realm) == nil then return false end
    for _, member in ipairs(roster or {}) do
        if type(member) == "table" and PlayerIdentity.same(sender, member.name, realm) then
            return member.rank == 2 or member.isML == true
        end
    end
    return false
end

-- Parse the two numeric fields used by SendMyMoney. Both are mandatory; a
-- malformed compatible client must be ignored before live auction comparisons.
function M.parseBid(auctionIDStr, moneyStr)
    local auctionID = boundedInteger(auctionIDStr, 1, M.MAX_ID)
    local money = boundedInteger(moneyStr, 0, M.MAX_MONEY)
    if not auctionID or not money then return nil end
    return auctionID, money
end

function M.parseStart(auctionIDStr, itemIDStr, moneyStr, durationStr)
    local auctionID = boundedInteger(auctionIDStr, 1, M.MAX_ID)
    local itemID = boundedInteger(itemIDStr, 1, M.MAX_ID)
    local money = boundedInteger(moneyStr, 0, M.MAX_MONEY)
    local duration = boundedInteger(durationStr, 1, 3600)
    if not auctionID or not itemID or not money or not duration then return nil end
    return auctionID, itemID, money, duration
end

function M.shouldRespondVersion(state, sender, realm, memberNames, now, options)
    if type(state) ~= "table" or type(now) ~= "number" then return false end
    if not M.isRaidSender(sender, realm, memberNames) then return false end

    options = options or {}
    local senderCooldown = options.senderCooldown or 30
    local globalWindow = options.globalWindow or 10
    local globalLimit = options.globalLimit or 3
    local senderKey = PlayerIdentity.key(sender, realm)
    local lastResponse = state.bySender and state.bySender[senderKey]
    if lastResponse and now >= lastResponse and now - lastResponse < senderCooldown then return false end

    if type(state.windowStart) ~= "number" or now < state.windowStart or now - state.windowStart >= globalWindow then
        state.windowStart = now
        state.windowCount = 0
    end
    if (state.windowCount or 0) >= globalLimit then return false end

    state.bySender = state.bySender or {}
    state.bySender[senderKey] = now
    state.windowCount = (state.windowCount or 0) + 1
    return true
end

function M.shouldAcceptAuctionMessage(state, sender, realm, memberNames, auctionID, now, interval)
    if type(state) ~= "table" or type(now) ~= "number" or type(interval) ~= "number" or interval < 0 then
        return false
    end
    if not M.isRaidSender(sender, realm, memberNames) then return false end
    auctionID = boundedInteger(auctionID, 1, M.MAX_ID)
    if not auctionID then return false end

    local senderKey = PlayerIdentity.key(sender, realm)
    local key = senderKey .. ":" .. auctionID
    state.byKey = state.byKey or {}
    local lastAccepted = state.byKey[key]
    if lastAccepted then
        if now < lastAccepted or now - lastAccepted < interval then return false end
    elseif (state.keyCount or 0) >= M.MAX_RATE_KEYS then
        for oldKey, timestamp in pairs(state.byKey) do
            if type(timestamp) ~= "number" or now < timestamp or now - timestamp >= 60 then
                state.byKey[oldKey] = nil
                state.keyCount = math.max(0, (state.keyCount or 1) - 1)
            end
        end
        if (state.keyCount or 0) >= M.MAX_RATE_KEYS then return false end
    end

    if not lastAccepted then
        state.keyCount = (state.keyCount or 0) + 1
    end
    state.byKey[key] = now
    return true
end

BG.BGNext.AuctionSender = M
return M
