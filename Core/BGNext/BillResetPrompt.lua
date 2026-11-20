BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Pure decision layer for the Forever-only "ask before clearing the previous
-- bill" prompt. It decides whether to ask, de-duplicates the question and keeps
-- a combat-deferral state machine. It performs no clearing, no Blizzard API
-- call and no UI work. The only persisted record is a single scalar marker,
-- BiaoGe.BGNext.billResetPrompt = { fb, billStamp, newTeamAsked,
-- resetAskedKey, at }: no names, GUIDs, hashes or roster content.

local M = {}
local MAX_AGE = 7 * 86400

local function validStamp(value)
    return type(value) == "number" and value == value
end

local function parseKey(key)
    if type(key) ~= "string" then return nil end
    local instanceID, stamp, lock = key:match("^(%d+)@(%-?%d+)@(%w+)$")
    if not instanceID then return nil end
    return tonumber(instanceID), tonumber(stamp), tonumber(lock) -- lock is nil for "none"
end

function M.resetKey(instanceID, billStamp, lockoutId)
    return tostring(instanceID) .. "@" .. tostring(billStamp) .. "@" .. (lockoutId and tostring(lockoutId) or "none")
end

local function validMarker(marker, fb)
    return type(marker) == "table" and marker.fb == fb
end

-- Returns request (or nil) and, optionally, a lock key to record silently.
-- ctx: forever, enabled, fb, hasContent, billStamp, newTeam (bool),
--      reset = { instanceID, locked, lockoutId }.
function M.shouldAsk(ctx, marker)
    if type(ctx) ~= "table" or ctx.forever ~= true or ctx.enabled ~= true
        or type(ctx.fb) ~= "string" or ctx.fb == "" or ctx.hasContent ~= true then
        return nil
    end
    local stamp = validStamp(ctx.billStamp) and ctx.billStamp or 0
    local sameFb = validMarker(marker, ctx.fb)
    local sameBill = sameFb and marker.billStamp == stamp

    local newTeam = ctx.newTeam == true and not (sameBill and marker.newTeamAsked == true)

    local reset, resetKey, observe = false, nil, nil
    local info = ctx.reset
    if type(info) == "table" and type(info.instanceID) == "number" then
        -- The reset key names its own instance and bill stamp, so it is read
        -- regardless of which table the new-team fields belong to.
        local askedKey = type(marker) == "table" and type(marker.resetAskedKey) == "string"
            and marker.resetAskedKey or nil
        if info.locked then
            -- Locked on entry: only a different, known lockout id proves a reset.
            -- Without a numeric id, or without a prior numeric baseline, fail
            -- closed and just remember the lockout.
            if type(info.lockoutId) == "number" then
                resetKey = M.resetKey(info.instanceID, stamp, info.lockoutId)
                local prevInstance, _, prevLock = parseKey(askedKey)
                if prevInstance == info.instanceID and prevLock and prevLock ~= info.lockoutId then
                    reset = true
                elseif askedKey ~= resetKey then
                    observe = resetKey
                end
            end
        else
            resetKey = M.resetKey(info.instanceID, stamp, nil)
            reset = askedKey ~= resetKey
        end
    end

    if not newTeam and not reset then
        return nil, observe
    end
    return {
        fb = ctx.fb,
        billStamp = stamp,
        newTeam = newTeam,
        reset = reset,
        resetKey = reset and resetKey or nil,
    }
end

local function writeMarker(root, fb, stamp, newTeamAsked, resetAskedKey, now)
    root.billResetPrompt = {
        fb = fb,
        billStamp = stamp,
        newTeamAsked = newTeamAsked or nil,
        resetAskedKey = resetAskedKey,
        at = now,
    }
end

-- The marker's fb/billStamp/newTeamAsked describe the new-team answer of one
-- table. An update that carries no new-team answer (a reset-only answer or a
-- silent lockout baseline, possibly for another table) keeps that answer
-- instead of overwriting it, otherwise the same party would be asked again.
local function keptTeamAnswer(old)
    if type(old) == "table" and type(old.fb) == "string" and old.fb ~= ""
        and old.newTeamAsked == true and validStamp(old.billStamp) then
        return old.fb, old.billStamp
    end
end

local function oldResetKey(old)
    return type(old) == "table" and type(old.resetAskedKey) == "string" and old.resetAskedKey or nil
end

-- Record that the user answered (clear or keep). Whitelisted fields only.
function M.markAsked(root, req, now)
    if type(root) ~= "table" or type(req) ~= "table" or type(req.fb) ~= "string" then return end
    local old = root.billResetPrompt
    local stamp = validStamp(req.billStamp) and req.billStamp or 0
    local resetKey = oldResetKey(old)
    if req.reset == true and type(req.resetKey) == "string" then resetKey = req.resetKey end
    if req.newTeam ~= true then
        local keptFb, keptStamp = keptTeamAnswer(old)
        if keptFb then
            writeMarker(root, keptFb, keptStamp, true, resetKey, now)
            return
        end
    end
    writeMarker(root, req.fb, stamp, req.newTeam == true, resetKey, now)
end

-- Silent lockout baseline: remembers the current lockout id without asking.
function M.observe(root, ctx, key, now)
    if type(root) ~= "table" or type(ctx) ~= "table" or type(ctx.fb) ~= "string"
        or type(key) ~= "string" or not parseKey(key) then
        return
    end
    local keptFb, keptStamp = keptTeamAnswer(root.billResetPrompt)
    if keptFb then
        writeMarker(root, keptFb, keptStamp, true, key, now)
        return
    end
    local stamp = validStamp(ctx.billStamp) and ctx.billStamp or 0
    writeMarker(root, ctx.fb, stamp, false, key, now)
end

function M.onGroupLeft(root)
    local marker = type(root) == "table" and root.billResetPrompt
    if type(marker) == "table" then marker.newTeamAsked = nil end
end

function M.onTableCleared(root, fb)
    if type(root) == "table" and type(root.billResetPrompt) == "table" and root.billResetPrompt.fb == fb then
        root.billResetPrompt = nil
    end
end

function M.prune(root, now)
    local marker = type(root) == "table" and root.billResetPrompt
    if marker == nil then return end
    if type(marker) ~= "table" or type(marker.fb) ~= "string" or type(marker.at) ~= "number"
        or now - marker.at >= MAX_AGE then
        root.billResetPrompt = nil
    end
end

-- Memory-only runtime state: one visible request plus one trigger deferred by
-- combat. A deferred trigger is a spec, never a request: it is re-evaluated
-- from scratch after combat.
function M.newState()
    return { shown = false, deferred = nil }
end

function M.begin(state, req)
    if state.shown or type(req) ~= "table" then return false end
    state.shown = true
    return true
end

function M.finish(state)
    state.shown = false
end

function M.defer(state, spec)
    state.deferred = spec
end

function M.takeDeferred(state)
    local spec = state.deferred
    state.deferred = nil
    return spec
end

function M.clearDeferred(state)
    state.deferred = nil
end

M.MAX_AGE = MAX_AGE

BG.BGNext.BillResetPrompt = M
return M
