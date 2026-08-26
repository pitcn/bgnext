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
