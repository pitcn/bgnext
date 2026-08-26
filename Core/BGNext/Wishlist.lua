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
