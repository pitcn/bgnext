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

-- Rebuilds every built-in profile from the supplied defaults and re-appends the
-- existing custom profiles in their current order. Built-ins are identified only
-- by their BGNext `builtInKey`, never by their id, so a stale built-in can be
-- replaced without ever colliding with a `custom-*` profile. Custom profiles are
-- kept by reference; their tables are never rewritten.
local function reconcileBuiltIns(state, defaults)
    state.profiles = type(state.profiles) == "table" and state.profiles or {}
    state.order = type(state.order) == "table" and state.order or {}
    local customIds = {}
    for _, id in ipairs(state.order) do
        local profile = state.profiles[id]
        if profile and profile.builtInKey == nil then
            customIds[#customIds + 1] = id
        end
    end
    local profiles = {}
    local order = {}
    for index, def in ipairs(defaults or {}) do
        local normalized = normalizeProfile(def, "default-" .. index)
        if normalized and normalized.builtInKey and not profiles[normalized.builtInKey] then
            profiles[normalized.builtInKey] = normalized
            order[#order + 1] = normalized.builtInKey
        end
    end
    for _, id in ipairs(customIds) do
        local profile = state.profiles[id]
        if profile then
            profiles[id] = profile
            order[#order + 1] = id
        end
    end
    state.profiles = profiles
    state.order = order
    return state
end

local function backfillMissingBuiltInPrimaryStats(state, defaults)
    if type(state) ~= "table" or type(state.profiles) ~= "table" then return end
    local defaultByBuiltInKey = {}
    for _, profile in ipairs(defaults or {}) do
        if type(profile) == "table" and type(profile.builtInKey) == "string" then
            defaultByBuiltInKey[profile.builtInKey] = profile
        end
    end
    for _, profile in pairs(state.profiles) do
        if type(profile) == "table" and profile.primaryStat == nil and type(profile.builtInKey) == "string" then
            local default = defaultByBuiltInKey[profile.builtInKey]
            if default and type(default.primaryStat) == "table" then
                profile.primaryStat = clone(default.primaryStat)
            end
        end
    end
end

-- The first specialization release persisted the class fallback icon on every
-- built-in profile. Upgrade only that known stale value; a custom profile or a
-- built-in whose icon the player changed to anything else remains untouched.
local function sameTable(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then return false end
    for key, value in pairs(left) do
        if right[key] ~= value then return false end
    end
    for key, value in pairs(right) do
        if left[key] ~= value then return false end
    end
    return true
end

local function upgradeStaleBuiltIns(state, defaults)
    if type(state) ~= "table" or type(state.profiles) ~= "table" then return false end
    local fallbackIcon
    for _, def in ipairs(defaults or {}) do
        if type(def) == "table" and type(def.builtInKey) == "string"
            and def.builtInKey:match(":class$") then
            fallbackIcon = def.icon
            break
        end
    end
    if fallbackIcon == nil then return false end
    local changed = false
    for _, def in ipairs(defaults or {}) do
        local key = type(def) == "table" and def.builtInKey
        local profile = key and state.profiles[key]
        local hasStaleIcon = profile and (profile.icon == fallbackIcon
            or (def.upgradeIconFrom ~= nil and profile.icon == def.upgradeIconFrom))
        if profile and profile.builtInKey == key and not key:match(":class$")
            and hasStaleIcon and def.icon ~= nil and def.icon ~= profile.icon then
            profile.icon = def.icon
            changed = true
        end
        if profile and profile.builtInKey == key and type(def.upgradeWeaponFrom) == "table"
            and sameTable(profile.weapon, def.upgradeWeaponFrom) then
            profile.weapon = clone(type(def.weapon) == "table" and def.weapon or {})
            changed = true
        end
    end
    return changed
end

M.upgradeStaleBuiltIns = upgradeStaleBuiltIns

function M.ensureCharacter(root, realmId, player, defaults, spec)
    if type(root) ~= "table" or realmId == nil or player == nil then return nil end
    root.equipmentFilters = type(root.equipmentFilters) == "table" and root.equipmentFilters or {}
    root.equipmentFilters[realmId] = root.equipmentFilters[realmId] or {}
    local state = root.equipmentFilters[realmId][player]
    if type(state) ~= "table" or type(state.profiles) ~= "table" or type(state.order) ~= "table" then
        state = {}
        root.equipmentFilters[realmId][player] = state
        reconcileBuiltIns(state, defaults)
        state.selectionMode = "follow-spec"
        local builtInId = spec and spec.builtInId
        if builtInId and state.profiles[builtInId] then
            state.selectedId = builtInId
        else
            state.selectedId = state.order[1]
        end
    else
        -- Keep pre-existing content and explicit choices intact. The #22
        -- migration only fills a field that is genuinely absent; an empty or
        -- customized primary-stat table remains authoritative.
        backfillMissingBuiltInPrimaryStats(state, defaults)
        upgradeStaleBuiltIns(state, defaults)
        if state.selectionMode == nil then
            -- Pre-feature state: keep the saved selection and treat it as manual
            -- so following specialization is always an explicit user choice.
            state.selectionMode = "manual"
        end
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
    state.selectedId = id
    state.selectionMode = "manual"
    return true
end

-- Enters follow-specialization mode and selects the resolved built-in when it
-- is known. Only this entry point (or reset) enables automatic switching.
function M.followSpecialization(state, builtInId, defaults)
    if type(state) ~= "table" or type(state.profiles) ~= "table" then return false end
    if builtInId and type(defaults) == "table" then
        reconcileBuiltIns(state, defaults)
    end
    state.selectionMode = "follow-spec"
    if builtInId and state.profiles[builtInId] then
        state.selectedId = builtInId
    end
    return true
end

-- Applies a freshly resolved specialization to a state that is already following.
-- A nil or unrecognized built-in preserves the active selection rather than
-- guessing; a manual selection is never changed.
function M.applyResolvedSpecialization(state, builtInId)
    if type(state) ~= "table" or state.selectionMode ~= "follow-spec" then return false end
    if type(state.profiles) ~= "table" or not builtInId or not state.profiles[builtInId] then return false end
    state.selectedId = builtInId
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

function M.resetDefaults(state, defaults, builtInId)
    if type(state) ~= "table" then return false end
    reconcileBuiltIns(state, defaults)
    state.selectionMode = "follow-spec"
    if builtInId and state.profiles[builtInId] then
        state.selectedId = builtInId
    else
        state.selectedId = state.order[1]
    end
    return true
end

M.reconcileBuiltIns = function(state, defaults)
    if type(state) ~= "table" then return false end
    reconcileBuiltIns(state, defaults)
    return true
end

BG.BGNext.EquipmentFilter = M

function BG.BGNext.GetActiveEquipmentFilterProfile()
    if not BG.BGNext.DB then return nil end
    return M.getActiveProfile(BG.BGNext.DB, BG.realmID or GetRealmID(), BG.playerName)
end

return M
