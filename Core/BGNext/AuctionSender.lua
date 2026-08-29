BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Sender validation for the retained BGLite native auction protocol. Pure
-- helpers (no WoW API) so the fail-closed checks are unit-testable. The caller
-- supplies the normalized realm and the raw current raid-member name list.
local M = {}
local PlayerIdentity = assert(BG.BGNext.PlayerIdentity, "BGNext PlayerIdentity must load before AuctionSender")

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
    local auctionID = tonumber(auctionIDStr)
    local money = tonumber(moneyStr)
    if auctionID == nil or money == nil then return nil end
    return auctionID, money
end

function M.parseStart(auctionIDStr, itemIDStr, moneyStr, durationStr)
    local auctionID = tonumber(auctionIDStr)
    local itemID = tonumber(itemIDStr)
    local money = tonumber(moneyStr)
    local duration = tonumber(durationStr)
    if not auctionID or auctionID <= 0 or not itemID or itemID <= 0 then return nil end
    if not money or money < 0 or not duration or duration <= 0 or duration > 3600 then return nil end
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

BG.BGNext.AuctionSender = M
return M
