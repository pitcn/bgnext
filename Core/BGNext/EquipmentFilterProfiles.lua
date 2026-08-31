BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

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

local weaponRules = {
    [0] = "单手斧", [1] = "双手斧", [2] = "弓", [3] = "枪", [4] = "单手锤",
    [5] = "双手锤", [6] = "长柄武器", [7] = "单手剑", [8] = "双手剑",
    [9] = "战刃", [10] = "法杖", [13] = "拳套", [15] = "匕首",
    [16] = "投掷武器", [18] = "弩", [19] = "魔杖",
}

local armorRules = {
    [0] = "副手物品", [1] = "布甲", [2] = "皮甲", [3] = "锁甲", [4] = "板甲", [6] = "盾牌",
}

local affixRules = {
    STRENGTH = "力量", AGILITY = "敏捷", INTELLECT = "智力", SPIRIT = "精神",
    MANA_REGEN = "法力回复", DEFENSE = "防御", PARRY = "招架", DODGE = "躲闪",
    BLOCK = "格挡", ATTACK_POWER = "攻击强度", HIT = "命中", CRIT = "爆击",
    HASTE = "急速", EXPERTISE = "精准", ARMOR_PEN = "护甲穿透", SPELL_POWER = "法术强度",
    MASTERY = "精通", VERSATILITY = "全能", RESILIENCE = "韧性",
}

local classNames = {
    DEATHKNIGHT = "死亡骑士", DEMONHUNTER = "恶魔猎手", DRUID = "德鲁伊",
    EVOKER = "唤魔师", HUNTER = "猎人", MAGE = "法师", MONK = "武僧",
    PALADIN = "圣骑士", PRIEST = "牧师", ROGUE = "盗贼", SHAMAN = "萨满",
    WARLOCK = "术士", WARRIOR = "战士",
}

local classIcons = {
    DEATHKNIGHT = "Interface/Icons/spell_deathknight_classicon",
    DEMONHUNTER = "Interface/Icons/classicon_demonhunter",
    DRUID = "Interface/Icons/classicon_druid",
    EVOKER = "Interface/Icons/classicon_evoker",
    HUNTER = "Interface/Icons/classicon_hunter",
    MAGE = 135846,
    MONK = "Interface/Icons/classicon_monk",
    PALADIN = "Interface/Icons/classicon_paladin",
    PRIEST = "Interface/Icons/classicon_priest",
    ROGUE = "Interface/Icons/classicon_rogue",
    SHAMAN = "Interface/Icons/classicon_shaman",
    WARLOCK = "Interface/Icons/classicon_warlock",
    WARRIOR = "Interface/Icons/classicon_warrior",
}

-- Armor a class keeps in pre-Cataclysm families (vanilla/tbc/titan): lower armor
-- tiers are still viable off-pieces because armor specialization does not exist.
local allowedArmorClassic = {
    MAGE = { [0] = true, [1] = true }, PRIEST = { [0] = true, [1] = true },
    WARLOCK = { [0] = true, [1] = true },
    DRUID = { [0] = true, [1] = true, [2] = true }, ROGUE = { [2] = true },
    MONK = { [0] = true, [2] = true }, DEMONHUNTER = { [2] = true },
    HUNTER = { [2] = true, [3] = true },
    SHAMAN = { [0] = true, [1] = true, [2] = true, [3] = true, [6] = true },
    EVOKER = { [3] = true },
    DEATHKNIGHT = { [2] = true, [3] = true, [4] = true },
    PALADIN = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [6] = true },
    WARRIOR = { [2] = true, [3] = true, [4] = true, [6] = true },
}

-- Armor a class keeps once armor specialization tightens it to the class's own
-- armor type (Cataclysm and later: mop/retail).
local allowedArmorModern = {
    MAGE = { [0] = true, [1] = true }, PRIEST = { [0] = true, [1] = true },
    WARLOCK = { [0] = true, [1] = true },
    DRUID = { [0] = true, [2] = true }, ROGUE = { [2] = true },
    MONK = { [0] = true, [2] = true }, DEMONHUNTER = { [2] = true },
    HUNTER = { [3] = true },
    SHAMAN = { [0] = true, [3] = true, [6] = true },
    EVOKER = { [3] = true },
    DEATHKNIGHT = { [4] = true },
    PALADIN = { [0] = true, [4] = true, [6] = true },
    WARRIOR = { [4] = true, [6] = true },
}

local primaryStats = {
    DEATHKNIGHT = { STRENGTH = true }, DEMONHUNTER = { AGILITY = true },
    DRUID = { AGILITY = true, INTELLECT = true }, EVOKER = { INTELLECT = true },
    HUNTER = { AGILITY = true }, MAGE = { INTELLECT = true },
    MONK = { AGILITY = true, INTELLECT = true }, PALADIN = { STRENGTH = true, INTELLECT = true },
    PRIEST = { INTELLECT = true }, ROGUE = { AGILITY = true },
    SHAMAN = { AGILITY = true, INTELLECT = true }, WARLOCK = { INTELLECT = true },
    WARRIOR = { STRENGTH = true },
}

-- These defaults describe only classes whose built-in profile has one
-- unambiguous damage-stat family. Hybrid classes intentionally stay empty:
-- their one class-wide profile cannot safely guess the player's spec.
local damageAffixes = {
    DEATHKNIGHT = { SPELL_POWER = true }, DEMONHUNTER = { SPELL_POWER = true },
    HUNTER = { SPELL_POWER = true }, ROGUE = { SPELL_POWER = true },
    WARRIOR = { SPELL_POWER = true },
    EVOKER = { ATTACK_POWER = true }, MAGE = { ATTACK_POWER = true },
    PRIEST = { ATTACK_POWER = true }, WARLOCK = { ATTACK_POWER = true },
}

local allowedWeapons = {
    DEATHKNIGHT = { 0, 1, 4, 5, 6, 7, 8 }, DEMONHUNTER = { 0, 7, 9, 13 },
    DRUID = { 4, 5, 6, 10, 13, 15 }, EVOKER = { 0, 4, 7, 10, 13, 15 },
    HUNTER = { 0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 18 },
    MAGE = { 7, 10, 15, 19 }, MONK = { 0, 4, 6, 7, 10, 13 },
    PALADIN = { 0, 1, 4, 5, 6, 7, 8 }, PRIEST = { 4, 10, 15, 19 },
    ROGUE = { 0, 4, 7, 13, 15 }, SHAMAN = { 0, 1, 4, 5, 10, 13, 15 },
    WARLOCK = { 7, 10, 15, 19 }, WARRIOR = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18 },
}

local function complement(catalog, allowed)
    local allow = {}
    for _, id in ipairs(allowed or {}) do allow[id] = true end
    local filtered = {}
    for id in pairs(catalog) do
        if not allow[id] then filtered[id] = true end
    end
    return filtered
end

local function isModernFamily(family)
    return family == "mop" or family == "retail"
end

local function armorFilter(family, classToken)
    local filtered = {}
    local allowed = (isModernFamily(family) and allowedArmorModern or allowedArmorClassic)[classToken] or {}
    for id in pairs(armorRules) do
        if not allowed[id] then filtered[id] = true end
    end
    return filtered
end

local function allowedWeaponsFor(family, classToken)
    local allowed = allowedWeapons[classToken]
    if not allowed then return nil end
    if classToken == "ROGUE" and not isModernFamily(family) then
        -- Pre-Cataclysm rogues carry a ranged stat-stick (bow/gun/crossbow/thrown).
        local result = {}
        for _, id in ipairs(allowed) do result[#result + 1] = id end
        for _, id in ipairs({ 2, 3, 16, 18 }) do result[#result + 1] = id end
        return result
    end
    return allowed
end

-- Affixes that exist (and are therefore selectable and filterable) in each
-- client family. Strength/agility/intellect remain ordinary affixes in every
-- pre-Retail family and move to the separate primary-stat choice on Retail.
local affixVisibility = {
    vanilla = { "STRENGTH", "AGILITY", "INTELLECT", "SPIRIT", "MANA_REGEN", "DEFENSE", "PARRY", "DODGE", "BLOCK", "ATTACK_POWER", "HIT", "CRIT", "SPELL_POWER" },
    tbc = { "STRENGTH", "AGILITY", "INTELLECT", "SPIRIT", "MANA_REGEN", "DEFENSE", "PARRY", "DODGE", "BLOCK", "ATTACK_POWER", "HIT", "CRIT", "HASTE", "EXPERTISE", "SPELL_POWER" },
    titan = { "STRENGTH", "AGILITY", "INTELLECT", "SPIRIT", "MANA_REGEN", "DEFENSE", "PARRY", "DODGE", "BLOCK", "ATTACK_POWER", "HIT", "CRIT", "HASTE", "EXPERTISE", "ARMOR_PEN", "SPELL_POWER" },
    mop = { "STRENGTH", "AGILITY", "INTELLECT", "SPIRIT", "DEFENSE", "PARRY", "DODGE", "ATTACK_POWER", "HIT", "CRIT", "HASTE", "EXPERTISE", "SPELL_POWER", "MASTERY", "RESILIENCE" },
    retail = { "CRIT", "HASTE", "MASTERY", "VERSATILITY" },
}

function M.getRuleCatalog(client)
    local result = clone({
        weapon = weaponRules,
        armor = armorRules,
        affix = affixRules,
        primaryStat = { STRENGTH = "力量", AGILITY = "敏捷", INTELLECT = "智力" },
        supportsTank = not client or client.supportsTank ~= false,
    })
    local family = client and client.family
    local visible = family and affixVisibility[family]
    if visible then
        local allowed = {}
        for _, key in ipairs(visible) do allowed[key] = true end
        for key in pairs(result.affix) do
            if not allowed[key] then result.affix[key] = nil end
        end
    end
    return result
end

local function baseProfile(family, classToken)
    if not classNames[classToken] then return nil end
    local localized = _G and _G.LOCALIZED_CLASS_NAMES_MALE
    local name = localized and localized[classToken] or classNames[classToken]
    return {
        name = name,
        icon = classIcons[classToken],
        weapon = complement(weaponRules, allowedWeaponsFor(family, classToken)),
        armor = armorFilter(family, classToken),
        affix = {},
        classRestriction = true,
        ignoreBattleNetBound = false,
        tankOnly = false,
        primaryStat = primaryStats[classToken] or {},
    }
end

function M.getClassIcon(classToken)
    return classIcons[classToken]
end

function M.getClassBase(family, classToken)
    local base = baseProfile(family, classToken)
    if not base then return nil end
    return clone(base)
end

function M.getClassFallback(family, classToken)
    local base = baseProfile(family, classToken)
    if not base then return nil end
    local key = family .. ":" .. classToken .. ":class"
    base.id = key
    base.builtInKey = key
    return clone(base)
end

function M.getDefaults(client, classToken)
    -- The legacy fallback path is a conservative class profile that keeps the
    -- loosest (classic) armor and weapon sets rather than over-filtering.
    local base = baseProfile(nil, classToken)
    if not base then return {} end
    local profile = clone(base)
    profile.id = classToken
    profile.builtInKey = classToken
    return { profile }
end

BG.BGNext.EquipmentFilterProfiles = M
return M
