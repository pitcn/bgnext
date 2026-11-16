return function(test)
    BG = { BGNext = {} }
    local A = dofile("Core/BGNext/OwnCharactersAdapters.lua")
    local C = dofile("Core/BGNext/OwnCharactersCollector.lua")
    local M = dofile("Core/BGNext/OwnCharacters.lua")
    local R = dofile("Core/BGNext/OwnCharactersRuntime.lua")
    local function build(root)
        local d = {
            family = "forever", globals = {}, root = root or {},
            catalog = { status = "pending-in-game-verification", resourceColumns = {{ id = "weapons" }} },
            adapters = A, collector = C, model = M, now = function() return 100 end,
            api = {
                UnitName = function() return "Hero" end,
                GetUnitName = function(unit, full) test.eq(unit, "player"); test.eq(full, true); return "Hero-RealmA" end,
                GetRealmID = function() return 1 end,
                UnitClass = function() return "Warlock", "WARLOCK" end,
            },
        }
        return d
    end
    local cases = {}
    cases.full_identity = function()
        local d = build()
        R.collectAndStore(d)
        d.api.GetUnitName = function() return "Hero-RealmB" end
        d.api.UnitClass = function() return "Paladin", "PALADIN" end
        R.collectAndStore(d)
        test.eq(#M.list(d.root, "forever"), 2, "same short name preserves both snapshots")
        test.eq(M.get(d.root, "forever", 1, "Hero-RealmA").class, "WARLOCK")
    end
    cases.filter_identity = function()
        local d = build()
        d.globals = { playerName = "Hero RealmA", realmID = 1 }
        R.collectAndStore(d)
        test.eq(M.get(d.root, "forever", 1, "Hero RealmA") ~= nil, true,
            "use the exact equipment-filter key, including client-specific separators")
    end
    cases.unavailable_full_identity = function()
        local d = build()
        d.api.GetUnitName = function() return nil end
        test.eq(R.collectAndStore(d), nil,
            "a temporarily unavailable full identity must not write a short-name collision")
        test.eq(#M.list(d.root, "forever"), 0)
    end
    cases.migrate_current = function()
        local d = build()
        M.upsert(d.root, "forever", { realmId = 1, player = "Hero", class = "WARLOCK",
            equipment = { [16] = { link = "item:101", icon = 101 } } })
        d.root.roleOverviewCharacterOrder = { forever = {{ realmId = 1, player = "Hero" }} }
        R.collectAndStore(d)
        R.collectAndStore(d)
        test.eq(M.get(d.root, "forever", 1, "Hero"), nil, "remove migrated alias")
        test.eq(#M.list(d.root, "forever"), 1, "migration is idempotent")
        test.eq(M.get(d.root, "forever", 1, "Hero-RealmA").equipment[16].icon, 101,
            "migration preserves cached equipment")
        test.eq(d.root.roleOverviewCharacterOrder.forever[1].player, "Hero-RealmA")
    end
    cases.migrate_unique_profile = function()
        local d = build()
        d.root.equipmentFilters = { [1] = { ["Other RealmB"] = {} } }
        M.upsert(d.root, "forever", { realmId = 1, player = "Other", class = "PALADIN", level = 60 })
        R.collectAndStore(d)
        test.eq(M.get(d.root, "forever", 1, "Other"), nil)
        test.eq(M.get(d.root, "forever", 1, "Other RealmB").level, 60)
    end
    cases.ambiguous_legacy = function()
        local d = build()
        M.upsert(d.root, "forever", { realmId = 1, player = "Hero", class = "PALADIN" })
        d.root.equipmentFilters = { [1] = { ["Hero-RealmB"] = {}, ["Hero-RealmC"] = {} } }
        R.collectAndStore(d)
        test.eq(M.get(d.root, "forever", 1, "Hero").class, "PALADIN", "never assign another class to current character")
        test.eq(M.get(d.root, "forever", 1, "Hero-RealmB"), nil, "ambiguous alias stays intact")
    end
    cases.existing_full_alias = function()
        local d = build()
        M.upsert(d.root, "forever", { realmId = 1, player = "Hero", class = "WARLOCK",
            updatedAt = 10, equipment = { [13] = { link = "item:13", icon = 13 } } })
        M.upsert(d.root, "forever", { realmId = 1, player = "Hero-RealmA", class = "WARLOCK",
            updatedAt = 20, level = 60, equipment = { [16] = { link = "item:16", icon = 16 } } })
        M.migrateShortNames(d.root, "forever", { realmId = 1, player = "Hero-RealmA", class = "WARLOCK" }, "Hero")
        test.eq(#M.list(d.root, "forever"), 1)
        local s = M.get(d.root, "forever", 1, "Hero-RealmA")
        test.eq(s.level, 60)
        test.eq(s.equipment[13].icon, 13)
        test.eq(s.equipment[16].icon, 16)
    end
    cases.link_without_cache = function()
        local slots = A.readEquipment({ GetInventoryItemLink = function(_, slot)
            if slot == 13 or slot == 16 then return "item:" .. slot end
        end, GetItemInfo = function() return nil end })
        test.eq(type(slots), "table", "uncached links survive without GetItemInfoInstant")
        test.eq(slots[13].link, "item:13")
        test.eq(slots[16].link, "item:16")
    end
    cases.partial_equipment = function()
        local root = {}
        M.upsert(root, "forever", { realmId = 1, player = "Hero-RealmA", equipment = {
            [13] = { link = "item:13", icon = 13 }, [16] = { link = "item:16", icon = 16, itemLevel = 60 },
        } })
        M.upsert(root, "forever", { realmId = 1, player = "Hero-RealmA", equipment = { [11] = { link = "item:11" } } })
        local s = M.get(root, "forever", 1, "Hero-RealmA")
        test.eq(s.equipment[16] and s.equipment[16].icon, 16, "full scan cannot erase unobserved weapon")
        M.mergeSections(root, "forever", { realmId = 1, player = "Hero-RealmA",
            equipment = { [16] = { link = "item:16", quality = 4 } } }, { equipment = true })
        s = M.get(root, "forever", 1, "Hero-RealmA")
        test.eq(s.equipment[13].icon, 13)
        test.eq(s.equipment[16].icon, 16, "same item retains cached metadata")
        test.eq(s.equipment[16].quality, 4, "new metadata fills old record")
        M.mergeSections(root, "forever", { realmId = 1, player = "Hero-RealmA",
            equipment = { [16] = { link = "item:99" } } }, { equipment = true })
        s = M.get(root, "forever", 1, "Hero-RealmA")
        test.eq(s.equipment[16].link, "item:99")
        test.eq(s.equipment[16].icon, nil, "new item must not inherit old icon")
    end
    cases.item_event_and_retry = function()
        local d = build()
        local scheduled, registered, handler = {}, {}, nil
        local warm = false
        d.api.GetInventoryItemLink = function(_, slot) if slot == 16 then return "item:16" end end
        d.api.GetItemInfo = function()
            if warm then return "Synthetic", "item:16", 4, 60, nil, nil, nil, nil, nil, 16 end
        end
        d.after = function(delay, fn) scheduled[#scheduled + 1] = { delay = delay, fn = fn } end
        d.frame = {
            RegisterEvent = function(_, event) registered[event] = true end,
            SetScript = function(_, script, fn) if script == "OnEvent" then handler = fn end end,
        }
        R.install(d)
        test.eq(registered.GET_ITEM_INFO_RECEIVED, true, "cache-ready event registered")
        test.eq(#scheduled > 0, true, "initial uncached collection schedules bounded retry")
        warm = true
        handler(d.frame, "GET_ITEM_INFO_RECEIVED", 16, true)
        local pending = scheduled; scheduled = {}
        for _, entry in ipairs(pending) do entry.fn() end
        test.eq(M.get(d.root, "forever", 1, "Hero-RealmA").equipment[16].icon, 16)
    end
    cases.retry_without_event = function()
        local d = build()
        local scheduled, warm, reads = {}, false, 0
        d.api.GetInventoryItemLink = function(_, slot) if slot == 14 then return "item:14" end end
        d.api.GetItemInfo = function()
            reads = reads + 1
            if warm then return "Synthetic", "item:14", 4, 60, nil, nil, nil, nil, nil, 14 end
        end
        d.after = function(_, fn) scheduled[#scheduled + 1] = fn end
        R.collectAndStore(d)
        test.eq(#scheduled > 0, true, "retry works independently of event registration")
        warm = true
        for round = 1, 8 do
            local pending = scheduled; scheduled = {}
            for _, fn in ipairs(pending) do fn() end
        end
        test.eq(M.get(d.root, "forever", 1, "Hero-RealmA").equipment[14].icon, 14)
        test.eq(#scheduled, 0, "retry terminates")
    end
    cases.retry_bounds_and_controls = function()
        local d = build()
        local scheduled, scans = {}, 0
        d.api.GetInventoryItemLink = function(_, slot)
            if slot == 16 then scans = scans + 1; return "item:16" end
        end
        d.after = function(_, fn) scheduled[#scheduled + 1] = fn end
        R.collectAndStore(d)
        for round = 1, 8 do
            local pending = scheduled; scheduled = {}
            for _, fn in ipairs(pending) do fn() end
        end
        test.eq(scans, 4, "initial scan plus at most three retries")
        test.eq(#scheduled, 0)
        R.collectAndStore(d)
        M.clearAll(d.root)
        local pending = scheduled; scheduled = {}
        for _, fn in ipairs(pending) do fn() end
        test.eq(#M.list(d.root, "forever"), 0, "clear cannot be undone by queued retry")
        R.collectAndStore(d)
        d.root.settings = { roleOverviewEnabled = false }
        local before = scans
        pending = scheduled; scheduled = {}
        for _, fn in ipairs(pending) do fn() end
        test.eq(scans, before, "disable prevents queued retry scans")
    end
    cases.onupdate_timer_fallback = function()
        local d = build()
        local scripts, warm = {}, false
        d.api.GetInventoryItemLink = function(_, slot) if slot == 16 then return "item:16" end end
        d.api.GetItemInfo = function()
            if warm then return "Synthetic", "item:16", 4, 60, nil, nil, nil, nil, nil, 16 end
        end
        d.frame = { SetScript = function(_, name, fn) scripts[name] = fn end }
        R.collectAndStore(d)
        test.eq(type(scripts.OnUpdate), "function", "no C_Timer still gets a frame-based delay")
        warm = true
        scripts.OnUpdate(d.frame, 2)
        test.eq(M.get(d.root, "forever", 1, "Hero-RealmA").equipment[16].icon, 16)
        test.eq(scripts.OnUpdate, nil, "frame fallback stops after completion")
    end
    local failures = {}
    for name, run in pairs(cases) do
        local ok, err = pcall(run)
        if not ok then failures[#failures + 1] = name .. ": " .. tostring(err) end
    end
    test.eq(#failures, 0, table.concat(failures, "\n"))
end
