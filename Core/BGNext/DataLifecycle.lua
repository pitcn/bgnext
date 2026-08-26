BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}
local MAX_AGE = 7 * 86400

local function emptySettlement()
    return {
        raidId = nil,
        startedAt = nil,
        expiresAt = nil,
        trades = {},
        mails = {},
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
    root.currentRaid = root.currentRaid or {}
    root.auctionPresets = root.auctionPresets or {}
    root.currentSettlement = root.currentSettlement or emptySettlement()
    return root
end

function M.clearSettlement(root)
    root.currentSettlement = emptySettlement()
end

function M.beginSettlement(root, raidId, now)
    local current = root.currentSettlement
    if current.raidId ~= raidId or (current.expiresAt and now >= current.expiresAt) then
        M.clearSettlement(root)
        current = root.currentSettlement
        current.raidId = raidId
        current.startedAt = now
        current.expiresAt = now + MAX_AGE
    end
    return current
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
        M.purgeExpired(BG.BGNext.DB, time())
    end)
end

return M
