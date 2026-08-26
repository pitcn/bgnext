return function(test)
    BG = { BGNext = {} }
    dofile("Core/BGNext/Wishlist.lua")
    local ui = dofile("Core/BGNext/WishlistUI.lua")

    test.eq(ui.tabNumber, 3, "wishlist uses original third tab")
    test.eq(ui.nextCell(1, 1, 1, "RIGHT", 4, 3, 2, false).slotIndex, 2, "right moves one slot")
    test.eq(ui.nextCell(1, 1, 2, "RIGHT", 4, 3, 2, false).difficultyIndex, 2,
        "right edge moves to paired difficulty")
    test.eq(ui.nextCell(2, 1, 1, "LEFT", 4, 3, 2, false).difficultyIndex, 1,
        "left edge moves to paired difficulty")
    test.eq(ui.nextCell(3, 3, 1, "DOWN", 4, 3, 2, false).difficultyIndex, 1,
        "down edge returns from lower-left difficulty")
    test.eq(ui.nextCell(4, 1, 1, "UP", 4, 3, 2, false).difficultyIndex, 2,
        "up edge returns from lower-right difficulty")
    test.eq(ui.nextCell(1, 2, 1, "DOWN", 4, 3, 2, true).difficultyIndex, 3,
        "modified vertical arrow changes difficulty row")
    test.eq(ui.nextCell(1, 2, 1, "RIGHT", 4, 3, 2, true).difficultyIndex, 2,
        "modified horizontal arrow changes difficulty column")
    test.eq(ui.nextCell(1, 3, 2, "TAB", 4, 3, 2, false).difficultyIndex, 3,
        "tab follows original difficulty order after last boss")
    test.eq(ui.nextCell(4, 3, 2, "TAB", 4, 3, 2, false), nil,
        "tab stops after original final difficulty")

    test.eq(ui.shortcutAction(false, "LeftButton", true), "wishlist", "member alt-left sets wishlist")
    test.eq(ui.shortcutAction(true, "LeftButton", true), "wishlist", "master looter alt-left sets wishlist")
    test.eq(ui.shortcutAction(true, "RightButton", true), "auction", "master looter alt-right starts auction")
    test.eq(ui.shortcutAction(false, "RightButton", true), nil, "member alt-right has no privileged action")
    test.eq(ui.shortcutAction(false, "LeftButton", false), nil, "no modifier does not set wishlist")

    local file = assert(io.open("Core/BGNext/WishlistUI.lua", "rb"))
    local source = file:read("*a")
    file:close()
    for _, forbidden in ipairs({
        "个人心愿清单",
        "输入物品 ID",
        "已记录 %d 件装备",
        "SendChatMessage",
        "SendAddonMessage",
        "通报心愿",
        "查询心愿竞争",
    }) do
        test.eq(source:find(forbidden, 1, true), nil, "forbidden simplified or communicating UI absent: " .. forbidden)
    end
    for _, required in ipairs({
        "local function showImportPanel",
        "local function showExportPanel",
        "local function confirmClearRaid",
        "wishlist.parseImport",
        "wishlist.applyImport",
        "wishlist.exportRaid",
        "BG.ButtonImportHope",
        "BG.ButtonExportHope",
    }) do
        test.eq(source:find(required, 1, true) ~= nil, true, "original control contract present: " .. required)
    end
    for _, forbiddenApi in ipairs({ "C_Clipboard", "CopyToClipboard", "ChatEdit_InsertLink" }) do
        test.eq(source:find(forbiddenApi, 1, true), nil, "no automatic clipboard or chat export: " .. forbiddenApi)
    end

    local mainFile = assert(io.open("Core/BiaoGe.lua", "rb"))
    local mainSource = mainFile:read("*a")
    mainFile:close()
    test.eq(mainSource:find("shortcutAction(BG.IsML, button, true)", 1, true) ~= nil, true,
        "alt-click call site passes the explicit modifier state")
end
