return function(test)
    local file = io.open("Core/BGNext/EquipmentFilterUI.lua", "rb")
    test.eq(file ~= nil, true, "equipment filter UI module exists")
    if not file then return end
    local source = file:read("*a")
    file:close()

    test.eq(source:find("BG.FilterClassItemUI =", 1, true) ~= nil, true,
        "BGNext replaces the deleted BGLite UI stub")
    test.eq(source:find('L["< 装备过滤 >"]', 1, true) ~= nil, true, "original title retained")
    test.eq(source:find('L["选择方案："]', 1, true) ~= nil, true, "profile chooser retained")
    test.eq(source:find("BOTTOMLEFT", 1, true) ~= nil, true, "bottom shortcut placement retained")
    for _, key in ipairs({ "weapon", "armor", "affix", "classRestriction", "ignoreBattleNetBound", "tankOnly", "primaryStat" }) do
        test.eq(source:find(key, 1, true) ~= nil, true, "UI exposes rule section " .. key)
    end
    for _, forbidden in ipairs({ "SendChatMessage", "C_ChatInfo.SendAddonMessage", "BiaoGe.FilterClassItemDB" }) do
        test.eq(source:find(forbidden, 1, true), nil, "UI excludes " .. forbidden)
    end
    test.eq(source:find("LibBG:EasyMenu", 1, true) ~= nil, true, "right-click profile menu retained")
    test.eq(source:find("moveProfile", 1, true) ~= nil, true, "profile reorder action retained")
    test.eq(source:find("deleteProfile", 1, true) ~= nil, true, "profile delete action retained")
    test.eq(source:find("IconButtons", 1, true) ~= nil, true, "profile icon chooser retained")

    local toc = assert(io.open("BGLite.toc", "rb"))
    local tocSource = toc:read("*a")
    toc:close()
    test.eq(tocSource:find("Core\\BGNext\\EquipmentFilterUI.lua", 1, true) ~= nil, true,
        "equipment filter UI loads after the main frame")
end
