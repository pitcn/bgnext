-- BGNext main-frame scale computation (pure Lua; no frames, SavedVariables or
-- game API). The user's preferred scale (BiaoGe.options.scale) is the ceiling:
-- the frame is never enlarged beyond it. The actual scale is that preferred
-- scale constrained so the whole table stays on screen with a safe margin:
--
--     actualScale = min(preferredScale, widthLimit, heightLimit)
--     widthLimit  = (screenWidth  - marginX) / tableWidth
--     heightLimit = (screenHeight - marginY) / tableHeight
--
-- tableWidth/tableHeight are the unscaled table dimensions (BG.FBWidth /
-- BG.FBHeight), screenWidth/screenHeight the logical screen size
-- (UIParent:GetWidth() / UIParent:GetHeight()). A missing, zero, negative or
-- non-number dimension simply skips that axis's limit, so a caller with partial
-- data degrades gracefully. The constrained result is never written back to the
-- preferred value: it is recomputed on demand, so the user's preferred scale
-- survives a switch from a wide to a narrow table.

BG = BG or {}
BG.BGNext = BG.BGNext or {}
local M = {}

-- Total reserved logical pixels along each axis (both sides combined), so the
-- centered frame keeps its title bar and bottom-right resize handle clear of
-- the screen edge. Tunable; validate against the in-game layouts.
M.MARGIN_X = 40
M.MARGIN_Y = 60

local function finite(n)
    return type(n) == "number" and n > -math.huge and n < math.huge
end

local function positive(n)
    return finite(n) and n > 0
end

function M.compute(preferredScale, tableWidth, tableHeight, screenWidth, screenHeight, marginX, marginY)
    if not positive(preferredScale) then return nil end
    if marginX == nil then marginX = M.MARGIN_X end
    if marginY == nil then marginY = M.MARGIN_Y end

    local actual = preferredScale
    if positive(tableWidth) and positive(screenWidth) then
        local usable = screenWidth - marginX
        if usable > 0 then
            actual = math.min(actual, usable / tableWidth)
        end
    end
    if positive(tableHeight) and positive(screenHeight) then
        local usable = screenHeight - marginY
        if usable > 0 then
            actual = math.min(actual, usable / tableHeight)
        end
    end
    return actual
end

function M.isOutsideScreen(left, bottom, right, top, screenWidth, screenHeight)
    if not finite(left) or not finite(bottom) or not finite(right) or not finite(top)
        or not positive(screenWidth) or not positive(screenHeight) then
        return false
    end
    return left < 0 or bottom < 0 or right > screenWidth or top > screenHeight
end

BG.BGNext.MainFrameScale = M
return M
