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

-- Parse the two numeric fields used by SendMyMoney. Both are mandatory; a
-- malformed compatible client must be ignored before live auction comparisons.
function M.parseBid(auctionIDStr, moneyStr)
    local auctionID = tonumber(auctionIDStr)
    local money = tonumber(moneyStr)
    if auctionID == nil or money == nil then return nil end
    return auctionID, money
end

BG.BGNext.AuctionSender = M
return M
