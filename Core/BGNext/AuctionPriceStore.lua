BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Validated storage and price resolution for the two local price-preset features:
-- leader starting-price schemes and per-character personal expectations. This
-- module never creates frames, never reads the retired auto-bid presets and
-- never communicates. All writes rebuild records from a strict whitelist.
local M = {}

M.MAX_MONEY = 10000000
M.MAX_PRESETS = 20
M.MAX_ITEMS = 500
M.MAX_NAME_CHARS = 24

-- Fresh-install global starting-price defaults per canonical BGNext client
-- family (matches OwnCharactersAdapters.families). Only used when the local
-- BiaoGe.Auction.money is missing or invalid; an existing user value is never
-- overwritten.
local DEFAULTS = {
    vanilla = 100, tbc = 100, wrath = 1000, titan = 100,
    cata = 100000, mop = 10000, retail = 100000,
}

function M.defaultGlobalPrice(clientFamily)
    return DEFAULTS[clientFamily]
end

local function validKey(value)
    return type(value) == "string" and value ~= ""
end

function M.isValidRealmId(value)
    if type(value) ~= "number" then return false end
    if value ~= value or value == math.huge or value == -math.huge then return false end
    return value % 1 == 0 and value > 0
end

local function validItemId(value)
    if type(value) ~= "number" then return false end
    if value ~= value or value == math.huge or value == -math.huge then return false end
    return value % 1 == 0 and value > 0
end

local function validMoney(value)
    if type(value) ~= "number" then return nil end
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    if value % 1 ~= 0 or value < 0 or value > M.MAX_MONEY then return nil end
    return value
end

-- Counts UTF-8 code points and rejects malformed sequences so a name is never
-- truncated mid-character. Returns nil for a non-string or malformed value.
local function utf8CodePoints(s)
    if type(s) ~= "string" then return nil end
    local count = 0
    local i, n = 1, #s
    while i <= n do
        local b = s:byte(i)
        local length
        if b < 0x80 then
            length = 1
        elseif b >= 0xC0 and b <= 0xDF then
            length = 2
        elseif b >= 0xE0 and b <= 0xEF then
            length = 3
        elseif b >= 0xF0 and b <= 0xF7 then
            length = 4
        else
            return nil
        end
        if i + length - 1 > n then return nil end
        for j = 1, length - 1 do
            local c = s:byte(i + j)
            if not c or c < 0x80 or c > 0xBF then return nil end
        end
        count = count + 1
        i = i + length
    end
    return count
end

local function validName(value)
    if type(value) ~= "string" then return nil end
    local len = utf8CodePoints(value)
    if not len or len < 1 or len > M.MAX_NAME_CHARS then return nil end
    return value
end

local function countKeys(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function nextPresetId(presets)
    local i = 1
    while presets["p" .. i] ~= nil do
        i = i + 1
    end
    return "p" .. i
end

local function getRaid(root, clientFamily, raidId, create)
    if type(root) ~= "table" or not validKey(clientFamily) or not validKey(raidId) then
        return nil
    end
    local store = root.leaderAuctionPricePresets
    if type(store) ~= "table" then
        if not create then return nil end
        store = {}
        root.leaderAuctionPricePresets = store
    end
    local family = store[clientFamily]
    if type(family) ~= "table" then
        if not create then return nil end
        family = {}
        store[clientFamily] = family
    end
    local raid = family[raidId]
    if type(raid) ~= "table" then
        if not create then return nil end
        raid = {}
        family[raidId] = raid
    end
    return raid
end

function M.ensureLeaderRaid(root, clientFamily, raidId, currentGlobalPrice)
    local raid = getRaid(root, clientFamily, raidId, true)
    if not raid then return nil end
    if type(raid.presets) ~= "table" then
        local basePrice = validMoney(currentGlobalPrice) or M.defaultGlobalPrice(clientFamily)
        raid.activePresetId = "p1"
        raid.presets = {
            p1 = { name = "默认方案", basePrice = basePrice, itemPrices = {} },
        }
    end
    return raid
end

function M.createPreset(root, clientFamily, raidId, name, basePrice)
    local raid = getRaid(root, clientFamily, raidId, false)
    if not raid or type(raid.presets) ~= "table" then return nil end
    local cleanName = validName(name)
    local cleanPrice = validMoney(basePrice)
    if not cleanName or cleanPrice == nil then return nil end
    if countKeys(raid.presets) >= M.MAX_PRESETS then return nil end
    local id = nextPresetId(raid.presets)
    raid.presets[id] = { name = cleanName, basePrice = cleanPrice, itemPrices = {} }
    return id
end

function M.copyPreset(root, clientFamily, raidId, presetId, newName)
    local raid = getRaid(root, clientFamily, raidId, false)
    if not raid or type(raid.presets) ~= "table" then return nil end
    local source = raid.presets[presetId]
    if type(source) ~= "table" then return nil end
    if countKeys(raid.presets) >= M.MAX_PRESETS then return nil end
    local name
    if newName ~= nil then
        name = validName(newName)
        if not name then return nil end
    else
        name = validName(source.name) or "默认方案"
    end
    local basePrice = validMoney(source.basePrice) or M.defaultGlobalPrice(clientFamily)
    local copy = { name = name, basePrice = basePrice, itemPrices = {} }
    if type(source.itemPrices) == "table" then
        for k, v in pairs(source.itemPrices) do
            if type(k) == "number" and type(v) == "number" then
                copy.itemPrices[k] = v
            end
        end
    end
    local id = nextPresetId(raid.presets)
    raid.presets[id] = copy
    return id
end

function M.renamePreset(root, clientFamily, raidId, presetId, newName)
    local raid = getRaid(root, clientFamily, raidId, false)
    if not raid or type(raid.presets) ~= "table" then return false end
    local preset = raid.presets[presetId]
    if type(preset) ~= "table" then return false end
    local name = validName(newName)
    if not name then return false end
    preset.name = name
    return true
end

function M.deletePreset(root, clientFamily, raidId, presetId, fallbackPresetId)
    local raid = getRaid(root, clientFamily, raidId, false)
    if not raid or type(raid.presets) ~= "table" then return false end
    if type(raid.presets[presetId]) ~= "table" then return false end
    if countKeys(raid.presets) <= 1 then return false end
    if presetId == raid.activePresetId then
        if type(raid.presets[fallbackPresetId]) ~= "table" or fallbackPresetId == presetId then
            return false
        end
        raid.activePresetId = fallbackPresetId
    end
    raid.presets[presetId] = nil
    return true
end

function M.selectPreset(root, clientFamily, raidId, presetId)
    local raid = getRaid(root, clientFamily, raidId, false)
    if not raid or type(raid.presets) ~= "table" then return false end
    if type(raid.presets[presetId]) ~= "table" then return false end
    raid.activePresetId = presetId
    return true
end

function M.setBasePrice(root, clientFamily, raidId, presetId, money)
    local raid = getRaid(root, clientFamily, raidId, false)
    if not raid or type(raid.presets) ~= "table" then return false end
    local preset = raid.presets[presetId]
    if type(preset) ~= "table" then return false end
    local value = validMoney(money)
    if value == nil then return false end
    preset.basePrice = value
    return true
end

function M.setLeaderItemPrice(root, clientFamily, raidId, presetId, itemId, money)
    local raid = getRaid(root, clientFamily, raidId, false)
    if not raid or type(raid.presets) ~= "table" then return false end
    local preset = raid.presets[presetId]
    if type(preset) ~= "table" then return false end
    if not validItemId(itemId) then return false end
    local value = validMoney(money)
    if value == nil then return false end
    local itemPrices = preset.itemPrices
    if type(itemPrices) ~= "table" then
        itemPrices = {}
        preset.itemPrices = itemPrices
    end
    if itemPrices[itemId] == nil and countKeys(itemPrices) >= M.MAX_ITEMS then
        return false
    end
    itemPrices[itemId] = value
    return true
end

function M.clearLeaderItemPrice(root, clientFamily, raidId, presetId, itemId)
    local raid = getRaid(root, clientFamily, raidId, false)
    if not raid or type(raid.presets) ~= "table" then return false end
    local preset = raid.presets[presetId]
    if type(preset) ~= "table" then return false end
    if type(preset.itemPrices) ~= "table" or preset.itemPrices[itemId] == nil then
        return false
    end
    preset.itemPrices[itemId] = nil
    return true
end

function M.resolveLeaderPrice(root, clientFamily, raidId, itemId)
    local raid = getRaid(root, clientFamily, raidId, false)
    if not raid or type(raid.presets) ~= "table" then return nil end
    local preset = raid.presets[raid.activePresetId]
    if type(preset) ~= "table" then
        -- Fall back to the first structurally valid preset when the active id
        -- is missing or corrupted; otherwise return nil (unresolved).
        for _, candidate in pairs(raid.presets) do
            if type(candidate) == "table" and type(candidate.basePrice) == "number" then
                preset = candidate
                break
            end
        end
        if not preset then return nil end
    end
    if type(preset.itemPrices) == "table" and preset.itemPrices[itemId] ~= nil then
        local value = preset.itemPrices[itemId]
        if type(value) == "number" then return value end
    end
    if type(preset.basePrice) == "number" then return preset.basePrice end
    return nil
end

local function personalRaid(root, clientFamily, realmId, player, raidId, create)
    if type(root) ~= "table" or not validKey(clientFamily) or not M.isValidRealmId(realmId)
        or not validKey(player) or not validKey(raidId) then
        return nil
    end
    local store = root.personalAuctionExpectations
    if type(store) ~= "table" then
        if not create then return nil end
        store = {}
        root.personalAuctionExpectations = store
    end
    local family = store[clientFamily]
    if type(family) ~= "table" then
        if not create then return nil end
        family = {}
        store[clientFamily] = family
    end
    local realm = family[realmId]
    if type(realm) ~= "table" then
        if not create then return nil end
        realm = {}
        family[realmId] = realm
    end
    local playerT = realm[player]
    if type(playerT) ~= "table" then
        if not create then return nil end
        playerT = {}
        realm[player] = playerT
    end
    local raid = playerT[raidId]
    if type(raid) ~= "table" then
        if not create then return nil end
        raid = {}
        playerT[raidId] = raid
    end
    return raid
end

-- Removes a personal raid record and prunes every ancestor that became empty, so
-- cleared expectations do not leave empty leaf tables behind.
local function dropRaidAndPrune(root, clientFamily, realmId, player, raidId)
    local store = root and root.personalAuctionExpectations
    if type(store) ~= "table" then return end
    local family = store[clientFamily]
    if type(family) ~= "table" then return end
    local realm = family[realmId]
    if type(realm) ~= "table" then return end
    local playerT = realm[player]
    if type(playerT) ~= "table" then return end
    playerT[raidId] = nil
    if next(playerT) == nil then realm[player] = nil end
    if next(realm) == nil then family[realmId] = nil end
    if next(family) == nil then store[clientFamily] = nil end
end

function M.setPersonalPrice(root, clientFamily, realmId, player, raidId, itemId, money)
    if not validItemId(itemId) then return false end
    local value = validMoney(money)
    if value == nil then return false end
    local raid = personalRaid(root, clientFamily, realmId, player, raidId, true)
    if not raid then return false end
    local itemPrices = raid.itemPrices
    if type(itemPrices) ~= "table" then
        itemPrices = {}
        raid.itemPrices = itemPrices
    end
    if itemPrices[itemId] == nil and countKeys(itemPrices) >= M.MAX_ITEMS then
        return false
    end
    itemPrices[itemId] = value
    return true
end

function M.getPersonalPrice(root, clientFamily, realmId, player, raidId, itemId)
    local raid = personalRaid(root, clientFamily, realmId, player, raidId, false)
    if not raid or type(raid.itemPrices) ~= "table" then return nil end
    return raid.itemPrices[itemId]
end

function M.clearPersonalPrice(root, clientFamily, realmId, player, raidId, itemId)
    local raid = personalRaid(root, clientFamily, realmId, player, raidId, false)
    if not raid or type(raid.itemPrices) ~= "table" then return false end
    if raid.itemPrices[itemId] == nil then return false end
    raid.itemPrices[itemId] = nil
    if next(raid.itemPrices) == nil then
        dropRaidAndPrune(root, clientFamily, realmId, player, raidId)
    end
    return true
end

function M.clearPersonalRaid(root, clientFamily, realmId, player, raidId)
    local raid = personalRaid(root, clientFamily, realmId, player, raidId, false)
    if not raid then return false end
    dropRaidAndPrune(root, clientFamily, realmId, player, raidId)
    return true
end

function M.countPersonalPrices(root, clientFamily, realmId, player, raidId)
    local raid = personalRaid(root, clientFamily, realmId, player, raidId, false)
    if not raid or type(raid.itemPrices) ~= "table" then return 0 end
    return countKeys(raid.itemPrices)
end

BG.BGNext.AuctionPriceStore = M
return M
