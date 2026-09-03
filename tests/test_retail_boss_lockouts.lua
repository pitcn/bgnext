return function(test)
    BG = { BGNext = {} }
    local Adapters = dofile("Core/BGNext/OwnCharactersAdapters.lua")
    local Catalog = dofile("Core/BGNext/OwnCharactersCatalog.lua")

    local retailCatalog = Catalog.forFamily("retail")
    local retailColumns = retailCatalog.raidColumns

    local function api(overrides)
        local base = {
            time = function() return 5000 end,
            UnitName = function() return "Piti" end,
            GetRealmID = function() return 123 end,
            GetRealmName = function() return "时光" end,
            UnitFactionGroup = function() return "Alliance" end,
            UnitClass = function() return "猎人", "HUNTER" end,
            UnitLevel = function() return 80 end,
            GetAverageItemLevel = function() return 230, 231 end,
            GetMoney = function() return 0 end,
            UnitHonor = function() return 0 end,
            GetInventoryItemLink = function() return nil end,
            GetNumSavedInstances = function() return 0 end,
        }
        for key, value in pairs(overrides or {}) do
            if value == false then base[key] = nil else base[key] = value end
        end
        return base
    end

    -- GetSavedInstanceInfo tuple: name, lockoutId, reset, difficulty, locked,
    -- extended, mostSig, isRaid, maxPlayers, difficultyName, numEncounters,
    -- encounterProgress, _, instanceId.
    local function row(instanceId, difficulty, numEncounters, encounterProgress, reset)
        return { "梦境裂隙", 900000 + difficulty, reset or 3600, difficulty, true, false, 1, true,
            20, "难度", numEncounters, encounterProgress, nil, instanceId }
    end

    local function retailStates(savedInstances, encounterJournal)
        return Adapters.readers("retail", api({
            GetNumSavedInstances = function() return #savedInstances end,
            GetSavedInstanceInfo = function(index) return unpack(savedInstances[index]) end,
            C_EncounterJournal = encounterJournal,
        }), retailColumns, retailCatalog.resourceColumns).raidStates()
    end

    -- 1. Per-difficulty non-merge: N/H/M stay separate and the representative
    --    is the highest difficulty carrying progress.
    local states = retailStates({
        row(2939, 14, 6, 6),  -- Normal 6/6
        row(2939, 15, 6, 3),  -- Heroic 3/6
        row(2939, 16, 6, 6),  -- Mythic 6/6
    })
    local dr = states.DR
    test.eq(dr ~= nil, true, "a retail raid maps to its column")
    test.eq(type(dr.difficulties), "table", "retail keeps a per-difficulty breakdown")
    test.eq(#dr.difficulties, 3, "three difficulties are tracked without merging")
    test.eq(dr.difficulties[1].difficultyLabel, "N", "normal difficulty is tracked")
    test.eq(dr.difficulties[1].completedParts, 6, "normal killed count is tracked")
    test.eq(dr.difficulties[1].totalParts, 6, "normal boss total comes from the lockout")
    test.eq(dr.difficulties[2].difficultyLabel, "H", "heroic difficulty is tracked")
    test.eq(dr.difficulties[2].completedParts, 3, "heroic partial count is tracked")
    test.eq(dr.difficulties[2].totalParts, 6, "heroic boss total comes from the lockout")
    test.eq(dr.difficulties[3].difficultyLabel, "M", "mythic difficulty is tracked")
    test.eq(dr.difficultyLabel, "M", "representative is the highest difficulty with progress")
    test.eq(dr.completedParts, 6, "representative killed count is the mythic count")
    test.eq(dr.totalParts, 6, "representative total is the boss count, not the instance grouping")
    test.eq(dr.completed, true, "a full mythic clear completes the raid")

    -- 2. A full Normal clear must not be hidden by a fresh empty Heroic lockout.
    local fullNormal = retailStates({
        row(2939, 14, 6, 6),  -- Normal 6/6
        row(2939, 15, 6, 0),  -- Heroic 0/6
    })
    local dn = fullNormal.DR
    test.eq(dn.difficultyLabel, "N", "a full normal clear is not hidden by an empty heroic lockout")
    test.eq(dn.completed, true, "the full normal clear completes the raid")
    test.eq(dn.totalParts, 6, "total bosses come from the lockout, not the instance grouping")

    -- 3. 0/N: a fresh lockout with no kills is partial, never complete.
    local zero = retailStates({ row(2939, 16, 6, 0) })
    test.eq(zero.DR.completedParts, 0, "zero kills are recorded as zero")
    test.eq(zero.DR.totalParts, 6, "the boss total is recorded")
    test.eq(zero.DR.completed, nil, "zero kills never complete the raid")
    test.eq(zero.DR.difficultyLabel, "M", "a fresh mythic lockout keeps its label")

    -- 4. X/N: a partial clear is partial, never complete.
    local partial = retailStates({ row(2939, 15, 6, 3) })
    test.eq(partial.DR.completedParts, 3, "a partial kill count is recorded")
    test.eq(partial.DR.totalParts, 6, "the partial boss total is recorded")
    test.eq(partial.DR.completed, nil, "a partial clear never completes the raid")
    test.eq(partial.DR.difficultyLabel, "H", "a partial heroic lockout keeps its label")

    -- 5. N/N: a full clear completes the raid.
    local full = retailStates({ row(2939, 14, 6, 6) })
    test.eq(full.DR.completed, true, "a full clear completes the raid")
    test.eq(full.DR.difficultyLabel, "N", "a full normal clear keeps its label")

    -- 6. Per-boss encounters read from the encounter journal carry a done flag.
    local withEncounters = retailStates({ row(2939, 16, 3, 1) }, {
        GetEncountersOnMap = function(instanceId) return { 1001, 1002, 1003 } end,
        GetEncounterInfo = function(id) return { name = "首王" .. tostring(id) } end,
    })
    local enc = withEncounters.DR.encounters
    test.eq(type(enc), "table", "encounters are read from the journal")
    test.eq(#enc, 3, "every boss is listed")
    test.eq(enc[1].done, true, "the first killed boss is marked done")
    test.eq(enc[2].done, false, "a not-yet-killed boss is marked not done")
    test.eq(enc[1].name, "首王1001", "the boss name is read from the journal")

    -- 7. Missing or failing APIs degrade to nil, never a fabricated zero.
    test.eq(retailStates({}), nil, "no saved instances means no raid state")
    test.eq(Adapters.readers("retail", api({ GetNumSavedInstances = false }),
        retailColumns, retailCatalog.resourceColumns).raidStates(), nil,
        "a missing saved-instance API yields nil")
    local noJournal = retailStates({ row(2939, 16, 6, 3) })
    test.eq(noJournal.DR.encounters, nil, "a missing journal API stores no per-boss list")
end
