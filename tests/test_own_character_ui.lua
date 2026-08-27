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

    -- Green completion marker and green section titles, grey hints.
    local complete = UI.colors.complete
    test.eq(complete.g > complete.r and complete.g > complete.b, true, "completion marker is green")
    local title = UI.colors.title
    test.eq(title.g > title.r and title.g > title.b, true, "section titles are green")
    local hint = UI.colors.hint
    test.eq(hint.r == hint.g and hint.g == hint.b, true, "hints are grey")

    -- Equipment icons use the documented 19px content size.
    test.eq(UI.metrics.iconSize, 19, "item icons are 19px")
    test.eq(UI.metrics.iconSize, View.metrics.iconSize, "renderer and projection share one icon size")
    test.eq(UI.metrics.rowHeight, View.metrics.rowHeight, "renderer and projection share one row height")
    test.eq(UI.metrics.nameColumnWidth, View.metrics.nameColumnWidth, "renderer shares the name column width")

    -- Class colouring is looked up per row, not stored per character.
    test.eq(type(UI.classColor("HUNTER")), "table", "class colour resolves")
    test.eq(type(UI.classColor("NOPE")), "table", "unknown class falls back safely")
    local hunter = UI.classColor("HUNTER")
    test.eq(type(hunter.r) == "number" and type(hunter.g) == "number" and type(hunter.b) == "number", true,
        "class colour has rgb components")

    -- Empty data renders a compact message, never an empty equipment wall.
    local emptyProjection = View.project({
        family = "titan", catalog = Catalog.forFamily("titan"), snapshots = {},
        currentRealmId = 123, now = 1000, visibility = {},
    })
    local emptyLayout = UI.layout(emptyProjection)
    test.eq(emptyLayout.isEmpty, true, "empty layout is flagged")
    test.eq(type(emptyLayout.emptyText), "string", "empty layout carries a message")
    test.eq(emptyLayout.emptyText ~= "", true, "empty message is not blank")
    test.eq(#emptyLayout.sections[1].rows, 0, "empty layout draws no character rows")

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

    -- No per-character card or vertical equipment wall may exist.
    for _, forbidden in ipairs({ "CreateCard", "cardLayout", "CreateCharacterCard", "columnPerCharacter" }) do
        test.eq(string.find(source, forbidden, 1, true), nil, "renderer has no " .. forbidden .. " helper")
    end
end
