BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Pure projection of the approved BG loot catalog into a searchable raid/boss/item
-- model for the price-preset page. This module never creates frames, never stores
-- data and never communicates. It only reads the supplied catalog options; the
-- caller owns the BG globals and item-description lookups.
local M = {}

local MISC_ID = "misc"

local function makeItem(itemId, describeItem)
    local item = { itemId = itemId }
    if type(describeItem) == "function" then
        local desc = describeItem(itemId)
        if type(desc) == "table" then
            item.name = desc.name
            item.equipLoc = desc.equipLoc
            item.quality = desc.quality
        end
    end
    return item
end

local function sortItems(group)
    table.sort(group.items, function(a, b) return a.itemId < b.itemId end)
end

-- Builds the model for one raid. `options` carries raidId, an ordered
-- difficulties list, an ordered boss list (each `{ id, name }`, the last being
-- the fixed `misc` group), the nested `loot[difficulty][bossKey] = { itemId }`
-- tables, and an optional `describeItem(itemId)` returning
-- `{ name, equipLoc, quality }`.
function M.build(options)
    if type(options) ~= "table" then return nil end
    local raidId = options.raidId
    local bosses = options.bosses
    local loot = options.loot
    if type(raidId) ~= "string" or type(bosses) ~= "table" or type(loot) ~= "table" then
        return nil
    end

    local groups = {}
    local groupById = {}
    for _, boss in ipairs(bosses) do
        if type(boss) == "table" and type(boss.id) == "string" then
            local group = { id = boss.id, name = boss.name, items = {} }
            groups[#groups + 1] = group
            groupById[boss.id] = group
        end
    end
    local miscGroup = groupById[MISC_ID]
    if not miscGroup then
        miscGroup = { id = MISC_ID, name = nil, items = {} }
        groups[#groups + 1] = miscGroup
        groupById[MISC_ID] = miscGroup
    end

    local difficulties = options.difficulties
    if type(difficulties) ~= "table" then
        difficulties = {}
        for key in pairs(loot) do difficulties[#difficulties + 1] = key end
        table.sort(difficulties)
    end

    local seenByGroup = {}
    local function addItem(group, itemId)
        if type(itemId) ~= "number" then return end
        local seen = seenByGroup[group]
        if not seen then
            seen = {}
            seenByGroup[group] = seen
        end
        if not seen[itemId] then
            seen[itemId] = true
            group.items[#group.items + 1] = makeItem(itemId, options.describeItem)
        end
    end

    for _, difficulty in ipairs(difficulties) do
        local diffLoot = loot[difficulty]
        if type(diffLoot) == "table" then
            for bossKey, itemIds in pairs(diffLoot) do
                -- `bossNother` contains the products obtained after exchanging
                -- a dropped token/quest item. The auction sells the source item,
                -- which already lives in `bossN`; listing every possible reward
                -- again inflates a single boss from ~20 drops to 90+ entries.
                local isExchangeResult = type(bossKey) == "string" and bossKey:match("^boss%d+other$") ~= nil
                if not isExchangeResult then
                    local group = groupById[bossKey] or miscGroup
                    for _, itemId in ipairs(itemIds) do
                        addItem(group, itemId)
                    end
                end
            end
        end
    end

    local byItem = {}
    for _, group in ipairs(groups) do
        sortItems(group)
        for _, item in ipairs(group.items) do
            item.groupId = group.id
            item.groupName = group.name
            byItem[item.itemId] = item
        end
    end

    return { raidId = raidId, groups = groups, byItem = byItem }
end

function M.buildAll(optionsByRaid)
    local models = {}
    if type(optionsByRaid) == "table" then
        for raidId, options in pairs(optionsByRaid) do
            local model = M.build(options)
            if model then models[raidId] = model end
        end
    end
    return models
end

local function modelHasItem(model, itemId)
    if type(model) ~= "table" then return false end
    return model.byItem ~= nil and model.byItem[itemId] ~= nil
end

-- Resolves the unique raid a known item belongs to, or nil when it is unknown
-- or appears in more than one raid (ambiguous).
function M.resolveRaidForItem(modelsByRaid, itemId)
    if type(modelsByRaid) ~= "table" then return nil end
    local found
    for raidId, model in pairs(modelsByRaid) do
        if modelHasItem(model, itemId) then
            if found then return nil end
            found = raidId
        end
    end
    return found
end

local function matches(item, text, criteria)
    if text and text ~= "" then
        local name = type(item.name) == "string" and item.name:lower() or nil
        local idStr = tostring(item.itemId)
        local nameHit = name and name:find(text, 1, true)
        local idHit = idStr:find(text, 1, true)
        if not (nameHit or idHit) then return false end
    end
    if criteria.equipLoc ~= nil and item.equipLoc ~= criteria.equipLoc then return false end
    if criteria.quality ~= nil and item.quality ~= criteria.quality then return false end
    if criteria.state == "set" or criteria.state == "unset" then
        local has = type(criteria.hasPrice) == "function" and criteria.hasPrice(item.itemId) or false
        local want = criteria.state == "set"
        if has ~= want then return false end
    end
    return true
end

-- Returns the items matching the combined criteria: `text` (name or item-id
-- substring), `equipLoc`, `quality`, and `state` ("set"/"unset") together with a
-- `hasPrice(itemId)` callback.
function M.filter(raidModel, criteria)
    if type(raidModel) ~= "table" or type(raidModel.groups) ~= "table" then return {} end
    criteria = criteria or {}
    local text = type(criteria.text) == "string" and criteria.text:lower() or nil
    local results = {}
    for _, group in ipairs(raidModel.groups) do
        for _, item in ipairs(group.items) do
            if matches(item, text, criteria) then
                results[#results + 1] = item
            end
        end
    end
    return results
end

-- Fills in (or refreshes) an item's description in place, keyed by item id.
function M.updateItemDescription(raidModel, itemId, description)
    if type(raidModel) ~= "table" or not raidModel.byItem then return false end
    local item = raidModel.byItem[itemId]
    if not item then return false end
    if type(description) == "table" then
        if description.name ~= nil then item.name = description.name end
        if description.equipLoc ~= nil then item.equipLoc = description.equipLoc end
        if description.quality ~= nil then item.quality = description.quality end
    end
    return true
end

BG.BGNext.AuctionPriceCatalog = M
return M
