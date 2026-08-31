-- BGNext specialization equipment-filter defaults.
--
-- Declares, per client family, the equipment-filter default for each supported
-- specialization. Every declaration composes an independent role rule family
-- (primary stat, filtered affixes, tank-only flag) with the class capability
-- base exposed by EquipmentFilterProfiles, and returns a defensive copy. Names
-- here are independently authored fallbacks: the UI/runtime prefers the live
-- Blizzard name and icon from GetSpecializationInfo when that API is available.
--
-- Unknown specializations, families without a catalog, and classes without a
-- base return nil so the caller preserves the active profile instead of guessing.
-- No BiaoGe tables, names, icons, ordering, or identifiers are reproduced here.

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

local function clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do copy[clone(key, seen)] = clone(child, seen) end
    return copy
end

-- Role rule families are authored independently and client-scoped. Physical
-- rules filter spell power; caster/healer rules filter attack power and the
-- physical-only affixes; healers keep mana regeneration; tanks set tankOnly.
local ROLES = {
    ["strength-melee"] = { primaryStat = { STRENGTH = true }, affix = { SPELL_POWER = true }, tankOnly = false },
    ["agility-melee"] = { primaryStat = { AGILITY = true }, affix = { SPELL_POWER = true }, tankOnly = false },
    ["agility-ranged"] = { primaryStat = { AGILITY = true }, affix = { SPELL_POWER = true }, tankOnly = false },
    ["intellect-damage"] = { primaryStat = { INTELLECT = true }, affix = { ATTACK_POWER = true, ARMOR_PEN = true, EXPERTISE = true }, tankOnly = false },
    ["intellect-healing"] = { primaryStat = { INTELLECT = true }, affix = { ATTACK_POWER = true, ARMOR_PEN = true, EXPERTISE = true }, tankOnly = false },
    ["strength-tank"] = { primaryStat = { STRENGTH = true }, affix = { SPELL_POWER = true }, tankOnly = true },
    ["agility-tank"] = { primaryStat = { AGILITY = true }, affix = { SPELL_POWER = true }, tankOnly = true },
    ["feral-ambiguous"] = { primaryStat = { AGILITY = true }, affix = { SPELL_POWER = true }, tankOnly = false },
}

local TREE_CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local TITAN_CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID", "DEATHKNIGHT" }
local MODERN_CLASS_ORDER = { "MAGE", "PALADIN", "WARRIOR", "DRUID", "DEATHKNIGHT", "HUNTER", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "MONK" }
local RETAIL_CLASS_ORDER = { "MAGE", "PALADIN", "WARRIOR", "DRUID", "DEATHKNIGHT", "HUNTER", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "MONK", "DEMONHUNTER", "EVOKER" }

local TREE_RAW = {
    WARRIOR = { { tree = 1, role = "strength-melee", name = "武器" }, { tree = 2, role = "strength-melee", name = "狂暴" }, { tree = 3, role = "strength-tank", name = "防护" } },
    PALADIN = { { tree = 1, role = "intellect-healing", name = "神圣" }, { tree = 2, role = "strength-tank", name = "防护" }, { tree = 3, role = "strength-melee", name = "惩戒" } },
    HUNTER = { { tree = 1, role = "agility-ranged", name = "野兽控制" }, { tree = 2, role = "agility-ranged", name = "射击" }, { tree = 3, role = "agility-ranged", name = "生存" } },
    ROGUE = { { tree = 1, role = "agility-melee", name = "刺杀" }, { tree = 2, role = "agility-melee", name = "战斗" }, { tree = 3, role = "agility-melee", name = "敏锐" } },
    PRIEST = { { tree = 1, role = "intellect-healing", name = "戒律" }, { tree = 2, role = "intellect-healing", name = "神圣" }, { tree = 3, role = "intellect-damage", name = "暗影" } },
    SHAMAN = { { tree = 1, role = "intellect-damage", name = "元素" }, { tree = 2, role = "agility-melee", name = "增强" }, { tree = 3, role = "intellect-healing", name = "恢复" } },
    MAGE = { { tree = 1, role = "intellect-damage", name = "奥术" }, { tree = 2, role = "intellect-damage", name = "火焰" }, { tree = 3, role = "intellect-damage", name = "冰霜" } },
    WARLOCK = { { tree = 1, role = "intellect-damage", name = "痛苦" }, { tree = 2, role = "intellect-damage", name = "恶魔学识" }, { tree = 3, role = "intellect-damage", name = "毁灭" } },
    DRUID = { { tree = 1, role = "intellect-damage", name = "平衡" }, { tree = 2, role = "feral-ambiguous", name = "野性战斗" }, { tree = 3, role = "intellect-healing", name = "恢复" } },
}

local DEATHKNIGHT_TREE = {
    DEATHKNIGHT = { { tree = 1, role = "strength-tank", name = "鲜血" }, { tree = 2, role = "strength-melee", name = "冰霜" }, { tree = 3, role = "strength-melee", name = "邪恶" } },
}

local MODERN_RAW = {
    MAGE = { { spec = 62, role = "intellect-damage", name = "奥术" }, { spec = 63, role = "intellect-damage", name = "火焰" }, { spec = 64, role = "intellect-damage", name = "冰霜" } },
    PALADIN = { { spec = 65, role = "intellect-healing", name = "神圣" }, { spec = 66, role = "strength-tank", name = "防护" }, { spec = 70, role = "strength-melee", name = "惩戒" } },
    WARRIOR = { { spec = 71, role = "strength-melee", name = "武器" }, { spec = 72, role = "strength-melee", name = "狂暴" }, { spec = 73, role = "strength-tank", name = "防护" } },
    DRUID = { { spec = 102, role = "intellect-damage", name = "平衡" }, { spec = 103, role = "agility-melee", name = "野性" }, { spec = 104, role = "agility-tank", name = "守护" }, { spec = 105, role = "intellect-healing", name = "恢复" } },
    DEATHKNIGHT = { { spec = 250, role = "strength-tank", name = "鲜血" }, { spec = 251, role = "strength-melee", name = "冰霜" }, { spec = 252, role = "strength-melee", name = "邪恶" } },
    HUNTER = { { spec = 253, role = "agility-ranged", name = "野兽控制" }, { spec = 254, role = "agility-ranged", name = "射击" }, { spec = 255, role = "agility-ranged", name = "生存" } },
    PRIEST = { { spec = 256, role = "intellect-healing", name = "戒律" }, { spec = 257, role = "intellect-healing", name = "神圣" }, { spec = 258, role = "intellect-damage", name = "暗影" } },
    ROGUE = { { spec = 259, role = "agility-melee", name = "刺杀" }, { spec = 260, role = "agility-melee", name = "战斗" }, { spec = 261, role = "agility-melee", name = "敏锐" } },
    SHAMAN = { { spec = 262, role = "intellect-damage", name = "元素" }, { spec = 263, role = "agility-melee", name = "增强" }, { spec = 264, role = "intellect-healing", name = "恢复" } },
    WARLOCK = { { spec = 265, role = "intellect-damage", name = "痛苦" }, { spec = 266, role = "intellect-damage", name = "恶魔学识" }, { spec = 267, role = "intellect-damage", name = "毁灭" } },
    MONK = { { spec = 268, role = "agility-tank", name = "酒仙" }, { spec = 269, role = "agility-melee", name = "踏风" }, { spec = 270, role = "intellect-healing", name = "织雾" } },
}

local RETAIL_EXTRA = {
    DEMONHUNTER = { { spec = 577, role = "agility-melee", name = "浩劫" }, { spec = 581, role = "agility-tank", name = "复仇" } },
    EVOKER = { { spec = 1467, role = "intellect-damage", name = "湮灭" }, { spec = 1468, role = "intellect-healing", name = "恩护" }, { spec = 1473, role = "intellect-damage", name = "增辉" } },
}

local function buildTree(classSpecs)
    local out = {}
    for classToken, entries in pairs(classSpecs) do
        local list = {}
        for _, entry in ipairs(entries) do
            list[#list + 1] = { key = "tree:" .. classToken .. ":" .. entry.tree, role = entry.role, name = entry.name }
        end
        out[classToken] = list
    end
    return out
end

local function buildModern(classSpecs)
    local out = {}
    for classToken, entries in pairs(classSpecs) do
        local list = {}
        for _, entry in ipairs(entries) do
            list[#list + 1] = { key = "spec:" .. entry.spec, role = entry.role, name = entry.name }
        end
        out[classToken] = list
    end
    return out
end

local function mergeSpecs(base, extra)
    local out = {}
    for classToken, list in pairs(base) do out[classToken] = list end
    for classToken, list in pairs(extra) do out[classToken] = list end
    return out
end

local treeSpecs = buildTree(TREE_RAW)
local titanSpecs = mergeSpecs(treeSpecs, buildTree(DEATHKNIGHT_TREE))
local modernSpecs = buildModern(MODERN_RAW)
local retailSpecs = mergeSpecs(modernSpecs, buildModern(RETAIL_EXTRA))

local FAMILIES = {
    vanilla = { order = TREE_CLASS_ORDER, specs = treeSpecs },
    tbc = { order = TREE_CLASS_ORDER, specs = treeSpecs },
    titan = { order = TITAN_CLASS_ORDER, specs = titanSpecs },
    mop = { order = MODERN_CLASS_ORDER, specs = modernSpecs },
    retail = { order = RETAIL_CLASS_ORDER, specs = retailSpecs },
}

local function profilesModule()
    return BG.BGNext.EquipmentFilterProfiles
end

local function compose(family, classToken, spec)
    local Profiles = profilesModule()
    local base = Profiles and Profiles.getClassBase(family, classToken)
    if not base then return nil end
    local role = ROLES[spec.role]
    if not role then return nil end
    local builtInKey = family .. ":" .. classToken .. ":" .. spec.key
    base.id = builtInKey
    base.builtInKey = builtInKey
    base.name = spec.name
    base.primaryStat = clone(role.primaryStat)
    base.affix = clone(role.affix)
    base.tankOnly = role.tankOnly
    return base
end

function M.listClasses(family)
    local familyDecl = FAMILIES[family]
    if not familyDecl then return {} end
    local result = {}
    for index, classToken in ipairs(familyDecl.order) do result[index] = classToken end
    return result
end

function M.list(family, classToken)
    local familyDecl = FAMILIES[family]
    if not familyDecl then return {} end
    local classSpecs = familyDecl.specs[classToken]
    if not classSpecs then return {} end
    local result = {}
    for _, spec in ipairs(classSpecs) do
        result[#result + 1] = compose(family, classToken, spec)
    end
    return result
end

function M.getDefault(family, classToken, specKey)
    local familyDecl = FAMILIES[family]
    if not familyDecl then return nil end
    local classSpecs = familyDecl.specs[classToken]
    if not classSpecs then return nil end
    for _, spec in ipairs(classSpecs) do
        if spec.key == specKey then return compose(family, classToken, spec) end
    end
    return nil
end

function M.getFallback(family, classToken)
    if not FAMILIES[family] then return nil end
    local Profiles = profilesModule()
    return Profiles and Profiles.getClassFallback(family, classToken) or nil
end

BG.BGNext.EquipmentFilterSpecializations = M
return M
