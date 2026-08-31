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

    -- Missing modern API degrades safely.
    test.eq(M.resolve("retail", {}, "MAGE").reason, "api-unavailable", "missing API is safe")
    test.eq(M.resolve("retail", { GetSpecialization = function() return 1 end }, "MAGE").reason,
        "api-unavailable", "missing specialization info is safe")

    -- Old clients resolve the single dominant tree among exactly three trees.
    -- GetTalentTabInfo returns pointsSpent as its third value.
    local old = M.resolve("titan", {
        GetActiveTalentGroup = function() return 1 end,
        GetTalentTabInfo = function(index) return nil, nil, ({ 8, 31, 2 })[index] end,
    }, "WARRIOR")
    test.eq(old.specKey, "tree:WARRIOR:2", "old client resolves dominant tree")

    local tied = M.resolve("titan", {
        GetActiveTalentGroup = function() return 1 end,
        GetTalentTabInfo = function(index) return nil, nil, ({ 20, 20, 0 })[index] end,
    }, "WARRIOR")
    test.eq(tied.specKey, nil, "tied trees are unknown")
    test.eq(tied.reason, "tie", "tie reason is explicit")

    local zero = M.resolve("tbc", {
        GetActiveTalentGroup = function() return 1 end,
        GetTalentTabInfo = function() return nil, nil, 0 end,
    }, "MAGE")
    test.eq(zero.specKey, nil, "zero-point trees are unknown")
    test.eq(zero.reason, "zero", "zero reason is explicit")

    local missingTreeApi = M.resolve("titan", {}, "WARRIOR")
    test.eq(missingTreeApi.reason, "api-unavailable", "missing tree API is safe")

    -- An unknown family is never guessed.
    local unknownFamily = M.resolve("sod", {}, "MAGE")
    test.eq(unknownFamily.specKey, nil, "unknown family is unresolved")
    test.eq(unknownFamily.reason ~= nil, true, "unknown family reports a reason")
end
