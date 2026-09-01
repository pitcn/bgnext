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
    test.eq(ui.description("leader"), "用于团长开团时自动填入起拍价；单件价优先，修改基础价只影响未单独设置的装备。", "leader description")
    test.eq(ui.description("personal"), "用于参团时自动填入已保存的心理价，不会自动启用或发送。", "personal description")
    test.eq(ui.description("bogus"), nil, "unknown mode has no description")

    -- Button widths are based on intrinsic text width, then clamped. Repeated
    -- refreshes therefore cannot add padding to the previous button width.
    test.eq(ui.buttonWidth(100, 14, 70, 150), 114, "button width adds padding once")
    test.eq(ui.buttonWidth(20, 14, 70, 150), 70, "button width observes its minimum")
    test.eq(ui.buttonWidth(300, 14, 70, 150), 150, "button width observes its maximum")

    -- StaticPopup changed the edit-box field casing on newer clients.
    local modernEdit = {}
    local legacyEdit = {}
    test.eq(ui.popupEditBox({ EditBox = modernEdit }), modernEdit, "modern popup EditBox is supported")
    test.eq(ui.popupEditBox({ editBox = legacyEdit }), legacyEdit, "legacy popup editBox is supported")
    test.eq(ui.popupEditBox({}), nil, "popup without an edit box fails safely")

    -- The boss picker is derived from the boss registry, not Maxb. Maxb is a
    -- ledger-layout value and can be two rows shorter than the actual loot
    -- catalog. The registry always ends with misc/fine/expense/overview.
    local registry = {}
    for i = 1, 15 do registry["boss" .. i] = { name2 = "首领" .. i } end
    registry.boss16 = { name2 = "杂项" }
    registry.boss17 = { name2 = "罚款" }
    registry.boss18 = { name2 = "支出" }
    registry.boss19 = { name2 = "总览" }
    local bosses = ui.bossDefinitions(registry)
    test.eq(#bosses, 15, "all actual bosses are retained")
    test.eq(bosses[15].id, "boss15", "last actual boss is retained")

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

    -- Import/export choices per mode. Leader schemes export by current/all scope
    -- and import as new/replace; personal expectations import as merge/replace.
    -- Any mode that overwrites saved data ("replace") requires confirmation.
    test.eq(ui.EXPORT_SCOPES.leader[1], "current", "leader export offers current scheme")
    test.eq(ui.EXPORT_SCOPES.leader[2], "all", "leader export offers all schemes")
    test.eq(ui.EXPORT_SCOPES.personal[1], nil, "personal export has no scope")
    test.eq(ui.IMPORT_MODES.leader[1], "new", "leader import offers new schemes")
    test.eq(ui.IMPORT_MODES.leader[2], "replace", "leader import offers replace")
    test.eq(ui.IMPORT_MODES.personal[1], "merge", "personal import offers merge")
    test.eq(ui.IMPORT_MODES.personal[2], "replace", "personal import offers replace")
    test.eq(ui.importRequiresConfirmation("replace"), true, "replace requires confirmation")
    test.eq(ui.importRequiresConfirmation("new"), false, "new needs no confirmation")
    test.eq(ui.importRequiresConfirmation("merge"), false, "merge needs no confirmation")

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
    test.eq(source:find("BG.TabButtonsFB:Hide()", 1, true) ~= nil, true, "price page hides the global raid navigation")
    test.eq(source:find("BG.TabButtonsFB:Show()", 1, true) ~= nil, true, "price page restores the global raid navigation")
    for _, token in ipairs({
        "setLeaderItemPrice",
        "setPersonalPrice",
        "clearLeaderItemPrice",
        "clearPersonalPrice",
    }) do
        test.eq(source:find(token, 1, true) ~= nil, true, "page shell wires " .. token)
    end
    for _, token in ipairs({
        "AuctionPriceCodec",
        "Codec.parse",
        "Codec.exportLeader",
        "Codec.exportPersonal",
        "Codec.applyLeader",
        "Codec.applyPersonal",
        "HighlightText",
        "panel.preview",
        "preview.unknownItems",
        "panel.commit",
    }) do
        test.eq(source:find(token, 1, true) ~= nil, true, "import/export panel wires " .. token)
    end

    for _, forbidden in ipairs({
        "SetClipboard",
        "SendChatMessage",
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
