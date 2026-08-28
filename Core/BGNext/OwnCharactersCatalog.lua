-- BGNext own-character column catalog.
--
-- Declarative data only: which columns each client family may show, in which
-- order, with which title, width class and default visibility. No rendering,
-- no storage, no API calls.
--
-- Raid columns reuse the raid keys and instance IDs this repository already
-- declares in Core/DB/DB.lua. `title` is a fallback label only; the renderer
-- prefers Blizzard's own localized zone name via `zoneId` so BGNext never
-- ships a hand-written raid name where the client can supply the real one.
--
-- A declared column is not a promise that the client exposes it. Availability
-- is decided at runtime from the adapter capabilities and the collected
-- snapshot; a column with no readable source is hidden, never faked.

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

local function raid(id, zoneId, title, fullTitle, variant, instanceIds, defaultVisible, color)
    local ids = instanceIds
    if type(ids) ~= "table" then
        ids = type(zoneId) == "number" and { zoneId } or {}
    end
    return {
        id = id,
        section = "raid",
        title = title,
        fullTitle = fullTitle,
        color = color,
        zoneId = #ids == 1 and zoneId or nil,
        variant = variant,
        kind = "status",
        width = "narrow",
        defaultVisible = defaultVisible ~= false,
        total = false,
        source = {
            kind = "raid",
            key = id,
            instanceIds = ids,
            readable = #ids > 0,
        },
    }
end

local function resource(id, title, kind, width, total, source, defaultVisible, color)
    return {
        id = id,
        section = "resource",
        title = title,
        color = color,
        kind = kind,
        width = width,
        defaultVisible = defaultVisible ~= false,
        total = total,
        source = source,
    }
end

-- These summaries are backed by the same local-player APIs on every enabled
-- family. Version-specific currencies, upgrade tokens and special equipment
-- deliberately stay out of this list until that family's visible behaviour
-- and IDs have been verified independently.
local function baseResourceColumns()
    return {
        resource("mainProfession", "主专业", "profession", "wide", false,
            { kind = "profession-summary" }, true, "ADFF2F"),
        resource("weapons", "武器", "items", "dynamic-items", false,
            { kind = "equipment", slots = { 16, 17, 18 } }, true, "C084FC"),
        resource("trinkets", "饰品", "items", "dynamic-items", false,
            { kind = "equipment", slots = { 13, 14 } }, true, "C084FC"),
        resource("money", "金币", "money", "normal", true,
            { kind = "money" }, true, "FFD700"),
        resource("equipmentDetails", "装备详情", "items", "dynamic-items", false,
            { kind = "equipment" }, false),
    }
end

local CATALOG = {
    vanilla = {
        status = "pending-in-game-verification",
        raidColumns = {
            raid("MC", 409, "MC", "熔火之心", nil, { 409 }, true, "00BFFF"),
            raid("ONY", 249, "ONY", "奥妮克希亚的巢穴", nil, { 249 }, true, "00BFFF"),
            raid("BWL", 469, "BWL", "黑翼之巢", nil, { 469 }, true, "00BFFF"),
            raid("ZUG", 309, "ZG", "祖尔格拉布", nil, { 309 }, true, "00BFFF"),
            raid("AQL", 509, "AQ20", "安其拉废墟", nil, { 509 }, true, "00BFFF"),
            raid("TAQ", 531, "AQ40", "安其拉神殿", nil, { 531 }, true, "00BFFF"),
            raid("NAXX", 533, "NAXX", "纳克萨玛斯", nil, { 533 }, true, "00BFFF"),
        },
        resourceColumns = {
            resource("mainProfession", "主专业", "profession", "wide", false,
                { kind = "profession-summary" }, true, "ADFF2F"),
            resource("weapons", "武器", "items", "dynamic-items", false,
                { kind = "equipment", slots = { 16, 17, 18 } }, true, "C084FC"),
            resource("trinkets", "饰品", "items", "dynamic-items", false,
                { kind = "equipment", slots = { 13, 14 } }, true, "C084FC"),
            resource("atieshFragment", "埃提耶什", "number", "narrow", false,
                { kind = "currency", key = "atieshFragment" }, true, "FFFFFF"),
            resource("transmute", "炼金转化", "cooldown", "normal", false,
                { kind = "profession-cooldown", key = "transmute", spellId = 17187 }, true, "FFFFFF"),
            resource("saltShaker", "筛盐", "cooldown", "normal", false,
                { kind = "profession-cooldown", key = "saltShaker", spellId = 19566 }, true, "FFFFFF"),
            resource("mooncloth", "月布", "cooldown", "normal", false,
                { kind = "profession-cooldown", key = "mooncloth", spellId = 18560 }, true, "FFFFFF"),
            resource("restXp", "休息经验", "number", "narrow", false,
                { kind = "currency", key = "restXp" }, false, "FFFFFF"),
            resource("money", "金币", "money", "normal", true,
                { kind = "money" }, true, "FFD700"),
            resource("equipmentDetails", "装备详情", "items", "dynamic-items", false,
                { kind = "equipment" }, false),
        },
    },
    tbc = {
        status = "pending-in-game-verification",
        raidColumns = {
            raid("KZ", 532, "KZ", "卡拉赞", nil, { 532 }, true, "00BFFF"),
            raid("GL", 565, "GL", "格鲁尔的巢穴", nil, { 565 }, true, "00BFFF"),
            raid("ML", 544, "MAG", "玛瑟里顿的巢穴", nil, { 544 }, true, "00BFFF"),
            raid("SSC", 548, "SSC", "毒蛇神殿", nil, { 548 }, true, "00BFFF"),
            raid("TK", 550, "TK", "风暴要塞", nil, { 550 }, true, "00BFFF"),
            raid("HS", 534, "HYJAL", "海加尔山之战", nil, { 534 }, true, "00BFFF"),
            raid("BT", 564, "BT", "黑暗神殿", nil, { 564 }, true, "00BFFF"),
            raid("ZA", 568, "ZA", "祖阿曼", nil, { 568 }, true, "00BFFF"),
            raid("SW", 580, "SW", "太阳之井高地", nil, { 580 }, true, "00BFFF"),
        },
        resourceColumns = {
            resource("mainProfession", "主专业", "profession", "wide", false,
                { kind = "profession-summary" }, true, "ADFF2F"),
            resource("weapons", "武器", "items", "dynamic-items", false,
                { kind = "equipment", slots = { 16, 17, 18 } }, true, "C084FC"),
            resource("trinkets", "饰品", "items", "dynamic-items", false,
                { kind = "equipment", slots = { 13, 14 } }, true, "C084FC"),
            resource("badgeOfJustice", "公正徽章", "number", "narrow", false,
                { kind = "currency", key = "badgeOfJustice" }, true, "FFFFFF"),
            resource("honor", "荣誉", "number", "narrow", true,
                { kind = "currency", key = "honor" }, true, "FFFFFF"),
            resource("arenaPoints", "竞技场点数", "number", "narrow", true,
                { kind = "currency", key = "arenaPoints" }, false, "FFFFFF"),
            resource("restXp", "休息经验", "number", "narrow", false,
                { kind = "currency", key = "restXp" }, false, "FFFFFF"),
            resource("money", "金币", "money", "normal", true,
                { kind = "money" }, true, "FFD700"),
            resource("equipmentDetails", "装备详情", "items", "dynamic-items", false,
                { kind = "equipment" }, false),
        },
    },
    wrath = {
        status = "unverified",
        raidColumns = {},
        resourceColumns = {},
    },
    titan = {
        status = "tested-in-game",
        raidColumns = {
            raid("SWtitan", 580, "SW", "太阳之井高地", nil, { 580 }, true, "00BFFF"),
            raid("ZAtitan", 568, "ZAM", "祖阿曼", nil, { 568 }, true, "00BFFF"),
            raid("TOCtitan", 649, "TOC", "十字军的试炼", nil, { 649 }, true, "00BFFF"),
            raid("ZUGtitan", 309, "ZG", "祖尔格拉布", nil, { 309 }, true, "00BFFF"),
            raid("NAXXtitan", 533, "NAXX", "纳克萨玛斯", nil, { 533 }, true, "00BFFF"),
            raid("OStitan", 615, "黑曜石", "黑曜石圣殿", nil, { 615 }, false, "00BFFF"),
            raid("EOEtitan", 616, "永恒", "永恒之眼", nil, { 616 }, false, "00BFFF"),
            raid("SSCtitan", 548, "毒蛇", "毒蛇神殿", nil, { 548 }, false, "00BFFF"),
            raid("TKtitan", 550, "风暴", "风暴要塞", nil, { 550 }, false, "00BFFF"),
            raid("MCtitan", 409, "MC", "熔火之心", nil, { 409 }, true, "00BFFF"),
            raid("VOAtitan", 624, "宝库", "阿尔卡冯的宝库", nil, { 624 }, true, "00BFFF"),
            raid("Doomwalker", 119, "末日行者", "末日行者", nil, { 119 }, false, "99CCFF"),
            raid("DoomLordKazzak", 118, "末日领主", "末日领主卡扎克", nil, { 118 }, false, "99CCFF"),
            raid("Lanlongtitan", 116, "蓝龙", "艾索雷葛斯", nil, { 116 }, false, "99CCFF"),
            raid("Kazaketitan", 117, "卡扎克", "卡扎克", nil, { 117 }, false, "99CCFF"),
        },
        resourceColumns = {
            resource("mainProfession", "主专业", "profession", "wide", false,
                { kind = "profession-summary" }, true, "ADFF2F"),
            resource("weapons", "武器", "items", "dynamic-items", false,
                { kind = "equipment", slots = { 16, 17, 18 } }, true, "C084FC"),
            resource("trinkets", "饰品", "items", "dynamic-items", false,
                { kind = "equipment", slots = { 13, 14 } }, true, "C084FC"),
            resource("legendaryItems", "已有", "items", "dynamic-items", false,
                { kind = "tracked-items", prefix = "legendary:" }, true, "ff8000"),
            resource("upgradeItems", "升级", "items", "dynamic-items", false,
                { kind = "tracked-items", prefix = "upgrade:" }, true, "ff8000"),
            resource("titanEmber", "余烬", "number", "narrow", true,
                { kind = "currency", key = "titanEmber", currencyId = 3403, showHeaderIcon = true }, true, "ff9900"),
            resource("titanShard", "碎片", "number", "narrow", true,
                { kind = "currency", key = "titanShard", currencyId = 3406, showHeaderIcon = true }, true, "7B68EE"),
            resource("jewelcraftingToken", "珠宝日常", "number", "narrow", true,
                { kind = "currency", key = "jewelcraftingToken" }, false, "FFFFFF"),
            resource("cookingToken", "烹饪日常", "number", "narrow", true,
                { kind = "currency", key = "cookingToken" }, false, "FFFFFF"),
            resource("championSeal", "冠军徽记", "number", "narrow", true,
                { kind = "currency", key = "championSeal" }, false, "FFFFFF"),
            resource("stoneKeeper", "岩石", "number", "narrow", true,
                { kind = "currency", key = "stoneKeeper", currencyId = 161, showHeaderIcon = true }, true, "FFFFFF"),
            resource("arena", "竞技场点数", "number", "narrow", true,
                { kind = "currency", key = "arena" }, false, "FFFFFF"),
            resource("honor", "荣誉", "number", "narrow", true,
                { kind = "currency", key = "honor", currencyId = 1901, showHeaderIcon = true }, true, "FFFFFF"),
            resource("alchemyResearch", "炼金研究", "cooldown", "normal", false,
                { kind = "profession-cooldown", key = "alchemyResearch", spellId = 60893 }, false, "FFFFFF"),
            resource("alchemyTransmute", "炼金转化", "cooldown", "normal", false,
                { kind = "profession-cooldown", key = "alchemyTransmute", spellId = 66660 }, false, "FFFFFF"),
            resource("inscriptionResearch", "铭文研究", "cooldown", "normal", false,
                { kind = "profession-cooldown", key = "inscriptionResearch", spellId = 61177 }, false, "FFFFFF"),
            resource("minorInscription", "次级铭文", "cooldown", "normal", false,
                { kind = "profession-cooldown", key = "minorInscription", spellId = 61288 }, false, "FFFFFF"),
            resource("icyPrism", "寒冰棱镜", "cooldown", "normal", false,
                { kind = "profession-cooldown", key = "icyPrism", spellId = 62242 }, false, "FFFFFF"),
            resource("smeltTitansteel", "泰坦精钢", "cooldown", "normal", false,
                { kind = "profession-cooldown", key = "smeltTitansteel", spellId = 55208 }, false, "FFFFFF"),
            resource("spellweave", "法术纹布", "cooldown", "normal", false,
                { kind = "profession-cooldown", key = "spellweave", spellId = 56003 }, false, "FFFFFF"),
            resource("ebonweave", "乌纹布", "cooldown", "normal", false,
                { kind = "profession-cooldown", key = "ebonweave", spellId = 56002 }, false, "FFFFFF"),
            resource("moonshroud", "月影布", "cooldown", "normal", false,
                { kind = "profession-cooldown", key = "moonshroud", spellId = 56001 }, false, "FFFFFF"),
            resource("glacialBag", "冰川包", "cooldown", "normal", false,
                { kind = "profession-cooldown", key = "glacialBag", spellId = 56005 }, false, "FFFFFF"),
            resource("money", "金币", "money", "normal", true, { kind = "money" }, true, "FFD700"),
            resource("equipmentDetails", "装备详情", "items", "dynamic-items", false,
                { kind = "equipment" }, false),
        },
    },
    cata = {
        status = "unverified",
        raidColumns = {},
        resourceColumns = {},
    },
    mop = {
        status = "pending-in-game-verification",
        raidColumns = {
            raid("MSV", 1008, "MSV", "魔古山宝库", nil, { 1008 }, true, "00BFFF"),
            raid("HOF", 1009, "HOF", "恐惧之心", nil, { 1009 }, true, "00BFFF"),
            raid("TES", 996, "TOES", "永春台", nil, { 996 }, true, "00BFFF"),
            raid("TOT", 1098, "TOT", "雷电王座", nil, { 1098 }, true, "00BFFF"),
            raid("SOO", 1136, "SOO", "决战奥格瑞玛", nil, { 1136 }, true, "00BFFF"),
        },
        resourceColumns = {
            resource("mainProfession", "主专业", "profession", "wide", false,
                { kind = "profession-summary" }, true, "ADFF2F"),
            resource("weapons", "武器", "items", "dynamic-items", false,
                { kind = "equipment", slots = { 16, 17, 18 } }, true, "C084FC"),
            resource("trinkets", "饰品", "items", "dynamic-items", false,
                { kind = "equipment", slots = { 13, 14 } }, true, "C084FC"),
            resource("valor", "勇气", "number", "narrow", false,
                { kind = "currency", key = "valor", currencyId = 396, showHeaderIcon = true }, true, "FFFFFF"),
            resource("justice", "正义", "number", "narrow", false,
                { kind = "currency", key = "justice", currencyId = 395, showHeaderIcon = true }, true, "FFFFFF"),
            resource("roll", "战火徽记", "number", "narrow", false,
                { kind = "currency", key = "roll", currencyId = 776, showHeaderIcon = true }, true, "FFFFFF"),
            resource("conquest", "征服点数", "number", "narrow", false,
                { kind = "currency", key = "conquest", currencyId = 390, showHeaderIcon = true }, false, "FFFFFF"),
            resource("honor", "荣誉", "number", "narrow", false,
                { kind = "currency", key = "honor", currencyId = 1901, showHeaderIcon = true }, false, "FFFFFF"),
            resource("ironpawToken", "铁掌代币", "number", "narrow", false,
                { kind = "currency", key = "ironpawToken", currencyId = 402, showHeaderIcon = true }, false, "FFFFFF"),
            resource("darkmoonTicket", "暗月奖券", "number", "narrow", false,
                { kind = "currency", key = "darkmoonTicket", currencyId = 515, showHeaderIcon = true }, false, "FFFFFF"),
            resource("elderCharm", "长者好运符", "number", "narrow", false,
                { kind = "currency", key = "elderCharm", currencyId = 697, showHeaderIcon = true }, false, "FFFFFF"),
            resource("lesserCharm", "次级好运符", "number", "narrow", false,
                { kind = "currency", key = "lesserCharm", currencyId = 738, showHeaderIcon = true }, false, "FFFFFF"),
            resource("moguRune", "魔古命运符文", "number", "narrow", false,
                { kind = "currency", key = "moguRune", currencyId = 752, showHeaderIcon = true }, false, "FFFFFF"),
            resource("timelessCoin", "永恒铸币", "number", "narrow", false,
                { kind = "currency", key = "timelessCoin", currencyId = 777, showHeaderIcon = true }, false, "FFFFFF"),
            resource("currency3350", "候选货币", "number", "narrow", false,
                { kind = "currency", key = "currency3350", currencyId = 3350, showHeaderIcon = true }, false, "FFFFFF"),
            resource("currency3407", "候选货币", "number", "narrow", false,
                { kind = "currency", key = "currency3407", currencyId = 3407, showHeaderIcon = true }, false, "FFFFFF"),
            resource("currency3414", "候选货币", "number", "narrow", false,
                { kind = "currency", key = "currency3414", currencyId = 3414, showHeaderIcon = true }, false, "FFFFFF"),
            resource("currency3416", "候选货币", "number", "narrow", false,
                { kind = "currency", key = "currency3416", currencyId = 3416, showHeaderIcon = true }, false, "FFFFFF"),
            resource("item256883", "候选物品", "number", "narrow", false,
                { kind = "currency", key = "item256883" }, false, "FFFFFF"),
            resource("item247796", "候选物品", "number", "narrow", false,
                { kind = "currency", key = "item247796" }, false, "FFFFFF"),
            resource("transmuteLivingSteel", "活化钢", "cooldown", "normal", false,
                { kind = "profession-cooldown", key = "transmuteLivingSteel", spellId = 114780 }, false, "FFFFFF"),
            resource("lightningSteelIngot", "闪电钢锭", "cooldown", "normal", false,
                { kind = "profession-cooldown", key = "lightningSteelIngot", spellId = 138646 }, false, "FFFFFF"),
            resource("shaCrystal", "煞水晶", "cooldown", "normal", false,
                { kind = "profession-cooldown", key = "shaCrystal", spellId = 116499 }, false, "FFFFFF"),
            resource("scrollOfWisdom", "智慧卷轴", "cooldown", "normal", false,
                { kind = "profession-cooldown", key = "scrollOfWisdom", spellId = 112996 }, false, "FFFFFF"),
            resource("facetsOfResearch", "研究刻面", "cooldown", "normal", false,
                { kind = "profession-cooldown", key = "facetsOfResearch", spellId = 131686 }, false, "FFFFFF"),
            resource("serpentsHeart", "蛇心", "cooldown", "normal", false,
                { kind = "profession-cooldown", key = "serpentsHeart", spellId = 140050 }, false, "FFFFFF"),
            resource("magnificenceOfLeather", "壮丽皮革", "cooldown", "normal", false,
                { kind = "profession-cooldown", key = "magnificenceOfLeather", spellId = 140040 }, false, "FFFFFF"),
            resource("imperialSilk", "帝国丝绸", "cooldown", "normal", false,
                { kind = "profession-cooldown", key = "imperialSilk", spellId = 125557 }, false, "FFFFFF"),
            resource("jardsPeculiarEnergy", "贾德能量", "cooldown", "normal", false,
                { kind = "profession-cooldown", key = "jardsPeculiarEnergy", spellId = 139176 }, false, "FFFFFF"),
            resource("money", "金币", "money", "normal", true, { kind = "money" }, true, "FFD700"),
            resource("equipmentDetails", "装备详情", "items", "dynamic-items", false,
                { kind = "equipment" }, false),
        },
    },
    retail = {
        status = "pending-in-game-verification",
        raidColumns = {
            raid("VA", 3004, "VA", "当前赛季团本", nil, { 3004 }, true, "00BFFF"),
            raid("VS", 2912, "VS", "P1团本", nil, { 2912 }, false, "00BFFF"),
            raid("DR", 2939, "DR", "梦境裂隙", nil, { 2939 }, false, "00BFFF"),
            raid("MQD", 2913, "MQD", "进军奎尔丹纳斯", nil, { 2913 }, false, "00BFFF"),
            raid("Micosis", 1592, "Micosis", "孢陨幽境", nil, { 1592 }, false, "00BFFF"),
        },
        resourceColumns = baseResourceColumns(),
    },
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

local SECTION_KEY = { raid = "raidColumns", resource = "resourceColumns" }

-- Returns a defensive copy so callers may sort, filter or annotate freely.
function M.forFamily(family)
    local catalog = type(family) == "string" and CATALOG[family] or nil
    if not catalog then return nil end
    return {
        family = family,
        status = catalog.status,
        raidColumns = clone(catalog.raidColumns),
        resourceColumns = clone(catalog.resourceColumns),
    }
end

function M.status(family)
    local catalog = type(family) == "string" and CATALOG[family] or nil
    return catalog and catalog.status or "unverified"
end

function M.column(family, section, columnId)
    local catalog = type(family) == "string" and CATALOG[family] or nil
    local key = SECTION_KEY[section]
    if not catalog or not key or type(columnId) ~= "string" then return nil end
    for _, column in ipairs(catalog[key]) do
        if column.id == columnId then return clone(column) end
    end
    return nil
end

-- Unknown families and columns default to hidden rather than shown, so a
-- catalog gap can never leak an unexplained column into the table.
function M.defaultVisible(family, section, columnId)
    local column = M.column(family, section, columnId)
    if not column then return false end
    return column.defaultVisible == true
end

BG.BGNext.OwnCharactersCatalog = M
return M
