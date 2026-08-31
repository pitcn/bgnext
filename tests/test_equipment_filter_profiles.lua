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
    test.eq(warlock[1].affix.ATTACK_POWER, true,
        "a pure spellcaster filters attack-power gear by default")
    test.eq(warlock[1].affix.SPELL_POWER, nil,
        "a pure spellcaster retains spell-power gear by default")

    local warrior = catalog.getDefaults({ project = "classic" }, "WARRIOR")
    test.eq(warrior[1].affix.SPELL_POWER, true,
        "a pure physical class filters spell-power gear by default")
    test.eq(warrior[1].affix.ATTACK_POWER, nil,
        "a pure physical class retains attack-power gear by default")

    local druid = catalog.getDefaults({ project = "classic" }, "DRUID")
    test.eq(next(druid[1].affix), nil,
        "a hybrid class does not guess one damage type for every specialization")
end
