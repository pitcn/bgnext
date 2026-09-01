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

function M.find(records, target, localRealm)
    if type(records) ~= "table" then return nil end
    for _, record in ipairs(records) do
        if type(record) == "table" and M.same(record.name, target, localRealm) then
            return record
        end
    end
    return nil
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

-- Buyer identity carried by the existing DuiZhang message. Non-Retail raids
-- have no cross-realm ambiguity and retain the legacy short field. Retail must
-- carry the canonical realm so same-name players on different realms remain
-- distinct. This changes neither the message type nor the item payload.
function M.duiZhangName(value, localRealm, family)
    if family == "retail" then
        local display = M.display(value, localRealm, family)
        if not display then return nil end
        -- Keep same-realm names legacy-compatible. Cross-realm display retains
        -- its realm, but the legacy protocol uses '-' as a field delimiter, so
        -- encode '%' and '-' without adding another message field or type.
        return display:gsub("%%", function() return "%25" end)
            :gsub("%-", function() return "%2D" end)
    end
    return M.shortName(value)
end

-- Parses from the item payload boundary on the right. The old three-way
-- strsplit treated the hyphen inside "Name-Realm" as a protocol delimiter.
-- Item payloads begin with a numeric item id, which makes that boundary stable
-- while preserving legacy short-name messages.
function M.parseDuiZhang(message)
    if type(message) ~= "string" then return nil end
    local buyer, payload = message:match("^DuiZhang%-(.+)%-(%d+ .*)$")
    if not buyer or buyer == "" or not payload or payload == "" then return nil end
    buyer = buyer:gsub("%%2[dD]", "-"):gsub("%%25", function() return "%" end)
    return buyer, payload
end

BG.BGNext.PlayerIdentity = M
return M
