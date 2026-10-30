return function(test)
    BG = { BGNext = {} }
    local Adapters = dofile("Core/BGNext/OwnCharactersAdapters.lua")
    local Catalog = dofile("Core/BGNext/OwnCharactersCatalog.lua")
    local catalog = Catalog.forFamily("titan")
    local columns = {}
    for _, column in ipairs(catalog.resourceColumns) do columns[column.id] = column end
    for _, key in ipairs({ "fishingDaily", "jewelcraftingDaily", "cookingDaily" }) do
        test.eq(type(columns[key]), "table", "Titan exposes " .. key)
        test.eq(columns[key].defaultVisible, true, "daily status is initially visible")
    end
    local completed = { [13830] = true, [12963] = true, [13107] = true }
    local api = {
        time = function() return 1000 end,
        GetQuestResetTime = function() return 500 end,
        UnitFactionGroup = function(unit) test.eq(unit, "player"); return "Alliance" end,
        GetProfessions = function() return 1, nil, nil, 4, 5, nil end,
        GetProfessionInfo = function(index)
            return "Profession", 134400, 450, 450, 0, 0, ({ [1] = 755, [4] = 356, [5] = 185 })[index]
        end,
        C_QuestLog = { IsQuestFlaggedCompleted = function(id) return completed[id] == true end },
    }
    local states = Adapters.readActivityStates(api, "titan", catalog.resourceColumns)
    for _, key in ipairs({ "fishingDaily", "jewelcraftingDaily", "cookingDaily" }) do
        test.eq(states[key].status, "completed", "a completed quest proves today's " .. key)
        test.eq(states[key].resetsAt, 1500, "daily status expires at the server reset")
        test.eq(states[key].observedAt, 1000, "only the latest observation is recorded")
    end
    for key, ids in pairs({
        fishingDaily = { 13830, 13832, 13833, 13834, 13836 },
        jewelcraftingDaily = { 12958, 12959, 12960, 12961, 12962, 12963 },
        cookingDaily = { 13100, 13101, 13102, 13103, 13107 },
    }) do
        for _, id in ipairs(ids) do
            completed = { [id] = true }
            test.eq(Adapters.readActivityStates(api, "titan", catalog.resourceColumns)[key].status,
                "completed", "quest " .. id .. " is accepted in its daily group")
        end
    end
    api.UnitFactionGroup = function() return "Horde" end
    for _, id in ipairs({ 13112, 13113, 13114, 13115, 13116 }) do
        completed = { [id] = true }
        test.eq(Adapters.readActivityStates(api, "titan", catalog.resourceColumns).cookingDaily.status,
            "completed", "Horde quest " .. id .. " is recognized")
    end
    completed = { [13107] = true }
    test.eq(Adapters.readActivityStates(api, "titan", catalog.resourceColumns).cookingDaily.status,
        "incomplete", "the other faction never completes today's cooking daily")
    api.UnitFactionGroup = function() return nil end
    test.eq(Adapters.readActivityStates(api, "titan", catalog.resourceColumns).cookingDaily.status,
        "unknown", "unknown faction is not guessed")
    api.UnitFactionGroup = function() return "Alliance" end
    local modernProfessions = api.GetProfessions
    api.GetProfessions = function() return 1, nil, nil, nil, nil, nil end
    states = Adapters.readActivityStates(api, "titan", catalog.resourceColumns)
    test.eq(states.fishingDaily.status, "not-applicable", "reliably unlearned fishing is not unfinished")
    test.eq(states.cookingDaily.status, "not-applicable", "secondary skills are checked independently")
    api.GetProfessions = function() return 1 end
    test.eq(Adapters.readActivityStates(api, "titan", catalog.resourceColumns).fishingDaily.status,
        "unknown", "a short profession tuple cannot prove secondary-skill absence")
    api.GetProfessions = function() return nil end
    api.GetNumSkillLines = function() return 3 end
    api.GetSkillLineInfo = function(index) return ({ "钓鱼", "烹饪", "珠宝加工" })[index], false end
    api.GetSpellInfo = function(id) return ({ [7620] = "钓鱼", [2550] = "烹饪", [25229] = "珠宝加工" })[id] end
    completed = { [13830] = true, [12963] = true, [13107] = true }
    states = Adapters.readActivityStates(api, "titan", catalog.resourceColumns)
    test.eq(states.fishingDaily.status, "completed", "legacy skill-list fishing is recognized")
    test.eq(states.jewelcraftingDaily.status, "completed", "legacy primary skill is recognized")
    test.eq(states.cookingDaily.status, "completed", "legacy skill-list cooking is recognized")
    for variant = 1, 3 do
        api.GetSkillLineInfo = function(index)
            local header
            if variant == 1 then header = false elseif variant == 2 then header = 0 end
            return ({ "钓鱼", "烹饪", "珠宝加工" })[index], header
        end
        test.eq(Adapters.readActivityStates(api, "titan", catalog.resourceColumns).fishingDaily.status,
            "completed", "legacy non-header false/zero/nil encodings remain readable")
    end
    api.GetSkillLineInfo = function(index) return ({ "钓鱼", "烹饪", "珠宝加工" })[index], 1 end
    test.eq(Adapters.readActivityStates(api, "titan", catalog.resourceColumns).fishingDaily.status,
        "unknown", "a numeric header flag never proves a learned profession")
    api.GetProfessions, api.GetNumSkillLines, api.GetSkillLineInfo = modernProfessions, nil, nil
    local modernFlag = api.C_QuestLog.IsQuestFlaggedCompleted
    api.C_QuestLog.IsQuestFlaggedCompleted = function(id)
        if id == 13830 then return nil end
        return false
    end
    test.eq(Adapters.readActivityStates(api, "titan", catalog.resourceColumns).fishingDaily.status,
        "unknown", "an incomplete API response is not a reliable unfinished status")
    api.C_QuestLog.IsQuestFlaggedCompleted = function(id)
        if id == 13830 then error("cache unavailable") end
        return id == 13836
    end
    test.eq(Adapters.readActivityStates(api, "titan", catalog.resourceColumns).fishingDaily.status,
        "completed", "one reliable completion is sufficient despite another unreadable quest")
    api.C_QuestLog, api.IsQuestFlaggedCompleted = nil, modernFlag
    test.eq(Adapters.readActivityStates(api, "titan", catalog.resourceColumns).cookingDaily.status,
        "completed", "the legacy completion API works")
    api.IsQuestFlaggedCompleted = function(id) if completed[id] then return 1 end end
    test.eq(Adapters.readActivityStates(api, "titan", catalog.resourceColumns).cookingDaily.status,
        "unknown", "an unverified numeric/nil API contract remains unknown, never guessed")
    api.IsQuestFlaggedCompleted = modernFlag
    test.eq(Adapters.canReadColumn("titan", api, columns.fishingDaily), true,
        "the Titan column is available when the required API surface exists")
    test.eq(Adapters.canReadColumn("wrath", api, columns.fishingDaily), false,
        "column availability never enables unsupported Wrath tracking")
    test.eq(Adapters.canReadColumn("mop", api, columns.fishingDaily), false,
        "Titan daily columns never leak into other client families")
    local resetReader = api.GetQuestResetTime
    api.GetQuestResetTime = nil
    test.eq(Adapters.canReadColumn("titan", api, columns.fishingDaily), false,
        "a missing required reset API hides the unreadable column")
    api.GetQuestResetTime = resetReader
    for _, invalid in ipairs({ 0, -1, math.huge, 0/0, "500" }) do
        api.GetQuestResetTime = function() return invalid end
        test.eq(Adapters.readActivityStates(api, "titan", catalog.resourceColumns).fishingDaily.status,
            "unknown", "invalid or zero reset time never creates an endless completed flag")
    end
    api.GetQuestResetTime = function() return 500 end
    test.eq(Adapters.readActivityStates(api, "wrath", catalog.resourceColumns), nil,
        "the unsupported Wrath overview is not silently enabled")

    -- Real storage/collector/runtime paths: new states must not replace other
    -- sections, and the visible current character re-reads once at reset.
    local Model = dofile("Core/BGNext/OwnCharacters.lua")
    local Collector = dofile("Core/BGNext/OwnCharactersCollector.lua")
    local Runtime = dofile("Core/BGNext/OwnCharactersRuntime.lua")
    local View = dofile("Core/BGNext/OwnCharactersView.lua")
    local now, visible, flagReads = 1000, true, 0
    api.time = function() return now end
    api.UnitName = function(unit) test.eq(unit, "player"); return "Test" end
    api.GetRealmID = function() return 1 end
    api.UnitLevel = function() return 80 end
    api.GetMoney = function() return 987654 end
    api.IsQuestFlaggedCompleted = function(id) flagReads = flagReads + 1; return completed[id] == true end
    local root = {}
    local deps = { family = "titan", catalog = catalog, root = root, api = api,
        adapters = Adapters, collector = Collector, model = Model, now = function() return now end,
        ui = { IsVisible = function() return visible end, Refresh = function() end } }
    Runtime.collectAndStore(deps)
    Model.upsert(root, "titan", { realmId = 1, player = "Offline", level = 80,
        money = 432100, activityStates = { fishingDaily = { status = "completed", resetsAt = 1500 } } })
    now, completed = 1500, {}
    Runtime.refreshVisible(deps)
    local current = Model.get(root, "titan", 1, "Test")
    test.eq(current.activityStates.fishingDaily.status, "incomplete", "current visible character is refreshed at reset")
    test.eq(current.money, 987654, "daily-only reset reads retain recorded gold")
    test.eq(Model.get(root, "titan", 1, "Offline").activityStates.fishingDaily, nil,
        "offline completion is expired without querying that character")
    local readsAfterReset = flagReads
    Runtime.refreshVisible(deps)
    test.eq(flagReads, readsAfterReset, "redrawing within the day does not poll quest APIs")
    local function project()
        return View.project({ family = "titan", catalog = catalog,
            snapshots = { Model.get(root, "titan", 1, "Test"), Model.get(root, "titan", 1, "Offline") },
            currentRealmId = 1, now = now })
    end
    local projected = project()
    local offlineCells = {}
    for _, row in ipairs(projected.resource.rows) do
        if row.player == "Offline" then for _, cell in ipairs(row.cells) do offlineCells[cell.columnId] = cell end end
    end
    test.eq(offlineCells.fishingDaily.text, "?", "expired or unobserved daily cells render unknown")
    visible, now = false, 2000
    Runtime.refreshVisible(deps)
    test.eq(flagReads, readsAfterReset, "hidden windows never trigger a daily API poll")
    visible = true
    Runtime.refreshVisible(deps)
    test.eq(flagReads > readsAfterReset, true, "reopening after reset refreshes the current character")
    Runtime.setEnabled(deps, false)
    local disabledReads = flagReads
    now = 2500
    Runtime.refreshVisible(deps)
    test.eq(flagReads, disabledReads, "disabled overview does not read daily quests")

    Runtime.setEnabled(deps, true)
    local eventHandler, queued, queuedCount = nil, nil, 0
    deps.frame = {
        RegisterEvent = function() end,
        SetScript = function(_, _, handler) eventHandler = handler end,
    }
    deps.after = function(_, callback) queued, queuedCount = callback, queuedCount + 1 end
    Runtime.install(deps)
    local saved = Model.get(root, "titan", 1, "Test")
    saved.currencies = { jewelcraftingToken = 9, cookingToken = 2 }
    completed = { [13832] = true }
    local beforeEventReads = flagReads
    eventHandler(deps.frame, "QUEST_TURNED_IN", 13832)
    eventHandler(deps.frame, "QUEST_LOG_UPDATE")
    test.eq(queuedCount, 1, "quest event bursts are debounced")
    test.eq(flagReads, beforeEventReads, "quest events never read immediately before the debounce")
    queued()
    saved = Model.get(root, "titan", 1, "Test")
    test.eq(saved.activityStates.fishingDaily.status, "completed", "real turn-in event refreshes the own snapshot")
    test.eq(saved.money, 987654, "turn-in keeps existing gold")
    test.eq(saved.currencies.jewelcraftingToken, 9, "turn-in keeps jewelcrafting token quantities")
    test.eq(saved.currencies.cookingToken, 2, "turn-in keeps cooking token quantities")
    for field in pairs(saved.activityStates.fishingDaily) do
        test.eq(field == "status" or field == "observedAt" or field == "resetsAt", true,
            "daily snapshots contain no quest log, quest id or extra metadata")
    end
    api.GetProfessions = function() return nil, nil, nil, nil, nil, nil end
    eventHandler(deps.frame, "SKILL_LINES_CHANGED")
    queued()
    test.eq(Model.get(root, "titan", 1, "Test").activityStates.fishingDaily.status,
        "not-applicable", "profession changes refresh daily eligibility via the real event path")
    api.GetProfessions = modernProfessions
    local getProfessionInfo = api.GetProfessionInfo
    api.GetProfessionInfo = function() return "Invalid", nil, nil, nil, nil, nil, 0 end
    test.eq(Adapters.readActivityStates(api, "titan", catalog.resourceColumns).fishingDaily.status,
        "unknown", "an invalid skill id never proves the profession is unlearned")
    api.GetProfessionInfo = getProfessionInfo
    for _, family in ipairs({ "mop", "titan" }) do
        local handler, observed
        Collector.installEvents({ family = family, frame = {
            RegisterEvent = function() end,
            SetScript = function(_, _, callback) handler = callback end,
        } }, function(sections) observed = sections end)
        handler(nil, "SKILL_LINES_CHANGED")
        test.eq(observed.activities == true, family == "titan",
            "profession changes only add daily reads for the Titan family")
        test.eq(observed.professions, true, "existing profession updates remain active")
    end
end
