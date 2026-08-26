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
end
