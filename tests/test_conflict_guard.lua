return function(test)
    BG = { BGNext = {} }
    local guard = dofile("Core/BGNext/ConflictGuard.lua")
    local addons = {
        { name = "BGLite", project = "BGNext", enabled = true, loaded = true },
        { name = "BiaoGe", enabled = true, loaded = true },
        { name = "DisabledCopy", project = "BGLite", enabled = false, loaded = false },
        { name = "Unrelated", title = "Damage Meter", enabled = true, loaded = true },
    }

    local conflicts = guard.findConflicts("BGLite", addons)
    test.eq(#conflicts, 1, "only one confirmed local conflict")
    test.eq(conflicts[1].name, "BiaoGe", "BiaoGe is reported")
    test.eq(guard.isKnownFamily({ name = "BGNext" }), true, "BGNext folder is known")
    test.eq(guard.isKnownFamily({ name = "Renamed", project = "BGNext" }), true, "BGNext metadata is known")
    test.eq(guard.isKnownFamily({ name = "Renamed", upstream = "BGLite 2.4.0" }), true, "BGLite upstream metadata is known")
    test.eq(guard.isKnownFamily({ name = "Unrelated", title = "BGLite guide" }), false, "title text alone is not enough")
end
