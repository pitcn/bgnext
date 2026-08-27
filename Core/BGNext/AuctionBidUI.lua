BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Minimal auction-bid UI extension: presentation and interaction decisions for
-- the controlled auto-bid region (每次加价 / 心理最高价 / 启用-停止按钮 / 状态文字).
--
-- This module is pure: it returns labels, layout numbers, lock state, and a
-- validated reading of the two inputs. The runtime owns the actual frames and
-- uses these values to build a compact region inside the existing bid frame.
local M = {}

M.LABELS = {
    increment = "每次加价",
    cap = "心理最高价",
    arm = "启用自动出价",
    stop = "停止自动出价",
}

M.ERRORS = {
    increment = "每次加价金额无效",
    cap = "心理最高价无效",
    ["cap-too-small"] = "心理最高价不能低于每次加价",
}

function M.errorText(code)
    return M.ERRORS[code] or ""
end

-- Centralised layout constants. Unconfirmed pixel values live here so no magic
-- numbers are scattered through the frame code.
M.layout = {
    regionWidth = 300,
    regionHeight = 42,
    labelWidth = 60,
    editWidth = 90,
    editHeight = 20,
    buttonWidth = 100,
    buttonHeight = 22,
    statusHeight = 14,
    gap = 4,
    margin = 4,
}

function M.isArmed(status)
    return status == "armed"
end

-- The two inputs are editable before arming, locked while armed, and editable
-- again after any stop.
function M.inputsLocked(status)
    return status == "armed"
end

function M.buttonText(status)
    if status == "armed" then
        return M.LABELS.stop
    end
    return M.LABELS.arm
end

-- Read and validate the two config inputs. Returns { increment, cap } on
-- success, or { error = "increment" | "cap" | "cap-too-small" } on failure.
-- Invalid amounts are blocked here, before anything is armed or sent.
function M.readConfig(incrementText, capText)
    local Store = BG.BGNext.AuctionPresetStore
    local increment = Store.validateIncrement(incrementText)
    if increment == nil then
        return { error = "increment" }
    end
    local cap = Store.validateMoney(capText)
    if cap == nil then
        return { error = "cap" }
    end
    if cap < increment then
        return { error = "cap-too-small" }
    end
    return { increment = increment, cap = cap }
end

BG.BGNext.AuctionBidUI = M

return M
