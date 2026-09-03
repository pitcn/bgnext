BG = BG or {}
BG.BGNext = BG.BGNext or {}

local AddonName, ns = ...
local L = ns and ns.L or setmetatable({}, { __index = function(_, key) return tostring(key) end })

-- Runtime wiring for the leader pending-auction queue. It owns one memory-only
-- queue, resolves each item's expected starting price from the active leader
-- scheme (read-only), gates every confirm, and reuses BG.StartAuction for the
-- actual send so every existing permission, validation, price and rate limit
-- stays authoritative. A queued item is only consumed after a matching local
-- created-auction round-trip (BG.HookCreateAuction); opening the confirm dialog,
-- cancelling it, or a failed send keeps the row. Nothing here is persisted and
-- nothing is sent except through the existing auction start path.
local M = {}

local Queue = assert(BG.BGNext.AuctionQueue, "AuctionQueue must load before AuctionQueueRuntime")
local Store = BG.BGNext.AuctionPriceStore

local MAX_ROWS = 40
local ROW_HEIGHT = 26
local TIMEOUT_SECONDS = 10

local FAMILY_ORDER = {
    { flag = "IsRetail", family = "retail" },
    { flag = "IsMOP", family = "mop" },
    { flag = "IsCTM", family = "cata" },
    { flag = "IsTitan", family = "titan" },
    { flag = "IsWLK", family = "wrath" },
    { flag = "IsTBC", family = "tbc" },
    { flag = "IsVanilla", family = "vanilla" },
}

local state = { queue = nil, frame = nil, pending = nil, gen = 0 }

local REASON_TEXT = {
    [Queue.REASON_NO_PERMISSION] = L["无权限发起拍卖"],
    [Queue.REASON_COMBAT] = L["战斗状态下无法发起拍卖"],
    [Queue.REASON_INVALID_ITEM] = L["物品无效"],
    [Queue.REASON_PRICE_UNRESOLVED] = L["请手动输入起拍价"],
    [Queue.REASON_AUCTION_BUSY] = L["已有拍卖进行中"],
    [Queue.REASON_PENDING_START] = L["已有待确认的拍卖"],
    [Queue.REASON_SCOPE_CHANGED] = L["团队或表格已变更"],
    [Queue.REASON_PRICE_CHANGED] = L["起拍价已变更，请重新确认"],
}

local SOURCE_TEXT = {
    [Queue.SOURCE_OVERRIDE] = L["单件价"],
    [Queue.SOURCE_BASE] = L["基础价"],
    [Queue.SOURCE_MANUAL] = L["手动输入"],
}

local function clientFamily()
    for _, entry in ipairs(FAMILY_ORDER) do
        if BG[entry.flag] then return entry.family end
    end
    return nil
end

local function storageRoot()
    return BG.BGNext and BG.BGNext.DB
end

local function currentRaid()
    local raidId = BG.FB1
    return type(raidId) == "string" and raidId ~= "" and raidId or nil
end

-- Resolves one item's price + source from the active leader scheme. Returns
-- { price, source } or nil. Read-only; it never writes back to the scheme.
local function resolvePrice(itemId)
    local root = storageRoot()
    local family = clientFamily()
    local raidId = currentRaid()
    if type(root) ~= "table" or type(family) ~= "string" or raidId == nil or not Store then
        return nil
    end
    return Store.resolveLeaderPriceDetail(root, family, raidId, itemId)
end

-- A short, non-reversible digest of the current raid roster so the scope key
-- distinguishes two different raid sessions even when the same table remains
-- selected. The roster is read transiently and never copied or stored.
local function hashString(s)
    local hash = 5381
    for i = 1, #s do
        hash = (hash * 33 + string.byte(s, i)) % 2147483647
    end
    return hash
end

local function raidSessionToken()
    if type(IsInRaid) == "function" and not IsInRaid(1) then return nil end
    local names = {}
    local count = 0
    if type(GetNumGroupMembers) == "function" then
        count = GetNumGroupMembers()
    end
    if type(GetRaidRosterInfo) == "function" and count > 0 then
        for i = 1, count do
            local name = GetRaidRosterInfo(i)
            if type(name) == "string" and name ~= "" then names[#names + 1] = name end
        end
    elseif type(BG.raidRosterInfo) == "table" then
        for _, entry in ipairs(BG.raidRosterInfo) do
            if type(entry) == "table" and type(entry.name) == "string" then names[#names + 1] = entry.name end
        end
        count = #names
    end
    table.sort(names)
    return tostring(count) .. ":" .. tostring(hashString(table.concat(names, "\1")))
end

function M.scopeKey()
    local tableKey = BG.FB1
    tableKey = type(tableKey) == "string" and tableKey ~= "" and tableKey or ""
    local token = raidSessionToken()
    if token == nil then
        return tableKey ~= "" and tableKey or ""
    end
    return tableKey .. "|" .. token
end

function M.ensureQueue()
    local key = M.scopeKey()
    if state.queue == nil or Queue.scopeChanged(state.queue, key) then
        state.queue = Queue.create(key)
    end
    return state.queue
end

function M.queue()
    return M.ensureQueue()
end

function M.isController()
    if BG.IsML == true then return true end
    if type(BG.ImMLorLeader) == "function" then return BG.ImMLorLeader() end
    return false
end

function M.inCombat()
    return InCombatLockdown and InCombatLockdown()
end

-- Busy when ANY live auction card exists; ended (lingering) cards do not block.
function M.auctionInProgress()
    if type(BGA) ~= "table" or type(BGA.Frames) ~= "table" then return false end
    for _, frame in pairs(BGA.Frames) do
        if type(frame) == "table" and not frame.IsEnd then return true end
    end
    return false
end

function M.gateContext()
    return {
        isController = M.isController(),
        inCombat = M.inCombat(),
        auctionInProgress = M.auctionInProgress(),
    }
end

function M.add(item)
    return Queue.add(M.ensureQueue(), item)
end

-- Parses an item id out of typed text, an "item:123" hyperlink, or a full item
-- link. Returns the numeric id or nil. Used by the drag/typed add path so only
-- a valid positive integer id can ever enter the queue.
function M.parseItemText(text)
    if type(text) ~= "string" then return nil end
    local id = text:match("item:(%d+)")
    if id then return tonumber(id) end
    id = text:match("^(%d+)$")
    if id then return tonumber(id) end
    return nil
end

function M.addFromText(text, quantity)
    local itemId = M.parseItemText(text)
    if not itemId then
        if type(BG.SendSystemMessage) == "function" then
            BG.SendSystemMessage(L["物品无效"])
        end
        return nil
    end
    local link = "item:" .. itemId
    local id = M.add({ itemId = itemId, link = link, quantity = quantity })
    M.refreshUI()
    return id
end

function M.remove(id)
    return Queue.remove(M.ensureQueue(), id)
end

function M.move(id, delta)
    return Queue.move(M.ensureQueue(), id, delta)
end

function M.moveTo(id, index)
    return Queue.moveTo(M.ensureQueue(), id, index)
end

function M.setQuantity(id, quantity)
    return Queue.setQuantity(M.ensureQueue(), id, quantity)
end

function M.adjustQuantity(id, delta)
    return Queue.adjustQuantity(M.ensureQueue(), id, delta)
end

function M.setPrice(id, price)
    return Queue.setPrice(M.ensureQueue(), id, price)
end

function M.clear()
    if state.queue then Queue.clear(state.queue) end
end

function M.project()
    return Queue.project(M.ensureQueue(), resolvePrice)
end

function M.sourceText(source)
    return SOURCE_TEXT[source] or ""
end

function M.reasonText(reason)
    return REASON_TEXT[reason]
end

local function findRow(q, id)
    if type(id) ~= "number" then return nil end
    for _, candidate in ipairs(Queue.project(q, resolvePrice)) do
        if candidate.id == id then return candidate end
    end
    return nil
end

-- Re-runs every gate against a freshly projected row at the actual Start click.
-- Returns nil when the send may proceed, or the blocking reason. `pending` is
-- the single in-flight confirm this button belongs to.
local function secondGate(pending)
    if type(pending) ~= "table" then return Queue.REASON_INVALID_ITEM end
    if state.pending ~= pending then return Queue.REASON_SCOPE_CHANGED end
    if pending.fired then return Queue.REASON_PENDING_START end
    local q = M.ensureQueue()
    local row = findRow(q, pending.id)
    local ctx = M.gateContext()
    ctx.scopeChanged = Queue.scopeChanged(q, M.scopeKey())
    local reason = Queue.gate(row, ctx)
    if reason then return reason end
    if type(pending.snapshot) == "table" and row then
        if row.price ~= pending.snapshot.price or row.source ~= pending.snapshot.source then
            return Queue.REASON_PRICE_CHANGED
        end
    end
    return nil
end

-- Arms the one-shot stale-pending timeout. A matching round-trip clears the
-- pending (and therefore the generation), so a late timer can never drop a
-- newer pending. On timeout the queued row is kept for a fresh confirm.
function M.armTimeout(pending)
    local gen = pending and pending.gen
    if type(BG.After) == "function" then
        BG.After(TIMEOUT_SECONDS, function()
            if state.pending and state.pending.gen == gen then
                state.pending = nil
                M.refreshUI()
            end
        end)
    end
end

local function installSecondGate(frame, pending)
    if type(frame) ~= "table" or type(frame.bt) ~= "table" then return end

    -- One item per confirmation: force the legacy quantity box to 1 and lock it
    -- so the existing start handler can never run its multi-send path.
    if type(frame.Edit3) == "table" then
        if type(frame.Edit3.SetText) == "function" then frame.Edit3:SetText("1") end
        if type(frame.Edit3.SetEnabled) == "function" then frame.Edit3:SetEnabled(false) end
    end

    local original = type(frame.bt.GetScript) == "function" and frame.bt:GetScript("OnClick")
    if type(frame.bt.SetScript) == "function" then
        frame.bt:SetScript("OnClick", function(self)
            local reason = secondGate(pending)
            if reason then
                local text = M.reasonText(reason)
                if text and type(BG.SendSystemMessage) == "function" then
                    BG.SendSystemMessage(text)
                end
                return
            end
            if type(frame.Edit3) == "table" and type(frame.Edit3.SetText) == "function" then
                frame.Edit3:SetText("1")
            end
            pending.fired = true
            M.armTimeout(pending)
            if original then original(self) end
        end)
    end

    -- Cancelling (close or escape) keeps the row and frees the pending slot. A
    -- fired send keeps the pending so only its matching round-trip consumes it.
    if type(frame.HookScript) == "function" then
        frame:HookScript("OnHide", function()
            if state.pending == pending and not pending.fired then
                state.pending = nil
            end
        end)
    end
end

-- Opens the existing confirm dialog for the queued row. Returns true only when
-- the dialog opened; the row is never removed here.
function M.confirm(id)
    local q = M.ensureQueue()
    local row = findRow(q, id)
    local ctx = M.gateContext()
    ctx.scopeChanged = Queue.scopeChanged(q, M.scopeKey())
    ctx.pendingStart = state.pending ~= nil
    local reason = Queue.gate(row, ctx)
    if reason then
        local text = M.reasonText(reason)
        if text and type(BG.SendSystemMessage) == "function" then
            BG.SendSystemMessage(text)
        end
        return false
    end

    local link = row.link or ("item:" .. row.itemId)
    state.gen = state.gen + 1
    local pending = {
        id = row.id,
        itemId = row.itemId,
        snapshot = { price = row.price, source = row.source },
        fired = false,
        gen = state.gen,
    }
    state.pending = pending

    local previous = BG.StartAucitonFrame
    BG.StartAuction(link, nil, nil, true)
    if BG.StartAucitonFrame == previous then
        -- The existing start path refused to open (its own gate or no item);
        -- drop the pending so the row can be retried, and keep the row.
        state.pending = nil
        return false
    end
    return true
end

-- A locally created auction that matches the pending item consumes exactly one
-- queued quantity (removing the row at quantity one).
local function onLoopback(frame)
    local pending = state.pending
    if not pending then return end
    if type(frame) ~= "table" or frame.itemID ~= pending.itemId then return end
    local q = M.ensureQueue()
    Queue.decrement(q, pending.id)
    state.pending = nil
    M.refreshUI()
end

-- --- Player-accessible UI ------------------------------------------------

local function bindRow(rowFrame, projected, index)
    rowFrame.id = projected.id
    rowFrame.link = projected.link or ("item:" .. projected.itemId)
    rowFrame:SetPoint("TOPLEFT", state.frame, "TOPLEFT", 4, -(state.frame.headerHeight + (index - 1) * ROW_HEIGHT))
    if rowFrame.name then
        rowFrame.name:SetText(projected.link or tostring(projected.itemId))
    end
    if rowFrame.count then
        rowFrame.count:SetText("x" .. projected.quantity)
    end
    local manual = projected.source == Queue.SOURCE_MANUAL
    if rowFrame.price then
        if manual then
            rowFrame.price:Hide()
        else
            rowFrame.price:Show()
            rowFrame.price:SetText(tostring(projected.price or "") .. " " .. M.sourceText(projected.source))
        end
    end
    if rowFrame.priceEdit then
        if manual then
            rowFrame.priceEdit:Show()
            rowFrame.priceEdit:SetText(projected.price ~= nil and tostring(projected.price) or "")
        else
            rowFrame.priceEdit:Hide()
        end
    end
end

function M.refreshUI()
    local frame = state.frame
    if not frame or type(frame.rows) ~= "table" then return end
    local rows = M.project()
    for index, rowFrame in ipairs(frame.rows) do
        if index <= #rows then
            bindRow(rowFrame, rows[index], index)
            rowFrame:Show()
        else
            rowFrame:Hide()
        end
    end
    if type(frame.SetHeight) == "function" then
        frame:SetHeight(frame.headerHeight + #rows * ROW_HEIGHT + 10)
    end
end

local function createRow(parent)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetSize(344, ROW_HEIGHT)
    row:SetBackdrop({ bgFile = "Interface/ChatFrame/ChatFrameBackground" })
    row:SetBackdropColor(0.2, 0.2, 0.2, 0.6)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("LEFT", 4, 0)
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.count:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row.price = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.price:SetPoint("LEFT", row.count, "RIGHT", 6, 0)
    row.priceEdit = CreateFrame("EditBox", nil, row)
    row.priceEdit:SetSize(70, 16)
    row.priceEdit:SetPoint("LEFT", row.count, "RIGHT", 6, 0)
    row.priceEdit:SetAutoFocus(false)
    row.priceEdit:Hide()

    row.minus = CreateFrame("Button", nil, row)
    row.minus:SetSize(16, 16)
    row.minus:SetPoint("RIGHT", row, "RIGHT", -96, 0)
    row.minus:SetText("-")
    row.plus = CreateFrame("Button", nil, row)
    row.plus:SetSize(16, 16)
    row.plus:SetPoint("LEFT", row.minus, "RIGHT", 0, 0)
    row.plus:SetText("+")

    row.up = CreateFrame("Button", nil, row)
    row.up:SetSize(30, 16)
    row.up:SetPoint("RIGHT", row, "RIGHT", -44, 0)
    row.up:SetText(L["上移"])
    row.down = CreateFrame("Button", nil, row)
    row.down:SetSize(30, 16)
    row.down:SetPoint("LEFT", row.up, "RIGHT", 0, 0)
    row.down:SetText(L["下移"])
    row.remove = CreateFrame("Button", nil, row)
    row.remove:SetSize(30, 16)
    row.remove:SetPoint("LEFT", row.down, "RIGHT", 2, 0)
    row.remove:SetText(L["移除"])

    row:SetScript("OnEnter", function(self)
        if self.link and type(GameTooltip) == "table" and type(GameTooltip.SetOwner) == "function" then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if type(GameTooltip.SetHyperlink) == "function" then GameTooltip:SetHyperlink(self.link) end
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function()
        if type(GameTooltip) == "table" and type(GameTooltip.Hide) == "function" then GameTooltip:Hide() end
    end)
    row:SetScript("OnClick", function(self)
        if self.id then M.confirm(self.id) end
    end)

    row.minus:SetScript("OnClick", function(self)
        local id = self:GetParent().id
        M.adjustQuantity(id, -1)
        M.refreshUI()
    end)
    row.plus:SetScript("OnClick", function(self)
        local id = self:GetParent().id
        M.adjustQuantity(id, 1)
        M.refreshUI()
    end)
    row.up:SetScript("OnClick", function(self)
        local id = self:GetParent().id
        M.move(id, -1)
        M.refreshUI()
    end)
    row.down:SetScript("OnClick", function(self)
        local id = self:GetParent().id
        M.move(id, 1)
        M.refreshUI()
    end)
    row.remove:SetScript("OnClick", function(self)
        local id = self:GetParent().id
        M.remove(id)
        M.refreshUI()
    end)
    row.priceEdit:SetScript("OnEditFocusLost", function(self)
        local parent = self:GetParent()
        if parent and parent.id then
            local value = tonumber(self:GetText())
            if value then M.setPrice(parent.id, value) else M.setPrice(parent.id, nil) end
            M.refreshUI()
        end
    end)
    row.priceEdit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return row
end

function M.openFrame()
    local frame = state.frame
    if not frame then
        frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        frame:SetSize(360, 200)
        frame:SetPoint("CENTER")
        frame:SetBackdrop({
            bgFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeFile = "Interface/ChatFrame/ChatFrameBackground",
            edgeSize = 2,
        })
        frame:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        frame:SetBackdropBorderColor(0, 0, 0, 1)
        frame:SetFrameStrata("DIALOG")
        frame:SetClampedToScreen(true)
        frame:SetMovable(true)
        frame:EnableMouse(true)
        frame:SetScript("OnMouseDown", function(self) self:StartMoving() end)
        frame:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

        frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        frame.title:SetPoint("TOP", 0, -6)
        frame.title:SetText(L["待拍队列"])

        frame.input = CreateFrame("EditBox", nil, frame)
        frame.input:SetSize(150, 20)
        frame.input:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, -22)
        frame.input:SetAutoFocus(false)
        frame.input:SetScript("OnEnterPressed", function(self)
            M.addFromText(self:GetText())
            self:SetText("")
        end)

        frame.addButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        frame.addButton:SetSize(44, 20)
        frame.addButton:SetPoint("LEFT", frame.input, "RIGHT", 4, 0)
        frame.addButton:SetText(L["添加"])
        frame.addButton:SetScript("OnClick", function()
            M.addFromText(frame.input:GetText())
            frame.input:SetText("")
        end)

        frame.clearButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        frame.clearButton:SetSize(44, 20)
        frame.clearButton:SetPoint("LEFT", frame.addButton, "RIGHT", 4, 0)
        frame.clearButton:SetText(L["清空"])
        frame.clearButton:SetScript("OnClick", function()
            M.clear()
            M.refreshUI()
        end)

        frame.rows = {}
        for i = 1, MAX_ROWS do
            local row = createRow(frame)
            row:Hide()
            frame.rows[i] = row
        end
        frame.headerHeight = 48
        state.frame = frame
    end
    frame:Show()
    M.refreshUI()
    return frame
end

function M.toggle()
    if state.frame and state.frame:IsShown() then
        state.frame:Hide()
    else
        M.openFrame()
    end
end

local entryButton = nil
function M.installEntry(mainFrame)
    if entryButton then return entryButton end
    if type(mainFrame) ~= "table" or type(CreateFrame) ~= "function" or type(BG.CreateButton) ~= "function" then
        return nil
    end
    local button = BG.CreateButton(mainFrame)
    button:SetSize(100, 20)
    local anchor = BG.ButtonCurrentTradeRecord or BG.ButtonRoleOverview
    if anchor then
        button:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
    else
        button:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -10, 8)
    end
    button:SetText(L["待拍队列"])
    button:SetScript("OnClick", function()
        if type(BG.PlaySound) == "function" then BG.PlaySound(1) end
        M.toggle()
    end)
    entryButton = button
    return button
end

-- --- Lifecycle -----------------------------------------------------------

function M.onRosterUpdate()
    if type(IsInRaid) == "function" and not IsInRaid(1) then
        M.clear()
        state.pending = nil
        M.refreshUI()
        return
    end
    if state.queue and Queue.size(state.queue) > 0 then
        local key = M.scopeKey()
        if Queue.scopeChanged(state.queue, key) then
            M.clear()
            state.pending = nil
            M.refreshUI()
        end
    end
end

function M.onLeavingWorld()
    M.clear()
    state.pending = nil
    M.refreshUI()
end

function M.state()
    return {
        queueSize = state.queue and Queue.size(state.queue) or 0,
        scopeKey = state.queue and state.queue.scopeKey or nil,
        hasPending = state.pending ~= nil,
        pendingFired = state.pending and state.pending.fired or false,
        pendingItemId = state.pending and state.pending.itemId or nil,
        frameShown = state.frame and state.frame:IsShown() and true or false,
    }
end

local installed = false
BG.Init(function()
    if installed then return end
    installed = true

    if type(BG.StartAuction) == "function" then
        local originalStart = BG.StartAuction
        BG.StartAuction = function(...)
            local previous = BG.StartAucitonFrame
            local result = originalStart(...)
            if BG.StartAucitonFrame ~= previous and state.pending then
                installSecondGate(BG.StartAucitonFrame, state.pending)
            end
            return result
        end
    end

    if type(BG.HookCreateAuction) == "function" then
        local originalHook = BG.HookCreateAuction
        BG.HookCreateAuction = function(frame)
            if originalHook then originalHook(frame) end
            onLoopback(frame)
        end
    end

    if type(BG.ClearBiaoGe) == "function" then
        local originalClear = BG.ClearBiaoGe
        BG.ClearBiaoGe = function(_type, FB, ...)
            if FB == BG.FB1 then
                M.clear()
                state.pending = nil
                M.refreshUI()
            end
            return originalClear(_type, FB, ...)
        end
    end

    if type(BG.RegisterEvent) == "function" then
        BG.RegisterEvent("GROUP_ROSTER_UPDATE", function() M.onRosterUpdate() end)
        BG.RegisterEvent("PLAYER_LEAVING_WORLD", function() M.onLeavingWorld() end)
    end
end)

BG.Init2(function()
    if type(SlashCmdList) == "table" and type(_G) == "table" then
        SlashCmdList["BGNQUEUE"] = function() M.toggle() end
        _G.SLASH_BGNQUEUE1 = "/bgnqueue"
        _G.SLASH_BGNQUEUE2 = "/bgnq"
    end
    if type(BG.MainFrame) == "table" then
        M.installEntry(BG.MainFrame)
    end
end)

BG.BGNext.AuctionQueueRuntime = M
return M
