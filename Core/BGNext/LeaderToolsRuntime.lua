local _, ns = ...

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local M = {}
local L = ns and ns.L or setmetatable({}, { __index = function(_, key) return tostring(key) end })
local Store = assert(BG.BGNext.LeaderToolsStore, "LeaderToolsStore must load first")
local View = assert(BG.BGNext.LeaderToolsView, "LeaderToolsView must load first")
local Maxb = ns and ns.Maxb or {}

local function isObject(value)
    return type(value) == "table" or type(value) == "userdata"
end

local function text(widget, fallback)
    if widget and type(widget.GetText) == "function" then
        local ok, value = pcall(widget.GetText, widget)
        if ok then return value end
    end
    return fallback
end

local function featureEnabled(id)
    local settings = BG.BGNext.FeatureSettings
    return not settings or type(settings.isCurrentEnabled) ~= "function"
        or settings.isCurrentEnabled(id, BG, BG.BGNext.DB)
end

local function safeCall(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end

function M.collectExpenseRows(options)
    options = options or {}
    local tableData, frames = options.table or {}, options.frames or {}
    local boss, slots = tonumber(options.expenseBoss), tonumber(options.slots) or 0
    local saved, visible = tableData["boss" .. tostring(boss)] or {}, frames["boss" .. tostring(boss)] or {}
    local rows = {}
    for index = 1, slots do
        rows[index] = {
            name = text(visible["zhuangbei" .. index], saved["zhuangbei" .. index]),
            amount = text(visible["jine" .. index], saved["jine" .. index]),
        }
    end
    return rows
end

function M.applyExpenseTemplate(options, template)
    options = options or {}
    local rows = M.collectExpenseRows(options)
    local plan, reason = Store.planExpenseApply(template, rows)
    if not plan then return false, reason end
    local tableData, frames = options.table or {}, options.frames or {}
    local boss = tonumber(options.expenseBoss)
    local saved, visible = tableData["boss" .. tostring(boss)], frames["boss" .. tostring(boss)]
    if type(saved) ~= "table" then return false, "missing-table" end
    -- Re-check immediately before committing so a row edited while the
    -- confirmation was open is never overwritten.
    local fresh = M.collectExpenseRows(options)
    local freshPlan, freshReason = Store.planExpenseApply(template, fresh)
    if not freshPlan then return false, freshReason end
    for _, entry in ipairs(freshPlan) do
        local index = entry.row
        saved["zhuangbei" .. index] = entry.name
        saved["jine" .. index] = tostring(entry.amount)
        if type(visible) == "table" then
            local nameWidget, amountWidget = visible["zhuangbei" .. index], visible["jine" .. index]
            if nameWidget and type(nameWidget.SetText) == "function" then nameWidget:SetText(entry.name) end
            if amountWidget and type(amountWidget.SetText) == "function" then amountWidget:SetText(tostring(entry.amount)) end
        end
    end
    return true, freshPlan
end

function M.captureHistory(options)
    options = options or {}
    if options.enabled ~= true then return 0 end
    local root, tableData = options.root, options.table
    local bosses, count = tonumber(options.bosses) or 0, 0
    if type(root) ~= "table" or type(tableData) ~= "table" then return 0 end
    for boss = 1, bosses do
        local row = tableData["boss" .. boss]
        local slots = tonumber(safeCall(options.slotsOf, options.fb, boss)) or 0
        for slot = 1, slots or 0 do
            local item, buyer, value = row and row["zhuangbei" .. slot], row and row["maijia" .. slot], row and row["jine" .. slot]
            local itemId = safeCall(options.itemIdOf, item)
            local mine = safeCall(options.isMine, buyer) == true
            if type(itemId) == "number" and type(buyer) == "string" and buyer:find("%S") and tonumber(value) then
                local stored = Store.appendHistory(root, {
                    itemId = itemId, amount = tonumber(value), sourceFb = options.fb,
                    -- Keep two identical rows in the same bill distinct while
                    -- making a repeated save in the same second idempotent.
                    time = options.now + (boss * 100 + slot) / 100000, mine = mine,
                }, true, options.now)
                if stored then count = count + 1 end
            end
        end
    end
    return count
end

function M.collectBill(options)
    options = options or {}
    local tableData, fb, bosses = options.table or {}, options.fb, tonumber(options.bosses) or 0
    local bill = { rows = {}, expenses = {}, splitCount = nil }
    for boss = 1, bosses do
        local row = tableData["boss" .. boss] or {}
        local slots = tonumber(safeCall(options.slotsOf, fb, boss)) or 0
        for slot = 1, slots or 0 do
            bill.rows[#bill.rows + 1] = {
                itemId = safeCall(options.itemIdOf, row["zhuangbei" .. slot]),
                item = tostring(row["zhuangbei" .. slot] or ""),
                buyer = tostring(row["maijia" .. slot] or ""),
                amount = row["jine" .. slot],
                debt = row["qiankuan" .. slot],
            }
        end
    end
    local expense = tableData["boss" .. (bosses + 1)] or {}
    local expenseSlots = tonumber(safeCall(options.slotsOf, fb, bosses + 1)) or 0
    for slot = 1, expenseSlots or 0 do
        bill.expenses[#bill.expenses + 1] = {
            name = tostring(expense["zhuangbei" .. slot] or ""), amount = expense["jine" .. slot],
        }
    end
    local summary = tableData["boss" .. (bosses + 2)] or {}
    bill.splitCount = summary.jine4
    return bill
end

function M.acceptRisk(pending)
    if type(pending) ~= "table" or pending.accepted == true then return false end
    local frame, button = pending.frame, pending.button
    if not isObject(frame) or frame.IsEnd == true or frame.isPaused == true
        or button ~= frame.ButtonSendMyMoney
        or pending.featureEnabled() ~= true then return false end
    local remaining = tonumber(frame.remaining)
    if remaining and remaining <= 1 then return false end
    local offered = frame.myMoneyEdit and tonumber(frame.myMoneyEdit:GetText()) or nil
    if tonumber(frame.money) ~= pending.current or offered ~= pending.offered then return false end
    if type(button.IsEnabled) == "function" and not button:IsEnabled() then return false end
    pending.accepted = true
    pending.original(button)
    return true
end

function M.wrapBidButton(frame, deps)
    deps = deps or {}
    if not isObject(frame) or not isObject(frame.ButtonSendMyMoney) or frame._BGNextRiskWrapped then return false end
    local button = frame.ButtonSendMyMoney
    local original = type(button.GetScript) == "function" and button:GetScript("OnClick") or nil
    if type(original) ~= "function" or type(button.SetScript) ~= "function" then return false end
    local enabled = deps.featureEnabled or function() return featureEnabled("auction_center") end
    local confirm = deps.confirm or M.confirmRisk
    button:SetScript("OnClick", function(self)
        local current = tonumber(frame.money)
        local offered = frame.myMoneyEdit and tonumber(frame.myMoneyEdit:GetText()) or nil
        if enabled() and View.isRiskyBid(current, offered) then
            confirm({ frame = frame, button = self, current = current, offered = offered,
                original = original, featureEnabled = enabled })
            return
        end
        return original(self)
    end)
    frame._BGNextRiskWrapped = true
    local edit = frame.myMoneyEdit
    if isObject(edit) and type(edit.GetScript) == "function" and type(edit.SetScript) == "function" then
        local originalEnter = edit:GetScript("OnEnterPressed")
        if type(originalEnter) == "function" then
            edit:SetScript("OnEnterPressed", function(self)
                local current, offered = tonumber(frame.money), tonumber(self:GetText())
                if enabled() and View.isRiskyBid(current, offered) then
                    confirm({ frame = frame, button = button, current = current, offered = offered,
                        original = function() originalEnter(self) end, featureEnabled = enabled })
                    return
                end
                return originalEnter(self)
            end)
        end
    end
    return true
end

function M.confirmRisk(pending)
    if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then return false end
    local key = "BGNextRiskyBid"
    if not StaticPopupDialogs[key] then
        StaticPopupDialogs[key] = {
            text = L["这次出价为 %s 金，明显高于当前 %s 金。确定继续吗？"],
            button1 = YES, button2 = NO, timeout = 0, whileDead = true,
            hideOnEscape = true, showAlert = true,
            OnAccept = function(_, data) M.acceptRisk(data) end,
        }
    end
    StaticPopup_Show(key, tostring(pending.offered), tostring(pending.current), pending)
    return true
end

function M.currentContext()
    local fb = BG.FB1
    local bosses = type(fb) == "string" and tonumber(Maxb[fb]) or nil
    if not fb or not bosses or type(BiaoGe) ~= "table" or type(BiaoGe[fb]) ~= "table" then return nil end
    local slots = tonumber(safeCall(BG.GetMaxi, fb, bosses + 1)) or 0
    return {
        root = BG.BGNext.DB, fb = fb, table = BiaoGe[fb], frames = BG.Frame and BG.Frame[fb],
        bosses = bosses, expenseBoss = bosses + 1,
        slots = slots,
        slotsOf = BG.GetMaxi,
        itemIdOf = ns and ns.GetItemID,
        now = type(GetServerTime) == "function" and GetServerTime() or time(),
    }
end

function M.captureCurrentHistory()
    local context = M.currentContext()
    if not context or not featureEnabled("local_history") then return 0 end
    local myName = type(UnitName) == "function" and UnitName("player") or nil
    local realm = type(GetRealmName) == "function" and GetRealmName() or nil
    local identity = BG.BGNext.PlayerIdentity
    context.enabled = true
    context.isMine = function(buyer)
        return identity and type(identity.same) == "function" and identity.same(buyer, myName, realm) or buyer == myName
    end
    return M.captureHistory(context)
end

function M.currentSettlementSummary()
    local context = M.currentContext()
    if not context then return View.settlementSummary(nil, nil) end
    local bill = M.collectBill(context)
    local settlement = context.root and context.root.currentSettlement
    return View.settlementSummary(bill, settlement)
end

function M.currentSettlementState()
    local context = M.currentContext()
    if not context then
        local bill, settlement = {}, {}
        return { summary = View.settlementSummary(bill, settlement),
            fingerprint = View.settlementFingerprint(bill, settlement) }
    end
    local bill = M.collectBill(context)
    local settlement = context.root and context.root.currentSettlement or {}
    return { summary = View.settlementSummary(bill, settlement),
        fingerprint = View.settlementFingerprint(bill, settlement) }
end

function M.currentAuctions(filter)
    local frames = type(BGA) == "table" and BGA.Frames or {}
    local wa = type(BGA) == "table" and BGA.aura_env or nil
    return View.projectAuctions(frames, filter, function(frame)
        return wa and type(wa.IsMe) == "function" and wa.IsMe(frame) or false
    end)
end

local installed = false
function M.install()
    if installed then return end
    installed = true
    if type(BG.HookCreateAuction) == "function" then
        local previous = BG.HookCreateAuction
        BG.HookCreateAuction = function(frame)
            if previous then previous(frame) end
            M.wrapBidButton(frame)
        end
    end
    Store.ensure(BG.BGNext.DB or {})
end

if type(BG.Init) == "function" then BG.Init(M.install) end

BG.BGNext.LeaderToolsRuntime = M
return M
