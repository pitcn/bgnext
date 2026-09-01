return function(test)
    BG = { BGNext = {} }
    local M = dofile("Core/BGNext/SpecializationAdapter.lua")

    -- Family detection uses the same ordered flags as OwnCharactersAdapters:
    -- the anniversary client sets both IsWLK and IsTitan, so Titan must win.
    test.eq(M.familyFromFlags({ IsTitan = true, IsWLK = true }), "titan", "Titan wins ordered flags")
    test.eq(M.familyFromFlags({ IsMOP = true }), "mop", "MoP family detected")
    test.eq(M.familyFromFlags({ IsRetail = true }), "retail", "Retail family detected")
    test.eq(M.familyFromFlags({ IsTBC = true }), "tbc", "TBC family detected")
    test.eq(M.familyFromFlags({ IsVanilla = true }), "vanilla", "Vanilla family detected")
    test.eq(M.familyFromFlags({ IsVanilla_Sod = true, IsVanilla = true }), nil, "Season of Discovery is unsupported")
    test.eq(M.familyFromFlags(nil), nil, "missing flags are unknown")

    -- Modern clients resolve the stable specialization ID, never the index.
    local modern = M.resolve("retail", {
        GetSpecialization = function() return 2 end,
        GetSpecializationInfo = function(index) return index == 2 and 72 or nil end,
    }, "WARRIOR")
    test.eq(modern.specKey, "spec:72", "modern client stores stable spec ID")
    test.eq(modern.reason, nil, "modern resolution is not a failure")

    local namespaced = M.resolve("retail", {
        C_SpecializationInfo = {
            GetSpecialization = function() return 2 end,
            GetSpecializationInfo = function(index)
                if index == 2 then return 72, "Fury", nil, 132347 end
            end,
        },
    }, "WARRIOR")
    test.eq(namespaced.specKey, "spec:72", "modern namespace resolves the stable spec ID")
    test.eq(namespaced.name, "Fury", "modern namespace returns Blizzard specialization name")
    test.eq(namespaced.icon, 132347, "modern namespace returns Blizzard specialization icon")

    -- Missing modern API degrades safely.
    test.eq(M.resolve("retail", {}, "MAGE").reason, "api-unavailable", "missing API is safe")
    test.eq(M.resolve("retail", { GetSpecialization = function() return 1 end }, "MAGE").reason,
        "api-unavailable", "missing specialization info is safe")

    -- BGLite's supported old clients expose committed points in the fifth slot.
    local old = M.resolve("titan", {
        GetActiveTalentGroup = function() return 1 end,
        GetTalentTabInfo = function(index)
            return ({ "Arms", "Fury", "Protection" })[index], 900000 + index,
                nil, nil, ({ 8, 31, 2 })[index]
        end,
        GetNumTalents = function() return 3 end,
        GetTalentInfo = function(tabIndex, talentIndex)
            local icons = {
                [1] = { 111, 112, 113 },
                [2] = { 221, 222, 223 },
                [3] = { 331, 332, 333 },
            }
            local tiers = { 1, 7, 3 }
            return "Talent", icons[tabIndex][talentIndex], tiers[talentIndex], talentIndex
        end,
    }, "WARRIOR")
    test.eq(old.specKey, "tree:WARRIOR:2", "old client resolves dominant tree")
    test.eq(old.name, "Fury", "old client returns the talent-tree name")
    test.eq(old.icon, 222, "old client uses a square signature-talent icon")
    test.eq(old.legacyIcon, 900002, "old client exposes the former tab background only for migration")

    local oldMetadata = M.getMetadata("titan", {
        GetActiveTalentGroup = function() return 1 end,
        GetTalentTabInfo = function(index) return "Tree " .. index, 800000 + index end,
        GetNumTalents = function() return 2 end,
        GetTalentInfo = function(_, talentIndex)
            return "Talent", 700000 + talentIndex, talentIndex, 1
        end,
    }, "WARRIOR", "tree:WARRIOR:3")
    test.eq(oldMetadata.icon, 700002, "tree metadata chooses the deepest square talent icon")
    test.eq(oldMetadata.legacyIcon, 800003, "tree metadata retains the tab background migration marker")

    local tied = M.resolve("titan", {
        GetActiveTalentGroup = function() return 1 end,
        GetTalentTabInfo = function(index) return nil, nil, nil, nil, ({ 20, 20, 0 })[index] end,
    }, "WARRIOR")
    test.eq(tied.specKey, nil, "tied trees are unknown")
    test.eq(tied.reason, "tie", "tie reason is explicit")

    local zero = M.resolve("tbc", {
        GetActiveTalentGroup = function() return 1 end,
        GetTalentTabInfo = function() return nil, nil, nil, nil, 0 end,
    }, "MAGE")
    test.eq(zero.specKey, nil, "zero-point trees are unknown")
    test.eq(zero.reason, "zero", "zero reason is explicit")

    local missingTreeApi = M.resolve("titan", {}, "WARRIOR")
    test.eq(missingTreeApi.reason, "api-unavailable", "missing tree API is safe")

    local thirdSlotFallback = M.resolve("tbc", {
        GetTalentTabInfo = function(index) return nil, nil, ({ 3, 18, 0 })[index] end,
    }, "MAGE")
    test.eq(thirdSlotFallback.specKey, "tree:MAGE:2", "third-slot clients remain compatible")

    -- An unknown family is never guessed.
    local unknownFamily = M.resolve("sod", {}, "MAGE")
    test.eq(unknownFamily.specKey, nil, "unknown family is unresolved")
    test.eq(unknownFamily.reason ~= nil, true, "unknown family reports a reason")
end
