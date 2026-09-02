BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}
M.tokens = {
    classic = { id = "classic" },
    preview = {
        id = "preview",
        colors = {
            window = "010F23", surface = "07182A", raised = "0C2033",
            gold = "F5B230", cyan = "00E6FF", text = "E8F1F8",
            secondaryText = "8EA6BA", border = "24445E",
        },
        localAlphaLift = 0.14,
    },
}

function M.normalize(value)
    return value == "preview" and "preview" or "classic"
end

function M.clampAlpha(value)
    value = tonumber(value)
    if value == nil then return 0.8 end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function pointSnapshot(frame)
    local points = {}
    local count = tonumber(frame:GetNumPoints()) or 0
    for index = 1, count do
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(index)
        points[index] = { point, relativeTo, relativePoint, x, y }
    end
    return points
end

function M.captureGeometry(frames)
    local snapshot = {}
    for key, frame in pairs(frames or {}) do
        if frame and frame.GetParent and frame.GetNumPoints and frame.GetPoint
            and frame.GetWidth and frame.GetHeight then
            snapshot[key] = {
                parent = frame:GetParent(), points = pointSnapshot(frame),
                width = frame:GetWidth(), height = frame:GetHeight(),
            }
        end
    end
    return snapshot
end

local function samePoints(left, right)
    if #left ~= #right then return false end
    for index = 1, #left do
        for field = 1, 5 do
            if left[index][field] ~= right[index][field] then return false end
        end
    end
    return true
end

function M.geometryMatches(snapshot, frames)
    for key, before in pairs(snapshot or {}) do
        local frame = frames and frames[key]
        if not frame then return false end
        local now = M.captureGeometry({ value = frame }).value
        if not now or before.parent ~= now.parent or before.width ~= now.width
            or before.height ~= now.height or not samePoints(before.points, now.points) then
            return false
        end
    end
    return true
end

BG.BGNext.UITheme = M
return M
