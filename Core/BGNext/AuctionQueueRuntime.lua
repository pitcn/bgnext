BG = BG or {}
BG.BGNext = BG.BGNext or {}

local AddonName, ns = ...
local L = ns and ns.L or setmetatable({}, { __index = function(_, key) return tostring(key) end })

-- Runtime wiring for the leader pending-auction queue. It owns one memory-only
-- queue, resolves each item's expected starting price from the active leader
-- scheme (read-only), gates every confirm, and reuses BG.StartAuction for the
-- actual send so every existing permission, validation, price and rate limit
-- stays authoritative. Nothing here is persisted and nothing is sent except
-- through the existing auction start path.
local M = {}

local Queue = assert(BG.BGNext.AuctionQueue, "AuctionQueue must load before AuctionQueueRuntime")
local Store = BG.BGNext.AuctionPriceStore

local MAX_AUCTIONS = 10

local FAMILY_ORDER = {
    { flag = "IsRetail", family = "retail" },
    { flag = "IsMOP", family = "mop" },
    { flag = "IsCTM", family = "cata" },
    { flag = "IsTitan", family = "titan" },
    { flag = "IsWLK", family = "wrath" },
    { flag = "IsTBC", family = "tbc" },
    { flag = "IsVanilla", family = "vanilla" },
}

local state = { queue = nil, frame = nil }

local REASON_TEXT = {
    [Queue.REASON_NO_PERMISSION] = L["无权限发起拍卖"],
    [Queue.REASON_COMBAT] = L["战斗状态下无法发起拍卖"],
    [Queue.REASON_INVALID_ITEM] = L["物品无效"],
    [Queue.REASON_PRICE_UNRESOLVED] = L["请手动输入起拍价"],
    [Queue.REASON_AUCTION_BUSY] = L["已有拍卖进行中"],
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

function M.ensureQueue()
    local key = currentRaid() or ""
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

function M.auctionInProgress()
    if type(BGA) ~= "table" or type(BGA.Frames) ~= "table" then return false end
    local count = 0
    for _ in pairs(BGA.Frames) do count = count + 1 end
    return count >= MAX_AUCTIONS
end

function M.add(item)
    return Queue.add(M.ensureQueue(), item)
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

-- Confirms the queued item at `id`: resolves its row, runs the gate, and only
-- then reuses BG.StartAuction. The item is removed only when the existing start
-- path actually created a frame (so a permission/validation early-return keeps
-- the row queued). Returns true when the send path ran, false when blocked.
function M.confirm(id)
    local q = M.ensureQueue()
    local row
    for _, candidate in ipairs(Queue.project(q, resolvePrice)) do
        if candidate.id == id then row = candidate end
    end
    local reason = Queue.gate(row, {
        isController = M.isController(),
        inCombat = M.inCombat(),
        auctionInProgress = M.auctionInProgress(),
    })
    if reason then
        local text = M.reasonText(reason)
        if text and type(BG.SendSystemMessage) == "function" then
            BG.SendSystemMessage(text)
        end
        return false
    end
    local link = row.link or ("item:" .. row.itemId)
    local previous = BG.StartAucitonFrame
    BG.StartAuction(link, nil, nil, true, true)
    if BG.StartAucitonFrame ~= previous then
        Queue.remove(q, id)
    end
    return true
end

-- --- Minimal queue frame ------------------------------------------------

local function refreshFrame()
    local frame = state.frame
    if not frame then return end
    if frame.rows then
        for _, row in ipairs(frame.rows) do
            row:Hide()
        end
    end
    frame.rows = frame.rows or {}
    local rows = M.project()
    for index, projected in ipairs(rows) do
        local row = frame.rows[index]
        if not row then
            row = CreateFrame("Button", nil, frame, "BackdropTemplate")
            row:SetSize(230, 22)
            row:SetBackdrop({ bgFile = "Interface/ChatFrame/ChatFrameBackground" })
            row:SetBackdropColor(0.2, 0.2, 0.2, 0.6)
            row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.text:SetPoint("LEFT", 4, 0)
            row:SetScript("OnEnter", function(self)
                if self.link then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(self.link)
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            frame.rows[index] = row
        end
        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -(frame.titleHeight + (index - 1) * 24))
        row.link = projected.link or ("item:" .. projected.itemId)
        local price = projected.price
        local source = M.sourceText(projected.source)
        row.text:SetText(string.format("%s x%d  %s %s",
            projected.itemId, projected.quantity,
            price ~= nil and price or "", source))
        row:Show()
        row.id = projected.id
        row:SetScript("OnClick", function(self)
            if self.id then M.confirm(self.id) end
            refreshFrame()
        end)
    end
    frame:SetHeight(frame.titleHeight + #rows * 24 + 8)
end

local function openFrame()
    local frame = state.frame
    if not frame then
        frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        frame:SetSize(250, 120)
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
        frame.titleHeight = 30
        state.frame = frame
    end
    frame:Show()
    refreshFrame()
end

function M.toggle()
    if state.frame and state.frame:IsShown() then
        state.frame:Hide()
    else
        openFrame()
    end
end

-- --- Lifecycle -----------------------------------------------------------

local installed = false
BG.Init(function()
    if installed then return end
    installed = true

    -- Leaving the raid drops the queue; a table switch or clear is caught
    -- lazily by ensureQueue on the next operation and here on roster updates.
    if type(BG.RegisterEvent) == "function" then
        BG.RegisterEvent("GROUP_ROSTER_UPDATE", function()
            if not IsInRaid(1) then M.clear() end
        end)
    end

    -- Clearing the current table also clears its pending queue.
    if type(BG.ClearBiaoGe) == "function" then
        local original = BG.ClearBiaoGe
        BG.ClearBiaoGe = function(_type, FB, ...)
            if FB == BG.FB1 then M.clear() end
            return original(_type, FB, ...)
        end
    end
end)

BG.BGNext.AuctionQueueRuntime = M
return M
