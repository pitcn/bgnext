return function(test)
    BG = { BGNext = {} }
    local model = dofile("Core/BGNext/EquipmentFilter.lua")

    local function specDefaults()
        return {
            { id = "retail:MAGE:spec:62", builtInKey = "retail:MAGE:spec:62", name = "奥术", icon = 135846,
                weapon = { [0] = true }, armor = { [2] = true, [3] = true, [4] = true }, affix = { STRENGTH = true },
                classRestriction = true, ignoreBattleNetBound = false, tankOnly = false, primaryStat = { INTELLECT = true } },
            { id = "retail:MAGE:spec:63", builtInKey = "retail:MAGE:spec:63", name = "火焰", icon = 135846,
                weapon = { [0] = true }, armor = { [2] = true, [3] = true, [4] = true }, affix = { STRENGTH = true },
                classRestriction = true, ignoreBattleNetBound = false, tankOnly = false, primaryStat = { INTELLECT = true } },
            { id = "retail:MAGE:spec:64", builtInKey = "retail:MAGE:spec:64", name = "冰霜", icon = 135846,
                weapon = { [0] = true }, armor = { [2] = true, [3] = true, [4] = true }, affix = { STRENGTH = true },
                classRestriction = true, ignoreBattleNetBound = false, tankOnly = false, primaryStat = { INTELLECT = true } },
        }
    end

    -- A brand-new character follows the resolved specialization.
    local root = { equipmentFilters = {} }
    local fresh = model.ensureCharacter(root, "realm", "Mage", specDefaults(),
        { specKey = "spec:63", builtInId = "retail:MAGE:spec:63" })
    test.eq(fresh.selectionMode, "follow-spec", "new state follows specialization")
    test.eq(fresh.selectedId, "retail:MAGE:spec:63", "new state selects resolved specialization")
    test.eq(model.getActiveProfile(root, "realm", "Mage").name, "火焰", "active profile returned")
    test.eq(model.getActiveProfile(root, "realm", "Other"), nil, "other character isolated")

    -- Selecting a profile pauses following and enters manual mode.
    local _, customId = model.createProfile(fresh, {
        name = "  自定义  ", icon = 132089, weapon = {}, armor = {}, affix = {},
        classRestriction = false, ignoreBattleNetBound = false, tankOnly = false, primaryStat = {},
    })
    test.eq(customId, "custom-1", "custom id assigned")
    test.eq(fresh.profiles[customId].name, "自定义", "custom profile name trimmed")
    test.eq(model.createProfile(fresh, { name = "   " }), false, "empty profile rejected")

    model.selectProfile(fresh, customId)
    test.eq(fresh.selectionMode, "manual", "custom selection pauses following")
    test.eq(fresh.selectedId, customId, "custom selection selects the custom profile")
    test.eq(model.selectProfile(fresh, "missing"), false, "unknown selection rejected")

    -- The dedicated follow entry resumes following and selects the new built-in.
    model.followSpecialization(fresh, "retail:MAGE:spec:64")
    test.eq(fresh.selectionMode, "follow-spec", "explicit follow resumes following")
    test.eq(fresh.selectedId, "retail:MAGE:spec:64", "follow selects new built-in")

    -- An unknown specialization preserves the active selection.
    model.applyResolvedSpecialization(fresh, nil)
    test.eq(fresh.selectedId, "retail:MAGE:spec:64", "unknown specialization preserves selection")
    model.applyResolvedSpecialization(fresh, "retail:MAGE:spec:62")
    test.eq(fresh.selectedId, "retail:MAGE:spec:62", "resolved specialization switches selection")
    model.selectProfile(fresh, customId)
    model.applyResolvedSpecialization(fresh, "retail:MAGE:spec:63")
    test.eq(fresh.selectedId, customId, "manual selection is never switched by resolution")

    -- Reset rebuilds built-ins, preserves customs, and returns to follow mode.
    fresh.profiles[customId].name = "我的方案"
    model.resetDefaults(fresh, specDefaults(), "retail:MAGE:spec:63")
    test.eq(fresh.selectionMode, "follow-spec", "reset returns to follow mode")
    test.eq(fresh.selectedId, "retail:MAGE:spec:63", "reset selects resolved built-in")
    test.eq(fresh.profiles[customId] ~= nil, true, "reset preserves custom profile")
    test.eq(fresh.profiles[customId].name, "我的方案", "reset preserves custom content")
    test.eq(fresh.profiles["retail:MAGE:spec:63"].name, "火焰", "reset restores built-in defaults")

    local missingPrimaryStat = {
        equipmentFilters = {
            realm = {
                Warlock = {
                    selectedId = "WARLOCK",
                    order = { "WARLOCK", "custom-1" },
                    profiles = {
                        WARLOCK = {
                            id = "WARLOCK", name = "术士", builtInKey = "WARLOCK",
                            weapon = {}, armor = {}, affix = {},
                        },
                        ["custom-1"] = {
                            id = "custom-1", name = "自定义", weapon = {}, armor = {}, affix = {},
                        },
                    },
                },
            },
        },
    }
    local warlockDefaults = {
        {
            id = "WARLOCK", name = "术士", builtInKey = "WARLOCK", icon = 136145,
            weapon = {}, armor = {}, affix = {}, primaryStat = { INTELLECT = true },
        },
    }
    local migrated = model.ensureCharacter(missingPrimaryStat, "realm", "Warlock", warlockDefaults)
    test.eq(migrated.profiles.WARLOCK.primaryStat.INTELLECT, true,
        "a legacy built-in profile missing primaryStat receives its default")
    test.eq(migrated.profiles["custom-1"].primaryStat, nil,
        "a custom profile missing primaryStat is not changed")

    migrated.profiles.WARLOCK.primaryStat = {}
    model.ensureCharacter(missingPrimaryStat, "realm", "Warlock", warlockDefaults)
    test.eq(next(migrated.profiles.WARLOCK.primaryStat), nil,
        "an intentionally empty built-in primaryStat selection is preserved")

    migrated.profiles.WARLOCK.primaryStat = { STRENGTH = true }
    model.ensureCharacter(missingPrimaryStat, "realm", "Warlock", warlockDefaults)
    test.eq(migrated.profiles.WARLOCK.primaryStat.STRENGTH, true,
        "a customized built-in primaryStat selection is preserved")
    test.eq(migrated.profiles.WARLOCK.primaryStat.INTELLECT, nil,
        "defaults do not overwrite a customized built-in primaryStat selection")

    -- Reset with an unknown built-in selects the first built-in (conservative fallback).
    model.resetDefaults(fresh, specDefaults(), nil)
    test.eq(fresh.selectedId, "retail:MAGE:spec:62", "unknown reset selects first built-in")

    -- A pre-feature state migrates without silently switching or losing content.
    local legacyRoot = { equipmentFilters = { realm = { Mage = {
        selectedId = "MAGE",
        order = { "MAGE", "custom-1" },
        profiles = {
            MAGE = { id = "MAGE", name = "法师", icon = 135846, weapon = {}, armor = {}, affix = {},
                classRestriction = true, ignoreBattleNetBound = false, tankOnly = false,
                primaryStat = { INTELLECT = true }, builtInKey = "MAGE" },
            ["custom-1"] = { id = "custom-1", name = "自定义", icon = 132089, weapon = {}, armor = {},
                affix = {}, classRestriction = true, ignoreBattleNetBound = false, tankOnly = false,
                primaryStat = {} },
        },
    } } } }
    local legacy = model.ensureCharacter(legacyRoot, "realm", "Mage", specDefaults(), { specKey = "spec:63" })
    test.eq(legacy.selectionMode, "manual", "existing state migrates without silent switching")
    test.eq(legacy.selectedId, "MAGE", "migration preserves selection")
    test.eq(legacy.profiles["custom-1"].name, "自定义", "migration preserves custom profile")
    test.eq(legacy.order[2], "custom-1", "migration preserves profile order")

    -- Profile lifecycle: update, move, delete.
    local edited = model.updateProfile(legacy, "custom-1", { name = "修改", unknown = true })
    test.eq(edited, true, "profile updated")
    test.eq(legacy.profiles["custom-1"].name, "修改", "known field updated")
    test.eq(legacy.profiles["custom-1"].unknown, nil, "unknown patch ignored")
    test.eq(model.moveProfile(legacy, "custom-1", -1), true, "profile moved")
    test.eq(legacy.order[1], "custom-1", "profile order changed")
    test.eq(model.deleteProfile(legacy, "custom-1"), true, "profile deleted")
    test.eq(legacy.profiles["custom-1"], nil, "deleted profile removed")
    test.eq(legacy.selectedId, "MAGE", "deleting inactive profile preserves selection")

    -- Defensive copies and character isolation.
    local other = model.ensureCharacter(root, "realm", "Other", specDefaults(),
        { specKey = "spec:62", builtInId = "retail:MAGE:spec:62" })
    other.profiles["retail:MAGE:spec:62"].name = "other"
    test.eq(fresh.profiles["retail:MAGE:spec:62"].name, "奥术", "character state is not aliased")
    test.eq(specDefaults()[1].name, "奥术", "source defaults are not mutated")

    -- Rule selection reads.
    test.eq(model.isRuleSelected(fresh.profiles["retail:MAGE:spec:62"], "classRestriction", nil, true), true,
        "enabled boolean rule is selected")
    test.eq(model.isRuleSelected(fresh.profiles["retail:MAGE:spec:62"], "ignoreBattleNetBound", nil, true), false,
        "disabled boolean rule is read without indexing the boolean")
    test.eq(model.isRuleSelected(fresh.profiles["retail:MAGE:spec:62"], "armor", 4, false), true,
        "table rule selection is read by id")

    -- BGLite integration reads the active profile accessor and never the legacy DB.
    local file = assert(io.open("Core/function2.lua", "rb"))
    local source = file:read("*a")
    file:close()
    test.eq(source:find("BG.BGNext.GetActiveEquipmentFilterProfile", 1, true) ~= nil, true,
        "BGLite filter engine reads the BGNext active profile accessor")
    test.eq(source:find("BiaoGe.FilterClassItemDB", 1, true), nil,
        "BGLite filter engine does not write or read the legacy profile database")
    test.eq(source:find("local editor = filterFrame and (filterFrame.EditFrame or filterFrame.AddFrame)", 1, true) ~= nil,
        true, "filter refresh accepts either the BGNext editor or the legacy placeholder")
    test.eq(source:find("C_ChatInfo.SendAddonMessage", 1, true), nil,
        "local equipment filtering adds no addon communication")
end
