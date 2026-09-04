BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Shared pre-send gate for the two leader auction start paths: a queued-row
-- confirm and an Alt+right-click preset direct start. Both paths capture an
-- approval snapshot when the price is resolved, then re-run this single gate
-- inside the reused Start_OnClick closure, immediately before the legacy send.
-- It re-validates permission, combat, an in-progress auction, client family,
-- raid scope, scheme identity and the resolved price. It never sends, never
-- writes storage and never creates frames.
local M = {}

M.REASON_NO_PERMISSION = "no-permission"
M.REASON_COMBAT = "combat"
M.REASON_INVALID_ITEM = "invalid-item"
M.REASON_PRICE_UNRESOLVED = "price-unresolved"
M.REASON_AUCTION_BUSY = "auction-busy"
M.REASON_PENDING_START = "pending-start"
M.REASON_SCOPE_CHANGED = "scope-changed"
M.REASON_PRICE_CHANGED = "price-changed"
M.REASON_QUEUE_FULL = "queue-full"
M.REASON_SCHEME_CHANGED = "scheme-changed"
M.REASON_FAMILY_CHANGED = "family-changed"

-- Canonical client families, strongest flag first (see AuctionPriceUI).
M.FAMILY_ORDER = {
    { flag = "IsRetail", family = "retail" },
    { flag = "IsMOP", family = "mop" },
    { flag = "IsCTM", family = "cata" },
    { flag = "IsTitan", family = "titan" },
    { flag = "IsWLK", family = "wrath" },
    { flag = "IsTBC", family = "tbc" },
    { flag = "IsVanilla", family = "vanilla" },
}

function M.clientFamily()
    for _, entry in ipairs(M.FAMILY_ORDER) do
        if BG[entry.flag] then return entry.family end
    end
    return nil
end

function M.isController()
    if BG.IsML == true then return true end
    if type(BG.ImMLorLeader) == "function" then return BG.ImMLorLeader() end
    return false
end

function M.inCombat()
    return InCombatLockdown and InCombatLockdown()
end

-- Busy when ANY live auction card exists; ended (lingering) cards do not block.
function M.auctionInProgress()
    if type(BGA) ~= "table" or type(BGA.Frames) ~= "table" then return false end
    for _, frame in pairs(BGA.Frames) do
        if type(frame) == "table" and not frame.IsEnd then return true end
    end
    return false
end

-- A short, non-reversible digest of the current raid roster so the scope key
-- distinguishes two different raid sessions even when the same table remains
-- selected. The roster is read transiently and never copied or stored.
local function hashString(s)
    local hash = 5381
    for i = 1, #s do
        hash = (hash * 33 + string.byte(s, i)) % 2147483647
    end
    return hash
end

function M.raidSessionToken()
    if type(IsInRaid) == "function" and not IsInRaid(1) then return nil end
    local names = {}
    local count = 0
    if type(GetNumGroupMembers) == "function" then
        count = GetNumGroupMembers()
    end
    if type(GetRaidRosterInfo) == "function" and count > 0 then
        for i = 1, count do
            local name = GetRaidRosterInfo(i)
            if type(name) == "string" and name ~= "" then names[#names + 1] = name end
        end
    elseif type(BG.raidRosterInfo) == "table" then
        for _, entry in ipairs(BG.raidRosterInfo) do
            if type(entry) == "table" and type(entry.name) == "string" then names[#names + 1] = entry.name end
        end
        count = #names
    end
    table.sort(names)
    return tostring(count) .. ":" .. tostring(hashString(table.concat(names, "\1")))
end

function M.scopeKey()
    local tableKey = BG.FB1
    tableKey = type(tableKey) == "string" and tableKey ~= "" and tableKey or ""
    local token = M.raidSessionToken()
    if token == nil then
        return tableKey ~= "" and tableKey or ""
    end
    return tableKey .. "|" .. token
end

-- The single pre-send gate. `approval` is the snapshot captured when the send
-- was approved and carries:
--   clientFamily  -- family at approval time
--   scopeKey      -- raid/table scope at approval time
--   items         -- list of { itemId, raidId, price, activePresetId }
-- `resolve(itemId, raidId)` re-resolves one item from live storage and must
-- return `{ price, source, activePresetId }` or nil. Returns nil to proceed, or
-- the blocking reason code.
function M.gate(approval, resolve)
    if type(approval) ~= "table" then return M.REASON_INVALID_ITEM end
    if not M.isController() then return M.REASON_NO_PERMISSION end
    if M.inCombat() then return M.REASON_COMBAT end
    if M.auctionInProgress() then return M.REASON_AUCTION_BUSY end
    if M.clientFamily() ~= approval.clientFamily then return M.REASON_FAMILY_CHANGED end
    if M.scopeKey() ~= approval.scopeKey then return M.REASON_SCOPE_CHANGED end
    if type(resolve) == "function" then
        for _, item in ipairs(approval.items or {}) do
            local itemId = type(item) == "table" and item.itemId or nil
            local raidId = type(item) == "table" and item.raidId or nil
            local current = resolve(itemId, raidId)
            if type(current) ~= "table" or type(current.price) ~= "number" then
                return M.REASON_PRICE_UNRESOLVED
            end
            if item.activePresetId ~= nil and current.activePresetId ~= item.activePresetId then
                return M.REASON_SCHEME_CHANGED
            end
            if current.price ~= item.price then
                return M.REASON_PRICE_CHANGED
            end
        end
    end
    return nil
end

BG.BGNext.AuctionPreSend = M
return M
