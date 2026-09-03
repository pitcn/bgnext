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
    local function row(instanceId, difficulty, numEncounters, encounterProgress, reset, name)
        return { name or "梦境裂隙", 900000 + difficulty, reset or 3600, difficulty, true, false, 1, true,
            20, "难度", numEncounters, encounterProgress, nil, instanceId }
    end

    local function retailStates(savedInstances, encounterJournal)
        return Adapters.readers("retail", api({
            GetNumSavedInstances = function() return #savedInstances end,
            GetSavedInstanceInfo = function(index) return unpack(savedInstances[index]) end,
            C_EncounterJournal = encounterJournal,
        }), retailColumns, retailCatalog.resourceColumns).raidStates()
    end

    -- 1. LFR + N/H/M coexist: every difficulty (14/15/16/17) is isolated, each
    --    keeps its own count and label, and the representative stays the highest
    --    difficulty carrying progress.
    local states = retailStates({
        row(2939, 14, 6, 6),  -- Normal 6/6
        row(2939, 15, 6, 3),  -- Heroic 3/6
        row(2939, 16, 6, 6),  -- Mythic 6/6
        row(2939, 17, 4, 4),  -- LFR 4/4
    })
    local dr = states.DR
    test.eq(dr ~= nil, true, "a retail raid maps to its column")
    test.eq(type(dr.difficulties), "table", "retail keeps a per-difficulty breakdown")
    test.eq(#dr.difficulties, 4, "LFR, Normal, Heroic and Mythic are tracked without merging")
    test.eq(dr.difficulties[1].difficultyLabel, "LFR", "raid finder is tracked and labelled")
    test.eq(dr.difficulties[1].difficulty, 17, "raid finder keeps its difficulty ID")
    test.eq(dr.difficulties[1].completedParts, 4, "raid finder killed count is tracked")
    test.eq(dr.difficulties[1].totalParts, 4, "raid finder boss total comes from the lockout")
    test.eq(dr.difficulties[2].difficultyLabel, "N", "normal difficulty is tracked")
    test.eq(dr.difficulties[2].completedParts, 6, "normal killed count is tracked")
    test.eq(dr.difficulties[2].totalParts, 6, "normal boss total comes from the lockout")
    test.eq(dr.difficulties[3].difficultyLabel, "H", "heroic difficulty is tracked")
    test.eq(dr.difficulties[3].completedParts, 3, "heroic partial count is tracked")
    test.eq(dr.difficulties[3].totalParts, 6, "heroic boss total comes from the lockout")
    test.eq(dr.difficulties[4].difficultyLabel, "M", "mythic difficulty is tracked")
    test.eq(dr.difficultyLabel, "M", "representative is the highest difficulty with progress")
    test.eq(dr.completedParts, 6, "representative killed count is the mythic count")
    test.eq(dr.totalParts, 6, "representative total is the boss count, not the instance grouping")
    test.eq(dr.completed, true, "a full mythic clear completes the raid")

    -- 2. LFR alone is a complete difficulty, never dropped or mislabelled.
    local lfrOnly = retailStates({ row(2939, 17, 4, 4) })
    test.eq(lfrOnly.DR.difficultyLabel, "LFR", "an LFR-only lockout keeps its label")
    test.eq(lfrOnly.DR.difficulty, 17, "an LFR-only lockout keeps its difficulty ID")
    test.eq(lfrOnly.DR.completedParts, 4, "an LFR-only lockout keeps its killed count")
    test.eq(lfrOnly.DR.completed, true, "a full LFR clear completes the raid")
    test.eq(#lfrOnly.DR.difficulties, 1, "an LFR-only lockout has exactly one difficulty")

    -- 3. A full Normal clear must not be hidden by a fresh empty Heroic lockout.
    local fullNormal = retailStates({
        row(2939, 14, 6, 6),  -- Normal 6/6
        row(2939, 15, 6, 0),  -- Heroic 0/6
    })
    local dn = fullNormal.DR
    test.eq(dn.difficultyLabel, "N", "a full normal clear is not hidden by an empty heroic lockout")
    test.eq(dn.completed, true, "the full normal clear completes the raid")
    test.eq(dn.totalParts, 6, "total bosses come from the lockout, not the instance grouping")

    -- 4. 0/N: a fresh lockout with no kills is partial, never complete.
    local zero = retailStates({ row(2939, 16, 6, 0) })
    test.eq(zero.DR.completedParts, 0, "zero kills are recorded as zero")
    test.eq(zero.DR.totalParts, 6, "the boss total is recorded")
    test.eq(zero.DR.completed, nil, "zero kills never complete the raid")
    test.eq(zero.DR.difficultyLabel, "M", "a fresh mythic lockout keeps its label")

    -- 5. X/N: a partial clear is partial, never complete.
    local partial = retailStates({ row(2939, 15, 6, 3) })
    test.eq(partial.DR.completedParts, 3, "a partial kill count is recorded")
    test.eq(partial.DR.totalParts, 6, "the partial boss total is recorded")
    test.eq(partial.DR.completed, nil, "a partial clear never completes the raid")
    test.eq(partial.DR.difficultyLabel, "H", "a partial heroic lockout keeps its label")

    -- 6. N/N: a full clear completes the raid.
    local full = retailStates({ row(2939, 14, 6, 6) })
    test.eq(full.DR.completed, true, "a full clear completes the raid")
    test.eq(full.DR.difficultyLabel, "N", "a full normal clear keeps its label")

    -- 7. Abnormal or partial tuples leave the difficulty blank, never a
    --    fabricated 0/N. numEncounters and encounterProgress are one pair.
    test.eq(retailStates({ row(2939, 16, 6, nil) }), nil,
        "a missing progress never fabricates a 0/N state")
    test.eq(retailStates({ row(2939, 16, nil, 3) }), nil,
        "a missing boss total never fabricates a state")
    test.eq(retailStates({ row(2939, 16, 6, 7) }), nil,
        "progress above the boss total leaves the difficulty blank")
    test.eq(retailStates({ row(2939, 16, 6, -1) }), nil,
        "negative progress leaves the difficulty blank")
    test.eq(retailStates({ row(2939, 16, 0, 0) }), nil,
        "an unusable zero boss total leaves the difficulty blank")
    local mixedBlank = retailStates({
        row(2939, 16, 6, 3),   -- valid Mythic 3/6
        row(2939, 17, 4, nil), -- malformed LFR
    })
    test.eq(mixedBlank.DR ~= nil, true, "a valid difficulty still survives beside a malformed one")
    test.eq(#mixedBlank.DR.difficulties, 1, "the malformed LFR is absent, not a fabricated 0/4")
    test.eq(mixedBlank.DR.difficulties[1].difficultyLabel, "M", "the surviving difficulty is the valid Mythic")

    -- 8. Per-boss detail fails closed: the encounter journal is never read from a
    --    saved-instance kill count. GetEncountersOnMap returns
    --    EncounterJournalMapEncounterInfo records ({encounterID, mapX, mapY}) and
    --    needs a uiMapID the saved-instance tuple does not expose, so no per-boss
    --    list is reconstructed and no first-N-killed fabrication is possible.
    local withJournal = retailStates({ row(2939, 16, 3, 1) }, {
        GetEncountersOnMap = function(mapID)
            return { { encounterID = 1001, mapX = 0, mapY = 0 }, { encounterID = 1002, mapX = 1, mapY = 1 } }
        end,
        GetEncounterInfo = function(id) return { name = "首王" .. tostring(id) } end,
        IsEncounterComplete = function(id) return id == 1001 end,
    })
    test.eq(withJournal.DR.encounters, nil,
        "the real record-tuple journal shape produces no fabricated per-boss list")
    test.eq(withJournal.DR.completedParts, 1, "the aggregate kill count still renders")
    local numericArrayJournal = retailStates({ row(2939, 16, 3, 1) }, {
        GetEncountersOnMap = function(mapID) return { 1001, 1002, 1003 } end,
        GetEncounterInfo = function(id) return { name = "首王" .. tostring(id) } end,
    })
    test.eq(numericArrayJournal.DR.encounters, nil,
        "a numeric-array journal no longer fabricates a first-N-killed list")

    -- 9. Two saved instances that share a name stay independent: the mapping is
    --    by instanceId, never by display name.
    local sameName = retailStates({
        row(2939, 16, 6, 6, 3600, "梦境裂隙"), -- DR
        row(2913, 15, 6, 3, 3600, "梦境裂隙"), -- MQD, same display name
    })
    test.eq(sameName.DR ~= nil, true, "the first same-name instance maps to its own column")
    test.eq(sameName.MQD ~= nil, true, "the second same-name instance maps to its own column")
    test.eq(sameName.DR.difficultyLabel, "M", "DR keeps its own difficulty")
    test.eq(sameName.MQD.difficultyLabel, "H", "MQD keeps its own difficulty")
    test.eq(sameName.MQD.completedParts, 3, "MQD progress is not polluted by DR")

    -- 10. Each difficulty expires on its own reset; the column keeps the nearest
    --     reset, not the representative's.
    local independentResets = retailStates({
        row(2939, 14, 6, 6, 600),   -- Normal 6/6, resets in 600s -> 5600
        row(2939, 16, 6, 3, 3600),  -- Mythic 3/6, resets in 3600s -> 8600
    })
    test.eq(independentResets.DR.difficulties[1].resetsAt, 5600, "normal keeps its own reset")
    test.eq(independentResets.DR.difficulties[2].resetsAt, 8600, "mythic keeps its own reset")
    test.eq(independentResets.DR.resetsAt, 5600, "column reset is the nearest difficulty reset")

    -- 11. Missing or failing APIs degrade to nil, never a fabricated zero.
    test.eq(retailStates({}), nil, "no saved instances means no raid state")
    test.eq(Adapters.readers("retail", api({ GetNumSavedInstances = false }),
        retailColumns, retailCatalog.resourceColumns).raidStates(), nil,
        "a missing saved-instance API yields nil")
    local noJournal = retailStates({ row(2939, 16, 6, 3) })
    test.eq(noJournal.DR.encounters, nil, "a missing journal API stores no per-boss list")
end
