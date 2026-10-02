return function(test)
    BG = { BGNext = {} }
    local Catalog = dofile("Core/BGNext/OwnCharactersCatalog.lua")
    local Adapters = dofile("Core/BGNext/OwnCharactersAdapters.lua")
    local column = Catalog.column("titan", "raid", "ULDtitan")
    test.eq(column ~= nil, true, "Titan offers one independent Ulduar CD column")
    if not column then return end
    test.eq(column.source.instanceIds[1], 603, "Ulduar uses its own instance")
    test.eq(#column.source.instanceIds, 1, "Ulduar does not merge other raids")
    test.eq(column.source.maxPlayers, 25, "P6 is restricted to the 25-player raid")
    test.eq(Catalog.defaultVisible("titan", "raid", "ULDtitan"), true,
        "Ulduar is visible by default without changing saved display choices")
    test.eq(Catalog.column("titan", "raid", "10ULD"), nil, "no 10-player Ulduar column")
    test.eq(Catalog.column("titan", "raid", "25ULD"), nil, "no duplicate 25-player column")
    test.eq(Catalog.column("tbc", "raid", "ULDtitan"), nil, "P6 does not leak into TBC")

    local View = dofile("Core/BGNext/OwnCharactersView.lua")
    local view = View.project({
        family = "titan", catalog = Catalog.forFamily("titan"), snapshots = {},
        currentRealmId = 1, showAllRealms = false, now = 10000,
        visibility = { raid = { ULDtitan = false, SWtitan = false } },
    })
    for _, visible in ipairs(view.raid.columns) do
        test.eq(visible.id == "ULDtitan" or visible.id == "SWtitan", false,
            "saved hidden choices still override the new default")
    end

    local api = {
        time = function() return 10000 end,
        GetNumSavedInstances = function() return 3 end,
        GetSavedInstanceInfo = function(index)
            if index == 1 then
                return "Ulduar", 100, 3600, 3, true, false, 0, true, 10, "10", 14, 14, false, 603
            elseif index == 2 then
                return "Ulduar", 101, 7200, 4, true, false, 0, true, 25, "25", 14, 7, false, 603
            end
            return "Sunwell", 102, 1800, 4, true, false, 0, true, 25, "25", 6, 6, false, 580
        end,
    }
    local states = Adapters.readRaidStates(api, Catalog.forFamily("titan").raidColumns, "titan")
    test.eq(states.ULDtitan.progress, 7, "a historical 10-player lock cannot overwrite P6 progress")
    test.eq(states.ULDtitan.total, 14, "boss total comes from the client")
    test.eq(states.ULDtitan.resetsAt, 17200, "P6 keeps its own reset")
    test.eq(states.SWtitan.progress, 6, "old P5 raid progress remains independent")

    api.GetNumSavedInstances = function() return 1 end
    api.GetSavedInstanceInfo = function()
        return "Ulduar", 101, 7200, 4, true, false, 0, true, 25, "25", 14, 14, false, 603
    end
    states = Adapters.readRaidStates(api, { column }, "titan")
    test.eq(states.ULDtitan.completed, true, "completed P6 lock is read normally")
    api.GetSavedInstanceInfo = function()
        return "Ulduar", 101, 7200, 4, true, false, 0, true, nil, "unknown", 14, 14, false, 603
    end
    states = Adapters.readRaidStates(api, { column }, "titan")
    test.eq(states and states.ULDtitan, nil, "unconfirmed raid size is not presented as P6")
end
