return function(test)
    BG = { BGNext = {} }
    local ui = dofile("Core/BGNext/AuctionPriceUI.lua")

    -- Fixed layout constants.
    test.eq(ui.tabNumber, 2, "price page is the second tab")
    test.eq(ui.ROW_CAPACITY, 12, "fixed reusable row capacity")

    -- Exact product labels.
    test.eq(ui.LABELS.leader, "团长起拍价", "leader label")
    test.eq(ui.LABELS.personal, "我的心理价", "personal label")

    -- Approved one-line descriptions.
    test.eq(ui.description("leader"), "用于团长开团时自动填入自定义装备起拍价，最终仍由团长确认。", "leader description")
    test.eq(ui.description("personal"), "用于参团时自动填入已保存的心理价，不会自动启用或发送。", "personal description")
    test.eq(ui.description("bogus"), nil, "unknown mode has no description")

    -- Fresh state defaults to leader.
    local state = ui.newState("ULD")
    test.eq(state.mode, "leader", "new state defaults to leader")
    test.eq(state.raidId, "ULD", "new state records raid")
    test.eq(state.filters.text, "", "new state has empty text filter")

    -- Mode switch preserves boss and search.
    ui.selectBoss(state, "boss4")
    ui.setFilter(state, "text", "饰品")
    ui.setMode(state, "personal")
    test.eq(state.mode, "personal", "mode switched")
    test.eq(state.bossId, "boss4", "mode switch preserves boss")
    test.eq(state.filters.text, "饰品", "mode switch preserves search")

    -- Filters clear back to the saved boss position.
    test.eq(state.savedBossId, "boss4", "search remembers boss")
    ui.setFilter(state, "quality", 4)
    test.eq(state.filters.quality, 4, "quality filter set")
    ui.clearFilters(state)
    test.eq(state.bossId, "boss4", "clear restores boss")
    test.eq(state.filters.text, "", "clear empties text")
    test.eq(state.filters.quality, nil, "clear empties quality")

    -- Selecting a raid resets position but keeps mode.
    ui.selectRaid(state, "ICC")
    test.eq(state.raidId, "ICC", "raid switched")
    test.eq(state.mode, "personal", "raid switch preserves mode")
    test.eq(state.bossId, nil, "raid switch resets boss")
    test.eq(state.filters.text, "", "raid switch resets filters")

    -- Reusable-row count.
    test.eq(ui.visibleRowCount(100, 12), 12, "large list reuses fixed rows")
    test.eq(ui.visibleRowCount(5, 12), 5, "small list uses only what it needs")
    test.eq(ui.visibleRowCount(0, 12), 0, "empty list needs no rows")

    -- Enter-next-visible behaviour.
    test.eq(ui.nextVisibleIndex({ "a", "b", "c" }, 1), 2, "enter moves to next")
    test.eq(ui.nextVisibleIndex({ "a", "b", "c" }, 3), 1, "enter wraps past last")
    test.eq(ui.nextVisibleIndex({ "a", "b", "c" }, nil), 1, "no focus moves to first")
    test.eq(ui.nextVisibleIndex({}, 1), nil, "empty list has no next")

    -- Toolbar actions are ordered and mode-specific.
    test.eq(ui.toolbarActions("leader")[1], "preset", "leader toolbar starts with preset chooser")
    test.eq(ui.toolbarActions("leader")[4], "new", "leader toolbar offers new scheme")
    test.eq(ui.toolbarActions("leader")[5], "copy", "leader toolbar offers copy scheme")
    test.eq(ui.toolbarActions("leader")[8], "import", "leader toolbar offers import")
    test.eq(ui.toolbarActions("personal")[1], "itemCount", "personal toolbar leads with item count")
    test.eq(ui.toolbarActions("personal")[4], "clear", "personal toolbar offers clear")
    test.eq(ui.toolbarActions("bogus"), nil, "unknown mode has no toolbar")
    test.eq(ui.toolbarActions("leader") == ui.toolbarActions("personal"), false, "modes never share a toolbar")

    -- The runtime frame hierarchy is present in source and built from the same
    -- reusable-row contract, wired to the store modules rather than to raw
    -- SavedVariables.
    local file = assert(io.open("Core/BGNext/AuctionPriceUI.lua", "rb"))
    local source = file:read("*a")
    file:close()
    for _, token in ipairs({
        "BG.PricePresetMainFrame",
        "BG.Create_TabButton(M.tabNumber",
        'L["价格预设"]',
    }) do
        test.eq(source:find(token, 1, true) ~= nil, true, "page shell builds " .. token)
    end
    for _, token in ipairs({
        "main.raidBar",
        "main.modeBar",
        "main.description",
        "main.toolbar",
        "main.bossScroll",
        "main.filterBar",
        "main.itemScroll",
        "main.rows",
    }) do
        test.eq(source:find(token, 1, true) ~= nil, true, "page shell declares " .. token)
    end
    test.eq(source:find("for i = 1, M.ROW_CAPACITY do", 1, true) ~= nil, true, "page shell reuses the fixed rows")
    for _, token in ipairs({
        "setLeaderItemPrice",
        "setPersonalPrice",
        "clearLeaderItemPrice",
        "clearPersonalPrice",
    }) do
        test.eq(source:find(token, 1, true) ~= nil, true, "page shell wires " .. token)
    end

    for _, forbidden in ipairs({
        "SendChatMessage",
        "SendAddonMessage",
        "C_ChatInfo.SendAddonMessage",
        "C_Clipboard",
        "CopyToClipboard",
        "ChatEdit_InsertLink",
        "C_Http",
        "HttpRequest",
        "telemetry",
        "Gargul",
    }) do
        test.eq(source:find(forbidden, 1, true), nil, "no " .. forbidden .. " in the page shell")
    end
end
