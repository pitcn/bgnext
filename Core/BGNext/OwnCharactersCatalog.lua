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

local function raid(id, zoneId, title, variant, instanceIds, defaultVisible, color)
    local ids = instanceIds
    if type(ids) ~= "table" then
        ids = type(zoneId) == "number" and { zoneId } or {}
    end
    return {
        id = id,
        section = "raid",
        title = title,
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

-- Columns every supported client can attempt. Order follows the approved
-- design: professions, equipment, currencies, honor, gold.
local function commonResources(extra)
    local columns = {
        resource("prof1", "专业1", "profession", "normal", false, { kind = "profession", index = 1 }),
        resource("prof2", "专业2", "profession", "normal", false, { kind = "profession", index = 2 }),
        resource("equipment", "装备", "items", "dynamic-items", false, { kind = "equipment" }),
    }
    for _, column in ipairs(extra or {}) do
        columns[#columns + 1] = column
    end
    columns[#columns + 1] = resource("honor", "荣誉", "number", "narrow", true, { kind = "currency", key = "honor" })
    columns[#columns + 1] = resource("money", "金币", "money", "normal", true, { kind = "money" })
    return columns
end

local CATALOG = {
    vanilla = {
        raidColumns = {
            raid("MC", 409, "熔火之心", "era"),
            raid("BWL", 469, "黑翼之巢", "era"),
            raid("ZUG", 309, "祖尔格拉布", "era"),
            raid("AQL", 509, "安其拉废墟", "era"),
            raid("TAQ", 531, "安其拉神殿", "era"),
            raid("NAXX", 533, "纳克萨玛斯", "era"),
            raid("BD", 48, "黑暗深渊", "sod"),
            raid("Gno", 90, "诺莫瑞根", "sod"),
            raid("Temple", 109, "沉没的神庙", "sod"),
            raid("MCsod", 409, "熔火之心", "sod"),
            raid("ZUGsod", 309, "祖尔格拉布", "sod"),
            raid("BWLsod", 469, "黑翼之巢", "sod"),
            raid("Worldsod", 249, "世界Boss", "sod"),
        },
        resourceColumns = commonResources(),
    },
    tbc = {
        raidColumns = {
            raid("KZ", 532, "卡拉赞"),
            raid("GL", 565, "格鲁尔的巢穴"),
            raid("SSC", 548, "毒蛇风暴"),
            raid("BT", 534, "海山黑庙"),
        },
        resourceColumns = commonResources(),
    },
    wrath = {
        raidColumns = {
            raid("NAXX", 533, "纳克萨玛斯"),
            raid("ULD", 603, "奥杜尔"),
            raid("TOC", 649, "十字军的试炼"),
            raid("ICC", 631, "冰冠堡垒"),
        },
        resourceColumns = commonResources({
            resource("emblem", "徽章", "number", "narrow", true, { kind = "currency", key = "emblem" }),
        }),
    },
    titan = {
        raidColumns = {
            raid("SWtitan", 580, "SW", nil, { 580 }, true, "00BFFF"),
            raid("ZAtitan", 568, "ZAM", nil, { 568 }, true, "00BFFF"),
            raid("TOCtitan", 649, "TOC", nil, { 649 }, true, "00BFFF"),
            raid("ZUGtitan", 309, "ZG", nil, { 309 }, true, "00BFFF"),
            raid("NAXXtitan", 533, "NAXX", nil, { 533 }, true, "00BFFF"),
            raid("OStitan", 615, "黑曜石", nil, { 615 }, false, "00BFFF"),
            raid("EOEtitan", 616, "永恒", nil, { 616 }, false, "00BFFF"),
            raid("SSCtitan", 548, "毒蛇", nil, { 548 }, false, "00BFFF"),
            raid("TKtitan", 550, "风暴", nil, { 550 }, false, "00BFFF"),
            raid("MCtitan", 409, "MC", nil, { 409 }, true, "00BFFF"),
            raid("VOAtitan", 624, "宝库", nil, { 624 }, true, "00BFFF"),
            raid("Doomwalker", 119, "末日行者", nil, { 119 }, false, "99CCFF"),
            raid("DoomLordKazzak", 118, "末日领主", nil, { 118 }, false, "99CCFF"),
            raid("Lanlongtitan", 116, "蓝龙", nil, { 116 }, false, "99CCFF"),
            raid("Kazaketitan", 117, "卡扎克", nil, { 117 }, false, "99CCFF"),
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
            resource("money", "金币", "money", "normal", true, { kind = "money" }, true, "FFD700"),
            resource("equipmentDetails", "装备详情", "items", "dynamic-items", false,
                { kind = "equipment" }, false),
        },
    },
    cata = {
        raidColumns = {
            raid("BOT", 671, "暮光堡垒"),
            raid("FL", 720, "火焰之地"),
            raid("DS", 967, "巨龙之魂"),
        },
        resourceColumns = commonResources({
            resource("valor", "勇气点数", "number", "narrow", true, { kind = "currency", key = "valor" }),
        }),
    },
    mop = {
        raidColumns = {
            raid("MSV", 1008, "P1三本"),
            raid("TOT", 1098, "雷电王座"),
            raid("SOO", 1136, "决战奥格瑞玛"),
        },
        resourceColumns = commonResources({
            resource("valor", "勇气点数", "number", "narrow", true, { kind = "currency", key = "valor" }),
        }),
    },
    retail = {
        raidColumns = {
            raid("VS", 2912, "P1三本"),
            raid("VA", 3004, "VA"),
        },
        resourceColumns = commonResources(),
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
        raidColumns = clone(catalog.raidColumns),
        resourceColumns = clone(catalog.resourceColumns),
    }
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
