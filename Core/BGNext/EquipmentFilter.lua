BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}
local fields = {
    name = true, icon = true, weapon = true, armor = true, affix = true,
    classRestriction = true, ignoreBattleNetBound = true, tankOnly = true,
    primaryStat = true, builtInKey = true,
}

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do copy[clone(key, seen)] = clone(child, seen) end
    return copy
end

local function trim(value)
    if type(value) ~= "string" then return nil end
    value = value:match("^%s*(.-)%s*$")
    if value == "" then return nil end
    if #value > 24 then
        local cut = 24
        while cut > 0 and value:byte(cut + 1) and value:byte(cut + 1) >= 128 and value:byte(cut + 1) < 192 do
            cut = cut - 1
        end
        value = value:sub(1, cut)
    end
    return value ~= "" and value or nil
end

local function normalizeProfile(profile, fallbackId)
    if type(profile) ~= "table" then return nil end
    local name = trim(profile.name)
    if not name then return nil end
    local normalized = {
        id = tostring(profile.id or fallbackId or ""),
        name = name,
        icon = profile.icon or 134400,
        weapon = clone(type(profile.weapon) == "table" and profile.weapon or {}),
        armor = clone(type(profile.armor) == "table" and profile.armor or {}),
        affix = clone(type(profile.affix) == "table" and profile.affix or {}),
        classRestriction = profile.classRestriction == true,
        ignoreBattleNetBound = profile.ignoreBattleNetBound == true,
        tankOnly = profile.tankOnly == true,
        primaryStat = clone(type(profile.primaryStat) == "table" and profile.primaryStat or {}),
        builtInKey = type(profile.builtInKey) == "string" and profile.builtInKey or nil,
    }
    if normalized.id == "" then return nil end
    return normalized
end

local function replaceWithDefaults(state, defaults)
    state.selectedId = nil
    state.order = {}
    state.profiles = {}
    for index, profile in ipairs(defaults or {}) do
        local normalized = normalizeProfile(profile, "default-" .. index)
        if normalized and not state.profiles[normalized.id] then
            state.profiles[normalized.id] = normalized
            state.order[#state.order + 1] = normalized.id
            state.selectedId = state.selectedId or normalized.id
        end
    end
    return state
end

function M.ensureCharacter(root, realmId, player, defaults)
    if type(root) ~= "table" or realmId == nil or player == nil then return nil end
    root.equipmentFilters = type(root.equipmentFilters) == "table" and root.equipmentFilters or {}
    root.equipmentFilters[realmId] = root.equipmentFilters[realmId] or {}
    local state = root.equipmentFilters[realmId][player]
    if type(state) ~= "table" or type(state.profiles) ~= "table" or type(state.order) ~= "table" then
        state = {}
        root.equipmentFilters[realmId][player] = state
        replaceWithDefaults(state, defaults)
    end
    return state
end

function M.getActiveProfile(root, realmId, player)
    local byRealm = type(root) == "table" and type(root.equipmentFilters) == "table" and root.equipmentFilters[realmId]
    local state = type(byRealm) == "table" and byRealm[player]
    if type(state) ~= "table" or type(state.profiles) ~= "table" then return nil end
    return state.selectedId and state.profiles[state.selectedId] or nil
end

function M.isRuleSelected(profile, sectionKey, ruleId, isBoolean)
    if type(profile) ~= "table" then return false end
    if isBoolean then return profile[sectionKey] == true end
    local rules = profile[sectionKey]
    return type(rules) == "table" and rules[ruleId] == true or false
end

function M.selectProfile(state, id)
    if type(state) ~= "table" or type(state.profiles) ~= "table" or not state.profiles[id] then return false end
    if state.selectedId == id then
        state.selectedId = nil
    else
        state.selectedId = id
    end
    return true
end

function M.createProfile(state, profile)
    if type(state) ~= "table" or type(state.profiles) ~= "table" then return false end
    local sequence = 1
    local id
    repeat
        id = "custom-" .. sequence
        sequence = sequence + 1
    until not state.profiles[id]
    local normalized = normalizeProfile(profile, id)
    if not normalized then return false end
    normalized.id = id
    normalized.builtInKey = nil
    state.profiles[id] = normalized
    state.order[#state.order + 1] = id
    return true, id
end

function M.updateProfile(state, id, patch)
    local profile = type(state) == "table" and type(state.profiles) == "table" and state.profiles[id]
    if not profile or type(patch) ~= "table" then return false end
    local candidate = clone(profile)
    for key, value in pairs(patch) do
        if fields[key] and key ~= "builtInKey" then candidate[key] = clone(value) end
    end
    candidate.id = id
    local normalized = normalizeProfile(candidate, id)
    if not normalized then return false end
    normalized.builtInKey = profile.builtInKey
    state.profiles[id] = normalized
    return true
end

function M.moveProfile(state, id, delta)
    if type(state) ~= "table" or type(state.order) ~= "table" or type(delta) ~= "number" then return false end
    for index, value in ipairs(state.order) do
        if value == id then
            local target = math.max(1, math.min(#state.order, index + delta))
            if target == index then return false end
            table.remove(state.order, index)
            table.insert(state.order, target, id)
            return true
        end
    end
    return false
end

function M.deleteProfile(state, id)
    if type(state) ~= "table" or type(state.profiles) ~= "table" or not state.profiles[id] then return false end
    state.profiles[id] = nil
    for index, value in ipairs(state.order or {}) do
        if value == id then table.remove(state.order, index) break end
    end
    if state.selectedId == id then state.selectedId = state.order and state.order[1] or nil end
    return true
end

function M.resetDefaults(state, defaults)
    if type(state) ~= "table" then return false end
    replaceWithDefaults(state, defaults)
    return true
end

BG.BGNext.EquipmentFilter = M

if BG.Init then
    BG.Init(function()
        local catalog = BG.BGNext.EquipmentFilterProfiles
        if not BG.BGNext.DB or not catalog then return end
        local _, classToken = UnitClass("player")
        local defaults = catalog.getDefaults({ project = WOW_PROJECT_ID }, classToken)
        M.ensureCharacter(BG.BGNext.DB, BG.realmID or GetRealmID(), BG.playerName, defaults)
    end)
end

function BG.BGNext.GetActiveEquipmentFilterProfile()
    if not BG.BGNext.DB then return nil end
    return M.getActiveProfile(BG.BGNext.DB, BG.realmID or GetRealmID(), BG.playerName)
end

return M
