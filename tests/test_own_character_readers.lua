return function(test)
    BG = { BGNext = {} }
    local Adapters = dofile("Core/BGNext/OwnCharactersAdapters.lua")
    local Catalog = dofile("Core/BGNext/OwnCharactersCatalog.lua")

    local titanRaidColumns = Catalog.forFamily("titan").raidColumns

    local titanById = {}
    for _, column in ipairs(titanRaidColumns) do titanById[column.id] = column end
    test.eq(#titanById.SSCtitan.source.instanceIds, 2, "Titan P2 groups SSC and TK")
    test.eq(titanById.SSCtitan.zoneId, nil, "a grouped raid keeps its combined catalog title")
    test.eq(titanById.MCtitan.zoneId, 409, "a single raid may use Blizzard's localized zone title")
    test.eq(titanById.SSCtitan.source.instanceIds[1], 548, "Titan P2 starts with SSC")
    test.eq(titanById.SSCtitan.source.instanceIds[2], 550, "Titan P2 also includes TK")
    test.eq(#titanById.NAXXtitan.source.instanceIds, 3, "Titan P3 groups Naxx, OS and EOE")
    test.eq(#titanById.TOCtitan.source.instanceIds, 2, "Titan P4 groups both raids")
    test.eq(#titanById.SWtitan.source.instanceIds, 2, "Titan P5 groups both raids")
    test.eq(titanById.Worldtitan.source.readable, false, "unreadable world-boss status is explicit")

    local function api(overrides)
        local base = {
            time = function() return 5000 end,
            UnitName = function(unit) return "Piti" end,
            GetRealmID = function() return 123 end,
            GetRealmName = function() return "时-光 II" end,
            UnitFactionGroup = function(unit) return "Alliance" end,
            UnitClass = function(unit) return "猎人", "HUNTER" end,
            UnitLevel = function(unit) return 80 end,
            GetAverageItemLevel = function() return 230, 231 end,
            GetMoney = function() return 50000 end,
            UnitHonor = function(unit) return 15 end,
            GetInventoryItemLink = function(unit, slot) return string.format("item:%d:0:0", 10000 + slot) end,
            GetItemInfoInstant = function(link) return tonumber(string.match(link, "item:(%d+)")) end,
            GetItemInfo = function(link) return "Item", link, 4, 226, 80, "Armor", "Misc", 1, "", "interface/icons/inv_1", 100 end,
            GetItemIcon = function(id) return "interface/icons/inv_" .. tostring(id) end,
        }
        for key, value in pairs(overrides or {}) do
            if value == false then base[key] = nil else base[key] = value end
        end
        return base
    end

    -- readers() builds the environment the collector consumes.
    local env = Adapters.readers("titan", api(), titanRaidColumns)
    test.eq(type(env), "table", "readers builds an environment")
    test.eq(env.playerName(), "Piti", "reads the logged-in name")
    test.eq(env.realmId(), 123, "reads the logged-in realm id")
    test.eq(env.realmName(), "时光II", "normalizes the realm name")
    test.eq(env.faction(), "Alliance", "reads the logged-in faction")
    test.eq(env.class(), "HUNTER", "reads the logged-in class file")
    test.eq(env.level(), 80, "reads the logged-in level")
    test.eq(env.itemLevel(), 231, "reads the equipped average item level")
    test.eq(env.money(), 50000, "reads the logged-in money")
    test.eq(env.now(), 5000, "reads the observation time")

    -- Equipment is read into slot-keyed entries with plain item data.
    local equipment = env.equipment()
    test.eq(type(equipment), "table", "equipment is read")
    test.eq(equipment[1].itemId, 10001, "equipment carries the item id")
    test.eq(equipment[1].itemLevel, 226, "equipment carries the item level")
    test.eq(equipment[1].quality, 4, "equipment carries the quality")
    test.eq(equipment[1].icon, "interface/icons/inv_1", "equipment carries the icon")
    test.eq(equipment[1].link, "item:10001:0:0", "equipment carries the link for the tooltip")
    test.eq(equipment[19] ~= nil, true, "all equipped slots are read")
    local numericEquipment = Adapters.readers("titan", api({
        GetItemInfo = function(link)
            return "Item", link, 4, 226, 80, "Armor", "Misc", 1, "", 134400, 100
        end,
    }), titanRaidColumns).equipment()
    test.eq(numericEquipment[1].icon, 134400, "numeric item texture file IDs are retained")

    -- Raid-state reader uses GetSavedInstanceInfo's real tuple: the second
    -- value is a lockout id, while the 14th value is the instance id used by
    -- BGLite's catalog. The third value is the reset duration in seconds.
    local raidApi = api({
        GetNumSavedInstances = function() return 3 end,
        GetSavedInstanceInfo = function(index)
            if index == 1 then
                return "熔火之心", 900001, 3600, 3, true, false, 1, true,
                    40, "25人", 10, 10, nil, 409
            elseif index == 2 then
                return "毒蛇神殿", 900002, 7200, 3, true, false, 1, true,
                    25, "25人", 6, 6, nil, 548
            elseif index == 3 then
                return "风暴要塞", 900003, 5400, 3, true, false, 1, true,
                    25, "25人", 4, 2, nil, 550
            end
            return nil
        end,
    })
    local raidStates = Adapters.readers("titan", raidApi, titanRaidColumns).raidStates()
    test.eq(raidStates.MCtitan.completed, true, "a full lockout maps to its column and is complete")
    test.eq(raidStates.MCtitan.difficulty, 3, "raid difficulty is numeric")
    test.eq(raidStates.MCtitan.total, 10, "raid total encounters are read")
    test.eq(raidStates.MCtitan.progress, 10, "raid progress is read")
    test.eq(raidStates.MCtitan.resetsAt, 8600, "raid reset time is now plus remaining lockout")
    test.eq(raidStates.SSCtitan.progress, 8, "a grouped raid sums encounter progress")
    test.eq(raidStates.SSCtitan.total, 10, "a grouped raid sums encounter totals")
    test.eq(raidStates.SSCtitan.completedParts, 1, "a grouped raid counts completed instances")
    test.eq(raidStates.SSCtitan.totalParts, 2, "a grouped raid knows every configured instance")
    test.eq(raidStates.SSCtitan.completed, nil, "a grouped raid is incomplete until every instance is complete")
    test.eq(raidStates.SSCtitan.resetsAt, 10400, "a grouped raid keeps the nearest reset")
    test.eq(raidStates.SSCtitan.completed, nil, "a partial lockout is not marked complete")

    -- Professions read the two primary skill lines into index-keyed entries.
    local profApi = api({
        GetProfessions = function() return 164, 165, nil, nil, nil, nil end,
        GetProfessionInfo = function(index)
            if index == 164 then return "锻造", "interface/icons/prof1", 450, 450, 0, 0 end
            if index == 165 then return "工程", "interface/icons/prof2", 300, 450, 0, 0 end
            return nil
        end,
    })
    local professions = Adapters.readers("titan", profApi, titanRaidColumns).professions()
    test.eq(professions[1].name, "锻造", "first profession name is read")
    test.eq(professions[1].skill, 450, "first profession skill is read")
    test.eq(professions[1].icon, "interface/icons/prof1", "first profession icon is read")
    test.eq(professions[2].name, "工程", "second profession name is read")
    local numericProfessions = Adapters.readers("titan", api({
        GetProfessions = function() return 164, nil, nil, nil, nil, nil end,
        GetProfessionInfo = function() return "锻造", 136241, 450, 450, 0, 0 end,
    }), titanRaidColumns).professions()
    test.eq(numericProfessions[1].icon, 136241, "numeric profession texture file IDs are retained")

    -- Resources read the current character's honor; unverified currency and item
    -- tokens stay empty so their columns remain hidden.
    local resources = Adapters.readers("titan", api(), titanRaidColumns).resources()
    test.eq(resources.currencies.honor, 15, "honor is read for the current character")
    test.eq(resources.currencies.titanShard, nil, "an unverified currency id yields no value")
    test.eq(resources.currencies.emblem, nil, "an unverified emblem yields no value")

    -- Missing, non-function or throwing APIs degrade to nil, never an error.
    local degraded = Adapters.readers("titan", api({
        UnitName = function() error("protected") end,
        GetRealmID = function() return "not-a-number" end,
        GetMoney = false,
        GetInventoryItemLink = false,
        GetNumSavedInstances = false,
        GetProfessions = false,
        UnitHonor = false,
    }), titanRaidColumns)
    test.eq(degraded.playerName(), nil, "a throwing name API yields nil")
    test.eq(degraded.realmId(), nil, "a non-numeric realm id yields nil")
    test.eq(degraded.money(), nil, "a missing money API yields nil")
    test.eq(degraded.equipment(), nil, "a missing equipment API yields nil")
    test.eq(degraded.raidStates(), nil, "a missing saved-instance API yields nil")
    test.eq(degraded.professions(), nil, "a missing profession API yields nil")
    test.eq(degraded.resources(), nil, "a missing honor API yields nil")

    -- No reader accepts a unit token or another player's name.
    local received = {}
    local probe = api({
        UnitName = function(unit) received[#received + 1] = unit return "Piti" end,
        UnitFactionGroup = function(unit) received[#received + 1] = unit return "Alliance" end,
        UnitClass = function(unit) received[#received + 1] = unit return "猎人", "HUNTER" end,
        UnitLevel = function(unit) received[#received + 1] = unit return 80 end,
        UnitHonor = function(unit) received[#received + 1] = unit return 15 end,
        GetInventoryItemLink = function(unit, slot) received[#received + 1] = unit return nil end,
    })
    local probeEnv = Adapters.readers("titan", probe, titanRaidColumns)
    probeEnv.playerName(); probeEnv.faction(); probeEnv.class(); probeEnv.level()
    probeEnv.resources(); probeEnv.equipment()
    for _, arg in ipairs(received) do
        test.eq(arg, "player", "readers address only the player unit")
    end
end
