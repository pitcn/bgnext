BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Auction-bid UI extension: presentation and interaction decisions for the
-- controlled auto-bid region (每次加价 / 心理最高价 / 启用-停止按钮 / 状态文字).
--
-- This module is pure: it returns labels, layout numbers, lock state, a
-- validated reading of the two inputs, and explicit control rectangles. The
-- runtime owns the actual frames and applies these rectangles to real UI
-- objects. The region is a single two-row strip: row one holds the two labelled
-- inputs, row two holds the button and the status text.
local M = {}

M.LABELS = {
    increment = "每次加价",
    cap = "心理最高价",
    arm = "启用自动出价",
    stop = "停止自动出价",
    builtinBlocked = "内置自动出价已开启，请先关闭",
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
-- numbers are scattered through the frame code. The region is 300px wide and
-- 54px tall; the card height is extended by (regionHeight + gap) to keep the
-- region from covering the next card.
M.layout = {
    regionWidth = 300,
    regionHeight = 54,
    labelWidth = 64, -- must actually accommodate the widest label (心理最高价)
    editWidth = 64,
    editHeight = 20,
    buttonWidth = 92,
    buttonHeight = 22,
    statusHeight = 14,
    gap = 4,
    margin = 4,
}

-- Explicit control rectangles, origin at the region's top-left corner, y growing
-- downward. Each is { x, y, w, h }. The runtime applies these verbatim; the
-- boundary test checks that they neither overlap each other nor leave the region.
function M.rects()
    local L = M.layout
    local m, g = L.margin, L.gap
    local row1y = m
    local row2y = m + L.editHeight + g

    local incLabel = { x = m, y = row1y, w = L.labelWidth, h = L.editHeight }
    local incEdit = { x = incLabel.x + L.labelWidth + g, y = row1y, w = L.editWidth, h = L.editHeight }
    local capLabel = { x = incEdit.x + L.editWidth + g, y = row1y, w = L.labelWidth, h = L.editHeight }
    local capEdit = { x = capLabel.x + L.labelWidth + g, y = row1y, w = L.editWidth, h = L.editHeight }
    local button = { x = m, y = row2y, w = L.buttonWidth, h = L.buttonHeight }
    local status = { x = button.x + L.buttonWidth + g, y = row2y + (L.buttonHeight - L.statusHeight) / 2,
        w = L.regionWidth - (button.x + L.buttonWidth + g) - m, h = L.statusHeight }

    return {
        incrementLabel = incLabel,
        incrementEdit = incEdit,
        capLabel = capLabel,
        capEdit = capEdit,
        button = button,
        status = status,
    }
end

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

-- The built-in auto-bid (bidFrame.isAuto) and my feature are mutually exclusive:
-- while the built-in one is on, my arm button is disabled and explained.
function M.armBlocked(bidFrame)
    if bidFrame and bidFrame.isAuto then
        return M.LABELS.builtinBlocked
    end
    return nil
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
