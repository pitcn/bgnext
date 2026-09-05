BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Transient, single-flight state for the batch-mail flow. This Module owns
-- no SavedVariables: it only freezes recipients and copper amounts between
-- one SendMail call and its ERR_MAIL_SENT result.
local M = {}

function M.new()
    local pending
    local tracker = {}

    function tracker:begin(values)
        values = type(values) == "table" and values or {}
        if pending then return nil end
        local snapshot = {
            fullName = values.fullName,
            name = values.name,
            colorName = values.colorName,
            money = tonumber(values.money),
        }
        pending = snapshot
        return snapshot
    end

    function tracker:consume(message, successMessage)
        if message ~= successMessage or not pending then return nil end
        local snapshot = pending
        pending = nil
        return snapshot
    end

    function tracker:isPending()
        return pending ~= nil
    end

    function tracker:clear()
        pending = nil
    end

    return tracker
end

BG.BGNext.MailSendAttempt = M
return M
