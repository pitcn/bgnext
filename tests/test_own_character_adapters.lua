return function(test)
    BG = { BGNext = {} }
    local Adapters = dofile("Core/BGNext/OwnCharactersAdapters.lua")
    local Catalog = dofile("Core/BGNext/OwnCharactersCatalog.lua")

    -- Client-family detection from the flags BGLite already sets in Core/DB/Init.lua.
    test.eq(Adapters.familyFromFlags({ IsTitan = true }), "titan", "detects titan")
    test.eq(Adapters.familyFromFlags({ IsMOP = true }), "mop", "detects mop")
    test.eq(Adapters.familyFromFlags({ IsRetail = true }), "retail", "detects retail")
    test.eq(Adapters.familyFromFlags({ IsCTM = true }), "cata", "detects cata")
    test.eq(Adapters.familyFromFlags({ IsTBC = true }), "tbc", "detects tbc")
    test.eq(Adapters.familyFromFlags({ IsVanilla = true }), "vanilla", "detects vanilla")
    test.eq(Adapters.familyFromFlags({ IsWLK = true, IsWLK_80 = true }), "wrath", "detects wrath")

    -- BGLite sets IsWLK for the anniversary client too; titan must win.
    test.eq(Adapters.familyFromFlags({ IsWLK = true, IsTitan = true }), "titan", "titan outranks wrath")
    test.eq(Adapters.familyFromFlags({ IsVanilla = true, IsVanilla_Sod = true }), nil,
        "season of discovery is excluded from role overview")
    test.eq(Adapters.familyFromFlags({}), nil, "unknown client has no family")
    test.eq(Adapters.familyFromFlags(nil), nil, "missing flags are safe")

    -- Missing or failing APIs degrade to nil instead of throwing.
    test.eq(Adapters.safeCall(nil), nil, "missing API is safe")
    test.eq(Adapters.safeCall("not a function"), nil, "non-function is safe")
    test.eq(Adapters.safeCall(function() error("protected") end), nil, "throwing API is safe")
    test.eq(Adapters.safeCall(function(a, b) return a + b end, 2, 3), 5, "forwards arguments")
    test.eq(Adapters.safeCall(function() return nil end), nil, "nil result is preserved")

    -- Every declared family is covered.
    local families = Adapters.families
    test.eq(#families, 7, "seven client families are declared")
    local expectedFamilies = {
        vanilla = true, tbc = true, wrath = true, titan = true,
        cata = true, mop = true, retail = true,
    }
    for _, family in ipairs(families) do
        test.eq(expectedFamilies[family], true, family .. " is an expected family")
    end

    local titan = Catalog.forFamily("titan")
    test.eq(type(titan.raidColumns), "table", "titan raid columns exist")
    test.eq(type(titan.resourceColumns), "table", "titan resource columns exist")
    test.eq(Catalog.defaultVisible("titan", "raid", "MCtitan"), true, "default is explicit")
    test.eq(Catalog.status("titan"), "tested-in-game", "titan is the release-ready catalog")
    for _, family in ipairs({ "wrath", "cata" }) do
        test.eq(Catalog.status(family), "unverified", family .. " remains unverified")
        local catalog = Catalog.forFamily(family)
        test.eq(#catalog.raidColumns, 0, family .. " exposes no unreliable raid placeholders")
        test.eq(#catalog.resourceColumns, 0, family .. " exposes no unreliable resource placeholders")
    end

    for _, family in ipairs({ "vanilla", "tbc", "mop", "retail" }) do
        test.eq(Catalog.status(family), "pending-in-game-verification",
            family .. " is explicitly pending real-client validation")
        local catalog = Catalog.forFamily(family)
        test.eq(#catalog.raidColumns > 0, true, family .. " declares verified BGLite instance IDs")
        test.eq(#catalog.resourceColumns > 0, true, family .. " declares only confirmed summary columns")
        test.eq(Catalog.column(family, "resource", "mainProfession") ~= nil, true,
            family .. " exposes the profession summary")
        test.eq(Catalog.column(family, "resource", "weapons") ~= nil, true,
            family .. " exposes equipped weapons")
        test.eq(Catalog.column(family, "resource", "trinkets") ~= nil, true,
            family .. " exposes equipped trinkets")
        test.eq(Catalog.column(family, "resource", "money") ~= nil, true,
            family .. " exposes local money")
        test.eq(Catalog.defaultVisible(family, "resource", "equipmentDetails"), false,
            family .. " keeps full equipment behind the details option")
        test.eq(Catalog.column(family, "resource", "upgradeItems"), nil,
            family .. " never inherits Titan upgrade items")
        test.eq(Catalog.column(family, "resource", "titanEmber"), nil,
            family .. " never inherits Titan currencies")
    end

    -- Vanilla adds the Atiesh fragment, rested XP and its three verified
    -- profession cooldowns; TBC adds badges, honor, arena points and rested XP.
    local vanillaResources = {}
    for _, column in ipairs(Catalog.forFamily("vanilla").resourceColumns) do vanillaResources[column.id] = column end
    test.eq(vanillaResources.atieshFragment ~= nil, true, "vanilla exposes the Atiesh fragment item")
    test.eq(vanillaResources.atieshFragment.kind, "number", "the Atiesh fragment is a numeric item count")
    test.eq(vanillaResources.atieshFragment.source.key, "atieshFragment", "the Atiesh fragment uses its own whitelist key")
    test.eq(Adapters.currencyId("vanilla", "atieshFragment"), nil, "the Atiesh fragment is an item, not a currency")
    test.eq(vanillaResources.restXp ~= nil, true, "vanilla exposes rested XP")
    test.eq(Catalog.defaultVisible("vanilla", "resource", "restXp"), false, "rested XP stays hidden until verified")
    test.eq(vanillaResources.transmute ~= nil, true, "vanilla exposes the transmute cooldown")
    test.eq(vanillaResources.transmute.kind, "cooldown", "transmute is a cooldown column")
    test.eq(vanillaResources.transmute.source.spellId, 17187, "transmute uses the verified spell id")
    test.eq(vanillaResources.saltShaker.source.spellId, 19566, "salt shaker uses the verified spell id")
    test.eq(vanillaResources.mooncloth.source.spellId, 18560, "mooncloth uses the verified spell id")
    test.eq(Catalog.defaultVisible("vanilla", "resource", "transmute"), true, "transmute shows by default")
    test.eq(Catalog.column("vanilla", "resource", "badgeOfJustice"), nil, "vanilla never carries the TBC badge")

    local tbcResources = {}
    for _, column in ipairs(Catalog.forFamily("tbc").resourceColumns) do tbcResources[column.id] = column end
    test.eq(tbcResources.badgeOfJustice ~= nil, true, "tbc exposes the badge of justice item")
    test.eq(tbcResources.badgeOfJustice.source.key, "badgeOfJustice", "the badge uses its own whitelist key")
    test.eq(tbcResources.honor ~= nil, true, "tbc exposes honor via UnitHonor")
    test.eq(tbcResources.arenaPoints ~= nil, true, "tbc declares arena points")
    test.eq(Catalog.defaultVisible("tbc", "resource", "arenaPoints"), false, "tbc arena points stay hidden until verified")
    test.eq(Adapters.currencyId("tbc", "arenaPoints"), 1900, "tbc arena points use currency 1900")
    test.eq(tbcResources.restXp ~= nil, true, "tbc exposes rested XP")
    test.eq(Catalog.column("tbc", "resource", "transmute"), nil, "tbc never carries a vanilla profession cooldown")
    test.eq(Catalog.column("tbc", "resource", "atieshFragment"), nil, "tbc never carries the Atiesh fragment")

    local expectedRaidInstances = {
        vanilla = { 409, 249, 469, 309, 509, 531, 533 },
        tbc = { 532, 565, 544, 548, 550, 534, 564, 568, 580 },
        mop = { 1008, 1009, 996, 1098, 1136 },
        retail = { 3004, 2912, 2939, 2913, 1592 },
    }
    for family, expected in pairs(expectedRaidInstances) do
        local catalog = Catalog.forFamily(family)
        test.eq(#catalog.raidColumns, #expected, family .. " has one column per confirmed instance")
        for index, instanceId in ipairs(expected) do
            local column = catalog.raidColumns[index]
            test.eq(#column.source.instanceIds, 1, family .. "/" .. column.id .. " is never grouped")
            test.eq(column.source.instanceIds[1], instanceId,
                family .. " instance order remains deterministic at " .. index)
        end
    end
    test.eq(Catalog.defaultVisible("retail", "raid", "VA"), true,
        "the BGLite current-season Retail raid is visible")
    for _, id in ipairs({ "VS", "DR", "MQD", "Micosis" }) do
        test.eq(Catalog.defaultVisible("retail", "raid", id), false,
            "the Retail previous-season column " .. id .. " is hidden by default")
    end

    local seenTitanInstances = {}
    for _, column in ipairs(titan.raidColumns) do
        test.eq(#column.source.instanceIds, 1, column.id .. " maps to one instance")
        test.eq(seenTitanInstances[column.source.instanceIds[1]], nil, column.id .. " has a unique instance")
        seenTitanInstances[column.source.instanceIds[1]] = column.id
    end

    -- Descriptor shape is enforced for every column of every family.
    local validKind = {
        status = true, progress = true, number = true,
        money = true, items = true, profession = true, cooldown = true,
    }
    local validWidth = {
        narrow = true, normal = true, wide = true, ["dynamic-items"] = true,
    }
    for _, family in ipairs(families) do
        local catalog = Catalog.forFamily(family)
        test.eq(type(catalog), "table", family .. " has a catalog")
        if family == "titan" or family == "vanilla" or family == "tbc"
            or family == "mop" or family == "retail" then
            test.eq(#catalog.raidColumns > 0, true, family .. " declares raid columns")
            test.eq(#catalog.resourceColumns > 0, true, family .. " declares resource columns")
        end

        local seen = {}
        for _, section in ipairs({ "raidColumns", "resourceColumns" }) do
            local expectedSection = section == "raidColumns" and "raid" or "resource"
            for _, column in ipairs(catalog[section]) do
                local label = family .. "/" .. tostring(column.id)
                test.eq(type(column.id), "string", label .. " has a string id")
                test.eq(column.id ~= "", true, label .. " id is not empty")
                test.eq(seen[column.id], nil, label .. " id is unique in its family")
                seen[column.id] = true
                test.eq(column.section, expectedSection, label .. " declares its section")
                test.eq(type(column.title), "string", label .. " has a title")
                test.eq(column.title ~= "", true, label .. " title is not empty")
                test.eq(validKind[column.kind], true, label .. " has a valid kind")
                test.eq(validWidth[column.width], true, label .. " has a valid width")
                test.eq(type(column.defaultVisible), "boolean", label .. " has explicit default visibility")
                test.eq(type(column.total), "boolean", label .. " states whether it totals")
            end
        end

        -- Only numeric-ish columns may claim a total; status columns never do.
        for _, column in ipairs(catalog.resourceColumns) do
            if column.kind == "status" or column.kind == "items" or column.kind == "profession" then
                test.eq(column.total, false, family .. "/" .. column.id .. " does not fake a total")
            end
        end
        for _, column in ipairs(catalog.raidColumns) do
            test.eq(column.total, false, family .. "/" .. column.id .. " raid column has no total")
        end

        if family == "titan" then
            test.eq(Catalog.column(family, "resource", "money") ~= nil, true, "titan exposes gold")
            test.eq(Catalog.column(family, "resource", "money").kind, "money", "titan gold is money-kind")
        end
    end

    -- Deterministic order across calls.
    local firstOrder, secondOrder = {}, {}
    for i, column in ipairs(Catalog.forFamily("titan").raidColumns) do firstOrder[i] = column.id end
    for i, column in ipairs(Catalog.forFamily("titan").raidColumns) do secondOrder[i] = column.id end
    test.eq(#firstOrder, #secondOrder, "raid column count is stable")
    for i = 1, #firstOrder do
        test.eq(firstOrder[i], secondOrder[i], "raid column order is stable at " .. i)
    end

    -- Callers cannot corrupt the shared catalog.
    local mutable = Catalog.forFamily("titan")
    mutable.raidColumns[1].title = "mutated"
    mutable.raidColumns[1] = nil
    test.eq(Catalog.forFamily("titan").raidColumns[1].id, firstOrder[1], "catalog is defensively copied")
    test.eq(Catalog.forFamily("titan").raidColumns[1].title ~= "mutated", true, "titles are defensively copied")

    -- Families expose only their own instances.
    test.eq(Catalog.column("titan", "raid", "MCtitan") ~= nil, true, "titan has MCtitan")
    test.eq(Catalog.column("mop", "raid", "MCtitan"), nil, "mop does not carry titan raids")
    test.eq(Catalog.column("mop", "raid", "MSV") ~= nil, true, "mop exposes Mogu'shan independently")
    test.eq(Catalog.column("mop", "raid", "HOF") ~= nil, true, "mop exposes Heart of Fear independently")
    test.eq(Catalog.column("mop", "raid", "TES") ~= nil, true, "mop exposes Terrace independently")
    test.eq(Catalog.column("titan", "raid", "MSV"), nil, "titan does not carry mop raids")
    test.eq(Catalog.column("retail", "raid", "VS") ~= nil, true, "retail keeps the BGLite P1 raid hidden")
    test.eq(Catalog.column("vanilla", "raid", "MC") ~= nil, true, "vanilla exposes Molten Core")
    test.eq(Catalog.column("titan", "raid", "MC"), nil, "titan uses suffixed raid keys")

    -- Titan follows the original visible resource summary. Full equipment is
    -- available only as an explicitly hidden details column.
    test.eq(Catalog.column("titan", "resource", "titanShard") ~= nil, true, "titan declares the shard column")
    test.eq(Catalog.defaultVisible("titan", "resource", "mainProfession"), true, "main professions show by default")
    test.eq(Catalog.defaultVisible("titan", "resource", "weapons"), true, "weapons show by default")
    test.eq(Catalog.defaultVisible("titan", "resource", "trinkets"), true, "trinkets show by default")
    test.eq(Catalog.defaultVisible("titan", "resource", "legendaryItems"), true, "owned legendaries show by default")
    test.eq(Catalog.defaultVisible("titan", "resource", "upgradeItems"), true, "upgrade items show by default")
    test.eq(Catalog.defaultVisible("titan", "resource", "equipmentDetails"), false, "full equipment is details-only")
    test.eq(Catalog.column("titan", "resource", "equipment"), nil, "the old all-equipment main column is gone")

    local shortTitles = {
        SWtitan = "SW", ZAtitan = "ZAM", TOCtitan = "TOC", ZUGtitan = "ZG",
        NAXXtitan = "NAXX", MCtitan = "MC", VOAtitan = "宝库",
    }
    for id, title in pairs(shortTitles) do
        test.eq(Catalog.column("titan", "raid", id).title, title, id .. " uses the compact requested heading")
    end
    test.eq(Catalog.column("titan", "resource", "legendaryItems").title, "已有", "legendary heading is compact")
    test.eq(Catalog.column("titan", "resource", "upgradeItems").title, "升级", "upgrade heading is compact")
    test.eq(Catalog.column("titan", "resource", "titanEmber").title, "余烬", "ember heading is compact")
    test.eq(Catalog.column("titan", "resource", "titanShard").title, "碎片", "shard heading is compact")
    test.eq(Catalog.column("titan", "resource", "stoneKeeper").title, "岩石", "Stone Keeper heading is compact")
    test.eq(Catalog.column("titan", "resource", "honor").title, "荣誉", "honor heading is compact")

    -- Titan adds the ten verified profession cooldowns. They stay hidden until
    -- real-client validation confirms each spell id, so none of them can leak a
    -- hand-written name or an unverified cooldown into the default table.
    local titanCooldowns = {
        alchemyResearch = 60893, alchemyTransmute = 66660,
        inscriptionResearch = 61177, minorInscription = 61288,
        icyPrism = 62242, smeltTitansteel = 55208,
        spellweave = 56003, ebonweave = 56002, moonshroud = 56001, glacialBag = 56005,
    }
    for key, spellId in pairs(titanCooldowns) do
        local column = Catalog.column("titan", "resource", key)
        test.eq(column ~= nil, true, "titan declares the " .. key .. " cooldown")
        test.eq(column.kind, "cooldown", key .. " is a cooldown column")
        test.eq(column.source.kind, "profession-cooldown", key .. " uses the profession-cooldown source")
        test.eq(column.source.spellId, spellId, key .. " uses its verified spell id")
        test.eq(column.total, false, key .. " never totals")
        test.eq(Catalog.defaultVisible("titan", "resource", key), false,
            key .. " stays hidden until real-client validation")
    end

    -- Unknown lookups stay safe.
    test.eq(Catalog.forFamily("nope"), nil, "unknown family has no catalog")
    test.eq(Catalog.forFamily(nil), nil, "missing family is safe")
    test.eq(Catalog.status("nope"), "unverified", "unknown family is never presented as supported")
    test.eq(Catalog.column("titan", "raid", "nope"), nil, "unknown column is nil")
    test.eq(Catalog.column("titan", "nope", "MCtitan"), nil, "unknown section is nil")
    test.eq(Catalog.defaultVisible("nope", "raid", "MCtitan"), false, "unknown family defaults to hidden")
    test.eq(Catalog.defaultVisible("titan", "raid", "nope"), false, "unknown column defaults to hidden")

    -- Capabilities are declared per family and never invented at render time.
    local caps = Adapters.capabilities("titan")
    test.eq(type(caps), "table", "titan declares capabilities")
    test.eq(type(caps.hasCurrencyApi), "boolean", "currency capability is explicit")
    test.eq(Adapters.capabilities("nope"), nil, "unknown family has no capabilities")

    -- Verified Titan currency IDs match the game data used by the original UI.
    test.eq(Adapters.currencyId("titan", "unverified-key"), nil, "unverified currency has no ID")
    test.eq(Adapters.currencyId("titan", "titanEmber"), 3403, "Titan ember ID is verified")
    test.eq(Adapters.currencyId("titan", "titanShard"), 3406, "Titan shard ID is verified")
    test.eq(Adapters.currencyId("titan", "stoneKeeper"), 161, "Stone Keeper shard ID is verified")
    test.eq(Adapters.currencyId("titan", "honor"), 1901, "Titan honor ID is verified")
    test.eq(Adapters.isVerifiedColumn("titan", "titanShard"), true, "shard column is now readable")
    test.eq(Adapters.canReadColumn("titan", {
        C_CurrencyInfo = { GetCurrencyInfo = function() return { quantity = 0 } end },
    }, Catalog.column("titan", "resource", "honor")), true,
        "Titan honor can use the currency API without UnitHonor")
end
