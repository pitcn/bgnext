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

-- Role rule families are authored independently and client-scoped: primary
-- stat and tank-only flag are fixed, while the wrong-role affix filter is
-- derived per family (see defaultAffix) so a profile never references an
-- affix that does not exist in that client.
local ROLES = {
    ["strength-melee"] = { primaryStat = { STRENGTH = true }, tankOnly = false },
    ["agility-melee"] = { primaryStat = { AGILITY = true }, tankOnly = false },
    ["agility-ranged"] = { primaryStat = { AGILITY = true }, tankOnly = false },
    ["intellect-damage"] = { primaryStat = { INTELLECT = true }, tankOnly = false },
    ["intellect-healing"] = { primaryStat = { INTELLECT = true }, tankOnly = false },
    ["strength-tank"] = { primaryStat = { STRENGTH = true }, tankOnly = true },
    ["agility-tank"] = { primaryStat = { AGILITY = true }, tankOnly = true },
    ["feral-ambiguous"] = { primaryStat = { AGILITY = true }, tankOnly = false },
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

local function addFilters(target, ids)
    for _, id in ipairs(ids or {}) do target[id] = true end
end

local function isModern(family)
    return family == "mop" or family == "retail"
end

local function isClassic(family)
    return family == "vanilla" or family == "tbc"
end

local function specNumber(spec)
    return tonumber(spec.key and spec.key:match(":(%d+)$"))
end

-- Wrong-role affix filter, per client family. Physical rules drop spell power;
-- caster/healer rules drop attack power plus the physical-only affixes that
-- exist in that family. Retail has no wrong-role affixes (primary stat is the
-- separate choice), so its affix filter is empty.
local function defaultAffix(family, role)
    local physical = role ~= "intellect-damage" and role ~= "intellect-healing"
    if family == "retail" then return {} end
    if physical then return { SPELL_POWER = true } end
    if family == "vanilla" then return { ATTACK_POWER = true } end
    if family == "tbc" then return { ATTACK_POWER = true, EXPERTISE = true } end
    if family == "mop" then return { ATTACK_POWER = true, EXPERTISE = true } end
    return { ATTACK_POWER = true, ARMOR_PEN = true, EXPERTISE = true }
end

local function applyEquipmentOverrides(family, classToken, spec, base)
    local num = specNumber(spec)
    if classToken == "HUNTER" then
        if family == "mop" or family == "retail" then
            local ranged = spec.key ~= "spec:255" or family == "mop"
            if ranged then
                addFilters(base.weapon, { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15 })
            else
                addFilters(base.weapon, { 2, 3, 18 })
            end
        else
            -- The first specialization test package incorrectly applied the
            -- post-MoP single-weapon-slot rule to classic-family Hunters. Keep
            -- the exact generated set only as transient migration evidence.
            base.upgradeWeaponFrom = clone(base.weapon)
            addFilters(base.upgradeWeaponFrom, { 0, 1, 4, 5, 6, 7, 8, 10, 13, 15 })
        end
    elseif classToken == "PALADIN" then
        if spec.role == "intellect-healing" then
            addFilters(base.weapon, { 1, 5, 6, 8 })
        elseif spec.role == "strength-tank" then
            addFilters(base.weapon, { 1, 5, 6, 8 })
            addFilters(base.armor, { 0, 1, 2, 3 })
        elseif spec.role == "strength-melee" then
            addFilters(base.weapon, { 0, 4, 7 })
            addFilters(base.armor, { 0, 1, 6 })
        end
    elseif classToken == "WARRIOR" then
        -- Tree indices 1/2/3 map to modern spec ids 71/72/73 (arms/fury/prot).
        if num == 3 or num == 73 then
            -- Protection: sword-and-board, filters two-handers and off-armor.
            addFilters(base.weapon, { 1, 5, 6, 8, 10 })
            if isModern(family) then addFilters(base.weapon, { 2, 3, 18 }) end
            addFilters(base.armor, { 2, 3 })
        elseif num == 2 or num == 72 then
            -- Fury: dual-wields one-handers pre-WotLK, two-handers from Titan's
            -- Grip (WotLK 3.0) onward.
            if isClassic(family) then
                addFilters(base.weapon, { 1, 5, 6, 8, 10 })
            else
                addFilters(base.weapon, { 15, 13, 0, 4, 7 })
            end
            if isModern(family) then
                addFilters(base.armor, { 2, 3, 6 })
            else
                addFilters(base.armor, { 6 })
            end
        else
            -- Arms: two-handers only.
            addFilters(base.weapon, { 15, 13, 0, 4, 7 })
            if isModern(family) then addFilters(base.weapon, { 2, 3, 18 }) end
            if isModern(family) then
                addFilters(base.armor, { 2, 3, 6 })
            else
                addFilters(base.armor, { 6 })
            end
        end
    elseif classToken == "SHAMAN" then
        if spec.role == "agility-melee" then
            -- Enhancement is dual-wield: no shield or off-hand stat stick.
            addFilters(base.armor, { 0, 6 })
        else
            -- Elemental and Restoration use a main-hand and a shield/off-hand,
            -- so two-handers are out.
            addFilters(base.weapon, { 1, 5 })
        end
    elseif classToken == "DRUID" then
        if spec.role == "intellect-damage" or spec.role == "intellect-healing" then
            addFilters(base.weapon, { 5, 6 })
        else
            -- Feral / Guardian: claws and staves, no daggers/fists/maces/off-armor.
            addFilters(base.weapon, { 15, 13, 4 })
            addFilters(base.armor, { 1, 0 })
        end
    elseif classToken == "DEATHKNIGHT" then
        -- Tree indices 1/2/3 map to modern spec ids 250/251/252 (blood/frost/unholy).
        if num == 1 or num == 250 then
            -- Blood tanks with a two-hander.
            addFilters(base.weapon, { 0, 4, 7 })
            addFilters(base.armor, { 2, 3 })
        elseif num == 3 or num == 252 then
            -- Unholy keeps dual-wield in the tree era; modern Unholy uses a two-hander.
            if isModern(family) then
                addFilters(base.weapon, { 0, 4, 7 })
            end
        end
        -- Frost (2/251) keeps one-handers in every family: no override.
    elseif classToken == "MONK" then
        if spec.role == "intellect-healing" then
            -- Mistweaver is a caster: no polearms.
            addFilters(base.weapon, { 6 })
        else
            -- Brewmaster and Windwalker fight with both hands free.
            addFilters(base.armor, { 0 })
        end
    end
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
    base.affix = defaultAffix(family, spec.role)
    base.tankOnly = role.tankOnly and (family == "titan" or family == "mop")
    applyEquipmentOverrides(family, classToken, spec, base)
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
