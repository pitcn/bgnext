return function(test)
    BG = { BGNext = {} }
    dofile("Core/BGNext/OwnCharactersAdapters.lua")
    local Catalog = dofile("Core/BGNext/OwnCharactersCatalog.lua")
    local View = dofile("Core/BGNext/OwnCharactersView.lua")

    local function snapshot(overrides)
        local base = {
            realmId = 123, realmName = "时光II", player = "Piti",
            class = "HUNTER", level = 80, itemLevel = 230.75,
            money = 12340000, updatedAt = 1000,
            raidStates = {}, currencies = {}, items = {}, equipment = {}, professions = {},
        }
        for key, value in pairs(overrides or {}) do base[key] = value end
        return base
    end

    local function input(overrides)
        local base = {
            family = "titan",
            catalog = Catalog.forFamily("titan"),
            snapshots = { snapshot() },
            currentRealmId = 123,
            showAllRealms = false,
            now = 1000,
            visibility = {},
        }
        for key, value in pairs(overrides or {}) do base[key] = value end
        return base
    end

    -- Two sections with the approved titles and hints.
    local view = View.project(input())
    test.eq(view.raid.title, "< 角色团本完成总览 >", "raid section title")
    test.eq(view.resource.title, "< 角色货币总览 >", "resource section title")
    test.eq(type(view.raid.hint), "string", "raid hint is a string")
    test.eq(type(view.resource.hint), "string", "resource hint is a string")
    test.eq(type(view.width), "number", "width is computed")
    test.eq(type(view.height), "number", "height is computed")
    test.eq(view.width > 0, true, "width is positive")
    test.eq(view.height > 0, true, "height is positive")

    -- Characters are rows and catalog descriptors are columns, in both sections.
    test.eq(#view.raid.rows, 1, "one character is one raid row")
    test.eq(#view.resource.rows, 1, "one character is one resource row")
    test.eq(view.raid.rows[1].player, "Piti", "row is keyed by character")
    test.eq(#view.raid.columns, #Catalog.forFamily("titan").raidColumns, "all raid columns project")
    test.eq(view.raid.columns[1].id, "MCtitan", "raid columns keep catalog order")
    test.eq(#view.raid.rows[1].cells, #view.raid.columns, "each row has one cell per column")
    test.eq(view.raid.rows[1].cells[1].columnId, "MCtitan", "cells follow column order")

    -- The first column header carries the visible character count.
    test.eq(type(view.raid.nameHeader), "string", "raid name header exists")
    test.eq(view.raid.characterCount, 1, "raid header counts visible characters")
    test.eq(view.resource.characterCount, 1, "resource header counts visible characters")

    -- Completion, progress and unknown states.
    local states = View.project(input({
        snapshots = { snapshot({
            raidStates = {
                MCtitan = { completed = true, resetsAt = 9000 },
                SSCtitan = { progress = 3, total = 6, resetsAt = 9000 },
                NAXXtitan = { completed = true, resetsAt = 500 },
            },
        }) },
    }))
    local byId = {}
    for _, cell in ipairs(states.raid.rows[1].cells) do byId[cell.columnId] = cell end
    test.eq(byId.MCtitan.state, "complete", "completed raid is marked complete")
    test.eq(byId.SSCtitan.state, "progress", "partial raid shows progress")
    test.eq(byId.SSCtitan.text, "3/6", "progress text is progress over total")
    test.eq(byId.NAXXtitan.state, "empty", "raid state past its reset renders blank")
    test.eq(byId.NAXXtitan.text, "", "expired raid has no text")
    test.eq(byId.TOCtitan.state, "empty", "unvisited raid renders blank")

    -- Expiry is a render-time decision; the caller's snapshot is untouched.
    local sourceSnapshot = snapshot({ raidStates = { NAXXtitan = { completed = true, resetsAt = 500 } } })
    View.project(input({ snapshots = { sourceSnapshot } }))
    test.eq(sourceSnapshot.raidStates.NAXXtitan.completed, true, "projection does not mutate snapshots")

    -- Class colour and item level travel with the row.
    test.eq(view.raid.rows[1].class, "HUNTER", "row carries the class for colouring")
    test.eq(view.raid.rows[1].itemLevel, 230.75, "row carries item level")
    test.eq(view.resource.rows[1].level, 80, "resource row carries level")

    -- Alternating stripes are deterministic.
    local striped = View.project(input({
        snapshots = {
            snapshot({ player = "Aaa" }), snapshot({ player = "Bbb" }),
            snapshot({ player = "Ccc" }), snapshot({ player = "Ddd" }),
        },
    }))
    test.eq(striped.raid.rows[1].stripe, "dark", "first row is dark")
    test.eq(striped.raid.rows[2].stripe, "light", "second row is light")
    test.eq(striped.raid.rows[3].stripe, "dark", "third row is dark")
    test.eq(striped.raid.rows[4].stripe, "light", "fourth row is light")
    local again = View.project(input({
        snapshots = {
            snapshot({ player = "Aaa" }), snapshot({ player = "Bbb" }),
            snapshot({ player = "Ccc" }), snapshot({ player = "Ddd" }),
        },
    }))
    test.eq(again.raid.rows[3].stripe, striped.raid.rows[3].stripe, "stripes are stable across calls")

    -- Default view is the current realm only; Shift widens it.
    local multiRealm = {
        snapshot({ realmId = 123, realmName = "时光II", player = "Piti" }),
        snapshot({ realmId = 456, realmName = "时光III", player = "Piti", class = "MAGE" }),
        snapshot({ realmId = 456, realmName = "时光III", player = "Alt", class = "MAGE" }),
    }
    local currentOnly = View.project(input({ snapshots = multiRealm }))
    test.eq(#currentOnly.raid.rows, 1, "default shows only the current realm")
    test.eq(currentOnly.raid.rows[1].realmId, 123, "current realm row is kept")

    local allRealms = View.project(input({ snapshots = multiRealm, showAllRealms = true }))
    test.eq(#allRealms.raid.rows, 3, "shift shows every local realm")
    test.eq(allRealms.raid.rows[1].realmId, 123, "current realm sorts first")

    -- Same-name cross-realm characters stay two rows and gain a short prefix.
    local piti = {}
    for _, row in ipairs(allRealms.raid.rows) do
        if row.player == "Piti" then piti[#piti + 1] = row end
    end
    test.eq(#piti, 2, "same-name cross-realm characters remain distinct rows")
    test.eq(piti[1].realmId ~= piti[2].realmId, true, "the two rows are different realms")
    test.eq(piti[1].prefix ~= "", true, "same-name row shows a realm prefix")
    test.eq(piti[2].prefix ~= "", true, "both same-name rows show a prefix")
    test.eq(piti[1].prefix ~= piti[2].prefix, true, "prefixes distinguish the two realms")
    test.eq(piti[1].display ~= piti[2].display, true, "the two rows display differently")
    -- "时光II" and "时光III" share their first codepoints, so the prefix has to
    -- grow past the default length until it actually disambiguates.
    test.eq(string.sub(piti[1].realmName, 1, #piti[1].prefix), piti[1].prefix, "prefix comes from the realm name")
    test.eq(string.sub(piti[2].realmName, 1, #piti[2].prefix), piti[2].prefix, "prefix comes from the realm name")

    -- Realms that differ early keep the compact two-character prefix.
    local distinctRealms = View.project(input({
        showAllRealms = true,
        snapshots = {
            snapshot({ realmId = 123, realmName = "白银之手", player = "Piti" }),
            snapshot({ realmId = 456, realmName = "洛萨", player = "Piti" }),
        },
    }))
    test.eq(distinctRealms.raid.rows[1].prefix, "白银", "distinct realms use a short prefix")
    test.eq(distinctRealms.raid.rows[2].prefix, "洛萨", "distinct realms use a short prefix")
    for _, row in ipairs(allRealms.raid.rows) do
        if row.player == "Alt" then
            test.eq(row.prefix, "", "unique names need no prefix")
            test.eq(row.display, "Alt", "unique name displays bare")
        end
    end

    -- Keys are the full family/realm/name triple so deletion cannot collide.
    test.eq(piti[1].key ~= piti[2].key, true, "same-name rows have different keys")
    test.eq(type(piti[1].key), "string", "row key is a string")

    -- Hiding a column removes it from the projection and shrinks the width,
    -- without touching the stored snapshots.
    local wide = View.project(input())
    local hiddenRaid = View.project(input({ visibility = { raid = { MCtitan = false } } }))
    test.eq(#hiddenRaid.raid.columns, #wide.raid.columns - 1, "hidden raid column disappears")
    -- Both sections share one window, so the window is as wide as the wider
    -- section; the raid section always narrows when one of its columns goes.
    test.eq(hiddenRaid.raid.width < wide.raid.width, true, "hiding a raid column narrows the raid section")
    test.eq(hiddenRaid.width <= wide.width, true, "hiding a raid column never widens the window")
    for _, column in ipairs(hiddenRaid.raid.columns) do
        test.eq(column.id ~= "MCtitan", true, "hidden column is absent from the projection")
    end
    test.eq(#hiddenRaid.raid.rows[1].cells, #hiddenRaid.raid.columns, "row cells follow visible columns")

    local hiddenResource = View.project(input({ visibility = { resource = { titanShard = false } } }))
    test.eq(hiddenResource.width < wide.width, true, "hiding a resource column shrinks the window")
    for _, column in ipairs(hiddenResource.resource.columns) do
        test.eq(column.id ~= "titanShard", true, "hidden resource column is absent")
    end

    local keptSnapshot = snapshot({ currencies = { titanShard = 12 } })
    View.project(input({ snapshots = { keptSnapshot }, visibility = { resource = { titanShard = false } } }))
    test.eq(keptSnapshot.currencies.titanShard, 12, "hiding a column keeps the underlying snapshot")

    -- The equipment column is sized by how many icons it actually has to draw.
    local function equipped(count)
        local slots = {}
        for slot = 1, count do slots[slot] = { itemId = 1000 + slot, itemLevel = 200 } end
        return slots
    end
    local fewItems = View.project(input({ snapshots = { snapshot({ equipment = equipped(3) }) } }))
    local manyItems = View.project(input({ snapshots = { snapshot({ equipment = equipped(10) }) } }))
    test.eq(manyItems.resource.width > fewItems.resource.width, true, "more equipment icons widen the column")
    local function equipmentColumn(projection)
        for _, column in ipairs(projection.resource.columns) do
            if column.id == "equipment" then return column end
        end
    end
    test.eq(equipmentColumn(fewItems).slots, 3, "column reserves one slot per drawn icon")
    test.eq(equipmentColumn(manyItems).slots, 10, "column grows with the icon count")
    local firstRowItems = manyItems.resource.rows[1].cells
    for _, cell in ipairs(firstRowItems) do
        if cell.columnId == "equipment" then
            test.eq(#cell.items, 10, "every equipped slot becomes an icon")
            test.eq(cell.items[1].slot, 1, "icons are ordered by slot")
        end
    end

    -- Unavailable columns never reach the projection, so nothing is faked.
    local unavailable = View.project(input({
        available = function(section, columnId) return not (section == "resource" and columnId == "titanShard") end,
    }))
    for _, column in ipairs(unavailable.resource.columns) do
        test.eq(column.id ~= "titanShard", true, "unavailable column is not projected")
    end

    -- Totals cover only descriptors that declare total=true.
    local totals = View.project(input({
        snapshots = {
            snapshot({ player = "Aaa", money = 10000, currencies = { honor = 5 } }),
            snapshot({ player = "Bbb", money = 20000, currencies = { honor = 7 } }),
        },
    }))
    test.eq(type(totals.resource.totals), "table", "totals table exists")
    test.eq(totals.resource.totals.money, 30000, "money totals across characters")
    test.eq(totals.resource.totals.honor, 12, "honor totals across characters")
    test.eq(totals.resource.totals.equipment, nil, "equipment has no fake total")
    test.eq(totals.resource.totals.prof1, nil, "professions have no fake total")
    for _, column in ipairs(totals.resource.columns) do
        if column.total ~= true then
            test.eq(totals.resource.totals[column.id], nil, column.id .. " must not report a total")
        end
    end
    test.eq(totals.raid.totals, nil, "the raid section has no totals row")

    -- Height grows with rows and shrinks when characters are filtered out.
    test.eq(totals.height > view.height, true, "more characters make the window taller")

    -- Empty and malformed input stay safe.
    local empty = View.project(input({ snapshots = {} }))
    test.eq(#empty.raid.rows, 0, "no characters yields no rows")
    test.eq(empty.isEmpty, true, "empty projection is flagged for the renderer")
    test.eq(empty.width > 0, true, "empty projection still has a usable width")
    test.eq(View.project(nil), nil, "missing input is safe")
    test.eq(View.project({}), nil, "input without a catalog is safe")

    local malformed = View.project(input({
        snapshots = { snapshot(), "not a table", { player = "NoRealm" }, snapshot({ raidStates = "broken" }) },
    }))
    test.eq(#malformed.raid.rows, 2, "malformed snapshots are skipped, valid ones survive")
end
