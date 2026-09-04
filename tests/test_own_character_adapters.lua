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

    -- Init-time identity validation with secret-value guards. A protected value
    -- must never be compared, concatenated or used as a SavedVariables key, so
    -- wrong types and empty strings are rejected before the secret check.
    local identity = Adapters.validatedIdentity({ playerName = "Piti", realmID = 123, realmName = "时光II" })
    test.eq(identity ~= nil, true, "a valid init identity is accepted")
    test.eq(identity.playerName, "Piti", "validated identity keeps the name")
    test.eq(identity.realmId, 123, "validated identity keeps the realm id")
    test.eq(identity.realmName, "时光II", "validated identity keeps the realm name")
    test.eq(Adapters.validatedIdentity({ playerName = "Piti", realmID = 123 }) ~= nil, true,
        "realm name is optional")
    test.eq(Adapters.validatedIdentity({ playerName = "Piti" }), nil, "missing realm id rejects identity")
    test.eq(Adapters.validatedIdentity({ realmID = 123 }), nil, "missing name rejects identity")
    test.eq(Adapters.validatedIdentity({}), nil, "empty globals reject identity")
    test.eq(Adapters.validatedIdentity(nil), nil, "nil globals are safe")
    test.eq(Adapters.validatedIdentity({ playerName = "", realmID = 123 }), nil, "empty name rejects identity")
    test.eq(Adapters.validatedIdentity({ playerName = 7, realmID = 123 }), nil, "non-string name rejects identity")
    test.eq(Adapters.validatedIdentity({ playerName = "Piti", realmID = "123" }), nil,
        "non-numeric realm id rejects identity")

    -- Secret-value detection honours the BG.IsSecret wrapper and degrades to a
    -- safe default when no guard is present.
    test.eq(Adapters.isSecretValue({ IsSecret = function() return false end }, "Piti"), false,
        "a non-secret value reads as readable")
    test.eq(Adapters.isSecretValue({ IsSecret = function() return true end }, "Piti"), true,
        "the BG.IsSecret wrapper is honoured")
    test.eq(Adapters.isSecretValue({}, "Piti"), false, "absent guard assumes readable")
    test.eq(Adapters.isSecretValue(nil, "Piti"), false, "nil globals are readable by default")

    -- A secret realm name is dropped but does not reject an otherwise-valid identity.
    local secretRealmName = {}
    local secretName = {
        playerName = "Piti", realmID = 123, realmName = secretRealmName,
        IsSecret = function(v) return v == secretRealmName end,
    }
    local partial = Adapters.validatedIdentity(secretName)
    test.eq(partial ~= nil, true, "a secret realm name does not reject the identity")
    test.eq(partial.playerName, "Piti", "identity survives a secret realm name")
    test.eq(partial.realmName, nil, "a secret realm name is dropped")


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
        tbc = { 580, 564, 534, 568, 550, 548, 565, 544, 532 },
        mop = { 1008, 1009, 996, 1098, 1136 },
        retail = { 2939, 2913, 1592, 2987 },
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
    for _, id in ipairs({ "DR", "MQD", "Micosis", "TG" }) do
        test.eq(Catalog.defaultVisible("retail", "raid", id), false,
            "the Retail raid column " .. id .. " stays hidden until its name is confirmed")
    end
    test.eq(Catalog.column("retail", "raid", "VA"), nil,
        "the unnameable current-season placeholder is removed")
    test.eq(Catalog.column("retail", "raid", "VS"), nil,
        "the unnameable P1-group placeholder is removed")

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
    test.eq(Catalog.column("retail", "raid", "VS"), nil, "retail drops the placeholder P1 group")
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
        SWtitan = "太阳井", ZAtitan = "祖阿曼", TOCtitan = "TOC", ZUGtitan = "ZG",
        NAXXtitan = "NAXX", MCtitan = "MC", VOAtitan = "宝库",
    }
    for id, title in pairs(shortTitles) do
        test.eq(Catalog.column("titan", "raid", id).title, title, id .. " uses the compact requested heading")
    end

    -- Player-visible raid headings use the requested Chinese short names and
    -- never leak an internal key or placeholder text.
    local function raidHeadings(family)
        local result = {}
        for _, column in ipairs(Catalog.forFamily(family).raidColumns) do
            result[column.id] = column.title
        end
        return result
    end
    local vanillaHeadings = raidHeadings("vanilla")
    test.eq(vanillaHeadings.MC, "MC", "vanilla MC keeps the conventional heading")
    test.eq(vanillaHeadings.ONY, "黑龙", "vanilla Onyxia shows 黑龙")
    test.eq(vanillaHeadings.BWL, "黑翼", "vanilla BWL shows 黑翼")
    test.eq(vanillaHeadings.ZUG, "祖格", "vanilla ZG shows 祖格")
    test.eq(vanillaHeadings.AQL, "废墟", "vanilla AQ20 shows 废墟")
    test.eq(vanillaHeadings.TAQ, "安其拉", "vanilla AQ40 shows 安其拉")
    test.eq(vanillaHeadings.NAXX, "NAXX", "vanilla Naxx keeps NAXX")

    local tbcHeadings = raidHeadings("tbc")
    test.eq(tbcHeadings.SW, "太阳井", "tbc Sunwell shows 太阳井")
    test.eq(tbcHeadings.BT, "黑庙", "tbc Black Temple shows 黑庙")
    test.eq(tbcHeadings.HS, "海山", "tbc Hyjal shows 海山")
    test.eq(tbcHeadings.ZA, "祖阿曼", "tbc Zul'Aman shows 祖阿曼")
    test.eq(tbcHeadings.TK, "风暴", "tbc Tempest Keep shows 风暴")
    test.eq(tbcHeadings.SSC, "毒蛇", "tbc SSC shows 毒蛇")
    test.eq(tbcHeadings.GL, "格鲁尔", "tbc Gruul shows 格鲁尔")
    test.eq(tbcHeadings.ML, "玛胖", "tbc Magtheridon shows 玛胖")
    test.eq(tbcHeadings.KZ, "卡拉赞", "tbc Karazhan shows 卡拉赞")

    local mopHeadings = raidHeadings("mop")
    test.eq(mopHeadings.MSV, "宝库", "mop Mogu'shan shows 宝库")
    test.eq(mopHeadings.HOF, "恐惧", "mop Heart of Fear shows 恐惧")
    test.eq(mopHeadings.TES, "永春", "mop Terrace shows 永春")
    test.eq(mopHeadings.TOT, "雷电", "mop Throne of Thunder shows 雷电")
    test.eq(mopHeadings.SOO, "奥格", "mop Siege of Orgrimmar shows 奥格")

    -- MoP-only routine trackers are independent optional columns. The farm
    -- entry deliberately declares an unavailable detector so the UI can show
    -- an honest unknown state instead of pretending that visiting or logging
    -- in means the crops were harvested.
    local mopActivities = {}
    for _, column in ipairs(Catalog.forFamily("mop").resourceColumns) do
        if column.source and column.source.kind == "activity" then mopActivities[column.id] = column end
    end
    test.eq(mopActivities.celestialFirst.source.detector, "lfg-daily", "daily first win uses the LFG reward state")
    test.eq(mopActivities.farmHarvest.source.detector, "unavailable", "farm harvest fails closed without a client API")
    test.eq(mopActivities.augustCelestials.source.questId, 33117, "Celestials use the BGLite world-boss quest flag")
    test.eq(mopActivities.ordos.source.questId, 33118, "Ordos uses the BGLite world-boss quest flag")
    test.eq(Catalog.defaultVisible("mop", "resource", "celestialFirst"), false, "new MoP trackers are opt-in")
    test.eq(Catalog.column("titan", "resource", "celestialFirst"), nil, "MoP activities never leak into Titan")

    local retailHeadings = raidHeadings("retail")
    test.eq(retailHeadings.DR, "梦境", "retail 梦境裂隙 shows 梦境")
    test.eq(retailHeadings.MQD, "奎尔", "retail 进军奎尔丹纳斯 shows 奎尔")
    test.eq(retailHeadings.Micosis, "孢陨", "retail 孢陨幽境 shows 孢陨")
    test.eq(retailHeadings.TG, "潮缚", "retail 潮缚石窟 shows 潮缚")

    local forbiddenHeadings = {
        ONY = true, BWL = true, AQ20 = true, AQ40 = true,
        KZ = true, GL = true, MAG = true, SSC = true, TK = true,
        HYJAL = true, BT = true, ZA = true, SW = true,
        MSV = true, HOF = true, TOES = true, TOT = true, SOO = true,
        ZAM = true, SWtitan = true, ZAtitan = true, VOAtitan = true,
        VA = true, VS = true, DR = true, MQD = true, Micosis = true,
        ["当前赛季团本"] = true, ["P1团本"] = true,
    }
    for _, family in ipairs(families) do
        for _, column in ipairs(Catalog.forFamily(family).raidColumns) do
            test.eq(forbiddenHeadings[column.title], nil,
                family .. "/" .. column.id .. " never leaks an internal key or placeholder title")
        end
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

    -- MoP registers its currencies and cooldowns against the exact whitelist.
    -- Only Valor, Justice, the bonus-roll seal and money show by default; every
    -- candidate currency, item and cooldown stays hidden until client checks.
    local mopCurrencyIds = {
        valor = 396, justice = 395, roll = 776, conquest = 390, honor = 1901,
        ironpawToken = 402, darkmoonTicket = 515, elderCharm = 697,
        lesserCharm = 738, moguRune = 752, timelessCoin = 777,
    }
    for key, id in pairs(mopCurrencyIds) do
        test.eq(Adapters.currencyId("mop", key), id, "MoP " .. key .. " uses currency " .. tostring(id))
        local column = Catalog.column("mop", "resource", key)
        test.eq(column ~= nil, true, "MoP declares the " .. key .. " column")
        test.eq(column.source.currencyId, id, "MoP " .. key .. " resolves its icon at runtime")
    end
    for _, id in ipairs({ "valor", "justice", "roll" }) do
        test.eq(Catalog.defaultVisible("mop", "resource", id), true, "MoP " .. id .. " shows by default")
    end
    test.eq(Catalog.defaultVisible("mop", "resource", "money"), true, "MoP gold shows by default")
    for _, id in ipairs({ "conquest", "honor", "ironpawToken", "darkmoonTicket",
        "elderCharm", "lesserCharm", "moguRune", "timelessCoin" }) do
        test.eq(Catalog.defaultVisible("mop", "resource", id), false,
            "MoP " .. id .. " stays hidden until confirmed")
    end
    test.eq(Catalog.column("mop", "resource", "titanEmber"), nil, "MoP never inherits Titan currencies")

    -- Unverified MoP candidate currencies and items are removed from the runtime
    -- catalog and register no ID, so they can never be collected or shown.
    for _, id in ipairs({ "currency3350", "currency3407", "currency3414", "currency3416",
        "item256883", "item247796" }) do
        test.eq(Catalog.column("mop", "resource", id), nil,
            "unverified MoP candidate " .. id .. " is removed from the runtime catalog")
        test.eq(Adapters.currencyId("mop", id), nil,
            "unverified MoP candidate " .. id .. " registers no currency ID")
    end

    local mopCooldowns = {
        transmuteLivingSteel = 114780, lightningSteelIngot = 138646,
        shaCrystal = 116499, scrollOfWisdom = 112996,
        facetsOfResearch = 131686, serpentsHeart = 140050,
        magnificenceOfLeather = 140040, imperialSilk = 125557,
        jardsPeculiarEnergy = 139176,
    }
    for key, spellId in pairs(mopCooldowns) do
        local column = Catalog.column("mop", "resource", key)
        test.eq(column ~= nil, true, "mop declares the " .. key .. " cooldown")
        test.eq(column.kind, "cooldown", key .. " is a cooldown column")
        test.eq(column.source.spellId, spellId, key .. " uses its verified spell id")
        test.eq(Catalog.defaultVisible("mop", "resource", key), false,
            key .. " stays hidden until real-client validation")
    end

    -- A profession cooldown is offered only when its spell also resolves to a
    -- name, so an API surface alone never surfaces an unresolvable cooldown.
    local smeltColumn = Catalog.column("titan", "resource", "smeltTitansteel")
    test.eq(Adapters.canReadColumn("titan", {
        GetSpellCooldown = function() return 0, 0 end,
    }, smeltColumn), false,
        "a cooldown API without a spell name cannot offer the column")
    test.eq(Adapters.canReadColumn("titan", {
        GetSpellCooldown = function() return 0, 0 end,
        GetSpellInfo = function() return "熔炼泰坦精钢" end,
    }, smeltColumn), true,
        "a legacy spell-name resolution authorizes the cooldown")
    test.eq(Adapters.canReadColumn("titan", {
        C_Spell = {
            GetSpellCooldown = function() return { startTime = 0, duration = 0 } end,
            GetSpellInfo = function() return { name = "熔炼泰坦精钢" } end,
        },
    }, smeltColumn), true,
        "a modern spell-name resolution authorizes the cooldown")

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

    -- Retail declares its 29 candidate currencies but registers no currency ID
    -- for any of them, so canReadColumn hides each one until a real-client check
    -- confirms the ID. Retail also exposes no profession cooldown columns.
    local retailCatalog = Catalog.forFamily("retail")
    local retailCurrencyCount, retailCooldownCount = 0, 0
    for _, column in ipairs(retailCatalog.resourceColumns) do
        if column.source.kind == "currency" and column.id:match("^currency%d+$") then
            retailCurrencyCount = retailCurrencyCount + 1
            test.eq(column.source.currencyId, nil, column.id .. " registers no unverified currency ID")
            test.eq(Adapters.currencyId("retail", column.id), nil, column.id .. " has no currency ID")
            test.eq(Catalog.defaultVisible("retail", "resource", column.id), false,
                column.id .. " stays hidden until confirmed")
            test.eq(Adapters.canReadColumn("retail", {
                C_CurrencyInfo = { GetCurrencyInfo = function() return { quantity = 0 } end },
            }, column), false, column.id .. " is not readable without a verified ID")
        end
        if column.source.kind == "profession-cooldown" then
            retailCooldownCount = retailCooldownCount + 1
        end
    end
    test.eq(retailCurrencyCount, 29, "retail declares its 29 candidate currencies")
    test.eq(retailCooldownCount, 0, "retail has no profession cooldown columns")
    test.eq(Catalog.column("retail", "raid", "TG") ~= nil, true, "retail declares the pending TG candidate raid")
    test.eq(Catalog.column("retail", "raid", "TG").source.instanceIds[1], 2987, "TG maps its commented BGLite instance")
end
