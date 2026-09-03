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

    local function retailStates(savedInstances, extra)
        local overrides = {
            GetNumSavedInstances = function() return #savedInstances end,
            GetSavedInstanceInfo = function(index) return unpack(savedInstances[index]) end,
        }
        for key, value in pairs(extra or {}) do
            if value == false then overrides[key] = nil else overrides[key] = value end
        end
        return Adapters.readers("retail", api(overrides), retailColumns, retailCatalog.resourceColumns).raidStates()
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
    test.eq(dr.completed, nil, "a full aggregate count never claims completion without a per-boss list")

    -- 2. LFR alone is a complete difficulty, never dropped or mislabelled.
    local lfrOnly = retailStates({ row(2939, 17, 4, 4) })
    test.eq(lfrOnly.DR.difficultyLabel, "LFR", "an LFR-only lockout keeps its label")
    test.eq(lfrOnly.DR.difficulty, 17, "an LFR-only lockout keeps its difficulty ID")
    test.eq(lfrOnly.DR.completedParts, 4, "an LFR-only lockout keeps its killed count")
    test.eq(lfrOnly.DR.completed, nil, "an LFR-only full count without per-boss detail never claims completion")
    test.eq(#lfrOnly.DR.difficulties, 1, "an LFR-only lockout has exactly one difficulty")

    -- 3. A full Normal clear must not be hidden by a fresh empty Heroic lockout.
    local fullNormal = retailStates({
        row(2939, 14, 6, 6),  -- Normal 6/6
        row(2939, 15, 6, 0),  -- Heroic 0/6
    })
    local dn = fullNormal.DR
    test.eq(dn.difficultyLabel, "N", "a full normal clear is not hidden by an empty heroic lockout")
    test.eq(dn.completed, nil, "a full normal count without per-boss detail never claims completion")
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
    test.eq(full.DR.completed, nil, "a full clear without per-boss detail never claims completion")
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

    -- 8. Per-boss detail comes from the real retail saved-instance encounter API
    --    GetSavedInstanceEncounterInfo(instanceIndex, encounterIndex) ->
    --    (bossName, fileDataID, isKilled, unknown4). Each difficulty keeps its
    --    own {name, killed} list from that boss's isKilled flag, never the
    --    "first N killed" aggregate or the encounter-journal ordering.
    local bossKills = retailStates({ row(2939, 16, 2, 2) }, {
        GetSavedInstanceEncounterInfo = function(index, encounterIndex)
            if encounterIndex == 1 then return "首王", 111, false, false end
            return "次王", 222, true, false
        end,
    })
    local bosses = bossKills.DR.difficulties[1].encounters
    test.eq(type(bosses), "table", "per-boss detail is stored per difficulty")
    test.eq(#bosses, 2, "every boss in the saved instance is listed")
    test.eq(bosses[1].name, "首王", "boss 1 keeps its localized name")
    test.eq(bosses[1].killed, false, "boss 1 not killed is recorded, not fabricated as killed")
    test.eq(bosses[2].name, "次王", "boss 2 keeps its localized name")
    test.eq(bosses[2].killed, true, "boss 2 killed is recorded from its own flag")
    test.eq(bosses[2].fileDataID, nil, "the texture id is never stored")
    test.eq(bosses[2].unknown4, nil, "the unknown fourth return is never stored")

    -- A non-prefix kill: boss 1 skipped, boss 2 killed must never become "first
    -- 2 killed". The killed count is the number of true flags, never the
    -- farthest-reached encounter index.
    local nonPrefix = retailStates({ row(2939, 15, 3, 2) }, {
        GetSavedInstanceEncounterInfo = function(index, encounterIndex)
            local names = { "一王", "二王", "三王" }
            local killed = { false, true, false }
            return names[encounterIndex], nil, killed[encounterIndex], false
        end,
    })
    local nb = nonPrefix.DR.difficulties[1].encounters
    test.eq(#nb, 3, "all three bosses are listed")
    test.eq(nb[1].killed, false, "boss 1 is not killed")
    test.eq(nb[2].killed, true, "boss 2 is killed")
    test.eq(nb[3].killed, false, "boss 3 is not killed")
    test.eq(nonPrefix.DR.difficulties[1].completedParts, 1,
        "the killed count is the number of true flags, not the farthest index")
    test.eq(nonPrefix.DR.difficulties[1].totalParts, 3,
        "the total stays the reliable encounter count")
    test.eq(nonPrefix.DR.completed, nil, "a non-prefix kill is incomplete")

    -- A kill past a skipped boss: boss 3 killed, bosses 1-2 not, and the
    -- aggregate farthest index is 3. The summary must count the one killed boss,
    -- never the farthest index 3, and must never complete.
    local tailOnly = retailStates({ row(2939, 16, 3, 3) }, {
        GetSavedInstanceEncounterInfo = function(index, encounterIndex)
            local names = { "一王", "二王", "三王" }
            local killed = { false, false, true }
            return names[encounterIndex], nil, killed[encounterIndex], false
        end,
    })
    local tDiff = tailOnly.DR.difficulties[1]
    test.eq(#tDiff.encounters, 3, "all three bosses are listed")
    test.eq(tDiff.encounters[1].killed, false, "boss 1 is not killed")
    test.eq(tDiff.encounters[2].killed, false, "boss 2 is not killed")
    test.eq(tDiff.encounters[3].killed, true, "only boss 3 is killed")
    test.eq(tDiff.completedParts, 1, "the killed count is 1, not the farthest index 3")
    test.eq(tDiff.totalParts, 3, "the total is the reliable encounter count")
    test.eq(tailOnly.DR.completedParts, 1, "the representative carries the killed count")
    test.eq(tailOnly.DR.completed, nil, "farthest index 3 never completes the raid")

    -- Two killed bosses out of three is 2/3, never 3/3 from the farthest index.
    local middleKill = retailStates({ row(2939, 15, 3, 3) }, {
        GetSavedInstanceEncounterInfo = function(index, encounterIndex)
            local names = { "一王", "二王", "三王" }
            local killed = { true, false, true }
            return names[encounterIndex], nil, killed[encounterIndex], false
        end,
    })
    local mDiff = middleKill.DR.difficulties[1]
    test.eq(mDiff.completedParts, 2, "two killed bosses are counted")
    test.eq(mDiff.totalParts, 3, "the total stays the reliable encounter count")
    test.eq(middleKill.DR.completed, nil, "two of three kills is incomplete")

    -- Every boss killed is a reliable full clear.
    local allKilled = retailStates({ row(2939, 14, 3, 3) }, {
        GetSavedInstanceEncounterInfo = function(index, encounterIndex)
            local names = { "一王", "二王", "三王" }
            local killed = { true, true, true }
            return names[encounterIndex], nil, killed[encounterIndex], false
        end,
    })
    local aDiff = allKilled.DR.difficulties[1]
    test.eq(aDiff.completedParts, 3, "three killed bosses are counted")
    test.eq(aDiff.totalParts, 3, "the total is the reliable encounter count")
    test.eq(allKilled.DR.completed, true, "every boss killed completes the raid")

    -- An abnormal second boss tuple fails the whole per-boss list closed and must
    -- never fabricate a prefix kill or claim completion from the aggregate
    -- farthest index.
    local abnormalMiddle = retailStates({ row(2939, 16, 3, 3) }, {
        GetSavedInstanceEncounterInfo = function(index, encounterIndex)
            if encounterIndex == 2 then return nil, nil, true, false end
            return "首王", nil, true, false
        end,
    })
    test.eq(abnormalMiddle.DR.difficulties[1].encounters, nil,
        "an abnormal second boss tuple drops the whole per-boss list")
    test.eq(abnormalMiddle.DR.completedParts, 3, "the degraded aggregate pair still renders")
    test.eq(abnormalMiddle.DR.completed, nil,
        "the farthest index never claims completion when the per-boss list failed")

    -- Normal and Mythic lockouts on the same instance read their own killed sets
    -- and never share or merge a kill count.
    local splitDiff = retailStates({
        row(2939, 14, 3, 3),  -- Normal
        row(2939, 16, 3, 3),  -- Mythic
    }, {
        GetSavedInstanceEncounterInfo = function(index, encounterIndex)
            local names = { "一王", "二王", "三王" }
            local killedByRow = {
                { true, true, false },   -- Normal: 2/3
                { false, false, true },  -- Mythic: 1/3
            }
            return names[encounterIndex], nil, killedByRow[index][encounterIndex], false
        end,
    })
    local sNormal = splitDiff.DR.difficulties[1]
    local sMythic = splitDiff.DR.difficulties[2]
    test.eq(sNormal.difficultyLabel, "N", "normal ranks first")
    test.eq(sNormal.completedParts, 2, "normal killed count is isolated from mythic")
    test.eq(sMythic.difficultyLabel, "M", "mythic ranks after normal")
    test.eq(sMythic.completedParts, 1, "mythic killed count is isolated from normal")
    test.eq(splitDiff.DR.difficultyLabel, "M", "the representative is the highest difficulty with progress")
    test.eq(splitDiff.DR.completedParts, 1, "the representative carries the mythic killed count")
    test.eq(splitDiff.DR.completed, nil, "neither difficulty is fully cleared")

    -- Fail closed: a missing encounter API stores no per-boss list, only the
    -- reliable aggregate count.
    local noEncounterApi = retailStates({ row(2939, 16, 3, 1) })
    test.eq(noEncounterApi.DR.difficulties[1].encounters, nil,
        "a missing encounter API stores no per-boss list")
    test.eq(noEncounterApi.DR.completedParts, 1, "the degraded aggregate pair still renders")

    -- Fail closed: an abnormal tuple (non-boolean kill flag or missing name)
    -- leaves the whole per-boss list absent, never a fabricated boss state.
    local abnormalKilled = retailStates({ row(2939, 16, 3, 1) }, {
        GetSavedInstanceEncounterInfo = function(index, encounterIndex)
            return "首王", nil, (encounterIndex == 1 and "yes" or true), false
        end,
    })
    test.eq(abnormalKilled.DR.difficulties[1].encounters, nil,
        "a non-boolean kill flag fails the whole per-boss list closed")
    test.eq(abnormalKilled.DR.completedParts, 1, "the aggregate count survives an abnormal boss tuple")
    local missingName = retailStates({ row(2939, 16, 3, 1) }, {
        GetSavedInstanceEncounterInfo = function(index, encounterIndex)
            return nil, nil, true, false
        end,
    })
    test.eq(missingName.DR.difficulties[1].encounters, nil,
        "an unnameable boss fails the per-boss list closed")

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
    test.eq(noJournal.DR.encounters, nil, "no root-level per-boss list is ever fabricated")
end
