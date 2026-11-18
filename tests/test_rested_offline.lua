return function(test)
    BG = { BGNext = {} }
    local Settings = dofile("Core/BGNext/RoleOverviewSettings.lua")
    local Catalog = dofile("Core/BGNext/OwnCharactersCatalog.lua")
    local Adapters = dofile("Core/BGNext/OwnCharactersAdapters.lua")
    local Collector = dofile("Core/BGNext/OwnCharactersCollector.lua")
    local Model = dofile("Core/BGNext/OwnCharacters.lua")
    local Runtime = dofile("Core/BGNext/OwnCharactersRuntime.lua")
    local View = dofile("Core/BGNext/OwnCharactersView.lua")
    local Lifecycle = dofile("Core/BGNext/DataLifecycle.lua")

    for _, family in ipairs({ "titan", "forever" }) do
        -- Synthetic identities only. Exercise real login/logout collection,
        -- root loading and projection rather than prebuilding rested rows.
        local player, stamp, readable = "A Test", 1000, true
        local api = {
            UnitName = function() return player end,
            GetRealmID = function() return 1 end,
            UnitLevel = function() return 20 end,
            GetMaxPlayerLevel = function() return 60 end,
            GetXPExhaustion = function() return 750 end,
            UnitXPMax = function() return readable and 1000 or 0 end,
            IsResting = function() return true end,
            time = function() return stamp end,
        }
        local saved = {}
        local deps = { family = family, globals = {}, api = api,
            root = Lifecycle.ensureRoot(saved), catalog = Catalog.forFamily(family),
            adapters = Adapters, collector = Collector, model = Model, settings = Settings,
            now = function() return stamp end }
        local function cells()
            local projected = View.project({ family = family, catalog = deps.catalog,
                snapshots = Model.list(deps.root, family), currentRealmId = 1,
                currentPlayer = player, maxLevel = 60, now = stamp })
            local result = {}
            for _, row in ipairs(projected.resource.rows) do
                for _, cell in ipairs(row.cells) do
                    if cell.columnId == "restXp" then result[row.player] = cell.text end
                end
            end
            return result
        end
        Runtime.collectAndStore(deps)
        test.eq(cells()["A Test"], "75%", "login observes actual rested XP")
        local handler
        Collector.installEvents({ family = family, frame = {
            RegisterEvent = function() end,
            SetScript = function(_, _, fn) handler = fn end,
        } }, function(sections) Runtime.collectAndStore(deps, sections) end)
        -- A late logout observation cannot read a valid XP denominator.
        readable = false
        handler(nil, "PLAYER_LOGOUT")
        player, stamp, readable = "B Test", 1000 + 28800, true
        deps.root = Lifecycle.ensureRoot(saved)
        Runtime.collectAndStore(deps)
        test.eq(cells()["B Test"], "75%", "second login observes its own actual value")
        test.eq(cells()["A Test"], "约80%", "first character remains visible after second login")
        test.eq(Model.get(deps.root, family, 1, "A Test").restXpObservedAt, 1000,
            "failed observation never advances the estimation anchor")

        -- Full refreshes obey the same last-successful-observation rule.
        player, readable = "A Test", false
        Runtime.collectAndStore(deps)
        player = "B Test"
        test.eq(cells()["A Test"], "约80%", "unreadable full refresh preserves the saved baseline")
        api.GetXPExhaustion = function() error("unavailable") end
        Runtime.collectAndStore(deps, { rested = true })
        test.eq(cells()["B Test"], "75%", "throwing API preserves the last observation")

        -- Old saves with no rested fields remain unknown, without migration.
        Model.upsert(deps.root, family, { player = "Legacy Test", realmId = 1, level = 20 })
        player = "Legacy Test"
        Runtime.collectAndStore(deps)
        test.eq(cells()["Legacy Test"], "", "legacy current character stays blank when unreadable")
        player = "B Test"
        test.eq(cells()["Legacy Test"], "", "legacy offline character stays blank")

        -- A successful nil is a real zero and must replace the previous 75%.
        readable = true
        api.GetXPExhaustion = function() return nil end
        api.IsResting = function() return false end
        stamp = stamp + 100
        handler(nil, "PLAYER_LOGOUT")
        test.eq(cells()["B Test"], "0%", "successful zero replaces the previous percentage")
        local latest = Model.get(deps.root, family, 1, "B Test")
        test.eq(latest.restXpObservedAt, stamp, "successful logout advances observation time")
        test.eq(latest.restXpResting, false, "successful logout records the current rest area state")
        player, stamp = "A Test", stamp + 28800
        test.eq(cells()["B Test"], "约1.25%", "offline estimate uses the latest successful logout state")
        test.eq(cells()["Legacy Test"], "", "old missing fields never fabricate growth")
    end
end
