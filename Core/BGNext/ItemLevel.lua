BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}
M.__index = M

function M.new(api)
    return setmetatable({
        getDetailedItemLevel = api and api.getDetailedItemLevel,
    }, M)
end

function M.production(env)
    env = env or _G
    local itemApi = env.C_Item
    local detailed = type(itemApi) == "table" and itemApi.GetDetailedItemLevelInfo or nil
    if type(detailed) ~= "function" then
        detailed = env.GetDetailedItemLevelInfo
    end
    return M.new({ getDetailedItemLevel = detailed })
end

function M:resolve(itemLink, legacyLevel)
    if type(self.getDetailedItemLevel) == "function" and type(itemLink) == "string" then
        local ok, detailedLevel = pcall(self.getDetailedItemLevel, itemLink)
        if ok and type(detailedLevel) == "number" and detailedLevel > 0 then
            return detailedLevel
        end
    end
    return legacyLevel
end

function M:displayLevel(itemText, legacyLevel, typeID)
    if type(itemText) ~= "string" or not itemText:find("item:", 1, true) then
        return nil
    end
    if typeID ~= 2 and typeID ~= 4 then
        return nil
    end
    return self:resolve(itemText, legacyLevel)
end

BG.BGNext.ItemLevel = M
BG.BGNext.itemLevel = M.production()
function BG.ResolveItemLevel(itemLink, legacyLevel)
    return BG.BGNext.itemLevel:resolve(itemLink, legacyLevel)
end
function BG.DisplayItemLevel(itemText, legacyLevel, typeID)
    return BG.BGNext.itemLevel:displayLevel(itemText, legacyLevel, typeID)
end
return M
