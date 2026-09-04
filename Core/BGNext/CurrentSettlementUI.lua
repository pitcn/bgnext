local AddonName, ns = ...
local L = ns and ns.L or setmetatable({}, {
    __index = function(_, key) return tostring(key) end,
})

BG = BG or {}
BG.BGNext = BG.BGNext or {}

-- Player-facing tables for the single current-raid settlement.
--
-- Two clearly scoped windows, built from the existing BGLite frame, scroll,
-- button, font and tooltip helpers so the handling matches the rest of the
-- addon. There is no raid selector, no player statistics page and no card
-- dashboard: one stored event is one table row, for the current raid only.
local M = {}

local ROW_HEIGHT = 20
local ROW_GAP = 2
local HEADER_HEIGHT = 22
local FILTER_HEIGHT = 24
local COLUMN_GAP = 4
local WINDOW_HEIGHT = 380
local CHECKLIST_HEIGHT = 360
local CLEAR_POPUP = "BGNextClearCurrentSettlement"
local CHECKLIST_KIND = "checklist"
local KNOWN_FILTERS = { all = true, pending = true, complete = true }

local COLUMNS = {
    trade = {
        { key = "item", label = L["物品"], width = 166, justify = "LEFT" },
        { key = "player", label = L["交易对象"], width = 110, justify = "LEFT" },
        { key = "amount", label = L["金额"], width = 80, justify = "RIGHT" },
        { key = "time", label = L["时间"], width = 80, justify = "CENTER" },
        { key = "status", label = L["状态"], width = 104, justify = "CENTER" },
    },
    mail = {
        { key = "item", label = L["物品"], width = 190, justify = "LEFT" },
        { key = "player", label = L["收件人/发件人"], width = 110, justify = "LEFT" },
        { key = "amount", label = L["金额"], width = 80, justify = "RIGHT" },
        { key = "time", label = L["时间"], width = 80, justify = "CENTER" },
        { key = "direction", label = L["方向"], width = 60, justify = "CENTER" },
        { key = "status", label = L["状态"], width = 80, justify = "CENTER" },
    },
}

local TITLES = {
    trade = "交易记录（当前团）",
    mail = "邮件记录（当前团）",
}

local EMPTY_TEXT = {
    trade = "当前团还没有交易记录。",
    mail = "当前团还没有邮件记录。",
}

local STATUS_LABELS = {
    trade = {
        complete = "已完成",
        pending = "待核对",
        failed = "失败",
        cancelled = "已取消",
    },
    mail = {
        sent = "已寄出",
        pending = "待核对",
        failed = "失败",
    },
}

local DIRECTION_LABELS = {
    outgoing = "寄出",
    incoming = "收到",
}

local function view()
    return BG.BGNext and BG.BGNext.CurrentSettlementView
end

local function checklist()
    return BG.BGNext and BG.BGNext.CurrentSettlementChecklist
end

local function lifecycle()
    return BG.BGNext and BG.BGNext.DataLifecycle
end

local function database()
    return BG.BGNext and BG.BGNext.DB
end

local function serverNow()
    if type(GetServerTime) == "function" then
        return GetServerTime()
    end
    if type(time) == "function" then
        return time()
    end
    return nil
end

function M.columns(kind)
    return COLUMNS[kind] or COLUMNS.trade
end

function M.title(kind)
    return L[TITLES[kind] or TITLES.trade]
end

function M.emptyText(kind)
    return L[EMPTY_TEXT[kind] or EMPTY_TEXT.trade]
end

function M.statusLabel(kind, status)
    local labels = STATUS_LABELS[kind] or STATUS_LABELS.trade
    local label = labels[status]
    if not label then
        return L["待核对"]
    end
    return L[label]
end

function M.statusColor(kind, status)
    local V = view()
    if V then
        return V.statusColor(kind, status)
    end
    return 0.5, 0.5, 0.5
end

function M.directionLabel(direction)
    local label = DIRECTION_LABELS[direction]
    if not label then
        return ""
    end
    return L[label]
end

-- The tooltip is driven only by the stored item id; nothing else about the row
-- is used to look an item up. A grouped trade tooltips its first identifiable
-- item (outgoing before incoming).
function M.tooltipTarget(row)
    if type(row) ~= "table" then
        return nil
    end
    if type(row.itemId) == "number" then
        return row.itemId
    end
    if type(row.myItems) == "table" and type(row.myItems[1]) == "table" then
        return row.myItems[1].itemId
    end
    if type(row.theirItems) == "table" and type(row.theirItems[1]) == "table" then
        return row.theirItems[1].itemId
    end
    return nil
end

-- Composes the gold column text for a grouped trade: an explicit 0 renders as
-- 0, an unknown side is omitted, and two-way gold is never netted. Legacy rows
-- (which carry a single stored amount) keep using their amountText instead.
function M.goldText(row)
    if type(row) ~= "table" then
        return ""
    end
    local parts = {}
    if type(row.theirGold) == "number" then
        parts[#parts + 1] = L["收到"] .. " " .. string.format("%d", row.theirGold)
    end
    if type(row.myGold) == "number" then
        parts[#parts + 1] = L["寄出"] .. " " .. string.format("%d", row.myGold)
    end
    return table.concat(parts, " / ")
end

function M.rows(root, kind, options)
    local V = view()
    if not V then
        return {}, true
    end
    if kind == "mail" then
        return V.mails(root, options)
    end
    return V.trades(root, options)
end

function M.filterRows(rows, filter)
    if filter == nil or filter == "all" then
        return rows
    end
    local filtered = {}
    for _, row in ipairs(rows or {}) do
        local matches = row.statusKey == filter
        if filter == "complete" and row.statusKey == "sent" then
            matches = true
        end
        if matches then
            filtered[#filtered + 1] = row
        end
    end
    return filtered
end

function M.setTradeStatus(root, index, status)
    local store = BG.BGNext and BG.BGNext.CurrentTrade
    if not store or type(store.setStatus) ~= "function" then
        return false
    end
    return store.setStatus(root, index, status)
end

-- Opening a page always runs the retention check first, so an expired
-- settlement is deleted rather than displayed.
function M.prepare(root, now)
    local life = lifecycle()
    if not life or type(root) ~= "table" or type(now) ~= "number" then
        return false
    end
    life.purgeExpired(root, now)
    return true
end

-- Clears the current settlement only. The bill, purchase log, wishlist,
-- equipment filters, character overview and every other setting are untouched.
function M.clear(root)
    local life = lifecycle()
    if not life or type(root) ~= "table" then
        return false
    end
    life.clearSettlement(root)
    return true
end

function M.clearConfirmText()
    return L["确认清空当前团的交易与邮件记录吗？\n只清除当前团结算记录，不影响表格账单、心愿清单和角色总览。"]
end

function M.contentWidth(kind)
    local total = 0
    for _, column in ipairs(M.columns(kind)) do
        total = total + column.width + COLUMN_GAP
    end
    return total
end

function M.scrollOuterWidth(kind)
    -- BG.CreateScrollFrame reserves 31 px for its scrollbar internally.
    return M.contentWidth(kind) + 31
end

function M.columnOffsets(kind)
    local offsets, x = {}, 0
    for index, column in ipairs(M.columns(kind)) do
        offsets[index] = x
        x = x + column.width + COLUMN_GAP
    end
    return offsets
end

function M.showItemTooltip(tooltip, itemId)
    if type(tooltip) ~= "table" or type(itemId) ~= "number" then
        return false
    end
    if type(tooltip.SetItemByID) == "function" then
        tooltip:SetItemByID(itemId)
        return true
    end
    if type(tooltip.SetHyperlink) == "function" then
        tooltip:SetHyperlink("item:" .. string.format("%d", itemId))
        return true
    end
    return false
end

local function itemDisplay(itemId)
    if type(itemId) ~= "number" then
        return "", nil
    end
    local text, texture
    if type(GetItemInfo) == "function" then
        local name, link = GetItemInfo(itemId)
        text = link or name
        texture = select(10, GetItemInfo(itemId))
    end
    if not texture and type(GetItemInfoInstant) == "function" then
        texture = select(5, GetItemInfoInstant(itemId))
    end
    return text or ("item:" .. string.format("%d", itemId)), texture
end

-- A compact count suffix for one delivered item row. Only a positive whole
-- quantity is shown, so a legacy record with no quantity (or a stack of
-- unknown size) stays silent instead of inventing "×1".
function M.quantityText(quantity)
    if type(quantity) ~= "number" or quantity < 1 or quantity % 1 ~= 0 then
        return ""
    end
    return "×" .. string.format("%d", quantity)
end

-- Trade facts and reconciliation state are two independent dimensions. A
-- grouped trade that actually completed (completedKey = true) is labelled with
-- the trade fact "已交易" in front of its reconciliation state, so a completed
-- trade that is still pending shows both instead of only "待核对". Legacy rows
-- never fabricate the trade fact and show only the reconciliation state.
function M.statusText(kind, statusKey, completedKey)
    local label = M.statusLabel(kind, statusKey)
    if kind == "trade" and completedKey == true then
        return L["已交易"] .. " · " .. label
    end
    return label
end

-- The status tooltip explains the two independent dimensions (the trade fact
-- and the reconciliation state) so a clipped narrow column never hides which
-- fact is which, then repeats the toggle hint.
function M.statusTooltipLines(kind, statusKey, completedKey)
    local lines = {}
    if kind == "trade" and completedKey == true then
        lines[#lines + 1] = { text = L["交易已完成"], r = 0, g = 1, b = 0 }
    end
    local r, g, b = M.statusColor(kind, statusKey)
    lines[#lines + 1] = {
        text = L["核对状态"] .. "：" .. M.statusLabel(kind, statusKey),
        r = r, g = g, b = b,
    }
    lines[#lines + 1] = { text = L["左键切换待核对/已完成"], r = 1, g = 0.82, b = 0 }
    return lines
end

-- Every delivered item in a row, in display order: a legacy row contributes its
-- single stored item, a grouped trade contributes each outgoing item then each
-- incoming item. The item tooltip iterates these so a grouped row never points
-- only at its first item.
function M.itemEntries(row)
    local entries = {}
    if type(row) ~= "table" then
        return entries
    end
    if type(row.itemId) == "number" then
        entries[#entries + 1] = { itemId = row.itemId, quantity = row.quantity }
        return entries
    end
    if type(row.myItems) == "table" then
        for _, item in ipairs(row.myItems) do
            entries[#entries + 1] = { itemId = item.itemId, quantity = item.quantity, direction = "outgoing" }
        end
    end
    if type(row.theirItems) == "table" then
        for _, item in ipairs(row.theirItems) do
            entries[#entries + 1] = { itemId = item.itemId, quantity = item.quantity, direction = "incoming" }
        end
    end
    return entries
end

-- A human-readable line per delivered item, used when a grouped row packs
-- several items into one cell. Each line keeps its direction and count so the
-- player can inspect every item rather than only the first.
function M.itemTooltipLines(row)
    local lines = {}
    for _, entry in ipairs(M.itemEntries(row)) do
        if type(entry.itemId) == "number" then
            local prefix = ""
            if entry.direction == "outgoing" then
                prefix = L["寄出"] .. " "
            elseif entry.direction == "incoming" then
                prefix = L["收到"] .. " "
            end
            lines[#lines + 1] = prefix .. itemDisplay(entry.itemId) .. M.quantityText(entry.quantity)
        end
    end
    return lines
end

------------------------------------------------------------------------
-- Rendering. Nothing below runs outside the game.
------------------------------------------------------------------------

local windows = {}
local entryButtons

function M.checklistTitle()
    return L["结算前检查（当前团）"]
end

function M.checklistEntryLabel()
    return L["结算前检查"]
end

local CHECKLIST_STATUS_LABELS = {
    ready = "可以结算",
    issues = "发现异常",
    pending = "待确认",
}

function M.checklistStatusLabel(status)
    return L[CHECKLIST_STATUS_LABELS[status] or CHECKLIST_STATUS_LABELS.pending]
end

-- Gathers the evaluate input from live data. Only this runtime section reads
-- the addon globals; the checklist derivation itself stays injectable.
local function checklistFb()
    local root = database()
    local settlement = root and root.currentSettlement
    return settlement and settlement.sourceFb or BG.FB1
end

local function checklistOptions(now)
    local root = database()
    local fb = checklistFb()
    return {
        db = root,
        fb = fb,
        now = now,
        table = type(BiaoGe) == "table" and BiaoGe[fb] or nil,
        bosses = ns and ns.Maxb and ns.Maxb[fb] or nil,
        slotsOf = BG.GetMaxi,
        itemIdOf = ns and ns.GetItemID or nil,
        moLing = type(BiaoGe) == "table" and type(BiaoGe.options) == "table"
            and BiaoGe.options.moLing == 1 or false,
        normalizeName = BG.GSN,
    }
end

local CATEGORY_ORDER = { "settlement", "trade", "sold", "debt", "bill", "summary", "mail" }
local CATEGORY_LABELS = {
    settlement = "结算状态",
    trade = "未核对交易",
    sold = "销售交付核对",
    debt = "未处理欠款",
    bill = "账单完整性",
    summary = "分金与工资",
    mail = "邮件核对",
}

local function categoryLabel(category)
    return L[CATEGORY_LABELS[category] or category]
end

local function acquireChecklistRow(win, index)
    local row = win.rowPool[index]
    if row then
        return row
    end
    row = CreateFrame("Frame", nil, win.child)
    row:SetSize(win.contentWidth, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * (ROW_HEIGHT + ROW_GAP))
    row.text = row:CreateFontString()
    row.text:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    row.text:SetPoint("LEFT", 2, 0)
    row.text:SetWidth(win.contentWidth - 76)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.locateButton = BG.CreateButton(row)
    row.locateButton:SetSize(64, 18)
    row.locateButton:SetPoint("RIGHT", 0, 0)
    row.locateButton:SetText(L["定位"])
    win.rowPool[index] = row
    return row
end

local function configureHeaderRow(row, category)
    row.isHeader = true
    row.entry = nil
    row.fullReason = nil
    row.text:SetText(categoryLabel(category))
    row.text:SetTextColor(0, 0.75, 1)
    row.text:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
    if row.locateButton then
        row.locateButton:SetScript("OnClick", nil)
        row.locateButton:Hide()
    end
    row:Show()
end

local function configureEntryRow(row, entryData)
    row.isHeader = false
    row.entry = entryData
    local text = L[entryData.reasonKey]
    if #(entryData.args or {}) > 0 then
        text = string.format(text, unpack(entryData.args))
    end
    row.fullReason = text
    row.text:SetText(text)
    row.text:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    if entryData.severity == "issue" then
        row.text:SetTextColor(1, 0.35, 0.35)
    else
        row.text:SetTextColor(1, 0.82, 0)
    end
    -- The row keeps to one line; the tooltip carries the full reason so long
    -- English text is never lost to clipping.
    row:SetScript("OnEnter", function(self)
        if type(GameTooltip) ~= "table" then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 0, 0)
        GameTooltip:ClearLines()
        GameTooltip:AddLine(self.fullReason or "", 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        if type(GameTooltip) == "table" and GameTooltip.Hide then
            GameTooltip:Hide()
        end
    end)
    local C = checklist()
    local target = C and C.resolveLocate and C.resolveLocate(entryData.locate, BG.FB1) or nil
    if target then
        row.locateButton:SetScript("OnClick", function()
            if BG.PlaySound then BG.PlaySound(1) end
            if target.window then
                M.Show(target.window, target.filter)
            elseif target.table and type(BG.ClickFBbutton) == "function" then
                BG.ClickFBbutton(target.table)
            end
        end)
        row.locateButton:Show()
    else
        row.locateButton:SetScript("OnClick", nil)
        row.locateButton:Hide()
    end
end

local function renderChecklist(win, report)
    win.statusText:SetText(M.checklistStatusLabel(report.status))
    local r, g, b = 0.5, 0.5, 0.5
    local C = checklist()
    if C and type(C.statusColor) == "function" then
        r, g, b = C.statusColor(report.status)
    end
    win.statusText:SetTextColor(r, g, b)
    win.totalText:SetText(string.format(L["共 %s 项"], tostring(report.total)))
    for _, row in ipairs(win.rowPool) do
        row:Hide()
    end

    -- One row per entry, grouped under a category header row.
    local display = {}
    for _, category in ipairs(CATEGORY_ORDER) do
        local groupStarted
        for _, entryData in ipairs(report.entries) do
            if entryData.category == category then
                if not groupStarted then
                    groupStarted = true
                    display[#display + 1] = { header = true, category = category }
                end
                display[#display + 1] = { entry = entryData }
            end
        end
    end
    win.checklistRows = {}
    for index, item in ipairs(display) do
        local row = acquireChecklistRow(win, index)
        if item.header then
            configureHeaderRow(row, item.category)
        else
            configureEntryRow(row, item.entry)
        end
        row:Show()
        win.checklistRows[#win.checklistRows + 1] = row
    end
    -- Surplus pooled rows lose their derived references immediately.
    for index = #display + 1, #win.rowPool do
        local row = win.rowPool[index]
        row.isHeader = nil
        row.entry = nil
        row.fullReason = nil
        row.text:SetText("")
        if row.locateButton then
            row.locateButton:SetScript("OnClick", nil)
            row.locateButton:Hide()
        end
        row:Hide()
    end
    win.child:SetHeight(math.max(#display * (ROW_HEIGHT + ROW_GAP), win.scrollHeight))
end

-- Forward declarations: the refresh funnel and the hook/expiry maintenance
-- helpers reference each other, so they are declared up front and assigned
-- below.
local refreshChecklist, requestChecklistRefresh
local hookBillFrames, hookDebtEditBox, armExpiryInvalidation

-- Recomputes only while the checklist window is visible; any record or window
-- refresh funnels through here, so no timer or hidden-page scanning is needed.
refreshChecklist = function()
    local win = windows[CHECKLIST_KIND]
    if not win or not win.frame:IsShown() then
        return
    end
    local C = checklist()
    if not C or type(C.report) ~= "function" then
        return
    end
    local root = database()
    local now = serverNow()
    M.prepare(root, now)
    -- Hook the current scope's edit frames once; a scope change re-hooks.
    local fb = checklistFb()
    if fb ~= win.hookedFb then
        hookBillFrames(fb)
        win.hookedFb = fb
    end
    hookDebtEditBox()
    local report = C.report(checklistOptions(now))
    win.report = report
    renderChecklist(win, report)
    armExpiryInvalidation(win, root, now)
end

-- Bursts of record updates coalesce into one recompute on the next frame.
local checklistScheduled = false
local function processChecklistRefresh()
    checklistScheduled = false
    refreshChecklist()
end

-- The checklist is recomputed only while it is shown: hidden windows do no
-- work, and bill-edit hooks that fire while it is closed are dropped here.
requestChecklistRefresh = function()
    local win = windows[CHECKLIST_KIND]
    if not win or not win.frame:IsShown() then
        return
    end
    if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
        if checklistScheduled then
            return
        end
        checklistScheduled = true
        C_Timer.After(0, processChecklistRefresh)
    else
        processChecklistRefresh()
    end
end

-- Bill edits (item, buyer, amount, debt, summary) live in baseline inline
-- scripts that cannot be replaced, but every frame can be subscribed without
-- touching its handler: one HookScript per edit frame, installed once per
-- frame when the checklist window first reaches that scope. The hooks only
-- fire a cheap, visibility-guarded refresh request -- no polling, no
-- hidden-page work.
hookBillFrames = function(fb)
    if type(BG.Frame) ~= "table" or type(BG.Frame[fb]) ~= "table" then
        return
    end
    local maxb = ns and ns.Maxb and ns.Maxb[fb] or 0
    for boss = 1, maxb + 2 do
        local bossData = BG.Frame[fb]["boss" .. boss]
        if type(bossData) == "table" then
            local slots = 0
            if type(BG.GetMaxi) == "function" then
                local ok, value = pcall(BG.GetMaxi, fb, boss)
                if ok and type(value) == "number" then
                    slots = value
                end
            end
            for slot = 1, slots do
                for _, field in ipairs({ "zhuangbei", "maijia", "jine" }) do
                    local box = bossData[field .. slot]
                    if type(box) == "table" and not box.__bgnChecklistNotify
                        and type(box.HookScript) == "function" then
                        box.__bgnChecklistNotify = true
                        box:HookScript("OnTextChanged", requestChecklistRefresh)
                    end
                end
                local debtButton = bossData["qiankuan" .. slot]
                if type(debtButton) == "table" and not debtButton.__bgnChecklistNotify
                    and type(debtButton.HookScript) == "function" then
                    debtButton.__bgnChecklistNotify = true
                    debtButton:HookScript("OnShow", requestChecklistRefresh)
                    debtButton:HookScript("OnHide", requestChecklistRefresh)
                end
            end
        end
    end
end

-- The debt amount is edited in a shared popup box that BGLite recreates each
-- time the popup opens, so a debt indicator that stays visible while its
-- amount changes emits no OnShow/OnHide. Hook whatever box is current; the
-- flag dies with the old box. Subscribe after the popup factory runs too:
-- editing an already-visible debt need not produce any other refresh event.
local debtFactoryHooked = false
hookDebtEditBox = function()
    if not debtFactoryHooked and type(BG.SetListjine) == "function"
        and type(hooksecurefunc) == "function" then
        debtFactoryHooked = true
        hooksecurefunc(BG, "SetListjine", hookDebtEditBox)
    end
    local edit = BG.FrameQianKuanEdit
    if type(edit) ~= "table" or edit.__bgnChecklistNotify
        or type(edit.HookScript) ~= "function" then
        return
    end
    edit.__bgnChecklistNotify = true
    edit:HookScript("OnTextChanged", requestChecklistRefresh)
end

-- Expiry is handled by one cancellable, scope-bound one-shot timer armed for
-- the current settlement's deadline; it re-arms for a replaced scope and is
-- cancelled on hide. No repeating scan ever runs.
armExpiryInvalidation = function(win, root, now)
    local settlement = root and root.currentSettlement
    local deadline = settlement and type(settlement.expiresAt) == "number"
        and settlement.expiresAt or nil
    -- Re-arming is idempotent per deadline: edits that keep the same scope do
    -- not cancel and recreate the timer on every keystroke.
    if deadline == win.expiryDeadline and win.expiryTimer then
        return
    end
    if win.expiryTimer then
        if type(win.expiryTimer.Cancel) == "function" then
            win.expiryTimer:Cancel()
        end
        win.expiryTimer = nil
    end
    win.expiryDeadline = deadline
    if not deadline or type(C_Timer) ~= "table" or type(C_Timer.NewTimer) ~= "function" then
        return
    end
    local remaining = deadline - now
    if remaining <= 0 then
        return
    end
    win.expiryTimer = C_Timer.NewTimer(remaining + 1, function()
        win.expiryTimer = nil
        win.expiryDeadline = nil
        if not win.frame:IsShown() then
            return
        end
        M.prepare(database(), serverNow())
        requestChecklistRefresh()
        armExpiryInvalidation(win, database(), serverNow())
    end)
end

-- Frames stay pooled for reuse, but every derived reference (entry, reason
-- text, locate closure) is dropped with the window or the scope.
local function releaseChecklistRows(win)
    win.report = nil
    win.checklistRows = nil
    for _, row in ipairs(win.rowPool) do
        row.isHeader = nil
        row.entry = nil
        row.fullReason = nil
        row.text:SetText("")
        row.text:SetTextColor(0.8, 0.8, 0.8)
        if row.locateButton then
            row.locateButton:SetScript("OnClick", nil)
            row.locateButton:Hide()
        end
        row:Hide()
    end
end

local function createChecklistWindow()
    if type(CreateFrame) ~= "function" or type(BG.CreateMainFrame) ~= "function"
        or type(BG.CreateScrollFrame) ~= "function" or type(BG.CreateButton) ~= "function" then
        return nil
    end
    local width = 560
    local frame = BG.CreateMainFrame()
    frame:SetSize(width, CHECKLIST_HEIGHT)
    frame:SetPoint("CENTER")
    frame:Hide()
    if frame.titleText then
        frame.titleText:SetText(M.checklistTitle())
    end
    local win = {
        kind = CHECKLIST_KIND,
        frame = frame,
        contentWidth = width - 32,
        rowPool = {},
    }

    win.statusText = frame:CreateFontString()
    win.statusText:SetFont(BIAOGE_TEXT_FONT, 16, "OUTLINE")
    win.statusText:SetPoint("TOPLEFT", 16, -30)
    win.totalText = frame:CreateFontString()
    win.totalText:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
    win.totalText:SetPoint("TOPRIGHT", -16, -32)
    win.totalText:SetTextColor(0.7, 0.7, 0.7)

    local scrollHeight = CHECKLIST_HEIGHT - 58 - 46
    local scroll, child = BG.CreateScrollFrame(frame, width - 30, scrollHeight)
    scroll:SetPoint("TOPLEFT", 15, -(30 + 28))
    win.scroll, win.child, win.scrollHeight = scroll, child, scrollHeight

    local hint = frame:CreateFontString()
    hint:SetFont(BIAOGE_TEXT_FONT, 11, "OUTLINE")
    hint:SetPoint("BOTTOMLEFT", 14, 14)
    hint:SetWidth(width - 28)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(true)
    hint:SetTextColor(0.6, 0.6, 0.6)
    hint:SetText(L["只读检查：不会自动修改账目、发送邮件或执行结算。"])

    frame:SetScript("OnShow", function()
        M.Refresh(CHECKLIST_KIND)
    end)
    -- The derived report, rendered rows, locate closures and the one-shot
    -- expiry timer are dropped with the window; nothing survives a close, a
    -- manual clear or a scope switch.
    frame:SetScript("OnHide", function()
        if win.expiryTimer then
            if type(win.expiryTimer.Cancel) == "function" then
                win.expiryTimer:Cancel()
            end
            win.expiryTimer = nil
        end
        win.expiryDeadline = nil
        releaseChecklistRows(win)
    end)

    windows[CHECKLIST_KIND] = win
    return win
end

local function newCell(row, column, offset)
    local cell = CreateFrame("Frame", nil, row)
    cell:SetSize(column.width, ROW_HEIGHT)
    cell:SetPoint("LEFT", offset, 0)
    cell.text = cell:CreateFontString()
    cell.text:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
    cell.text:SetAllPoints()
    cell.text:SetJustifyH(column.justify)
    cell.text:SetWordWrap(false)
    return cell
end

local function acquireRow(win, index)
    local row = win.rowPool[index]
    if row then
        return row
    end
    row = CreateFrame("Frame", nil, win.child)
    row:SetSize(win.contentWidth, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * (ROW_HEIGHT + ROW_GAP))
    row:EnableMouse(true)

    row.stripe = row:CreateTexture()
    row.stripe:SetAllPoints()
    row.stripe:SetColorTexture(0.5, 0.5, 0.5, 0.3)
    row.stripe:Hide()
    row:SetScript("OnEnter", function(self) self.stripe:Show() end)
    row:SetScript("OnLeave", function(self) self.stripe:Hide() end)

    row.cells = {}
    local offsets = win.offsets
    for position, column in ipairs(M.columns(win.kind)) do
        row.cells[column.key] = newCell(row, column, offsets[position])
    end

    local itemCell = row.cells.item
    if itemCell then
        itemCell:EnableMouse(true)
        itemCell.icon = itemCell:CreateTexture()
        itemCell.icon:SetSize(16, 16)
        itemCell.icon:SetPoint("LEFT", 0, 0)
        itemCell.text:ClearAllPoints()
        itemCell.text:SetPoint("LEFT", itemCell.icon, "RIGHT", 2, 0)
        itemCell.text:SetPoint("RIGHT", 0, 0)
        itemCell:SetScript("OnEnter", function(self)
            row.stripe:Show()
            if type(GameTooltip) ~= "table" then
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 0, 0)
            GameTooltip:ClearLines()
            local entries = M.itemEntries(row.data)
            if #entries == 1 then
                M.showItemTooltip(GameTooltip, entries[1].itemId)
            elseif #entries > 1 then
                for _, line in ipairs(M.itemTooltipLines(row.data)) do
                    GameTooltip:AddLine(line, 1, 1, 1, true)
                end
            end
            GameTooltip:Show()
        end)
        itemCell:SetScript("OnLeave", function()
            row.stripe:Hide()
            if type(GameTooltip) == "table" and GameTooltip.Hide then
                GameTooltip:Hide()
            end
        end)
    end


    local statusCell = row.cells.status
    if statusCell and win.kind == "trade" then
        statusCell:EnableMouse(true)
        statusCell:SetScript("OnMouseUp", function(_, mouseButton)
            if mouseButton ~= "LeftButton" or not row.data then
                return
            end
            local nextStatus = row.data.statusKey == "pending" and "complete" or "pending"
            if M.setTradeStatus(database(), row.data.index, nextStatus) then
                M.Refresh("trade")
            end
        end)
        statusCell:SetScript("OnEnter", function(self)
            row.stripe:Show()
            if type(GameTooltip) ~= "table" then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT", 0, 0)
            GameTooltip:ClearLines()
            local lines = M.statusTooltipLines(win.kind, row.data and row.data.statusKey, row.data and row.data.completedKey)
            for _, line in ipairs(lines) do
                GameTooltip:AddLine(line.text, line.r or 1, line.g or 1, line.b or 1, true)
            end
            GameTooltip:Show()
        end)
        statusCell:SetScript("OnLeave", function()
            row.stripe:Hide()
            if type(GameTooltip) == "table" and GameTooltip.Hide then GameTooltip:Hide() end
        end)
    end

    win.rowPool[index] = row
    return row
end

-- Builds the item column for one row. Legacy rows show their single stored
-- item; grouped trades list both delivery directions, each item with its count.
local function itemCellText(data)
    if type(data) ~= "table" then
        return "", nil
    end
    if type(data.itemId) == "number" then
        local text, texture = itemDisplay(data.itemId)
        return text .. M.quantityText(data.quantity), texture
    end
    local parts = {}
    local texture
    if type(data.myItems) == "table" then
        for _, entry in ipairs(data.myItems) do
            local text, tex = itemDisplay(entry.itemId)
            if not texture then texture = tex end
            parts[#parts + 1] = L["寄出"] .. " " .. text .. M.quantityText(entry.quantity)
        end
    end
    if type(data.theirItems) == "table" then
        for _, entry in ipairs(data.theirItems) do
            local text, tex = itemDisplay(entry.itemId)
            if not texture then texture = tex end
            parts[#parts + 1] = L["收到"] .. " " .. text .. M.quantityText(entry.quantity)
        end
    end
    return table.concat(parts, " / "), texture
end

local function fillRow(win, row, data)
    row.data = data
    local cells = row.cells

    local itemCell = cells.item
    if itemCell then
        local text, texture = itemCellText(data)
        itemCell.text:SetText(text)
        itemCell.icon:SetTexture(texture)
        itemCell.icon:SetShown(texture ~= nil)
    end
    if cells.player then
        cells.player.text:SetText(data.player or "")
        cells.player.text:SetTextColor(1, 0.82, 0)
    end
    if cells.amount then
        local text = data.amountText or ""
        if type(data.myGold) == "number" or type(data.theirGold) == "number" then
            text = M.goldText(data)
        end
        cells.amount.text:SetText(text)
        cells.amount.text:SetTextColor(1, 0.82, 0)
    end
    if cells.time then
        cells.time.text:SetText(data.timeText or "")
        cells.time.text:SetTextColor(0.8, 0.8, 0.8)
    end
    if cells.direction then
        cells.direction.text:SetText(M.directionLabel(data.directionKey))
        cells.direction.text:SetTextColor(0.8, 0.8, 0.8)
    end
    if cells.status then
        cells.status.text:SetText(M.statusText(win.kind, data.statusKey, data.completedKey))
        cells.status.text:SetTextColor(M.statusColor(win.kind, data.statusKey))
    end
    row:Show()
end

function M.Refresh(kind)
    -- Any record or window refresh also updates a visible checklist; bursts
    -- coalesce into one recompute via the deferred refresh request.
    requestChecklistRefresh()
    if kind == CHECKLIST_KIND then
        return
    end
    local win = windows[kind]
    if not win or not win.frame:IsShown() then
        return
    end
    local root = database()
    local now = serverNow()
    M.prepare(root, now)
    local rows = M.rows(root, kind, { now = now })
    rows = M.filterRows(rows, win.filter)
    local isEmpty = #rows == 0

    for _, row in ipairs(win.rowPool) do
        row:Hide()
    end
    for index, data in ipairs(rows) do
        fillRow(win, acquireRow(win, index), data)
    end
    win.child:SetHeight(math.max(#rows * (ROW_HEIGHT + ROW_GAP), win.scrollHeight))
    win.emptyText:SetShown(isEmpty and true or false)
end

local function createWindow(kind)
    if type(CreateFrame) ~= "function" or type(BG.CreateMainFrame) ~= "function"
        or type(BG.CreateScrollFrame) ~= "function" then
        return nil
    end

    local contentWidth = M.contentWidth(kind)
    local frame = BG.CreateMainFrame()
    frame:SetSize(contentWidth + 48, WINDOW_HEIGHT)
    frame:SetPoint("CENTER")
    frame:Hide()
    if frame.titleText then
        frame.titleText:SetText(M.title(kind))
    end

    local win = {
        kind = kind,
        frame = frame,
        contentWidth = contentWidth,
        offsets = M.columnOffsets(kind),
        rowPool = {},
    }

    win.filter = "all"
    win.filterButtons = {}
    local previousFilter
    local function bindFilter(button, key)
        button:SetScript("OnClick", function()
            win.filter = key
            M.Refresh(kind)
        end)
    end
    for _, option in ipairs({
        { key = "all", label = "全部" },
        { key = "pending", label = "待核对" },
        { key = "complete", label = "已完成" },
    }) do
        local button = BG.CreateButton(frame)
        button:SetSize(70, 20)
        if previousFilter then
            button:SetPoint("LEFT", previousFilter, "RIGHT", 4, 0)
        else
            button:SetPoint("TOPLEFT", 14, -28)
        end
        button:SetText(L[option.label])
        bindFilter(button, option.key)
        win.filterButtons[option.key] = button
        previousFilter = button
    end

    -- Column headers
    local header = CreateFrame("Frame", nil, frame)
    header:SetSize(contentWidth, HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", 15, -(28 + FILTER_HEIGHT))
    for position, column in ipairs(M.columns(kind)) do
        local text = header:CreateFontString()
        text:SetFont(BIAOGE_TEXT_FONT, 13, "OUTLINE")
        text:SetSize(column.width, HEADER_HEIGHT)
        text:SetPoint("LEFT", win.offsets[position], 0)
        text:SetJustifyH(column.justify)
        text:SetTextColor(0, 0.75, 1)
        text:SetText(column.label)
    end

    local scrollHeight = WINDOW_HEIGHT - 28 - FILTER_HEIGHT - HEADER_HEIGHT - 46
    local scroll, child = BG.CreateScrollFrame(frame, M.scrollOuterWidth(kind), scrollHeight)
    scroll:SetPoint("TOPLEFT", 12, -(28 + FILTER_HEIGHT + HEADER_HEIGHT))
    win.scroll = scroll
    win.child = child
    win.scrollHeight = scrollHeight

    local empty = child:CreateFontString()
    empty:SetFont(BIAOGE_TEXT_FONT, 14, "OUTLINE")
    empty:SetPoint("TOP", 0, -12)
    empty:SetTextColor(0.7, 0.7, 0.7)
    empty:SetText(M.emptyText(kind))
    empty:Hide()
    win.emptyText = empty

    local clearButton = BG.CreateButton(frame)
    clearButton:SetSize(150, 22)
    clearButton:SetPoint("BOTTOMRIGHT", -12, 10)
    clearButton:SetText(L["清空当前团记录"])
    clearButton:SetScript("OnClick", function()
        if BG.PlaySound then BG.PlaySound(1) end
        M.ensureClearPopup()
        if type(StaticPopup_Show) == "function" then
            StaticPopup_Show(CLEAR_POPUP)
        end
    end)
    clearButton:SetScript("OnEnter", function(self)
        if type(GameTooltip) ~= "table" then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["清空当前团记录"], 1, 1, 1, true)
        GameTooltip:AddLine(M.clearConfirmText(), 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    clearButton:SetScript("OnLeave", function()
        if type(GameTooltip) == "table" and GameTooltip.Hide then GameTooltip:Hide() end
    end)
    win.clearButton = clearButton

    local scopeText = frame:CreateFontString()
    scopeText:SetFont(BIAOGE_TEXT_FONT, 12, "OUTLINE")
    scopeText:SetPoint("BOTTOMLEFT", 14, 14)
    scopeText:SetTextColor(0.6, 0.6, 0.6)
    scopeText:SetText(L["只保留当前或最近一次未结算团本，最长七日。"])

    frame:SetScript("OnShow", function() M.Refresh(kind) end)

    windows[kind] = win
    return win
end

function M.ensureClearPopup()
    if type(StaticPopupDialogs) ~= "table" then
        return false
    end
    if StaticPopupDialogs[CLEAR_POPUP] then
        return true
    end
    StaticPopupDialogs[CLEAR_POPUP] = {
        text = M.clearConfirmText(),
        button1 = L["是"],
        button2 = L["否"],
        OnAccept = function()
            if not M.clear(database()) then
                return
            end
            if BG.SendSystemMessage then
                BG.SendSystemMessage(L["已清空当前团的交易与邮件记录。"])
            end
            M.Refresh("trade")
            M.Refresh("mail")
        end,
        OnCancel = function() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        showAlert = true,
    }
    return true
end

local function ensureWindow(kind)
    local win = windows[kind]
    if win then
        return win
    end
    if kind == CHECKLIST_KIND then
        return createChecklistWindow()
    end
    return createWindow(kind)
end

function M.Show(kind, filter)
    local win = ensureWindow(kind)
    if not win then
        return false
    end
    if filter ~= nil and win.filter ~= nil and KNOWN_FILTERS[filter] then
        win.filter = filter
    end
    -- Show only fires OnShow on a visibility transition. An already visible
    -- window still needs to render changes to its requested filter.
    if win.frame:IsShown() then
        M.Refresh(kind)
    else
        win.frame:Show()
    end
    return true
end

function M.Toggle(kind)
    local win = ensureWindow(kind)
    if not win then
        return false
    end
    if win.frame:IsShown() then
        win.frame:Hide()
    else
        M.Show(kind)
    end
    return true
end

-- Test/support accessors: the checklist window state and its rendered rows
-- (with locate buttons) so harnesses can verify refresh, cleanup and locate
-- wiring without reaching into file locals.
function M.checklistState()
    local win = windows[CHECKLIST_KIND]
    if not win then
        return { shown = false, report = nil, rows = {}, pooledRows = {} }
    end
    return {
        shown = win.frame:IsShown() and true or false,
        report = win.report,
        rows = win.checklistRows or {},
        pooledRows = win.rowPool,
    }
end

function M.windowState(kind)
    local win = windows[kind]
    if not win then
        return { shown = false, filter = nil }
    end
    return { shown = win.frame:IsShown() and true or false, filter = win.filter }
end

-- Entry buttons on the main window, next to the character overview entry so the
-- familiar bottom-right control row keeps its habit.
function M.installEntry(mainFrame)
    if entryButtons then
        return entryButtons
    end
    if not mainFrame or type(CreateFrame) ~= "function" or type(BG.CreateButton) ~= "function" then
        return nil
    end

    local created = {}
    local previous
    -- Built right to left so the visible order is 交易记录, 邮件记录, 结算前检查.
    for _, kind in ipairs({ CHECKLIST_KIND, "mail", "trade" }) do
        local button = BG.CreateButton(mainFrame)
        button:SetSize(120, 20)
        if previous then
            button:SetPoint("RIGHT", previous, "LEFT", -4, 0)
        elseif BG.ButtonRoleOverview then
            button:SetPoint("RIGHT", BG.ButtonRoleOverview, "LEFT", -8, 0)
        else
            button:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -10, 8)
        end
        button:SetText(kind == CHECKLIST_KIND and M.checklistEntryLabel() or M.title(kind))
        local fontString = button.GetFontString and button:GetFontString()
        if fontString then
            button:SetWidth(math.max(100, fontString:GetStringWidth() + 16))
        end
        button:SetScript("OnClick", function()
            if BG.PlaySound then BG.PlaySound(1) end
            M.Toggle(kind)
        end)
        previous = button
        created[kind] = button
    end

    BG.ButtonCurrentTradeRecord = created.trade
    BG.ButtonCurrentMailRecord = created.mail
    BG.ButtonSettlementChecklist = created.checklist
    entryButtons = created
    return created
end

BG.BGNext.CurrentSettlementUI = M
return M
