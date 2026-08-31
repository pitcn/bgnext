-- BGNext specialization adapter.
--
-- Converts each client family's Blizzard APIs into a stable BGNext `specKey`, or
-- an explicit unknown reason. The key is family-scoped and never stores a
-- volatile list index: modern clients keep the stable specialization ID and old
-- clients keep the class token plus the dominant talent-tree index.
--
-- This module never stores data, never creates frames, never sends messages and
-- never inspects another player. It reads only the current character's own
-- specialization or talent trees, and degrades to an unknown reason rather than
-- guessing a zero-point, tied, missing-API or unverified case.

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

-- Same ordered flags as OwnCharactersAdapters.lua so family detection stays
-- consistent across BGNext modules. BGLite sets several flags at once: the
-- anniversary client sets both IsWLK and IsTitan, and SoD sets both IsVanilla
-- and IsVanilla_Sod.
local FAMILY_ORDER = {
    { flag = "IsRetail", family = "retail" },
    { flag = "IsMOP", family = "mop" },
    { flag = "IsCTM", family = "cata" },
    { flag = "IsTitan", family = "titan" },
    { flag = "IsWLK", family = "wrath" },
    { flag = "IsTBC", family = "tbc" },
    { flag = "IsVanilla", family = "vanilla" },
}

local MODERN_FAMILIES = { mop = true, retail = true, cata = true }
local TREE_FAMILIES = { vanilla = true, tbc = true, wrath = true, titan = true }

function M.familyFromFlags(flags)
    if type(flags) ~= "table" then return nil end
    -- Season of Discovery has no specialization catalog; check before IsVanilla
    -- because BGLite sets both flags on that client.
    if flags.IsVanilla_Sod then return nil end
    for _, entry in ipairs(FAMILY_ORDER) do
        if flags[entry.flag] then return entry.family end
    end
    return nil
end

function M.detect(globals)
    return M.familyFromFlags(globals or BG)
end

-- Calls an optional Blizzard API. Returns nil when the API is absent, is not
-- callable, or throws because the value is protected.
local function safeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    if not ok then return nil end
    return result
end

local function resolveModern(family, api, classToken, result)
    local getSpec = api and api.GetSpecialization
    if type(getSpec) ~= "function" then
        result.reason = "api-unavailable"
        return result
    end
    local specIndex = safeCall(getSpec)
    if type(specIndex) ~= "number" then
        result.reason = "api-unavailable"
        return result
    end
    local getInfo = api and api.GetSpecializationInfo
    if type(getInfo) ~= "function" then
        result.reason = "api-unavailable"
        return result
    end
    local specId = safeCall(getInfo, specIndex)
    if type(specId) ~= "number" then
        result.reason = "spec-invalid"
        return result
    end
    result.specKey = "spec:" .. tostring(specId)
    return result
end

local function resolveTrees(family, api, classToken, result)
    local getInfo = api and api.GetTalentTabInfo
    if type(getInfo) ~= "function" then
        result.reason = "api-unavailable"
        return result
    end
    local activeGroup = safeCall(api and api.GetActiveTalentGroup)
    local maxPoints, maxIndex, tied = 0, nil, false
    for index = 1, 3 do
        -- GetTalentTabInfo returns pointsSpent as its third value.
        local ok, _, _, spent = pcall(getInfo, index, false, false, activeGroup)
        if not ok or type(spent) ~= "number" then
            result.reason = "api-unavailable"
            return result
        end
        if spent > 0 then
            if spent > maxPoints then
                maxPoints, maxIndex, tied = spent, index, false
            elseif spent == maxPoints then
                tied = true
            end
        end
    end
    if maxIndex == nil then
        result.reason = "zero"
        return result
    end
    if tied then
        result.reason = "tie"
        return result
    end
    result.specKey = "tree:" .. classToken .. ":" .. tostring(maxIndex)
    return result
end

function M.resolve(family, api, classToken)
    local result = { family = family, classToken = classToken, specKey = nil, reason = nil }
    if MODERN_FAMILIES[family] then
        return resolveModern(family, api, classToken, result)
    elseif TREE_FAMILIES[family] then
        return resolveTrees(family, api, classToken, result)
    end
    result.reason = "unknown-family"
    return result
end

BG.BGNext.SpecializationAdapter = M
return M
