BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

local function validText(value)
    return type(value) == "string" and value:find("%S") ~= nil
end

local function validContextKey(value)
    return validText(value) or type(value) == "number"
end

local function validItemId(itemId)
    return type(itemId) == "number" and itemId > 0 and itemId == math.floor(itemId)
end

local function validPositiveIndex(value)
    return type(value) == "number" and value > 0 and value == math.floor(value)
end

local function validLimits(limits, difficultyIndex, bossIndex, slotIndex)
    return type(limits) == "table"
        and validPositiveIndex(limits.difficulties)
        and validPositiveIndex(limits.bosses)
        and validPositiveIndex(limits.slots)
        and validPositiveIndex(difficultyIndex)
        and validPositiveIndex(bossIndex)
        and validPositiveIndex(slotIndex)
        and difficultyIndex <= limits.difficulties
        and bossIndex <= limits.bosses
        and slotIndex <= limits.slots
end

function M.itemIdFromValue(value)
    if validItemId(value) then
        return value
    end
    if type(value) ~= "string" then
        return nil
    end
    local itemId = tonumber(value:match("^%s*(%d+)%s*$") or value:match("item:(%d+)"))
    if validItemId(itemId) then
        return itemId
    end
    return nil
end

local function getRaid(root, realmId, player, raidId, create)
    if type(root) ~= "table" or type(root.wishlist) ~= "table" then
        return nil
    end
    if not validContextKey(realmId) or not validText(player) or not validContextKey(raidId) then
        return nil
    end
    local realm = root.wishlist[realmId]
    if not realm and create then
        realm = {}
        root.wishlist[realmId] = realm
    end
    local character = realm and realm[player]
    if not character and create then
        character = {}
        realm[player] = character
    end
    local raid = character and character[raidId]
    if not raid and create then
        raid = {}
        character[raidId] = raid
    end
    return raid
end

local function getBossSlots(root, realmId, player, raidId, difficultyIndex, bossIndex)
    local raid = getRaid(root, realmId, player, raidId, false)
    return raid and raid[difficultyIndex] and raid[difficultyIndex][bossIndex] or nil
end

function M.setSlot(root, realmId, player, raidId, limits, difficultyIndex, bossIndex, slotIndex, itemId)
    if not validItemId(itemId) or not validLimits(limits, difficultyIndex, bossIndex, slotIndex) then
        return false
    end
    local raid = getRaid(root, realmId, player, raidId, true)
    if not raid then
        return false
    end
    raid[difficultyIndex] = raid[difficultyIndex] or {}
    raid[difficultyIndex][bossIndex] = raid[difficultyIndex][bossIndex] or {}
    raid[difficultyIndex][bossIndex][slotIndex] = itemId
    return true
end

function M.getSlot(root, realmId, player, raidId, difficultyIndex, bossIndex, slotIndex)
    local slots = getBossSlots(root, realmId, player, raidId, difficultyIndex, bossIndex)
    return slots and slots[slotIndex] or nil
end

function M.clearSlot(root, realmId, player, raidId, difficultyIndex, bossIndex, slotIndex)
    local slots = getBossSlots(root, realmId, player, raidId, difficultyIndex, bossIndex)
    if not slots or slots[slotIndex] == nil then
        return false
    end
    slots[slotIndex] = nil
    return true
end

function M.findItem(root, realmId, player, raidId, itemId)
    local result = {}
    if not validItemId(itemId) then
        return result
    end
    local raid = getRaid(root, realmId, player, raidId, false)
    if raid then
        for difficultyIndex, bosses in pairs(raid) do
            if validPositiveIndex(difficultyIndex) and type(bosses) == "table" then
                for bossIndex, slots in pairs(bosses) do
                    if validPositiveIndex(bossIndex) and type(slots) == "table" then
                        for slotIndex, storedItemId in pairs(slots) do
                            if validPositiveIndex(slotIndex) and storedItemId == itemId then
                                result[#result + 1] = {
                                    difficultyIndex = difficultyIndex,
                                    bossIndex = bossIndex,
                                    slotIndex = slotIndex,
                                }
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(result, function(left, right)
        if left.difficultyIndex ~= right.difficultyIndex then
            return left.difficultyIndex < right.difficultyIndex
        end
        if left.bossIndex ~= right.bossIndex then
            return left.bossIndex < right.bossIndex
        end
        return left.slotIndex < right.slotIndex
    end)
    return result
end

function M.clearRaid(root, realmId, player, raidId)
    local raid = getRaid(root, realmId, player, raidId, false)
    if not raid or not next(raid) then
        return false
    end
    for key in pairs(raid) do
        raid[key] = nil
    end
    return true
end

function M.placeItem(root, realmId, player, raidId, limits, itemId, resolver)
    if not validItemId(itemId) or type(resolver) ~= "function" then
        return { ok = false, reason = "unknown-drop" }
    end
    local location = resolver(itemId, raidId)
    if type(location) ~= "table"
        or not validLimits(limits, location.difficultyIndex, location.bossIndex, 1)
    then
        return { ok = false, reason = "unknown-drop" }
    end
    for slotIndex = 1, limits.slots do
        if M.getSlot(root, realmId, player, raidId, location.difficultyIndex, location.bossIndex, slotIndex) == nil then
            M.setSlot(root, realmId, player, raidId, limits, location.difficultyIndex, location.bossIndex, slotIndex, itemId)
            return {
                ok = true,
                difficultyIndex = location.difficultyIndex,
                bossIndex = location.bossIndex,
                slotIndex = slotIndex,
            }
        end
    end
    return { ok = false, reason = "boss-full" }
end

local function getUnplacedRaid(root, realmId, player, raidId, create)
    if type(root) ~= "table" or not validContextKey(realmId) or not validText(player) or not validContextKey(raidId) then
        return nil
    end
    if type(root.wishlistUnplaced) ~= "table" then
        if not create then return nil end
        root.wishlistUnplaced = {}
    end
    local realm = root.wishlistUnplaced[realmId]
    if not realm and create then
        realm = {}
        root.wishlistUnplaced[realmId] = realm
    end
    local character = realm and realm[player]
    if not character and create then
        character = {}
        realm[player] = character
    end
    local raid = character and character[raidId]
    if not raid and create then
        raid = {}
        character[raidId] = raid
    end
    return raid
end

function M.migrateFlatRaid(root, realmId, player, raidId, limits, resolver)
    local raid = getRaid(root, realmId, player, raidId, false)
    local itemIds = {}
    if raid then
        for key, value in pairs(raid) do
            if validItemId(key) and value == true then
                itemIds[#itemIds + 1] = key
            end
        end
    end
    if #itemIds == 0 then
        return { changed = false, placed = 0, quarantined = 0 }
    end
    table.sort(itemIds)

    local temporaryRoot = { wishlist = {} }
    local placed, quarantined = 0, 0
    local unplacedItems = {}
    for _, itemId in ipairs(itemIds) do
        local result = M.placeItem(temporaryRoot, realmId, player, raidId, limits, itemId, resolver)
        if result.ok then
            placed = placed + 1
        else
            quarantined = quarantined + 1
            unplacedItems[itemId] = true
        end
    end

    for key in pairs(raid) do
        raid[key] = nil
    end
    local migratedRaid = getRaid(temporaryRoot, realmId, player, raidId, false) or {}
    for difficultyIndex, bosses in pairs(migratedRaid) do
        raid[difficultyIndex] = bosses
    end
    if next(unplacedItems) then
        local unplacedRaid = getUnplacedRaid(root, realmId, player, raidId, true)
        for itemId in pairs(unplacedItems) do
            unplacedRaid[itemId] = true
        end
    end
    return { changed = true, placed = placed, quarantined = quarantined }
end

function M.add(root, realmId, player, raidId, itemId)
    if not validItemId(itemId) then
        return false
    end
    local raid = getRaid(root, realmId, player, raidId, true)
    if not raid or raid[itemId] then
        return false
    end
    raid[itemId] = true
    return true
end

function M.remove(root, realmId, player, raidId, itemId)
    local raid = getRaid(root, realmId, player, raidId, false)
    if not raid or not raid[itemId] then
        return false
    end
    raid[itemId] = nil
    return true
end

function M.clear(root, realmId, player, raidId)
    local raid = getRaid(root, realmId, player, raidId, false)
    if not raid or not next(raid) then
        return false
    end
    for itemId in pairs(raid) do
        raid[itemId] = nil
    end
    return true
end

function M.contains(root, realmId, player, raidId, itemId)
    local raid = getRaid(root, realmId, player, raidId, false)
    return (raid ~= nil and raid[itemId] == true) or #M.findItem(root, realmId, player, raidId, itemId) > 0
end

function M.toggle(root, realmId, player, raidId, itemId)
    if M.contains(root, realmId, player, raidId, itemId) then
        M.remove(root, realmId, player, raidId, itemId)
        return false
    end
    if M.add(root, realmId, player, raidId, itemId) then
        return true
    end
    return nil
end

function M.list(root, realmId, player, raidId)
    local result = {}
    local raid = getRaid(root, realmId, player, raidId, false)
    if raid then
        for itemId, enabled in pairs(raid) do
            if enabled == true then
                result[#result + 1] = itemId
            end
        end
        table.sort(result)
    end
    return result
end

BG.BGNext.Wishlist = M
return M
