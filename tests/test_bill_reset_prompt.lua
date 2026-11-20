-- Pure decision layer for the Forever "ask before clearing the previous bill"
-- prompt. No Blizzard API is touched here.

return function(test)
    local oldBG = BG
    BG = { BGNext = {} }
    local P = dofile("Core/BGNext/BillResetPrompt.lua")
    test.eq(BG.BGNext.BillResetPrompt, P, "module publishes itself in the runtime namespace")

    local function ctx(overrides)
        local c = { forever = true, enabled = true, fb = "HSforever", hasContent = true, billStamp = 1000 }
        for k, v in pairs(overrides or {}) do c[k] = v end
        return c
    end

    -- 1/2/3: hard gates.
    test.eq(P.shouldAsk(ctx({ forever = false, newTeam = true }), nil), nil, "non-Forever never asks")
    local unknown = ctx({ newTeam = true })
    unknown.forever = nil
    test.eq(P.shouldAsk(unknown, nil), nil, "unknown client never asks")
    test.eq(P.shouldAsk(ctx({ enabled = false, newTeam = true }), nil), nil, "disabled never asks")
    test.eq(P.shouldAsk(ctx({ hasContent = false, newTeam = true }), nil), nil, "empty table never asks")
    local noTable = ctx({ newTeam = true })
    noTable.fb = nil
    test.eq(P.shouldAsk(noTable, nil), nil, "missing table never asks")
    test.eq(P.shouldAsk(ctx({}), nil), nil, "no trigger never asks")

    -- 4: new team asks once per party.
    local root = {}
    local req = P.shouldAsk(ctx({ newTeam = true }), root.billResetPrompt)
    test.eq(req ~= nil, true, "new team asks")
    test.eq(req.newTeam, true, "reason newTeam")
    test.eq(req.reset, false, "no reset reason")
    test.eq(req.fb, "HSforever", "request names the table")
    P.markAsked(root, req, 5000)
    test.eq(root.billResetPrompt.newTeamAsked, true, "asked flag stored")
    test.eq(P.shouldAsk(ctx({ newTeam = true }), root.billResetPrompt), nil, "same stamp does not ask twice")
    P.onGroupLeft(root)
    test.eq(P.shouldAsk(ctx({ newTeam = true }), root.billResetPrompt) ~= nil, true, "asks again after leaving the group")
    -- A new bill stamp is a different bill: asks again.
    P.markAsked(root, P.shouldAsk(ctx({ newTeam = true }), root.billResetPrompt), 5000)
    test.eq(P.shouldAsk(ctx({ newTeam = true, billStamp = 2000 }), root.billResetPrompt) ~= nil, true,
        "changed bill stamp invalidates the asked flag")

    -- 5: reset without a lock asks once per instance+stamp.
    root = {}
    local reset = { instanceID = 1001, locked = false }
    req = P.shouldAsk(ctx({ reset = reset }), nil)
    test.eq(req ~= nil and req.reset, true, "unlocked entry is a reset")
    test.eq(req.newTeam, false, "no new-team reason")
    P.markAsked(root, req, 5000)
    test.eq(P.shouldAsk(ctx({ reset = reset }), root.billResetPrompt), nil, "same resetAskedKey does not ask twice")
    test.eq(P.shouldAsk(ctx({ reset = reset, billStamp = 1001 }), root.billResetPrompt) ~= nil, true,
        "changed bill stamp asks again")
    test.eq(P.shouldAsk(ctx({ reset = { instanceID = 1002, locked = false } }), root.billResetPrompt) ~= nil, true,
        "another instance asks again")
    -- A lockout appearing after an unlocked answer is not itself a reset.
    local r2, observe = P.shouldAsk(ctx({ reset = { instanceID = 1001, locked = true, lockoutId = 77 } }),
        root.billResetPrompt)
    test.eq(r2, nil, "a fresh lock after an unlocked answer does not ask")
    test.eq(type(observe), "string", "the lock is observed as a silent baseline")
    P.observe(root, ctx({ fb = "HSforever" }), observe, 5000)
    test.eq(root.billResetPrompt.resetAskedKey, observe, "baseline stored")
    test.eq(P.shouldAsk(ctx({ reset = { instanceID = 1001, locked = true, lockoutId = 77 } }), root.billResetPrompt),
        nil, "same lockout id does not ask")
    local r3 = P.shouldAsk(ctx({ reset = { instanceID = 1001, locked = true, lockoutId = 78 } }), root.billResetPrompt)
    test.eq(r3 ~= nil and r3.reset, true, "changed lockout id is a reset")
    test.eq(P.shouldAsk(ctx({ reset = { instanceID = 1001, locked = true, lockoutId = nil } }), root.billResetPrompt),
        nil, "locked without an id fails closed")
    test.eq(P.shouldAsk(ctx({ reset = { instanceID = 1001, locked = true, lockoutId = "x" } }), root.billResetPrompt),
        nil, "locked with a non-numeric id fails closed")

    -- 6: both reasons combine into one request.
    root = {}
    req = P.shouldAsk(ctx({ newTeam = true, reset = { instanceID = 1001, locked = false } }), nil)
    test.eq(req.newTeam and req.reset, true, "both reasons present in one request")
    P.markAsked(root, req, 5000)
    test.eq(root.billResetPrompt.newTeamAsked, true, "new team recorded")
    test.eq(type(root.billResetPrompt.resetAskedKey), "string", "reset recorded")

    -- Review fix: the single marker serves two tables. A reset answer (or a
    -- silent lockout baseline) for another table must not erase the new-team
    -- answer recorded for the last bill, or the same party is asked again.
    root = {}
    P.markAsked(root, P.shouldAsk(ctx({ fb = "X", newTeam = true }), nil), 5000)
    local yReset = { instanceID = 2002, locked = false }
    local yReq = P.shouldAsk(ctx({ fb = "Y", billStamp = 300, reset = yReset }), root.billResetPrompt)
    test.eq(yReq ~= nil and yReq.reset, true, "a reset on another table still asks")
    P.markAsked(root, yReq, 5100)
    test.eq(P.shouldAsk(ctx({ fb = "X", newTeam = true }), root.billResetPrompt), nil,
        "a reset answer on another table keeps the new-team answer")
    test.eq(P.shouldAsk(ctx({ fb = "Y", billStamp = 300, reset = yReset }), root.billResetPrompt), nil,
        "the reset answer on the other table is kept too")
    local zCtx = ctx({ fb = "Z", billStamp = 400, reset = { instanceID = 3003, locked = true, lockoutId = 5 } })
    local zReq, zObserve = P.shouldAsk(zCtx, root.billResetPrompt)
    test.eq(zReq == nil and type(zObserve) == "string", true, "first lock on a third table is a silent baseline")
    P.observe(root, zCtx, zObserve, 5200)
    test.eq(P.shouldAsk(ctx({ fb = "X", newTeam = true }), root.billResetPrompt), nil,
        "a lockout baseline on another table keeps the new-team answer")
    test.eq(P.shouldAsk(ctx({ fb = "X", newTeam = true, billStamp = 1001 }), root.billResetPrompt) ~= nil, true,
        "a changed stamp of the last bill still re-asks")
    P.onGroupLeft(root)
    test.eq(P.shouldAsk(ctx({ fb = "X", newTeam = true }), root.billResetPrompt) ~= nil, true,
        "leaving the group still re-asks")

    -- 7: combat stash state machine.
    local state = P.newState()
    test.eq(P.begin(state, req), true, "first request may show")
    test.eq(P.begin(state, req), false, "only one request at a time")
    P.finish(state)
    test.eq(P.begin(state, req), true, "a finished request frees the slot")
    P.finish(state)
    test.eq(P.takeDeferred(state), nil, "nothing deferred initially")
    P.defer(state, { kind = "team" })
    P.defer(state, { kind = "reset", instanceID = 5 })
    local spec = P.takeDeferred(state)
    test.eq(spec.kind, "reset", "only the newest deferred trigger is kept")
    test.eq(P.takeDeferred(state), nil, "deferred trigger is consumed once")
    P.defer(state, { kind = "team" })
    P.clearDeferred(state)
    test.eq(P.takeDeferred(state), nil, "clearDeferred drops it")

    -- 8: lifecycle and privacy.
    root = {}
    P.markAsked(root, P.shouldAsk(ctx({ newTeam = true }), nil), 5000)
    P.onTableCleared(root, "OtherFB")
    test.eq(root.billResetPrompt ~= nil, true, "clearing another table keeps the marker")
    P.onTableCleared(root, "HSforever")
    test.eq(root.billResetPrompt, nil, "clearing the table deletes the marker")

    root = { billResetPrompt = { fb = "HSforever", billStamp = 1, newTeamAsked = true, at = 1000 } }
    P.prune(root, 1000 + 7 * 86400 - 1)
    test.eq(root.billResetPrompt ~= nil, true, "marker survives inside seven days")
    P.prune(root, 1000 + 7 * 86400)
    test.eq(root.billResetPrompt, nil, "marker expires after seven days")
    root = { billResetPrompt = { fb = 5, at = "x" } }
    P.prune(root, 10)
    test.eq(root.billResetPrompt, nil, "malformed marker is discarded")

    root = {}
    P.markAsked(root, P.shouldAsk(ctx({ newTeam = true, reset = { instanceID = 9, locked = false } }), nil), 5000)
    local allowed = { fb = true, billStamp = true, newTeamAsked = true, resetAskedKey = true, at = true }
    for key, value in pairs(root.billResetPrompt) do
        test.eq(allowed[key], true, "stored key is whitelisted: " .. tostring(key))
        test.eq(type(value) == "table", false, "stored values are scalar: " .. tostring(key))
    end
    P.markAsked(root, { fb = "HSforever", billStamp = 1000, newTeam = true, reset = false,
        name = "Player Name", guid = "Player-1-ABC", roster = { "a" } }, 5000)
    for key in pairs(root.billResetPrompt) do
        test.eq(allowed[key], true, "foreign request fields are never stored: " .. tostring(key))
    end

    -- DataLifecycle.ensureRoot validates the persisted marker.
    local oldGetServerTime = GetServerTime
    GetServerTime = function() return 100000 end
    local DL = dofile("Core/BGNext/DataLifecycle.lua")
    local function marker(extra)
        local m = { fb = "HSforever", billStamp = 5, newTeamAsked = true, resetAskedKey = "1@5@none", at = 99000 }
        for k, v in pairs(extra or {}) do m[k] = v end
        return m
    end
    local saved = { BGNext = { billResetPrompt = marker({ name = "Player Name", guid = "Player-1-A", roster = { "x" } }) } }
    local r = DL.ensureRoot(saved)
    test.eq(r.billResetPrompt.fb, "HSforever", "valid marker is kept")
    test.eq(r.billResetPrompt.name, nil, "foreign name field is stripped")
    test.eq(r.billResetPrompt.guid, nil, "foreign guid field is stripped")
    test.eq(r.billResetPrompt.roster, nil, "foreign roster field is stripped")
    test.eq(DL.ensureRoot({ BGNext = { billResetPrompt = marker({ at = 100000 - 7 * 86400 }) } }).billResetPrompt, nil,
        "seven-day-old marker is pruned")
    test.eq(DL.ensureRoot({ BGNext = { billResetPrompt = marker({ fb = 3 }) } }).billResetPrompt, nil,
        "marker with a bad table id is dropped")
    test.eq(DL.ensureRoot({ BGNext = { billResetPrompt = "junk" } }).billResetPrompt, nil, "non-table marker is dropped")
    test.eq(DL.ensureRoot({ BGNext = { billResetPrompt = marker({ resetAskedKey = { 1 } }) } }).billResetPrompt.resetAskedKey,
        nil, "non-string reset key is dropped")
    test.eq(DL.ensureRoot({ BGNext = {} }).billResetPrompt, nil, "absent marker stays absent")
    GetServerTime = oldGetServerTime

    BG = oldBG
end
