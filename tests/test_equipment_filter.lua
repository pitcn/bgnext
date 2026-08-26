return function(test)
    BG = { BGNext = {} }
    local model = dofile("Core/BGNext/EquipmentFilter.lua")
    local defaults = {
        {
            id = "MAGE",
            name = "法师",
            icon = 135846,
            weapon = { [0] = true },
            armor = { [2] = true, [3] = true, [4] = true },
            affix = { STRENGTH = true },
            classRestriction = true,
            ignoreBattleNetBound = false,
            tankOnly = false,
            primaryStat = { INTELLECT = true },
        },
    }
    local root = { equipmentFilters = {} }
    local state = model.ensureCharacter(root, "realm", "Mage", defaults)

    test.eq(state.selectedId, "MAGE", "first default selected")
    test.eq(model.getActiveProfile(root, "realm", "Mage").name, "法师", "active profile returned")
    test.eq(model.getActiveProfile(root, "realm", "Other"), nil, "other character isolated")

    test.eq(model.selectProfile(state, "MAGE"), true, "selected profile toggles")
    test.eq(state.selectedId, nil, "selected profile toggles off")
    test.eq(model.selectProfile(state, "missing"), false, "unknown selection rejected")
    model.selectProfile(state, "MAGE")

    local created, id = model.createProfile(state, {
        name = "  自定义  ", icon = 132089, weapon = {}, armor = {}, affix = {},
        classRestriction = false, ignoreBattleNetBound = false, tankOnly = false,
        primaryStat = {},
    })
    test.eq(created, true, "custom profile created")
    test.eq(state.profiles[id].name, "自定义", "custom profile name trimmed")
    test.eq(model.createProfile(state, { name = "   " }), false, "empty profile rejected")

    test.eq(model.updateProfile(state, id, { name = "修改", unknown = true }), true, "profile updated")
    test.eq(state.profiles[id].name, "修改", "known field updated")
    test.eq(state.profiles[id].unknown, nil, "unknown patch ignored")
    test.eq(model.moveProfile(state, id, -1), true, "profile moved")
    test.eq(state.order[1], id, "profile order changed")

    test.eq(model.deleteProfile(state, id), true, "profile deleted")
    test.eq(state.profiles[id], nil, "deleted profile removed")
    test.eq(state.selectedId, "MAGE", "deleting inactive profile preserves selection")

    state.profiles.MAGE.name = "changed"
    model.resetDefaults(state, defaults)
    test.eq(state.profiles.MAGE.name, "法师", "reset restores defaults")

    local otherDefaults = model.ensureCharacter(root, "realm", "Other", defaults)
    otherDefaults.profiles.MAGE.name = "other"
    test.eq(state.profiles.MAGE.name, "法师", "character state is not aliased")
    test.eq(defaults[1].name, "法师", "source defaults are not mutated")
end
