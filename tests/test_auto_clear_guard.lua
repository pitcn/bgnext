local Guard = dofile("Core/BGNext/AutoClearGuard.lua")

return function(test)
    -- TOC-style load registration: a real WoW TOC load runs the file and
    -- discards its return value, so the module must publish itself into the
    -- runtime namespace exactly like every other BGNext runtime module.
    do
        local savedBG = BG
        BG = { BGNext = {} }
        local returned = dofile("Core/BGNext/AutoClearGuard.lua")
        test.eq(type(returned), "table", "AutoClearGuard returns its module table")
        test.eq(type(BG.BGNext.AutoClearGuard), "table", "TOC load registers the module into BG.BGNext")
        test.eq(BG.BGNext.AutoClearGuard, returned, "the registered module is the returned table")
        BG = savedBG
    end

    -- needsConfirmation: ask only when enabled + new CD + old content
    test.eq(Guard.needsConfirmation(true, true, true), true, "enabled + new CD + content asks")
    test.eq(Guard.needsConfirmation(false, true, true), false, "disabled setting never asks")
    test.eq(Guard.needsConfirmation(true, false, true), false, "not a new CD never asks")
    test.eq(Guard.needsConfirmation(true, true, false), false, "empty table never asks")
    test.eq(Guard.needsConfirmation(false, false, false), false, "all-false never asks")
    test.eq(Guard.needsConfirmation(true, true, nil), false, "missing content is treated as empty")

    -- createPending validates the table id
    test.eq(Guard.createPending(nil, 1), nil, "nil table id yields nil")
    test.eq(Guard.createPending("", 1), nil, "empty table id yields nil")
    local p = Guard.createPending("ZUG", 1, { instanceID = 309, startB = 3, endB = 8 })
    test.eq(p.fb, "ZUG", "captures the table id")
    test.eq(p.clearType, 1, "captures the clear reason")
    test.eq(p.instanceID, 309, "captures the instance id")
    test.eq(p.startB, 3, "captures the first boss row")
    test.eq(p.endB, 8, "captures the last boss row")
    test.eq(p.state, Guard.STATE_PENDING, "starts pending")
    test.eq(Guard.createPending("ZUG", 1), nil, "range clear requires a captured scope")
    test.eq(Guard.createPending("ZUG", 1, { instanceID = 309, startB = 8, endB = 3 }), nil,
        "reversed boss ranges are rejected")

    -- accept with content clears exactly once
    test.eq(Guard.accept(p, true, 999), "skip", "accept rejects a changed instance")
    test.eq(p.state, Guard.STATE_SKIPPED, "changed instance consumes the stale request")

    p = Guard.createPending("ZUG", 1, { instanceID = 309, startB = 3, endB = 8 })
    test.eq(Guard.accept(p, true, 309), "clear", "accept with matching scope and content clears")
    test.eq(p.state, Guard.STATE_CLEARED, "state advances to cleared")
    test.eq(Guard.accept(p, true), "skip", "a cleared request never clears again")

    -- accept with an emptied table skips
    local p2 = Guard.createPending("ZUG", 2)
    test.eq(Guard.accept(p2, false), "skip", "emptied table skips")
    test.eq(p2.state, Guard.STATE_SKIPPED, "state advances to skipped")
    test.eq(Guard.accept(p2, true), "skip", "a skipped request never clears later")

    -- refuse / cancel abandons without clearing
    local p3 = Guard.createPending("ZUG", 1, { instanceID = 309, startB = 3, endB = 8 })
    test.eq(Guard.refuse(p3), false, "refuse returns false (do not clear)")
    test.eq(p3.state, Guard.STATE_CANCELLED, "state advances to cancelled")
    test.eq(Guard.accept(p3, true), "skip", "a cancelled request never clears")

    -- refuse after a clear does not regress the state
    local p4 = Guard.createPending("ZUG", 1, { instanceID = 309, startB = 3, endB = 8 })
    Guard.accept(p4, true, 309)
    test.eq(p4.state, Guard.STATE_CLEARED, "cleared state established")
    test.eq(Guard.refuse(p4), false, "refuse after clear still returns false")
    test.eq(p4.state, Guard.STATE_CLEARED, "refuse does not regress a cleared request")

    -- accept on a nil request is a no-op
    test.eq(Guard.accept(nil, true), "skip", "nil request never clears")
end
