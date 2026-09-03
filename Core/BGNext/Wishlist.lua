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

-- Local per-item wish priority. The three-value enum is stable because it is
-- written into SavedVariables and export text; display names live in Locales.
local PRIORITY_RANK = { backup = 1, normal = 2, core = 3 }
local PRIORITY_CYCLE = { "backup", "normal", "core" }
local PRIORITY_TAG_KEYS = { core = "BIS", normal = "次BIS", backup = "备选" }
local PRIORITY_NAME_KEYS = { core = "核心提升", normal = "普通需求", backup = "备选" }
local PRIORITY_TIP_KEYS = {
    core = "BIS：核心提升，最高优先级的毕业装备。",
    normal = "次BIS：普通需求，明确的提升或第二选择。",
    backup = "备选：过渡装备，或无人需求时才考虑。",
}

function M.normalizePriority(value)
    if type(value) == "string" and PRIORITY_RANK[value] then
        return value
    end
    return "normal"
end

-- A slot stores either the historical plain itemId number (default priority, so
-- old SavedVariables stay byte-identical) or, only for core/backup, a record
-- table. The priority therefore always dies with its slot: no parallel table,
-- no orphan data.
-- Hot scan paths (contains / highestPriority / findItem over every boss and
-- slot) decode through these scalar helpers; only callers that actually need a
-- record object go through readRecord, so a full wish scan allocates nothing.
local function slotItemId(value)
    if validItemId(value) then
        return value
    end
    if type(value) == "table" then
        local item = value.item
        if validItemId(item) then
            return item
        end
    end
    return nil
end

local function slotPriority(value)
    if validItemId(value) then
        return "normal"
    end
    if type(value) == "table" and validItemId(value.item) then
        return M.normalizePriority(value.priority)
    end
    return nil
end

local function readRecord(value)
    local itemId = slotItemId(value)
    if not itemId then
        return nil
    end
    return { itemId = itemId, priority = slotPriority(value) }
end

local function encodeSlot(itemId, priority)
    priority = M.normalizePriority(priority)
    if priority == "normal" then
        return itemId
    end
    return { item = itemId, priority = priority }
end

function M.cyclePriority(priority, direction)
    local index = PRIORITY_RANK[M.normalizePriority(priority)]
    local step = (direction and direction > 0) and 1 or -1
    index = ((index - 1 + step) % #PRIORITY_CYCLE) + 1
    return PRIORITY_CYCLE[index]
end

function M.priorityTagKey(priority)
    return PRIORITY_TAG_KEYS[M.normalizePriority(priority)]
end

function M.priorityNameKey(priority)
    return PRIORITY_NAME_KEYS[M.normalizePriority(priority)]
end

function M.priorityTipKey(priority)
    return PRIORITY_TIP_KEYS[M.normalizePriority(priority)]
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

-- Resolve an item against a raid loot catalog. Some encounters use the same
-- item ID for more than one difficulty (for example Garrosh essence tokens in
-- MoP). When a concrete wishlist cell is being edited, prefer that exact
-- difficulty/boss before falling back to the catalog's normal search order.
function M.resolveDrop(itemId, difficultyNames, raidLoot, bossLimit, sameItem,
    preferredDifficultyIndex, preferredBossIndex)
    if not validItemId(itemId) or type(difficultyNames) ~= "table"
        or type(raidLoot) ~= "table" or not validPositiveIndex(bossLimit)
        or type(sameItem) ~= "function"
    then
        return nil
    end

    local function matches(difficultyIndex, bossIndex)
        local difficultyName = difficultyNames[difficultyIndex]
        local difficultyLoot = difficultyName and raidLoot[difficultyName]
        local drops = difficultyLoot and difficultyLoot["boss" .. bossIndex]
        if type(drops) ~= "table" then return false end
        for _, droppedItemId in ipairs(drops) do
            if sameItem(itemId, droppedItemId) then return true end
        end
        return false
    end

    if validPositiveIndex(preferredDifficultyIndex)
        and validPositiveIndex(preferredBossIndex)
        and preferredBossIndex <= bossLimit
        and matches(preferredDifficultyIndex, preferredBossIndex)
    then
        return {
            difficultyIndex = preferredDifficultyIndex,
            bossIndex = preferredBossIndex,
        }
    end

    for difficultyIndex in ipairs(difficultyNames) do
        for bossIndex = 1, bossLimit do
            if matches(difficultyIndex, bossIndex) then
                return {
                    difficultyIndex = difficultyIndex,
                    bossIndex = bossIndex,
                }
            end
        end
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

function M.getSlotRecord(root, realmId, player, raidId, difficultyIndex, bossIndex, slotIndex)
    local slots = getBossSlots(root, realmId, player, raidId, difficultyIndex, bossIndex)
    return slots and readRecord(slots[slotIndex]) or nil
end

function M.getSlotPriority(root, realmId, player, raidId, difficultyIndex, bossIndex, slotIndex)
    local slots = getBossSlots(root, realmId, player, raidId, difficultyIndex, bossIndex)
    return slots and slotPriority(slots[slotIndex]) or nil
end

function M.setSlotPriority(root, realmId, player, raidId, difficultyIndex, bossIndex, slotIndex, priority)
    local slots = getBossSlots(root, realmId, player, raidId, difficultyIndex, bossIndex)
    if not slots then
        return false
    end
    local itemId = slotItemId(slots[slotIndex])
    if not itemId then
        return false
    end
    slots[slotIndex] = encodeSlot(itemId, priority)
    return true
end

function M.setSlot(root, realmId, player, raidId, limits, difficultyIndex, bossIndex, slotIndex, itemId, priority)
    if not validItemId(itemId) or not validLimits(limits, difficultyIndex, bossIndex, slotIndex) then
        return false
    end
    local raid = getRaid(root, realmId, player, raidId, true)
    if not raid then
        return false
    end
    raid[difficultyIndex] = raid[difficultyIndex] or {}
    raid[difficultyIndex][bossIndex] = raid[difficultyIndex][bossIndex] or {}
    raid[difficultyIndex][bossIndex][slotIndex] = encodeSlot(itemId, priority)
    return true
end

function M.getSlot(root, realmId, player, raidId, difficultyIndex, bossIndex, slotIndex)
    local slots = getBossSlots(root, realmId, player, raidId, difficultyIndex, bossIndex)
    return slots and slotItemId(slots[slotIndex]) or nil
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
                        for slotIndex, storedValue in pairs(slots) do
                            if validPositiveIndex(slotIndex) and slotItemId(storedValue) == itemId then
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

function M.placeItem(root, realmId, player, raidId, limits, itemId, resolver, priority)
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
            M.setSlot(root, realmId, player, raidId, limits, location.difficultyIndex, location.bossIndex,
                slotIndex, itemId, priority or "backup")
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
        -- Migration is not a new selection: preserve the legacy normal tier.
        local result = M.placeItem(temporaryRoot, realmId, player, raidId, limits, itemId, resolver, "normal")
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
                local record = M.getSlotRecord(root, realmId, player, raidId, difficultyIndex, bossIndex, slotIndex)
                if record then
                    -- Normal stays the historical plain token so an unchanged
                    -- wishlist exports the exact original text format.
                    local token = tostring(record.itemId)
                    if record.priority ~= "normal" then
                        token = token .. "@" .. record.priority
                    end
                    itemIds[#itemIds + 1] = token
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
    local priorities
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
            local bossPriorities
            for _, itemPart in ipairs(splitPlain(itemText, "-")) do
                -- The historical token is a plain item id. The only extension is
                -- an optional "@priority" suffix; missing, empty or unknown
                -- values fall back to the default instead of rejecting the
                -- still-valid wishlist data around them.
                local itemIdText, priorityText = itemPart:match("^(%d+)@(.*)$")
                if not itemIdText then
                    if not itemPart:match("^%d+$") then
                        return parseFailure("invalid-item")
                    end
                    itemIdText = itemPart
                end
                local itemId = tonumber(itemIdText)
                if not validItemId(itemId) then
                    return parseFailure("invalid-item")
                end
                if #slots >= limits.slots then
                    return parseFailure("too-many-items")
                end
                slots[#slots + 1] = itemId
                itemCount = itemCount + 1
                local priority = M.normalizePriority(priorityText)
                if priority ~= "normal" then
                    bossPriorities = bossPriorities or {}
                    bossPriorities[#slots] = priority
                end
            end
            raid[difficultyIndex][bossIndex] = slots
            if bossPriorities then
                priorities = priorities or {}
                priorities[raidId] = priorities[raidId] or {}
                priorities[raidId][difficultyIndex] = priorities[raidId][difficultyIndex] or {}
                priorities[raidId][difficultyIndex][bossIndex] = bossPriorities
            end
        end
        raids[raidId] = raid
    end
    if itemCount == 0 then
        return parseFailure("empty")
    end
    return { ok = true, raids = raids, priorities = priorities, itemCount = itemCount }
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
        local raidPriorities = parsed.priorities and parsed.priorities[raidId] or nil
        for difficultyIndex, importedBosses in pairs(importedRaid) do
            local bosses = {}
            raid[difficultyIndex] = bosses
            local difficultyPriorities = raidPriorities and raidPriorities[difficultyIndex] or nil
            for bossIndex, importedSlots in pairs(importedBosses) do
                local slots = {}
                bosses[bossIndex] = slots
                local bossPriorities = difficultyPriorities and difficultyPriorities[bossIndex] or nil
                for slotIndex, itemId in ipairs(importedSlots) do
                    local priority = bossPriorities and bossPriorities[slotIndex] or nil
                    slots[slotIndex] = encodeSlot(itemId, priority)
                end
            end
        end
    end
    return true
end

function M.highestPriority(root, realmId, player, raidId, itemId)
    if not validItemId(itemId) then
        return nil
    end
    local raid = getRaid(root, realmId, player, raidId, false)
    if not raid then
        return nil
    end
    -- Single allocation-free scan; core is the ceiling, so stop as soon as it
    -- is found.
    local best, bestRank
    for difficultyIndex, bosses in pairs(raid) do
        if validPositiveIndex(difficultyIndex) and type(bosses) == "table" then
            for bossIndex, slots in pairs(bosses) do
                if validPositiveIndex(bossIndex) and type(slots) == "table" then
                    for slotIndex, value in pairs(slots) do
                        if validPositiveIndex(slotIndex) and slotItemId(value) == itemId then
                            local priority = slotPriority(value)
                            local rank = PRIORITY_RANK[priority]
                            if not best or rank > bestRank then
                                best, bestRank = priority, rank
                                if rank == PRIORITY_RANK.core then
                                    return best
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

function M.contains(root, realmId, player, raidId, itemId)
    if not validItemId(itemId) then
        return false
    end
    local raid = getRaid(root, realmId, player, raidId, false)
    if not raid then
        return false
    end
    -- Allocation-free scan with an early return; loot and auction checks call
    -- this per event, so misses must not build or sort a match list.
    for difficultyIndex, bosses in pairs(raid) do
        if validPositiveIndex(difficultyIndex) and type(bosses) == "table" then
            for bossIndex, slots in pairs(bosses) do
                if validPositiveIndex(bossIndex) and type(slots) == "table" then
                    for slotIndex, value in pairs(slots) do
                        if validPositiveIndex(slotIndex) and slotItemId(value) == itemId then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

BG.BGNext.Wishlist = M
return M
