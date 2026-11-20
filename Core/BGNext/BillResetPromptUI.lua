BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Addon-owned prompt frame for the Forever "clear the previous bill?" question.
-- Created lazily on first display; never touches StaticPopup, Blizzard globals,
-- secure functions or keyboard handling. Closing it without choosing (Esc via
-- UISpecialFrames, hide) is the same as "keep". A /reload or logout while it is
-- shown records no answer, so the question may be asked again afterwards.

local _, ns = ...
local L = type(ns) == "table" and ns.L or setmetatable({}, { __index = function(_, key) return tostring(key) end })

local M = {}
local frame
local current

local function decide(choice)
    local request = current
    if not request or request.decided then return end
    request.decided = true
    current = nil
    if frame then frame:Hide() end
    local callback = choice == "clear" and request.onClear or request.onKeep
    if type(callback) == "function" then callback() end
end

local function ensureFrame()
    if frame then return frame end
    frame = CreateFrame("Frame", "BGNextBillResetPromptFrame", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("HIGH")
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
    frame:SetSize(420, 150)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:SetBackdropBorderColor(1, 1, 1, 0.5)
    frame:EnableMouse(true)

    frame.title = frame:CreateFontString(nil, "OVERLAY")
    frame.title:SetFont(BIAOGE_TEXT_FONT, 16, "OUTLINE")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -12)
    frame.title:SetTextColor(1, 0.82, 0)

    frame.message = frame:CreateFontString(nil, "OVERLAY")
    frame.message:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
    frame.message:SetPoint("TOP", frame, "TOP", 0, -40)
    frame.message:SetJustifyH("LEFT")
    frame.message:SetWordWrap(true)

    frame.clearButton = BG.CreateButton(frame)
    frame.clearButton:SetScript("OnClick", function() decide("clear") end)
    frame.keepButton = BG.CreateButton(frame)
    frame.keepButton:SetScript("OnClick", function() decide("keep") end)

    frame:SetScript("OnHide", function() decide("keep") end)
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BGNextBillResetPromptFrame")
    end
    frame:Hide()
    return frame
end

local function messageKey(opts)
    if opts.newTeam and opts.reset then
        return "检测到你进入了新团队，且副本进度已重置。表格< %s >仍有上次的账单内容，要清空上次账单吗？"
    elseif opts.reset then
        return "检测到副本进度已重置。表格< %s >仍有上次的账单内容，要清空上次账单吗？"
    end
    return "检测到你进入了新团队。表格< %s >仍有上次的账单内容，要清空上次账单吗？"
end

-- opts: fbName, newTeam, reset, onClear, onKeep. Returns true when shown.
function M.show(opts)
    if type(opts) ~= "table" or current then return false end
    local f = ensureFrame()
    current = { onClear = opts.onClear, onKeep = opts.onKeep }

    f.title:SetText(L["清空上次账单？"])
    f.message:SetWidth(380)
    f.message:SetText(string.format(L[messageKey(opts)], tostring(opts.fbName or "")))
    f.clearButton:SetText(L["清空上次账单"])
    f.keepButton:SetText(L["保留"])
    local clearWidth = math.max(110, f.clearButton:GetFontString():GetStringWidth() + 30)
    local keepWidth = math.max(90, f.keepButton:GetFontString():GetStringWidth() + 30)
    f.clearButton:SetSize(clearWidth, 25)
    f.keepButton:SetSize(keepWidth, 25)
    local total = clearWidth + keepWidth + 10
    local width = math.max(420, total + 40)
    f.message:SetWidth(width - 40)
    f:SetSize(width, 40 + f.message:GetStringHeight() + 25 + 25 + 12)
    f.clearButton:ClearAllPoints()
    f.clearButton:SetPoint("BOTTOMLEFT", f, "BOTTOM", -total / 2, 12)
    f.keepButton:ClearAllPoints()
    f.keepButton:SetPoint("LEFT", f.clearButton, "RIGHT", 10, 0)
    f:Show()
    return true
end

function M.isShown()
    return current ~= nil
end

-- Programmatic close counts as "keep".
function M.hide()
    decide("keep")
end

BG.BGNext.BillResetPromptUI = M
return M
