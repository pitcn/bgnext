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

-- Forever requires a surname. Discard ambiguous first-name observations,
-- never transfer them to a guessed complete identity. Work only at known
-- character boundaries; snapshot fields and filter profile names are not keys.
local function pruneForeverShortKeys(root)
    local function singleName(name)
        return type(name) == "string" and name:match("^[^%s%-]+$") ~= nil
    end
    local function realmKey(value)
        return type(value) == "number" or (type(value) == "string" and value ~= "")
    end
    local realms = {}
    if realmKey(BG.realmID) then realms[BG.realmID] = true end
    local family = root.ownCharacters.forever
    for realmId, characters in pairs(type(family) == "table" and family or {}) do
        if realmKey(realmId) and type(characters) == "table" then
            for player, snapshot in pairs(characters) do
                if type(snapshot) == "table" and snapshot.player == player
                    and snapshot.realmId == realmId then
                    realms[realmId] = true
                    if singleName(player) then characters[player] = nil end
                end
            end
        end
    end
    local order = root.roleOverviewCharacterOrder.forever
    if type(order) == "table" then
        for index = #order, 1, -1 do
            local entry = order[index]
            if type(entry) == "table" and realmKey(entry.realmId) and type(entry.player) == "string" then
                realms[entry.realmId] = true
                if singleName(entry.player) then table.remove(order, index) end
            end
        end
    end
    -- Filters have no family dimension: touch only realms evidenced above or
    -- the current Forever realm, and only the established character-state shape.
    for realmId in pairs(realms) do
        local filters = root.equipmentFilters[realmId]
        for player, state in pairs(type(filters) == "table" and filters or {}) do
            if singleName(player) and type(state) == "table"
                and type(state.profiles) == "table" and type(state.order) == "table" then
                filters[player] = nil
            end
        end
    end
end

-- Single scalar dedupe marker of the Forever "clear previous bill?" prompt.
-- Rebuilt from its whitelisted fields only, so nothing else can persist there,
-- and dropped when malformed or older than the seven-day retention limit.
local function sanitizeBillResetPrompt(root)
    local marker = root.billResetPrompt
    if marker == nil then return end
    local now = serverNow()
    if type(marker) ~= "table" or type(marker.fb) ~= "string" or marker.fb == ""
        or type(marker.billStamp) ~= "number" or type(marker.at) ~= "number"
        or now - marker.at >= MAX_AGE then
        root.billResetPrompt = nil
        return
    end
    root.billResetPrompt = {
        fb = marker.fb,
        billStamp = marker.billStamp,
        newTeamAsked = marker.newTeamAsked == true or nil,
        resetAskedKey = type(marker.resetAskedKey) == "string" and marker.resetAskedKey or nil,
        at = marker.at,
    }
end

function M.ensureRoot(saved)
    saved.BGNext = type(saved.BGNext) == "table" and saved.BGNext or {}
    local root = saved.BGNext
    root.schemaVersion = 1
    root.settings = type(root.settings) == "table" and root.settings or {}
    root.wishlist = type(root.wishlist) == "table" and root.wishlist or {}
    root.equipmentFilters = type(root.equipmentFilters) == "table" and root.equipmentFilters or {}
    root.ownCharacters = type(root.ownCharacters) == "table" and root.ownCharacters or {}
    root.roleOverviewCharacterOrder = type(root.roleOverviewCharacterOrder) == "table"
        and root.roleOverviewCharacterOrder or {}
    if BG.IsForever then pruneForeverShortKeys(root) end
    root.leaderAuctionPricePresets = type(root.leaderAuctionPricePresets) == "table"
        and root.leaderAuctionPricePresets or {}
    root.personalAuctionExpectations = type(root.personalAuctionExpectations) == "table"
        and root.personalAuctionExpectations or {}
    root.leaderTools = type(root.leaderTools) == "table" and root.leaderTools or {}
    root.leaderTools.expenseTemplates = type(root.leaderTools.expenseTemplates) == "table"
        and root.leaderTools.expenseTemplates or {}
    root.leaderTools.localHistory = type(root.leaderTools.localHistory) == "table"
        and root.leaderTools.localHistory or {}
    if root.leaderTools.historyRetentionDays ~= 30 and root.leaderTools.historyRetentionDays ~= 90
        and root.leaderTools.historyRetentionDays ~= 180 then
        root.leaderTools.historyRetentionDays = 90
    end
    sanitizeBillResetPrompt(root)
    root.currentRaid = type(root.currentRaid) == "table" and root.currentRaid or {}
    root.currentRaid.purchases = type(root.currentRaid.purchases) == "table" and root.currentRaid.purchases or {}
    root.currentSettlement = type(root.currentSettlement) == "table" and root.currentSettlement or emptySettlement()
    root.currentSettlement.trades = type(root.currentSettlement.trades) == "table"
        and root.currentSettlement.trades or {}
    root.currentSettlement.mails = type(root.currentSettlement.mails) == "table"
        and root.currentSettlement.mails or {}
    root.currentSettlement.returns = type(root.currentSettlement.returns) == "table"
        and root.currentSettlement.returns or {}
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
