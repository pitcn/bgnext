return function(test)
    BG = { BGNext = {} }
    local catalog = dofile("Core/BGNext/EquipmentFilterProfiles.lua")

    local required = {
        "id", "name", "icon", "weapon", "armor", "affix",
        "classRestriction", "ignoreBattleNetBound", "tankOnly", "primaryStat",
    }
    for _, classToken in ipairs({ "WARRIOR", "MAGE", "HUNTER", "DRUID" }) do
        local profiles = catalog.getDefaults({ project = "classic" }, classToken)
        test.eq(type(profiles), "table", classToken .. " profiles table")
        test.eq(#profiles > 0, true, classToken .. " has defaults")
        for _, key in ipairs(required) do
            test.eq(profiles[1][key] ~= nil, true, classToken .. " profile has " .. key)
        end
    end

    local first = catalog.getDefaults({ project = "classic" }, "MAGE")
    local originalName = first[1].name
    first[1].name = "mutated"
    first[1].armor[4] = nil
    local second = catalog.getDefaults({ project = "classic" }, "MAGE")
    test.eq(second[1].name, originalName, "default name is defensively copied")
    test.eq(second[1].armor[4], true, "nested rules are defensively copied")

    local rules = catalog.getRuleCatalog({ project = "classic" })
    test.eq(type(rules.weapon), "table", "weapon rules exposed")
    test.eq(type(rules.armor), "table", "armor rules exposed")
    test.eq(type(rules.affix), "table", "affix rules exposed")
    test.eq(rules.primaryStat.INTELLECT ~= nil, true, "primary stat rules use stable IDs")

    local warlock = catalog.getDefaults({ project = "classic" }, "WARLOCK")
    test.eq(warlock[1].primaryStat.INTELLECT, true,
        "the built-in Warlock profile selects Intellect without manual setup")
    test.eq(warlock[1].primaryStat.STRENGTH, nil,
        "the built-in Warlock profile does not allow Strength")
    test.eq(next(warlock[1].affix), nil,
        "the conservative class fallback leaves damage-role affixes to the specialization profile")

    local warrior = catalog.getDefaults({ project = "classic" }, "WARRIOR")
    test.eq(next(warrior[1].affix), nil,
        "the conservative physical class fallback also defers affixes to specialization")

    local druid = catalog.getDefaults({ project = "classic" }, "DRUID")
    test.eq(next(druid[1].affix), nil,
        "a hybrid class does not guess one damage type for every specialization")

    local titanRules = catalog.getRuleCatalog({ family = "titan" })
    test.eq(titanRules.affix.MASTERY, nil, "Titan UI hides unavailable mastery")
    test.eq(titanRules.affix.VERSATILITY, nil, "Titan UI hides unavailable versatility")
    local mopRules = catalog.getRuleCatalog({ family = "mop" })
    test.eq(mopRules.affix.MASTERY ~= nil, true, "MoP UI exposes mastery")
    test.eq(mopRules.affix.VERSATILITY, nil, "MoP UI hides unavailable versatility")
    local retailRules = catalog.getRuleCatalog({ family = "retail" })
    test.eq(retailRules.affix.MASTERY ~= nil, true, "Retail UI exposes mastery")
    test.eq(retailRules.affix.VERSATILITY ~= nil, true, "Retail UI exposes versatility")

    -- Class capability base is a defensively copied, id-less profile.
    local base = catalog.getClassBase("titan", "SHAMAN")
    test.eq(base ~= nil, true, "class base exists")
    test.eq(base.id, nil, "class base carries no id")
    test.eq(base.primaryStat.AGILITY, true, "class base keeps agility")
    test.eq(base.primaryStat.INTELLECT, true, "class base keeps intellect")
    base.primaryStat.AGILITY = nil
    test.eq(catalog.getClassBase("titan", "SHAMAN").primaryStat.AGILITY, true, "class base defensively copied")
    test.eq(catalog.getClassBase("titan", "NOPE"), nil, "unknown class has no base")

    -- Class icon helper exposes the stable icon.
    test.eq(catalog.getClassIcon("MAGE"), 135846, "class icon exposed")

    -- The fallback is a family-scoped conservative class profile.
    local fallback = catalog.getClassFallback("titan", "DRUID")
    test.eq(fallback.id, "titan:DRUID:class", "fallback id is family-scoped")
    test.eq(fallback.builtInKey, "titan:DRUID:class", "fallback key is family-scoped")
    test.eq(fallback.tankOnly, false, "fallback is not tank")
    test.eq(fallback.primaryStat.AGILITY, true, "fallback keeps class stats")
    test.eq(catalog.getClassFallback("titan", "NOPE"), nil, "unknown class has no fallback")
end
