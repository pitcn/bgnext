return function(test)
    local init
    BG = { IsForever = true, realmID = 1, BGNext = {},
        Init = function(callback) init = callback end }
    local life = dofile("Core/BGNext/DataLifecycle.lua")
    local M = dofile("Core/BGNext/OwnCharacters.lua")
    local function snapshot(name, realm)
        return { player = name, realmId = realm or 1, level = 17,
            raidStates = { MC = { completed = true } } }
    end
    local function filter()
        return { profiles = {}, order = {} }
    end
    local lock, pal, alias = snapshot("pit lock"), snapshot("pit pal"), snapshot("Pit-Lock")
    local validFilter, oldFilter = filter(), filter()
    local root = {
        settings = { roleOverviewEnabled = false },
        ownCharacters = {
            forever = { [1] = { ["pit lock"] = lock, ["pit pal"] = pal, Pit = snapshot("Pit") },
                [2] = { ["Pit-Lock"] = alias, Old = snapshot("Old", 2) } },
            vanilla = { [3] = { Pit = snapshot("Pit", 3) } },
            tbc = { [4] = { Pit = snapshot("Pit", 4) } },
            wrath = { [5] = { Pit = snapshot("Pit", 5) } },
        },
        roleOverviewCharacterOrder = {
            forever = { { realmId = 1, player = "Pit" }, { realmId = 1, player = "pit pal" },
                { realmId = 1, player = "pit lock" }, { realmId = 2, player = "Pit-Lock" },
                { realmId = 6, player = "Orphan" } },
            vanilla = { { realmId = 3, player = "Pit" } },
        },
        equipmentFilters = {
            [1] = { Pit = oldFilter, ["pit lock"] = validFilter, ["pit pal"] = filter(),
                schemaVersion = 1, metadata = { enabled = true }, Orphan = filter() },
            [2] = { Old = filter(), ["Pit-Lock"] = validFilter },
            [3] = { Pit = oldFilter }, [6] = { Orphan = filter() },
            [7] = { Unscoped = oldFilter },
        },
    }
    BiaoGe = { BGNext = root }
    GetServerTime = function() return 100 end
    -- Exercise the real login callback, even with collection disabled and no name API.
    init()
    test.eq(root.ownCharacters.forever[1].Pit, nil, "login discards illegal Forever short snapshot")
    local count = 0
    for _ in pairs(root.ownCharacters.forever[1]) do count = count + 1 end
    test.eq(count, 2, "the affected realm contains exactly the two complete names")
    test.eq(#M.list(root, "forever"), 3, "only complete identities remain across two Forever realms")
    test.eq(root.ownCharacters.forever[1]["pit lock"], lock, "no legacy snapshot merged into Lock")
    test.eq(lock.raidStates.MC.completed, true, "valid completion snapshot preserved")
    test.eq(root.ownCharacters.forever[1]["pit pal"], pal, "Pal untouched")
    test.eq(root.ownCharacters.forever[2]["Pit-Lock"], alias, "hyphen alias survives cleanup")
    test.eq(root.ownCharacters.forever[2].Old, nil)
    test.eq(#root.roleOverviewCharacterOrder.forever, 3, "short and orphan sort references removed")
    test.eq(root.roleOverviewCharacterOrder.forever[1].player, "pit pal", "valid ordering retained")
    test.eq(root.equipmentFilters[1].Pit, nil)
    test.eq(root.equipmentFilters[1].Orphan, nil, "current Forever realm filter-only key removed")
    test.eq(root.equipmentFilters[6].Orphan, nil, "sort-only Forever identity cleaned")
    test.eq(root.equipmentFilters[2].Old, nil)
    test.eq(root.equipmentFilters[1]["pit lock"], validFilter, "complete filter profiles preserved")
    test.eq(root.equipmentFilters[2]["Pit-Lock"], validFilter)
    test.eq(root.equipmentFilters[1].schemaVersion, 1, "field name is not a character")
    test.eq(root.equipmentFilters[1].metadata.enabled, true)
    for family, realm in pairs({ vanilla = 3, tbc = 4, wrath = 5 }) do
        test.eq(root.ownCharacters[family][realm].Pit.player, "Pit", "other family short names preserved")
    end
    test.eq(root.roleOverviewCharacterOrder.vanilla[1].player, "Pit")
    test.eq(root.equipmentFilters[3].Pit, oldFilter, "unrelated realm not scanned")
    test.eq(root.equipmentFilters[7].Unscoped, oldFilter)
    life.ensureRoot(BiaoGe)
    test.eq(#M.list(root, "forever"), 3, "repeat loading is idempotent")
    -- A non-Forever load must not invoke the migration, even with a stray Forever subtree.
    BG.IsForever = false
    root.ownCharacters.forever[1].Pit = snapshot("Pit")
    root.equipmentFilters[1].Pit = oldFilter
    life.ensureRoot(BiaoGe)
    test.eq(root.ownCharacters.forever[1].Pit.player, "Pit", "non-Forever save remains untouched")
    test.eq(root.equipmentFilters[1].Pit, oldFilter)
end
