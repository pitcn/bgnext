BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Pure player-name identity helpers shared by auction and trade code. WoW may
-- expose the same local player as either "Name" or "Name-Realm", while realm
-- display names can contain spaces or separators. Identity always keeps the
-- realm component so cross-realm players with the same short name stay apart.
local M = {}

local function normalizePart(value, removeSeparators)
    if type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$") or ""
    if removeSeparators then
        value = value:gsub("[%s%-]", "")
    end
    value = value:lower()
    if value == "" then return nil end
    return value
end

function M.key(value, localRealm)
    if type(value) ~= "string" or value == "" then return nil end
    local name, realm = value:match("^([^%-]+)%-(.+)$")
    if not name then
        name = value
        realm = localRealm
    end
    name = normalizePart(name, false)
    realm = normalizePart(realm, true)
    if not name or not realm then return nil end
    return name .. "-" .. realm
end

function M.same(left, right, localRealm)
    local leftKey = M.key(left, localRealm)
    local rightKey = M.key(right, localRealm)
    return leftKey ~= nil and rightKey ~= nil and leftKey == rightKey
end

BG.BGNext.PlayerIdentity = M
return M
