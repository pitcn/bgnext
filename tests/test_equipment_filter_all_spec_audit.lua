return function(test)
    BG = { BGNext = {} }
    dofile("Core/BGNext/EquipmentFilterProfiles.lua")
    local catalog = dofile("Core/BGNext/EquipmentFilterSpecializations.lua")

    local function base(family, classToken)
        return BG.BGNext.EquipmentFilterProfiles.getClassBase(family, classToken)
    end
    local function spec(family, classToken, key)
        return catalog.getDefault(family, classToken, key)
    end

    -- ===== Slice 1: class-base weapon and armor corrections =====
    local dh = base("retail", "DEMONHUNTER")
    test.eq(dh.weapon[15], true, "demon hunter filters daggers")
    test.eq(dh.weapon[9], nil, "demon hunter keeps warglaives")

    local evoker = base("retail", "EVOKER")
    test.eq(evoker.weapon[13], nil, "evoker keeps fist weapons")

    -- Rogue ranged stat-stick slot exists only in classic families.
    local rogueClassic = base("vanilla", "ROGUE")
    test.eq(rogueClassic.weapon[2], nil, "classic rogue keeps bows")
    test.eq(rogueClassic.weapon[18], nil, "classic rogue keeps crossbows")
    test.eq(rogueClassic.weapon[16], nil, "classic rogue keeps thrown")
    local rogueModern = base("retail", "ROGUE")
    test.eq(rogueModern.weapon[2], true, "retail rogue filters bows")
    test.eq(rogueModern.armor[1], true, "rogue filters cloth")
    test.eq(rogueModern.armor[2], nil, "rogue keeps leather")

    test.eq(base("mop", "MONK").armor[1], true, "monk filters cloth")
    test.eq(base("mop", "MONK").armor[0], nil, "monk keeps off-hand")
    test.eq(base("retail", "DEMONHUNTER").armor[1], true, "demon hunter filters cloth")
    test.eq(base("retail", "EVOKER").armor[1], true, "evoker filters cloth")
    test.eq(base("retail", "EVOKER").armor[3], nil, "evoker keeps mail")

    -- Armor specialization: classic keeps lower armor, modern tightens.
    test.eq(base("vanilla", "WARRIOR").armor[1], true, "classic warrior filters cloth")
    test.eq(base("vanilla", "WARRIOR").armor[2], nil, "classic warrior keeps leather")
    test.eq(base("retail", "WARRIOR").armor[2], true, "retail warrior filters leather")
    test.eq(base("retail", "WARRIOR").armor[4], nil, "retail warrior keeps plate")

    test.eq(base("vanilla", "DEATHKNIGHT").armor[1], true, "classic death knight filters cloth")
    test.eq(base("retail", "DEATHKNIGHT").armor[2], true, "retail death knight filters leather")
    test.eq(base("retail", "DEATHKNIGHT").armor[4], nil, "retail death knight keeps plate")

    test.eq(base("vanilla", "HUNTER").armor[1], true, "classic hunter filters cloth")
    test.eq(base("vanilla", "HUNTER").armor[2], nil, "classic hunter keeps leather")
    test.eq(base("retail", "HUNTER").armor[2], true, "retail hunter filters leather")
    test.eq(base("retail", "HUNTER").armor[3], nil, "retail hunter keeps mail")

    test.eq(base("vanilla", "SHAMAN").armor[1], nil, "classic shaman keeps cloth")
    test.eq(base("retail", "SHAMAN").armor[1], true, "retail shaman filters cloth")
    test.eq(base("retail", "SHAMAN").armor[2], true, "retail shaman filters leather")
    test.eq(base("retail", "SHAMAN").armor[3], nil, "retail shaman keeps mail")

    test.eq(base("vanilla", "DRUID").armor[1], nil, "classic druid keeps cloth")
    test.eq(base("retail", "DRUID").armor[1], true, "retail druid filters cloth")
    test.eq(base("retail", "DRUID").armor[2], nil, "retail druid keeps leather")

    test.eq(base("vanilla", "PALADIN").armor[1], nil, "classic paladin keeps cloth")
    test.eq(base("retail", "PALADIN").armor[1], true, "retail paladin filters cloth")
    test.eq(base("retail", "PALADIN").armor[4], nil, "retail paladin keeps plate")

    -- ===== Slice 2: mixed-role specialization weapon/armor overrides =====
    -- Warrior: arms filters 1H, fury is version-dependent, prot filters 2H.
    test.eq(spec("titan", "WARRIOR", "tree:WARRIOR:1").weapon[7], true, "arms filters one-handed swords")
    test.eq(spec("titan", "WARRIOR", "tree:WARRIOR:1").weapon[8], nil, "arms keeps two-handed swords")
    test.eq(spec("retail", "WARRIOR", "spec:71").weapon[2], true, "retail arms filters bows")
    test.eq(spec("vanilla", "WARRIOR", "tree:WARRIOR:2").weapon[5], true, "vanilla fury filters two-handed maces")
    test.eq(spec("titan", "WARRIOR", "tree:WARRIOR:2").weapon[5], nil, "titan fury keeps two-handed maces")
    test.eq(spec("titan", "WARRIOR", "tree:WARRIOR:2").weapon[4], true, "titan fury filters one-handed maces")
    test.eq(spec("titan", "WARRIOR", "tree:WARRIOR:3").weapon[5], true, "prot filters two-handed maces")
    test.eq(spec("titan", "WARRIOR", "tree:WARRIOR:3").armor[2], true, "prot filters leather")
    test.eq(spec("titan", "WARRIOR", "tree:WARRIOR:3").armor[4], nil, "prot keeps plate")

    -- Paladin: prot and ret tighten armor.
    test.eq(spec("titan", "PALADIN", "tree:PALADIN:2").armor[1], true, "paladin prot filters cloth")
    test.eq(spec("titan", "PALADIN", "tree:PALADIN:2").armor[6], nil, "paladin prot keeps shield")
    test.eq(spec("titan", "PALADIN", "tree:PALADIN:3").armor[1], true, "ret filters cloth")
    test.eq(spec("titan", "PALADIN", "tree:PALADIN:3").armor[6], true, "ret filters shield")
    test.eq(spec("titan", "PALADIN", "tree:PALADIN:3").armor[4], nil, "ret keeps plate")

    -- Shaman: enhancement filters shield/off-hand; elemental/restoration filter 2H.
    test.eq(spec("titan", "SHAMAN", "tree:SHAMAN:2").armor[6], true, "enhancement filters shield")
    test.eq(spec("titan", "SHAMAN", "tree:SHAMAN:2").armor[0], true, "enhancement filters off-hand")
    test.eq(spec("titan", "SHAMAN", "tree:SHAMAN:1").weapon[5], true, "elemental filters two-handed maces")
    test.eq(spec("titan", "SHAMAN", "tree:SHAMAN:1").weapon[1], true, "elemental filters two-handed axes")
    test.eq(spec("titan", "SHAMAN", "tree:SHAMAN:3").weapon[5], true, "restoration filters two-handed maces")

    -- Druid: feral filters dagger/fist/1H mace + cloth/off-hand; balance/restoration filter 2H mace/polearm.
    test.eq(spec("titan", "DRUID", "tree:DRUID:2").weapon[15], true, "feral filters daggers")
    test.eq(spec("titan", "DRUID", "tree:DRUID:2").armor[1], true, "feral filters cloth")
    test.eq(spec("titan", "DRUID", "tree:DRUID:2").armor[0], true, "feral filters off-hand")
    test.eq(spec("titan", "DRUID", "tree:DRUID:2").armor[2], nil, "feral keeps leather")
    test.eq(spec("titan", "DRUID", "tree:DRUID:1").weapon[5], true, "balance filters two-handed maces")
    test.eq(spec("titan", "DRUID", "tree:DRUID:1").weapon[6], true, "balance filters polearms")
    test.eq(spec("titan", "DRUID", "tree:DRUID:3").weapon[6], true, "restoration filters polearms")
    test.eq(spec("retail", "DRUID", "spec:104").weapon[15], true, "guardian filters daggers")

    -- Death knight: blood filters 1H + leather/mail; frost keeps all; unholy filters 1H modern-only.
    test.eq(spec("titan", "DEATHKNIGHT", "tree:DEATHKNIGHT:1").weapon[7], true, "blood filters one-handed swords")
    test.eq(spec("titan", "DEATHKNIGHT", "tree:DEATHKNIGHT:1").armor[2], true, "blood filters leather")
    test.eq(spec("titan", "DEATHKNIGHT", "tree:DEATHKNIGHT:1").armor[4], nil, "blood keeps plate")
    test.eq(spec("titan", "DEATHKNIGHT", "tree:DEATHKNIGHT:2").weapon[7], nil, "frost keeps one-handed swords")
    test.eq(spec("titan", "DEATHKNIGHT", "tree:DEATHKNIGHT:3").weapon[7], nil, "classic unholy keeps one-handed swords")
    test.eq(spec("retail", "DEATHKNIGHT", "spec:252").weapon[7], true, "retail unholy filters one-handed swords")

    -- Monk: brewmaster/windwalker filter off-hand; mistweaver filters polearms.
    test.eq(spec("mop", "MONK", "spec:268").armor[0], true, "brewmaster filters off-hand")
    test.eq(spec("mop", "MONK", "spec:269").armor[0], true, "windwalker filters off-hand")
    test.eq(spec("mop", "MONK", "spec:270").weapon[6], true, "mistweaver filters polearms")
    test.eq(spec("mop", "MONK", "spec:270").armor[0], nil, "mistweaver keeps off-hand")

    -- ===== Slice 3: per-version affix visibility and default filtering =====
    local function affix(family)
        return BG.BGNext.EquipmentFilterProfiles.getRuleCatalog({ family = family }).affix
    end
    test.eq(affix("vanilla").HASTE, nil, "vanilla hides haste")
    test.eq(affix("vanilla").EXPERTISE, nil, "vanilla hides expertise")
    test.eq(affix("tbc").HASTE ~= nil, true, "tbc shows haste")
    test.eq(affix("tbc").EXPERTISE ~= nil, true, "tbc shows expertise")
    test.eq(affix("tbc").ARMOR_PEN, nil, "tbc hides armor penetration")
    test.eq(affix("titan").ARMOR_PEN ~= nil, true, "titan shows armor penetration")
    test.eq(affix("titan").RESILIENCE, nil, "titan hides resilience")
    test.eq(affix("mop").RESILIENCE ~= nil, true, "mop shows resilience")
    test.eq(affix("mop").ARMOR_PEN, nil, "mop hides armor penetration")
    test.eq(affix("retail").STRENGTH, nil, "retail hides strength affix")
    test.eq(affix("retail").RESILIENCE, nil, "retail hides resilience")
    test.eq(affix("retail").VERSATILITY ~= nil, true, "retail shows versatility")

    -- Default affix filter references only affixes that exist in that family.
    local casterVanilla = spec("vanilla", "MAGE", "tree:MAGE:1")
    test.eq(casterVanilla.affix.ATTACK_POWER, true, "vanilla caster filters attack power")
    test.eq(casterVanilla.affix.ARMOR_PEN, nil, "vanilla caster does not filter armor penetration")
    test.eq(casterVanilla.affix.EXPERTISE, nil, "vanilla caster does not filter expertise")
    local casterTitan = spec("titan", "MAGE", "tree:MAGE:1")
    test.eq(casterTitan.affix.ARMOR_PEN, true, "titan caster filters armor penetration")
    test.eq(casterTitan.affix.EXPERTISE, true, "titan caster filters expertise")
    local casterRetail = spec("retail", "MAGE", "spec:62")
    test.eq(casterRetail.affix.ATTACK_POWER, nil, "retail caster does not filter attack power")
    test.eq(next(casterRetail.affix), nil, "retail caster filters no affix")
    local physicalRetail = spec("retail", "WARRIOR", "spec:71")
    test.eq(physicalRetail.affix.SPELL_POWER, nil, "retail physical does not filter spell power")
end
