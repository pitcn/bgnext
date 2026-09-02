local function readAll(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

local function keys(columns)
    local list = {}
    for index, column in ipairs(columns) do
        list[index] = column.key
    end
    return table.concat(list, ",")
end

return function(test)
    BG = { BGNext = {} }
    local life = dofile("Core/BGNext/DataLifecycle.lua")
    local trade = dofile("Core/BGNext/CurrentTrade.lua")
    local mail = dofile("Core/BGNext/CurrentMail.lua")
    dofile("Core/BGNext/CurrentSettlementView.lua")
    local ui = dofile("Core/BGNext/CurrentSettlementUI.lua")

    local function stubDate(_, t)
        return "t" .. tostring(t)
    end

    -- 1. the tables keep the familiar column order and are clearly scoped
    test.eq(keys(ui.columns("trade")), "item,player,amount,time,status", "trade column order")
    test.eq(keys(ui.columns("mail")), "item,player,amount,time,direction,status", "mail column order")
    test.eq(ui.title("trade"), "交易记录（当前团）", "trade window title names the current raid scope")
    test.eq(ui.title("mail"), "邮件记录（当前团）", "mail window title names the current raid scope")

    -- 2. empty state
    local saved = {
        tradeHistory = { { player = "历史买家" } },
        mailHistory = { { player = "历史收件人" } },
        History = { ["raid-old"] = true },
        ICC = { auctionLog = { { maijia = "我" } } },
        options = { autoTrade = 1 },
    }
    local root = life.ensureRoot(saved)
    local rows, isEmpty = ui.rows(root, "trade", { now = 1000, dateFn = stubDate })
    test.eq(#rows, 0, "no trade rows in a fresh settlement")
    test.eq(isEmpty, true, "trade table reports the empty state")
    test.eq(type(ui.emptyText("trade")), "string", "trade empty state has text")
    test.eq(ui.emptyText("trade") ~= ui.emptyText("mail"), true, "each table has its own empty state text")

    -- 3. rows come only from the current settlement
    life.beginSettlement(root, "raid-a", 1000)
    test.eq(trade.append(root, {
        raidId = "raid-a", player = "甲", itemId = 11, amount = 100, time = 1100, status = "complete",
    }), true, "trade stored")
    test.eq(mail.append(root, {
        raidId = "raid-a", player = "乙", amount = 200, time = 1200, status = "sent", direction = "outgoing",
    }), true, "mail stored")

    rows, isEmpty = ui.rows(root, "trade", { now = 1300, dateFn = stubDate })
    test.eq(isEmpty, false, "trade table is populated")
    test.eq(#rows, 1, "only the settlement trade is listed")
    test.eq(rows[1].player, "甲", "trade row shows the counterparty")
    test.eq(rows[1].amountText, "100", "trade row shows the amount")
    test.eq(rows[1].timeText, "t1100", "trade row shows the time")

    local mailRows = ui.rows(root, "mail", { now = 1300, dateFn = stubDate })
    test.eq(#mailRows, 1, "only the settlement mail is listed")
    test.eq(mailRows[1].player, "乙", "mail row shows the counterparty")
    test.eq(mailRows[1].subject, nil, "mail row exposes no subject")
    test.eq(mailRows[1].body, nil, "mail row exposes no body")

    -- 4. status and direction are presented with distinct labels and colours
    test.eq(ui.statusLabel("trade", "complete") ~= ui.statusLabel("trade", "pending"), true,
        "success and pending are distinguishable")
    test.eq(ui.statusLabel("trade", "cancelled") ~= ui.statusLabel("trade", "failed"), true,
        "cancelled and failed are distinguishable")
    test.eq(type(ui.statusLabel("mail", "sent")), "string", "mail sent status has a label")
    test.eq(ui.directionLabel("outgoing") ~= ui.directionLabel("incoming"), true,
        "mail directions are distinguishable")
    local r, g, b = ui.statusColor("trade", "complete")
    test.eq(r == 0 and g == 1 and b == 0, true, "success is green in the table")
    r, g, b = ui.statusColor("trade", "pending")
    test.eq(r == 1 and b == 0, true, "pending is gold in the table")
    r, g, b = ui.statusColor("trade", "failed")
    test.eq(r == 1 and g == 0 and b == 0, true, "failure is red in the table")

    -- 5. the tooltip is driven by the stored item id, nothing else
    test.eq(ui.tooltipTarget({ itemId = 11 }), 11, "tooltip uses the stored item id")
    test.eq(ui.tooltipTarget({ itemId = "11" }), nil, "tooltip refuses a non-numeric item id")
    test.eq(ui.tooltipTarget({}), nil, "a row without an item has no tooltip")

    -- 6. filtering and reconciliation are explicit, local and reversible.
    test.eq(#ui.filterRows(rows, "all"), 1, "all filter keeps every row")
    test.eq(#ui.filterRows(rows, "pending"), 0, "pending filter excludes completed rows")
    test.eq(#ui.filterRows(rows, "complete"), 1, "complete filter keeps completed rows")
    test.eq(ui.setTradeStatus(root, rows[1].index, "pending"), true,
        "a completed row can be returned to pending")
    rows = ui.rows(root, "trade", { now = 1300, dateFn = stubDate })
    test.eq(rows[1].statusKey, "pending", "reconciliation status change is visible")
    test.eq(ui.setTradeStatus(root, rows[1].index, "complete"), true,
        "a pending row can be marked complete")
    test.eq(ui.setTradeStatus(root, rows[1].index, "failed"), false,
        "the reconciliation action cannot invent failure states")
    test.eq(ui.scrollOuterWidth("trade") - ui.contentWidth("trade"), 31,
        "scroll frame reserves the helper's scrollbar inset without clipping rows")

    -- 7. clearing removes the settlement only
    test.eq(type(ui.clearConfirmText()), "string", "clearing asks for confirmation")
    test.eq(ui.clear(root), true, "clear reported success")
    test.eq(root.currentSettlement.raidId, nil, "settlement identity cleared")
    test.eq(#root.currentSettlement.trades, 0, "settlement trades cleared")
    test.eq(#root.currentSettlement.mails, 0, "settlement mails cleared")
    -- everything else survives
    test.eq(saved.ICC.auctionLog[1].maijia, "我", "the current bill and purchase log survive")
    test.eq(saved.options.autoTrade, 1, "BGLite options survive")
    test.eq(saved.tradeHistory ~= nil, true, "untouched legacy data is not deleted")
    test.eq(saved.mailHistory ~= nil, true, "untouched legacy mail data is not deleted")
    test.eq(saved.History ~= nil, true, "untouched legacy raid data is not deleted")
    test.eq(root.wishlist ~= nil, true, "wishlist survives")
    test.eq(root.equipmentFilters ~= nil, true, "equipment filters survive")
    test.eq(root.ownCharacters ~= nil, true, "own-character overview survives")
    test.eq(root.auctionPresets, nil, "no auto-bid presets are created")
    test.eq(root.settings ~= nil, true, "settings survive")

    -- 8. an expired settlement is purged before the table is shown
    life.beginSettlement(root, "raid-b", 2000)
    test.eq(trade.append(root, {
        raidId = "raid-b", player = "丙", itemId = 22, amount = 300, time = 2100, status = "complete",
    }), true, "second settlement trade stored")
    test.eq(ui.prepare(root, 2000 + 7 * 86400), true, "opening the page purges an expired settlement")
    test.eq(root.currentSettlement.raidId, nil, "expired settlement identity removed")
    rows, isEmpty = ui.rows(root, "trade", { now = 2000 + 7 * 86400, dateFn = stubDate })
    test.eq(#rows, 0, "no expired rows are displayed")
    test.eq(isEmpty, true, "expired settlement shows the empty state")

    -- 9. defence in depth on the source
    local source = readAll("Core/BGNext/CurrentSettlementUI.lua")
    for _, forbidden in ipairs({
        "SendAddonMessage", "SendChatMessage", "NotifyInspect",
        "COMBAT_LOG_EVENT_UNFILTERED", "tradeHistory", "mailHistory",
        "BiaoGe.History", "GetInboxText",
    }) do
        test.eq(source:find(forbidden, 1, true), nil, "settlement UI never references " .. forbidden)
    end
    test.eq(source:find("交易记录（当前团）", 1, true) ~= nil, true, "trade window is explicitly labelled")
    test.eq(source:find("邮件记录（当前团）", 1, true) ~= nil, true, "mail window is explicitly labelled")
    test.eq(source:find("StaticPopup_Show", 1, true) ~= nil, true, "clearing goes through a confirmation popup")
    test.eq(source:find("C_Timer", 1, true), nil, "settlement UI adds no timer")
    test.eq(source:find("OnUpdate", 1, true), nil, "settlement UI adds no per-frame handler")

    -- 10. the settlement checklist window: refresh, locate and cleanup run on
    --     real frames (mocked), and every swapped global comes back
    local watchedGlobals = { "BG", "CreateFrame", "BIAOGE_TEXT_FONT", "GetServerTime", "BiaoGe" }
    local originalValues = {}
    for _, name in ipairs(watchedGlobals) do
        originalValues[name] = rawget(_G, name)
    end
    local function setGlobal(name, value)
        rawset(_G, name, value)
    end

    local checklistOk, checklistErr = pcall(function()
        BG = { BGNext = {} }
        local checklistLife = dofile("Core/BGNext/DataLifecycle.lua")
        local checklistTrade = dofile("Core/BGNext/CurrentTrade.lua")
        dofile("Core/BGNext/CurrentMail.lua")
        dofile("Core/BGNext/CurrentSettlementView.lua")
        dofile("Core/BGNext/CurrentSettlementChecklist.lua")

        local function makeFrame()
            local frame = {
                points = {}, scripts = {}, children = {},
                text = "", shown = true, width = 0, height = 0,
            }
            function frame:SetPoint(point, relative, relativePoint)
                self.points[#self.points + 1] = { point = point, relative = relative, relativePoint = relativePoint }
            end
            function frame:SetSize(width, height) self.width, self.height = width, height end
            function frame:SetWidth(width) self.width = width end
            function frame:SetHeight(height) self.height = height end
            function frame:SetScript(name, handler) self.scripts[name] = handler end
            function frame:SetText(value) self.text = value end
            function frame:GetText() return self.text end
            function frame:SetTextColor() end
            function frame:SetFont() end
            function frame:SetJustifyH() end
            function frame:SetWordWrap() end
            function frame:SetAllPoints() end
            function frame:ClearAllPoints() self.points = {} end
            function frame:SetColorTexture() end
            function frame:SetTexture() end
            function frame:SetShown(value) self.shown = value and true or false end
            function frame:Show() self.shown = true end
            function frame:Hide()
                self.shown = false
                if self.scripts.OnHide then self.scripts.OnHide(self) end
            end
            function frame:IsShown() return self.shown end
            function frame:EnableMouse() end
            function frame:SetFrameLevel() end
            function frame:SetCursorPosition() end
            function frame:CreateFontString()
                local label = makeFrame()
                self.children[#self.children + 1] = label
                return label
            end
            function frame:CreateTexture()
                local texture = makeFrame()
                self.children[#self.children + 1] = texture
                return texture
            end
            return frame
        end

        setGlobal("CreateFrame", function(_, _, parent)
            local frame = makeFrame()
            if parent and parent.children then
                parent.children[#parent.children + 1] = frame
            end
            return frame
        end)
        setGlobal("BIAOGE_TEXT_FONT", "Fonts\\FRIZQT__.TTF")
        local nowValue = 1000000
        setGlobal("GetServerTime", function() return nowValue end)
        local clickTargets = {}
        setGlobal("BiaoGe", {
            ICC = {
                boss1 = {
                    zhuangbei1 = "[装备一]", maijia1 = "买家甲", jine1 = "100",
                    zhuangbei2 = "[装备二]", maijia2 = "买家乙", jine2 = "", qiankuan2 = 300,
                },
                boss4 = { jine3 = "500", jine4 = "40" },
            },
        })

        BG.CreateMainFrame = function()
            local frame = makeFrame()
            frame.titleText = makeFrame()
            return frame
        end
        BG.CreateScrollFrame = function()
            return makeFrame(), makeFrame()
        end
        BG.CreateButton = function() return makeFrame() end
        BG.GetMaxi = function() return 2 end
        BG.ClickFBbutton = function(fb) clickTargets[#clickTargets + 1] = fb end

        BG.BGNext.DB = checklistLife.ensureRoot({})
        checklistLife.beginSettlement(BG.BGNext.DB, "ICC@123", nowValue, { fb = "ICC", realm = "realm" })
        checklistTrade.append(BG.BGNext.DB, {
            raidId = "ICC@123", player = "买家甲", itemId = 7001, amount = 100,
            time = nowValue, status = "pending",
        })

        local chunk = assert(loadfile("Core/BGNext/CurrentSettlementUI.lua"))
        local ui2 = chunk("BGNEXT", { Maxb = { ICC = 2 } })

        test.eq(ui2.Show("checklist"), true, "checklist window opens")
        local state = ui2.checklistState()
        test.eq(state.shown, true, "checklist window is shown")
        test.eq(state.report ~= nil, true, "opening computes the report")
        test.eq(state.report.status, "issues", "collected anomalies surface as issues")
        test.eq(state.report.issueCount, 3, "unconfirmed trade, debt and missing amount are counted")
        test.eq(#state.rows, state.report.total, "every entry gets a row")

        -- 10a. locate buttons perform real jumps only
        local clickedWindow, clickedTable = false, false
        for _, row in ipairs(state.rows) do
            local locate = row.entry.locate
            if locate and locate.type == "table" then
                row.locateButton.scripts.OnClick(row.locateButton)
                clickedTable = true
            elseif locate and locate.type == "window" then
                row.locateButton.scripts.OnClick(row.locateButton)
                clickedWindow = true
            end
        end
        test.eq(clickedWindow and clickedTable, true, "both locate kinds are offered")
        test.eq(clickTargets[1], "ICC", "table locate switches to the raid table")
        test.eq(ui2.windowState("trade").filter, "pending", "window locate applies the pending filter")

        -- 10b. record events refresh a visible checklist through the existing
        --      pipeline, with no extra scheduling
        ui2.setTradeStatus(BG.BGNext.DB, 1, "complete")
        ui2.Refresh("trade")
        state = ui2.checklistState()
        test.eq(state.report.issueCount, 2, "confirming the trade removes its finding on refresh")

        -- 10c. closing the window releases the derived report
        ui2.Toggle("checklist")
        state = ui2.checklistState()
        test.eq(state.shown, false, "checklist window closes")
        test.eq(state.report, nil, "closing releases the derived report")

        -- 10d. clearing the settlement reads as pending, never as ready
        ui2.Show("checklist")
        test.eq(ui2.checklistState().report.status, "issues", "report is recomputed on reopen")
        ui2.clear(BG.BGNext.DB)
        ui2.Refresh("checklist")
        state = ui2.checklistState()
        test.eq(state.report.status, "pending", "a cleared settlement stays pending")
        ui2.Toggle("checklist")
    end)

    for _, name in ipairs(watchedGlobals) do
        rawset(_G, name, originalValues[name])
    end
    for _, name in ipairs(watchedGlobals) do
        test.eq(rawget(_G, name), originalValues[name], "settlement UI suite restores global: " .. name)
    end
    if not checklistOk then
        error(checklistErr, 0)
    end
end
