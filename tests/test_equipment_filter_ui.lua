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
    local profileButtonStart = assert(source:find("local function createProfileButton", 1, true))
    local profileButtonEnd = assert(source:find("local function updateProfileRows", profileButtonStart, true))
    local profileButtonSource = source:sub(profileButtonStart, profileButtonEnd - 1)
    test.eq(profileButtonSource:find('icon:SetAllPoints()', 1, true) ~= nil, true,
        "shortcut profile icon uses the original 25x25 button bounds")
    test.eq(profileButtonSource:find('selected:SetSize(40, 40)', 1, true) ~= nil, true,
        "shortcut selection glow retains the original 40x40 size")
    test.eq(profileButtonSource:find('Interface/ChatFrame/UI-ChatIcon-BlinkHilight', 1, true) ~= nil, true,
        "shortcut selection glow retains the original texture")
    test.eq(source:find('button.icon:SetDesaturated(not selected)', 1, true) ~= nil, true,
        "inactive shortcut icons retain the original desaturated state")
    test.eq(source:find("#current.order * 35 - 10", 1, true), nil,
        "shortcut container preserves trailing spacing before settings")
    test.eq(source:find("main:SetSize(560, 700)", 1, true) ~= nil, true,
        "settings backdrop contains every rule section")
    test.eq(source:find("main:SetBackdropColor(0, 0, 0, 1)", 1, true) ~= nil, true,
        "settings backdrop is opaque over the bill")

    local toc = assert(io.open("BGLite.toc", "rb"))
    local tocSource = toc:read("*a")
    toc:close()
    test.eq(tocSource:find("Core\\BGNext\\EquipmentFilterUI.lua", 1, true) ~= nil, true,
        "equipment filter UI loads after the main frame")
end
