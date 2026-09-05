local _, ns = ...

BG = BG or {}
BG.BGNext = BG.BGNext or {}

local L = ns and ns.L or setmetatable({}, { __index = function(_, key) return tostring(key) end })
local M = {}
local Store = assert(BG.BGNext.LeaderToolsStore, "LeaderToolsStore must load first")
local Runtime = assert(BG.BGNext.LeaderToolsRuntime, "LeaderToolsRuntime must load first")

local state = { frame = nil, entry = nil, tab = nil, selectedTemplate = nil, auctionFilter = "all", elapsed = 0 }
local TAB_FEATURE = {
    templates = "expense_templates", history = "local_history",
    auctions = "auction_center", settlement = "settlement_summary",
}

local function enabled(id)
    local settings = BG.BGNext.FeatureSettings
    return not settings or type(settings.isCurrentEnabled) ~= "function"
        or settings.isCurrentEnabled(id, BG, BG.BGNext.DB)
end

local function anyEnabled()
    for _, id in pairs(TAB_FEATURE) do if enabled(id) then return true end end
    return false
end

local function button(parent, label, width)
    local result = BG.CreateButton(parent)
    result:SetSize(width or 90, 24)
    result:SetText(L[label])
    return result
end

local function edit(parent, width, height, multiline)
    local result = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    result:SetSize(width, height)
    result:SetAutoFocus(false)
    if multiline then
        result:SetMultiLine(true)
        result:SetMaxLetters(8000)
        result:SetTextInsets(8, 8, 8, 8)
    end
    return result
end

local function confirm(key, message, onAccept)
    if type(StaticPopupDialogs) ~= "table" or type(StaticPopup_Show) ~= "function" then return false end
    StaticPopupDialogs[key] = {
        text = message, button1 = YES, button2 = NO, timeout = 0, whileDead = true,
        hideOnEscape = true, showAlert = true,
        OnAccept = function() onAccept() end,
    }
    StaticPopup_Show(key)
    return true
end

local function setStatus(panel, value, bad)
    panel.status:SetText(value or "")
    panel.status:SetTextColor(bad and 1 or 0.3, bad and 0.3 or 1, 0.3)
end

local function parseTemplate(panel)
    local items = {}
    for line in (panel.body:GetText() .. "\n"):gmatch("(.-)\r?\n") do
        if line:find("%S") then
            local itemName, amount = line:match("^%s*(.-)%s*=%s*(%d+)%s*$")
            if not itemName then return nil end
            items[#items + 1] = { name = itemName, amount = tonumber(amount) }
        end
    end
    return { name = panel.name:GetText(), items = items }
end

local function templateBody(template)
    local lines = {}
    for _, item in ipairs(template and template.items or {}) do
        lines[#lines + 1] = item.name .. "=" .. tostring(item.amount)
    end
    return table.concat(lines, "\n")
end

local function refreshTemplates(panel)
    local templates = Store.listTemplates(BG.BGNext.DB)
    for index, row in ipairs(panel.templateRows) do row:SetShown(templates[index] ~= nil) end
    for index, template in ipairs(templates) do
        local row = panel.templateRows[index]
        if not row then
            row = button(panel, "", 170)
            row:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -42 - (index - 1) * 27)
            panel.templateRows[index] = row
        end
        row:SetText(template.name)
        row:SetShown(true)
        row:SetScript("OnClick", function()
            state.selectedTemplate = index
            panel.name:SetText(template.name)
            panel.body:SetText(templateBody(template))
            setStatus(panel, L["已载入模板："] .. template.name)
        end)
    end
end

local function buildTemplates(parent)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetAllPoints()
    panel.templateRows = {}
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hint:SetPoint("TOPLEFT", 205, -10)
    hint:SetText(L["每行填写：项目=金额（金币整数）"])
    panel.name = edit(panel, 310, 24)
    panel.name:SetPoint("TOPLEFT", 205, -38)
    panel.body = edit(panel, 430, 240, true)
    panel.body:SetPoint("TOPLEFT", 205, -72)
    panel.body:SetJustifyH("LEFT")
    panel.body:SetJustifyV("TOP")
    panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.status:SetPoint("TOPLEFT", 205, -320)
    panel.status:SetWidth(430)
    panel.status:SetJustifyH("LEFT")

    local new = button(panel, "新建", 68)
    new:SetPoint("TOPLEFT", 205, -350)
    new:SetScript("OnClick", function()
        state.selectedTemplate = nil
        panel.name:SetText("") panel.body:SetText("") setStatus(panel, L["请输入新模板。"])
    end)
    local save = button(panel, "保存", 68)
    save:SetPoint("LEFT", new, "RIGHT", 6, 0)
    save:SetScript("OnClick", function()
        local candidate = parseTemplate(panel)
        if not candidate then setStatus(panel, L["格式无效，请按“项目=金额”逐行填写。"], true) return end
        confirm("BGNextSaveExpenseTemplate", L["确定保存此支出模板吗？"], function()
            local ok, reason
            if state.selectedTemplate then ok, reason = Store.replaceTemplate(BG.BGNext.DB, state.selectedTemplate, candidate)
            else ok, reason = Store.upsertTemplate(BG.BGNext.DB, candidate, false) end
            if ok then refreshTemplates(panel) setStatus(panel, L["模板已保存。"])
            else setStatus(panel, L["模板保存失败："] .. tostring(reason), true) end
        end)
    end)
    local copy = button(panel, "复制", 68)
    copy:SetPoint("LEFT", save, "RIGHT", 6, 0)
    copy:SetScript("OnClick", function()
        if not state.selectedTemplate then return end
        local name = panel.name:GetText() .. L["（副本）"]
        confirm("BGNextCopyExpenseTemplate", L["确定复制此模板吗？"], function()
            local ok, reason = Store.copyTemplate(BG.BGNext.DB, state.selectedTemplate, name)
            if ok then refreshTemplates(panel) else setStatus(panel, tostring(reason), true) end
        end)
    end)
    local rename = button(panel, "重命名", 76)
    rename:SetPoint("LEFT", copy, "RIGHT", 6, 0)
    rename:SetScript("OnClick", function()
        if not state.selectedTemplate then return end
        confirm("BGNextRenameExpenseTemplate", L["确定重命名此模板吗？"], function()
            local ok, reason = Store.renameTemplate(BG.BGNext.DB, state.selectedTemplate, panel.name:GetText())
            if ok then refreshTemplates(panel) else setStatus(panel, tostring(reason), true) end
        end)
    end)
    local remove = button(panel, "删除", 68)
    remove:SetPoint("LEFT", rename, "RIGHT", 6, 0)
    remove:SetScript("OnClick", function()
        if not state.selectedTemplate then return end
        confirm("BGNextDeleteExpenseTemplate", L["确定删除此模板吗？此操作不可恢复。"], function()
            Store.deleteTemplate(BG.BGNext.DB, state.selectedTemplate, true)
            state.selectedTemplate = nil panel.name:SetText("") panel.body:SetText("") refreshTemplates(panel)
        end)
    end)
    local apply = button(panel, "预览并应用", 108)
    apply:SetPoint("TOPLEFT", new, "BOTTOMLEFT", 0, -10)
    apply:SetScript("OnClick", function()
        local templates = Store.listTemplates(BG.BGNext.DB)
        local template = templates[state.selectedTemplate or 0]
        local context = Runtime.currentContext()
        if not template or not context then setStatus(panel, L["请先选择模板并打开当前账表。"], true) return end
        local plan, reason = Store.planExpenseApply(template, Runtime.collectExpenseRows(context))
        if not plan then setStatus(panel, L["无法应用模板："] .. tostring(reason), true) return end
        local preview = { string.format(L["将向 %d 个空白支出行写入内容："], #plan) }
        for _, entry in ipairs(plan) do preview[#preview + 1] = string.format(L["第 %d 行：%s = %d G"], entry.row, entry.name, entry.amount) end
        preview[#preview + 1] = L["确定继续吗？"]
        confirm("BGNextApplyExpenseTemplate", table.concat(preview, "\n"), function()
            local ok, why = Runtime.applyExpenseTemplate(context, template)
            setStatus(panel, ok and L["模板已应用。"] or (L["应用失败："] .. tostring(why)), not ok)
        end)
    end)
    local export = button(panel, "导出", 68)
    export:SetPoint("LEFT", apply, "RIGHT", 8, 0)
    export:SetScript("OnClick", function() panel.body:SetText(Store.exportTemplates(BG.BGNext.DB)); panel.body:HighlightText() end)
    local import = button(panel, "预览导入", 88)
    import:SetPoint("LEFT", export, "RIGHT", 6, 0)
    import:SetScript("OnClick", function()
        local value = panel.body:GetText()
        local preview, reason = Store.previewImport(value)
        if not preview then setStatus(panel, L["导入内容无效："] .. tostring(reason), true) return end
        local names = {}
        for _, template in ipairs(preview) do names[#names + 1] = template.name .. " (" .. #template.items .. ")" end
        confirm("BGNextImportExpenseTemplate", string.format(L["将用导入内容替换现有 %d 套模板："], #preview)
            .. "\n" .. table.concat(names, "\n") .. "\n" .. L["确定继续吗？"], function()
            Store.importTemplates(BG.BGNext.DB, value, true)
            state.selectedTemplate = nil refreshTemplates(panel) setStatus(panel, L["导入完成。"])
        end)
    end)
    local clear = button(panel, "清空模板", 88)
    clear:SetPoint("LEFT", import, "RIGHT", 6, 0)
    clear:SetScript("OnClick", function()
        confirm("BGNextClearExpenseTemplates", L["确定清空全部支出模板吗？此操作不可恢复。"], function()
            Store.clearTemplates(BG.BGNext.DB, true)
            state.selectedTemplate = nil panel.name:SetText("") panel.body:SetText("") refreshTemplates(panel)
        end)
    end)
    panel.refresh = function() refreshTemplates(panel) end
    return panel
end

local function historyExport(root)
    local lines = { "BGNext local history summary" }
    for _, entry in ipairs(root.leaderTools and root.leaderTools.localHistory or {}) do
        lines[#lines + 1] = table.concat({ tostring(entry.time), entry.sourceFb, entry.itemId, entry.amount, entry.mine and "self" or "other" }, "\t")
    end
    return table.concat(lines, "\n")
end

local function buildHistory(parent)
    local panel = CreateFrame("Frame", nil, parent) panel:SetAllPoints()
    panel.summary = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.summary:SetPoint("TOPLEFT", 18, -20) panel.summary:SetJustifyH("LEFT")
    panel.search = edit(panel, 440, 24) panel.search:SetPoint("TOPLEFT", 18, -52)
    panel.search:SetText("")
    local search = button(panel, "筛选", 80) search:SetPoint("LEFT", panel.search, "RIGHT", 8, 0)
    panel.body = edit(panel, 610, 240, true) panel.body:SetPoint("TOPLEFT", 18, -88)
    panel.body:SetJustifyH("LEFT") panel.body:SetJustifyV("TOP")
    local save = button(panel, "保存当前成交摘要", 150) save:SetPoint("BOTTOMLEFT", 18, 18)
    save:SetScript("OnClick", function()
        confirm("BGNextCaptureLocalHistory", L["只保存物品、金额、副本、时间和“是否本人”，确定吗？"], function()
            local count = Runtime.captureCurrentHistory() panel.refresh()
            panel.body:SetText(string.format(L["本次新增 %d 条摘要。"], count))
        end)
    end)
    panel.retention = button(panel, "", 120) panel.retention:SetPoint("LEFT", save, "RIGHT", 8, 0)
    panel.retention:SetScript("OnClick", function()
        local days = BG.BGNext.DB.leaderTools.historyRetentionDays
        Store.setHistoryRetention(BG.BGNext.DB, days == 30 and 90 or days == 90 and 180 or 30, time()) panel.refresh()
    end)
    local export = button(panel, "导出摘要", 100) export:SetPoint("LEFT", panel.retention, "RIGHT", 8, 0)
    export:SetScript("OnClick", function() panel.body:SetText(historyExport(BG.BGNext.DB)); panel.body:HighlightText() end)
    local clear = button(panel, "清空摘要", 100) clear:SetPoint("LEFT", export, "RIGHT", 8, 0)
    clear:SetScript("OnClick", function()
        confirm("BGNextClearLocalHistory", L["确定清空全部本地成交摘要吗？此操作不可恢复。"], function()
            Store.clearHistory(BG.BGNext.DB, true) panel.refresh()
        end)
    end)
    panel.refresh = function()
        local summary = Store.summarizeHistory(BG.BGNext.DB, time())
        panel.summary:SetText(string.format(L["共 %d 条；本人消费 %d 金；保留 %d 天"], summary.count, summary.mineTotal, summary.retentionDays))
        panel.retention:SetText(string.format(L["保留 %d 天"], summary.retentionDays))
        local query = string.lower(panel.search:GetText() or "")
        local lines = {}
        for _, entry in ipairs(BG.BGNext.DB.leaderTools.localHistory or {}) do
            local itemName = type(GetItemInfo) == "function" and GetItemInfo(entry.itemId) or nil
            local day = type(date) == "function" and date("%Y-%m-%d", math.floor(entry.time)) or tostring(math.floor(entry.time))
            local haystack = string.lower(table.concat({ entry.sourceFb, tostring(entry.itemId), itemName or "", day }, " "))
            if query == "" or haystack:find(query, 1, true) then
                lines[#lines + 1] = string.format("%s  %s  %s  %d G  %s", day, entry.sourceFb,
                    itemName or ("item:" .. entry.itemId), entry.amount, entry.mine and L["本人"] or "")
            end
        end
        panel.body:SetText(#lines > 0 and table.concat(lines, "\n") or L["没有符合条件的摘要。"])
    end
    search:SetScript("OnClick", panel.refresh)
    return panel
end

local function buildAuctions(parent)
    local panel = CreateFrame("Frame", nil, parent) panel:SetAllPoints() panel.rows = {}
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPRIGHT", -18, -21)
    hint:SetText(L["手动出价同时达到当前价 10 倍且多出至少 1000G 时会再次确认。"])
    local previous
    for _, spec in ipairs({ { "all", "全部" }, { "mine", "我参与的" }, { "urgent", "即将结束" } }) do
        local filter = button(panel, spec[2], 90)
        if previous then filter:SetPoint("LEFT", previous, "RIGHT", 8, 0) else filter:SetPoint("TOPLEFT", 18, -15) end
        filter:SetScript("OnClick", function() state.auctionFilter = spec[1] panel.refresh() end)
        previous = filter
    end
    panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.empty:SetPoint("CENTER") panel.empty:SetText(L["当前没有符合条件的拍品。"])
    panel.refresh = function()
        local auctions = Runtime.currentAuctions(state.auctionFilter)
        panel.empty:SetShown(#auctions == 0)
        for index = 1, 20 do
            local row = panel.rows[index]
            if not row then
                row = button(panel, "", 610) row:SetHeight(28)
                row:SetPoint("TOPLEFT", 18, -55 - (index - 1) * 30)
                panel.rows[index] = row
            end
            local auction = auctions[index]
            row:SetShown(auction ~= nil)
            if auction then
                local status = auction.ended and L["已结束"] or auction.paused and L["已暂停"]
                    or auction.mine and L["领先"] or auction.urgent and L["紧急"] or L["进行中"]
                row:SetText(string.format("%s  |  %s G  |  %s  |  %s", auction.link or ("item:" .. tostring(auction.itemId)),
                    tostring(auction.amount or "?"), tostring(auction.remaining or "?"), status))
                row:SetScript("OnClick", function()
                    if BGA and BGA.AuctionMainFrame then BGA.AuctionMainFrame:Show() end
                    if auction.source.updateFrame and auction.source.updateFrame.Show then auction.source.updateFrame:Show() end
                end)
            end
        end
    end
    return panel
end

local function buildSettlement(parent)
    local panel = CreateFrame("Frame", nil, parent) panel:SetAllPoints()
    panel.text = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    panel.text:SetPoint("TOPLEFT", 28, -35) panel.text:SetWidth(590) panel.text:SetJustifyH("LEFT")
    panel.confirm = button(panel, "确认当前摘要", 130)
    panel.confirm:SetPoint("BOTTOMLEFT", 28, 25)
    panel.confirm:SetScript("OnClick", function()
        local current = Runtime.currentSettlementState()
        confirm("BGNextConfirmSettlementSummary", L["确认只会冻结本地核对标记，不会交易、邮寄、通报或清空。确定吗？"], function()
            -- Re-read on accept; a change while the popup is open must not be
            -- confirmed under the old facts.
            local fresh = Runtime.currentSettlementState()
            panel.confirmedFingerprint = fresh.fingerprint == current.fingerprint and fresh.fingerprint or nil
            panel.refresh()
        end)
    end)
    panel.refresh = function()
        local current = Runtime.currentSettlementState()
        local s = current.summary
        if panel.confirmedFingerprint and panel.confirmedFingerprint ~= current.fingerprint then
            panel.confirmedFingerprint = nil
        end
        local distributable = s.distributable and tostring(s.distributable) .. " G" or L["待核对"]
        local wage = s.wage and string.format("%.2f G", s.wage) or L["待核对"]
        panel.text:SetText(table.concat({
            string.format(L["账面收入：%d G"], s.ledgerIncome),
            string.format(L["已证实实收：%d G"], s.provenReceived),
            string.format(L["支出：%d G"], s.expenses),
            string.format(L["欠款：%d G"], s.debt),
            string.format(L["待核对事项：%d"], s.pendingCount),
            L["可分净额："] .. distributable,
            L["人均工资："] .. wage,
            "", panel.confirmedFingerprint and L["状态：已确认；账表或交易变化后会自动失效。"]
                or L["状态：待确认或已因数据变化失效。"],
            L["这里只显示只读预览，不会自动交易、邮寄、通报或清空。"],
        }, "\n\n"))
    end
    return panel
end

local function firstEnabledTab()
    for _, tab in ipairs({ "templates", "history", "auctions", "settlement" }) do
        if enabled(TAB_FEATURE[tab]) then return tab end
    end
end

function M.setTab(tab)
    if not state.frame or not enabled(TAB_FEATURE[tab]) then return false end
    state.tab = tab
    for id, panel in pairs(state.frame.panels) do panel:SetShown(id == tab) end
    local panel = state.frame.panels[tab]
    if panel and panel.refresh then panel.refresh() end
    state.frame:SetScript("OnUpdate", tab == "auctions" and function(_, elapsed)
        state.elapsed = state.elapsed + elapsed
        if state.elapsed >= 0.25 then state.elapsed = 0 panel.refresh() end
    end or nil)
    return true
end

function M.buildWindow()
    if state.frame then return state.frame end
    if type(CreateFrame) ~= "function" or type(BG.CreateButton) ~= "function" then return nil end
    local frame = CreateFrame("Frame", "BGNextLeaderToolsFrame", UIParent, "BackdropTemplate")
    frame:SetSize(680, 470) frame:SetPoint("CENTER") frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true) frame:EnableMouse(true) frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton") frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({ bgFile = "Interface/ChatFrame/ChatFrameBackground", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 14 })
    frame:SetBackdropColor(0.02, 0.05, 0.08, 0.96)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14) title:SetText(L["团长工具"])
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton") close:SetPoint("TOPRIGHT", -3, -3)
    local content = CreateFrame("Frame", nil, frame) content:SetPoint("TOPLEFT", 10, -68) content:SetPoint("BOTTOMRIGHT", -10, 10)
    frame.panels = {
        templates = buildTemplates(content), history = buildHistory(content),
        auctions = buildAuctions(content), settlement = buildSettlement(content),
    }
    local previous
    for _, spec in ipairs({ { "templates", "支出模板" }, { "history", "成交摘要" }, { "auctions", "拍卖中心" }, { "settlement", "实收与分金" } }) do
        local tab = button(frame, spec[2], 112)
        if previous then tab:SetPoint("LEFT", previous, "RIGHT", 6, 0) else tab:SetPoint("TOPLEFT", 16, -38) end
        tab:SetScript("OnClick", function() M.setTab(spec[1]) end)
        frame.panels[spec[1]].tabButton = tab previous = tab
    end
    frame:Hide() state.frame = frame
    return frame
end

function M.toggle()
    if not anyEnabled() then return false end
    local frame = M.buildWindow() if not frame then return false end
    if frame:IsShown() then frame:Hide() frame:SetScript("OnUpdate", nil)
    else frame:Show() M.setTab(enabled(TAB_FEATURE[state.tab]) and state.tab or firstEnabledTab()) end
    return true
end

function M.installEntry(mainFrame)
    if state.entry then return state.entry end
    if (type(mainFrame) ~= "table" and type(mainFrame) ~= "userdata") or type(BG.CreateButton) ~= "function" then return nil end
    local entry = button(mainFrame, "团长工具", 100)
    local anchor = BG.ButtonAuctionQueue or BG.ButtonCurrentTradeRecord or BG.ButtonRoleOverview
    if anchor then entry:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
    else entry:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -10, 8) end
    entry:SetScript("OnClick", M.toggle) state.entry = entry
    M.refreshFeatureState()
    return entry
end

function M.refreshFeatureState()
    local show = anyEnabled()
    if state.entry then state.entry:SetShown(show) end
    if state.frame then
        for tab, panel in pairs(state.frame.panels) do panel.tabButton:SetShown(enabled(TAB_FEATURE[tab])) end
        if not enabled("settlement_summary") then state.frame.panels.settlement.confirmedFingerprint = nil end
        if not show then state.frame:Hide() state.frame:SetScript("OnUpdate", nil)
        elseif state.frame:IsShown() and not enabled(TAB_FEATURE[state.tab]) then M.setTab(firstEnabledTab()) end
    end
    return show
end

if type(BG.Init2) == "function" then BG.Init2(function()
    if type(BG.MainFrame) == "table" then M.installEntry(BG.MainFrame) end
end) end

BG.BGNext.LeaderToolsUI = M
return M
