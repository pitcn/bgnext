BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Raid auction authority: "am I the raid leader or the master looter?"
-- Self is identified by unit token (UnitIsUnit("raidN", "player")), never by
-- comparing display names, because Forever two-part names ("名 姓") and other
-- client name formats are not guaranteed to match the roster string. Name
-- comparison is only a fallback when the unit API is unavailable or fails.
-- Every client API call is guarded; a missing or failing API means "no".
-- Nothing here is stored: no names, GUIDs or hashes are kept. The diagnostic
-- record below holds only booleans, a method tag and a source location.
local M = {}

local function call(api, name, ...)
    local fn = api and api[name]
    if type(fn) ~= "function" then return false end
    local ok, a, b, c = pcall(fn, ...)
    if not ok then return false end
    return true, a, b, c
end

local function isMasterMethod(api, method)
    if method == "master" or method == 2 then return true end
    local enum = api and api.Enum
    local lootMethod = type(enum) == "table" and enum.LootMethod or nil
    return type(lootMethod) == "table" and lootMethod.Masterlooter ~= nil
        and method == lootMethod.Masterlooter or false
end

function M.inRaid(api)
    local has, value = call(api, "IsInRaid")
    return has and value and true or false
end

-- Returns isSelf, method ("unit" | "name" | nil).
function M.isSelfRow(api, index, rosterName, playerName, localRealm, identity)
    if type(index) == "number" then
        local has, same = call(api, "UnitIsUnit", "raid" .. index, "player")
        if has then return same and true or false, "unit" end
    end
    if type(rosterName) ~= "string" or type(playerName) ~= "string" then return false, nil end
    if identity and type(identity.same) == "function" then
        local ok, same = pcall(identity.same, rosterName, playerName, localRealm)
        if ok then return same == true, "name" end
        return false, nil
    end
    local ok, same = pcall(function() return rosterName == playerName end)
    return ok and same or false, "name"
end

function M.liveIsLeader(api)
    if not M.inRaid(api) then return false end
    local has, value = call(api, "UnitIsGroupLeader", "player")
    return has and value and true or false
end

local function lootMethodNamesMe(api, method, partyID, raidID)
    if not isMasterMethod(api, method) then return false end
    if partyID == 0 then return true end
    if type(raidID) == "number" then
        local has, same = call(api, "UnitIsUnit", "raid" .. raidID, "player")
        if has and same then return true end
    end
    return false
end

function M.liveIsMasterLooter(api)
    if not M.inRaid(api) then return false end
    local has, value = call(api, "IsMasterLooter")
    if has and value then return true end
    local party = api and api.C_PartyInfo
    if type(party) == "table" then
        local found, method, partyID, raidID = call(party, "GetLootMethod")
        if found and lootMethodNamesMe(api, method, partyID, raidID) then return true end
    end
    local found, method, partyID, raidID = call(api, "GetLootMethod")
    return found and lootMethodNamesMe(api, method, partyID, raidID) or false
end

-- Leader or master looter. Assistants and regular members never qualify.
function M.isController(api, cachedIsML)
    if cachedIsML == true then return true end
    return M.liveIsLeader(api) or M.liveIsMasterLooter(api)
end

-- Memory-only diagnostic of the last roster refresh (no names).
M.lastRefresh = {}
function M.recordRefresh(selfFound, method, failedAt)
    local record = M.lastRefresh
    record.selfFound = selfFound and true or false
    record.method = method
    record.failedAt = failedAt
end

function M.errorLocation(err)
    if type(err) ~= "string" then return "unknown" end
    return err:match("([%w_]+%.lua:%d+)") or "unknown"
end

BG.BGNext.RaidAuthority = M

function BG.IsAuctionController()
    return M.isController(_G, BG.IsML)
end

return M