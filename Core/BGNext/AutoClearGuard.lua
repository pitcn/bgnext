BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Pure decision layer for the "auto clear table on a new lockout" confirmation
-- gate. The actual deletion is performed only by the existing BG.ClearBiaoGe
-- path after an explicit user confirmation; this module owns only the decision
-- of whether to ask and whether an accepted request still clears. Nothing here
-- persists, sends or clears anything.

local M = {}

local STATE_PENDING = "pending"
local STATE_CLEARED = "cleared"
local STATE_SKIPPED = "skipped"
local STATE_CANCELLED = "cancelled"

-- Whether a new-lockout auto-clear must ask the user before clearing. True only
-- when auto-clear is enabled, this is a new lockout, and the target table still
-- holds old content. An empty table is never disturbed, and a disabled setting
-- never asks.
function M.needsConfirmation(autoQingKongEnabled, newCD, hasOldContent)
    return autoQingKongEnabled == true and newCD == true and hasOldContent == true
end

-- A pending auto-clear request captures the target table id and the reason that
-- made it eligible, but performs no mutation until accept() confirms it.
-- Returns nil when the table id is missing or empty.
function M.createPending(fb, clearType, scope)
    if type(fb) ~= "string" or fb == "" then
        return nil
    end
    local pending = { fb = fb, clearType = clearType, state = STATE_PENDING }
    if clearType == 1 then
        if type(scope) ~= "table"
            or type(scope.instanceID) ~= "number"
            or type(scope.startB) ~= "number"
            or type(scope.endB) ~= "number"
            or scope.startB < 1
            or scope.endB < scope.startB
        then
            return nil
        end
        pending.instanceID = scope.instanceID
        pending.startB = scope.startB
        pending.endB = scope.endB
    end
    return pending
end

-- On accept, the captured table is re-checked for old content before clearing,
-- so a table that was emptied or cleared meanwhile (a duplicate event, a manual
-- clear) is not cleared a second time. Returns "clear" or "skip" and advances
-- the pending state; a request that is no longer pending is never cleared.
function M.accept(pending, hasOldContentNow, currentInstanceID)
    if not pending or pending.state ~= STATE_PENDING then
        return "skip"
    end
    if pending.clearType == 1 and currentInstanceID ~= pending.instanceID then
        pending.state = STATE_SKIPPED
        return "skip"
    end
    if hasOldContentNow == true then
        pending.state = STATE_CLEARED
        return "clear"
    end
    pending.state = STATE_SKIPPED
    return "skip"
end

-- Refuse / Esc / cancel: abandon the request without clearing. Returns false so
-- the "do not clear" result is explicit at call sites.
function M.refuse(pending)
    if pending and pending.state == STATE_PENDING then
        pending.state = STATE_CANCELLED
    end
    return false
end

M.STATE_PENDING = STATE_PENDING
M.STATE_CLEARED = STATE_CLEARED
M.STATE_SKIPPED = STATE_SKIPPED
M.STATE_CANCELLED = STATE_CANCELLED

-- Publish into the runtime namespace exactly like every other BGNext module:
-- a WoW TOC load discards the return value, so the guard must be reachable at
-- BG.BGNext.AutoClearGuard. The value is still returned for the test harness.
BG.BGNext.AutoClearGuard = M
return M
