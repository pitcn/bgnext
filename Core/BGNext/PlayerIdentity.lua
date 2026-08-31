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

-- Splits a name into its character and realm components. The realm is nil for a
-- bare name. Returns nothing for an unparseable value.
local function splitIdentity(value)
    if type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$") or ""
    if value == "" then return nil end
    local name, realm = value:match("^([^%-]+)%-(.+)$")
    if not name then
        name = value
    end
    return name, realm
end

-- The bare character name, without any "-Realm" suffix.
function M.shortName(value)
    local name = splitIdentity(value)
    return name
end

-- The canonical full "Name-Realm" identity used for storage and comparison. A
-- bare name gains the local realm; an existing realm is preserved verbatim
-- (including case). Returns nil when the value is unparseable or no realm can
-- be determined.
function M.canonical(value, localRealm)
    local name, realm = splitIdentity(value)
    if not name then return nil end
    realm = realm or localRealm
    if type(realm) ~= "string" or realm == "" then return nil end
    return name .. "-" .. realm
end

-- The name to display for a client family. Non-retail families always show the
-- short name. Retail keeps the realm for cross-realm players so two players who
-- share a short name on different realms never merge.
function M.display(value, localRealm, family)
    local name, realm = splitIdentity(value)
    if not name then return value end
    if family ~= "retail" then
        return name
    end
    if not realm or realm == "" then return name end
    local a = normalizePart(realm, true)
    local b = normalizePart(localRealm, true)
    if a and b and a == b then return name end
    return name .. "-" .. realm
end

-- Resolves the client family from BGLite's version flags. Only "retail" changes
-- the display rule, so every other family (and an undetectable one) reports nil.
function M.familyFromGlobals(globals)
    if type(globals) ~= "table" then return nil end
    if globals.IsRetail then return "retail" end
    return nil
end

BG.BGNext.PlayerIdentity = M
return M
