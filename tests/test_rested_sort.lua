return function(test)
    BG = { BGNext = {} }
    local Settings = dofile("Core/BGNext/RoleOverviewSettings.lua")
    local Catalog = dofile("Core/BGNext/OwnCharactersCatalog.lua")
    local View = dofile("Core/BGNext/OwnCharactersView.lua")
    local root = {}
    test.eq(Settings.sortMode(root), "default", "absent sort preserves default")
    for _, mode in ipairs({ "default", "class", "itemLevel", "level", "name", "updatedAt" }) do
        test.eq(Settings.setSortMode(root, mode), true, "accept declared sort mode")
        test.eq(Settings.sortMode(root), mode, "sort mode persists account-wide")
    end
    test.eq(Settings.setSortMode(root, "invalid"), false, "reject invalid mode")
    root.settings.roleOverviewSortMode = {}
    test.eq(Settings.sortMode(root), "default", "corrupt mode falls back")

    local snapshots = {
        { player = "C", realmId = 1, class = "MAGE", itemLevel = 100, level = 20, updatedAt = 300 },
        { player = "B", realmId = 2, class = "WARRIOR", itemLevel = 200, level = 40, updatedAt = 100 },
        { player = "A", realmId = 1, class = "WARRIOR", itemLevel = 250, level = 30, updatedAt = 200 },
        { player = "D", realmId = 1 },
    }
    local input = { family = "forever", catalog = Catalog.forFamily("forever"), snapshots = snapshots,
        currentRealmId = 2, showAllRealms = true }
    local expected = { default = "BACD", class = "ABCD", itemLevel = "ABCD",
        level = "BACD", name = "ABCD", updatedAt = "CABD" }
    for mode, names in pairs(expected) do
        input.sortMode = mode
        local projected, order = View.project(input), ""
        for i, row in ipairs(projected.resource.rows) do
            order = order .. row.player
            test.eq(projected.raid.rows[i].player, row.player, "both sections share order")
        end
        test.eq(order, names, "sort " .. mode)
    end
    input.characterOrder = { { realmId = 1, player = "D" } }
    input.sortMode = "default"
    test.eq(View.project(input).resource.rows[1].player, "D", "default keeps manual order")
    input.sortMode = "itemLevel"
    test.eq(View.project(input).resource.rows[1].player, "A", "auto mode overrides manual order")
    test.eq(snapshots[1].player, "C", "projection does not reorder snapshots")
    input.snapshots = {
        { player = "Same", realmId = 2, class = "MAGE", itemLevel = 100, level = 20, updatedAt = 30 },
        { player = "Same", realmId = 1, class = "MAGE", itemLevel = 100, level = 20, updatedAt = 30 },
        { player = "Missing", realmId = 1 },
    }
    for _, mode in ipairs({ "class", "itemLevel", "level", "updatedAt" }) do
        input.sortMode = mode
        local rows = View.project(input).resource.rows
        test.eq(rows[1].realmId, 1, "equal names use realm ID tie break for " .. mode)
        test.eq(rows[3].player, "Missing", "missing sort value goes last for " .. mode)
    end

    local Adapters = dofile("Core/BGNext/OwnCharactersAdapters.lua")
    local api = {
        GetXPExhaustion = function() return 750 end,
        UnitXPMax = function(unit) test.eq(unit, "player", "only reads own XP"); return 1000 end,
        IsResting = function() return true end,
        time = function() return 1000 end,
        GetMaxPlayerLevel = function() return 60 end,
    }
    local rest = Adapters.readRestedSnapshot(api)
    test.eq(rest.restXpPercent, 75, "rested XP is percentage of current level")
    test.eq(rest.restXpObservedAt, 1000, "independent rested timestamp")
    test.eq(rest.restXpResting, true, "records rest-area boolean")
    test.eq(Adapters.readMaxLevel(api), 60, "client API provides level cap")
    api.GetXPExhaustion = function() return nil end
    test.eq(Adapters.readRestedSnapshot(api).restXpPercent, 0, "successful nil exhaustion means zero")
    api.GetXPExhaustion = function() error("protected") end
    test.eq(Adapters.readRestedSnapshot(api), nil, "failed API stays unknown")
    api.GetXPExhaustion = function() return 2000 end
    test.eq(Adapters.readRestedSnapshot(api).restXpPercent, 150, "real percentage bounded")
    api.UnitXPMax = function() return 0 end
    test.eq(Adapters.readRestedSnapshot(api), nil, "zero denominator stays unknown")
    test.eq(Adapters.readRestedSnapshot({}), nil, "missing APIs stay unknown")
    api.UnitXPMax = function() return 0/0 end
    test.eq(Adapters.readRestedSnapshot(api), nil, "NaN denominator stays unknown")
    api.UnitXPMax = function() return math.huge end
    test.eq(Adapters.readRestedSnapshot(api), nil, "infinite denominator stays unknown")
    test.eq(Adapters.readMaxLevel({ MAX_PLAYER_LEVEL = 70 }), 70, "client constant fallback")
    test.eq(Adapters.readMaxLevel({}), nil, "no hardcoded level cap")
    test.eq(Adapters.readMaxLevel({ GetMaxPlayerLevel = function() error("missing") end,
        MAX_PLAYER_LEVEL_TABLE = { [2] = 80 }, GetExpansionLevel = function() return 2 end }), 80,
        "failed cap API falls back to current expansion constant")

    api.GetXPExhaustion = function() return 750 end
    api.UnitXPMax = function() return 1000 end
    api.IsResting = function() return false end
    test.eq(Adapters.readRestedSnapshot(api).restXpResting, false, "outside rest zone is a real false")

    local Collector = dofile("Core/BGNext/OwnCharactersCollector.lua")
    local Model = dofile("Core/BGNext/OwnCharacters.lua")
    api.UnitName = function() return "Own" end
    api.GetRealmID = function() return 1 end
    api.UnitLevel = function() return 10 end
    local catalog = Catalog.forFamily("vanilla")
    local env = Adapters.readers("vanilla", api, catalog.raidColumns, catalog.resourceColumns)
    local collected = Collector.collect(env)
    test.eq(collected.restXpPercent, 75, "collector includes actual percentage")
    local stored = Model.upsert({}, "vanilla", collected)
    test.eq(stored.restXpPercent, 75, "storage permits percentage")
    test.eq(stored.restXpObservedAt, 1000, "storage permits rested observation time")
    test.eq(stored.restXpResting, false, "storage preserves false resting state")

    local function restCell(level, percent, resting, now, current, maxLevel)
        local value = View.project({ family = "forever", catalog = Catalog.forFamily("forever"),
            snapshots = { { player = "Own", realmId = 1, level = level,
                restXpPercent = percent, restXpObservedAt = 1000, restXpResting = resting } },
            currentRealmId = 1, currentPlayer = current and "Own" or "Other",
            maxLevel = maxLevel or 60, now = now })
        for _, cell in ipairs(value.resource.rows[1].cells) do
            if cell.columnId == "restXp" then return cell end
        end
        error("rested column must be default-visible on Forever")
    end
    test.eq(restCell(10, 75, true, 1000 + 28800, true).text, "75%", "current character is never estimated")
    test.eq(restCell(10, 75, true, 1000 + 28800).text, "约80%", "rest area grows five points in eight hours")
    test.eq(restCell(10, 75, false, 1000 + 28800).text, "约76.25%", "outside grows quarter rate")
    test.eq(restCell(10, 149, true, 1000 + 28800).text, "约150%", "estimate capped at 150")
    test.eq(restCell(9, 75, true, 1000).text, "", "below ten blank")
    test.eq(restCell(59, 75, true, 1000, true).text, "75%", "below cap visible")
    test.eq(restCell(60, 75, true, 1000).text, "", "at cap blank")
    test.eq(restCell(61, 75, true, 1000).text, "", "above cap blank")
    test.eq(restCell(10, 75, true, 500).text, "约75%", "backwards clock cannot subtract rest")
    test.eq(restCell(10, nil, true, 2000).text, "", "legacy raw XP never guessed as percentage")
    test.eq(restCell(10, 75, nil, 1000 + 28800).text, "约75%", "unknown rest area cannot fabricate growth")
    test.eq(restCell(10, 75, true, 1000, false, 0/0).text, "", "invalid cap cannot imply eligibility")
    for _, family in ipairs(Adapters.families) do
        local column = Catalog.column(family, "resource", "restXp")
        test.eq(column and column.defaultVisible, true, "rested column declared on " .. family)
    end

    local modelRoot = {}
    Model.upsert(modelRoot, "vanilla", collected)
    Model.mergeSections(modelRoot, "vanilla", { player = collected.player, realmId = 1,
        updatedAt = 2000, money = 10 }, { money = true })
    test.eq(Model.get(modelRoot, "vanilla", 1, collected.player).restXpObservedAt, 1000,
        "unrelated events preserve independent rested timestamp")
    local pending, callbacks, handler = {}, {}, nil
    Collector.installEvents({ family = "forever", frame = {
        RegisterEvent = function() end,
        SetScript = function(_, _, fn) handler = fn end,
    }, after = function(_, fn) pending[#pending + 1] = fn end }, function(sections)
        callbacks[#callbacks + 1] = sections
    end)
    handler(nil, "PLAYER_XP_UPDATE", "target")
    test.eq(#pending, 0, "other unit XP is ignored")
    handler(nil, "PLAYER_XP_UPDATE", "player")
    test.eq(#pending, 1, "own XP schedules rested refresh")
    pending[1]()
    test.eq(callbacks[1].rested, true, "XP refresh includes rested section")
    handler(nil, "PLAYER_UPDATE_RESTING")
    pending[2]()
    test.eq(callbacks[2].rested, true, "rest-area changes refresh snapshot")
    handler(nil, "PLAYER_LOGOUT")
    test.eq(#callbacks, 3, "logout flushes synchronously")
    test.eq(callbacks[3].rested, true, "logout records actual rested state")
    test.eq(callbacks[3].identity, true, "logout records level with rested state")
    pending[2]()
    test.eq(#callbacks, 3, "stale debounce callback after logout does not write empty snapshot")

    local Runtime = dofile("Core/BGNext/OwnCharactersRuntime.lua")
    local deps = { globals = { IsVanilla = true }, family = "vanilla", root = {}, api = api,
        catalog = catalog, adapters = Adapters, collector = Collector, model = Model, settings = Settings }
    Runtime.collectAndStore(deps)
    test.eq(Model.get(deps.root, "vanilla", 1, "Own").restXpPercent, 75, "runtime stores real login observation")
    api.GetXPExhaustion = function() return 100 end
    Runtime.collectAndStore(deps)
    test.eq(Model.get(deps.root, "vanilla", 1, "Own").restXpPercent, 10, "login replaces offline estimate baseline")
    Runtime.setEnabled(deps, false)
    api.GetXPExhaustion = function() error("disabled must not collect") end
    test.eq(Runtime.collectAndStore(deps, { rested = true }), nil, "disabled feature does not collect rested data")
end
