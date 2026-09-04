BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}
local MAX_AGE = 7 * 86400

local function serverNow()
    if type(GetServerTime) == "function" then
        return GetServerTime()
    end
    return time()
end

local function emptySettlement()
    return {
        raidId = nil,
        sourceFb = nil,
        sourceRealm = nil,
        startedAt = nil,
        expiresAt = nil,
        trades = {},
        mails = {},
        returns = {},
    }
end

function M.ensureRoot(saved)
    saved.BGNext = saved.BGNext or {}
    local root = saved.BGNext
    root.schemaVersion = 1
    root.settings = root.settings or {}
    root.wishlist = root.wishlist or {}
    root.equipmentFilters = root.equipmentFilters or {}
    root.ownCharacters = root.ownCharacters or {}
    root.leaderAuctionPricePresets = root.leaderAuctionPricePresets or {}
    root.personalAuctionExpectations = root.personalAuctionExpectations or {}
    root.currentRaid = root.currentRaid or {}
    root.currentSettlement = root.currentSettlement or emptySettlement()
    root.currentSettlement.returns = root.currentSettlement.returns or {}
    return root
end

function M.clearSettlement(root)
    root.currentSettlement = emptySettlement()
end

function M.beginSettlement(root, raidId, now, source)
    local current = root.currentSettlement
    if current.raidId ~= raidId or (current.expiresAt and now >= current.expiresAt) then
        M.clearSettlement(root)
        current = root.currentSettlement
        current.raidId = raidId
        current.sourceFb = source and source.fb or nil
        current.sourceRealm = source and source.realm or nil
        current.startedAt = now
        current.expiresAt = now + MAX_AGE
    elseif source then
        -- Upgrade an in-flight settlement created before source attribution
        -- was introduced without discarding its current-raid records.
        if current.sourceFb == nil then
            current.sourceFb = source.fb
        end
        if current.sourceRealm == nil then
            current.sourceRealm = source.realm
        end
    end
    return current
end

function M.beginRaid(root, raidId, now)
    local currentRaid = root.currentRaid
    if currentRaid.raidId ~= raidId then
        root.currentRaid = {
            raidId = raidId,
            startedAt = now,
            purchases = {},
        }
    end
    local settlement = M.beginSettlement(root, raidId, now)
    return root.currentRaid, settlement
end

function M.purgeExpired(root, now)
    local expiresAt = root.currentSettlement.expiresAt
    if expiresAt and now >= expiresAt then
        M.clearSettlement(root)
        return true
    end
    return false
end

BG.BGNext.DataLifecycle = M

if BG.Init then
    BG.Init(function()
        BiaoGe = type(BiaoGe) == "table" and BiaoGe or {}
        BG.BGNext.DB = M.ensureRoot(BiaoGe)
        M.purgeExpired(BG.BGNext.DB, serverNow())
    end)
end

return M
