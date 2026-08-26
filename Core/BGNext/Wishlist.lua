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

function M.exportRaid(root, realmId, player, raidId, limits)
    if type(limits) ~= "table"
        or not validPositiveIndex(limits.difficulties)
        or not validPositiveIndex(limits.bosses)
        or not validPositiveIndex(limits.slots)
    then
        return nil
    end
    local sections = {}
    for difficultyIndex = 1, limits.difficulties do
        for bossIndex = 1, limits.bosses do
            local itemIds = {}
            for slotIndex = 1, limits.slots do
                local itemId = M.getSlot(root, realmId, player, raidId, difficultyIndex, bossIndex, slotIndex)
                if validItemId(itemId) then
                    itemIds[#itemIds + 1] = tostring(itemId)
                end
            end
            if #itemIds > 0 then
                sections[#sections + 1] = "n" .. difficultyIndex .. "b" .. bossIndex .. "-" .. table.concat(itemIds, "-")
            end
        end
    end
    if #sections == 0 then
        return nil
    end
    return tostring(raidId) .. ":" .. table.concat(sections, ",")
end

local function splitPlain(text, separator)
    local result = {}
    local startAt = 1
    while true do
        local separatorAt = text:find(separator, startAt, true)
        if not separatorAt then
            result[#result + 1] = text:sub(startAt)
            return result
        end
        result[#result + 1] = text:sub(startAt, separatorAt - 1)
        startAt = separatorAt + #separator
    end
end

local function parseFailure(reason)
    return { ok = false, reason = reason, raids = {}, itemCount = 0 }
end

function M.parseImport(text, limitsByRaid)
    if not validText(text) then
        return parseFailure("empty")
    end
    if #text > 32768 then
        return parseFailure("too-large")
    end
    if type(limitsByRaid) ~= "table" then
        return parseFailure("unknown-raid")
    end

    local raids, itemCount = {}, 0
    for _, raidSection in ipairs(splitPlain(text, ".")) do
        local raidId, payload = raidSection:match("^([^:]+):(.+)$")
        local limits = raidId and limitsByRaid[raidId] or nil
        if not raidId or not limits then
            return parseFailure("unknown-raid")
        end
        if raids[raidId] then
            return parseFailure("invalid-section")
        end
        local raid = {}
        for _, bossSection in ipairs(splitPlain(payload, ",")) do
            local difficultyText, bossText, itemText = bossSection:match("^n(%d+)b(%d+)%-(.+)$")
            if not difficultyText then
                return parseFailure("invalid-section")
            end
            local difficultyIndex, bossIndex = tonumber(difficultyText), tonumber(bossText)
            if not validLimits(limits, difficultyIndex, bossIndex, 1) then
                return parseFailure("out-of-range")
            end
            raid[difficultyIndex] = raid[difficultyIndex] or {}
            if raid[difficultyIndex][bossIndex] then
                return parseFailure("invalid-section")
            end
            local slots = {}
            for _, itemPart in ipairs(splitPlain(itemText, "-")) do
                if not itemPart:match("^%d+$") then
                    return parseFailure("invalid-item")
                end
                local itemId = tonumber(itemPart)
                if not validItemId(itemId) then
                    return parseFailure("invalid-item")
                end
                if #slots >= limits.slots then
                    return parseFailure("too-many-items")
                end
                slots[#slots + 1] = itemId
                itemCount = itemCount + 1
            end
            raid[difficultyIndex][bossIndex] = slots
        end
        raids[raidId] = raid
    end
    if itemCount == 0 then
        return parseFailure("empty")
    end
    return { ok = true, raids = raids, itemCount = itemCount }
end

function M.applyImport(root, realmId, player, parsed)
    if type(parsed) ~= "table" or parsed.ok ~= true or type(parsed.raids) ~= "table" then
        return false
    end
    if type(root) ~= "table" or type(root.wishlist) ~= "table"
        or not validContextKey(realmId) or not validText(player)
    then
        return false
    end
    for raidId, importedRaid in pairs(parsed.raids) do
        local raid = getRaid(root, realmId, player, raidId, true)
        for key in pairs(raid) do
            raid[key] = nil
        end
        for difficultyIndex, importedBosses in pairs(importedRaid) do
            local bosses = {}
            raid[difficultyIndex] = bosses
            for bossIndex, importedSlots in pairs(importedBosses) do
                local slots = {}
                bosses[bossIndex] = slots
                for slotIndex, itemId in ipairs(importedSlots) do
                    slots[slotIndex] = itemId
                end
            end
        end
    end
    return true
end

function M.contains(root, realmId, player, raidId, itemId)
    return #M.findItem(root, realmId, player, raidId, itemId) > 0
end

BG.BGNext.Wishlist = M
return M
