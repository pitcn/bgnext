return function(test)
    BG = { BGNext = {}, IsRetail = false }
    dofile("Core/BGNext/ItemPrimaryStats.lua")
    dofile("Core/BGNext/EquipmentFilterProfiles.lua")
    local catalog = dofile("Core/BGNext/EquipmentFilterSpecializations.lua")

    -- Load the real equipment-filter block without executing the unrelated UI
    -- helpers in the rest of the large baseline file.
    local file = assert(io.open("Core/function2.lua", "rb"))
    local source = file:read("*a")
    file:close()
    local startMarker = "------------------过滤装备------------------"
    local stopMarker = "------------------函数：按职业排序------------------"
    local startAt = assert(source:find(startMarker, 1, true)) + #startMarker
    local stopAt = assert(source:find(stopMarker, startAt, true))

    ITEM_SOCKET_BONUS = "镶孔奖励：%s"
    ITEM_MOD_FERAL_ATTACK_POWER = "在猎豹、熊等等攻击强度提高%s点"
    ITEM_LIMIT_CATEGORY_MULTIPLE = "最多装备%s个"
    ITEM_MOD_STRENGTH_SHORT = "力量"
    ITEM_MOD_AGILITY_SHORT = "敏捷"
    ITEM_MOD_INTELLECT_SHORT = "智力"
    ITEM_MOD_MASTERY_RATING_SHORT = "精通"
    STAT_MASTERY = "精通"
    WARDROBE_SETS = "套装"
    CLASS = "职业"
    ITEM_BIND_TO_BNETACCOUNT = "战网通行证绑定"
    strfind = string.find
    tinsert = table.insert

    local tooltipText = "+10 智力"
    BiaoGeTooltip = {
        SetOwner = function() end,
        ClearLines = function() end,
        SetItemByID = function() end,
        SetHyperlink = function() end,
        NumLines = function() return 2 end,
    }
    UIParent = {}
    BiaoGeTooltipTextLeft2 = { GetText = function() return tooltipText end }

    local activeProfile
    BG.BGNext.GetActiveEquipmentFilterProfile = function() return activeProfile end
    assert(loadstring(source:sub(startAt, stopAt - 1), "equipment-filter-engine"))()

    activeProfile = catalog.getDefault("titan", "WARRIOR", "tree:WARRIOR:1")
    test.eq(BG.FilterAll(1001, 4, "INVTYPE_CHEST", 4), true,
        "non-Retail physical profile filters intellect-only armor")

    activeProfile = catalog.getDefault("titan", "MAGE", "tree:MAGE:1")
    test.eq(BG.FilterAll(1002, 4, "INVTYPE_CHEST", 1), nil,
        "non-Retail caster profile keeps intellect armor")

    activeProfile = catalog.getDefault("mop", "WARRIOR", "spec:73")
    test.eq(BG.FilterAll(1003, 4, "INVTYPE_CHEST", 4, "20 精通"), nil,
        "MoP tank profile keeps mastery armor")
    test.eq(BG.FilterAll(1004, 4, "INVTYPE_CHEST", 4, "100 护甲"), true,
        "MoP tank profile filters armor without a tank stat")

    activeProfile = catalog.getDefault("retail", "WARRIOR", "spec:73")
    test.eq(BG.FilterAll(1005, 4, "INVTYPE_CHEST", 4, "100 护甲"), nil,
        "Retail tank profile does not apply the legacy tank-stat filter")
end
