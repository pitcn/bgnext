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

local function raid(id, zoneId, title, variant, instanceIds)
    local ids = instanceIds
    if type(ids) ~= "table" then
        ids = type(zoneId) == "number" and { zoneId } or {}
    end
    return {
        id = id,
        section = "raid",
        title = title,
        zoneId = #ids == 1 and zoneId or nil,
        variant = variant,
        kind = "status",
        width = "narrow",
        defaultVisible = true,
        total = false,
        source = {
            kind = "raid",
            key = id,
            instanceIds = ids,
            readable = #ids > 0,
        },
    }
end

local function resource(id, title, kind, width, total, source)
    return {
        id = id,
        section = "resource",
        title = title,
        kind = kind,
        width = width,
        defaultVisible = true,
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
            raid("MCtitan", 409, "熔火之心", nil, { 409 }),
            raid("SSCtitan", 548, "毒蛇风暴", nil, { 548, 550 }),
            raid("NAXXtitan", 533, "纳克萨玛斯", nil, { 533, 615, 616 }),
            raid("TOCtitan", 309, "P4双本", nil, { 309, 649 }),
            raid("SWtitan", 568, "P5双本", nil, { 568, 580 }),
            raid("ULDtitan", 603, "奥杜尔", nil, { 603 }),
            raid("Worldtitan", nil, "世界Boss"),
        },
        resourceColumns = commonResources({
            resource("titanShard", "泰坦碎片", "number", "narrow", true, { kind = "currency", key = "titanShard" }),
            resource("emblem", "徽章", "number", "narrow", true, { kind = "currency", key = "emblem" }),
        }),
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
