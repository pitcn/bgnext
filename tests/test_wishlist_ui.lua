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
    test.eq(ui.shortcutAction(true, "RightButton", false, true, false), "leader-price",
        "ctrl-right edits the saved leader price")
    test.eq(ui.shortcutAction(false, "RightButton", false, true, false), nil,
        "member ctrl-right cannot edit the leader price")
    test.eq(ui.shortcutAction(true, "RightButton", true, true, false), "auction",
        "alt-right keeps priority over ctrl-right")
    test.eq(ui.shortcutAction(true, "RightButton", false, true, true), nil,
        "shift combinations are left to existing table actions")
    test.eq(ui.isLooted(7001, { 7002, 7001 }), true, "recorded current-raid item shows looted marker")
    test.eq(ui.isLooted(7001, { 7002 }), false, "unrecorded item hides looted marker")

    -- Three difficulties (retail N/H/M) stack vertically: no block opens a
    -- second column, so Mythic no longer drifts off-screen to the right.
    local d1 = ui.difficultyAnchor(1, 3)
    test.eq(d1.relative, "main", "first difficulty anchors to the main frame")
    test.eq(d1.point, "TOPLEFT", "first difficulty uses its top-left corner")
    local d2 = ui.difficultyAnchor(2, 3)
    test.eq(d2.point, "TOPRIGHT", "second difficulty hangs below the first block")
    test.eq(d2.relative.anchor, "bottomFirst", "second difficulty anchors to the first block's bottom")
    test.eq(d2.relative.index, 1, "second difficulty references the first block")
    local d3 = ui.difficultyAnchor(3, 3)
    test.eq(d3.relative.anchor, "bottomFirst", "third difficulty stays in the same column")
    test.eq(d3.relative.index, 2, "third difficulty stacks below the second block")
    test.eq(d3.point, "TOPRIGHT", "three difficulties never open a second column")

    -- One and two difficulties keep their existing positions.
    test.eq(ui.difficultyAnchor(1, 1).relative, "main", "single difficulty anchors to the main frame")
    test.eq(ui.difficultyAnchor(1, 2).relative, "main", "first of two difficulties anchors to the main frame")
    test.eq(ui.difficultyAnchor(2, 2).relative.anchor, "bottomFirst", "second of two difficulties stacks below")
    test.eq(ui.difficultyAnchor(2, 2).relative.index, 1, "second of two references the first block")

    -- Four difficulties keep the original 2x2 grid without overlap.
    local f1, f2, f3, f4 = ui.difficultyAnchor(1, 4), ui.difficultyAnchor(2, 4),
        ui.difficultyAnchor(3, 4), ui.difficultyAnchor(4, 4)
    test.eq(f1.relative, "main", "first of four anchors to the main frame")
    test.eq(f2.relative.anchor, "bottomFirst", "second of four stacks below the first")
    test.eq(f2.relative.index, 1, "second of four references the first block")
    test.eq(f3.relative.anchor, "headerLast", "third of four moves to the right of the second")
    test.eq(f3.relative.index, 1, "third of four aligns with the top row, not the second block")
    test.eq(f4.relative.anchor, "bottomFirst", "fourth of four stacks below the third")
    test.eq(f4.relative.index, 3, "fourth of four references the third block")
    test.eq(ui.difficultyAnchor(5, 4), nil, "no block is placed beyond the declared difficulties")

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
        "wishlist.migrateFlatRaid",
        "BG.ButtonImportHope",
        "BG.ButtonExportHope",
    }) do
        test.eq(source:find(required, 1, true) ~= nil, true, "original control contract present: " .. required)
    end
    for _, forbiddenApi in ipairs({ "C_Clipboard", "CopyToClipboard", "ChatEdit_InsertLink" }) do
        test.eq(source:find(forbiddenApi, 1, true), nil, "no automatic clipboard or chat export: " .. forbiddenApi)
    end
    test.eq(source:find("and BG.MainFrame and BG.Create_TabButton", 1, true), nil,
        "wishlist registration does not require frames before ADDON_LOADED")
    test.eq(source:find("and BG.BGNext.DB", 1, true), nil,
        "wishlist registration does not require SavedVariables before ADDON_LOADED")
    test.eq(source:find("if not BG.MainFrame or not BG.Create_TabButton or not BG.BGNext.DB then return end", 1, true) ~= nil, true,
        "wishlist callback validates frames and SavedVariables after ADDON_LOADED")
    test.eq(source:find("BG.AddHText(slot.FB, link, itemId, slot)", 1, true) ~= nil, true,
        "hard-mode decoration receives the raid identifier")
    test.eq(source:find("BG.lastfocuszhuangbei2 = nextSlot", 1, true) ~= nil, true,
        "item picker advances to the next slot like the original workflow")

    local mainFile = assert(io.open("Core/BiaoGe.lua", "rb"))
    local mainSource = mainFile:read("*a")
    mainFile:close()
    test.eq(mainSource:find("shortcutAction(BG.IsML, button, true)", 1, true) ~= nil, true,
        "alt-click call site passes the explicit modifier state")

    local billFile = assert(io.open("Core/FBUI/FBUIfunction.lua", "rb"))
    local billSource = billFile:read("*a")
    billFile:close()
    test.eq(billSource:find("shortcutAction(BG.IsML, button, true)", 1, true) ~= nil, true,
        "bill-table alt-click call site passes the explicit modifier state")
    test.eq(billSource:find('shortcut == "leader-price"', 1, true) ~= nil, true,
        "bill table routes ctrl-right to the leader-price editor")
end
