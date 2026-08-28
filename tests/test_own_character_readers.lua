return function(test)
    BG = { BGNext = {} }
    local Adapters = dofile("Core/BGNext/OwnCharactersAdapters.lua")
    local Catalog = dofile("Core/BGNext/OwnCharactersCatalog.lua")

    local titanRaidColumns = Catalog.forFamily("titan").raidColumns

    local titanById = {}
    for _, column in ipairs(titanRaidColumns) do titanById[column.id] = column end
    test.eq(#titanById.SSCtitan.source.instanceIds, 1, "Titan SSC is an independent lockout")
    test.eq(titanById.SSCtitan.zoneId, 548, "Titan SSC keeps its own Blizzard instance id")
    test.eq(titanById.MCtitan.zoneId, 409, "a single raid may use Blizzard's localized zone title")
    test.eq(titanById.SSCtitan.source.instanceIds[1], 548, "Titan SSC maps only instance 548")
    test.eq(titanById.TKtitan.source.instanceIds[1], 550, "Titan TK maps only instance 550")
    test.eq(titanById.NAXXtitan.source.instanceIds[1], 533, "Titan Naxx maps only instance 533")
    test.eq(titanById.OStitan.source.instanceIds[1], 615, "Titan OS maps only instance 615")
    test.eq(titanById.EOEtitan.source.instanceIds[1], 616, "Titan EOE maps only instance 616")
    test.eq(titanById.TOCtitan.source.instanceIds[1], 649, "Titan TOC maps only instance 649")
    test.eq(titanById.ZUGtitan.source.instanceIds[1], 309, "Titan ZG maps only instance 309")
    test.eq(titanById.SWtitan.source.instanceIds[1], 580, "Titan Sunwell maps only instance 580")
    test.eq(titanById.ZAtitan.source.instanceIds[1], 568, "Titan ZA maps only instance 568")
    test.eq(titanById.Worldtitan, nil, "synthetic combined world-boss column is absent")

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
    test.eq(raidStates.SSCtitan.progress, 6, "SSC progress stays on the SSC column")
    test.eq(raidStates.SSCtitan.total, 6, "SSC total stays on the SSC column")
    test.eq(raidStates.SSCtitan.completed, true, "a complete SSC lockout is complete")
    test.eq(raidStates.SSCtitan.resetsAt, 12200, "SSC keeps its own reset")
    test.eq(raidStates.TKtitan.progress, 2, "TK progress stays on the TK column")
    test.eq(raidStates.TKtitan.total, 4, "TK total stays on the TK column")
    test.eq(raidStates.TKtitan.completed, nil, "a partial TK lockout is not complete")
    test.eq(raidStates.TKtitan.resetsAt, 10400, "TK keeps its own reset")

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

    local classicProfessions = Adapters.readers("titan", api({
        GetProfessions = function() return nil end,
        GetProfessionInfo = function() return nil end,
        GetNumSkillLines = function() return 4 end,
        GetSkillLineInfo = function(index)
            if index == 1 then return "专业", true, true end
            if index == 2 then return "锻造", false, nil, 441, 0, 0, 450, true end
            if index == 3 then return "工程学", false, nil, 450, 0, 0, 450, true end
            return "烹饪", false, nil, 450, 0, 0, 450, false
        end,
        GetSpellTexture = function(name) return "interface/icons/" .. name end,
    }), titanRaidColumns).professions()
    test.eq(#classicProfessions, 2, "classic skill lines fall back to the two primary professions")
    test.eq(classicProfessions[1].name, "锻造", "classic fallback retains the profession name")
    test.eq(classicProfessions[1].skill, 441, "classic fallback retains the skill rank")
    test.eq(classicProfessions[1].icon, "interface/icons/锻造", "classic fallback resolves an available icon")
    test.eq(classicProfessions[2].name, "工程学", "secondary skills are excluded from the fallback")

    -- Titan resources use the verified game IDs and table-returning currency API.
    local resources = Adapters.readers("titan", api({
        C_CurrencyInfo = {
            GetCurrencyInfo = function(id)
                local amounts = { [3403] = 12, [3406] = 34, [161] = 56, [1900] = 78, [1901] = 90 }
                return { quantity = amounts[id] or 0 }
            end,
        },
        GetItemCount = function(id)
            if id == 255103 then return 1 end
            if id == 265340 then return 2 end
            return 0
        end,
    }), titanRaidColumns, Catalog.forFamily("titan").resourceColumns).resources()
    test.eq(resources.currencies.honor, 90, "Titan honor uses currency 1901")
    test.eq(resources.currencies.titanEmber, 12, "Titan ember uses currency 3403")
    test.eq(resources.currencies.titanShard, 34, "Titan shard uses currency 3406")
    test.eq(resources.currencies.stoneKeeper, 56, "Stone Keeper shards use currency 161")
    test.eq(resources.currencies.arena, 78, "Titan arena points use currency 1900")
    test.eq(resources.items["legendary:255103"], 1, "owned legendary items are tracked by item id")
    test.eq(resources.items["upgrade:265340"], 2, "legendary upgrade items are tracked by item id")

    local vanillaCatalog = Catalog.forFamily("vanilla")
    local vanillaResources = Adapters.readers("vanilla", api({
        UnitHonor = function() return 999 end,
    }), vanillaCatalog.raidColumns, vanillaCatalog.resourceColumns).resources()
    test.eq(vanillaResources, nil,
        "a family does not collect honor or currencies absent from its explicit resource whitelist")

    -- Rested XP, item counts and profession cooldowns are read only when the
    -- family's explicit resource whitelist declares them.
    local vanillaFull = Adapters.readers("vanilla", api({
        GetXPExhaustion = function() return 4200 end,
        GetItemCount = function(id) return id == 22726 and 12 or 0 end,
        GetSpellCooldown = function(id)
            if id == 17187 then return 1000, 7200 end
            return 0, 0
        end,
    }), vanillaCatalog.raidColumns, vanillaCatalog.resourceColumns).resources()
    test.eq(vanillaFull.currencies.restXp, 4200, "vanilla reads rested XP via GetXPExhaustion")
    test.eq(vanillaFull.items.atieshFragment, 12, "vanilla reads the Atiesh fragment by item id")
    test.eq(vanillaFull.professionCooldowns.transmute.endsAt, 8200, "a cooling transmute records its end time")
    test.eq(vanillaFull.professionCooldowns.saltShaker.ready, true, "a zero-duration cooldown is ready")
    test.eq(vanillaFull.professionCooldowns.mooncloth.ready, true, "the third vanilla cooldown is ready when idle")

    -- The modern C_Spell table form is preferred over the legacy call.
    local modernCd = Adapters.readers("vanilla", api({
        GetSpellCooldown = false,
        C_Spell = { GetSpellCooldown = function(id)
            return { startTime = 1000, duration = 7200, isEnabled = true }
        end },
    }), vanillaCatalog.raidColumns, vanillaCatalog.resourceColumns).resources()
    test.eq(modernCd.professionCooldowns.transmute.endsAt, 8200, "the modern C_Spell cooldown API is preferred")

    -- Missing rest-XP, item and cooldown APIs leave those columns empty.
    local noVanillaApi = api({ GetXPExhaustion = false, GetItemCount = false, GetSpellCooldown = false })
    test.eq(Adapters.readers("vanilla", noVanillaApi,
        vanillaCatalog.raidColumns, vanillaCatalog.resourceColumns).resources(), nil,
        "missing vanilla resource APIs yield no resources")

    -- TBC reads badges by item id, honor via UnitHonor and arena via currency 1900.
    local tbcResources = Adapters.readers("tbc", api({
        GetItemCount = function(id) return id == 29434 and 40 or 0 end,
        UnitHonor = function() return 2500 end,
        C_CurrencyInfo = { GetCurrencyInfo = function(id)
            return id == 1900 and { quantity = 1500 } or { quantity = 0 }
        end },
    }), Catalog.forFamily("tbc").raidColumns, Catalog.forFamily("tbc").resourceColumns).resources()
    test.eq(tbcResources.items.badgeOfJustice, 40, "tbc reads badges by item id")
    test.eq(tbcResources.currencies.honor, 2500, "tbc reads honor via UnitHonor")
    test.eq(tbcResources.currencies.arenaPoints, 1500, "tbc reads arena points via currency 1900")

    -- MoP reads capped currencies as records carrying the weekly caps; a
    -- legacy family with the same API still stores a plain count.
    local mopResources = Adapters.readers("mop", api({
        C_CurrencyInfo = { GetCurrencyInfo = function(id)
            if id == 396 then
                return { quantity = 1000, maxQuantity = 3000, quantityEarnedThisWeek = 1000, maxWeeklyQuantity = 1000 }
            end
            if id == 395 then return { quantity = 500, maxQuantity = 4000 } end
            return nil
        end },
    }), Catalog.forFamily("mop").raidColumns, Catalog.forFamily("mop").resourceColumns).resources()
    test.eq(mopResources.currencies.valor.quantity, 1000, "MoP Valor records its quantity")
    test.eq(mopResources.currencies.valor.maxQuantity, 3000, "MoP Valor records its maximum")
    test.eq(mopResources.currencies.valor.quantityEarnedThisWeek, 1000, "MoP Valor records its weekly earned")
    test.eq(mopResources.currencies.valor.maxWeeklyQuantity, 1000, "MoP Valor records its weekly cap")
    test.eq(mopResources.currencies.justice.quantity, 500, "MoP Justice records its quantity")
    test.eq(mopResources.currencies.justice.maxQuantity, 4000, "MoP Justice records its maximum")
    test.eq(mopResources.currencies.justice.maxWeeklyQuantity, nil, "an absent cap stays empty")
    local mopMissing = Adapters.readers("mop", api({ C_CurrencyInfo = false }),
        Catalog.forFamily("mop").raidColumns, Catalog.forFamily("mop").resourceColumns).resources()
    test.eq(mopMissing.currencies.valor, nil, "missing MoP currency API records no Valor")

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
