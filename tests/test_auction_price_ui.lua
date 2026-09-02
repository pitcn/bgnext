return function(test)
    BG = { BGNext = {} }
    BG.BGNext.UITheme = dofile("Core/BGNext/UITheme.lua")
    local Style = dofile("Core/BGNext/UIStyle.lua")
    local ui = dofile("Core/BGNext/AuctionPriceUI.lua")

    -- Responsive two-column layout constants.
    test.eq(ui.tabNumber, 2, "price page is the second tab")
    test.eq(ui.COLUMN_COUNT, 2, "price items use two columns")
    test.eq(ui.ITEM_FONT_SIZE, 13, "price item names remain readable")
    test.eq(ui.PRICE_FONT_SIZE, 13, "price values remain readable")
    test.eq(ui.MIN_ROWS_PER_COLUMN, 12, "short windows retain twelve rows per column")
    test.eq(ui.MAX_ROWS_PER_COLUMN, 30, "row objects stay capped per column")
    test.eq(ui.ROW_CAPACITY, 60, "maximum reusable row capacity")
    test.eq((tonumber(ui.DECORATIVE_REGION_COUNT) or math.huge) <= Style.objectBudget(), true,
        "price decoration stays within the fixed object budget")

    local largeLayout = ui.viewportLayout(1900, 1400)
    test.eq(largeLayout.columns, 2, "large layout keeps two columns")
    test.eq(largeLayout.rowsPerColumn, 30, "large layout observes row cap")
    test.eq(largeLayout.capacity, 60, "large layout exposes sixty reusable rows")
    test.eq(largeLayout.columnWidth > 500, true, "large layout fills horizontal space")

    local standardLayout = ui.viewportLayout(1280, 800)
    test.eq(standardLayout.rowsPerColumn, 25, "standard layout derives rows from height")
    test.eq(standardLayout.capacity, 50, "standard layout exposes both columns")

    local fallbackLayout = ui.viewportLayout(nil, nil)
    test.eq(fallbackLayout.rowsPerColumn, 12, "invalid height uses safe minimum")
    test.eq(fallbackLayout.capacity, 24, "fallback still uses two columns")
    test.eq(fallbackLayout.columnWidth, 320, "invalid width uses safe column width")

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
    test.eq(ui.bossCountLabel("艾瑞达双子", 27), "艾瑞达双子（27件）", "boss count is labelled as item count")
    test.eq(ui.itemTooltipLink(34393), "item:34393", "tooltip uses a stable item hyperlink")
    test.eq(ui.itemTooltipLink(nil), nil, "missing item has no tooltip link")

    local text, canClear, role = ui.priceDisplay("leader", nil, 2000)
    test.eq(text, "2000 G", "inherited leader price is compact")
    test.eq(canClear, false, "inherited leader price has nothing to clear")
    test.eq(role, "secondary", "inherited leader price is visually secondary")
    text, canClear, role = ui.priceDisplay("leader", 3500, 2000)
    test.eq(text, "3500 G", "explicit leader price is compact")
    test.eq(canClear, true, "explicit leader price can be cleared")
    test.eq(role, "primary", "explicit leader price is visually primary")
    text, canClear, role = ui.priceDisplay("personal", nil, 2000)
    test.eq(text, "—", "unset personal price is a quiet placeholder")
    test.eq(canClear, false, "unset personal price has nothing to clear")
    test.eq(role, "secondary", "unset personal price is visually secondary")
    text, canClear, role = ui.priceDisplay("personal", 800, 2000)
    test.eq(text, "800 G", "explicit personal price is compact")
    test.eq(canClear, true, "explicit personal price can be cleared")
    test.eq(role, "primary", "explicit personal price is visually primary")

    -- Fresh state defaults to leader.
    local state = ui.newState("ULD")
    test.eq(state.mode, "leader", "new state defaults to leader")
    test.eq(state.raidId, "ULD", "new state records raid")
    test.eq(state.filters.text, "", "new state has empty text filter")
    test.eq(state.itemOffset, 0, "new state starts at the first item")

    -- Mode switch preserves boss and search.
    ui.selectBoss(state, "boss4")
    ui.setFilter(state, "text", "饰品")
    state.itemOffset = 7
    ui.setFilter(state, "quality", 4)
    test.eq(state.itemOffset, 0, "changing filters returns to the first item")
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

    -- A fixed twelve-row viewport must still expose every item through a
    -- clamped zero-based scroll offset.
    local many = {}
    for i = 1, 20 do many[i] = "item" .. i end
    local first, firstOffset, maxOffset = ui.visibleWindow(many, 0, 12)
    test.eq(#first, 12, "first viewport has twelve rows")
    test.eq(first[1], "item1", "first viewport starts at item one")
    test.eq(maxOffset, 8, "twenty items have eight scroll steps")
    local last, lastOffset = ui.visibleWindow(many, 99, 12)
    test.eq(lastOffset, 8, "oversized scroll offset is clamped")
    test.eq(last[1], "item9", "last viewport begins at item nine")
    test.eq(last[12], "item20", "last item is reachable")

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
        "main.itemSlider",
        "main.rows",
    }) do
        test.eq(source:find(token, 1, true) ~= nil, true, "page shell declares " .. token)
    end
    test.eq(source:find("UIPanelScrollBarTemplate", 1, true), nil,
        "price page does not use the ScrollFrame-only scrollbar template")
    test.eq(source:find('CreateFrame("Slider", nil, main)', 1, true) ~= nil, true,
        "price page uses a plain compatible slider")
    test.eq(source:find("local pageCapacity = layout.capacity", 1, true) ~= nil, true,
        "runtime uses the responsive capacity")
    test.eq(source:find("for i = 1, pageCapacity do", 1, true) ~= nil, true,
        "page shell creates only the computed reusable rows")
    test.eq(source:find("math.floor((i - 1) / layout.rowsPerColumn)", 1, true) ~= nil, true,
        "rows flow into a second column")
    test.eq(source:find('main.bossScroll = CreateFrame("Frame", nil, main, "BackdropTemplate")', 1, true) ~= nil, true,
        "boss navigation uses a scoped surface")
    test.eq(source:find('main.itemScroll = CreateFrame("Frame", nil, main, "BackdropTemplate")', 1, true) ~= nil, true,
        "item columns use a scoped surface")
    test.eq(source:find("main.columnDivider", 1, true) ~= nil, true,
        "price page has one column divider")
    test.eq(source:find('Style.setButtonState(bt, "selected"', 1, true) ~= nil, true,
        "selected price navigation uses the brand state")
    test.eq(source:find('Style.setButtonState(bt, selected and "listSelected" or "listNormal"', 1, true) ~= nil, true,
        "boss picker uses quiet semantic list states")
    local raidRefresh = source:match("function refreshRaidBar%(%)%s*(.-)%s*function refreshModeBar") or ""
    local bossRefresh = source:match("function refreshBossBar%(%)%s*(.-)%s*function refreshFilterBar") or ""
    test.eq(raidRefresh:find("applySelection(bt, selected)", 1, true) ~= nil, true,
        "raid navigation keeps the ordinary selected-tab treatment")
    test.eq(bossRefresh:find("applyBossSelection(bt, selected)", 1, true) ~= nil, true,
        "boss navigation alone uses the quiet list treatment")
    test.eq(source:find("row.clear:SetShown(canClear)", 1, true) ~= nil, true,
        "clear action appears only for explicit item prices")
    test.eq(source:find('main.itemScroll:SetScript("OnMouseWheel"', 1, true) ~= nil, true, "long item lists are mouse-wheel scrollable")
    test.eq(source:find("GameTooltip:SetHyperlink(link)", 1, true) ~= nil, true, "item rows show the native item tooltip")
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
