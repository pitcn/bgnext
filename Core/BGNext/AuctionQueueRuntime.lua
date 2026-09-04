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
local PreSend = assert(BG.BGNext.AuctionPreSend, "AuctionPreSend must load before AuctionQueueRuntime")

local MAX_ROWS = Queue.MAX_ITEMS
local ROW_HEIGHT = 26
local HEADER_HEIGHT = 48
local BOTTOM_PADDING = 26
local TIMEOUT_SECONDS = 10

local state = { queue = nil, frame = nil, pending = nil, gen = 0 }

-- Native WoW UI objects can be userdata while still exposing Frame methods and
-- writable addon fields. Runtime gates therefore validate object capability,
-- not only the Lua table representation used by the test harness.
local function isFrameObject(value)
    local kind = type(value)
    return kind == "table" or kind == "userdata"
end

-- Screen-relative viewport height: rows are bound into a fixed pool whose
-- visible count never exceeds what actually fits, so the queue window stays
-- on-screen at any UIParent height instead of growing to 40*26 + header.
local function availableViewport()
    if type(UIParent) ~= "table" or type(UIParent.GetHeight) ~= "function" then
        return nil
    end
    local height = UIParent:GetHeight()
    if type(height) ~= "number" or height <= 0 then return nil end
    return height
end

local function maxVisibleRows()
    local viewport = availableViewport()
    if viewport == nil then return MAX_ROWS end
    return math.min(MAX_ROWS, math.max(1, math.floor((viewport - HEADER_HEIGHT - BOTTOM_PADDING) / ROW_HEIGHT)))
end

local REASON_TEXT = {
    [Queue.REASON_NO_PERMISSION] = L["无权限发起拍卖"],
    [Queue.REASON_COMBAT] = L["战斗状态下无法发起拍卖"],
    [Queue.REASON_INVALID_ITEM] = L["物品无效"],
    [Queue.REASON_PRICE_UNRESOLVED] = L["请手动输入起拍价"],
    [Queue.REASON_AUCTION_BUSY] = L["已有拍卖进行中"],
    [Queue.REASON_PENDING_START] = L["已有待确认的拍卖"],
    [Queue.REASON_SCOPE_CHANGED] = L["团队或表格已变更"],
    [Queue.REASON_PRICE_CHANGED] = L["起拍价已变更，请重新确认"],
    [Queue.REASON_QUEUE_FULL] = L["待拍队列已满（最多40项）"],
    [Queue.REASON_SCHEME_CHANGED] = L["起拍价方案已变更，请重新确认"],
    [Queue.REASON_FAMILY_CHANGED] = L["客户端版本已变更，请重新确认"],
}

local SOURCE_TEXT = {
    [Queue.SOURCE_OVERRIDE] = L["单件价"],
    [Queue.SOURCE_BASE] = L["基础价"],
    [Queue.SOURCE_MANUAL] = L["手动输入"],
}

local function storageRoot()
    return BG.BGNext and BG.BGNext.DB
end

local function featureEnabled()
    local settings = BG.BGNext and BG.BGNext.FeatureSettings
    if not settings then return true end
    if type(settings.isCurrentEnabled) == "function" then
        return settings.isCurrentEnabled("auction_queue", BG, storageRoot())
    end
    if type(settings.isEnabled) ~= "function" then return true end
    return settings.isEnabled(storageRoot(), "auction_queue", "wrath")
end

local function currentRaid()
    local raidId = BG.FB1
    return type(raidId) == "string" and raidId ~= "" and raidId or nil
end

-- Resolves one item's price + source from the active leader scheme. Returns
-- { price, source } or nil. Read-only; it never writes back to the scheme.
local function resolvePrice(itemId)
    local root = storageRoot()
    local family = PreSend.clientFamily()
    local raidId = currentRaid()
    if type(root) ~= "table" or type(family) ~= "string" or raidId == nil or not Store then
        return nil
    end
    return Store.resolveLeaderPriceDetail(root, family, raidId, itemId)
end

function M.scopeKey()
    return PreSend.scopeKey()
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

-- The single shared pre-send gate owns the authoritative answers to these
-- environment questions, so the queue runtime never drifts from the preset
-- direct-start path. Delegated, not re-implemented.
function M.isController()
    return PreSend.isController()
end

function M.inCombat()
    return PreSend.inCombat()
end

function M.auctionInProgress()
    return PreSend.auctionInProgress()
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
    local id, reason = M.add({ itemId = itemId, link = link, quantity = quantity })
    if id == nil then
        local text = M.reasonText(reason)
        if text and type(BG.SendSystemMessage) == "function" then
            BG.SendSystemMessage(text)
        end
    end
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

-- Re-resolves one queued item for the shared pre-send gate. The active scheme is
-- authoritative; a manual row (no scheme) falls back to its stored manual price.
-- Returns { price, source, activePresetId } or nil.
local function resolveApproval(q, id, itemId, raidId)
    if Store and type(Store.resolveLeaderApproval) == "function" then
        local root = storageRoot()
        local family = PreSend.clientFamily()
        local resolved = Store.resolveLeaderApproval(root, family, raidId, itemId)
        if resolved ~= nil and type(resolved.price) == "number" then
            return resolved
        end
    end
    local row = findRow(q, id)
    if type(row) == "table" and row.source == Queue.SOURCE_MANUAL and type(row.price) == "number" then
        return { price = row.price, source = Queue.SOURCE_MANUAL }
    end
    return nil
end

-- Re-runs the single shared pre-send gate against the approval snapshot captured
-- at confirm time. Returns nil when the send may proceed, or the blocking reason.
-- `pending` is the single in-flight confirm this button belongs to.
local function secondGate(pending)
    if type(pending) ~= "table" then return Queue.REASON_INVALID_ITEM end
    if state.pending ~= pending then return Queue.REASON_SCOPE_CHANGED end
    if pending.fired then return Queue.REASON_PENDING_START end
    local q = M.ensureQueue()
    return PreSend.gate(pending.approval, function(itemId, raidId)
        return resolveApproval(q, pending.id, itemId, raidId)
    end)
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
    if not isFrameObject(frame) or not isFrameObject(frame.bt) then return end

    -- One item per confirmation: force the legacy quantity box to 1 and lock it
    -- so the existing start handler can never run its multi-send path.
    if isFrameObject(frame.Edit3) then
        if type(frame.Edit3.SetText) == "function" then frame.Edit3:SetText("1") end
        if type(frame.Edit3.SetEnabled) == "function" then frame.Edit3:SetEnabled(false) end
    end

    -- Bind the approved amount to the confirmation button's per-send money so the
    -- legacy handler (`self.money or BiaoGe.Auction.money`) can never fall back to
    -- a stale global preset. The saved preset is left untouched.
    local approved = type(pending.snapshot) == "table" and pending.snapshot.price or nil
    if approved ~= nil then
        frame.bt.money = approved
    end

    -- Show the approved amount in Edit2 without writing back to the saved preset
    -- (the legacy OnTextChanged stores whatever is typed into BiaoGe.Auction).
    if isFrameObject(frame.Edit2) and type(frame.Edit2.SetText) == "function" then
        local edit2 = frame.Edit2
        local onChanged
        if type(edit2.GetScript) == "function" then
            onChanged = edit2:GetScript("OnTextChanged")
            if type(edit2.SetScript) == "function" then
                edit2:SetScript("OnTextChanged", nil)
            end
        end
        edit2:SetText(tostring(approved))
        if onChanged and type(edit2.SetScript) == "function" then
            edit2:SetScript("OnTextChanged", onChanged)
        end
    end

    -- Authoritative pre-send gate. The legacy Start_OnClick invokes this before
    -- any side effect; every activation path (button click, Edit2 Enter,
    -- quick-price) funnels through Start_OnClick, so this single optional hook
    -- covers them all. Returning false/nil vetoes the send with no side effects.
    frame.bt.onPreSend = function()
        local reason = secondGate(pending)
        if reason then
            local text = M.reasonText(reason)
            if text and type(BG.SendSystemMessage) == "function" then
                BG.SendSystemMessage(text)
            end
            return false
        end
        -- Editing the price box after confirmation invalidates the approval;
        -- require a fresh confirm instead of silently sending a changed amount.
        if approved ~= nil and isFrameObject(frame.Edit2)
            and type(frame.Edit2.GetText) == "function" then
            local edited = tonumber(frame.Edit2:GetText())
            if edited ~= approved then
                local text = M.reasonText(Queue.REASON_PRICE_CHANGED)
                if text and type(BG.SendSystemMessage) == "function" then
                    BG.SendSystemMessage(text)
                end
                return false
            end
        end
        if isFrameObject(frame.Edit3) and type(frame.Edit3.SetText) == "function" then
            frame.Edit3:SetText("1")
        end
        pending.fired = true
        M.armTimeout(pending)
        return true
    end

    -- Causal auctionID capture. The legacy scheduled send closure hands the
    -- auctionID it just received to this callback, so the queue binds exactly its
    -- own send and never a foreign same-item sender racing in the BG.After(0)
    -- window. Other senders do not own this callback and cannot touch the pending.
    frame.bt.onAuctionSent = function(auctionID, itemID, money, link)
        if state.pending == pending and pending.fired then
            pending.auctionID = auctionID
        end
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

-- Installs the shared pre-send gate for a preset Alt+right-click direct start.
-- The Price wrapper already pre-filled the price box and recorded
-- `frame.bgnextDirectApproval`; it must NOT click on its own, because the queue
-- wrapper is the outermost layer and only here is the gate guaranteed to be
-- armed before the reused OnClick runs. We arm the gate, then invoke the real
-- Start_OnClick (the same closure every other entry path funnels through), so a
-- direct start can never bypass BG.SendStartAuctionMsg or the pre-send checks.
local function installDirectGate(frame)
    if not isFrameObject(frame) or not isFrameObject(frame.bt) then return end
    local approval = frame.bgnextDirectApproval
    if type(approval) ~= "table" then return end

    -- One item per direct start: force the legacy quantity box to 1 and lock it
    -- so the reused handler runs its single-send path.
    if isFrameObject(frame.Edit3) then
        if type(frame.Edit3.SetText) == "function" then frame.Edit3:SetText("1") end
        if type(frame.Edit3.SetEnabled) == "function" then frame.Edit3:SetEnabled(false) end
    end

    frame.bt.onPreSend = function()
        local reason = PreSend.gate(approval, function(itemId, raidId)
            if Store and type(Store.resolveLeaderApproval) == "function" then
                return Store.resolveLeaderApproval(storageRoot(), PreSend.clientFamily(), raidId, itemId)
            end
            return nil
        end)
        if reason then
            local text = M.reasonText(reason)
            if text and type(BG.SendSystemMessage) == "function" then
                BG.SendSystemMessage(text)
            end
            return false
        end
        return true
    end

    frame.bgnextDirectApproval = nil
    if type(frame.bt.GetScript) == "function" then
        local click = frame.bt:GetScript("OnClick")
        if type(click) == "function" then
            click(frame.bt)
        end
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
    local family = PreSend.clientFamily()
    local raidId = currentRaid()
    local approvalItem
    if Store and type(Store.resolveLeaderApproval) == "function" then
        local resolved = Store.resolveLeaderApproval(storageRoot(), family, raidId, row.itemId)
        if resolved ~= nil and type(resolved.price) == "number" then
            approvalItem = {
                itemId = row.itemId,
                raidId = raidId,
                price = resolved.price,
                source = resolved.source,
                activePresetId = resolved.activePresetId,
            }
        end
    end
    if approvalItem == nil then
        -- No scheme produced a price: snapshot the manual row so the shared gate
        -- can still re-validate its stored manual price at the actual send.
        approvalItem = {
            itemId = row.itemId,
            raidId = raidId,
            price = row.price,
            source = row.source,
        }
    end
    state.gen = state.gen + 1
    local pending = {
        id = row.id,
        itemId = row.itemId,
        snapshot = { price = row.price, source = row.source },
        approval = {
            clientFamily = family,
            scopeKey = M.scopeKey(),
            items = { approvalItem },
        },
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
    if not pending.fired or pending.auctionID == nil then return end
    if not isFrameObject(frame) or frame.auctionID ~= pending.auctionID then return end
    local q = M.ensureQueue()
    Queue.decrement(q, pending.id)
    state.pending = nil
    M.refreshUI()
end

-- --- Player-accessible UI ------------------------------------------------

local function bindRow(rowFrame, projected, slot)
    rowFrame.id = projected.id
    rowFrame.link = projected.link or ("item:" .. projected.itemId)
    rowFrame:SetPoint("TOPLEFT", state.frame, "TOPLEFT", 4, -(state.frame.headerHeight + (slot - 1) * ROW_HEIGHT))
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
    local maxVisible = frame.maxVisible or MAX_ROWS
    local offset = frame.scrollOffset or 0
    local maxOffset = math.max(0, #rows - maxVisible)
    if offset > maxOffset then offset = maxOffset end
    if offset < 0 then offset = 0 end
    frame.scrollOffset = offset
    for slot = 1, maxVisible do
        local rowFrame = frame.rows[slot]
        if not rowFrame then break end
        local projected = rows[offset + slot]
        if projected then
            bindRow(rowFrame, projected, slot)
            rowFrame:Show()
        else
            rowFrame:Hide()
        end
    end
    if type(frame.SetHeight) == "function" then
        local shown = math.min(#rows, maxVisible)
        frame:SetHeight(frame.headerHeight + shown * ROW_HEIGHT + BOTTOM_PADDING)
    end
end

-- Clamps the scroll offset into [0, #rows - maxVisible] and rebinds the pool so
-- the offset stays legal after clear/delete/reorder/price edits change row count.
function M.scrollBy(delta)
    local frame = state.frame
    if not frame then return end
    frame.scrollOffset = (frame.scrollOffset or 0) + (delta or 0)
    M.refreshUI()
end

function M.scrollToTop()
    if state.frame then
        state.frame.scrollOffset = 0
        M.refreshUI()
    end
end

function M.scrollToBottom()
    local frame = state.frame
    if not frame then return end
    local rows = M.project()
    local maxOffset = math.max(0, #rows - (frame.maxVisible or 0))
    frame.scrollOffset = maxOffset
    M.refreshUI()
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
    if not featureEnabled() then return nil, "feature-disabled" end
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

        frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame.title:SetPoint("TOPLEFT", 10, -7)
        frame.title:SetText(L["待拍队列"])

        frame.closeButton = BG.CreateButton(frame)
        frame.closeButton:SetSize(24, 20)
        frame.closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
        frame.closeButton:SetText("×")
        frame.closeButton:SetScript("OnClick", function() frame:Hide() end)

        frame.input = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        frame.input:SetSize(150, 20)
        frame.input:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -28)
        frame.input:SetAutoFocus(false)
        frame.input:SetScript("OnEnterPressed", function(self)
            M.addFromText(self:GetText())
            self:SetText("")
        end)

        frame.addButton = BG.CreateButton(frame)
        frame.addButton:SetSize(44, 20)
        frame.addButton:SetPoint("LEFT", frame.input, "RIGHT", 4, 0)
        frame.addButton:SetText(L["添加"])
        frame.addButton:SetScript("OnClick", function()
            M.addFromText(frame.input:GetText())
            frame.input:SetText("")
        end)

        frame.clearButton = BG.CreateButton(frame)
        frame.clearButton:SetSize(44, 20)
        frame.clearButton:SetPoint("LEFT", frame.addButton, "RIGHT", 4, 0)
        frame.clearButton:SetText(L["清空"])
        frame.clearButton:SetScript("OnClick", function()
            M.clear()
            M.refreshUI()
        end)

        frame.scrollUp = BG.CreateButton(frame)
        frame.scrollUp:SetSize(20, 20)
        frame.scrollUp:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 3)
        frame.scrollUp:SetText("^")
        frame.scrollUp:SetScript("OnClick", function() M.scrollBy(-1) end)

        frame.scrollDown = BG.CreateButton(frame)
        frame.scrollDown:SetSize(20, 20)
        frame.scrollDown:SetPoint("RIGHT", frame.scrollUp, "LEFT", -2, 0)
        frame.scrollDown:SetText("v")
        frame.scrollDown:SetScript("OnClick", function() M.scrollBy(1) end)

        frame:EnableMouseWheel(true)
        frame:SetScript("OnMouseWheel", function(self, delta) M.scrollBy(-delta) end)

        frame.rows = {}
        for i = 1, MAX_ROWS do
            local row = createRow(frame)
            row:Hide()
            frame.rows[i] = row
        end
        frame.headerHeight = HEADER_HEIGHT
        frame.maxVisible = maxVisibleRows()
        frame.scrollOffset = 0
        state.frame = frame
    end
    frame:Show()
    M.refreshUI()
    return frame
end

function M.toggle()
    if not featureEnabled() then
        if state.frame then state.frame:Hide() end
        if type(BG.SendSystemMessage) == "function" then BG.SendSystemMessage(L["待拍队列已在功能管理中关闭。"] ) end
        return false, "feature-disabled"
    end
    if state.frame and state.frame:IsShown() then
        state.frame:Hide()
    else
        M.openFrame()
    end
end

local entryButton = nil
local function layoutEntry(button, mainFrame)
    if type(button.ClearAllPoints) == "function" then button:ClearAllPoints() end
    local anchor = BG.ButtonCurrentTradeRecord or BG.ButtonRoleOverview
    if anchor then
        button:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
    else
        button:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -10, 8)
    end
end

function M.installEntry(mainFrame)
    if entryButton then
        layoutEntry(entryButton, mainFrame)
        if type(entryButton.SetShown) == "function" then entryButton:SetShown(featureEnabled())
        elseif featureEnabled() then entryButton:Show() else entryButton:Hide() end
        return entryButton
    end
    if type(mainFrame) ~= "table" or type(CreateFrame) ~= "function" or type(BG.CreateButton) ~= "function" then
        return nil
    end
    local button = BG.CreateButton(mainFrame)
    button:SetSize(100, 20)
    layoutEntry(button, mainFrame)
    button:SetText(L["待拍队列"])
    button:SetScript("OnClick", function()
        if type(BG.PlaySound) == "function" then BG.PlaySound(1) end
        M.toggle()
    end)
    entryButton = button
    if not featureEnabled() then button:Hide() end
    return button
end

function M.refreshFeatureState()
    local enabled = featureEnabled()
    if entryButton then
        if type(entryButton.SetShown) == "function" then entryButton:SetShown(enabled)
        elseif enabled then entryButton:Show() else entryButton:Hide() end
    end
    if not enabled and state.frame then state.frame:Hide() end
    return enabled
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
        pendingAuctionID = state.pending and state.pending.auctionID or nil,
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
            if BG.StartAucitonFrame ~= previous then
                local frame = BG.StartAucitonFrame
                if state.pending then
                    installSecondGate(frame, state.pending)
                elseif type(frame.bgnextDirectApproval) == "table" then
                    installDirectGate(frame)
                end
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
