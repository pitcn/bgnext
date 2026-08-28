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
    test.eq(view.raid.hint, "（团本重置时间：", "raid uses the original reset prefix")
    test.eq(view.resource.hint, "（鼠标中键固定显示，长按SHIFT显示全服务器角色）",
        "resource uses the original interaction hint")
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
    test.eq(#view.raid.columns, 7, "only the original default Titan raid columns project")
    test.eq(view.raid.columns[1].id, "SWtitan", "raid columns keep the original Titan order")
    test.eq(#view.raid.rows[1].cells, #view.raid.columns, "each row has one cell per column")
    test.eq(view.raid.rows[1].cells[1].columnId, "SWtitan", "cells follow column order")

    -- The first column header carries the visible character count.
    test.eq(type(view.raid.nameHeader), "string", "raid name header exists")
    test.eq(view.raid.characterCount, 1, "raid header counts visible characters")
    test.eq(view.resource.characterCount, 1, "resource header counts visible characters")
    test.eq(view.raid.nameHeader, "1个角色（装等）", "raid name header matches the original")
    test.eq(view.resource.nameHeader, "1个角色（等级）", "resource name header matches the original")
    test.eq(view.raid.columns[1].color, "00BFFF", "Titan raid headers keep the original blue")
    local resourceById = {}
    for _, column in ipairs(view.resource.columns) do resourceById[column.id] = column end
    test.eq(resourceById.mainProfession.color, "ADFF2F", "profession header keeps the original green")
    test.eq(resourceById.weapons.color, "C084FC", "weapon header keeps the original purple")
    test.eq(resourceById.legendaryItems.color, "ff8000", "legendary header keeps the original orange")
    test.eq(resourceById.upgradeItems.width >= View.metrics.columnWidths.narrow, true,
        "an empty upgrade-item column still fits its complete heading")
    test.eq(resourceById.money.color, "FFD700", "gold header keeps the original gold")

    local professionView = View.project(input({
        snapshots = { snapshot({
            professions = {
                [1] = { name = "锻造", skill = 441, icon = 136241 },
                [2] = { name = "工程", skill = 450, icon = 136243 },
            },
        }) },
    }))
    local professionCell
    for _, cell in ipairs(professionView.resource.rows[1].cells) do
        if cell.columnId == "mainProfession" then professionCell = cell break end
    end
    test.eq(professionCell.state, "professions", "main profession is an icon summary")
    test.eq(#professionCell.entries, 2, "both main professions are retained")
    test.eq(professionCell.entries[1].skill, 441, "profession summary retains the skill value")
    test.eq(professionCell.entries[1].icon, 136241, "profession summary retains the icon")

    -- Completion, progress and unknown states.
    local states = View.project(input({
        visibility = { raid = { SSCtitan = true, TKtitan = true } },
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

    test.eq(byId.TKtitan.state, "empty", "TK remains independent from SSC")

    -- Real reset countdown, surfaced as a section-level hint.
    test.eq(View.formatCountdown(1000, 1000 + 2 * 86400 + 3 * 3600), "2天3小时", "countdown spans days and hours")
    test.eq(View.formatCountdown(1000, 1000 + 3 * 3600 + 20 * 60), "3小时20分", "countdown spans hours and minutes")
    test.eq(View.formatCountdown(1000, 1000 + 5 * 60), "5分", "countdown under an hour shows minutes")
    test.eq(View.formatCountdown(1000, 1000 + 30), "不足1分钟", "countdown under a minute is clamped")
    test.eq(View.formatCountdown(1000, 1000), nil, "a reset at now has no countdown")
    test.eq(View.formatCountdown(2000, 1000), nil, "a past reset has no countdown")
    test.eq(View.formatCountdown(nil, 1000), nil, "a missing now has no countdown")
    test.eq(View.formatCountdown(1000, nil), nil, "a missing reset has no countdown")

    test.eq(View.nearestReset(states.raid.rows, 1000), 9000, "nearest reset picks the closest future reset")
    test.eq(View.nearestReset({}, 1000), nil, "no rows means no reset")
    test.eq(states.raid.resetCountdown ~= nil, true, "the raid section carries a countdown")
    test.eq(type(states.raid.resetCountdown), "string", "the countdown is a string")
    test.eq(View.project(input()).raid.resetCountdown, nil, "no raid states means no countdown")

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

    -- The main table limits equipment to the original weapon/trinket summaries.
    -- Full equipment remains an explicitly enabled details column.
    local function equipped(count)
        local slots = {}
        for slot = 1, count do slots[slot] = { itemId = 1000 + slot, itemLevel = 200 } end
        return slots
    end
    local fewItems = View.project(input({
        snapshots = { snapshot({ equipment = equipped(3) }) },
        visibility = { resource = { equipmentDetails = true } },
    }))
    local manyItems = View.project(input({
        snapshots = { snapshot({ equipment = equipped(10) }) },
        visibility = { resource = { equipmentDetails = true } },
    }))
    test.eq(manyItems.resource.width > fewItems.resource.width, true, "more equipment icons widen the column")
    local function equipmentColumn(projection)
        for _, column in ipairs(projection.resource.columns) do
            if column.id == "equipmentDetails" then return column end
        end
    end
    test.eq(equipmentColumn(fewItems).slots, 3, "column reserves one slot per drawn icon")
    test.eq(equipmentColumn(manyItems).slots, 10, "column grows with the icon count")
    local firstRowItems = manyItems.resource.rows[1].cells
    for _, cell in ipairs(firstRowItems) do
        if cell.columnId == "equipmentDetails" then
            test.eq(#cell.items, 10, "every equipped slot becomes an icon")
            test.eq(cell.items[1].slot, 1, "icons are ordered by slot")
        end
    end

    -- Item identity reaches the renderer, and content-derived widths prevent
    -- item strips and adjacent large numeric values from colliding.
    local measured = View.project(input({
        snapshots = { snapshot({
            equipment = {
                [13] = {
                    itemId = 1001,
                    link = "|Hitem:1001::::::::|h[Test Trinket]|h",
                    icon = 11,
                },
                [14] = { itemId = 1002, icon = 12 },
            },
            currencies = { titanEmber = 18421, titanShard = 542 },
        }) },
    }))
    local measuredColumns = {}
    for _, column in ipairs(measured.resource.columns) do measuredColumns[column.id] = column end
    local measuredCells = {}
    for _, cell in ipairs(measured.resource.rows[1].cells) do measuredCells[cell.columnId] = cell end
    test.eq(measuredCells.trinkets.items[1].link, "|Hitem:1001::::::::|h[Test Trinket]|h",
        "item link reaches the renderer")
    test.eq(measuredCells.trinkets.items[2].itemId, 1002, "item id remains a tooltip fallback")
    test.eq(measuredColumns.trinkets.width >= View.metrics.iconSize * 2 + View.metrics.iconGap, true,
        "two item icons fit without overflow")
    test.eq(measuredColumns.titanEmber.width >= View.measureNumber("18421"), true,
        "currency width fits its longest value")
    test.eq(measuredColumns.titanShard.x
        - (measuredColumns.titanEmber.x + measuredColumns.titanEmber.width)
        >= View.metrics.columnGap, true, "adjacent numeric columns retain a gap")

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
    test.eq(totals.resource.totals.equipmentDetails, nil, "equipment details have no fake total")
    test.eq(totals.resource.totals.mainProfession, nil, "professions have no fake total")
    for _, column in ipairs(totals.resource.columns) do
        if column.total ~= true then
            test.eq(totals.resource.totals[column.id], nil, column.id .. " must not report a total")
        end
    end
    test.eq(totals.raid.totals, nil, "the raid section has no totals row")

    -- Profession cooldowns project to a ready checkmark or a countdown string.
    local cdView = View.project({
        family = "vanilla",
        catalog = Catalog.forFamily("vanilla"),
        snapshots = { snapshot({
            professionCooldowns = {
                transmute = { ready = true },
                mooncloth = { endsAt = 1000 + 3 * 86400 + 2 * 3600 },
                saltShaker = { endsAt = 1000 + 5 * 60 },
            },
        }) },
        currentRealmId = 123,
        showAllRealms = false,
        now = 1000,
        visibility = {},
    })
    local cdCells = {}
    for _, cell in ipairs(cdView.resource.rows[1].cells) do cdCells[cell.columnId] = cell end
    test.eq(cdCells.transmute.state, "complete", "a ready cooldown renders as complete")
    test.eq(cdCells.transmute.ready, true, "a ready cooldown is flagged ready")
    test.eq(cdCells.mooncloth.state, "cooldown", "a cooling cooldown renders as a countdown")
    test.eq(cdCells.mooncloth.text, "3天2小时", "cooldown countdown spans days and hours")
    test.eq(cdCells.saltShaker.text, "5分", "cooldown under an hour shows minutes")

    local expiredCd = View.project({
        family = "vanilla",
        catalog = Catalog.forFamily("vanilla"),
        snapshots = { snapshot({ professionCooldowns = { transmute = { endsAt = 500 } } }) },
        currentRealmId = 123,
        showAllRealms = false,
        now = 1000,
        visibility = {},
    })
    for _, cell in ipairs(expiredCd.resource.rows[1].cells) do
        if cell.columnId == "transmute" then
            test.eq(cell.state, "complete", "an expired cooldown is ready, never a negative countdown")
        end
    end

    -- Height grows with rows and shrinks when characters are filtered out.
    test.eq(totals.height > view.height, true, "more characters make the window taller")

    -- Empty and malformed input stay safe.
    local empty = View.project(input({ snapshots = {} }))
    test.eq(#empty.raid.rows, 0, "no characters yields no rows")
    test.eq(empty.isEmpty, true, "empty projection is flagged for the renderer")
    test.eq(empty.width > 0, true, "empty projection still has a usable width")
    test.eq(View.project(nil), nil, "missing input is safe")
    test.eq(View.project({}), nil, "input without a catalog is safe")

    local unsupported = View.project({
        family = "wrath",
        catalog = Catalog.forFamily("wrath"),
        snapshots = { snapshot() },
        currentRealmId = 123,
        now = 1000,
        visibility = {},
    })
    test.eq(unsupported.unsupported, true, "unverified client projects an explicit unsupported state")
    test.eq(unsupported.characterCount, 0, "unverified client does not render misleading character rows")

    local pending = View.project({
        family = "mop",
        catalog = Catalog.forFamily("mop"),
        snapshots = { snapshot() },
        currentRealmId = 123,
        now = 1000,
        visibility = {},
    })
    test.eq(pending.unsupported, nil, "pending clients remain renderable for real-client validation")
    test.eq(pending.verificationStatus, "pending-in-game-verification",
        "the projection preserves the client validation status")
    test.eq(pending.characterCount, 1, "a pending client renders only its local test snapshot")

    local malformed = View.project(input({
        snapshots = { snapshot(), "not a table", { player = "NoRealm" }, snapshot({ raidStates = "broken" }) },
    }))
    test.eq(#malformed.raid.rows, 2, "malformed snapshots are skipped, valid ones survive")

    -- Column visibility is stored per client family.
    local Settings = dofile("Core/BGNext/RoleOverviewSettings.lua")
    test.eq(type(Settings.Open), "function", "role overview settings expose a section-aware opener")
    local root = {}
    local titanCatalog = Catalog.forFamily("titan")
    local mopCatalog = Catalog.forFamily("mop")

    Settings.ensure(root, "titan", titanCatalog)
    test.eq(Settings.isVisible(root, "titan", "raid", "MCtitan", titanCatalog), true, "defaults come from the catalog")

    Settings.setVisible(root, "titan", "raid", "MCtitan", false)
    test.eq(Settings.isVisible(root, "titan", "raid", "MCtitan", titanCatalog), false, "hiding is remembered")
    test.eq(Settings.isVisible(root, "mop", "raid", "MSV", mopCatalog), true,
        "mop uses its explicit independent-instance default")

    Settings.setVisible(root, "mop", "raid", "MSV", false)
    test.eq(Settings.isVisible(root, "mop", "raid", "MSV", mopCatalog), false, "mop hiding is remembered")
    test.eq(Settings.isVisible(root, "titan", "raid", "MCtitan", titanCatalog), false, "mop settings do not affect titan")

    Settings.setVisible(root, "titan", "raid", "MCtitan", true)
    test.eq(Settings.isVisible(root, "titan", "raid", "MCtitan", titanCatalog), true, "re-checking restores the column")

    Settings.setVisible(root, "titan", "raid", "MCtitan", false)
    Settings.setVisible(root, "titan", "resource", "titanShard", false)
    Settings.resetFamily(root, "titan")
    test.eq(Settings.isVisible(root, "titan", "raid", "MCtitan", titanCatalog), true, "reset restores catalog defaults")
    test.eq(Settings.isVisible(root, "titan", "resource", "titanShard", titanCatalog), true, "reset restores every section")
    test.eq(Settings.isVisible(root, "mop", "raid", "MSV", mopCatalog), false,
        "resetting Titan does not change the Mogu'shan preference")

    -- Settings feed the projection, and hiding never deletes snapshot data.
    Settings.setVisible(root, "titan", "resource", "titanShard", false)
    local settingsSnapshot = snapshot({ currencies = { titanShard = 3 } })
    local projected = View.project(input({
        snapshots = { settingsSnapshot },
        visibility = Settings.visibilityFor(root, "titan"),
    }))
    for _, column in ipairs(projected.resource.columns) do
        test.eq(column.id ~= "titanShard", true, "settings hide the column in the projection")
    end
    test.eq(settingsSnapshot.currencies.titanShard, 3, "settings never delete snapshot values")
    test.eq(projected.resource.width < wide.resource.width, true, "settings-driven hiding shrinks the section")

    -- Unknown lookups stay safe and default to the catalog, never to a guess.
    test.eq(Settings.isVisible(root, "titan", "raid", "nope", titanCatalog), false, "unknown column is not visible")
    test.eq(Settings.isVisible(root, "titan", "nope", "MCtitan", titanCatalog), false, "unknown section is not visible")
    test.eq(type(Settings.visibilityFor(root, "nope")), "table", "unknown family yields an empty override set")
    test.eq(Settings.visibilityFor(nil, "titan") ~= nil, true, "missing root is safe")
    Settings.setVisible(root, nil, "raid", "MCtitan", false)
    test.eq(Settings.isVisible(root, "titan", "raid", "MCtitan", titanCatalog), true, "a missing family writes nothing")

    -- Only booleans are stored, so a corrupted save cannot smuggle in data.
    Settings.setVisible(root, "titan", "raid", "MCtitan", "yes")
    test.eq(Settings.isVisible(root, "titan", "raid", "MCtitan", titanCatalog), true, "non-boolean visibility is ignored")

    -- The settings page lists only columns this client can actually read, so a
    -- field with no verified reader is never offered as a checkbox and never
    -- rendered with a guessed value.
    local readableApi = {
        GetNumSavedInstances = function() return 0 end,
        GetSavedInstanceInfo = function() end,
        GetMoney = function() return 0 end,
        GetInventoryItemLink = function() end,
        GetItemInfoInstant = function() end,
        GetProfessions = function() end,
        GetProfessionInfo = function() end,
        UnitHonor = function() return 0 end,
        C_CurrencyInfo = { GetCurrencyInfo = function() return { quantity = 0 } end },
        GetItemCount = function() return 0 end,
    }
    local availability = Settings.availableColumns("titan", titanCatalog, readableApi)
    test.eq(type(availability), "function", "availability is a predicate")
    test.eq(availability("raid", "MCtitan"), true, "raid lock state is readable")
    test.eq(availability("resource", "money"), true, "gold is readable on every client")
    test.eq(availability("resource", "equipmentDetails"), true, "equipment details are readable on every client")
    test.eq(availability("resource", "weapons"), true, "weapon summary is readable on titan")
    test.eq(availability("resource", "trinkets"), true, "trinket summary is readable on titan")
    test.eq(availability("resource", "mainProfession"), true, "professions are readable on titan")
    test.eq(availability("resource", "titanShard"), true, "verified Titan currency is offered")
    test.eq(availability("resource", "legendaryItems"), true, "tracked legendary items are offered")
    test.eq(availability("resource", "nope"), false, "unknown columns are unavailable")
    local unavailable = Settings.availableColumns("titan", titanCatalog, {})
    test.eq(unavailable("raid", "MCtitan"), false, "missing saved-instance APIs hide raid columns")
    test.eq(unavailable("resource", "money"), false, "missing money API hides gold")
    test.eq(unavailable("resource", "equipmentDetails"), false, "missing inventory APIs hide equipment")
    test.eq(unavailable("resource", "mainProfession"), false, "missing profession APIs hide professions")
    test.eq(unavailable("resource", "honor"), false, "missing honor API hides honor")

    -- That same predicate drives projection; verified values reach the table.
    local guarded = View.project(input({
        snapshots = { snapshot({ currencies = { titanShard = 7 } }) },
        available = Settings.availableColumns("titan", titanCatalog, readableApi),
    }))
    local hasTitanShard = false
    for _, column in ipairs(guarded.resource.columns) do
        if column.id == "titanShard" then hasTitanShard = true end
    end
    test.eq(hasTitanShard, true, "verified Titan shard column reaches the table")

    -- Destructive clears expose distinct confirmation text naming the scope.
    test.eq(type(Settings.clearDialogText), "function", "clear confirmation text is exposed")
    test.eq(Settings.clearDialogText("family") ~= Settings.clearDialogText("all"), true,
        "family and all clears warn differently")
    test.eq(string.find(Settings.clearDialogText("family"), "当前版本", 1, true) ~= nil, true,
        "family clear names the current version")

    -- The settings page wires the clear and disable controls to the runtime.
    local settingsSource = io.open("Core/BGNext/RoleOverviewSettings.lua", "r")
    local ssrc = settingsSource:read("*a")
    settingsSource:close()
    for _, required in ipairs({ "setEnabled", "isEnabled", "clearFamily", "clearAll", "confirmClear" }) do
        test.eq(string.find(ssrc, required, 1, true) ~= nil, true, "settings page wires " .. required)
    end
end
