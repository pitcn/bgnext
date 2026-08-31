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

local allowedArmor = {
    MAGE = { [0] = true, [1] = true }, PRIEST = { [0] = true, [1] = true },
    WARLOCK = { [0] = true, [1] = true },
    DRUID = { [0] = true, [1] = true, [2] = true }, ROGUE = { [1] = true, [2] = true },
    MONK = { [1] = true, [2] = true }, DEMONHUNTER = { [1] = true, [2] = true },
    HUNTER = { [1] = true, [2] = true, [3] = true },
    SHAMAN = { [0] = true, [1] = true, [2] = true, [3] = true, [6] = true },
    EVOKER = { [0] = true, [1] = true, [2] = true, [3] = true },
    DEATHKNIGHT = { [1] = true, [2] = true, [3] = true, [4] = true },
    PALADIN = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [6] = true },
    WARRIOR = { [1] = true, [2] = true, [3] = true, [4] = true, [6] = true },
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
    DEATHKNIGHT = { 0, 1, 4, 5, 6, 7, 8 }, DEMONHUNTER = { 0, 7, 9, 13, 15 },
    DRUID = { 4, 5, 6, 10, 13, 15 }, EVOKER = { 0, 4, 7, 10, 15 },
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

local function armorFilter(classToken)
    local filtered = {}
    local allowed = allowedArmor[classToken] or {}
    for id in pairs(armorRules) do
        if not allowed[id] then filtered[id] = true end
    end
    return filtered
end

function M.getRuleCatalog(client)
    return clone({
        weapon = weaponRules,
        armor = armorRules,
        affix = affixRules,
        primaryStat = { STRENGTH = "力量", AGILITY = "敏捷", INTELLECT = "智力" },
        supportsTank = not client or client.supportsTank ~= false,
    })
end

local function baseProfile(classToken)
    if not classNames[classToken] then return nil end
    local localized = _G and _G.LOCALIZED_CLASS_NAMES_MALE
    local name = localized and localized[classToken] or classNames[classToken]
    return {
        name = name,
        icon = classIcons[classToken],
        weapon = complement(weaponRules, allowedWeapons[classToken]),
        armor = armorFilter(classToken),
        affix = damageAffixes[classToken] or {},
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
    local base = baseProfile(classToken)
    if not base then return nil end
    return clone(base)
end

function M.getClassFallback(family, classToken)
    local base = baseProfile(classToken)
    if not base then return nil end
    local key = family .. ":" .. classToken .. ":class"
    base.id = key
    base.builtInKey = key
    return clone(base)
end

function M.getDefaults(client, classToken)
    local base = baseProfile(classToken)
    if not base then return {} end
    local profile = clone(base)
    profile.id = classToken
    profile.builtInKey = classToken
    return { profile }
end

BG.BGNext.EquipmentFilterProfiles = M
return M
