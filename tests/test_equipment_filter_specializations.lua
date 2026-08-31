return function(test)
    BG = { BGNext = {} }
    dofile("Core/BGNext/EquipmentFilterProfiles.lua")
    local catalog = dofile("Core/BGNext/EquipmentFilterSpecializations.lua")

    local families = { "vanilla", "tbc", "titan", "mop", "retail" }

    -- Physical profiles filter spell power and keep attack power.
    local arms = catalog.getDefault("titan", "WARRIOR", "tree:WARRIOR:1")
    test.eq(arms.affix.SPELL_POWER, true, "physical profile filters spell power")
    test.eq(arms.affix.ATTACK_POWER, nil, "physical profile keeps attack power")

    -- Caster profiles filter attack power and keep spell power.
    local elemental = catalog.getDefault("titan", "SHAMAN", "tree:SHAMAN:1")
    test.eq(elemental.affix.ATTACK_POWER, true, "caster profile filters attack power")
    test.eq(elemental.affix.SPELL_POWER, nil, "caster profile keeps spell power")

    -- Healer profiles keep mana regeneration.
    local restoration = catalog.getDefault("titan", "SHAMAN", "tree:SHAMAN:3")
    test.eq(restoration.affix.MANA_REGEN, nil, "healer keeps mana regeneration")

    -- Tank profiles enable the tank-only rule.
    local protection = catalog.getDefault("titan", "WARRIOR", "tree:WARRIOR:3")
    test.eq(protection.tankOnly, true, "tank profile enables tank-only rule")
    test.eq(catalog.getDefault("retail", "WARRIOR", "spec:73").tankOnly, false,
        "retail tank does not use legacy tank-stat filtering")
    test.eq(catalog.getDefault("mop", "WARRIOR", "spec:73").tankOnly, true,
        "MoP tank uses the mastery-aware tank filter")

    -- Feral is a three-tree client ambiguity, never guessed as tank or cat.
    local feral = catalog.getDefault("titan", "DRUID", "tree:DRUID:2")
    test.eq(feral.builtInKey, "titan:DRUID:tree:DRUID:2", "ambiguous feral has stable key")
    test.eq(feral.tankOnly, false, "ambiguous feral does not guess tank")
    test.eq(feral.primaryStat.AGILITY, true, "ambiguous feral keeps agility")

    -- Modern clients resolve the stable spec ID.
    test.eq(catalog.getDefault("retail", "WARRIOR", "spec:72").primaryStat.STRENGTH, true,
        "retail Fury selects strength")
    test.eq(catalog.getDefault("retail", "WARRIOR", "spec:999999"), nil,
        "unverified spec is absent")
    test.eq(catalog.getDefault("wrath", "MAGE", "tree:MAGE:1"), nil,
        "unverified family has no catalog")

    local retailMarksman = catalog.getDefault("retail", "HUNTER", "spec:254")
    local retailSurvival = catalog.getDefault("retail", "HUNTER", "spec:255")
    test.eq(retailMarksman.weapon[6], true, "retail ranged hunter filters polearms")
    test.eq(retailSurvival.weapon[2], true, "retail Survival filters bows")
    test.eq(retailSurvival.weapon[6], nil, "retail Survival keeps polearms")
    local mopSurvival = catalog.getDefault("mop", "HUNTER", "spec:255")
    test.eq(mopSurvival.weapon[2], nil, "MoP Survival remains ranged")
    test.eq(mopSurvival.weapon[6], true, "MoP Survival filters polearms")

    local holyPaladin = catalog.getDefault("titan", "PALADIN", "tree:PALADIN:1")
    local retPaladin = catalog.getDefault("titan", "PALADIN", "tree:PALADIN:3")
    test.eq(holyPaladin.weapon[1], true, "Holy Paladin filters two-handed axes")
    test.eq(retPaladin.weapon[4], true, "Retribution Paladin filters one-handed maces")
    test.eq(retPaladin.armor[6], true, "Retribution Paladin filters shields")

    -- Iterate every declared profile and assert its shape.
    for _, family in ipairs(families) do
        local classes = catalog.listClasses(family)
        test.eq(type(classes), "table", family .. " lists classes")
        test.eq(#classes > 0, true, family .. " has classes")
        for _, classToken in ipairs(classes) do
            local profiles = catalog.list(family, classToken)
            test.eq(type(profiles), "table", family .. " " .. classToken .. " list")
            test.eq(#profiles > 0, true, family .. " " .. classToken .. " has specs")
            local seen = {}
            for _, profile in ipairs(profiles) do
                test.eq(type(profile.id), "string", "profile id is a string")
                test.eq(profile.id ~= "", true, "profile id is non-empty")
                test.eq(seen[profile.id], nil, "profile id is unique")
                seen[profile.id] = true
                test.eq(profile.id, profile.builtInKey, "id matches builtInKey")
                test.eq(type(profile.name), "string", "profile name is a string")
                test.eq(profile.name ~= "", true, "profile name is non-empty")
                test.eq(profile.icon ~= nil, true, "profile has an icon")
                test.eq(type(profile.weapon), "table", "weapon rule table present")
                test.eq(type(profile.armor), "table", "armor rule table present")
                test.eq(type(profile.affix), "table", "affix rule table present")
                test.eq(type(profile.primaryStat), "table", "primaryStat rule table present")
                test.eq(type(profile.classRestriction), "boolean", "classRestriction is boolean")
                test.eq(type(profile.ignoreBattleNetBound), "boolean", "ignoreBattleNetBound is boolean")
                test.eq(type(profile.tankOnly), "boolean", "tankOnly is boolean")
            end
        end
    end

    -- Defaults are defensively copied.
    local copy1 = catalog.getDefault("titan", "WARRIOR", "tree:WARRIOR:1")
    copy1.name = "mutated"
    copy1.affix.SPELL_POWER = nil
    copy1.primaryStat.STRENGTH = nil
    local copy2 = catalog.getDefault("titan", "WARRIOR", "tree:WARRIOR:1")
    test.eq(copy2.name, "武器", "default name defensively copied")
    test.eq(copy2.affix.SPELL_POWER, true, "default affix defensively copied")
    test.eq(copy2.primaryStat.STRENGTH, true, "default primaryStat defensively copied")

    -- The fallback is a conservative, family-scoped class profile.
    local fallback = catalog.getFallback("titan", "WARRIOR")
    test.eq(fallback ~= nil, true, "fallback exists")
    test.eq(fallback.tankOnly, false, "fallback is not tank")
    test.eq(fallback.builtInKey, "titan:WARRIOR:class", "fallback key is family-scoped")
    test.eq(fallback.primaryStat.STRENGTH, true, "fallback keeps class strength")
    test.eq(catalog.getFallback("retail", "MAGE").primaryStat.INTELLECT, true,
        "fallback keeps class intellect")
    test.eq(catalog.getFallback("titan", "NOPE"), nil, "unknown class has no fallback")
end
