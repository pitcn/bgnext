BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}

local UNIT_SECONDS = {
    ["天"] = 86400,
    ["小时"] = 3600,
    ["小時"] = 3600,
    ["分钟"] = 60,
    ["分鐘"] = 60,
    ["秒"] = 1,
    day = 86400,
    days = 86400,
    hour = 3600,
    hours = 3600,
    hr = 3600,
    hrs = 3600,
    minute = 60,
    minutes = 60,
    min = 60,
    mins = 60,
    second = 1,
    seconds = 1,
    sec = 1,
    secs = 1,
}

function M.parseRemainingSeconds(text)
    if type(text) ~= "string" or text == "" then return nil end
    local total, matched = 0, false
    local normalized = text:lower()
    for amount, unit in normalized:gmatch("(%d+)%s*([a-z]+)") do
        local multiplier = UNIT_SECONDS[unit]
        if multiplier then
            total = total + tonumber(amount) * multiplier
            matched = true
        end
    end
    for _, entry in ipairs({
        { "小时", 3600 }, { "小時", 3600 },
        { "分钟", 60 }, { "分鐘", 60 },
        { "天", 86400 }, { "秒", 1 },
    }) do
        for amount in normalized:gmatch("(%d+)%s*" .. entry[1]) do
            total = total + tonumber(amount) * entry[2]
            matched = true
        end
    end
    return matched and total or nil
end

function M.shouldScan(enabled, isLootLeader)
    return enabled == true and isLootLeader == true
end

function M.extractRemainingSeconds(lines, template)
    if type(lines) ~= "table" or type(template) ~= "string" then return nil end
    local marker = template:find("%s", 1, true)
    if not marker then return nil end
    local prefix = template:sub(1, marker - 1)
    local suffix = template:sub(marker + 2)
    for _, line in ipairs(lines) do
        if type(line) == "string" then
            local startAt = line:find(prefix, 1, true)
            if startAt then
                local valueStart = startAt + #prefix
                local valueEnd = #line
                if suffix ~= "" then
                    local suffixAt = line:find(suffix, valueStart, true)
                    if not suffixAt then
                        valueEnd = nil
                    else
                        valueEnd = suffixAt - 1
                    end
                end
                if valueEnd then
                    local seconds = M.parseRemainingSeconds(line:sub(valueStart, valueEnd))
                    if seconds then return seconds end
                end
            end
        end
    end
    return nil
end

local Controller = {}
Controller.__index = Controller

local function safeCall(fn, fallback)
    if type(fn) ~= "function" then return fallback end
    local ok, value = pcall(fn)
    if ok then return value end
    return fallback
end

function Controller:cancelTimer()
    if self.timer then
        if type(self.deps.cancel) == "function" then
            self.deps.cancel(self.timer)
        elseif type(self.timer.Cancel) == "function" then
            self.timer:Cancel()
        end
        self.timer = nil
    end
end

function Controller:stop()
    self:cancelTimer()
    self.entries = {}
    if type(self.deps.updateView) == "function" then
        self.deps.updateView(self.entries)
    end
end

function Controller:refresh()
    self:cancelTimer()
    local enabled = safeCall(self.deps.enabled, false) == true
    local leader = safeCall(self.deps.isLootLeader, false) == true
    if not M.shouldScan(enabled, leader) then
        self.entries = {}
        if type(self.deps.updateView) == "function" then
            self.deps.updateView(self.entries)
        end
        return self.entries
    end

    local entries = safeCall(self.deps.scan, {})
    if type(entries) ~= "table" then entries = {} end
    local sanitized = {}
    local present = {}
    for _, entry in ipairs(entries) do
        if type(entry) == "table" and type(entry.key) == "string"
            and type(entry.remainingSeconds) == "number" and entry.remainingSeconds > 0
        then
            sanitized[#sanitized + 1] = entry
            present[entry.key] = true
        end
    end
    for key in pairs(self.notified) do
        if not present[key] then self.notified[key] = nil end
    end
    table.sort(sanitized, function(a, b)
        if a.remainingSeconds ~= b.remainingSeconds then
            return a.remainingSeconds < b.remainingSeconds
        end
        return a.key < b.key
    end)
    self.entries = sanitized
    if type(self.deps.updateView) == "function" then
        self.deps.updateView(self.entries)
    end

    local threshold = tonumber(safeCall(self.deps.thresholdSeconds, 1800)) or 1800
    local now = tonumber(safeCall(self.deps.now, 0)) or 0
    local mutedUntil = tonumber(safeCall(self.deps.mutedUntil, 0)) or 0
    local minInterval = tonumber(safeCall(self.deps.minNotifyInterval, 300)) or 300
    local intervalReadyAt = (self.lastNotifyAt or -math.huge) + math.max(0, minInterval)
    local notifyReadyAt = math.max(mutedUntil, intervalReadyAt)
    local canNotify = now >= notifyReadyAt
    local due = {}
    local nextDelay
    for _, entry in ipairs(self.entries) do
        if canNotify and entry.remainingSeconds <= threshold and not self.notified[entry.key] then
            due[#due + 1] = entry
            self.notified[entry.key] = true
        end
        local delay
        if entry.remainingSeconds > threshold then
            delay = entry.remainingSeconds - threshold + 1
        else
            delay = entry.remainingSeconds + 1
        end
        if delay > 0 and (not nextDelay or delay < nextDelay) then nextDelay = delay end
    end
    if not canNotify and #self.entries > 0 then
        local waitForNotice = notifyReadyAt - now
        if waitForNotice > 0 and (not nextDelay or waitForNotice < nextDelay) then
            nextDelay = waitForNotice
        end
    end
    if #due > 0 and type(self.deps.notify) == "function" then
        self.deps.notify(due)
        self.lastNotifyAt = now
    end
    if nextDelay and type(self.deps.schedule) == "function" then
        self.timer = self.deps.schedule(math.max(1, nextDelay), function()
            self.timer = nil
            self:refresh()
        end)
    end
    return self.entries
end

function M.newController(deps)
    return setmetatable({ deps = deps or {}, entries = {}, notified = {} }, Controller)
end

local function stripColors(text)
    if type(text) ~= "string" then return nil end
    return text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
end

local function defaultTooltipLines(bag, slot)
    if C_TooltipInfo and type(C_TooltipInfo.GetBagItem) == "function" then
        local data = C_TooltipInfo.GetBagItem(bag, slot)
        local lines = {}
        for _, line in ipairs(data and data.lines or {}) do
            if line.leftText then lines[#lines + 1] = stripColors(line.leftText) end
            if line.rightText then lines[#lines + 1] = stripColors(line.rightText) end
        end
        return lines
    end
    if not BiaoGeTooltip3 or type(BiaoGeTooltip3.SetBagItem) ~= "function" then return {} end
    BiaoGeTooltip3:SetOwner(UIParent, "ANCHOR_NONE")
    BiaoGeTooltip3:ClearLines()
    BiaoGeTooltip3:SetBagItem(bag, slot)
    local lines = {}
    for i = 1, BiaoGeTooltip3:NumLines() do
        for _, side in ipairs({ "Left", "Right" }) do
            local region = _G["BiaoGeTooltip3Text" .. side .. i]
            local text = region and region:GetText()
            if text then lines[#lines + 1] = stripColors(text) end
        end
    end
    BiaoGeTooltip3:Hide()
    return lines
end

function M.scanBags(api)
    api = api or {}
    local numSlots = api.numSlots
        or (C_Container and C_Container.GetContainerNumSlots)
        or GetContainerNumSlots
    local itemLink = api.itemLink
        or (C_Container and C_Container.GetContainerItemLink)
        or GetContainerItemLink
    local tooltipLines = api.tooltipLines or defaultTooltipLines
    if type(numSlots) ~= "function" or type(itemLink) ~= "function" then return {} end

    local template = api.tradeTemplate or BIND_TRADE_TIME_REMAINING
    if type(template) ~= "string" or not template:find("%s", 1, true) then return {} end
    local maxBag = tonumber(api.maxBag)
        or tonumber(NUM_BAG_SLOTS)
        or tonumber(NUM_TOTAL_EQUIPPED_BAG_SLOTS)
        or 4
    local entries = {}
    for bag = 0, maxBag do
        local okSlots, slots = pcall(numSlots, bag)
        slots = okSlots and tonumber(slots) or 0
        for slot = 1, slots do
            local okLink, link = pcall(itemLink, bag, slot)
            if okLink and link then
                local okLines, lines = pcall(tooltipLines, bag, slot)
                local seconds = okLines and M.extractRemainingSeconds(lines, template) or nil
                if seconds and seconds > 0 then
                    local itemID = tonumber(link:match("item:(%d+)"))
                    entries[#entries + 1] = {
                        key = table.concat({ bag, slot, link }, ":"),
                        bag = bag,
                        slot = slot,
                        b = bag,
                        i = slot,
                        link = link,
                        itemID = itemID,
                        remainingSeconds = seconds,
                        time = math.max(1, math.ceil(seconds / 60)),
                    }
                end
            end
        end
    end
    return entries
end

local function makeRow(parent, index)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(24)
    row:SetPoint("TOPLEFT", 12, -42 - (index - 1) * 25)
    row:SetPoint("TOPRIGHT", -12, -42 - (index - 1) * 25)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetPoint("LEFT", 4, 0)
    row.text:SetJustifyH("LEFT")
    row.timeText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.timeText:SetPoint("RIGHT", -4, 0)
    row:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.link)
        GameTooltip:Show()
        if BG.Show_AllHighlight then BG.Show_AllHighlight(self.link, "outtime") end
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
        if BG.Hide_AllHighlight then BG.Hide_AllHighlight() end
    end)
    return row
end

local function createFrame(L)
    local parent = BG.MainFrame or UIParent
    local frame = CreateFrame("Frame", "BGNextTradeExpiryFrame", parent, "BackdropTemplate")
    frame:SetSize(460, 390)
    frame:SetPoint("CENTER", parent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface/ChatFrame/ChatFrameBackground",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    frame:SetBackdropColor(0.03, 0.04, 0.06, 0.96)
    frame:SetBackdropBorderColor(0.15, 0.65, 0.85, 0.9)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", 14, -13)
    frame.title:SetText(L["装备过期剩余时间"])
    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", -2, -2)
    frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    frame.empty:SetPoint("CENTER")
    frame.empty:SetText(L["背包里没有可交易的装备。"])
    frame.buttons = {}
    for i = 1, 12 do frame.buttons[i] = makeRow(frame, i) end
    frame.tbl = {}
    frame:Hide()
    return frame
end

local function updateFrame(frame, entries)
    frame.tbl = entries
    if not frame:IsShown() then return end
    frame.empty:SetShown(#entries == 0)
    for i, row in ipairs(frame.buttons) do
        local entry = entries[i]
        if entry then
            row.link = entry.link
            row.itemID = entry.itemID
            row.text:SetText(entry.link)
            row.timeText:SetText(entry.time .. "m")
            row:Show()
        else
            row.link, row.itemID = nil, nil
            row:Hide()
        end
    end
end

function M.install(ns)
    if M.controller or type(CreateFrame) ~= "function" then return M.controller end
    local L = ns and ns.L or setmetatable({}, { __index = function(_, key) return key end })
    local frame = createFrame(L)
    BG.itemGuoQiFrame = frame
    local controller
    controller = M.newController({
        enabled = function() return BiaoGe and BiaoGe.options and BiaoGe.options.guoqiRemind == 1 end,
        isLootLeader = function()
            if BG.ImML and BG.ImML() then return true end
            return BG.IsML == true
        end,
        now = function() return GetServerTime and GetServerTime() or time() end,
        thresholdSeconds = function()
            local minutes = BiaoGe and BiaoGe.options and tonumber(BiaoGe.options.guoqiRemindMinTime) or 30
            return math.max(1, math.min(120, minutes)) * 60
        end,
        mutedUntil = function() return BiaoGe and tonumber(BiaoGe.lastGuoQiTime) or 0 end,
        scan = M.scanBags,
        updateView = function(entries) updateFrame(frame, entries) end,
        notify = function()
            if BG.FrameLootMsg and BG.FrameLootMsg.AddMessage then
                local details = "|HBGNext:BiaoGeGuoQi:" .. L["详细"] .. "|h[" .. L["详细"] .. "]|h"
                local mute = "|HBGNext:BiaoGeGuoQi:" .. L["设置为1小时内不再提醒"] .. "|h[" .. L["设置为1小时内不再提醒"] .. "]|h"
                BG.FrameLootMsg:AddMessage(string.format(L["你有装备快过期了。%s %s"], details, mute))
            end
            if BG.PlaySound then BG.PlaySound("guoqi") end
        end,
        schedule = function(delay, callback) return C_Timer.NewTimer(delay, callback) end,
    })
    frame:SetScript("OnShow", function() controller:refresh() end)
    BG.UpdateItemGuoQiFrame = function() return controller:refresh() end
    M.controller = controller
    if BG.RegisterEvent then
        BG.RegisterEvent("BAG_UPDATE_DELAYED", function() controller:refresh() end)
        BG.RegisterEvent("GROUP_ROSTER_UPDATE", function() controller:refresh() end)
        BG.RegisterEvent("PLAYER_ENTERING_WORLD", function() controller:refresh() end)
    end
    controller:refresh()
    return controller
end

local addonName, ns = ...
if ns and BG.Init then
    BG.Init(function() M.install(ns) end)
end

BG.BGNext.TradeExpiryRuntime = M
return M
