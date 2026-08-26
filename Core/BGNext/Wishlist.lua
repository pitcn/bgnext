BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

local function validText(value)
    return type(value) == "string" and value:find("%S") ~= nil
end

local function validItemId(itemId)
    return type(itemId) == "number" and itemId > 0 and itemId == math.floor(itemId)
end

local function getRaid(root, realmId, player, raidId, create)
    if type(root) ~= "table" or type(root.wishlist) ~= "table" then
        return nil
    end
    if not validText(realmId) or not validText(player) or (type(raidId) ~= "string" and type(raidId) ~= "number") then
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
    return raid ~= nil and raid[itemId] == true
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
