BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

local apiKeys = {
    STRENGTH = { "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_STRENGTH" },
    AGILITY = { "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_AGILITY" },
    INTELLECT = { "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_INTELLECT" },
}

local function hasSelections(selected)
    return type(selected) == "table" and next(selected) ~= nil
end

local function collectFromAPI(rawStats)
    if type(rawStats) ~= "table" then return nil end
    local primary = {}
    for stat, keys in pairs(apiKeys) do
        for _, key in ipairs(keys) do
            if rawStats[key] ~= nil and rawStats[key] ~= 0 then
                primary[stat] = true
                break
            end
        end
    end
    return primary
end

local function collectFromTooltip(text, patterns)
    if type(text) ~= "string" or text == "" then return nil end
    local primary = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        for stat, pattern in pairs(patterns or {}) do
            if type(pattern) == "string" and pattern ~= "" and line:find(pattern) then
                primary[stat] = true
            end
        end
    end
    return primary
end

function M.selectItemRef(exactLink, loadedLink, itemID)
    if type(exactLink) == "string" and exactLink:find("item:", 1, true) then return exactLink end
    if type(loadedLink) == "string" and loadedLink:find("item:", 1, true) then return loadedLink end
    return itemID
end

function M.new(options)
    options = options or {}
    local getItemStats = options.getItemStats
    local tooltipPatterns = options.tooltipPatterns or {}
    local cache = {}
    local detector = {}

    local function cacheKey(itemRef)
        if itemRef == nil then return nil end
        return type(itemRef) .. ":" .. tostring(itemRef)
    end

    local function resolve(itemRef, tooltipText)
        local key = cacheKey(itemRef)
        local cached = key and cache[key]
        if cached then return cached end

        if type(getItemStats) == "function" then
            local ok, rawStats = pcall(getItemStats, itemRef)
            if ok then
                local primary = collectFromAPI(rawStats)
                if primary then
                    if key and next(primary) then cache[key] = primary end
                    return primary
                end
            end
        end

        local primary = collectFromTooltip(tooltipText, tooltipPatterns)
        if primary and key and next(primary) then cache[key] = primary end
        return primary
    end

    function detector:isMismatch(selected, itemRef, tooltipText)
        if not hasSelections(selected) then return false end
        local primary = resolve(itemRef, tooltipText)
        if not primary or not next(primary) then return false end
        for stat in pairs(selected) do
            if primary[stat] then return false end
        end
        return true
    end

    return detector
end

BG.BGNext.ItemPrimaryStats = M
return M
