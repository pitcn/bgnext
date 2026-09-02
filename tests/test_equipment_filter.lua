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
    test.eq(fresh.enabled, true, "equipment filtering starts enabled")
    local selectedBeforeDisable = fresh.selectedId
    local modeBeforeDisable = fresh.selectionMode
    test.eq(model.setEnabled(fresh, false), true, "the global shortcut disables filtering")
    test.eq(model.getActiveProfile(root, "realm", "Mage"), nil,
        "disabled filtering exposes no active profile to the filter engine")
    test.eq(fresh.selectedId, selectedBeforeDisable, "disabling preserves the selected profile")
    test.eq(fresh.selectionMode, modeBeforeDisable, "disabling preserves follow or manual mode")
    test.eq(model.setEnabled(fresh, true), true, "the same shortcut restores filtering")
    test.eq(model.getActiveProfile(root, "realm", "Mage"), fresh.profiles[selectedBeforeDisable],
        "restoring filtering reuses the previous profile")
    test.eq(fresh.selectionMode, "follow-spec", "new state follows specialization")
    test.eq(fresh.selectedId, "retail:MAGE:spec:63", "new state selects resolved specialization")
    test.eq(model.getActiveProfile(root, "realm", "Mage").name, "火焰", "active profile returned")
    test.eq(model.getActiveProfile(root, "realm", "Other"), nil, "other character isolated")

    -- Profiles created by the first specialization build used the class icon for
    -- every built-in. A later load upgrades only those stale class icons to the
    -- Blizzard specialization icons and leaves a custom icon untouched.
    local classIcon = "Interface/Icons/classicon_hunter"
    local badHunterWeapons = { [0] = true, [1] = true, [4] = true, [5] = true, [6] = true }
    local iconDefaults = {
        { id = "titan:HUNTER:tree:HUNTER:1", builtInKey = "titan:HUNTER:tree:HUNTER:1", name = "野兽控制", icon = 111,
            weapon = { [4] = true, [5] = true }, upgradeWeaponFrom = badHunterWeapons },
        { id = "titan:HUNTER:tree:HUNTER:2", builtInKey = "titan:HUNTER:tree:HUNTER:2", name = "射击", icon = 222,
            weapon = { [4] = true, [5] = true }, upgradeWeaponFrom = badHunterWeapons },
        { id = "titan:HUNTER:tree:HUNTER:3", builtInKey = "titan:HUNTER:tree:HUNTER:3", name = "生存",
            icon = 333, upgradeIconFrom = 444 },
        { id = "titan:HUNTER:class", builtInKey = "titan:HUNTER:class", name = "猎人", icon = classIcon },
    }
    local iconRoot = { equipmentFilters = { realm = { Hunter = {
        selectionMode = "follow-spec",
        selectedId = "titan:HUNTER:tree:HUNTER:1",
        order = { "titan:HUNTER:tree:HUNTER:1", "titan:HUNTER:tree:HUNTER:2",
            "titan:HUNTER:tree:HUNTER:3", "titan:HUNTER:class", "custom-1" },
        profiles = {
            ["titan:HUNTER:tree:HUNTER:1"] = { id = "titan:HUNTER:tree:HUNTER:1", name = "野兽控制", icon = classIcon,
                weapon = { [0] = true, [1] = true, [4] = true, [5] = true, [6] = true }, builtInKey = "titan:HUNTER:tree:HUNTER:1" },
            ["titan:HUNTER:tree:HUNTER:2"] = { id = "titan:HUNTER:tree:HUNTER:2", name = "射击", icon = classIcon,
                weapon = { [0] = true, [4] = true, [5] = true, [6] = true }, builtInKey = "titan:HUNTER:tree:HUNTER:2" },
            ["titan:HUNTER:tree:HUNTER:3"] = { id = "titan:HUNTER:tree:HUNTER:3", name = "生存", icon = 444, builtInKey = "titan:HUNTER:tree:HUNTER:3" },
            ["titan:HUNTER:class"] = { id = "titan:HUNTER:class", name = "猎人", icon = classIcon, builtInKey = "titan:HUNTER:class" },
            ["custom-1"] = { id = "custom-1", name = "自定义", icon = 999 },
        },
    } } } }
    local iconState = model.ensureCharacter(iconRoot, "realm", "Hunter", iconDefaults,
        { builtInId = "titan:HUNTER:tree:HUNTER:1" })
    test.eq(iconState.profiles["titan:HUNTER:tree:HUNTER:1"].icon, 111,
        "stale built-in class icon upgrades to the specialization icon")
    test.eq(iconState.profiles["titan:HUNTER:tree:HUNTER:2"].icon, 222,
        "every built-in specialization icon upgrades, not only the active one")
    test.eq(iconState.profiles["titan:HUNTER:tree:HUNTER:3"].icon, 333,
        "a stored talent-tab background upgrades to the square specialization icon")
    test.eq(iconState.profiles["titan:HUNTER:tree:HUNTER:1"].weapon[6], nil,
        "known bad built-in hunter weapon defaults are upgraded")
    test.eq(iconState.profiles["titan:HUNTER:tree:HUNTER:2"].weapon[0], true,
        "a player-modified built-in weapon profile is preserved")
    test.eq(iconState.profiles["custom-1"].icon, 999, "custom profile icon is preserved")

    -- Selecting a profile pauses following and enters manual mode.
    local _, customId = model.createProfile(fresh, {
        name = "  自定义  ", icon = 132089, weapon = {}, armor = {}, affix = {},
        classRestriction = false, ignoreBattleNetBound = false, tankOnly = false, primaryStat = {},
    })
    test.eq(customId, "custom-1", "custom id assigned")
    test.eq(fresh.profiles[customId].name, "自定义", "custom profile name trimmed")
    test.eq(model.createProfile(fresh, { name = "   " }), false, "empty profile rejected")

    model.setEnabled(fresh, false)
    model.selectProfile(fresh, customId)
    test.eq(fresh.enabled, true, "choosing a profile re-enables filtering")
    test.eq(fresh.selectionMode, "manual", "custom selection pauses following")
    test.eq(fresh.selectedId, customId, "custom selection selects the custom profile")
    test.eq(model.selectProfile(fresh, "missing"), false, "unknown selection rejected")

    -- The dedicated follow entry resumes following and selects the new built-in.
    model.setEnabled(fresh, false)
    model.followSpecialization(fresh, "retail:MAGE:spec:64")
    test.eq(fresh.enabled, true, "choosing follow-specialization re-enables filtering")
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
    model.setEnabled(fresh, false)
    model.resetDefaults(fresh, specDefaults(), "retail:MAGE:spec:63")
    test.eq(fresh.enabled, true, "reset restores filtering")
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
    test.eq(legacy.enabled, true, "existing profiles migrate to enabled without changing their selection")
    test.eq(legacy.selectionMode, "manual", "existing state migrates without silent switching")
    test.eq(legacy.selectedId, "MAGE", "migration preserves selection")
    test.eq(legacy.profiles["custom-1"].name, "自定义", "migration preserves custom profile")
    test.eq(legacy.order[2], "custom-1", "migration preserves profile order")

    model.followSpecialization(legacy, "retail:MAGE:spec:63", specDefaults())
    test.eq(legacy.selectionMode, "follow-spec", "legacy state can explicitly enable following")
    test.eq(legacy.selectedId, "retail:MAGE:spec:63", "explicit follow installs and selects spec defaults")
    test.eq(legacy.profiles["custom-1"].name, "自定义", "explicit follow preserves legacy custom profiles")

    -- Profile lifecycle: update, move, delete.
    local edited = model.updateProfile(legacy, "custom-1", { name = "修改", unknown = true })
    test.eq(edited, true, "profile updated")
    test.eq(legacy.profiles["custom-1"].name, "修改", "known field updated")
    test.eq(legacy.profiles["custom-1"].unknown, nil, "unknown patch ignored")
    test.eq(model.moveProfile(legacy, "custom-1", -#legacy.order), true, "profile moved")
    test.eq(legacy.order[1], "custom-1", "profile order changed")
    test.eq(model.deleteProfile(legacy, "custom-1"), true, "profile deleted")
    test.eq(legacy.profiles["custom-1"], nil, "deleted profile removed")
    test.eq(legacy.selectedId, "retail:MAGE:spec:63", "deleting inactive profile preserves selection")

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
    test.eq(source:find("ItemPrimaryStats.new", 1, true) ~= nil, true,
        "all clients use the shared primary-stat detector for explicit profile rules")
    test.eq(source:find("itemAttributeCache", 1, true), nil,
        "specialization compatibility does not restore the legacy Retail-only attribute cache")
end
