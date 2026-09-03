return function(test)
    BG = { BGNext = {} }
    dofile("Core/BGNext/OwnCharactersAdapters.lua")
    local Catalog = dofile("Core/BGNext/OwnCharactersCatalog.lua")
    local View = dofile("Core/BGNext/OwnCharactersView.lua")
    local UI = dofile("Core/BGNext/OwnCharactersUI.lua")

    local function snapshot(overrides)
        local base = {
            realmId = 123, realmName = "时光II", player = "Piti",
            class = "HUNTER", level = 80, itemLevel = 230.75,
            money = 12340000, updatedAt = 1000,
            raidStates = { MCtitan = { completed = true, resetsAt = 9000 } },
            currencies = {}, items = {},
            equipment = { [1] = { itemId = 1234, itemLevel = 226 } },
            professions = {},
        }
        for key, value in pairs(overrides or {}) do base[key] = value end
        return base
    end

    local projection = View.project({
        family = "titan",
        catalog = Catalog.forFamily("titan"),
        snapshots = {
            snapshot({ player = "Aaa" }), snapshot({ player = "Bbb" }), snapshot({ player = "Ccc" }),
        },
        currentRealmId = 123,
        now = 1000,
        visibility = {},
    })

    -- The renderer lays out a projection it is handed; it never reads storage.
    local layout = UI.layout(projection)
    test.eq(type(layout), "table", "layout is computed from a projection")
    test.eq(UI.layout(nil), nil, "missing projection is safe")
    test.eq(UI.layout({}), nil, "malformed projection is safe")

    -- Dynamic size comes from the projection, not from a fixed window size.
    test.eq(layout.width, projection.width, "width follows the projection")
    test.eq(layout.height, projection.height, "height follows the projection")

    -- Two stacked sections in the approved order.
    test.eq(#layout.sections, 2, "exactly two sections")
    test.eq(layout.sections[1].key, "raid", "raid section comes first")
    test.eq(layout.sections[2].key, "resource", "resource section comes second")
    test.eq(layout.sections[1].title, "< 角色团本完成总览 >", "raid section keeps its title")
    test.eq(layout.sections[2].title, "< 角色货币总览 >", "resource section keeps its title")
    test.eq(type(layout.sections[1].hint), "string", "raid hint is laid out")
    test.eq(type(layout.sections[2].hint), "string", "resource hint is laid out")

    -- Characters are rows: one row per character, stacked vertically.
    local raid = layout.sections[1]
    test.eq(#raid.rows, 3, "one row per character")
    test.eq(raid.rows[1].key, projection.raid.rows[1].key, "rows keep projection identity")
    test.eq(raid.rows[2].y < raid.rows[1].y, true, "rows stack downwards")
    test.eq(raid.rows[1].y - raid.rows[2].y, UI.metrics.rowHeight, "rows are one row-height apart")
    test.eq(raid.rows[2].y - raid.rows[3].y, UI.metrics.rowHeight, "row spacing is uniform")
    test.eq(UI.rowCenterY(raid.rows[1].y), raid.rows[1].y - UI.metrics.rowHeight / 2,
        "row content is vertically centred inside the stripe")

    local titleRegion = { width = 120, naturalWidth = 168 }
    function titleRegion:SetWidth(value) self.width = value end
    function titleRegion:SetText(value) self.text = value end
    function titleRegion:GetStringWidth() return math.min(self.width, self.naturalWidth) end
    test.eq(UI.fitTextWidth(titleRegion, "< 角色团本完成总览 >", 600), 168,
        "title measurement first removes a pooled narrow-width constraint")
    test.eq(titleRegion.width, 168, "title region is resized to its full measured width")

    -- Categories are columns: laid out horizontally in projected order.
    test.eq(#raid.columns, #projection.raid.columns, "every visible column is laid out")
    for index, column in ipairs(raid.columns) do
        test.eq(column.id, projection.raid.columns[index].id, "column order follows the projection")
    end
    for index = 2, #raid.columns do
        test.eq(raid.columns[index].x > raid.columns[index - 1].x, true, "columns advance to the right")
    end
    test.eq(raid.columns[1].x >= UI.metrics.nameColumnWidth, true, "columns start after the name column")
    test.eq(raid.columns[1].width > 0, true, "columns have a width")

    -- The resource section carries the totals row below the last character.
    local resource = layout.sections[2]
    test.eq(type(resource.totalsY), "number", "resource section has a totals row")
    test.eq(resource.totalsY < resource.rows[#resource.rows].y, true, "totals sit below the last character")
    test.eq(raid.totalsY, nil, "the raid section has no totals row")

    -- Alternating black/grey rows.
    test.eq(raid.rows[1].stripe, "dark", "first row is dark")
    test.eq(raid.rows[2].stripe, "light", "second row is light")
    test.eq(raid.rows[3].stripe, "dark", "third row is dark")
    test.eq(type(UI.colors.stripeDark), "table", "dark stripe colour exists")
    test.eq(type(UI.colors.stripeLight), "table", "light stripe colour exists")
    local dark, light = UI.colors.stripeDark, UI.colors.stripeLight
    test.eq(dark.r ~= light.r or dark.g ~= light.g or dark.b ~= light.b or dark.a ~= light.a, true,
        "the two stripes actually differ")

    -- Completion stays semantic green; section titles use brand cyan and hints
    -- use the same blue-grey hierarchy as the rest of the modern UI.
    local complete = UI.colors.complete
    test.eq(complete.g > complete.r and complete.g > complete.b, true, "completion marker is green")
    local title = UI.colors.title
    test.eq(title.g > title.r and title.b > title.r, true, "section titles are cyan")
    local hint = UI.colors.hint
    test.eq(hint.b > hint.r and hint.g > hint.r, true, "hints are blue grey")
    local header = UI.colors.header
    test.eq(header.r == header.g and header.g == header.b, true, "column headings are neutral")

    -- Equipment icons use the documented 19px content size.
    test.eq(UI.metrics.iconSize, 19, "item icons are 19px")
    test.eq(UI.metrics.iconSize, View.metrics.iconSize, "renderer and projection share one icon size")
    test.eq(UI.metrics.rowHeight, View.metrics.rowHeight, "renderer and projection share one row height")
    test.eq(UI.metrics.nameColumnWidth, View.metrics.nameColumnWidth, "renderer shares the name column width")

    -- The difficulty abbreviation sits in the remaining column width after the
    -- completion checkmark, so a three-character "LFR" is never clipped into the
    -- old single-letter 8px column gap.
    local lfrLabelWidth = UI.difficultyLabelWidth(UI.metrics.columnWidths.narrow)
    test.eq(type(lfrLabelWidth), "number", "the difficulty label width is numeric")
    test.eq(lfrLabelWidth, UI.metrics.columnWidths.narrow - UI.metrics.iconSize - 2,
        "the label takes the full column width after the checkmark")
    test.eq(lfrLabelWidth > UI.metrics.columnGap, true, "the label region is wider than the old 8px column gap")
    local lfrRegion = { width = 0, naturalWidth = 3 * 7 }
    function lfrRegion:SetWidth(value) self.width = value end
    function lfrRegion:SetText(value) self.text = value end
    function lfrRegion:GetStringWidth() return math.min(self.width, self.naturalWidth) end
    local lfrMeasured = UI.fitTextWidth(lfrRegion, "LFR", lfrLabelWidth)
    test.eq(lfrMeasured, lfrRegion.naturalWidth, "LFR measures its full width without clipping")
    test.eq(lfrMeasured <= lfrLabelWidth, true, "LFR fits inside the label region")

    -- Class colouring is looked up per row, not stored per character.
    test.eq(type(UI.classColor("HUNTER")), "table", "class colour resolves")
    test.eq(type(UI.classColor("NOPE")), "table", "unknown class falls back safely")
    local hunter = UI.classColor("HUNTER")
    test.eq(type(hunter.r) == "number" and type(hunter.g) == "number" and type(hunter.b) == "number", true,
        "class colour has rgb components")

    -- Item tooltips prefer the collected link and fall back to the item id.
    local byLink = UI.tooltipTarget({ itemId = 123, link = "|cffffffff|Hitem:123|h|r" })
    test.eq(type(byLink), "table", "tooltipTarget resolves a link")
    test.eq(byLink.kind, "link", "a collected link is preferred")
    test.eq(byLink.value, "|cffffffff|Hitem:123|h|r", "the link is the tooltip source")
    local byId = UI.tooltipTarget({ itemId = 123 })
    test.eq(byId.kind, "item", "item id is the fallback")
    test.eq(byId.value, 123, "the item id is the tooltip source")
    test.eq(UI.tooltipTarget({}), nil, "no item means no tooltip")
    test.eq(UI.tooltipTarget(nil), nil, "a missing item means no tooltip")
    test.eq(UI.tooltipTarget({ itemId = 0 }), nil, "a zero item id means no tooltip")

    local tooltipCalls = {}
    local fakeTooltip = {
        SetHyperlink = function(_, value) tooltipCalls[#tooltipCalls + 1] = { "link", value } end,
        SetItemByID = function(_, value) tooltipCalls[#tooltipCalls + 1] = { "id", value } end,
    }
    test.eq(UI.showItemTooltip(fakeTooltip, { link = "|Hitem:123|h[Test]|h" }), true,
        "a collected item link can populate the Blizzard tooltip")
    test.eq(tooltipCalls[#tooltipCalls][1], "link", "links use SetHyperlink")
    test.eq(UI.showItemTooltip(fakeTooltip, { itemId = 456 }), true,
        "an item id can populate clients that expose SetItemByID")
    test.eq(tooltipCalls[#tooltipCalls][1], "id", "supported clients use SetItemByID")
    local hyperlinkOnly = {
        SetHyperlink = function(_, value) tooltipCalls[#tooltipCalls + 1] = { "fallback", value } end,
    }
    test.eq(UI.showItemTooltip(hyperlinkOnly, { itemId = 789 }), true,
        "older clients fall back to an item hyperlink")
    test.eq(tooltipCalls[#tooltipCalls][2], "item:789", "fallback hyperlink contains the item id")

    test.eq(UI.rowLabel("raid", { display = "Piti", itemLevel = 230.75 }), "Piti (230)",
        "raid rows use the original parenthesized item level")
    test.eq(UI.rowLabel("resource", { display = "Piti", level = 80 }), "Piti (80)",
        "resource rows use the original parenthesized level")
    local cyan = UI.hexColor("00BFFF")
    test.eq(cyan.r, 0, "hex color parses red")
    test.eq(cyan.g > 0.7, true, "hex color parses green")
    test.eq(cyan.b, 1, "hex color parses blue")

    -- Catalog titles are authoritative: raid IDs never expand back to long
    -- localized zone names, while selected currencies add their game icon.
    local raidHeader = UI.columnHeader({ title = "SW", fullTitle = "太阳之井高地", zoneId = 580 })
    test.eq(raidHeader.text, "SW",
        "compact raid title is not replaced by GetRealZoneText")
    test.eq(raidHeader.tooltip, "太阳之井高地", "compact raid heading exposes the full raid name")
    test.eq(Catalog.column("titan", "raid", "SWtitan").fullTitle, "太阳之井高地",
        "the Titan catalog carries the full raid tooltip name")
    local currencyHeader = UI.columnHeader({
        title = "余烬",
        source = { kind = "currency", currencyId = 3403, showHeaderIcon = true },
    }, function(id)
        test.eq(id, 3403, "currency header resolves the declared currency id")
        return { name = "泰坦余烬", iconFileID = 123456 }
    end)
    test.eq(currencyHeader.text, "|T123456:20:20|t", "currency heading uses a readable icon-only size")
    test.eq(currencyHeader.tooltip, "泰坦余烬", "currency tooltip uses its official full name")
    local plainHeader = UI.columnHeader({
        title = "荣誉", source = { kind = "currency", currencyId = 1901 },
    }, function() return { name = "荣誉点数", iconFileID = 999 } end)
    test.eq(plainHeader.text, "荣誉", "icons remain opt-in per heading")
    test.eq(plainHeader.tooltip, "荣誉", "plain heading retains its catalog tooltip")
    local fallbackHeader = UI.columnHeader({
        title = "余烬", source = { kind = "currency", currencyId = 3403, showHeaderIcon = true },
    }, function() return nil end)
    test.eq(fallbackHeader.text, "余烬", "missing currency data falls back to the catalog title")
    test.eq(fallbackHeader.tooltip, "余烬", "missing currency data has a safe tooltip")

    -- A currency value cell builds a tooltip from its confirmed id: the name is
    -- Blizzard's own localized name, and each cap line appears only when the
    -- API actually returned it. Missing fields stay hidden, never a fake zero.
    local fullCapCell = {
        value = 1000, maxQuantity = 3000,
        quantityEarnedThisWeek = 400, maxWeeklyQuantity = 1000,
        currencyId = 396,
    }
    local fullTip = UI.currencyTooltip(fullCapCell, function(id)
        test.eq(id, 396, "currency tooltip resolves the confirmed cell id")
        return { name = "勇气点数" }
    end)
    test.eq(fullTip.name, "勇气点数", "tooltip uses Blizzard's localized currency name")
    test.eq(fullTip.lines[1], "当前数量 1000", "tooltip shows the current quantity")
    test.eq(fullTip.lines[2], "总上限 3000", "tooltip shows the total cap")
    test.eq(fullTip.lines[3], "本周获得 400", "tooltip shows weekly earnings")
    test.eq(fullTip.lines[4], "每周上限 1000", "tooltip shows the weekly cap")
    local noWeeklyCap = UI.currencyTooltip({
        currencyId = 396, value = 40, maxQuantity = 6400,
        quantityEarnedThisWeek = 560, maxWeeklyQuantity = 0,
    }, function() return { name = "勇气点数" } end)
    test.eq(#noWeeklyCap.lines, 3, "a placeholder weekly cap of zero is hidden")

    local quantityOnly = UI.currencyTooltip({ value = 42, currencyId = 396 },
        function() return { name = "勇气点数" } end)
    test.eq(quantityOnly.lines[1], "当前数量 42", "a quantity-only cell still shows its quantity")
    test.eq(#quantityOnly.lines, 1, "missing caps are not shown as extra lines")

    local missingName = UI.currencyTooltip({ value = 5, currencyId = 396 }, function() return nil end)
    test.eq(missingName.name, nil, "a missing API name stays nil")
    test.eq(#missingName.lines, 1, "only the quantity line survives without a name")

    test.eq(UI.currencyTooltip({ value = 5 }, function() return { name = "x" } end), nil,
        "a cell without a confirmed id has no currency tooltip")

    -- showCurrencyTooltip writes the name once then appends each present line.
    local currencyTooltipTitle, currencyTooltipLines = nil, {}
    local fakeCurrencyTooltip = {
        SetText = function(_, value) currencyTooltipTitle = value end,
        AddLine = function(_, value) currencyTooltipLines[#currencyTooltipLines + 1] = value end,
    }
    test.eq(UI.showCurrencyTooltip(fakeCurrencyTooltip, fullCapCell, function()
        return { name = "勇气点数" }
    end), true, "a currency cell can populate the Blizzard tooltip")
    test.eq(currencyTooltipTitle, "勇气点数", "the tooltip title is the currency name")
    test.eq(#currencyTooltipLines, 4, "all four field lines reach the tooltip")
    test.eq(UI.showCurrencyTooltip({ SetText = function() end }, { value = 5 }, function() return nil end),
        false, "a cell without an id cannot populate a tooltip")

    -- A raid cell with a per-difficulty breakdown builds a per-difficulty
    -- tooltip that names every difficulty. There is no per-boss list: boss
    -- completion is never reconstructed from a kill count.
    local raidDifficultyCell = {
        difficulties = {
            { difficulty = 14, difficultyLabel = "N", completedParts = 6, totalParts = 6 },
            { difficulty = 15, difficultyLabel = "H", completedParts = 3, totalParts = 6 },
            { difficulty = 17, difficultyLabel = "LFR", completedParts = 4, totalParts = 4 },
        },
    }
    local raidDiffTip = UI.raidTooltip(raidDifficultyCell)
    test.eq(#raidDiffTip.lines, 3, "a per-difficulty tooltip lists each difficulty")
    test.eq(raidDiffTip.lines[1], "N 6/6", "the normal difficulty count is listed")
    test.eq(raidDiffTip.lines[2], "H 3/6", "the heroic partial count is listed")
    test.eq(raidDiffTip.lines[3], "LFR 4/4", "the raid finder count is named")

    test.eq(UI.raidTooltip({ encounters = { { id = 1, done = true } } }), nil,
        "a root-level encounters table is not a difficulty breakdown, so it yields nothing")
    test.eq(UI.raidTooltip({}), nil, "a cell without a breakdown has no raid tooltip")

    -- A malformed difficulty line without a usable count is skipped, never a
    -- fabricated 0/N.
    local malformedDifficultyCell = {
        difficulties = {
            { difficulty = 14, difficultyLabel = "N", completedParts = 6, totalParts = 6 },
            { difficulty = 16, difficultyLabel = "M" },
        },
    }
    local malformedDiffTip = UI.raidTooltip(malformedDifficultyCell)
    test.eq(#malformedDiffTip.lines, 1, "a malformed difficulty line is skipped")
    test.eq(malformedDiffTip.lines[1], "N 6/6", "the valid difficulty still renders")

    -- A retail difficulty's own per-boss list renders under its difficulty line,
    -- scoped to that difficulty and using each boss's real killed flag.
    local bossTooltipCell = {
        difficulties = {
            {
                difficulty = 16, difficultyLabel = "M", completedParts = 1, totalParts = 2,
                encounters = {
                    { name = "首王", killed = false },
                    { name = "次王", killed = true },
                },
            },
            {
                difficulty = 14, difficultyLabel = "N", completedParts = 2, totalParts = 2,
                encounters = { { name = "首王", killed = true } },
            },
        },
    }
    local bossTip = UI.raidTooltip(bossTooltipCell)
    test.eq(#bossTip.lines, 5, "a per-boss tooltip lists the difficulty and every boss")
    test.eq(bossTip.lines[1], "M 1/2", "the mythic difficulty header is listed")
    test.eq(bossTip.lines[2], "    首王 ✗", "mythic boss 1 is not killed")
    test.eq(bossTip.lines[3], "    次王 ✓", "mythic boss 2 is killed")
    test.eq(bossTip.lines[4], "N 2/2", "the normal difficulty header is listed")
    test.eq(bossTip.lines[5], "    首王 ✓", "normal boss 1 is killed, scoped to its own difficulty")

    -- A boss with no name is skipped rather than rendered as an empty line.
    local namelessBoss = UI.raidTooltip({
        difficulties = {
            {
                difficulty = 16, difficultyLabel = "M", completedParts = 1, totalParts = 2,
                encounters = { { killed = true }, { name = "次王", killed = true } },
            },
        },
    })
    test.eq(#namelessBoss.lines, 2, "a nameless boss is skipped, the named one survives")
    test.eq(namelessBoss.lines[2], "    次王 ✓", "the named boss still renders")

    local raidTooltipTitle, raidTooltipLines = nil, {}
    local fakeRaidTooltip = {
        SetText = function(_, value) raidTooltipTitle = value end,
        AddLine = function(_, value) raidTooltipLines[#raidTooltipLines + 1] = value end,
    }
    test.eq(UI.showRaidTooltip(fakeRaidTooltip, raidDifficultyCell), true,
        "a raid cell can populate the Blizzard tooltip")
    test.eq(#raidTooltipLines, 3, "every difficulty line reaches the tooltip")
    test.eq(UI.showRaidTooltip({ SetText = function() end }, {}), false,
        "a cell without a breakdown cannot populate a tooltip")

    -- Profession cooldown headings keep the compact title and resolve the
    -- client's own spell name for the tooltip, falling back when it is absent.
    local cooldownHeader = UI.columnHeader({
        title = "炼金转化",
        source = { kind = "profession-cooldown", key = "alchemyTransmute", spellId = 66660 },
    }, nil, function(id)
        test.eq(id, 66660, "cooldown header resolves the declared spell id")
        return "转化：琥珀"
    end)
    test.eq(cooldownHeader.text, "炼金转化", "cooldown heading keeps its compact catalog title")
    test.eq(cooldownHeader.tooltip, "转化：琥珀", "cooldown tooltip uses Blizzard's localized spell name")
    local cooldownFallback = UI.columnHeader({
        title = "炼金转化",
        source = { kind = "profession-cooldown", key = "alchemyTransmute", spellId = 66660 },
    }, nil, function() return nil end)
    test.eq(cooldownFallback.tooltip, "炼金转化", "a missing spell name falls back to the catalog title")

    test.eq(UI.headerControls("pinned", true).canAdd, true, "pinned sections expose settings")
    test.eq(UI.headerControls("preview", true).canAdd, false, "preview sections do not expose settings")
    test.eq(type(UI.SetMode), "function", "entry can declare preview or pinned rendering")
    test.eq(UI.SetColumnHandler, nil, "per-heading X removal is not part of the renderer")
    test.eq(type(UI.SetSettingsHandler), "function", "entry can inject the section settings handler")
    local resourceLayout = layout.sections[2]
    local lastResourceColumn = resourceLayout.columns[#resourceLayout.columns]
    test.eq(lastResourceColumn.x + lastResourceColumn.width <= resourceLayout.addX, true,
        "the section add control never overlaps the last column")

    -- The raid section lays out the reset countdown; the resource section does not.
    test.eq(layout.sections[1].countdown ~= nil, true, "raid section lays out the reset countdown")
    test.eq(layout.sections[2].countdown, nil, "resource section has no countdown")

    -- Empty data renders a compact message, never an empty equipment wall.
    local emptyProjection = View.project({
        family = "titan", catalog = Catalog.forFamily("titan"), snapshots = {},
        currentRealmId = 123, showAllRealms = true, now = 1000, visibility = {},
    })
    local emptyLayout = UI.layout(emptyProjection)
    test.eq(emptyLayout.isEmpty, true, "empty layout is flagged")
    test.eq(type(emptyLayout.emptyText), "string", "empty layout carries a message")
    test.eq(emptyLayout.emptyText ~= "", true, "empty message is not blank")
    test.eq(#emptyLayout.sections[1].rows, 0, "empty layout draws no character rows")

    local unsupportedLayout = UI.layout(View.project({
        family = "wrath",
        catalog = Catalog.forFamily("wrath"),
        snapshots = { snapshot() },
        currentRealmId = 123, now = 1000, visibility = {},
    }))
    test.eq(unsupportedLayout.emptyText, "该版本角色总览适配中。",
        "unverified clients show a truthful adaptation message")

    local pendingLayout = UI.layout(View.project({
        family = "mop",
        catalog = Catalog.forFamily("mop"),
        snapshots = { snapshot() },
        currentRealmId = 123, showAllRealms = true, now = 1000, visibility = {},
    }))
    test.eq(pendingLayout.emptyText ~= "该版本角色总览适配中。", true,
        "pending clients do not render an unsupported placeholder")
    test.eq(pendingLayout.characterCount, 1,
        "pending clients render the local snapshot for real-client validation")

    -- Hiding a column immediately reflows the layout.
    local hidden = View.project({
        family = "titan",
        catalog = Catalog.forFamily("titan"),
        snapshots = { snapshot() },
        currentRealmId = 123, now = 1000,
        visibility = { raid = { MCtitan = false } },
    })
    local hiddenLayout = UI.layout(hidden)
    for _, column in ipairs(hiddenLayout.sections[1].columns) do
        test.eq(column.id ~= "MCtitan", true, "hidden column is not laid out")
    end

    -- The window controls the approved design requires.
    test.eq(type(UI.controls), "table", "controls are declared")
    local controls = {}
    for _, control in ipairs(UI.controls) do controls[control] = true end
    test.eq(controls.settings, true, "settings control exists")
    test.eq(controls.refresh, true, "refresh control exists")
    test.eq(controls.close, true, "close control exists")

    -- Source-level invariants that plain Lua cannot exercise through frames.
    local handle = io.open("Core/BGNext/OwnCharactersUI.lua", "r")
    local source = handle:read("*a")
    handle:close()

    for _, forbidden in ipairs({
        "SendAddonMessage", "SendChatMessage", "C_ChatInfo",
        "INSPECT_READY", "COMBAT_LOG_EVENT", "CHAT_MSG", "NotifyInspect",
    }) do
        test.eq(string.find(source, forbidden, 1, true), nil, "renderer never calls " .. forbidden)
    end

    -- The renderer must not reach into storage; it is given a projection.
    for _, forbidden in ipairs({ "BG.BGNext.DB", "ownCharacters", "BiaoGe.BGNext" }) do
        test.eq(string.find(source, forbidden, 1, true), nil, "renderer never traverses " .. forbidden)
    end

    -- Rows expose a right-click delete surface; the entry wires the handler.
    test.eq(type(UI.SetRowHandler), "function", "a per-row handler setter is exposed")
    test.eq(string.find(source, "RightButton", 1, true) ~= nil, true, "rows register right-click")
    test.eq(string.find(source, "SetRowHandler", 1, true) ~= nil, true, "the renderer exposes SetRowHandler")

    -- No per-character card or vertical equipment wall may exist.
    for _, forbidden in ipairs({ "CreateCard", "cardLayout", "CreateCharacterCard", "columnPerCharacter" }) do
        test.eq(string.find(source, forbidden, 1, true), nil, "renderer has no " .. forbidden .. " helper")
    end
    test.eq(string.find(source, "GetRealZoneText", 1, true), nil,
        "renderer never expands compact raid headings back to full zone names")
    test.eq(string.find(source, "__closeButton", 1, true), nil,
        "headers never create the removed hover X")
    test.eq(string.find(source, "SetWordWrap(false)", 1, true) ~= nil, true,
        "pooled row labels cannot wrap into another line")
    test.eq(string.find(source, "ClearAllPoints", 1, true) ~= nil, true,
        "pooled regions clear stale anchors before reuse")
    test.eq(string.find(source, "SetFrameLevel", 1, true) ~= nil, true,
        "item buttons are raised above the row click surface")
    test.eq(string.find(source, "M.colors.header", 1, true) ~= nil, true,
        "renderer uses one neutral column-heading colour")

    -- Equipment icons use Blizzard's official tooltip, not a hand-built one.
    for _, required in ipairs({
        "GameTooltip", "SetHyperlink", "SetItemByID", "RequestLoadItemDataByID", "SetText",
    }) do
        test.eq(string.find(source, required, 1, true) ~= nil, true, "renderer uses " .. required)
    end

    UI.SetFrame(nil)
    test.eq(UI.IsVisible(), false, "an uncreated overview is not visible")
    UI.SetFrame({ IsShown = function() return false end })
    test.eq(UI.IsVisible(), false, "a hidden overview reports not visible")
    UI.SetFrame({ IsShown = function() return true end })
    test.eq(UI.IsVisible(), true, "a shown overview reports visible")
end
