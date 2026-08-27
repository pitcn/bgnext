-- BGNext own-character client adapters.
--
-- Isolates every client-version difference behind a read-only declaration so
-- the projection and renderer stay version-agnostic. This module never stores
-- data, never creates frames and never communicates.
--
-- Capabilities and currency IDs are declared only where they are actually
-- verifiable. A field with no verified reader resolves to nil, which hides its
-- column instead of showing a fabricated value.

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

M.families = { "vanilla", "tbc", "wrath", "titan", "cata", "mop", "retail" }

-- Ordered because BGLite sets several flags at once: the anniversary client
-- sets both IsWLK and IsTitan, and SoD sets both IsVanilla and IsVanilla_Sod.
local FAMILY_ORDER = {
    { flag = "IsRetail", family = "retail" },
    { flag = "IsMOP", family = "mop" },
    { flag = "IsCTM", family = "cata" },
    { flag = "IsTitan", family = "titan" },
    { flag = "IsWLK", family = "wrath" },
    { flag = "IsTBC", family = "tbc" },
    { flag = "IsVanilla", family = "vanilla" },
}

-- Declared per family. `false` means BGNext must not render that column group
-- on this client, even if a catalog entry exists.
local CAPABILITIES = {
    vanilla = { hasCurrencyApi = false, hasProfessionApi = true, hasItemLevelApi = true, hasHonorApi = true },
    tbc     = { hasCurrencyApi = false, hasProfessionApi = true, hasItemLevelApi = true, hasHonorApi = true },
    wrath   = { hasCurrencyApi = true, hasProfessionApi = true, hasItemLevelApi = true, hasHonorApi = true },
    titan   = { hasCurrencyApi = true, hasProfessionApi = true, hasItemLevelApi = true, hasHonorApi = true },
    cata    = { hasCurrencyApi = true, hasProfessionApi = true, hasItemLevelApi = true, hasHonorApi = true },
    mop     = { hasCurrencyApi = true, hasProfessionApi = true, hasItemLevelApi = true, hasHonorApi = true },
    retail  = { hasCurrencyApi = true, hasProfessionApi = true, hasItemLevelApi = true, hasHonorApi = true },
}

-- Stable BGNext column key -> numeric currency ID, per family.
--
-- Only entries confirmed against a live client belong here. Keys that are not
-- listed are reported as unverified by isVerifiedColumn() and produce no value,
-- so their column stays hidden. Do not guess IDs to "fill in" a family: an
-- unverified column must render blank, never wrong.
local CURRENCY_IDS = {
    vanilla = {},
    tbc = {},
    wrath = {},
    titan = {},
    cata = {},
    mop = {},
    retail = {},
}

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[clone(key, seen)] = clone(child, seen)
    end
    return copy
end

M.clone = clone

function M.familyFromFlags(flags)
    if type(flags) ~= "table" then return nil end
    for _, entry in ipairs(FAMILY_ORDER) do
        if flags[entry.flag] then return entry.family end
    end
    return nil
end

-- Detects the family from the live BGLite globals. Kept separate from
-- familyFromFlags so tests never need WoW globals.
function M.detect(globals)
    return M.familyFromFlags(globals or BG)
end

function M.isFamily(family)
    return CAPABILITIES[family] ~= nil
end

function M.capabilities(family)
    local caps = CAPABILITIES[family]
    if not caps then return nil end
    return clone(caps)
end

-- Calls an optional Blizzard API. Returns nil when the API is absent on this
-- client, is not callable, or throws because the value is protected.
function M.safeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, result = pcall(fn, ...)
    if not ok then return nil end
    return result
end

function M.currencyId(family, columnId)
    local ids = CURRENCY_IDS[family]
    if not ids or type(columnId) ~= "string" then return nil end
    return ids[columnId]
end

-- A column is verified only when this client family has a confirmed reader for
-- it. Unverified columns must be hidden rather than rendered with a guess.
function M.isVerifiedColumn(family, columnId)
    return M.currencyId(family, columnId) ~= nil
end

BG.BGNext.OwnCharactersAdapters = M
return M
